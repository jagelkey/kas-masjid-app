import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/core/di/injection.dart';
import 'package:masjid_app/core/services/pdf_service.dart';
import 'package:masjid_app/core/theme/app_theme.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/blocs/profile/profile_bloc.dart';
import 'package:masjid_app/presentation/blocs/qurban/qurban_bloc.dart';
import 'package:masjid_app/presentation/pages/qurban_payment_form_page.dart';
import 'package:masjid_app/presentation/widgets/app_components.dart';

final _currency = NumberFormat.currency(
  locale: 'id',
  symbol: 'Rp ',
  decimalDigits: 0,
);

class QurbanPage extends StatefulWidget {
  const QurbanPage({super.key});

  @override
  State<QurbanPage> createState() => _QurbanPageState();
}

class _QurbanPageState extends State<QurbanPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<QurbanBloc, QurbanState>(
      listener: _listenOperationState,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Iuran Qurban'),
          actions: [
            BlocBuilder<QurbanBloc, QurbanState>(
              builder: (context, state) {
                return IconButton(
                  tooltip: 'Laporan PDF',
                  icon: const Icon(Icons.picture_as_pdf),
                  onPressed: state is QurbanLoaded
                      ? () => _generatePdf(context, state)
                      : null,
                );
              },
            ),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, authState) {
                if (!_canManageQurban(authState)) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: 'Paket cicilan',
                  icon: const Icon(Icons.tune),
                  onPressed: () => context.push('/qurban/packages'),
                );
              },
            ),
          ],
        ),
        body: BlocBuilder<QurbanBloc, QurbanState>(
          builder: (context, state) {
            if (state is QurbanLoading || state is QurbanInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is QurbanError) {
              return AppEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Data qurban belum bisa dimuat',
                message: state.message,
              );
            }
            if (state is! QurbanLoaded) {
              return const AppEmptyState(
                icon: Icons.volunteer_activism_outlined,
                title: 'Gagal memuat data qurban',
              );
            }

            return Column(
              children: [
                _SummaryHeader(summary: state.summary),
                _SearchAndFilter(
                  controller: _searchController,
                  state: state,
                  onChanged: (query) => context.read<QurbanBloc>().add(
                    ApplyQurbanFilter(query: query, status: state.statusFilter),
                  ),
                  onStatusChanged: (status) => context.read<QurbanBloc>().add(
                    ApplyQurbanFilter(query: state.query, status: status),
                  ),
                ),
                Expanded(
                  child: state.filteredProgress.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.group_add_outlined,
                          title: 'Belum ada peserta qurban',
                          message:
                              'Tambahkan peserta untuk mulai mencatat cicilan.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: state.filteredProgress.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final progress = state.filteredProgress[index];
                            return _ParticipantTile(
                              progress: progress,
                              onTap: () => context.push(
                                '/qurban/participant/detail',
                                extra: progress,
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, authState) {
            if (!_canManageQurban(authState)) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: () => context.push('/qurban/participant/add'),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Peserta'),
            );
          },
        ),
      ),
    );
  }

  void _listenOperationState(BuildContext context, QurbanState state) {
    if (state is QurbanOperationSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.operationMessage)));
    } else if (state is QurbanOperationFailure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.operationMessage)));
    }
  }

  void _generatePdf(BuildContext context, QurbanLoaded state) {
    final profileState = context.read<ProfileBloc>().state;
    final profile = profileState is ProfileLoaded ? profileState.profile : null;
    getIt<PdfService>().generateQurbanReport(
      progress: state.filteredProgress,
      summary: QurbanSummary.fromProgress(state.filteredProgress),
      profile: profile,
      period: 'Progress Iuran Qurban',
    );
  }
}

class QurbanParticipantDetailPage extends StatelessWidget {
  final QurbanParticipantProgress progress;

