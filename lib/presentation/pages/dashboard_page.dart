import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masjid_app/presentation/blocs/transaction/transaction_bloc.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Kas Masjid'),
        centerTitle: false,
        actions: [
          BlocBuilder<SyncCubit, SyncState>(
            builder: (context, state) {
              if (state.isSyncing) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.green,
                    ),
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Sinkronisasi Data',
                onPressed: () {
                  context.read<SyncCubit>().forceSync();
                },
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<TransactionBloc, TransactionState>(
        builder: (context, state) {
          return Column(
            children: [
              // Offline Indicator
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, authState) {
                  if (authState is AuthOffline) {
                    return Container(
                      width: double.infinity,
                      color: Colors.orange.shade100,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_off,
                            size: 16,
                            color: Colors.orange.shade900,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mode Offline (Admin Lokal)',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              // Sync Error Indicator
              BlocBuilder<SyncCubit, SyncState>(
                builder: (context, syncState) {
                  if (!syncState.isSuccess &&
                      syncState.errorMessages.isNotEmpty) {
                    return Container(
                      width: double.infinity,
                      color: Colors.red.shade100,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.red.shade900,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              syncState.errorMessages.join(', '),
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.red.shade900,
                            ),
                            onPressed: () {
                              context.read<SyncCubit>().clearError();
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              Expanded(
                child: Builder(
                  builder: (context) {
                    if (state is TransactionLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is TransactionError) {
                      return Center(child: Text(state.message));
                    }
                    if (state is TransactionLoaded) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildBalanceCard(context, state),
                            const SizedBox(height: 16),
                            _buildIncomeExpenseChart(context, state),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    context,
                                    'Pemasukan',
                                    state.incomeThisMonth,
                                    Colors.green,
                                    Icons.arrow_downward,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildStatCard(
                                    context,
                                    'Pengeluaran',
                                    state.expenseThisMonth,
                                    Colors.red,
                                    Icons.arrow_upward,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Transaksi Terakhir',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    context.go('/transactions');
                                  },
                                  child: const Text('Lihat Semua'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildRecentTransactions(state),
                          ],
                        ),
                      );
                    }
                    return const Center(child: Text('Tidak ada data'));
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          bool canAdd = false;
          if (authState is Authenticated) {
            canAdd = authState.role.canManageTransactions;
          } else if (authState is AuthOffline) {
            canAdd = authState.role.canManageTransactions;
          }

          if (!canAdd) return const SizedBox.shrink();

          return FloatingActionButton(
            onPressed: () {
              context.push('/transactions/add');
            },
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }

  Widget _buildIncomeExpenseChart(
    BuildContext context,
    TransactionLoaded state,
  ) {
    // Pastikan nilai tidak negatif untuk grafik
    final income = state.incomeThisMonth < 0 ? 0.0 : state.incomeThisMonth;
    final expense = state.expenseThisMonth < 0 ? 0.0 : state.expenseThisMonth;

    final maxValue = income > expense ? income : expense;
    // Tambahkan buffer 20% agar grafik tidak mentok atas, minimal 100rb jika kosong
    final maxY = maxValue <= 0 ? 100000.0 : maxValue * 1.2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ringkasan Bulan Ini',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.blueGrey,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        String type = group.x == 0 ? 'Masuk' : 'Keluar';
                        return BarTooltipItem(
                          '$type\n',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          children: <TextSpan>[
                            TextSpan(
                              text: NumberFormat.compactCurrency(
                                locale: 'id',
                                symbol: 'Rp',
                              ).format(rod.toY),
                              style: const TextStyle(
                                color: Colors.yellow,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
                        getTitlesWidget: (double value, TitleMeta meta) {
                          const style = TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          );
                          Widget text;
                          switch (value.toInt()) {
                            case 0:
                              text = const Text('Masuk', style: style);
                              break;
                            case 1:
                              text = const Text('Keluar', style: style);
                              break;
                            default:
                              text = const Text('', style: style);
                              break;
                          }
                          return SideTitleWidget(
                            meta: meta,
                            space: 4,
                            child: text,
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
                          color: Colors.green,
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: expense,
                          color: Colors.red,
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
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
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, TransactionLoaded state) {
    return Card(
      elevation: 4,
      color: Theme.of(context).primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Total Saldo Kas',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              NumberFormat.currency(
                locale: 'id',
                symbol: 'Rp ',
              ).format(state.totalBalance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              NumberFormat.compactCurrency(
                locale: 'id',
                symbol: 'Rp',
              ).format(amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactions(TransactionLoaded state) {
    final recent = state.transactions.take(5).toList();
    if (recent.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Belum ada transaksi.'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recent.length,
      itemBuilder: (context, index) {
        final t = recent[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: t.type.name == 'income'
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            child: Icon(
              t.type.name == 'income'
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
              color: t.type.name == 'income' ? Colors.green : Colors.red,
            ),
          ),
          title: Text(t.category),
          subtitle: Text(DateFormat('dd MMM yyyy').format(t.date)),
          trailing: Text(
            NumberFormat.currency(locale: 'id', symbol: 'Rp ').format(t.amount),
            style: TextStyle(
              color: t.type.name == 'income' ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}
