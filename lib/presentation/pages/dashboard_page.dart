import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/core/theme/app_theme.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';
import 'package:masjid_app/presentation/blocs/transaction/transaction_bloc.dart';
import 'package:masjid_app/presentation/widgets/app_components.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          BlocBuilder<SyncCubit, SyncState>(
            builder: (context, state) {
              if (state.isSyncing) {
                return const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  tooltip: 'Sinkronisasi Data',
                  onPressed: () => context.read<SyncCubit>().forceSync(),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<TransactionBloc, TransactionState>(
        builder: (context, state) {
          return Column(
            children: [
              _buildConnectionBanners(context),
              Expanded(
                child: switch (state) {
                  TransactionLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  TransactionError() => AppEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Data belum bisa dimuat',
                    message: state.message,
                  ),
                  TransactionLoaded() => RefreshIndicator(
                    onRefresh: () => context.read<SyncCubit>().forceSync(),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBalancePanel(context, state),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  title: 'Pemasukan',
                                  amount: state.incomeThisMonth,
                                  color: AppColors.primary,
                                  icon: Icons.trending_up_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  title: 'Pengeluaran',
                                  amount: state.expenseThisMonth,
                                  color: AppColors.danger,
                                  icon: Icons.trending_down_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildIncomeExpenseChart(context, state),
                          const SizedBox(height: 16),
                          _buildExpenseInsight(context, state),
                          const SizedBox(height: 24),
                          AppSectionTitle(
                            title: 'Transaksi Terakhir',
                            trailing: TextButton.icon(
                              onPressed: () => context.go('/transactions'),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Semua'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildRecentTransactions(context, state),
                        ],
                      ),
                    ),
                  ),
                  _ => const AppEmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Belum ada data kas',
                  ),
                },
              ),
            ],
          );
        },
      ),
      floatingActionButton: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          var canAdd = false;
          if (authState is Authenticated) {
            canAdd = authState.role.canManageTransactions;
          } else if (authState is AuthOffline) {
            canAdd = authState.role.canManageTransactions;
          }

          if (!canAdd) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            onPressed: () => context.push('/transactions/add'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tambah'),
          );
        },
      ),
    );
  }

  Widget _buildConnectionBanners(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, authState) {
              if (authState is! AuthOffline) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: AppStatusBanner(
                  icon: Icons.wifi_off_rounded,
                  title: 'Mode offline',
                  message:
                      'Data tetap tersimpan di perangkat dan akan dikirim saat koneksi tersedia.',
                  tone: AppBannerTone.warning,
                ),
              );
            },
          ),
          BlocBuilder<SyncCubit, SyncState>(
            builder: (context, syncState) {
              if (syncState.isSuccess || syncState.errorMessages.isEmpty) {
                return const SizedBox.shrink();
              }
              return AppStatusBanner(
                icon: Icons.cloud_off_rounded,
                title: 'Sinkronisasi tertunda',
                message: syncState.errorMessages.first,
                tone: AppBannerTone.danger,
                onClose: () => context.read<SyncCubit>().clearError(),
                onTap: () => context.go('/settings/sync'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBalancePanel(BuildContext context, TransactionLoaded state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Total Saldo Kas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              ),
              BlocBuilder<SyncCubit, SyncState>(
                builder: (context, syncState) {
                  if (syncState.isSyncing) {
                    return const AppStatusPill(
                      label: 'SYNC',
                      icon: Icons.sync_rounded,
                      color: Colors.white,
                    );
                  }
                  if (!syncState.isSuccess) {
                    return const AppStatusPill(
                      label: 'ANTRI',
                      icon: Icons.cloud_queue_rounded,
                      color: AppColors.gold,
                    );
                  }
                  return const AppStatusPill(
                    label: 'ONLINE',
                    icon: Icons.cloud_done_rounded,
                    color: Color(0xFFB9F6D3),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              NumberFormat.currency(
                locale: 'id',
                symbol: 'Rp ',
                decimalDigits: 0,
              ).format(state.totalBalance),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('MMMM yyyy', 'id').format(DateTime.now()),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return AppMetricCard(
      title: title,
      value: NumberFormat.compactCurrency(
        locale: 'id',
        symbol: 'Rp',
        decimalDigits: 0,
      ).format(amount),
      icon: icon,
      color: color,
      caption: 'Bulan ini',
    );
  }

  Widget _buildIncomeExpenseChart(
    BuildContext context,
    TransactionLoaded state,
  ) {
    final income = state.incomeThisMonth < 0 ? 0.0 : state.incomeThisMonth;
    final expense = state.expenseThisMonth < 0 ? 0.0 : state.expenseThisMonth;
    final maxValue = income > expense ? income : expense;
    final maxY = maxValue <= 0 ? 100000.0 : maxValue * 1.2;

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
          const AppSectionTitle(title: 'Ringkasan Bulan Ini'),
          const SizedBox(height: 20),
          SizedBox(
            height: 168,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.ink,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final type = group.x == 0 ? 'Masuk' : 'Keluar';
                      return BarTooltipItem(
                        '$type\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: NumberFormat.compactCurrency(
                              locale: 'id',
                              symbol: 'Rp',
                              decimalDigits: 0,
                            ).format(rod.toY),
                            style: const TextStyle(
                              color: Color(0xFFFFD98A),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final label = value.toInt() == 0 ? 'Masuk' : 'Keluar';
                        return SideTitleWidget(
                          meta: meta,
                          space: 8,
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.muted),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barRods: [
                      BarChartRodData(
                        toY: income,
                        color: AppColors.primary,
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadii.md),
                        ),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 1,
                    barRods: [
                      BarChartRodData(
                        toY: expense,
                        color: AppColors.danger,
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadii.md),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseInsight(BuildContext context, TransactionLoaded state) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final endOfMonth = DateTime(now.year, now.month + 1);
    final totals = <String, double>{};

    for (final transaction in state.transactions) {
      if (transaction.type.name != 'expense') continue;
      if (transaction.date.isBefore(startOfMonth) ||
          !transaction.date.isBefore(endOfMonth)) {
        continue;
      }
      totals.update(
        transaction.category,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }

    final topCategories = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visible = topCategories.take(3).toList();
    final maxAmount = visible.isEmpty ? 1.0 : visible.first.value;

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
          const AppSectionTitle(title: 'Pengeluaran Terbesar'),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Text(
              'Belum ada pengeluaran bulan ini.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            )
          else
            ...visible.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          NumberFormat.compactCurrency(
                            locale: 'id',
                            symbol: 'Rp',
                            decimalDigits: 0,
                          ).format(entry.value),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: AppColors.danger),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: (entry.value / maxAmount).clamp(0.0, 1.0),
                        backgroundColor: AppColors.dangerSoft,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(
    BuildContext context,
    TransactionLoaded state,
  ) {
    final recent = state.transactions.take(5).toList();
    if (recent.isEmpty) {
      return const AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Belum ada transaksi',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.line),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recent.length,
        separatorBuilder: (context, index) => const Divider(indent: 70),
        itemBuilder: (context, index) {
          final transaction = recent[index];
          final isIncome = transaction.type.name == 'income';
          final color = isIncome ? AppColors.primary : AppColors.danger;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(
                isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: color,
              ),
            ),
            title: Text(
              transaction.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              DateFormat('dd MMM yyyy', 'id').format(transaction.date),
            ),
            trailing: Text(
              NumberFormat.compactCurrency(
                locale: 'id',
                symbol: 'Rp',
                decimalDigits: 0,
              ).format(transaction.amount),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        },
      ),
    );
  }
}
