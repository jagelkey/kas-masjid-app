import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/core/theme/app_theme.dart';
import 'package:masjid_app/domain/entities/mosque_profile.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/blocs/profile/profile_bloc.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';
import 'package:masjid_app/presentation/widgets/app_components.dart';

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
                  'Sinkronisasi gagal: ${state.errorMessages.first}',
                ),
                backgroundColor: AppColors.danger,
              ),
            );
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _buildUserProfileSection(context),
            const SizedBox(height: 12),
            _buildProfileSection(context),
            const SizedBox(height: 24),
            const AppSectionTitle(title: 'Sinkronisasi'),
            const SizedBox(height: 10),
            BlocBuilder<SyncCubit, SyncState>(
              builder: (context, state) {
                return AppActionTile(
                  icon: Icons.sync_rounded,
                  title: 'Sinkronisasi Data',
                  subtitle: state.isSyncing
                      ? 'Sedang menyinkronkan...'
                      : 'Kirim dan tarik perubahan terbaru',
                  trailing: state.isSyncing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: state.isSyncing
                      ? null
                      : () => context.read<SyncCubit>().forceSync(),
                );
              },
            ),
            const SizedBox(height: 10),
            AppActionTile(
              icon: Icons.cloud_queue_rounded,
              title: 'Sync Center',
              subtitle: 'Status antrean offline perangkat ini',
              accentColor: AppColors.teal,
              onTap: () => context.go('/settings/sync'),
            ),
            const SizedBox(height: 24),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, authState) {
                var isAdmin = false;
                if (authState is Authenticated) {
                  isAdmin = authState.role.canManageSettings;
                } else if (authState is AuthOffline) {
                  isAdmin = authState.role.canManageSettings;
                }

                if (!isAdmin) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionTitle(title: 'Admin'),
                    const SizedBox(height: 10),
                    AppActionTile(
                      icon: Icons.group_rounded,
                      title: 'Daftar Pengguna',
                      subtitle: 'Kelola akses dan role pengguna',
                      accentColor: AppColors.gold,
                      onTap: () => context.go('/settings/users'),
                    ),
                    const SizedBox(height: 10),
                    AppActionTile(
                      icon: Icons.manage_history_rounded,
                      title: 'Audit Logs',
                      subtitle: 'Riwayat aktivitas pengguna',
                      accentColor: AppColors.teal,
                      onTap: () => context.go('/settings/audit-logs'),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
            AppActionTile(
              icon: Icons.logout_rounded,
              title: 'Logout',
              subtitle: 'Keluar dari sesi pengguna saat ini',
              accentColor: AppColors.danger,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                // Navigating on a fixed delay was a guess: too short and the
                // user lands on /login while signOut() is still in flight, too
                // long and they stare at Settings for nothing. _onLogoutRequested
                // awaits signOut() + clearCredentials() and then emits
                // Unauthenticated outside its try/catch, so that state is the
                // completion signal -- wait for it instead.
                final authBloc = context.read<AuthBloc>();
                final router = GoRouter.of(context);
                authBloc.add(LogoutRequested());
                // Bounded only so a signOut() stalled on a dead connection
                // cannot strand the user on this page with no feedback; the
                // state above is the real mechanism, not this timeout.
                await authBloc.stream
                    .firstWhere((s) => s is Unauthenticated)
                    .timeout(
                      const Duration(seconds: 10),
                      onTimeout: () => Unauthenticated(),
                    );
                router.go('/login');
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
        var name = '';
        var email = '';
        var role = '';

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

        return _ProfilePanel(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primarySoft,
            foregroundColor: AppColors.primary,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          title: name,
          subtitle: email,
          pill: AppStatusPill(
            label: role,
            icon: Icons.verified_user_outlined,
            color: AppColors.primary,
          ),
          onEdit: () => context.go('/settings/edit-profile'),
        );
      },
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return BlocBuilder<AuthBloc, AuthState>(
          builder: (context, authState) {
            var canEdit = false;
            if (authState is Authenticated) {
              canEdit = authState.role.canManageSettings;
            } else if (authState is AuthOffline) {
              canEdit = authState.role.canManageSettings;
            }

            return _ProfilePanel(
              leading: _buildLogo(state.profile),
              title: state.profile.name,
              subtitle: state.profile.address ?? '-',
              pill: const AppStatusPill(
                label: 'MASJID',
                icon: Icons.mosque_rounded,
                color: AppColors.teal,
              ),
              onEdit: canEdit
                  ? () => _showEditProfileDialog(context, state.profile)
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildLogo(MosqueProfile profile) {
    if (profile.logoPath != null && File(profile.logoPath!).existsSync()) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: FileImage(File(profile.logoPath!)),
      );
    }
    if (profile.logoUrl != null) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(profile.logoUrl!),
      );
    }
    return const CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.primarySoft,
      foregroundColor: AppColors.primary,
      child: Icon(Icons.mosque_rounded),
    );
  }

  void _showEditProfileDialog(
    BuildContext context,
    MosqueProfile currentProfile,
  ) {
    final nameController = TextEditingController(text: currentProfile.name);
    final addressController = TextEditingController(
      text: currentProfile.address,
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profil Masjid'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nama Masjid'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nama masjid wajib diisi';
                  }
                  if (value.trim().length < 3) {
                    return 'Nama minimal 3 karakter';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Alamat'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Alamat wajib diisi';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final newProfile = MosqueProfile(
                id: currentProfile.id,
                name: nameController.text.trim(),
                address: addressController.text.trim(),
                logoPath: currentProfile.logoPath,
                logoUrl: currentProfile.logoUrl,
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

class _ProfilePanel extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget pill;
  final VoidCallback? onEdit;

  const _ProfilePanel({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.pill,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                pill,
              ],
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
          ],
        ],
      ),
    );
  }
}
