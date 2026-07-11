import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/core/theme/app_theme.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';
import 'package:masjid_app/presentation/widgets/app_components.dart';

class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({super.key});

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  late Future<_SyncSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  Future<_SyncSnapshot> _loadSnapshot() async {
    final db = GetIt.I<AppDatabase>();
    final pendingStatuses = [
      SyncStatus.pendingCreate.index,
      SyncStatus.pendingUpdate.index,
      SyncStatus.pendingDelete.index,
    ];

    final transactionCount = (await (db.select(
      db.transactions,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;
    final activityCount = (await (db.select(
      db.activities,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;
    final profileCount = (await (db.select(
      db.mosqueProfiles,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;
    final userCount = (await (db.select(
      db.users,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;
    final auditCount = (await (db.select(
      db.auditLogs,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;
    final qurbanPackageCount = (await (db.select(
      db.qurbanPackages,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;
    final qurbanParticipantCount = (await (db.select(
      db.qurbanParticipants,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;
    final qurbanPaymentCount = (await (db.select(
      db.qurbanPayments,
    )..where((t) => t.syncStatus.isIn(pendingStatuses))).get()).length;

    return _SyncSnapshot(
      transactionCount: transactionCount,
      activityCount: activityCount,
      profileCount: profileCount,
      userCount: userCount,
      auditCount: auditCount,
      qurbanPackageCount: qurbanPackageCount,
      qurbanParticipantCount: qurbanParticipantCount,
      qurbanPaymentCount: qurbanPaymentCount,
    );
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = _loadSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Center')),
      body: BlocListener<SyncCubit, SyncState>(
        listener: (context, state) {
          if (!state.isSyncing) {
            _refresh();
          }
        },
        child: FutureBuilder<_SyncSnapshot>(
          future: _snapshotFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: () async {
                _refresh();
                await _snapshotFuture;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  BlocBuilder<SyncCubit, SyncState>(
                    builder: (context, state) {
                      return _SyncStatusCard(state: state, snapshot: data);
                    },
                  ),
                  const SizedBox(height: 18),
                  const AppSectionTitle(title: 'Antrean Lokal'),
                  const SizedBox(height: 10),
                  _PendingTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Transaksi Kas',
                    count: data.transactionCount,
                    onTap: () => context.go('/transactions'),
                  ),
                  _PendingTile(
                    icon: Icons.event_note_outlined,
                    title: 'Kegiatan',
                    count: data.activityCount,
                    onTap: () => context.go('/activities'),
                  ),
                  _PendingTile(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'Qurban',
                    count: data.qurbanCount,
                    subtitle:
                        'Paket, peserta, dan pembayaran yang belum terkirim',
                    onTap: () => context.go('/qurban'),
                  ),
                  _PendingTile(
                    icon: Icons.mosque_outlined,
                    title: 'Profil Masjid',
                    count: data.profileCount,
                    onTap: () => context.go('/settings'),
                  ),
                  _PendingTile(
                    icon: Icons.people_outline,
                    title: 'Pengguna',
                    count: data.userCount,
                    subtitle: data.userCount > 0
                        ? 'Sinkronisasi akun memakai backend admin-users'
                        : null,
                    onTap: () => context.go('/settings/users'),
                  ),
                  _PendingTile(
                    icon: Icons.history_rounded,
                    title: 'Audit Log',
                    count: data.auditCount,
                    onTap: () => context.go('/settings/audit-logs'),
                  ),
                  const SizedBox(height: 20),
                  BlocBuilder<SyncCubit, SyncState>(
                    builder: (context, state) {
                      return FilledButton.icon(
                        onPressed: state.isSyncing
                            ? null
                            : () => context.read<SyncCubit>().forceSync(),
                        icon: state.isSyncing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync_rounded),
                        label: Text(
                          state.isSyncing
                              ? 'Menyinkronkan...'
                              : 'Sinkronisasi Sekarang',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh Status Lokal'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  final SyncState state;
  final _SyncSnapshot snapshot;

  const _SyncStatusCard({required this.state, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final hasPending = snapshot.totalPending > 0;
    final tone = state.isSyncing
        ? AppBannerTone.info
        : state.isSuccess && !hasPending
        ? AppBannerTone.success
        : state.isSuccess
        ? AppBannerTone.warning
        : AppBannerTone.danger;
    final icon = state.isSyncing
        ? Icons.sync_rounded
        : state.isSuccess && !hasPending
        ? Icons.cloud_done_rounded
        : state.isSuccess
        ? Icons.cloud_queue_rounded
        : Icons.cloud_off_rounded;
    final title = state.isSyncing
        ? 'Sinkronisasi berjalan'
        : state.isSuccess && !hasPending
        ? 'Semua data sinkron'
        : state.isSuccess
        ? '${snapshot.totalPending} item menunggu sync'
        : 'Sinkronisasi gagal';
    final message = state.errorMessages.isEmpty
        ? 'Status dihitung dari database lokal perangkat ini.'
        : state.errorMessages.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStatusBanner(icon: icon, title: title, message: message, tone: tone),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: 'Total',
                  value: '${snapshot.totalPending}',
                  color: hasPending ? AppColors.gold : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniMetric(
                  label: 'Qurban',
                  value: '${snapshot.qurbanCount}',
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniMetric(
                  label: 'Kas',
                  value: '${snapshot.transactionCount}',
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PendingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final String? subtitle;
  final VoidCallback? onTap;

  const _PendingTile({
    required this.icon,
    required this.title,
    required this.count,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = count == 0 ? AppColors.primary : AppColors.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppActionTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        accentColor: color,
        onTap: onTap,
        trailing: Chip(
          label: Text('$count'),
          side: BorderSide(color: color.withValues(alpha: 0.28)),
          backgroundColor: color.withValues(alpha: 0.1),
          labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SyncSnapshot {
  final int transactionCount;
  final int activityCount;
  final int profileCount;
  final int userCount;
  final int auditCount;
  final int qurbanPackageCount;
  final int qurbanParticipantCount;
  final int qurbanPaymentCount;

  const _SyncSnapshot({
    required this.transactionCount,
    required this.activityCount,
    required this.profileCount,
    required this.userCount,
    required this.auditCount,
    required this.qurbanPackageCount,
    required this.qurbanParticipantCount,
    required this.qurbanPaymentCount,
  });

  int get qurbanCount =>
      qurbanPackageCount + qurbanParticipantCount + qurbanPaymentCount;

  int get totalPending =>
      transactionCount +
      activityCount +
      profileCount +
      userCount +
      auditCount +
      qurbanCount;
}
