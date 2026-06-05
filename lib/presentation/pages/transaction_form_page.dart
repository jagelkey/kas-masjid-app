import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/blocs/transaction/transaction_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

class TransactionFormPage extends StatefulWidget {
  final Transaction? transaction;
  const TransactionFormPage({super.key, this.transaction});

  @override
  State<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends State<TransactionFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TransactionType _type;
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;
  String? _selectedCategory;
  late DateTime _selectedDate;
  List<String> _proofPaths = [];
  List<String> _proofUrls = [];
  bool _isSubmitting = false;

  final List<String> _incomeCategories = [
    'Infaq',
    'Sedekah',
    'Donasi',
    'Wakaf',
    'Lainnya',
  ];
  final List<String> _expenseCategories = [
    'Operasional',
    'Listrik & Air',
    'Kegiatan',
    'Perawatan',
    'Honor',
    'Lainnya',
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _type = t?.type ?? TransactionType.income;
    _amountController = TextEditingController(
      text: t?.amount.toString().replaceAll('.0', '') ?? '',
    );
    _descriptionController = TextEditingController(text: t?.description ?? '');
    _selectedCategory = t?.category;
    final now = DateTime.now();
    _selectedDate = t?.date ?? DateTime(now.year, now.month, now.day);
    _proofPaths = t?.proofPaths != null ? List.from(t!.proofPaths) : [];
    _proofUrls = t?.proofUrls != null ? List.from(t!.proofUrls) : [];
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<bool> _checkPermission(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) {
      return true;
    }

    // Special case for Android 13+ gallery permissions
    if (Platform.isAndroid &&
        permission == Permission.storage &&
        await Permission.photos.status.isGranted) {
      return true;
    }

    final result = await permission.request();
    if (result.isGranted) {
      return true;
    }

    if (Platform.isAndroid &&
        permission == Permission.storage &&
        await Permission.photos.request().isGranted) {
      return true;
    }

    if (result.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Izin Diperlukan'),
            content: const Text(
              'Aplikasi membutuhkan izin akses kamera/galeri untuk mengupload bukti transaksi. Silakan aktifkan di pengaturan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );
      }
    }
    return false;
  }

