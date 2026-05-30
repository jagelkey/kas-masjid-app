import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain_status;
import 'package:masjid_app/domain/entities/activity.dart';
import 'package:masjid_app/presentation/blocs/activity/activity_bloc.dart';
import 'package:intl/intl.dart';

class ActivityFormPage extends StatefulWidget {
  final Activity? activity;
  const ActivityFormPage({super.key, this.activity});

  @override
  State<ActivityFormPage> createState() => _ActivityFormPageState();
}

class _ActivityFormPageState extends State<ActivityFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _picController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late String _selectedType;

  final List<String> _types = [
    'Pengajian',
    'Sholat Jumat',
    'Kajian Rutin',
    'Acara Khusus',
    'Lainnya',
  ];

  @override
  void initState() {
    super.initState();
    final activity = widget.activity;
    _titleController = TextEditingController(text: activity?.title ?? '');
    _descriptionController = TextEditingController(
      text: activity?.description ?? '',
    );
    _picController = TextEditingController(text: activity?.picName ?? '');

    if (activity != null) {
      _selectedDate = activity.date;
      _selectedTime = TimeOfDay.fromDateTime(activity.date);
      _selectedType = _types.contains(activity.type)
          ? activity.type
          : 'Pengajian';
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
      _selectedType = 'Pengajian';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _picController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.activity == null ? 'Tambah Kegiatan' : 'Edit Kegiatan',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Nama Kegiatan'),
                validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedType),
                isExpanded: true,
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: 'Jenis Kegiatan'),
                items: _types
                    .map(
                      (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedType = value);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) setState(() => _selectedDate = date);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tanggal',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          DateFormat('dd MMM yyyy').format(_selectedDate),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime,
                        );
                        if (time != null) setState(() => _selectedTime = time);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Jam',
                          suffixIcon: Icon(Icons.access_time),
                        ),
                        child: Text(_selectedTime.format(context)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _picController,
                decoration: const InputDecoration(
                  labelText: 'Penanggung Jawab',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Deskripsi'),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(
                    widget.activity == null
                        ? 'Simpan Kegiatan'
                        : 'Update Kegiatan',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      final activity = Activity(
        id: widget.activity?.id,
        remoteId: widget.activity?.remoteId,
        syncStatus: widget.activity?.syncStatus ?? domain_status.SyncStatus.pendingCreate,
        title: _titleController.text,
        type: _selectedType,
        date: dateTime,
        picName: _picController.text,
        description: _descriptionController.text,
      );

      if (widget.activity == null) {
        context.read<ActivityBloc>().add(AddActivityEvent(activity));
      } else {
        context.read<ActivityBloc>().add(UpdateActivityEvent(activity));
      }
      context.pop();
    }
  }
}
