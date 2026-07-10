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
        // Generate and persist the remote id BEFORE the insert so a retry after
        // a lost response re-sends the same id (upsert => no duplicate log).
        final remoteId = log.remoteId ?? const Uuid().v4();
        if (log.remoteId == null) {
          await (_db.update(_db.auditLogs)..where((r) => r.id.equals(log.id)))
              .write(AuditLogsCompanion(remoteId: Value(remoteId)));
        }

        final data = {
          'id': remoteId,
          'user_id': log.userId,
          'action': log.action,
          'table_name': log.targetTable,
          'record_id': log.recordId,
          'description': log.description,
          'created_at': log.createdAt.toIso8601String(),
          // created_by is deliberately NOT sent: the server stamps it from
          // auth.uid() (unforgeable), which is the column auditors can trust.
          // user_id above is only the app's best guess at the actor and can be
          // anything the client wrote locally.
        };

        // No .select() back: audit_logs SELECT is restricted to admin/ketua, so
        // reading the row after insert threw for every other role and left
        // their logs stuck pendingCreate forever. upsert(ignoreDuplicates) needs
        // no read and is idempotent on the client-supplied id.
        await _supabase!
            .from('audit_logs')
            .upsert(data, ignoreDuplicates: true);

        await (_db.update(
          _db.auditLogs,
        )..where((r) => r.id.equals(log.id))).write(
          AuditLogsCompanion(
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
    const pageSize = 500;
    try {
      // Cursor-based on created_at (audit logs are append-only, never
      // updated) instead of a flat "last 100": a device that syncs
      // infrequently, or a mosque with >100 log entries between syncs,
      // used to permanently miss anything older than the 100 most recent
      // rows at pull time. Only remoteId-tagged rows count toward the
      // cursor -- a not-yet-pushed local entry's timestamp doesn't tell us
      // what's already been pulled from the server.
      final cursorRow =
          await (_db.selectOnly(_db.auditLogs)
                ..addColumns([_db.auditLogs.createdAt.max()])
                ..where(_db.auditLogs.remoteId.isNotNull()))
              .getSingleOrNull();
      var cursor = cursorRow?.read(_db.auditLogs.createdAt.max());

      while (true) {
        var filterBuilder = _supabase!.from('audit_logs').select();
        if (cursor != null) {
          filterBuilder = filterBuilder.gt(
            'created_at',
            cursor.toIso8601String(),
          );
        }
        final response = await filterBuilder
            .order('created_at', ascending: true)
            .limit(pageSize);

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

        if (response.length < pageSize) break;
        cursor = DateTime.parse(response.last['created_at'] as String);
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
                // _uploadFile returns null (no exception) when the local
                // proof file is missing. Treat this the same as a thrown
                // error so the transaction stays pending and keeps this
                // path queued for retry, instead of silently being marked
                // "synced" with the proof quietly dropped.
                debugPrint(
                  'Warning: Skipping upload for $path (Returned null)',
                );
                hasUploadError = true;
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

          // upsert(), not insert(): the row's UUID is generated and persisted
          // locally BEFORE this call, so if the server commits but the response
          // is lost (mobile network drop, app killed), the row stays
          // pendingCreate with a remoteId the server already knows. A plain
          // insert() would then fail forever with 23505 duplicate key on every
          // subsequent sync, leaving a transaction that exists on the server
          // but is permanently stuck "unsynced" on the device. Re-upserting the
          // same id with the same values is a no-op, which is what idempotency
          // means here.
          final response = await _supabase!
              .from('transactions')
              .upsert(data)
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
              } else {
                debugPrint(
                  'Warning: Skipping upload (update) for $path (Returned null)',
                );
                hasUploadError = true;
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
    const pageSize = 500;
    try {
      // Cursor on updated_at instead of an unconditional full-table fetch:
      // avoids re-downloading years of transactions on every single sync.
      // Merge logic below is unchanged and already idempotent, so this is
      // purely a "fetch less" optimization, not a behavior change.
      final cursorRow =
          await (_db.selectOnly(_db.transactions)
                ..addColumns([_db.transactions.updatedAt.max()])
                ..where(_db.transactions.remoteId.isNotNull()))
              .getSingleOrNull();
      var cursor = cursorRow?.read(_db.transactions.updatedAt.max());

      while (true) {
        var filterBuilder = _supabase!.from('transactions').select();
        if (cursor != null) {
          filterBuilder = filterBuilder.gt(
            'updated_at',
            cursor.toIso8601String(),
          );
        }
        final response = await filterBuilder
            .order('updated_at', ascending: true)
            .limit(pageSize);
        if (response.isEmpty) break;

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

        if (response.length < pageSize) break;
        cursor = DateTime.parse(response.last['updated_at'] as String);
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

        if (package.syncStatus == domain.SyncStatus.pendingUpdate) {
          final response = await _supabase!
              .from('qurban_packages')
              .update(data)
              .eq('id', remoteId)
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
          continue;
        }

        // pendingCreate. ignoreDuplicates matters because the two default
        // packages are seeded locally with FIXED remote ids on every fresh
        // install. A plain upsert would make each new device overwrite the
        // server's copy of those rows back to the hardcoded defaults, silently
        // reverting any name/amount the admin had already changed and synced
        // from another device. Insert-if-absent is the only safe semantic for a
        // row this device merely assumed into existence rather than authored.
        final rows = await _supabase!
            .from('qurban_packages')
            .upsert(data, ignoreDuplicates: true)
            .select();

        // Empty rows => the server already had this id and kept its own values.
        // Leave updatedAt null so the _pullQurbanPackages pass that runs
        // immediately after this one treats the server row as newer and pulls
        // the real values down over the local placeholder.
        final inserted = rows.isEmpty ? null : rows.first;

        await (_db.update(
          _db.qurbanPackages,
        )..where((r) => r.id.equals(package.id))).write(
          QurbanPackagesCompanion(
            remoteId: Value(inserted?['id'] as String? ?? remoteId),
            syncStatus: Value(domain.SyncStatus.synced),
            updatedAt: Value(
              DateTime.tryParse(inserted?['updated_at']?.toString() ?? ''),
            ),
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
    const pageSize = 500;
    try {
      final cursorRow =
          await (_db.selectOnly(_db.qurbanPackages)
                ..addColumns([_db.qurbanPackages.updatedAt.max()])
                ..where(_db.qurbanPackages.remoteId.isNotNull()))
              .getSingleOrNull();
      var cursor = cursorRow?.read(_db.qurbanPackages.updatedAt.max());

      while (true) {
        var filterBuilder = _supabase!.from('qurban_packages').select();
        if (cursor != null) {
          filterBuilder = filterBuilder.gt(
            'updated_at',
            cursor.toIso8601String(),
          );
        }
        final response = await filterBuilder
            .order('updated_at', ascending: true)
            .limit(pageSize);
        if (response.isEmpty) break;

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

        if (response.length < pageSize) break;
        cursor = DateTime.parse(response.last['updated_at'] as String);
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

    const chunkSize = 50;

    // Deletes stay one row at a time (not batched): each one needs its own
    // server-side "does this participant have payments now?" re-check
    // before the irreversible delete (see H4 in the audit) -- batching
    // that safety check is significantly more complex and this path is
    // rarely high-volume enough to need it.
    for (final participant in pending) {
      if (participant.syncStatus != domain.SyncStatus.pendingDelete) continue;
      try {
        if (participant.remoteId != null) {
          // Re-check for payments on the SERVER (not just this device's
          // local mirror) right before the irreversible delete: another
          // device may have already synced payments for this participant
          // that this device hasn't pulled yet. ON DELETE CASCADE would
          // silently destroy those payments -- and orphan their linked
          // income transactions -- if we only trusted the local check
          // made when the delete was first requested.
          final remotePayments = await _supabase!
              .from('qurban_payments')
              .select('id')
              .eq('participant_id', participant.remoteId!)
              .limit(1);
          if (remotePayments.isNotEmpty) {
            // Reject the delete and restore the participant instead of
            // leaving it stuck in pendingDelete limbo forever.
            await (_db.update(
              _db.qurbanParticipants,
            )..where((r) => r.id.equals(participant.id))).write(
              const QurbanParticipantsCompanion(
                syncStatus: Value(domain.SyncStatus.synced),
              ),
            );
            errors.add(
              'Peserta ${participant.name} tidak jadi dihapus: sudah ada '
              'pembayaran tersinkron dari perangkat lain. Tarik data '
              'terbaru lalu coba lagi.',
            );
            continue;
          }
          await _supabase
              .from('qurban_participants')
              .delete()
              .eq('id', participant.remoteId!);
        }
        await (_db.delete(
          _db.qurbanParticipants,
        )..where((r) => r.id.equals(participant.id))).go();
      } catch (e) {
        final msg = 'Gagal hapus peserta qurban ${participant.name}: $e';
        debugPrint(msg);
        errors.add(msg);
      }
    }

    // Creates/updates: batched via chunked upsert (remoteId is the
    // conflict key), with a per-chunk fallback to row-by-row processing so
    // one bad row can't sink an otherwise-good chunk.
    final effectiveRemoteId = <int, String>{};
    final toUpsert = <QurbanParticipantEntity>[];
    for (final participant in pending) {
      if (participant.syncStatus == domain.SyncStatus.pendingDelete) continue;
      var remoteId = participant.remoteId;
      if (remoteId == null) {
        remoteId = const Uuid().v4();
        await (_db.update(_db.qurbanParticipants)
              ..where((r) => r.id.equals(participant.id)))
            .write(QurbanParticipantsCompanion(remoteId: Value(remoteId)));
      }
      effectiveRemoteId[participant.id] = remoteId;
      toUpsert.add(participant);
    }

    Map<String, dynamic> toPayload(QurbanParticipantEntity p) => {
      'id': effectiveRemoteId[p.id],
      'name': p.name,
      'phone': p.phone,
      'address': p.address,
      'notes': p.notes,
      'start_month': p.startMonth.toIso8601String(),
      'monthly_amount': p.monthlyAmount,
      'total_months': p.totalMonths,
    };

    Future<void> pushOne(QurbanParticipantEntity p) async {
      final response = await _supabase!
          .from('qurban_participants')
          .upsert(toPayload(p))
          .select()
          .single();
      await (_db.update(
        _db.qurbanParticipants,
      )..where((r) => r.id.equals(p.id))).write(
        QurbanParticipantsCompanion(
          syncStatus: Value(domain.SyncStatus.synced),
          updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
        ),
      );
    }

    for (var i = 0; i < toUpsert.length; i += chunkSize) {
      final end = (i + chunkSize < toUpsert.length)
          ? i + chunkSize
          : toUpsert.length;
      final chunk = toUpsert.sublist(i, end);

      try {
        final response = await _supabase!
            .from('qurban_participants')
            .upsert(chunk.map(toPayload).toList())
            .select();
        final updatedAtById = {
          for (final row in response)
            row['id'] as String: row['updated_at'] as String?,
        };
        for (final p in chunk) {
          await (_db.update(
            _db.qurbanParticipants,
          )..where((r) => r.id.equals(p.id))).write(
            QurbanParticipantsCompanion(
              syncStatus: Value(domain.SyncStatus.synced),
              updatedAt: Value(
                DateTime.tryParse(updatedAtById[effectiveRemoteId[p.id]] ?? ''),
              ),
            ),
          );
        }
      } catch (e) {
        for (final p in chunk) {
          try {
            await pushOne(p);
          } catch (e2) {
            final msg = 'Gagal sync peserta qurban ${p.name}: $e2';
            debugPrint(msg);
            errors.add(msg);
          }
        }
      }
    }

    return errors;
  }

  Future<List<String>> _pullQurbanParticipants() async {
    final errors = <String>[];
    const pageSize = 500;
    try {
      final cursorRow =
          await (_db.selectOnly(_db.qurbanParticipants)
                ..addColumns([_db.qurbanParticipants.updatedAt.max()])
                ..where(_db.qurbanParticipants.remoteId.isNotNull()))
              .getSingleOrNull();
      var cursor = cursorRow?.read(_db.qurbanParticipants.updatedAt.max());

      while (true) {
        var filterBuilder = _supabase!.from('qurban_participants').select();
        if (cursor != null) {
          filterBuilder = filterBuilder.gt(
            'updated_at',
            cursor.toIso8601String(),
          );
        }
        final response = await filterBuilder
            .order('updated_at', ascending: true)
            .limit(pageSize);
        if (response.isEmpty) break;

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

        if (response.length < pageSize) break;
        cursor = DateTime.parse(response.last['updated_at'] as String);
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
    const pageSize = 500;
    try {
      final cursorRow =
          await (_db.selectOnly(_db.qurbanPayments)
                ..addColumns([_db.qurbanPayments.updatedAt.max()])
                ..where(_db.qurbanPayments.remoteId.isNotNull()))
              .getSingleOrNull();
      var cursor = cursorRow?.read(_db.qurbanPayments.updatedAt.max());

      while (true) {
        var filterBuilder = _supabase!.from('qurban_payments').select();
        if (cursor != null) {
          filterBuilder = filterBuilder.gt(
            'updated_at',
            cursor.toIso8601String(),
          );
        }
        final response = await filterBuilder
            .order('updated_at', ascending: true)
            .limit(pageSize);
        if (response.isEmpty) break;

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

          // Repair a link an earlier sync couldn't resolve (the payment was
          // pulled while its cash transaction hadn't landed locally yet). The
          // merge below only runs when the remote row is *newer*, so without
          // this the payment would keep transactionId = null forever -- and a
          // null link makes updatePayment() mint a duplicate income row.
          if (local != null &&
              local.transactionId == null &&
              localTransactionId != null) {
            await (_db.update(
              _db.qurbanPayments,
            )..where((r) => r.id.equals(local.id))).write(
              QurbanPaymentsCompanion(
                transactionId: Value(localTransactionId),
              ),
            );
          }

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
                  // Value.absent(), not Value(null): if the linked transaction
                  // simply isn't on this device yet, keep whatever link we
                  // already have instead of wiping a good one.
                  transactionId: localTransactionId != null
                      ? Value(localTransactionId)
                      : const Value.absent(),
                  amount: Value((remote['amount'] as num).toDouble()),
                  paymentDate: Value(DateTime.parse(remote['payment_date'])),
                  note: Value(remote['note']),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
            }
          }
        }

        if (response.length < pageSize) break;
        cursor = DateTime.parse(response.last['updated_at'] as String);
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

    const chunkSize = 50;

    Map<String, dynamic> toPayload(ActivityEntity a) => {
      'id': a.remoteId,
      'title': a.title,
      'description': a.description,
      'type': a.type,
      'activity_date': a.date.toIso8601String(),
      'pic_name': a.picName,
    };

    Future<void> pushOneUpsert(ActivityEntity a) async {
      final response = await _supabase!
          .from('activities')
          .upsert(toPayload(a))
          .select()
          .single();
      await (_db.update(_db.activities)..where((r) => r.id.equals(a.id))).write(
        ActivitiesCompanion(
          syncStatus: Value(domain.SyncStatus.synced),
          updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
        ),
      );
    }

    // Upsert covers both pendingCreate and pendingUpdate uniformly (each
    // row already carries its own remoteId as the conflict key), batched
    // in chunks instead of one request per row. A chunk that fails falls
    // back to processing its rows individually, so one bad row can't sink
    // an otherwise-good chunk -- same error isolation as before, just
    // fewer round trips in the common case where nothing fails.
    final toUpsert = <ActivityEntity>[];
    for (final a in pending) {
      if (a.syncStatus == domain.SyncStatus.pendingCreate ||
          (a.syncStatus == domain.SyncStatus.pendingUpdate &&
              a.remoteId != null)) {
        if (a.remoteId == null) {
          final newRemoteId = const Uuid().v4();
          await (_db.update(_db.activities)..where((r) => r.id.equals(a.id)))
              .write(ActivitiesCompanion(remoteId: Value(newRemoteId)));
          toUpsert.add(
            ActivityEntity(
              id: a.id,
              remoteId: newRemoteId,
              title: a.title,
              description: a.description,
              type: a.type,
              date: a.date,
              picName: a.picName,
              syncStatus: a.syncStatus,
              createdAt: a.createdAt,
              updatedAt: a.updatedAt,
            ),
          );
        } else {
          toUpsert.add(a);
        }
      }
    }

    for (var i = 0; i < toUpsert.length; i += chunkSize) {
      final end = (i + chunkSize < toUpsert.length)
          ? i + chunkSize
          : toUpsert.length;
      final chunk = toUpsert.sublist(i, end);

      try {
        final response = await _supabase!
            .from('activities')
            .upsert(chunk.map(toPayload).toList())
            .select();
        final updatedAtById = {
          for (final row in response)
            row['id'] as String: row['updated_at'] as String?,
        };
        for (final a in chunk) {
          await (_db.update(
            _db.activities,
          )..where((r) => r.id.equals(a.id))).write(
            ActivitiesCompanion(
              syncStatus: Value(domain.SyncStatus.synced),
              updatedAt: Value(
                DateTime.tryParse(updatedAtById[a.remoteId] ?? ''),
              ),
            ),
          );
        }
      } catch (e) {
        for (final a in chunk) {
          try {
            await pushOneUpsert(a);
          } catch (e2) {
            final msg = 'Gagal sync kegiatan ${a.title}: $e2';
            debugPrint(msg);
            errors.add(msg);
          }
        }
      }
    }

    // Deletes, batched the same way.
    final toDelete = pending
        .where(
          (a) =>
              a.syncStatus == domain.SyncStatus.pendingDelete &&
              a.remoteId != null,
        )
        .toList();

    for (var i = 0; i < toDelete.length; i += chunkSize) {
      final end = (i + chunkSize < toDelete.length)
          ? i + chunkSize
          : toDelete.length;
      final chunk = toDelete.sublist(i, end);
      final ids = chunk.map((a) => a.remoteId!).toList();

      try {
        await _supabase!.from('activities').delete().inFilter('id', ids);
        for (final a in chunk) {
          await (_db.delete(
            _db.activities,
          )..where((r) => r.id.equals(a.id))).go();
        }
      } catch (e) {
        for (final a in chunk) {
          try {
            await _supabase!.from('activities').delete().eq('id', a.remoteId!);
            await (_db.delete(
              _db.activities,
            )..where((r) => r.id.equals(a.id))).go();
          } catch (e2) {
            final msg = 'Gagal hapus kegiatan ${a.title}: $e2';
            debugPrint(msg);
            errors.add(msg);
          }
        }
      }
    }

    return errors;
  }

  Future<List<String>> _pullActivities() async {
    final errors = <String>[];
    const pageSize = 500;
    try {
      final cursorRow =
          await (_db.selectOnly(_db.activities)
                ..addColumns([_db.activities.updatedAt.max()])
                ..where(_db.activities.remoteId.isNotNull()))
              .getSingleOrNull();
      var cursor = cursorRow?.read(_db.activities.updatedAt.max());

      while (true) {
        var filterBuilder = _supabase!.from('activities').select();
        if (cursor != null) {
          filterBuilder = filterBuilder.gt(
            'updated_at',
            cursor.toIso8601String(),
          );
        }
        final response = await filterBuilder
            .order('updated_at', ascending: true)
            .limit(pageSize);
        if (response.isEmpty) break;

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

        if (response.length < pageSize) break;
        cursor = DateTime.parse(response.last['updated_at'] as String);
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
        // Tracks a logo-specific failure so it never blocks unrelated
        // name/address edits from syncing (previously a missing/failed
        // logo upload threw before the update/insert call ran at all,
        // freezing the whole profile row -- including fields that have
        // nothing to do with the logo -- until the logo problem resolved).
        var logoUploadFailed = false;
        if (p.logoPath != null) {
          if (p.logoPath!.startsWith('http')) {
            // Already a remote URL
            logoUrl = p.logoPath;
          } else {
            // Local file, try to upload
            try {
              logoUrl = await _uploadFile(p.logoPath!, 'logos');
              if (logoUrl == null) logoUploadFailed = true;
            } catch (e) {
              debugPrint('Gagal upload logo masjid: $e');
              logoUploadFailed = true;
            }
          }
        }

        final data = {
          'name': p.name,
          'address': p.address,
          // Omit the key entirely on failure (rather than sending null) so
          // PostgREST leaves the remote logo_url untouched instead of
          // wiping it out.
          if (!logoUploadFailed) 'logo_url': logoUrl,
        };

        // Nothing in the schema limits mosque_profiles to one row. A device
        // whose local profile has no remoteId yet -- fresh install that edited
        // the profile before its first pull, a reset local DB, a re-register --
        // used to INSERT a second mosque, and from then on different devices
        // would show different names/logos depending on which row their pull
        // happened to land on. Adopt the existing remote row instead; only
        // insert when the mosque genuinely has no profile on the server yet.
        var remoteId = p.remoteId;
        if (remoteId == null) {
          final existing = await _supabase!
              .from('mosque_profiles')
              .select('id')
              .order('created_at', ascending: true)
              .limit(1)
              .maybeSingle();
          remoteId = existing?['id'] as String?;
        }

        Map<String, dynamic> response;
        if (remoteId != null) {
          response = await _supabase!
              .from('mosque_profiles')
              .update(data)
              .eq('id', remoteId)
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
            syncStatus: Value(
              logoUploadFailed
                  ? domain.SyncStatus.pendingUpdate
                  : domain.SyncStatus.synced,
            ),
            updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
          ),
        );

        if (logoUploadFailed) {
          errors.add(
            'Gagal upload logo masjid (nama/alamat tetap tersinkron, logo akan dicoba lagi)',
          );
        }
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
      // order(): nothing constrains mosque_profiles to a single row, and a bare
      // limit(1) lets PostgREST return whichever row it happens to reach first.
      // If duplicates ever exist, two devices would otherwise settle on
      // different profiles and the mosque name/logo would appear to change by
      // itself after a sync. Oldest row wins, consistently, everywhere.
      final response = await _supabase!
          .from('mosque_profiles')
          .select()
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();
      if (response != null) {
        final remoteId = response['id'] as String;
        // order + limit(1) instead of a throwing getSingleOrNull(), in case
        // a pre-fix duplicate row still exists locally on this device.
        final local =
            await (_db.select(_db.mosqueProfiles)
                  ..orderBy([(t) => OrderingTerm.asc(t.id)])
                  ..limit(1))
                .getSingleOrNull();
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
    const pageSize = 500;
    try {
      final cursorRow =
          await (_db.selectOnly(_db.users)
                ..addColumns([_db.users.updatedAt.max()])
                ..where(_db.users.remoteId.isNotNull()))
              .getSingleOrNull();
      var cursor = cursorRow?.read(_db.users.updatedAt.max());

      while (true) {
        var filterBuilder = _supabase!.from('profiles').select();
        if (cursor != null) {
          filterBuilder = filterBuilder.gt(
            'updated_at',
            cursor.toIso8601String(),
          );
        }
        final response = await filterBuilder
            .order('updated_at', ascending: true)
            .limit(pageSize);
        if (response.isEmpty) break;

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

        if (response.length < pageSize) break;
        cursor = DateTime.parse(response.last['updated_at'] as String);
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
