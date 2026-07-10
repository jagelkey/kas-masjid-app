import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:masjid_app/core/services/admin_user_service.dart';
import 'package:masjid_app/data/datasources/local/auth_local_datasource.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain_status;
import 'package:masjid_app/domain/entities/user.dart';
import 'package:masjid_app/domain/repositories/user_repository.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final _userRepository = GetIt.I<UserRepository>();
  final _authLocalDatasource = GetIt.I<AuthLocalDatasource>();

  AdminUserService _adminUserService() {
    try {
      return AdminUserService(Supabase.instance.client);
    } catch (_) {
      return const AdminUserService(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final isAdmin =
            (authState is Authenticated && authState.role.canManageSettings) ||
            (authState is AuthOffline && authState.role.canManageSettings);

        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Manajemen Pengguna')),
            body: const Center(child: Text('Akses ditolak')),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Manajemen Pengguna')),
          body: StreamBuilder<List<UserEntity>>(
            stream: _userRepository.watchUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final users = snapshot.data ?? [];

              if (users.isEmpty) {
                return const Center(
                  child: Text('Tidak ada pengguna ditemukan'),
                );
              }

              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  return _buildUserTile(user);
                },
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _showAddUserDialog,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'viewer';
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Pengguna Baru'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Lengkap',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: obscurePassword,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedRole),
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'ketua', child: Text('Ketua')),
                      DropdownMenuItem(
                        value: 'bendahara',
                        child: Text('Bendahara'),
                      ),
                      DropdownMenuItem(
                        value: 'sekretaris',
                        child: Text('Sekretaris'),
                      ),
                      DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedRole = value);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty &&
                  usernameController.text.isNotEmpty &&
                  emailController.text.isNotEmpty &&
                  passwordController.text.isNotEmpty) {
                Navigator.pop(ctx);
                _addNewUser(
                  nameController.text,
                  usernameController.text,
                  emailController.text,
                  selectedRole,
                  passwordController.text,
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Semua field harus diisi')),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewUser(
    String name,
    String username,
    String email,
    String role,
    String password,
  ) async {
    try {
      final normalizedUsername = username.trim().toLowerCase();
      final existingUsers = await _userRepository.getUsers();
      final emailExists = existingUsers.any(
        (u) => u.email.toLowerCase() == email.toLowerCase(),
      );
      final usernameExists = existingUsers.any(
        (u) => (u.username ?? '').toLowerCase() == normalizedUsername,
      );
      if (emailExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Email sudah terdaftar')),
          );
        }
        return;
      }
      if (usernameExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username sudah terdaftar')),
          );
        }
        return;
      }

      // Generate a local ID for offline user
      String userId = const Uuid().v4();
      int syncStatus = domain_status.SyncStatus.pendingCreate.index;

      // Check connectivity and try to create online first
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline =
          connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.wifi);

      if (isOnline) {
        try {
          final result = await _adminUserService().createUser(
            email: email,
            password: password,
            fullName: name,
            username: normalizedUsername,
            role: role,
          );
          if (result.isSuccess && result.userId != null) {
            userId = result.userId!;
            syncStatus = domain_status.SyncStatus.synced.index;
          } else {
            throw Exception(result.message ?? 'Admin user backend gagal');
          }
        } catch (e) {
          debugPrint('Gagal create user online: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Gagal buat user online: $e. Menyimpan offline...',
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Offline: User dibuat lokal. Password hanya tersimpan di perangkat ini.',
              ),
            ),
          );
        }
      }

      // 1. Save credentials securely (so they can login offline).
      // markAsLastLoggedIn: false -- this account belongs to someone else. The
      // admin doing the provisioning must stay the current user on this device.
      await _authLocalDatasource.saveCredentials(
        email: email,
        password: password,
        role: role,
        userId: userId,
        metadata: {'full_name': name, 'username': normalizedUsername},
        username: normalizedUsername,
        markAsLastLoggedIn: false,
      );

      // If offline, save pending password for sync
      if (!isOnline ||
          syncStatus == domain_status.SyncStatus.pendingCreate.index) {
        await _authLocalDatasource.savePendingUserPassword(userId, password);
      }

      // 2. Save user profile to local database
      final newUser = UserEntity(
        remoteId: userId, // Use UUID as remoteId for offline users too
        email: email,
        username: normalizedUsername,
        fullName: name,
        role: role,
        syncStatus: syncStatus,
      );

      await _userRepository.addUser(newUser);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengguna berhasil ditambahkan (Lokal)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menambah pengguna: $e')));
      }
    }
  }

  Widget _buildUserTile(UserEntity user) {
    final String currentRole = user.role;
    final String name = user.fullName ?? 'Tanpa Nama';
    final String email = user.email;

    return ListTile(
      leading: CircleAvatar(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
      ),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(email),
          const SizedBox(height: 4),
          Row(
            children: [
              Chip(
                label: Text(
                  currentRole.toUpperCase(),
                  style: const TextStyle(fontSize: 10),
                ),
                backgroundColor: _getRoleColor(
                  currentRole,
                ).withValues(alpha: 0.2),
                labelStyle: TextStyle(color: _getRoleColor(currentRole)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              if (user.syncStatus != 0) ...[
                const SizedBox(width: 8),
                const Icon(Icons.sync, size: 14, color: Colors.grey),
              ],
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            _showRoleDialog(user);
          } else if (value == 'delete') {
            _confirmDeleteUser(user);
          }
        },
        itemBuilder: (BuildContext context) {
          return [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Edit User'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Hapus User'),
                ],
              ),
            ),
          ];
        },
      ),
    );
  }

  void _confirmDeleteUser(UserEntity user) {
    final authState = context.read<AuthBloc>().state;
    String? currentUserId;
    if (authState is Authenticated) {
      currentUserId = authState.user.id;
    } else if (authState is AuthOffline) {
      currentUserId = authState.user.id;
    }

    if (user.remoteId == currentUserId && currentUserId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anda tidak dapat menghapus akun Anda sendiri'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pengguna?'),
        content: Text(
          'Apakah Anda yakin ingin menghapus pengguna ${user.fullName ?? user.email}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteUser(user);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(UserEntity user) async {
    if (user.id == null) return;
    try {
      await _userRepository.deleteUser(user.id!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pengguna dihapus')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menghapus pengguna: $e')));
      }
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'ketua':
        return Colors.purple;
      case 'bendahara':
        return Colors.green;
      case 'sekretaris':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showRoleDialog(UserEntity user) {
    final nameController = TextEditingController(text: user.fullName);
    final usernameController = TextEditingController(text: user.username);
    final emailController = TextEditingController(text: user.email);
    final passwordController = TextEditingController();
    String selectedRole = user.role;
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit User: ${user.fullName ?? user.email}'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Lengkap',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password Baru (Opsional)',
                      helperText: 'Kosongkan jika tidak ingin mengubah',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: obscurePassword,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedRole),
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'ketua', child: Text('Ketua')),
                      DropdownMenuItem(
                        value: 'bendahara',
                        child: Text('Bendahara'),
                      ),
                      DropdownMenuItem(
                        value: 'sekretaris',
                        child: Text('Sekretaris'),
                      ),
                      DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedRole = value);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateUserFull(
                user,
                nameController.text,
                usernameController.text,
                emailController.text,
                selectedRole,
                passwordController.text,
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUserFull(
    UserEntity user,
    String name,
    String username,
    String email,
    String role,
    String password,
  ) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline =
          connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.wifi);

      // Handle Pending Create User (Promote to Online)
      if (user.syncStatus == domain_status.SyncStatus.pendingCreate.index) {
        if (isOnline && password.isNotEmpty) {
          try {
            final result = await _adminUserService().createUser(
              email: email,
              password: password,
              fullName: name,
              username: username.trim().toLowerCase(),
              role: role,
            );

            if (result.isSuccess && result.userId != null) {
              final updatedUser = UserEntity(
                id: user.id,
                remoteId: result.userId!,
                email: email,
                username: username.trim().toLowerCase(),
                fullName: name,
                role: role,
                syncStatus: domain_status.SyncStatus.synced.index,
              );
              await _userRepository.updateUser(updatedUser);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('User baru berhasil disinkronkan ke server'),
                  ),
                );
              }
              return;
            }
          } catch (e) {
            debugPrint('Gagal create user online saat edit: $e');
            // Continue to local update
          }
        }
      }

      // 1. Update Password if provided (Online Only) for existing users
      if (password.isNotEmpty &&
          user.syncStatus != domain_status.SyncStatus.pendingCreate.index) {
        if (!isOnline) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Ganti password hanya bisa dilakukan saat online',
                ),
              ),
            );
          }
          return;
        }

        if (user.remoteId != null) {
          final result = await _adminUserService().updateUser(
            userId: user.remoteId!,
            email: email,
            fullName: name,
            username: username.trim().toLowerCase(),
            role: role,
            password: password,
          );
          if (!result.isSuccess) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Gagal update password online: ${result.message}',
                  ),
                ),
              );
            }
            return;
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Update password user lokal belum didukung (Hapus & Buat Baru)',
                ),
              ),
            );
          }
        }
      }

      // 2. Update Entity Local
      // Jika status sebelumnya pendingCreate, tetap pendingCreate
      int newSyncStatus = domain_status.SyncStatus.pendingUpdate.index;
      if (user.syncStatus == domain_status.SyncStatus.pendingCreate.index) {
        newSyncStatus = domain_status.SyncStatus.pendingCreate.index;
      }

      final updatedUser = UserEntity(
        id: user.id,
        remoteId: user.remoteId,
        email: email,
        username: username.trim().toLowerCase(),
        fullName: name,
        role: role,
        syncStatus: newSyncStatus,
      );

      await _userRepository.updateUser(updatedUser);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User berhasil diperbarui')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal update user: $e')));
      }
    }
  }
}