  const QurbanParticipantDetailPage({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return BlocListener<QurbanBloc, QurbanState>(
      listener: (context, state) {
        if (state is QurbanOperationSuccess) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.operationMessage)));
        } else if (state is QurbanOperationFailure) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.operationMessage)));
        }
      },
      child: BlocBuilder<QurbanBloc, QurbanState>(
        builder: (context, state) {
          final currentProgress = _resolveCurrentProgress(state, progress);
          final participant = currentProgress.participant;
          final canManage = _canManageQurban(context.read<AuthBloc>().state);

          return Scaffold(
            appBar: AppBar(
              title: Text(participant.name),
              actions: [
                if (canManage)
                  IconButton(
                    tooltip: 'Edit peserta',
                    icon: const Icon(Icons.edit),
                    onPressed: () => context.push(
                      '/qurban/participant/edit',
                      extra: participant,
                    ),
                  ),
                if (canManage)
                  IconButton(
                    tooltip: 'Hapus peserta',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        _confirmDeleteParticipant(context, participant.id),
                  ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ParticipantDetailCard(progress: currentProgress),
                const SizedBox(height: 16),
                Text(
                  'Timeline 10 Bulan',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _PaymentTimeline(progress: currentProgress),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Histori Pembayaran',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (canManage)
                      FilledButton.icon(
                        onPressed: () => context.push(
                          '/qurban/payment/add',
                          extra: participant,
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Bayar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (currentProgress.payments.isEmpty)
                  const Text('Belum ada pembayaran')
                else
                  ..._sortedPayments(currentProgress.payments).map(
                    (payment) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(_currency.format(payment.amount)),
                        subtitle: Text(
                          '${DateFormat('dd MMM yyyy', 'id_ID').format(payment.paymentDate)}'
                          '${payment.note == null ? '' : ' - ${payment.note}'}',
                        ),
                        trailing: payment.syncStatus == SyncStatus.synced
                            ? null
                            : const Icon(Icons.cloud_upload_outlined, size: 18),
                        onTap: canManage
                            ? () => _showPaymentOptions(
                                context,
                                participant,
                                payment,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  QurbanParticipantProgress _resolveCurrentProgress(
    QurbanState state,
    QurbanParticipantProgress fallback,
  ) {
    if (state is! QurbanLoaded) return fallback;
    final id = fallback.participant.id;
    return state.progress.firstWhere(
      (item) => item.participant.id == id,
      orElse: () => fallback,
    );
  }

  void _confirmDeleteParticipant(BuildContext context, int? participantId) {
    if (participantId == null) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Peserta?'),
        content: const Text(
          'Peserta hanya bisa dihapus jika belum memiliki pembayaran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<QurbanBloc>().add(
                DeleteQurbanParticipant(participantId),
              );
              context.pop();
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showPaymentOptions(
    BuildContext context,
    QurbanParticipant participant,
    QurbanPayment payment,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Pembayaran'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(
                  '/qurban/payment/edit',
                  extra: QurbanPaymentFormArgs(
                    participant: participant,
                    payment: payment,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Hapus Pembayaran',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeletePayment(context, payment.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePayment(BuildContext context, int? paymentId) {
    if (paymentId == null) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Pembayaran?'),
        content: const Text('Transaksi kas terkait juga akan ikut dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<QurbanBloc>().add(DeleteQurbanPayment(paymentId));
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final QurbanSummary summary;

  const _SummaryHeader({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QurbanHeroMetric(
            label: 'Terkumpul',
            value: _currency.format(summary.totalCollected),
            helper: 'Target ${_currency.format(summary.totalTarget)}',
            icon: Icons.savings_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Sisa',
                  value: _currency.format(summary.totalRemaining),
                  icon: Icons.pending_actions_rounded,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryCard(
                  label: 'Peserta',
                  value: summary.participantCount.toString(),
                  icon: Icons.groups_rounded,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Lunas',
                  value: summary.paidOffCount.toString(),
                  icon: Icons.verified_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryCard(
                  label: 'Tunggakan',
                  value: summary.overdueCount.toString(),
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QurbanHeroMetric extends StatelessWidget {
  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;

  const _QurbanHeroMetric({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.76),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  helper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilter extends StatelessWidget {
  final TextEditingController controller;
  final QurbanLoaded state;
  final ValueChanged<String> onChanged;
  final ValueChanged<QurbanProgressStatus?> onStatusChanged;

  const _SearchAndFilter({
    required this.controller,
    required this.state,
    required this.onChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Cari peserta',
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Semua'),
                    selected: state.statusFilter == null,
                    onSelected: (_) => onStatusChanged(null),
                  ),
                ),
                ...QurbanProgressStatus.values.map(
                  (status) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_statusLabel(status)),
                      selected: state.statusFilter == status,
                      onSelected: (_) => onStatusChanged(status),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final QurbanParticipantProgress progress;
  final VoidCallback onTap;

  const _ParticipantTile({required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final participant = progress.participant;
    final progressValue = progress.targetAmount <= 0
        ? 0.0
        : (progress.paidAmount / progress.targetAmount).clamp(0.0, 1.0);
    final statusColor = _statusColor(progress.status);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.1),
                foregroundColor: statusColor,
                child: Text(participant.name[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            participant.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        _StatusBadge(status: progress.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_currency.format(progress.paidAmount)} / '
                      '${_currency.format(progress.targetAmount)}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: progressValue,
                        backgroundColor: statusColor.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(statusColor),
                      ),
                    ),
                    if (participant.syncStatus != SyncStatus.synced) ...[
                      const SizedBox(height: 8),
                      const AppStatusPill(
                        label: 'BELUM SYNC',
                        icon: Icons.cloud_upload_outlined,
                        color: AppColors.gold,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantDetailCard extends StatelessWidget {
  final QurbanParticipantProgress progress;

  const _ParticipantDetailCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final participant = progress.participant;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  participant.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _StatusBadge(status: progress.status),
            ],
          ),
          if (participant.phone != null) Text(participant.phone!),
          if (participant.address != null) Text(participant.address!),
          if (participant.notes != null) Text(participant.notes!),
          const Divider(height: 24),
          _DetailAmountRow(
            label: 'Cicilan per bulan',
            amount: participant.monthlyAmount,
          ),
          _DetailAmountRow(label: 'Target', amount: progress.targetAmount),
          _DetailAmountRow(label: 'Terbayar', amount: progress.paidAmount),
          _DetailAmountRow(label: 'Sisa', amount: progress.remainingAmount),
          if (progress.arrearsAmount > 0)
            _DetailAmountRow(
              label: 'Tunggakan',
              amount: progress.arrearsAmount,
            ),
        ],
      ),
    );
  }
}

class _DetailAmountRow extends StatelessWidget {
  final String label;
  final double amount;

  const _DetailAmountRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _currency.format(amount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PaymentTimeline extends StatelessWidget {
  final QurbanParticipantProgress progress;

  const _PaymentTimeline({required this.progress});

  @override
  Widget build(BuildContext context) {
    final participant = progress.participant;
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    return Column(
      children: List.generate(participant.totalMonths, (index) {
        final dueMonth = DateTime(
          participant.startMonth.year,
          participant.startMonth.month + index,
        );
        final cumulativeDue = participant.monthlyAmount * (index + 1);
        final isPaid = progress.paidAmount >= cumulativeDue;
        final isDue = !dueMonth.isAfter(currentMonth);
        final color = isPaid
            ? AppColors.primary
            : isDue
            ? AppColors.gold
            : AppColors.muted;
        final icon = isPaid
            ? Icons.check_circle
            : isDue
            ? Icons.schedule
            : Icons.radio_button_unchecked;

        return ListTile(
          dense: true,
          leading: Icon(icon, color: color),
          title: Text('Bulan ${index + 1}'),
          subtitle: Text(DateFormat('MMMM yyyy', 'id_ID').format(dueMonth)),
          trailing: Text(_currency.format(participant.monthlyAmount)),
        );
      }),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final QurbanProgressStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

List<QurbanPayment> _sortedPayments(List<QurbanPayment> payments) {
  final sorted = [...payments];
  sorted.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
  return sorted;
}

bool _canManageQurban(AuthState state) {
  if (state is Authenticated) return state.role.canManageQurban;
  if (state is AuthOffline) return state.role.canManageQurban;
  return false;
}

String _statusLabel(QurbanProgressStatus status) {
  switch (status) {
    case QurbanProgressStatus.notStarted:
      return 'Belum mulai';
    case QurbanProgressStatus.current:
      return 'Lancar';
    case QurbanProgressStatus.overdue:
      return 'Menunggak';
    case QurbanProgressStatus.paidOff:
      return 'Lunas';
    case QurbanProgressStatus.overpaid:
      return 'Lebih bayar';
  }
}

Color _statusColor(QurbanProgressStatus status) {
  switch (status) {
    case QurbanProgressStatus.notStarted:
      return AppColors.muted;
    case QurbanProgressStatus.current:
      return AppColors.teal;
    case QurbanProgressStatus.overdue:
      return AppColors.gold;
    case QurbanProgressStatus.paidOff:
      return AppColors.primary;
    case QurbanProgressStatus.overpaid:
      return const Color(0xFF7C4D9E);
  }
}
