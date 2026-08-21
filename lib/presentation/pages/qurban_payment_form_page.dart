import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/blocs/qurban/qurban_bloc.dart';

class QurbanPaymentFormArgs {
  final QurbanParticipant participant;
  final QurbanPayment? payment;

  const QurbanPaymentFormArgs({required this.participant, this.payment});
}

class QurbanPaymentFormPage extends StatefulWidget {
  final QurbanParticipant participant;
  final QurbanPayment? payment;

  const QurbanPaymentFormPage({
    super.key,
    required this.participant,
    this.payment,
  });

  @override
  State<QurbanPaymentFormPage> createState() => _QurbanPaymentFormPageState();
}

class _QurbanPaymentFormPageState extends State<QurbanPaymentFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late DateTime _paymentDate;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final payment = widget.payment;
    _amountController = TextEditingController(
      text: (payment?.amount ?? widget.participant.monthlyAmount)
          .toStringAsFixed(0),
    );
    _noteController = TextEditingController(text: payment?.note ?? '');
    final now = DateTime.now();
    _paymentDate =
        payment?.paymentDate ?? DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
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
            widget.payment == null ? 'Tambah Pembayaran' : 'Edit Pembayaran',
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(widget.participant.name),
                    subtitle: Text(
                      'Cicilan ${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(widget.participant.monthlyAmount)}/bulan',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Nominal pembayaran',
                    prefixText: 'Rp ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final amount = double.tryParse(value ?? '');
                    if (amount == null || amount <= 0) {
                      return 'Nominal wajib lebih dari 0';
                    }
                    if (amount > 1000000000) {
                      return 'Nominal terlalu besar, periksa kembali angkanya';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickPaymentDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tanggal pembayaran',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(
                      DateFormat('dd MMMM yyyy', 'id_ID').format(_paymentDate),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _noteController,
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
                            widget.payment == null
                                ? 'Simpan Pembayaran'
                                : 'Update Pembayaran',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _paymentDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitted = true);

    final payment = QurbanPayment(
      id: widget.payment?.id,
      remoteId: widget.payment?.remoteId,
      participantId: widget.participant.id!,
      transactionId: widget.payment?.transactionId,
      amount: double.parse(_amountController.text),
      paymentDate: _paymentDate,
      note: _noteController.text.trim(),
      syncStatus: widget.payment?.syncStatus ?? SyncStatus.pendingCreate,
    );

    if (widget.payment == null) {
      context.read<QurbanBloc>().add(AddQurbanPayment(payment));
    } else {
      context.read<QurbanBloc>().add(UpdateQurbanPayment(payment));
    }
  }
}
