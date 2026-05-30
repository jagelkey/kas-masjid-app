import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masjid_app/core/di/injection.dart';
import 'package:masjid_app/core/services/pdf_service.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/blocs/profile/profile_bloc.dart';
import 'package:masjid_app/presentation/blocs/transaction/transaction_bloc.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class TransactionListPage extends StatelessWidget {
  const TransactionListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Kas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () {
              final state = context.read<TransactionBloc>().state;
              if (state is TransactionLoaded) {
                final transactions = state.filteredTransactions;

                // Determine period text
                String period = 'Semua Transaksi';
                if (state.filterDateRange != null) {
                  final start = DateFormat(
                    'dd MMM yyyy',
                    'id',
                  ).format(state.filterDateRange!.start);
                  final end = DateFormat(
                    'dd MMM yyyy',
                    'id',
                  ).format(state.filterDateRange!.end);
                  period = '$start - $end';
                } else if (state.filterType != null) {
                  period =
                      'Filter: ${state.filterType == TransactionType.income ? 'Pemasukan' : 'Pengeluaran'}';
                } else if (state.filterCategory != null) {
                  period = 'Kategori: ${state.filterCategory}';
                }

                // Calculate totals for the report based on the visible transactions
                double totalIncome = 0;
                double totalExpense = 0;
                for (final t in transactions) {
                  if (t.type == TransactionType.income) {
                    totalIncome += t.amount;
                  } else {
                    totalExpense += t.amount;
                  }
                }

                final profileState = context.read<ProfileBloc>().state;
                final profile = profileState is ProfileLoaded
                    ? profileState.profile
                    : null;

                getIt<PdfService>().generateReport(
                  transactions: transactions,
                  period: period,
                  totalIncome: totalIncome,
                  totalExpense: totalExpense,
                  profile: profile,
                  title: 'Laporan Transaksi',
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              _showFilterDialog(context);
            },
          ),
        ],
      ),
      body: BlocBuilder<TransactionBloc, TransactionState>(
        builder: (context, state) {
          if (state is TransactionLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is TransactionLoaded) {
            final transactions =
                state.filteredTransactions; // Use filtered list

            if (transactions.isEmpty) {
              return const Center(
                child: Text('Belum ada transaksi (sesuai filter)'),
              );
            }
            return ListView.separated(
              itemCount: transactions.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final transaction = transactions[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: transaction.type == TransactionType.income
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    child: Icon(
                      transaction.type == TransactionType.income
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      color: transaction.type == TransactionType.income
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  title: Text(transaction.category),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (transaction.description != null &&
                          transaction.description!.isNotEmpty)
                        Text(transaction.description!),
                      Text(DateFormat('dd MMM yyyy').format(transaction.date)),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        NumberFormat.currency(
                          locale: 'id',
                          symbol: 'Rp ',
                        ).format(transaction.amount),
                        style: TextStyle(
                          color: transaction.type == TransactionType.income
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (transaction.syncStatus != SyncStatus.synced)
                        const Icon(
                          Icons.cloud_upload_outlined,
                          size: 12,
                          color: Colors.grey,
                        ),
                    ],
                  ),
                  onTap: () {
                    // Show details or edit
                    final authState = context.read<AuthBloc>().state;
                    bool canManage = false;
                    if (authState is Authenticated) {
                      canManage = authState.role.canManageTransactions;
                    } else if (authState is AuthOffline) {
                      canManage = authState.role.canManageTransactions;
                    }

                    _showTransactionOptions(context, transaction, canManage);
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

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return _FilterDialog(bloc: context.read<TransactionBloc>());
      },
    );
  }

  void _showTransactionOptions(
    BuildContext context,
    Transaction transaction,
    bool canManage,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (canManage)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Edit Transaksi'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/transactions/edit', extra: transaction);
                },
              ),
            if (transaction.proofUrls.isNotEmpty ||
                transaction.proofPaths.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.image, color: Colors.green),
                title: const Text('Lihat Bukti Transaksi'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showProofDialog(context, transaction);
                },
              ),
            if (canManage)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Hapus Transaksi',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, transaction);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showProofDialog(BuildContext context, Transaction transaction) {
    showDialog(
      context: context,
      builder: (ctx) => _ProofGalleryDialog(transaction: transaction),
    );
  }

  void _confirmDelete(BuildContext context, Transaction transaction) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi'),
        content: const Text('Apakah Anda yakin ingin menghapus transaksi ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              if (transaction.id != null) {
                context.read<TransactionBloc>().add(
                  DeleteTransactionEvent(transaction.id!),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _FilterDialog extends StatefulWidget {
  final TransactionBloc bloc;
  const _FilterDialog({required this.bloc});

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  DateTimeRange? _selectedDateRange;
  TransactionType? _selectedType;

  @override
  void initState() {
    super.initState();
    final state = widget.bloc.state;
    if (state is TransactionLoaded) {
      _selectedDateRange = state.filterDateRange;
      _selectedType = state.filterType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter Transaksi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Rentang Tanggal'),
            subtitle: Text(
              _selectedDateRange == null
                  ? 'Semua Waktu'
                  : '${DateFormat('dd/MM/yy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yy').format(_selectedDateRange!.end)}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                initialDateRange: _selectedDateRange,
              );
              if (picked != null) {
                setState(() {
                  _selectedDateRange = picked;
                });
              }
            },
          ),
          DropdownButtonFormField<TransactionType>(
            decoration: const InputDecoration(labelText: 'Tipe Transaksi'),
            key: ValueKey(_selectedType),
            initialValue: _selectedType,
            items: const [
              DropdownMenuItem(value: null, child: Text('Semua')),
              DropdownMenuItem(
                value: TransactionType.income,
                child: Text('Pemasukan'),
              ),
              DropdownMenuItem(
                value: TransactionType.expense,
                child: Text('Pengeluaran'),
              ),
            ],
            onChanged: (val) {
              setState(() {
                _selectedType = val;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Reset filters
            context.read<TransactionBloc>().add(
              const ApplyFilterEvent(
                dateRange: null,
                type: null,
                category: null,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('Reset', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () {
            context.read<TransactionBloc>().add(
              ApplyFilterEvent(
                dateRange: _selectedDateRange,
                type: _selectedType,
                category:
                    null, // Assuming category filter is not in this simple dialog yet or handled separately
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('Terapkan'),
        ),
      ],
    );
  }
}

class _ProofGalleryDialog extends StatefulWidget {
  final Transaction transaction;
  const _ProofGalleryDialog({required this.transaction});

  @override
  State<_ProofGalleryDialog> createState() => _ProofGalleryDialogState();
}

class _ProofGalleryDialogState extends State<_ProofGalleryDialog> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final total =
        widget.transaction.proofUrls.length +
        widget.transaction.proofPaths.length;
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxHeight: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bukti Transaksi',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: PageView.builder(
                itemCount: total,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  if (index < widget.transaction.proofUrls.length) {
                    return Image.network(
                      widget.transaction.proofUrls[index],
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 50,
                            color: Colors.grey,
                          ),
                        );
                      },
                    );
                  } else {
                    final localIndex =
                        index - widget.transaction.proofUrls.length;
                    if (kIsWeb) {
                      return Image.network(
                        widget.transaction.proofPaths[localIndex],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 50,
                              color: Colors.grey,
                            ),
                          );
                        },
                      );
                    } else {
                      return Image.file(
                        File(widget.transaction.proofPaths[localIndex]),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 50,
                              color: Colors.grey,
                            ),
                          );
                        },
                      );
                    }
                  }
                },
              ),
            ),
            if (total > 1) ...[
              const SizedBox(height: 8),
              Text('${_currentIndex + 1} / $total'),
            ],
          ],
        ),
      ),
    );
  }
}
