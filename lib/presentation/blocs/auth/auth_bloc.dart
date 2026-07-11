import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/core/router/app_router.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/local/auth_local_datasource.dart';
import 'package:masjid_app/domain/entities/user.dart' as domain;
import 'package:masjid_app/domain/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum UserRole {
  admin,
  ketua,
  bendahara,
  sekretaris,
  viewer;

  bool get canManageTransactions => this == admin || this == bendahara;
  bool get canManageActivities => this == admin || this == sekretaris;
  bool get canManageSettings => this == admin || this == ketua;
  bool get canManageQurban =>
      this == admin || this == ketua || this == bendahara;
}

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class LoginRequested extends AuthEvent {
  final String identifier;
  final String password;
  const LoginRequested(this.identifier, this.password);
  @override
  List<Object?> get props => [identifier, password];
}

class RegisterRequested extends AuthEvent {
  final String name;
  final String email;
  final String username;
  final String password;
  final UserRole role;

  const RegisterRequested({
    required this.name,
    required this.email,
    required this.username,
    required this.password,
    this.role = UserRole.viewer,
  });

  @override
  List<Object?> get props => [name, email, username, password, role];
}

class LogoutRequested extends AuthEvent {}

class OfflineLoginRequested extends AuthEvent {}

class CheckAuthStatus extends AuthEvent {}

class UpdateProfileRequested extends AuthEvent {
  final String? fullName;
  final String? username;
  final String? email;
  final String? password;

  const UpdateProfileRequested({
    this.fullName,
    this.username,
    this.email,
    this.password,
  });

  @override
  List<Object?> get props => [fullName, username, email, password];
}

// States
abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class Authenticated extends AuthState {
  final User user;
  final UserRole role;
  const Authenticated(this.user, {this.role = UserRole.viewer});
  @override
  List<Object?> get props => [user, role];
}

class AuthOffline extends AuthState {
  final LocalUser user;

  UserRole get role => user.role;

  const AuthOffline(this.user);
  @override
  List<Object?> get props => [user];
}

class Unauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

class AuthSuccess extends AuthState {
  final String message;
  const AuthSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc

@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  SupabaseClient? _supabase;
  final AuthLocalDatasource _localDatasource;
  final UserRepository _userRepository;

