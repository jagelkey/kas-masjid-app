import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/blocs/qurban/qurban_bloc.dart';

class QurbanPackageSettingsPage extends StatelessWidget {
  const QurbanPackageSettingsPage({super.key});

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
      child: Scaffold(
        appBar: AppBar(title: const Text('Paket Cicilan Qurban')),
        body: BlocBuilder<QurbanBloc, QurbanState>(
          builder: (context, state) {
            if (state is! QurbanLoaded) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.packages.isEmpty) {
              return const Center(child: Text('Belum ada paket cicilan'));
            }
            return ListView.separated(
              itemCount: state.packages.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final package = state.packages[index];
                return ListTile(
                  leading: const Icon(Icons.savings_outlined),
                  title: Text(package.name),
                  subtitle: Text(
                    '${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(package.monthlyAmount)}/bulan',
                  ),
                  trailing: package.syncStatus == SyncStatus.synced
                      ? const Icon(Icons.chevron_right)
                      : const Icon(Icons.cloud_upload_outlined),
                  onTap: () => _showPackageDialog(context, package: package),
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showPackageDialog(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showPackageDialog(BuildContext context, {QurbanPackage? package}) {
    final nameController = TextEditingController(text: package?.name ?? '');
    final amountController = TextEditingController(
      text: package?.monthlyAmount.toStringAsFixed(0) ?? '',
    );
    var isActive = package?.isActive ?? true;
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(package == null ? 'Tambah Paket' : 'Edit Paket'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nama paket'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Nominal per bulan',
                    prefixText: 'Rp ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  title: const Text('Aktif'),
                  onChanged: (value) => setState(() => isActive = value),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (package?.id != null)
                TextButton(
                  onPressed: () {
                    // Show confirmation dialog before deleting
                    showDialog(
                      context: dialogContext,
                      builder: (confirmCtx) => AlertDialog(
                        title: const Text('Hapus Paket?'),
                        content: Text(
                          'Paket "${package!.name}" akan dihapus. '
                          'Data peserta yang sudah ada tidak terpengaruh.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmCtx),
                            child: const Text('Batal'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(confirmCtx);
                              Navigator.pop(dialogContext);
                              context.read<QurbanBloc>().add(
                                DeleteQurbanPackage(package.id!),
                              );
                            },
                            child: const Text('Hapus'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Hapus'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text);
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setState(
                      () => errorText = 'Nama paket tidak boleh kosong.',
                    );
                    return;
                  }
                  if (amount == null || amount <= 0) {
                    setState(() => errorText = 'Nominal harus lebih dari 0.');
                    return;
                  }
                  if (amount > 50000000) {
                    setState(
                      () => errorText = 'Nominal maksimal Rp 50.000.000.',
                    );
                    return;
                  }

                  final next = QurbanPackage(
                    id: package?.id,
                    remoteId: package?.remoteId,
                    name: nameController.text.trim(),
                    monthlyAmount: amount,
                    isActive: isActive,
                    syncStatus: package?.syncStatus ?? SyncStatus.pendingCreate,
                  );
                  Navigator.pop(dialogContext);
                  if (package == null) {
                    context.read<QurbanBloc>().add(AddQurbanPackage(next));
                  } else {
                    context.read<QurbanBloc>().add(UpdateQurbanPackage(next));
                  }
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }
}