  Future<void> _pickImage(ImageSource source) async {
    final totalImages = _proofPaths.length + _proofUrls.length;
    if (totalImages >= 10) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Maksimal 10 foto')));
      }
      return;
    }

    if (!kIsWeb) {
      final permission = source == ImageSource.camera
          ? Permission.camera
          : Permission.storage;

      if (!await _checkPermission(permission)) {
        return;
      }
    }

    try {
      final picker = ImagePicker();
      // Allow multiple selection only for Gallery
      if (source == ImageSource.gallery) {
        final pickedFiles = await picker.pickMultiImage(
          imageQuality: 70,
          maxWidth: 1024,
        );
        if (pickedFiles.isNotEmpty) {
          for (var picked in pickedFiles) {
            if ((_proofPaths.length + _proofUrls.length) >= 10) break;
            if (kIsWeb) {
              setState(() {
                _proofPaths.add(picked.path);
              });
            } else {
              await _saveImageLocally(picked.path);
            }
          }
        }
      } else {
        final picked = await picker.pickImage(
          source: source,
          imageQuality: 70,
          maxWidth: 1024,
        );
        if (picked != null) {
          if (kIsWeb) {
            setState(() {
              _proofPaths.add(picked.path);
            });
          } else {
            await _saveImageLocally(picked.path);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengambil foto: $e'),
            action: SnackBarAction(
              label: 'Coba Lagi',
              onPressed: () => _pickImage(source),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveImageLocally(String sourcePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName =
          'proof_${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
      final localImage = File('${appDir.path}/transaction_proofs/$fileName');

      if (!await localImage.parent.exists()) {
        await localImage.parent.create(recursive: true);
      }

      await File(sourcePath).copy(localImage.path);

      setState(() {
        _proofPaths.add(localImage.path);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menyimpan gambar: $e')));
      }
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeri'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProofImagesList() {
    final totalImages = _proofUrls.length + _proofPaths.length;
    if (totalImages == 0) {
      return GestureDetector(
        onTap: () => _showImageSourceActionSheet(context),
        child: Container(
          color: Colors.transparent, // Ensure hit test works
          width: double.infinity,
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.camera_alt, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Upload Bukti (Opsional)',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: totalImages + 1, // +1 for Add button
      itemBuilder: (context, index) {
        if (index == totalImages) {
          // Add Button at the end
          if (totalImages >= 10) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => _showImageSourceActionSheet(context),
            child: Container(
              width: 100,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: const Icon(Icons.add, size: 30, color: Colors.grey),
            ),
          );
        }

        Widget imageWidget;
        bool isRemote = index < _proofUrls.length;

        if (isRemote) {
          final url = _proofUrls[index];
          imageWidget = Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              );
            },
          );
        } else {
          final localIndex = index - _proofUrls.length;
          final path = _proofPaths[localIndex];
          if (kIsWeb) {
            imageWidget = Image.network(
              path,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                );
              },
            );
          } else {
            final file = File(path);
            final fileExists = file.existsSync();
            imageWidget = fileExists
                ? Image.file(file, fit: BoxFit.cover)
                : const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  );
          }
        }

        return Stack(
          children: [
            Container(
              width: 120,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageWidget,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isRemote) {
                      _proofUrls.removeAt(index);
                    } else {
                      _proofPaths.removeAt(index - _proofUrls.length);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TransactionBloc, TransactionState>(
      listener: (context, state) {
        if (state is TransactionOperationSuccess) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.operationMessage)));
          if (mounted) context.pop();
        } else if (state is TransactionOperationFailure) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.operationMessage)));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.transaction == null ? 'Tambah Transaksi' : 'Edit Transaksi',
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Type Selector
                SegmentedButton<TransactionType>(
                  segments: const [
                    ButtonSegment(
                      value: TransactionType.income,
                      label: Text('Pemasukan'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                    ButtonSegment(
                      value: TransactionType.expense,
                      label: Text('Pengeluaran'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (Set<TransactionType> newSelection) {
                    setState(() {
                      _type = newSelection.first;
                      _selectedCategory = null;
                    });
                  },
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Nominal (Rp)',
                    border: OutlineInputBorder(),
                    prefixText: 'Rp ',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nominal wajib diisi';
                    }
                    final parsedAmount = double.tryParse(
                      value.replaceAll(',', '.'),
                    );
                    if (parsedAmount == null) {
                      return 'Format nominal salah';
                    }
                    if (parsedAmount <= 0) {
                      return 'Nominal harus lebih dari 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Category
                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedCategory),
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items:
                      (_type == TransactionType.income
                              ? _incomeCategories
                              : _expenseCategories)
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCategory = value;
                      });
                    }
                  },
                  validator: (value) => value == null ? 'Pilih kategori' : null,
                ),
                const SizedBox(height: 16),

                // Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tanggal',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan (Opsional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Proof Image
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildProofImagesList(),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_proofPaths.length + _proofUrls.length} / 10 foto dipilih',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),

                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _submitForm,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.transaction == null
                                ? 'Simpan Transaksi'
                                : 'Update Transaksi',
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

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      // Robust parsing: replace comma with dot for decimal compatibility
      final cleanAmountText = _amountController.text.replaceAll(',', '.');
      final amount = double.tryParse(cleanAmountText);

      if (amount == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Format nominal tidak valid')),
        );
        return;
      }
      setState(() => _isSubmitting = true);

      final transaction = Transaction(
        id: widget.transaction?.id,
        remoteId: widget.transaction?.remoteId ?? const Uuid().v4(),
        type: _type,
        amount: amount,
        category: _selectedCategory!,
        description: _descriptionController.text,
        date: _selectedDate,
        proofPaths: _proofPaths, // Pass the list of local paths
        proofUrls: _proofUrls,
        syncStatus: widget.transaction?.remoteId != null
            ? SyncStatus.pendingUpdate
            : SyncStatus.pendingCreate,
      );

      if (widget.transaction == null) {
        context.read<TransactionBloc>().add(AddTransactionEvent(transaction));
      } else {
        context.read<TransactionBloc>().add(
          UpdateTransactionEvent(transaction),
        );
      }
      // context.pop(); // Di-handle oleh BlocListener
    }
  }
}
