import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/blocs/qurban/qurban_bloc.dart';

class QurbanParticipantFormPage extends StatefulWidget {
  final QurbanParticipant? participant;

  const QurbanParticipantFormPage({super.key, this.participant});

  @override
  State<QurbanParticipantFormPage> createState() =>
      _QurbanParticipantFormPageState();
}

class _QurbanParticipantFormPageState extends State<QurbanParticipantFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  late final TextEditingController _amountController;
  late DateTime _startMonth;
  int? _selectedPackageId;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final participant = widget.participant;
    _nameController = TextEditingController(text: participant?.name ?? '');
    _phoneController = TextEditingController(text: participant?.phone ?? '');
    _addressController = TextEditingController(
      text: participant?.address ?? '',
    );
    _notesController = TextEditingController(text: participant?.notes ?? '');
    _amountController = TextEditingController(
      text: participant?.monthlyAmount.toStringAsFixed(0) ?? '250000',
    );
    final now = DateTime.now();
    _startMonth = participant?.startMonth ?? DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<QurbanBloc, QurbanState>(
      listener: (context, state) {
        if (state is QurbanOperationSuccess && _submitted) {
          Navigator.pop(context);
        } else if (state is QurbanOperationFailure) {
          setState(() => _submitted = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.participant == null
                ? 'Tambah Peserta Qurban'
                : 'Edit Peserta Qurban',
          ),
        ),
        body: BlocBuilder<QurbanBloc, QurbanState>(
          builder: (context, state) {
            final packages = state is QurbanLoaded
                ? state.packages.where((p) => p.isActive).toList()
                : const <QurbanPackage>[];
            _syncSelectedPackage(packages);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama peserta',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nama peserta wajib diisi';
                        }
                        if (value.trim().length < 3) {
                          return 'Nama minimal 3 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Nomor HP',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Alamat',
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      initialValue: _selectedPackageId,
                      decoration: const InputDecoration(
                        labelText: 'Paket cicilan',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      items: [
                        ...packages.map(
                          (package) => DropdownMenuItem<int?>(
                            value: package.id,
                            child: Text(
                              '${package.name} - '
                              '${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(package.monthlyAmount)}/bln',
                            ),
                          ),
                        ),
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Nominal custom'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPackageId = value;
                          QurbanPackage? selected;
                          for (final package in packages) {
                            if (package.id == value) {
                              selected = package;
                              break;
                            }
                          }
                          if (selected != null) {
                            _amountController.text = selected.monthlyAmount
                                .toStringAsFixed(0);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'Nominal cicilan per bulan',
                        prefixText: 'Rp ',
                        prefixIcon: Icon(Icons.savings_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        final amount = double.tryParse(value ?? '');
                        if (amount == null || amount <= 0) {
                          return 'Nominal wajib lebih dari 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickStartMonth,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Bulan mulai',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                        child: Text(
                          DateFormat('MMMM yyyy', 'id_ID').format(_startMonth),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Catatan',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _submitted ? null : _submit,
                        child: _submitted
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.participant == null
                                    ? 'Simpan Peserta'
                                    : 'Update Peserta',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _syncSelectedPackage(List<QurbanPackage> packages) {
    if (_selectedPackageId != null || widget.participant != null) return;
    final currentAmount = double.tryParse(_amountController.text);
    final match = packages.where((p) => p.monthlyAmount == currentAmount);
    if (match.isNotEmpty) {
      _selectedPackageId = match.first.id;
    }
  }

  Future<void> _pickStartMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Pilih bulan mulai',
    );
    if (picked != null) {
      setState(() => _startMonth = DateTime(picked.year, picked.month));
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitted = true);

    final participant = QurbanParticipant(
      id: widget.participant?.id,
      remoteId: widget.participant?.remoteId,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      notes: _notesController.text.trim(),
      startMonth: DateTime(_startMonth.year, _startMonth.month),
      monthlyAmount: double.parse(_amountController.text),
      totalMonths: widget.participant?.totalMonths ?? 10,
      syncStatus: widget.participant?.syncStatus ?? SyncStatus.pendingCreate,
    );

    if (widget.participant == null) {
      context.read<QurbanBloc>().add(AddQurbanParticipant(participant));
    } else {
      context.read<QurbanBloc>().add(UpdateQurbanParticipant(participant));
    }
  }
}