  AuthBloc(this._localDatasource, AppDatabase _, this._userRepository)
    : super(AuthInitial()) {
    on<CheckAuthStatus>(_onCheckAuthStatus);
    on<LoginRequested>(_onLoginRequested);
    on<RegisterRequested>(_onRegisterRequested);
    on<UpdateProfileRequested>(_onUpdateProfileRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<OfflineLoginRequested>(_onOfflineLoginRequested);

    try {
      _supabase = Supabase.instance.client;
    } catch (_) {
      _supabase = null;
    }
  }

  Future<void> _onUpdateProfileRequested(
    UpdateProfileRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentState = state;
    if (currentState is! Authenticated && currentState is! AuthOffline) {
      emit(const AuthError('User tidak terautentikasi'));
      return;
    }

    emit(AuthLoading());

    String? userId;
    String? currentEmail;
    String? currentUsername;
    UserRole? currentRole;

    if (currentState is Authenticated) {
      userId = currentState.user.id;
      currentEmail = currentState.user.email;
      currentRole = currentState.role;
      currentUsername = currentState.user.userMetadata?['username'];
    } else if (currentState is AuthOffline) {
      userId = currentState.user.id;
      currentEmail = currentState.user.email;
      currentRole = currentState.role;
      currentUsername = currentState.user.username;
    }

    if (userId == null || currentEmail == null) {
      emit(const AuthError('Data user tidak valid'));
      return;
    }

    // Validate password strength if provided
    if (event.password != null && event.password!.isNotEmpty) {
      if (event.password!.length < 6) {
        emit(const AuthError('Password minimal 6 karakter'));
        add(CheckAuthStatus());
        return;
      }
    }

    // Normalize inputs
    final newEmail = event.email?.trim().toLowerCase();
    final newUsername = event.username?.trim().toLowerCase();
    final newFullName = event.fullName?.trim();

    // Validate inputs
    if (newEmail != null &&
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(newEmail)) {
      emit(const AuthError('Format email tidak valid'));
      add(CheckAuthStatus());
      return;
    }

    if (newUsername != null) {
      if (newUsername.length < 3) {
        emit(const AuthError('Username minimal 3 karakter'));
        add(CheckAuthStatus());
        return;
      }
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(newUsername)) {
        emit(
          const AuthError('Username hanya boleh huruf, angka, dan underscore'),
        );
        add(CheckAuthStatus());
        return;
      }
    }

    if (newFullName != null && newFullName.isEmpty) {
      emit(const AuthError('Nama lengkap tidak boleh kosong'));
      add(CheckAuthStatus());
      return;
    }

    // Get current user entity from database
    domain.UserEntity? currentUserEntity;
    try {
      currentUserEntity = await _userRepository.getUserByRemoteId(userId);
      if (currentUserEntity == null && currentUsername != null) {
        currentUserEntity = await _userRepository.getUserByUsername(
          currentUsername,
        );
      }
    } catch (e) {
      debugPrint('Error getting current user entity: $e');
    }

    // Validate email uniqueness
    if (newEmail != null && newEmail != currentEmail.toLowerCase()) {
      final emailExists = await _userRepository.getUserByEmail(newEmail);
      if (emailExists != null && emailExists.id != currentUserEntity?.id) {
        emit(const AuthError('Email sudah digunakan user lain'));
        add(CheckAuthStatus());
        return;
      }
    }

    // Validate username uniqueness
    if (newUsername != null &&
        (currentUsername == null ||
            newUsername != currentUsername.toLowerCase())) {
      final usernameExists = await _userRepository.getUserByUsername(
        newUsername,
      );
      if (usernameExists != null &&
          usernameExists.id != currentUserEntity?.id) {
        emit(const AuthError('Username sudah digunakan user lain'));
        add(CheckAuthStatus());
        return;
      }
    }

    // Track what needs to be updated

    // 1. Supabase Update (if online and authenticated)
    if (_supabase != null && currentState is Authenticated) {
      try {
        // Update auth user (email and password)
        final authUpdates = UserAttributes(
          email: newEmail != null && newEmail != currentEmail.toLowerCase()
              ? newEmail
              : null,
          password: event.password,
        );

        if (authUpdates.email != null || authUpdates.password != null) {
          await _supabase!.auth.updateUser(authUpdates);
        }

        // Update user metadata
        final metadataUpdates = <String, dynamic>{};
        if (newFullName != null) {
          metadataUpdates['full_name'] = newFullName;
        }
        if (newUsername != null) {
          metadataUpdates['username'] = newUsername;
        }

        if (metadataUpdates.isNotEmpty) {
          await _supabase!.auth.updateUser(
            UserAttributes(data: metadataUpdates),
          );
        }

        // Update profiles table
        final profileUpdates = <String, dynamic>{};
        if (newFullName != null) {
          profileUpdates['full_name'] = newFullName;
        }
        if (newUsername != null) {
          profileUpdates['username'] = newUsername;
        }
        if (newEmail != null) {
          profileUpdates['email'] = newEmail;
        }

        if (profileUpdates.isNotEmpty) {
          await _supabase!
              .from('profiles')
              .update(profileUpdates)
              .eq('id', userId);
        }
      } catch (e) {
        debugPrint('Supabase update failed: $e');

        // If online update fails, don't proceed with local update
        emit(AuthError('Gagal update profil online: ${e.toString()}'));
        add(CheckAuthStatus());
        return;
      }
    }

    // 2. Local DB Update (only if Supabase succeeded or offline)
    if (currentUserEntity != null) {
      try {
        // If the online push above actually ran (authenticated + live client),
        // the row is genuinely synced. If it was skipped because we're offline,
        // mark it pendingUpdate so the edit is replayed on reconnect instead of
        // being falsely marked synced and then overwritten on the next login.
        final didOnlinePush =
            _supabase != null && currentState is Authenticated;
        final updatedUser = currentUserEntity.copyWith(
          email: newEmail ?? currentUserEntity.email,
          username: newUsername ?? currentUserEntity.username,
          fullName: newFullName ?? currentUserEntity.fullName,
          syncStatus: didOnlinePush ? 0 : 2, // 0=synced, 2=pendingUpdate
        );
        await _userRepository.updateUser(updatedUser);
      } catch (e) {
        debugPrint('Error updating user in local DB: $e');
        emit(AuthError('Gagal update database lokal: ${e.toString()}'));
        add(CheckAuthStatus());
        return;
      }
    }

    // 3. Local Auth Datasource Update
    try {
      await _localDatasource.updateProfile(
        currentEmail: currentEmail,
        newEmail: newEmail,
        newUsername: newUsername,
        newFullName: newFullName,
        newPassword: event.password,
        role: currentRole.toString().split('.').last,
        userId: userId,
      );
    } catch (e) {
      debugPrint('Error updating local auth datasource: $e');
      emit(AuthError('Gagal update kredensial lokal: ${e.toString()}'));
      add(CheckAuthStatus());
      return;
    }

    emit(const AuthSuccess('Profil berhasil diperbarui'));
    add(CheckAuthStatus());
  }

