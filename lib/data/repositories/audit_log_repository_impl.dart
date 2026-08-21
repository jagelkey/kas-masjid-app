import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:injectable/injectable.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/local/auth_local_datasource.dart';
import 'package:masjid_app/domain/entities/audit_log.dart';
import 'package:masjid_app/domain/repositories/audit_log_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain_status;

@LazySingleton(as: AuditLogRepository)
class AuditLogRepositoryImpl implements AuditLogRepository {
  final AppDatabase _db;
  final AuthLocalDatasource _authLocalDatasource;

  AuditLogRepositoryImpl(this._db, this._authLocalDatasource);

  Future<String?> _getCurrentUserId() async {
    // 1. Try Supabase Auth (Online)
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        return user.id;
      }
    } catch (_) {}

    // 2. Try Local Storage (Offline)
    final localUserId = await _authLocalDatasource.getLastUserId();
    return localUserId ?? 'offline_user';
  }

  @override
  Future<void> logActivity({
    required String action,
    String? targetTable,
    String? recordId,
    String? description,
  }) async {
    // Get current user ID
    String userId = await _getCurrentUserId() ?? 'system';

    // Wrap in try/catch: audit logging failure must NOT roll back the
    // business operation that triggered it. Fire-and-forget with a
    // debug warning instead.
    try {
      await _db
          .into(_db.auditLogs)
          .insert(
            AuditLogsCompanion(
              userId: Value(userId),
              action: Value(action),
              targetTable: Value(targetTable),
              recordId: Value(recordId),
              description: Value(description),
              syncStatus: Value(domain_status.SyncStatus.pendingCreate),
              createdAt: Value(DateTime.now()),
            ),
          );
    } catch (e) {
      debugPrint('Warning: Failed to write audit log: $e');
    }
  }

  @override
  Stream<List<AuditLog>> watchLogs() {
    final query = _db.select(_db.auditLogs).join([
      leftOuterJoin(
        _db.users,
        _db.users.remoteId.equalsExp(_db.auditLogs.userId),
      ),
    ]);

    query.orderBy([
      OrderingTerm(
        expression: _db.auditLogs.createdAt,
        mode: OrderingMode.desc,
      ),
    ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final log = row.readTable(_db.auditLogs);
        final user = row.readTableOrNull(_db.users);
        return _mapToDomain(log, user?.fullName ?? user?.username);
      }).toList();
    });
  }

  AuditLog _mapToDomain(AuditLogEntity row, String? userName) {
    return AuditLog(
      id: row.id,
      remoteId: row.remoteId,
      userId: row.userId,
      userName: userName,
      action: row.action,
      targetTable: row.targetTable,
      recordId: row.recordId,
      description: row.description,
      createdAt: row.createdAt,
      syncStatus: row.syncStatus.index,
    );
  }
}
