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
        final updatedUser = currentUserEntity.copyWith(
          email: newEmail ?? currentUserEntity.email,
          username: newUsername ?? currentUserEntity.username,
          fullName: newFullName ?? currentUserEntity.fullName,
          syncStatus: 0, // 0=synced
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
              'role': event.role.toString().split('.').last,
              'username': normalizedUsername,
            },
          );
          user = response.user;

          // Ensure role is set in public.profiles
          if (user != null) {
            await _supabase!
                .from('profiles')
                .update({'role': event.role.toString().split('.').last})
                .eq('id', user.id);
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
        await _localDatasource.saveOnlinePassword(
          email: normalizedEmail,
          password: event.password,
        );
        globalAuthNotifier.setOffline(false);
        emit(Authenticated(user, role: role));
      } else {
        globalAuthNotifier.setOffline(true);
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
          final role = _parseRole(session.user.userMetadata);
          globalAuthNotifier.setOffline(false);
          emit(Authenticated(session.user, role: role));
          return;
        }
      }

      // 2. Try Restore Offline Session
      final lastUser = await _localDatasource.getLastLoggedInUser();
      if (lastUser != null) {
        final restoredSession = await _tryRestoreOnlineSession(lastUser);
        if (restoredSession != null) {
          await _handleSuccessfulLogin(
            restoredSession.user,
            restoredSession.password,
            emit,
          );
          return;
        }

        globalAuthNotifier.setOffline(true);
        emit(AuthOffline(lastUser));
      } else {
        globalAuthNotifier.setOffline(false);
        emit(Unauthenticated());
      }
    } catch (_) {
      // If error occurs, try fallback to local storage
      try {
        final lastUser = await _localDatasource.getLastLoggedInUser();
        if (lastUser != null) {
          final restoredSession = await _tryRestoreOnlineSession(lastUser);
          if (restoredSession != null) {
            await _handleSuccessfulLogin(
              restoredSession.user,
              restoredSession.password,
              emit,
            );
            return;
          }

          globalAuthNotifier.setOffline(true);
          emit(AuthOffline(lastUser));
        } else {
          globalAuthNotifier.setOffline(false);
          emit(Unauthenticated());
        }
      } catch (e) {
        globalAuthNotifier.setOffline(false);
        emit(Unauthenticated());
      }
    }
  }

  Future<({User user, String password})?> _tryRestoreOnlineSession(
    LocalUser lastUser,
  ) async {
    if (_supabase == null) return null;

    final password = await _localDatasource.getOnlinePassword(lastUser.email);
    if (password == null || password.isEmpty) return null;

    try {
      final response = await _supabase!.auth.signInWithPassword(
        email: lastUser.email,
        password: password,
      );
      final user = response.user;
      if (user == null) return null;
      return (user: user, password: password);
    } catch (e) {
      debugPrint('Online session restore failed: $e');
      return null;
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
        // --- AUTO MIGRATION LOGIC START ---
        if (_supabase != null) {
          try {
            // Try to Sign Up this local user to Supabase
            final response = await _supabase!.auth.signUp(
              email: localUser.email,
              password: event.password, // We have the password from input
              data: localUser.metadata,
            );

            if (response.user != null) {
              // Migration Success! Update local credentials with new Remote ID
              await _localDatasource.saveCredentials(
                email: localUser.email,
                password: event.password,
                role: localUser.role.toString().split('.').last,
                userId: response.user!.id,
                metadata: localUser.metadata,
                username: localUser.metadata['username'],
              );

              // Update User Entity in DB
              final existingUser = await _userRepository.getUserByUsername(
                localUser.metadata['username'] ?? '',
              );
              if (existingUser != null) {
                await _userRepository.updateUser(
                  existingUser.copyWith(
                    remoteId: response.user!.id,
                    syncStatus: 0, // Synced
                  ),
                );
              }

              // Log in again with new account to get session
              final loginResponse = await _supabase!.auth.signInWithPassword(
                email: localUser.email,
                password: event.password,
              );

              if (loginResponse.user != null) {
                await _handleSuccessfulLogin(
                  loginResponse.user!,
                  event.password,
                  emit,
                );
                return;
              }
            }
          } catch (migrationError) {
            debugPrint('Migration failed: $migrationError');
            // Continue to offline login if migration fails
          }
        }
        // --- AUTO MIGRATION LOGIC END ---

        await _localDatasource.setLastLoggedInEmail(localUser.email);
        globalAuthNotifier.setOffline(true);
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
    final role = _parseRole(user.userMetadata);
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
    await _localDatasource.saveOnlinePassword(
      email: user.email!,
      password: password,
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
    emit(Authenticated(user, role: role));
  }

  UserRole _parseRole(Map<String, dynamic>? metadata) {
    if (metadata == null) return UserRole.viewer;
    final roleStr = metadata['role'] as String?;
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

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    globalAuthNotifier.setOffline(false);
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
