import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/core/theme/app_theme.dart';
import 'package:masjid_app/domain/entities/activity.dart';
import 'package:masjid_app/domain/entities/transaction.dart'; // For SyncStatus
import 'package:masjid_app/presentation/blocs/activity/activity_bloc.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/presentation/widgets/app_components.dart';

class ActivityListPage extends StatefulWidget {
  const ActivityListPage({super.key});

  @override
  State<ActivityListPage> createState() => _ActivityListPageState();
}

class _ActivityListPageState extends State<ActivityListPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Activity> _filter(List<Activity> activities) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return activities;
    return activities.where((a) {
      return a.title.toLowerCase().contains(q) ||
          a.type.toLowerCase().contains(q) ||
          (a.picName ?? '').toLowerCase().contains(q) ||
          (a.description ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal Kegiatan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Cari judul, PIC, atau jenis...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'Bersihkan',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<ActivityBloc, ActivityState>(
              builder: (context, state) {
                if (state is ActivityLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is ActivityLoaded) {
                  if (state.activities.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.event_note_outlined,
                      title: 'Belum ada kegiatan',
                      message:
                          'Tambahkan jadwal untuk mulai mengatur agenda masjid.',
                    );
                  }

                  final activities = _filter(state.activities);
                  if (activities.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Tidak ada hasil',
                      message: 'Coba kata kunci lain untuk mencari kegiatan.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: activities.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final activity = activities[index];
                      return BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, authState) {
                          bool canManage = false;
                          if (authState is Authenticated) {
                            canManage = authState.role.canManageActivities;
                          } else if (authState is AuthOffline) {
                            canManage = authState.role.canManageActivities;
                          }

                          return Material(
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              side: const BorderSide(color: AppColors.line),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.tealSoft,
                                foregroundColor: AppColors.teal,
                                child: Text(
                                  activity.date.day.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              title: Text(
                                activity.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${DateFormat('EEEE, dd MMM yyyy HH:mm', 'id').format(activity.date)}\n${activity.picName ?? '-'}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (activity.syncStatus != SyncStatus.synced)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8.0),
                                      child: Icon(
                                        Icons.cloud_upload_outlined,
                                        size: 16,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  if (canManage)
                                    IconButton(
                                      icon: const Icon(Icons.more_vert_rounded),
                                      onPressed: () {
                                        _showActivityOptions(context, activity);
                                      },
                                    ),
                                ],
                              ),
                              onTap: () {
                                _showActivityDetails(context, activity);
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                }
                return const Center(child: Text('Error loading data'));
              },
            ),
          ),
        ],
      ),
      floatingActionButton: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          bool canAdd = false;
          if (authState is Authenticated) {
            canAdd = authState.role.canManageActivities;
          } else if (authState is AuthOffline) {
            canAdd = authState.role.canManageActivities;
          }

          if (!canAdd) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            onPressed: () {
              context.push('/activities/add');
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Kegiatan'),
          );
        },
      ),
    );
  }

  void _showActivityDetails(BuildContext context, Activity activity) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activity.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, dd MMM yyyy HH:mm', 'id').format(activity.date),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('PIC: ${activity.picName ?? '-'}'),
            const SizedBox(height: 16),
            const Text(
              'Deskripsi:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(activity.description ?? '-'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showActivityOptions(BuildContext context, Activity activity) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Edit Kegiatan'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/activities/edit', extra: activity);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Hapus Kegiatan',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, activity);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Activity activity) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kegiatan'),
        content: const Text('Apakah Anda yakin ingin menghapus kegiatan ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              context.read<ActivityBloc>().add(DeleteActivityEvent(activity.id!));
              Navigator.pop(ctx);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
