import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:masjid_app/domain/entities/mosque_profile.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/blocs/profile/profile_bloc.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: BlocListener<SyncCubit, SyncState>(
        listener: (context, state) {
          if (state.isSuccess && !state.isSyncing) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sinkronisasi berhasil')),
            );
          } else if (!state.isSuccess && state.errorMessages.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Gagal sinkronisasi: ${state.errorMessages.first}',
                ),
              ),
            );
          }
        },
        child: ListView(
          children: [
            _buildUserProfileSection(context),
            const Divider(),
            _buildProfileSection(context),
            const Divider(),
            BlocBuilder<SyncCubit, SyncState>(
              builder: (context, state) {
                return ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sinkronisasi Data'),
                  subtitle: Text(
                    state.isSyncing
                        ? 'Sedang menyinkronkan...'
                        : 'Tekan untuk sinkronisasi manual',
                  ),
                  trailing: state.isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: state.isSyncing
                      ? null
                      : () => context.read<SyncCubit>().forceSync(),
                );
              },
            ),
            const Divider(),
            // User Management Menu
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, authState) {
                bool isAdmin = false;
                if (authState is Authenticated) {
                  isAdmin = authState.role.canManageSettings; // Only Admin
                } else if (authState is AuthOffline) {
                  isAdmin = authState.role.canManageSettings;
                }

                if (!isAdmin) return const SizedBox.shrink();

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.people),
                      title: const Text('Daftar Pengguna'),
                      subtitle: const Text('Kelola role pengguna lain'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        context.go('/settings/users');
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Audit Logs'),
                      subtitle: const Text('Riwayat aktivitas pengguna'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        context.go('/settings/audit-logs');
                      },
                    ),
                  ],
                );
              },
            ),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () {
                context.read<AuthBloc>().add(LogoutRequested());
                context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserProfileSection(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        String name = '';
        String email = '';
        String role = '';

        if (state is Authenticated) {
          name = state.user.userMetadata?['full_name'] ?? 'User';
          email = state.user.email ?? '';
          role = state.role.name.toUpperCase();
        } else if (state is AuthOffline) {
          name = state.user.metadata['full_name'] ?? 'User';
          email = state.user.email;
          role = state.role.name.toUpperCase();
        } else {
          return const SizedBox.shrink();
        }

        return ListTile(
          leading: CircleAvatar(
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U'),
          ),
          title: Text(name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email),
              Text(
                role,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.go('/settings/edit-profile'),
          ),
        );
      },
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is ProfileLoaded) {
          return BlocBuilder<AuthBloc, AuthState>(
            builder: (context, authState) {
              bool canEdit = false;
              if (authState is Authenticated) {
                canEdit = authState.role.canManageSettings;
              } else if (authState is AuthOffline) {
                canEdit = authState.role.canManageSettings;
              }

              return ListTile(
                leading: _buildLogo(state.profile),
                title: Text(state.profile.name),
                subtitle: Text(state.profile.address ?? '-'),
                trailing: canEdit
                    ? IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _showEditProfileDialog(context, state.profile),
                      )
                    : null,
              );
            },
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildLogo(MosqueProfile profile) {
    if (profile.logoPath != null && File(profile.logoPath!).existsSync()) {
      return CircleAvatar(backgroundImage: FileImage(File(profile.logoPath!)));
    } else if (profile.logoUrl != null) {
      return CircleAvatar(backgroundImage: NetworkImage(profile.logoUrl!));
    }
    return const CircleAvatar(child: Icon(Icons.mosque));
  }

  void _showEditProfileDialog(
    BuildContext context,
    MosqueProfile currentProfile,
  ) {
    final nameController = TextEditingController(text: currentProfile.name);
    final addressController = TextEditingController(
      text: currentProfile.address,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profil Masjid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nama Masjid'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Alamat'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              final newProfile = MosqueProfile(
                id: currentProfile.id,
                name: nameController.text,
                address: addressController.text,
                logoPath: currentProfile.logoPath,
              );
              context.read<ProfileBloc>().add(SaveProfile(newProfile));
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
