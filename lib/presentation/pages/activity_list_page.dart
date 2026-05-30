import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/domain/entities/activity.dart';
import 'package:masjid_app/domain/entities/transaction.dart'; // For SyncStatus
import 'package:masjid_app/presentation/blocs/activity/activity_bloc.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:intl/intl.dart';

class ActivityListPage extends StatelessWidget {
  const ActivityListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal Kegiatan')),
      body: BlocBuilder<ActivityBloc, ActivityState>(
        builder: (context, state) {
          if (state is ActivityLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ActivityLoaded) {
            if (state.activities.isEmpty) {
              return const Center(child: Text('Belum ada kegiatan'));
            }
            return ListView.separated(
              itemCount: state.activities.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final activity = state.activities[index];
                return BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, authState) {
                    bool canManage = false;
                    if (authState is Authenticated) {
                      canManage = authState.role.canManageActivities;
                    } else if (authState is AuthOffline) {
                      canManage = authState.role.canManageActivities;
                    }

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(activity.date.day.toString()),
                      ),
                      title: Text(activity.title),
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
                                color: Colors.grey,
                              ),
                            ),
                          if (canManage)
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () {
                                _showActivityOptions(context, activity);
                              },
                            ),
                        ],
                      ),
                      onTap: () {
                        _showActivityDetails(context, activity);
                      },
                    );
                  },
                );
              },
            );
          }
          return const Center(child: Text('Error loading data'));
        },
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

          return FloatingActionButton(
            onPressed: () {
              context.push('/activities/add');
            },
            child: const Icon(Icons.add),
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
              context.read<ActivityBloc>().add(
                DeleteActivityEvent(activity.id!),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