  Future<void> _onRegisterRequested(
    RegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      User? user;
      final normalizedEmail = event.email.trim().toLowerCase();
      final normalizedUsername = event.username.trim().toLowerCase();

      final existingUsers = await _userRepository.getUsers();
      final emailExists = existingUsers.any(
        (u) => u.email.toLowerCase() == normalizedEmail,
      );
      final usernameExists = existingUsers.any(
        (u) => (u.username ?? '').toLowerCase() == normalizedUsername,
      );
      if (emailExists || usernameExists) {
        emit(
          AuthError(
            emailExists ? 'Email sudah terdaftar' : 'Username sudah terdaftar',
          ),
        );
        return;
      }
      // 1. Try Supabase Registration (if online/configured)
      if (_supabase != null) {
        try {
          final response = await _supabase!.auth.signUp(
            email: normalizedEmail,
            password: event.password,
            data: {
              'full_name': event.name,
              'username': normalizedUsername,
              // NOTE: role is intentionally NOT sent here. The server-side
              // handle_new_user() trigger always assigns 'viewer' and
              // ignores any client-supplied role -- trusting it was a
              // privilege-escalation hole (anyone could sign up as admin).
            },
          );
          user = response.user;

          // With Supabase "Confirm email" enabled, signUp returns a user but no
          // session. Keying success off user != null then ran claim_first_admin
          // unauthenticated (misleading "admin already exists" error) and
          // emitted Authenticated with no session (the router bounces to /login
          // and every sync fails "Not authenticated"). Stop with a clear message.
          if (user != null && response.session == null) {
            emit(
              AuthError(
                event.role == UserRole.admin
                    ? 'Akun dibuat, tetapi email harus dikonfirmasi dulu. Cek '
                          'inbox lalu login. Jika status admin belum aktif '
                          'setelah login, nonaktifkan "Confirm email" di '
                          'pengaturan Auth Supabase lalu daftar ulang.'
                    : 'Registrasi berhasil. Konfirmasi email Anda (cek inbox), '
                          'lalu login.',
              ),
            );
            return;
          }

          if (user != null && event.role == UserRole.admin) {
            // First-admin bootstrap (mosque registration screen). This is
            // the ONLY path that can elevate a brand-new account above
            // 'viewer', and it succeeds exactly once per project -- see
            // claim_first_admin() in the database migrations.
            try {
              await _supabase!.rpc('claim_first_admin');
            } catch (e) {
              emit(
                AuthError(
                  'Masjid ini sudah memiliki admin terdaftar. Akun Anda '
                  'tetap dibuat sebagai Viewer — silakan login, lalu minta '
                  'admin masjid untuk mengubah role Anda.',
                ),
              );
              return;
            }

            // Mirror the now server-confirmed role into user_metadata purely as
            // a display cache for other tooling. Nothing in this app reads it
            // for authorization any more: _resolveRole() goes to
            // public.profiles.role, because any user can rewrite their own
            // user_metadata via auth.updateUser(). Best-effort -- the claim
            // itself already succeeded above regardless of this.
            try {
              await _supabase!.auth.updateUser(
                UserAttributes(data: {'role': 'admin'}),
              );
            } catch (e) {
              // Non-fatal: the claim itself already succeeded, so let
              // registration continue normally below.
              debugPrint('Failed to sync admin role into user_metadata: $e');
            }
          }
        } catch (e) {
          debugPrint('Supabase registration failed: $e');
          emit(AuthError('Registrasi online gagal: $e'));
          return; // FIX: Do not silently fallback to offline registration on error
        }
      }

      // 2. Local Registration (Only if Supabase is null or successful)
      final userId = user?.id ?? const Uuid().v4();
      final role = event.role;

      await _localDatasource.saveCredentials(
        email: normalizedEmail,
        password: event.password,
        role: role.toString().split('.').last,
        userId: userId,
        metadata: {'full_name': event.name},
        username: normalizedUsername,
      );

      if (user == null) {
        await _localDatasource.savePendingUserPassword(userId, event.password);
      }

      // Save to Users Table (Local DB)
      await _userRepository.addUser(
        domain.UserEntity(
          remoteId: user?.id ?? userId,
          email: normalizedEmail,
          username: normalizedUsername,
          fullName: event.name,
          role: role.toString().split('.').last,
          syncStatus: user != null ? 0 : 1, // 0 if synced, 1 if pending
        ),
      );

      // 3. Emit Authenticated
      if (user != null) {
        globalAuthNotifier.setOffline(false);
        globalAuthNotifier.setRole(role);
        emit(Authenticated(user, role: role));
      } else {
        globalAuthNotifier.setOffline(true);
        globalAuthNotifier.setRole(role);
        emit(
          AuthOffline(
            LocalUser(
              id: userId,
              email: normalizedEmail,
              role: role,
              metadata: {
                'full_name': event.name,
                'username': normalizedUsername,
              },
            ),
          ),
        );
      }
    } catch (e) {
      emit(AuthError('Registrasi gagal: $e'));
    }
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    try {
      // 1. Try Online Session First
      if (_supabase != null) {
        final session = _supabase!.auth.currentSession;
        if (session != null) {
          final role = await _resolveRole(session.user);
          globalAuthNotifier.setOffline(false);
          globalAuthNotifier.setRole(role);
          emit(Authenticated(session.user, role: role));
          return;
        }
      }

      // 2. Fall back to the locally remembered session. We deliberately do
      // NOT attempt a silent password-based re-login here: that used to
      // work by keeping the user's real online password in secure storage
      // indefinitely so it could be replayed against signInWithPassword,
      // which meant a compromised device/keystore handed over the user's
      // actual reusable password, not just a local hash. Supabase's own
      // session persistence (backed by its refresh token) already restores
      // `currentSession` above whenever it's still valid; if it isn't, the
      // safe behavior is simply to stay in local/offline mode until the
      // user explicitly logs in online again.
      final lastUser = await _localDatasource.getLastLoggedInUser();
      if (lastUser != null) {
        globalAuthNotifier.setOffline(true);
        globalAuthNotifier.setRole(lastUser.role);
        emit(AuthOffline(lastUser));
      } else {
        globalAuthNotifier.setOffline(false);
        globalAuthNotifier.setRole(null);
        emit(Unauthenticated());
      }
    } catch (_) {
      // If error occurs, try fallback to local storage
      try {
        final lastUser = await _localDatasource.getLastLoggedInUser();
        if (lastUser != null) {
          globalAuthNotifier.setOffline(true);
          globalAuthNotifier.setRole(lastUser.role);
          emit(AuthOffline(lastUser));
        } else {
          globalAuthNotifier.setOffline(false);
          globalAuthNotifier.setRole(null);
          emit(Unauthenticated());
        }
      } catch (e) {
        globalAuthNotifier.setOffline(false);
        globalAuthNotifier.setRole(null);
        emit(Unauthenticated());
      }
    }
  }

  Future<void> _onOfflineLoginRequested(
    OfflineLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final lastUser = await _localDatasource.getLastLoggedInUser();

      if (lastUser != null) {
        globalAuthNotifier.setOffline(true);
        globalAuthNotifier.setRole(lastUser.role);
        emit(AuthOffline(lastUser));
      } else {
        emit(
          const AuthError(
            'Belum ada data akun di perangkat ini. Silakan Login Online atau Daftar Masjid Baru terlebih dahulu.',
          ),
        );
      }
    } catch (e) {
      emit(AuthError('Gagal masuk mode offline: $e'));
    }
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      final identifier = event.identifier.trim();
      final isEmail = identifier.contains('@');
      String? resolvedEmail = isEmail ? identifier : null;
      if (!isEmail) {
        final user = await _userRepository.getUserByUsername(identifier);
        resolvedEmail =
            user?.email ??
            await _localDatasource.getEmailByUsername(identifier);

        // Jika tidak ketemu di lokal, login menggunakan username tidak didukung online tanpa RPC khusus
        // Supabase secara default membutuhkan email.
      }

      // Try Online Login
      if (_supabase != null && resolvedEmail != null) {
        try {
          final response = await _supabase!.auth.signInWithPassword(
            email: resolvedEmail,
            password: event.password,
          );

          if (response.user != null) {
            await _handleSuccessfulLogin(response.user!, event.password, emit);
            return;
          }
        } catch (e) {
          // If login fails (maybe user doesn't exist on Supabase yet),
          // Check if it's a valid local user, and if so, MIGRATE them.
          if (e.toString().contains('Invalid login credentials') ||
              e.toString().contains('Email not confirmed')) {
            // Fallback to local verification
          } else {
            debugPrint('Login error: $e');
          }
        }
      }

      // If Supabase login failed or not configured, try Local Verification
      final localUser = await _localDatasource.verifyCredentials(
        event.identifier,
        event.password,
      );

      if (localUser != null) {
        // We intentionally do NOT self-signUp offline-provisioned accounts on
        // login. Doing so created a brand-new server account whose
        // handle_new_user() trigger forces role='viewer' -- silently
        // downgrading e.g. a bendahara to viewer -- and duplicated an email
        // that the admin's _pushUsers sync later tries to create again via the
        // admin-users Edge Function, wedging that row. Offline-provisioned
        // users stay offline until an admin's device syncs their account (which
        // creates it server-side with the correct role); then they log in
        // online normally.
        await _localDatasource.setLastLoggedInEmail(localUser.email);
        globalAuthNotifier.setOffline(true);
        globalAuthNotifier.setRole(localUser.role);
        emit(AuthOffline(localUser));
      } else {
        emit(
          AuthError(
            !event.identifier.contains('@')
                ? 'Username tidak ditemukan di perangkat. Gunakan email atau login online terlebih dahulu.'
                : 'Login gagal. Pastikan email/password benar atau koneksi internet tersedia.',
          ),
        );
      }
    } catch (e) {
      emit(AuthError('Login error: $e'));
    }
  }

  Future<void> _handleSuccessfulLogin(
    User user,
    String password,
    Emitter<AuthState> emit,
  ) async {
    final role = await _resolveRole(user);
    final username = (user.userMetadata?['username'] as String?)?.toLowerCase();

    // Save Credentials for Offline
    await _localDatasource.saveCredentials(
      email: user.email!,
      password: password,
      role: role.toString().split('.').last, // 'admin', etc.
      userId: user.id,
      metadata: user.userMetadata ?? {},
      username: username,
    );

    // Sync User to Local DB
    final existingUser = await _userRepository.getUserByRemoteId(user.id);
    if (existingUser == null) {
      // Check by email/username if remoteId mismatch (legacy handling)
      final legacyUser = await _userRepository.getUserByUsername(
        username ?? '',
      );

      if (legacyUser != null) {
        await _userRepository.updateUser(
          legacyUser.copyWith(remoteId: user.id, syncStatus: 0),
        );
      } else {
        await _userRepository.addUser(
          domain.UserEntity(
            remoteId: user.id,
            email: user.email!,
            username: username,
            fullName: user.userMetadata?['full_name'] as String?,
            role: role.toString().split('.').last,
            syncStatus: 0,
          ),
        );
      }
    } else if (existingUser.syncStatus == 2) {
      // Preserve an offline profile edit that hasn't synced yet (pendingUpdate):
      // overwriting it with the server's stale values here would lose it. Only
      // refresh the server-authoritative role + remoteId; keep the edited
      // fields and the pending status so the sync engine pushes them up.
      await _userRepository.updateUser(
        existingUser.copyWith(
          remoteId: user.id,
          role: role.toString().split('.').last,
        ),
      );
    } else {
      await _userRepository.updateUser(
        domain.UserEntity(
          id: existingUser.id,
          remoteId: user.id,
          email: user.email!,
          username: username ?? existingUser.username,
          fullName: user.userMetadata?['full_name'] as String?,
          role: role.toString().split('.').last,
          syncStatus: 0,
        ),
      );
    }

    globalAuthNotifier.setOffline(false);
    globalAuthNotifier.setRole(role);
    emit(Authenticated(user, role: role));
  }

  UserRole _roleFromName(String? roleStr) {
    switch (roleStr) {
      case 'admin':
        return UserRole.admin;
      case 'ketua':
        return UserRole.ketua;
      case 'bendahara':
        return UserRole.bendahara;
      case 'sekretaris':
        return UserRole.sekretaris;
      default:
        return UserRole.viewer;
    }
  }

  /// Resolves the role this session is allowed to act with.
  ///
  /// `user_metadata` is NOT an authorization source: any authenticated user can
  /// rewrite it with `auth.updateUser(data: {'role': 'admin'})`, which used to
  /// be enough to unlock every admin screen and route guard in the app. RLS
  /// still refused the writes server-side, so the damage was local ghost data
  /// -- but the app's own access control was trivially bypassable.
  ///
  /// `public.profiles.role` is the real thing: only an admin/ketua may change
  /// it (enforced by the `WITH CHECK` on the profiles UPDATE policy).
  ///
  /// When the server is unreachable we fall back to the role last confirmed BY
  /// the server for this account, and to `viewer` if there is none. We never
  /// fall back to metadata, otherwise an attacker could forge the claim and
  /// then simply go offline to make it stick.
  Future<UserRole> _resolveRole(User user) async {
    final client = _supabase;
    if (client != null) {
      try {
        final row = await client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        final serverRole = row?['role'] as String?;
        if (serverRole != null) {
          final email = user.email;
          if (email != null) {
            await _localDatasource.saveStoredRole(email, serverRole);
          }
          return _roleFromName(serverRole);
        }
      } catch (e) {
        debugPrint('Could not read profiles.role, using cached role: $e');
      }
    }

    final email = user.email;
    if (email != null) {
      final cached = await _localDatasource.getStoredRole(email);
      if (cached != null) return _roleFromName(cached);
    }
    return UserRole.viewer;
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    globalAuthNotifier.setOffline(false);
    globalAuthNotifier.setRole(null);
    try {
      if (_supabase != null) {
        await _supabase!.auth.signOut();
      }
      await _localDatasource.clearCredentials();
      // Jangan panggil await _appDatabase.clearAllData(); karena akan menghapus semua data transaksi dan aktivitas
    } catch (_) {}
    emit(Unauthenticated());
  }
}
