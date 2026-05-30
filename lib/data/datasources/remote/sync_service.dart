import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:get_it/get_it.dart';
import 'package:masjid_app/core/constants/env.dart';
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
  late final SupabaseClient? _adminSupabase;
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
      if (Env.supabaseServiceRoleKey.isNotEmpty) {
        _adminSupabase = SupabaseClient(
          Env.supabaseUrl,
          Env.supabaseServiceRoleKey,
        );
      } else {
        _adminSupabase = null;
      }

      // Only listen to connectivity if Supabase is initialized
      if (_supabase != null) {
        _initConnectivityListener();
      }
    } catch (_) {
      _supabase = null;
      _adminSupabase = null;
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
      final client = _adminSupabase ?? _supabase;
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

      final authLocalDatasource = GetIt.I<AuthLocalDatasource>();

      for (final user in pendingCreate) {
        try {
          if (_adminSupabase != null) {
            final password = await authLocalDatasource.getPendingUserPassword(
              user.remoteId!,
            );

            if (password == null) {
              throw Exception('Password not found for pending user');
            }

            try {
              final response = await _adminSupabase.auth.admin.createUser(
                AdminUserAttributes(
                  email: user.email,
                  password: password,
                  emailConfirm: true,
                  userMetadata: {
                    'full_name': user.fullName,
                    'username': user.username,
                    'role': user.role,
                  },
                ),
              );

              if (response.user != null) {
                final newRemoteId = response.user!.id;
                await _updateUserSynced(
                  user.id,
                  newRemoteId,
                  response.user?.updatedAt,
                );
                await authLocalDatasource.deletePendingUserPassword(
                  user.remoteId!,
                );
              }
            } catch (e) {
              final errorStr = e.toString().toLowerCase();
              if (errorStr.contains('already registered') ||
                  errorStr.contains('exists')) {
                // Conflict: User already exists in Supabase Auth.
                // Try to find the user in 'profiles' table to get their ID
                debugPrint(
                  'User ${user.email} already exists. Attempting to link...',
                );
                final existing = await _supabase!
                    .from('profiles')
                    .select('id')
                    .eq('email', user.email)
                    .maybeSingle();

                if (existing != null) {
                  final existingId = existing['id'] as String;
                  await _updateUserSynced(user.id, existingId, null);
                  await authLocalDatasource.deletePendingUserPassword(
                    user.remoteId!,
                  );
                } else {
                  // If not in profiles, we might need manual intervention or just skip
                  throw Exception(
                    'User exists in Auth but not in Profiles. Sync blocked.',
                  );
                }
              } else {
                rethrow;
              }
            }
          } else {
            throw Exception('Service Role Key required for creating users');
          }
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
          // 1. Update Auth User (Email, Password if handled separately, Metadata)
          // Requires Service Role Key for Admin operations on other users
          if (_adminSupabase != null) {
            final attributes = AdminUserAttributes(
              email: user.email,
              userMetadata: {
                'full_name': user.fullName,
                'username': user.username,
                'role': user.role,
              },
            );
            await _adminSupabase.auth.admin.updateUserById(
              user.remoteId!,
              attributes: attributes,
            );
          }

          // 2. Update public profile
          final response = await client
              .from('profiles')
              .update({
                'full_name': user.fullName,
                'username': user.username,
                'role': user.role,
                'email': user.email,
              })
              .eq('id', user.remoteId!)
              .select()
              .single();

          await (_db.update(
            _db.users,
          )..where((r) => r.id.equals(user.id))).write(
            UsersCompanion(
              syncStatus: Value(domain.SyncStatus.synced),
              updatedAt: Value(DateTime.tryParse(response['updated_at'] ?? '')),
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
          // Delete from Auth (requires Service Role Key)
          if (_adminSupabase != null) {
            try {
              // 1. Try to delete profile explicitly first.
              // This can resolve DB constraint errors where CASCADE might fail.
              await _adminSupabase
                  .from('profiles')
                  .delete()
                  .eq('id', user.remoteId!);

              // 2. Delete from Auth
              await _adminSupabase.auth.admin.deleteUser(user.remoteId!);
              debugPrint(
                'Successfully deleted user ${user.fullName} from remote.',
              );
            } catch (e) {
              final errorStr = e.toString();
              // If user or profile already gone (404), we consider it a success for sync purposes
              if (errorStr.contains('404') || errorStr.contains('not found')) {
                debugPrint(
                  'User ${user.remoteId} already gone from remote. Proceeding with local delete.',
                );
              } else {
                // For other errors (like 500), we rethrow to outer catch block
                // and keep the user in pendingDelete state for retry.
                rethrow;
              }
            }
          } else {
            throw Exception('Service Role Key required for deleting users');
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
