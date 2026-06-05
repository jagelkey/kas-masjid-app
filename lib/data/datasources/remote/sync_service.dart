import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:get_it/get_it.dart';
import 'package:masjid_app/core/constants/env.dart';
import 'package:masjid_app/core/services/admin_user_service.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/local/auth_local_datasource.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

class SyncResult {
  final bool isSuccess;
  final List<String> errors;

  SyncResult({required this.isSuccess, this.errors = const []});

  factory SyncResult.success() => SyncResult(isSuccess: true);
  factory SyncResult.failure(List<String> errors) =>
      SyncResult(isSuccess: false, errors: errors);
}

@lazySingleton
class SyncService {
  // --- Audit Logs Sync ---

  Future<List<String>> _pushAuditLogs() async {
    final errors = <String>[];
    final pending =
        await (_db.select(_db.auditLogs)..where(
              (t) => t.syncStatus.equals(domain.SyncStatus.pendingCreate.index),
            ))
            .get();

    for (final log in pending) {
      try {
        final data = {
          'user_id': log.userId,
          'action': log.action,
          'table_name': log.targetTable,
          'record_id': log.recordId,
          'description': log.description,
          'created_at': log.createdAt.toIso8601String(),
        };

        final response = await _supabase!
            .from('audit_logs')
            .insert(data)
            .select()
            .single();

        await (_db.update(
          _db.auditLogs,
        )..where((r) => r.id.equals(log.id))).write(
          AuditLogsCompanion(
            remoteId: Value(response['id']),
            syncStatus: Value(domain.SyncStatus.synced),
          ),
        );
      } catch (e) {
        final msg = 'Gagal sync audit log ${log.id}: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }
    return errors;
  }

  Future<List<String>> _pullAuditLogs() async {
    final errors = <String>[];
    try {
      // Only pull logs if user is admin?
      // For now pull all. Pagination might be needed later.
      final response = await _supabase!
          .from('audit_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(100); // Limit to last 100 logs

      for (final remote in response) {
        final remoteId = remote['id'] as String;
        final localRows = await (_db.select(
          _db.auditLogs,
        )..where((t) => t.remoteId.equals(remoteId))).get();
        final local = localRows.isEmpty ? null : localRows.first;

        if (local == null) {
          await _db
              .into(_db.auditLogs)
              .insert(
                AuditLogsCompanion(
                  remoteId: Value(remoteId),
                  userId: Value(remote['user_id'] ?? ''),
                  action: Value(remote['action'] ?? ''),
                  targetTable: Value(remote['table_name']),
                  recordId: Value(remote['record_id']),
                  description: Value(remote['description']),
                  createdAt: Value(DateTime.parse(remote['created_at'])),
                  syncStatus: Value(domain.SyncStatus.synced),
                ),
              );
        }
      }
    } catch (e) {
      final msg = 'Gagal pull audit logs: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  final AppDatabase _db;
  late final SupabaseClient? _supabase;
  late final AdminUserService _adminUserService;
  StreamSubscription? _connectivitySubscription;

  bool _isSyncing = false;
  final StreamController<bool> _isSyncingController =
      StreamController<bool>.broadcast();
  Stream<bool> get isSyncing => _isSyncingController.stream;

  final StreamController<SyncResult> _syncResultController =
      StreamController<SyncResult>.broadcast();
  Stream<SyncResult> get onSyncResult => _syncResultController.stream;

  SyncService(this._db) {
    try {
      _supabase = Supabase.instance.client;
      _adminUserService = AdminUserService(_supabase);

      // Only listen to connectivity if Supabase is initialized
      if (_supabase != null) {
        _initConnectivityListener();
      }
    } catch (_) {
      _supabase = null;
      _adminUserService = const AdminUserService(null);
    }
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi)) {
        debugPrint('Connectivity restored. Triggering sync...');
        syncData();
      } else if (results.contains(ConnectivityResult.none)) {
        _isSyncingController.add(false); // Stop showing sync if offline
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _isSyncingController.close();
    _syncResultController.close();
  }

  Future<SyncResult> syncData() async {
    if (_isSyncing) {
      return SyncResult.failure(['Sync already in progress']);
    }

    // Check if Supabase is initialized properly
    if (!Env.hasValidConfig) {
      return SyncResult.failure(['Sync disabled (Supabase not configured)']);
    }

    try {
      if (_supabase == null || _supabase.auth.currentSession == null) {
        return SyncResult.failure([
          'Not authenticated for sync (Offline Mode)',
        ]);
      }
    } catch (_) {
      // Supabase probably not initialized
      return SyncResult.failure(['Sync disabled (Offline Mode)']);
    }

    _isSyncing = true;
    _isSyncingController.add(true);
    final allErrors = <String>[];

    try {
      // Core Data
      try {
        allErrors.addAll(await _pushTransactions());
        allErrors.addAll(await _pullTransactions());
        allErrors.addAll(await _pushQurbanPackages());
        allErrors.addAll(await _pullQurbanPackages());
        allErrors.addAll(await _pushQurbanParticipants());
        allErrors.addAll(await _pullQurbanParticipants());
        allErrors.addAll(await _pushQurbanPayments());
        allErrors.addAll(await _pullQurbanPayments());
        allErrors.addAll(await _pushActivities());
        allErrors.addAll(await _pullActivities());
        allErrors.addAll(await _pushMosqueProfile());
        allErrors.addAll(await _pullMosqueProfile());
      } catch (e) {
        allErrors.add('Sync System Error (Core): $e');
      }

      // Users Sync (Push & Pull)
      try {
        allErrors.addAll(await _pushUsers());
        allErrors.addAll(await _pullUsers());
      } catch (e) {
        allErrors.add('Sync System Error (Users): $e');
      }

      // Audit Logs
      try {
        allErrors.addAll(await _pushAuditLogs());
        allErrors.addAll(await _pullAuditLogs());
      } catch (e) {
        allErrors.add('Sync System Error (AuditLogs): $e');
      }
    } catch (e) {
      allErrors.add('Critical Sync Error: $e');
    } finally {
      _isSyncing = false;
      _isSyncingController.add(false);
    }

    final result = allErrors.isEmpty
        ? SyncResult.success()
        : SyncResult.failure(allErrors);
    _syncResultController.add(result);
    return result;
  }

  // --- Transactions Sync ---

  Future<List<String>> _pushTransactions() async {
    final errors = <String>[];
    final pending =
        await (_db.select(_db.transactions)..where(
              (t) => t.syncStatus.isNotValue(domain.SyncStatus.synced.index),
            ))
            .get();

    for (final t in pending) {
      try {
        if (t.syncStatus == domain.SyncStatus.pendingCreate) {
          List<String> uploadedUrls = [];
          bool hasUploadError = false;

          // Upload all local images
          for (final path in t.proofPaths) {
            try {
              final url = await _uploadFile(path, 'proofs');
              if (url != null) {
                uploadedUrls.add(url);
              } else {
                debugPrint(
                  'Warning: Skipping upload for $path (Returned null)',
                );
              }
            } catch (e) {
              debugPrint('Error uploading proof $path: $e');
              hasUploadError = true;
              // If it's a network error, we might want to stop to retry later.
              // But if the file is missing/inaccessible, we should continue.
              // For now, we'll mark that an error happened but let the loop continue.
            }
          }

          // If there was a network-like error during upload, we might want to skip this transaction
          // for now to retry later properly with all images.
          // But if we want the data to at least reflect on server, we proceed.

          final mergedUrls = {...t.proofUrls, ...uploadedUrls}.toList();

          // Safety: generate remoteId if for some reason it's null (migration case)
          final syncRemoteId = t.remoteId ?? const Uuid().v4();
          if (t.remoteId == null) {
            await (_db.update(_db.transactions)
                  ..where((r) => r.id.equals(t.id)))
                .write(TransactionsCompanion(remoteId: Value(syncRemoteId)));
          }

          final data = {
            'id': syncRemoteId, // Use client-generated UUID for idempotency
            'type': t.type == domain.TransactionType.income
                ? 'income'
                : 'expense',
            'amount': t.amount,
            'category': t.category,
            'description': t.description,
            'transaction_date': t.date.toIso8601String(),
            'proof_url': mergedUrls.isEmpty ? null : mergedUrls,
            'source': t.source,
            'source_ref': t.sourceRef,
          };

          final response = await _supabase!
              .from('transactions')
              .insert(data)
              .select()
              .single();

          await (_db.update(
            _db.transactions,
          )..where((r) => r.id.equals(t.id))).write(
            TransactionsCompanion(
              remoteId: Value(response['id']),
              syncStatus: Value(
                hasUploadError
                    ? domain.SyncStatus.pendingUpdate
                    : domain.SyncStatus.synced,
              ),
              proofUrls: Value(mergedUrls),
              proofPaths: Value(
                hasUploadError
                    ? t.proofPaths
                          .where(
                            (p) => !uploadedUrls.any(
                              (u) => u.contains(p.split('/').last),
                            ),
                          )
                          .toList()
                    : [],
              ),
              updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
            ),
          );
        } else if (t.syncStatus == domain.SyncStatus.pendingUpdate &&
            t.remoteId != null) {
          final uploadedUrls = <String>[];
          bool hasUploadError = false;

          for (final path in t.proofPaths) {
            try {
              final url = await _uploadFile(path, 'proofs');
              if (url != null) {
                uploadedUrls.add(url);
              }
            } catch (e) {
              debugPrint('Error uploading (update) proof $path: $e');
              hasUploadError = true;
            }
          }

          final mergedUrls = {...t.proofUrls, ...uploadedUrls}.toList();
          final response = await _supabase!
              .from('transactions')
              .update({
                'type': t.type == domain.TransactionType.income
                    ? 'income'
                    : 'expense',
                'amount': t.amount,
                'category': t.category,
                'description': t.description,
                'transaction_date': t.date.toIso8601String(),
                'proof_url': mergedUrls.isEmpty ? null : mergedUrls,
                'source': t.source,
                'source_ref': t.sourceRef,
              })
              .eq('id', t.remoteId!)
              .select()
              .single();

          await (_db.update(
            _db.transactions,
          )..where((r) => r.id.equals(t.id))).write(
            TransactionsCompanion(
              syncStatus: Value(
                hasUploadError
                    ? domain.SyncStatus.pendingUpdate
                    : domain.SyncStatus.synced,
              ),
              proofUrls: Value(mergedUrls),
              proofPaths: Value(
                hasUploadError
                    ? t.proofPaths
                          .where(
                            (p) => !uploadedUrls.any(
                              (u) => u.contains(p.split('/').last),
                            ),
                          )
                          .toList()
                    : [],
              ),
              updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
            ),
          );
        } else if (t.syncStatus == domain.SyncStatus.pendingDelete &&
            t.remoteId != null) {
          await _supabase!.from('transactions').delete().eq('id', t.remoteId!);
          await (_db.delete(
            _db.transactions,
          )..where((r) => r.id.equals(t.id))).go();
        }
      } catch (e) {
        final msg = 'Gagal sync transaksi ${t.category}: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }
    return errors;
  }

  Future<List<String>> _pullTransactions() async {
    final errors = <String>[];
    try {
      final response = await _supabase!.from('transactions').select();

      for (final remote in response) {
        final remoteId = remote['id'] as String;
        final localRows = await (_db.select(
          _db.transactions,
        )..where((t) => t.remoteId.equals(remoteId))).get();
        final local = localRows.isEmpty ? null : localRows.first;
        final remoteUpdatedAt = DateTime.tryParse(
          remote['updated_at']?.toString() ?? '',
        );

        // Parse proof_url from remote. It could be a string (legacy) or a list (new).
        List<String> remoteProofUrls = [];
        final rawProof = remote['proof_url'];
        if (rawProof is List) {
          remoteProofUrls = rawProof.map((e) => e.toString()).toList();
        } else if (rawProof is String) {
          if (rawProof.startsWith('[')) {
            try {
              final decoded = jsonDecode(rawProof);
              if (decoded is List) {
                remoteProofUrls = decoded.map((e) => e.toString()).toList();
              }
            } catch (_) {
              remoteProofUrls = [];
            }
          } else {
            remoteProofUrls = [rawProof];
          }
        }

        if (local == null) {
          await _db
              .into(_db.transactions)
              .insert(
                TransactionsCompanion(
                  remoteId: Value(remoteId),
                  type: Value(
                    remote['type'] == 'income'
                        ? domain.TransactionType.income
                        : domain.TransactionType.expense,
                  ),
                  amount: Value((remote['amount'] as num).toDouble()),
                  category: Value(remote['category']),
                  description: Value(remote['description']),
                  date: Value(DateTime.parse(remote['transaction_date'])),
                  proofUrls: Value(remoteProofUrls),
                  source: Value(
                    remote['source']?.toString() ??
                        domain.TransactionSource.manual,
                  ),
                  sourceRef: Value(remote['source_ref']?.toString()),
                  syncStatus: Value(domain.SyncStatus.synced),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (local.syncStatus == domain.SyncStatus.synced) {
          if (remoteUpdatedAt != null &&
              (local.updatedAt == null ||
                  remoteUpdatedAt.isAfter(local.updatedAt!))) {
            await (_db.update(
              _db.transactions,
            )..where((r) => r.id.equals(local.id))).write(
              TransactionsCompanion(
                type: Value(
                  remote['type'] == 'income'
                      ? domain.TransactionType.income
                      : domain.TransactionType.expense,
                ),
                amount: Value((remote['amount'] as num).toDouble()),
                category: Value(remote['category']),
                description: Value(remote['description']),
                date: Value(DateTime.parse(remote['transaction_date'])),
                proofUrls: Value(remoteProofUrls),
                source: Value(
                  remote['source']?.toString() ??
                      domain.TransactionSource.manual,
                ),
                sourceRef: Value(remote['source_ref']?.toString()),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    } catch (e) {
      final msg = 'Gagal pull transaksi: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  // --- Qurban Sync ---

  Future<List<String>> _pushQurbanPackages() async {
    final errors = <String>[];
    final pending =
        await (_db.select(_db.qurbanPackages)..where(
              (t) => t.syncStatus.isNotValue(domain.SyncStatus.synced.index),
            ))
            .get();

    for (final package in pending) {
      try {
        if (package.syncStatus == domain.SyncStatus.pendingDelete) {
          if (package.remoteId != null) {
            await _supabase!
                .from('qurban_packages')
                .delete()
                .eq('id', package.remoteId!);
          }
          await (_db.delete(
            _db.qurbanPackages,
          )..where((r) => r.id.equals(package.id))).go();
          continue;
        }

        final remoteId = package.remoteId ?? const Uuid().v4();
        if (package.remoteId == null) {
          await (_db.update(_db.qurbanPackages)
                ..where((r) => r.id.equals(package.id)))
              .write(QurbanPackagesCompanion(remoteId: Value(remoteId)));
        }

        final data = {
          'id': remoteId,
          'name': package.name,
          'monthly_amount': package.monthlyAmount,
          'is_active': package.isActive,
        };

        final response = package.syncStatus == domain.SyncStatus.pendingUpdate
            ? await _supabase!
                  .from('qurban_packages')
                  .update(data)
                  .eq('id', remoteId)
                  .select()
                  .single()
            : await _supabase!
                  .from('qurban_packages')
                  .upsert(data)
                  .select()
                  .single();

        await (_db.update(
          _db.qurbanPackages,
        )..where((r) => r.id.equals(package.id))).write(
          QurbanPackagesCompanion(
            remoteId: Value(response['id']),
            syncStatus: Value(domain.SyncStatus.synced),
            updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
          ),
        );
      } catch (e) {
        final msg = 'Gagal sync paket qurban ${package.name}: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }
    return errors;
  }

  Future<List<String>> _pullQurbanPackages() async {
    final errors = <String>[];
    try {
      final response = await _supabase!.from('qurban_packages').select();

      for (final remote in response) {
        final remoteId = remote['id'] as String;
        final localRows = await (_db.select(
          _db.qurbanPackages,
        )..where((t) => t.remoteId.equals(remoteId))).get();
        final local = localRows.isEmpty ? null : localRows.first;
        final remoteUpdatedAt = DateTime.tryParse(
          remote['updated_at']?.toString() ?? '',
        );

        if (local == null) {
          await _db
              .into(_db.qurbanPackages)
              .insert(
                QurbanPackagesCompanion.insert(
                  remoteId: Value(remoteId),
                  name: remote['name'] ?? '',
                  monthlyAmount: (remote['monthly_amount'] as num).toDouble(),
                  isActive: Value(remote['is_active'] ?? true),
                  syncStatus: const Value(domain.SyncStatus.synced),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (local.syncStatus == domain.SyncStatus.synced) {
          if (remoteUpdatedAt != null &&
              (local.updatedAt == null ||
                  remoteUpdatedAt.isAfter(local.updatedAt!))) {
            await (_db.update(
              _db.qurbanPackages,
            )..where((r) => r.id.equals(local.id))).write(
              QurbanPackagesCompanion(
                name: Value(remote['name'] ?? ''),
                monthlyAmount: Value(
                  (remote['monthly_amount'] as num).toDouble(),
                ),
                isActive: Value(remote['is_active'] ?? true),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    } catch (e) {
      final msg = 'Gagal pull paket qurban: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  Future<List<String>> _pushQurbanParticipants() async {
    final errors = <String>[];
    final pending =
        await (_db.select(_db.qurbanParticipants)..where(
              (t) => t.syncStatus.isNotValue(domain.SyncStatus.synced.index),
            ))
            .get();

    for (final participant in pending) {
      try {
        if (participant.syncStatus == domain.SyncStatus.pendingDelete) {
          if (participant.remoteId != null) {
            await _supabase!
                .from('qurban_participants')
                .delete()
                .eq('id', participant.remoteId!);
          }
          await (_db.delete(
            _db.qurbanParticipants,
          )..where((r) => r.id.equals(participant.id))).go();
          continue;
        }

        final remoteId = participant.remoteId ?? const Uuid().v4();
        if (participant.remoteId == null) {
          await (_db.update(_db.qurbanParticipants)
                ..where((r) => r.id.equals(participant.id)))
              .write(QurbanParticipantsCompanion(remoteId: Value(remoteId)));
        }

        final data = {
          'id': remoteId,
          'name': participant.name,
          'phone': participant.phone,
          'address': participant.address,
          'notes': participant.notes,
          'start_month': participant.startMonth.toIso8601String(),
          'monthly_amount': participant.monthlyAmount,
          'total_months': participant.totalMonths,
        };

        final response =
            participant.syncStatus == domain.SyncStatus.pendingUpdate
            ? await _supabase!
                  .from('qurban_participants')
                  .update(data)
                  .eq('id', remoteId)
                  .select()
                  .single()
            : await _supabase!
                  .from('qurban_participants')
                  .upsert(data)
                  .select()
                  .single();

        await (_db.update(
          _db.qurbanParticipants,
        )..where((r) => r.id.equals(participant.id))).write(
          QurbanParticipantsCompanion(
            remoteId: Value(response['id']),
            syncStatus: Value(domain.SyncStatus.synced),
            updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
          ),
        );
      } catch (e) {
        final msg = 'Gagal sync peserta qurban ${participant.name}: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }
    return errors;
  }

  Future<List<String>> _pullQurbanParticipants() async {
    final errors = <String>[];
    try {
      final response = await _supabase!.from('qurban_participants').select();

      for (final remote in response) {
        final remoteId = remote['id'] as String;
        final localRows = await (_db.select(
          _db.qurbanParticipants,
        )..where((t) => t.remoteId.equals(remoteId))).get();
        final local = localRows.isEmpty ? null : localRows.first;
        final remoteUpdatedAt = DateTime.tryParse(
          remote['updated_at']?.toString() ?? '',
        );

        if (local == null) {
          await _db
              .into(_db.qurbanParticipants)
              .insert(
                QurbanParticipantsCompanion.insert(
                  remoteId: Value(remoteId),
                  name: remote['name'] ?? '',
                  phone: Value(remote['phone']),
                  address: Value(remote['address']),
                  notes: Value(remote['notes']),
                  startMonth: DateTime.parse(remote['start_month']),
                  monthlyAmount: (remote['monthly_amount'] as num).toDouble(),
                  totalMonths: Value(remote['total_months'] ?? 10),
                  syncStatus: const Value(domain.SyncStatus.synced),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (local.syncStatus == domain.SyncStatus.synced) {
          if (remoteUpdatedAt != null &&
              (local.updatedAt == null ||
                  remoteUpdatedAt.isAfter(local.updatedAt!))) {
            await (_db.update(
              _db.qurbanParticipants,
            )..where((r) => r.id.equals(local.id))).write(
              QurbanParticipantsCompanion(
                name: Value(remote['name'] ?? ''),
                phone: Value(remote['phone']),
                address: Value(remote['address']),
                notes: Value(remote['notes']),
                startMonth: Value(DateTime.parse(remote['start_month'])),
                monthlyAmount: Value(
                  (remote['monthly_amount'] as num).toDouble(),
                ),
                totalMonths: Value(remote['total_months'] ?? 10),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    } catch (e) {
      final msg = 'Gagal pull peserta qurban: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  Future<List<String>> _pushQurbanPayments() async {
    final errors = <String>[];
    final pending =
        await (_db.select(_db.qurbanPayments)..where(
              (t) => t.syncStatus.isNotValue(domain.SyncStatus.synced.index),
            ))
            .get();

    for (final payment in pending) {
      try {
        if (payment.syncStatus == domain.SyncStatus.pendingDelete) {
          if (payment.remoteId != null) {
            await _supabase!
                .from('qurban_payments')
                .delete()
                .eq('id', payment.remoteId!);
          }
          await (_db.delete(
            _db.qurbanPayments,
          )..where((r) => r.id.equals(payment.id))).go();
          continue;
        }

        final participant = await (_db.select(
          _db.qurbanParticipants,
        )..where((t) => t.id.equals(payment.participantId))).getSingleOrNull();
        if (participant?.remoteId == null) {
          throw Exception('Peserta belum tersinkron');
        }

        TransactionEntity? transaction;
        if (payment.transactionId != null) {
          transaction =
              await (_db.select(_db.transactions)
                    ..where((t) => t.id.equals(payment.transactionId!)))
                  .getSingleOrNull();
        }
        if (transaction?.remoteId == null) {
          throw Exception('Transaksi kas qurban belum tersinkron');
        }

        final remoteId = payment.remoteId ?? const Uuid().v4();
        if (payment.remoteId == null) {
          await (_db.update(_db.qurbanPayments)
                ..where((r) => r.id.equals(payment.id)))
              .write(QurbanPaymentsCompanion(remoteId: Value(remoteId)));
        }

        final data = {
          'id': remoteId,
          'participant_id': participant!.remoteId,
          'transaction_id': transaction!.remoteId,
          'amount': payment.amount,
          'payment_date': payment.paymentDate.toIso8601String(),
          'note': payment.note,
        };

        final response = payment.syncStatus == domain.SyncStatus.pendingUpdate
            ? await _supabase!
                  .from('qurban_payments')
                  .update(data)
                  .eq('id', remoteId)
                  .select()
                  .single()
            : await _supabase!
                  .from('qurban_payments')
                  .upsert(data)
                  .select()
                  .single();

        await (_db.update(
          _db.qurbanPayments,
        )..where((r) => r.id.equals(payment.id))).write(
          QurbanPaymentsCompanion(
            remoteId: Value(response['id']),
            syncStatus: Value(domain.SyncStatus.synced),
            updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
          ),
        );
      } catch (e) {
        final msg = 'Gagal sync pembayaran qurban ${payment.id}: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }
    return errors;
  }

  Future<List<String>> _pullQurbanPayments() async {
    final errors = <String>[];
    try {
      final response = await _supabase!.from('qurban_payments').select();

      for (final remote in response) {
        final remoteId = remote['id'] as String;
        final participantRemoteId = remote['participant_id']?.toString();
        if (participantRemoteId == null) continue;

        final participantRows = await (_db.select(
          _db.qurbanParticipants,
        )..where((t) => t.remoteId.equals(participantRemoteId))).get();
        if (participantRows.isEmpty) continue;
        final participant = participantRows.first;

        final transactionRemoteId = remote['transaction_id']?.toString();
        int? localTransactionId;
        if (transactionRemoteId != null) {
          final transactionRows = await (_db.select(
            _db.transactions,
          )..where((t) => t.remoteId.equals(transactionRemoteId))).get();
          if (transactionRows.isNotEmpty) {
            localTransactionId = transactionRows.first.id;
          }
        }

        final localRows = await (_db.select(
          _db.qurbanPayments,
        )..where((t) => t.remoteId.equals(remoteId))).get();
        final local = localRows.isEmpty ? null : localRows.first;
        final remoteUpdatedAt = DateTime.tryParse(
          remote['updated_at']?.toString() ?? '',
        );

        if (local == null) {
          await _db
              .into(_db.qurbanPayments)
              .insert(
                QurbanPaymentsCompanion.insert(
                  remoteId: Value(remoteId),
                  participantId: participant.id,
                  transactionId: Value(localTransactionId),
                  amount: (remote['amount'] as num).toDouble(),
                  paymentDate: DateTime.parse(remote['payment_date']),
                  note: Value(remote['note']),
                  syncStatus: const Value(domain.SyncStatus.synced),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (local.syncStatus == domain.SyncStatus.synced) {
          if (remoteUpdatedAt != null &&
              (local.updatedAt == null ||
                  remoteUpdatedAt.isAfter(local.updatedAt!))) {
            await (_db.update(
              _db.qurbanPayments,
            )..where((r) => r.id.equals(local.id))).write(
              QurbanPaymentsCompanion(
                participantId: Value(participant.id),
                transactionId: Value(localTransactionId),
                amount: Value((remote['amount'] as num).toDouble()),
                paymentDate: Value(DateTime.parse(remote['payment_date'])),
                note: Value(remote['note']),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    } catch (e) {
      final msg = 'Gagal pull pembayaran qurban: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  // --- Activities Sync ---
  Future<List<String>> _pushActivities() async {
    final errors = <String>[];
    final pending =
        await (_db.select(_db.activities)..where(
              (t) => t.syncStatus.isNotValue(domain.SyncStatus.synced.index),
            ))
            .get();

    for (final a in pending) {
      try {
        if (a.syncStatus == domain.SyncStatus.pendingCreate) {
          final response = await _supabase!
              .from('activities')
              .insert({
                'title': a.title,
                'description': a.description,
                'type': a.type,
                'activity_date': a.date.toIso8601String(),
                'pic_name': a.picName,
              })
              .select()
              .single();

          await (_db.update(
            _db.activities,
          )..where((r) => r.id.equals(a.id))).write(
            ActivitiesCompanion(
              remoteId: Value(response['id']),
              syncStatus: Value(domain.SyncStatus.synced),
              updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
            ),
          );
        } else if (a.syncStatus == domain.SyncStatus.pendingUpdate &&
            a.remoteId != null) {
          final response = await _supabase!
              .from('activities')
              .update({
                'title': a.title,
                'description': a.description,
                'type': a.type,
                'activity_date': a.date.toIso8601String(),
                'pic_name': a.picName,
              })
              .eq('id', a.remoteId!)
              .select()
              .single();

          await (_db.update(
            _db.activities,
          )..where((r) => r.id.equals(a.id))).write(
            ActivitiesCompanion(
              syncStatus: Value(domain.SyncStatus.synced),
              updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
            ),
          );
        } else if (a.syncStatus == domain.SyncStatus.pendingDelete &&
            a.remoteId != null) {
          await _supabase!.from('activities').delete().eq('id', a.remoteId!);
          await (_db.delete(
            _db.activities,
          )..where((r) => r.id.equals(a.id))).go();
        }
      } catch (e) {
        final msg = 'Gagal sync kegiatan ${a.title}: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }
    return errors;
  }

  Future<List<String>> _pullActivities() async {
    final errors = <String>[];
    try {
      final response = await _supabase!.from('activities').select();

      for (final remote in response) {
        final remoteId = remote['id'] as String;
        final localRows = await (_db.select(
          _db.activities,
        )..where((t) => t.remoteId.equals(remoteId))).get();
        final local = localRows.isEmpty ? null : localRows.first;
        final remoteUpdatedAt = DateTime.tryParse(
          remote['updated_at']?.toString() ?? '',
        );

        if (local == null) {
          await _db
              .into(_db.activities)
              .insert(
                ActivitiesCompanion(
                  remoteId: Value(remoteId),
                  title: Value(remote['title']),
                  description: Value(remote['description']),
                  type: Value(remote['type']),
                  date: Value(DateTime.parse(remote['activity_date'])),
                  picName: Value(remote['pic_name']),
                  syncStatus: Value(domain.SyncStatus.synced),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (local.syncStatus == domain.SyncStatus.synced) {
          if (remoteUpdatedAt != null &&
              (local.updatedAt == null ||
                  remoteUpdatedAt.isAfter(local.updatedAt!))) {
            await (_db.update(
              _db.activities,
            )..where((r) => r.id.equals(local.id))).write(
              ActivitiesCompanion(
                title: Value(remote['title']),
                description: Value(remote['description']),
                type: Value(remote['type']),
                date: Value(DateTime.parse(remote['activity_date'])),
                picName: Value(remote['pic_name']),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    } catch (e) {
      final msg = 'Gagal pull kegiatan: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  // --- Mosque Profile Sync ---
  Future<List<String>> _pushMosqueProfile() async {
    final errors = <String>[];
    final pending =
        await (_db.select(_db.mosqueProfiles)..where(
              (t) => t.syncStatus.isNotValue(domain.SyncStatus.synced.index),
            ))
            .get();

    for (final p in pending) {
      try {
        String? logoUrl;
        if (p.logoPath != null) {
          if (p.logoPath!.startsWith('http')) {
            // Already a remote URL
            logoUrl = p.logoPath;
          } else {
            // Local file, try to upload
            logoUrl = await _uploadFile(p.logoPath!, 'logos');
            // If upload failed (returned null) but we had a path, abort sync for this item
            // to avoid overwriting remote logo with null.
            if (logoUrl == null) {
              throw Exception(
                'Gagal upload logo: File tidak ditemukan atau upload gagal',
              );
            }
          }
        }

        final data = {
          'name': p.name,
          'address': p.address,
          'logo_url': logoUrl,
        };

        Map<String, dynamic> response;
        if (p.remoteId != null) {
          response = await _supabase!
              .from('mosque_profiles')
              .update(data)
              .eq('id', p.remoteId!)
              .select()
              .single();
        } else {
          response = await _supabase!
              .from('mosque_profiles')
              .insert(data)
              .select()
              .single();
        }

        await (_db.update(
          _db.mosqueProfiles,
        )..where((r) => r.id.equals(p.id))).write(
          MosqueProfilesCompanion(
            remoteId: Value(response['id']),
            syncStatus: Value(domain.SyncStatus.synced),
            updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
          ),
        );
      } catch (e) {
        final msg = 'Gagal sync profil: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }
    return errors;
  }

  Future<List<String>> _pullMosqueProfile() async {
    final errors = <String>[];
    try {
      final response = await _supabase!
          .from('mosque_profiles')
          .select()
          .limit(1)
          .maybeSingle();
      if (response != null) {
        final remoteId = response['id'] as String;
        final local = await _db.select(_db.mosqueProfiles).getSingleOrNull();
        final remoteUpdatedAt = DateTime.tryParse(
          response['updated_at']?.toString() ?? '',
        );

        if (local == null) {
          await _db
              .into(_db.mosqueProfiles)
              .insert(
                MosqueProfilesCompanion(
                  remoteId: Value(remoteId),
                  name: Value(response['name']),
                  address: Value(response['address']),
                  logoPath: Value(response['logo_url']),
                  syncStatus: Value(domain.SyncStatus.synced),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (local.syncStatus == domain.SyncStatus.synced) {
          if (remoteUpdatedAt != null &&
              (local.updatedAt == null ||
                  remoteUpdatedAt.isAfter(local.updatedAt!))) {
            await (_db.update(
              _db.mosqueProfiles,
            )..where((r) => r.id.equals(local.id))).write(
              MosqueProfilesCompanion(
                name: Value(response['name']),
                address: Value(response['address']),
                logoPath: Value(response['logo_url']),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    } catch (e) {
      final msg = 'Gagal pull profil: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  Future<List<String>> _pushUsers() async {
    final errors = <String>[];
    try {
      final client = _supabase;
      if (client == null) {
        errors.add('Supabase client not initialized for user sync');
        return errors;
      }

      // Handle Pending Create
      final pendingCreate =
          await (_db.select(_db.users)..where(
                (t) =>
                    t.syncStatus.equals(domain.SyncStatus.pendingCreate.index),
              ))
              .get();

      final authLocalDatasource = GetIt.I.isRegistered<AuthLocalDatasource>()
          ? GetIt.I<AuthLocalDatasource>()
          : null;

      for (final user in pendingCreate) {
        try {
          final tempUserId = user.remoteId;
          if (authLocalDatasource == null || tempUserId == null) {
            throw Exception('Pending user credential store is unavailable');
          }

          final password = await authLocalDatasource.getPendingUserPassword(
            tempUserId,
          );

          if (password == null) {
            throw Exception('Password not found for pending user');
          }

          final result = await _adminUserService.createUser(
            email: user.email,
            password: password,
            fullName: user.fullName ?? '',
            username: user.username,
            role: user.role,
          );

          if (result.isBackendUnavailable) {
            debugPrint(_adminUserDeferredMessage('create', user.fullName));
            continue;
          }

          if (!result.isSuccess || result.userId == null) {
            throw Exception(result.message ?? 'Admin user create failed');
          }

          await _updateUserSynced(user.id, result.userId!, result.updatedAt);
          await authLocalDatasource.deletePendingUserPassword(tempUserId);
        } catch (e) {
          final msg = 'Gagal create user ${user.fullName}: $e';
          debugPrint(msg);
          errors.add(msg);
        }
      }

      // Handle Pending Update
      final pendingUpdate =
          await (_db.select(_db.users)..where(
                (t) =>
                    t.syncStatus.equals(domain.SyncStatus.pendingUpdate.index),
              ))
              .get();

      for (final user in pendingUpdate) {
        if (user.remoteId == null) continue;

        try {
          final result = await _adminUserService.updateUser(
            userId: user.remoteId!,
            email: user.email,
            fullName: user.fullName ?? '',
            username: user.username,
            role: user.role,
          );

          if (result.isBackendUnavailable) {
            debugPrint(_adminUserDeferredMessage('update', user.fullName));
            continue;
          }

          if (!result.isSuccess) {
            throw Exception(result.message ?? 'Admin user update failed');
          }

          await (_db.update(
            _db.users,
          )..where((r) => r.id.equals(user.id))).write(
            UsersCompanion(
              syncStatus: Value(domain.SyncStatus.synced),
              updatedAt: Value(DateTime.tryParse(result.updatedAt ?? '')),
            ),
          );
        } catch (e) {
          final msg = 'Gagal update user ${user.fullName}: $e';
          debugPrint(msg);
          errors.add(msg);
        }
      }

      // Handle Pending Delete
      final pendingDelete =
          await (_db.select(_db.users)..where(
                (t) =>
                    t.syncStatus.equals(domain.SyncStatus.pendingDelete.index),
              ))
              .get();

      for (final user in pendingDelete) {
        if (user.remoteId == null) {
          // Local only, just delete
          await (_db.delete(
            _db.users,
          )..where((r) => r.id.equals(user.id))).go();
          continue;
        }

        try {
          final result = await _adminUserService.deleteUser(user.remoteId!);
          if (result.isBackendUnavailable) {
            debugPrint(_adminUserDeferredMessage('delete', user.fullName));
            continue;
          }

          if (!result.isSuccess) {
            throw Exception(result.message ?? 'Admin user delete failed');
          }

          // Delete from local DB - only reaches here if no exception or 404
          await (_db.delete(
            _db.users,
          )..where((r) => r.id.equals(user.id))).go();
        } catch (e) {
          final msg = 'Gagal delete user ${user.fullName}: $e';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    } catch (e) {
      errors.add('Error preparing user sync: $e');
    }
    return errors;
  }

  String _adminUserDeferredMessage(String action, String? name) {
    final userName = (name == null || name.trim().isEmpty)
        ? 'pengguna'
        : name.trim();
    return 'Sync user $action untuk $userName ditunda: Edge Function admin-users belum tersedia';
  }

  Future<List<String>> _pullUsers() async {
    final errors = <String>[];
    try {
      final response = await _supabase!.from('profiles').select();

      for (final remote in response) {
        final remoteId = remote['id'] as String;
        final localRows = await (_db.select(
          _db.users,
        )..where((t) => t.remoteId.equals(remoteId))).get();
        final local = localRows.isEmpty ? null : localRows.first;

        if (local == null) {
          await _db
              .into(_db.users)
              .insert(
                UsersCompanion(
                  remoteId: Value(remoteId),
                  email: Value(remote['email'] ?? ''),
                  username: Value(remote['username']),
                  fullName: Value(remote['full_name']),
                  role: Value(remote['role'] ?? 'viewer'),
                  syncStatus: Value(domain.SyncStatus.synced),
                  createdAt: Value(
                    DateTime.tryParse(remote['created_at'] ?? '') ??
                        DateTime.now(),
                  ),
                  updatedAt: Value(
                    DateTime.tryParse(remote['updated_at'] ?? ''),
                  ),
                ),
              );
        } else if (local.syncStatus == domain.SyncStatus.synced) {
          final remoteUpdatedAt = DateTime.tryParse(
            remote['updated_at']?.toString() ?? '',
          );
          if (remoteUpdatedAt != null &&
              (local.updatedAt == null ||
                  remoteUpdatedAt.isAfter(local.updatedAt!))) {
            await (_db.update(
              _db.users,
            )..where((t) => t.id.equals(local.id))).write(
              UsersCompanion(
                email: Value(remote['email'] ?? ''),
                username: Value(remote['username']),
                fullName: Value(remote['full_name']),
                role: Value(remote['role'] ?? 'viewer'),
                syncStatus: Value(domain.SyncStatus.synced),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          }
        }
      }
    } catch (e) {
      final msg = 'Gagal pull users: $e';
      debugPrint(msg);
      errors.add(msg);
    }
    return errors;
  }

  Future<String?> _uploadFile(String path, String bucket) async {
    final supabase = _supabase;
    if (supabase == null) return null;

    // Use local filename which already contains timestamp from TransactionFormPage
    // format: proof_{timestamp}_{basename}
    // This ensures consistency and avoids duplicates on retry (with upsert)
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('Error: Cannot upload file without authenticated user');
      return null;
    }

    final rawFileName = p.basename(path);
    // Sanitize filename: replace spaces and non-ascii with underscores
    final sanitizedFileName = rawFileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final fileName = '$userId/$sanitizedFileName';

    try {
      if (kIsWeb) {
        // On Web, we want to rethrow the exception so _pushTransactions can catch it
        // and abort the sync for this transaction (retry later).
        final bundle = NetworkAssetBundle(Uri.parse(path));
        final data = await bundle.load(path);
        final bytes = data.buffer.asUint8List();

        await supabase.storage
            .from(bucket)
            .uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        final publicUrl = supabase.storage.from(bucket).getPublicUrl(fileName);
        return publicUrl;
      } else {
        final file = File(path);
        if (!await file.exists()) {
          debugPrint('File not found for upload: $path');
          return null;
        }

        await supabase.storage
            .from(bucket)
            .upload(
              fileName,
              file,
              fileOptions: const FileOptions(upsert: true),
            );
        final publicUrl = supabase.storage.from(bucket).getPublicUrl(fileName);
        return publicUrl;
      }
    } catch (e) {
      debugPrint('Error uploading file ($path) to bucket ($bucket): $e');
      rethrow;
    }
  }

  Future<void> _updateUserSynced(
    int localId,
    String remoteId,
    String? updatedAt,
  ) async {
    await (_db.update(_db.users)..where((r) => r.id.equals(localId))).write(
      UsersCompanion(
        remoteId: Value(remoteId),
        syncStatus: Value(domain.SyncStatus.synced),
        updatedAt: Value(DateTime.tryParse(updatedAt ?? '')),
      ),
    );
  }
}
