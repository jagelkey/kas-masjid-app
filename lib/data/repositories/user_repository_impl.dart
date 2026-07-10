import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain_status;
import 'package:masjid_app/domain/entities/user.dart' as domain;
import 'package:masjid_app/domain/repositories/user_repository.dart';

import 'package:masjid_app/domain/repositories/audit_log_repository.dart';

@LazySingleton(as: UserRepository)
class UserRepositoryImpl implements UserRepository {
  final AppDatabase _db;
  final AuditLogRepository _auditLogRepository;

  UserRepositoryImpl(this._db, this._auditLogRepository);

  @override
  Stream<List<domain.UserEntity>> watchUsers() {
    return (_db.select(_db.users)..where(
          (t) => t.syncStatus.isNotValue(
            domain_status.SyncStatus.pendingDelete.index,
          ),
        ))
        .watch()
        .map((rows) => rows.map((row) => _mapToDomain(row)).toList());
  }

  @override
  Future<List<domain.UserEntity>> getUsers() async {
    final rows =
        await (_db.select(_db.users)..where(
              (t) => t.syncStatus.isNotValue(
                domain_status.SyncStatus.pendingDelete.index,
              ),
            ))
            .get();
    return rows.map((row) => _mapToDomain(row)).toList();
  }

  @override
  Future<void> addUser(domain.UserEntity user) async {
    // Wrapped in a transaction so the audit trail entry can never be lost
    // (or the write silently un-recorded) if the app is killed between the
    // two statements.
    await _db.transaction(() async {
      await _db
          .into(_db.users)
          .insert(
            UsersCompanion(
              remoteId: Value(user.remoteId),
              email: Value(user.email),
              username: Value(user.username),
              fullName: Value(user.fullName),
              role: Value(user.role),
              syncStatus: Value(
                domain_status.SyncStatus.values[user.syncStatus],
              ),
            ),
          );

      await _auditLogRepository.logActivity(
        action: 'CREATE',
        targetTable: 'users',
        description: 'User: ${user.fullName} (${user.role})',
      );
    });
  }

  @override
  Future<void> updateUser(domain.UserEntity user) async {
    if (user.id == null) return;
    await _db.transaction(() async {
      await (_db.update(_db.users)..where((t) => t.id.equals(user.id!))).write(
        UsersCompanion(
          email: Value(user.email),
          fullName: Value(user.fullName),
          username: Value(user.username),
          role: Value(user.role),
          syncStatus: Value(domain_status.SyncStatus.values[user.syncStatus]),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _auditLogRepository.logActivity(
        action: 'UPDATE',
        targetTable: 'users',
        recordId: user.id.toString(),
        description: 'Updated User: ${user.fullName}',
      );
    });
  }

  @override
  Future<void> deleteUser(int id) async {
    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (user == null) return;

    // Validate relations before deleting
    final relatedLogs = await (_db.select(
      _db.auditLogs,
    )..where((t) => t.userId.equals(user.remoteId ?? user.email))).get();

    // picName is a free-text copy of the user's name, not a real foreign
    // key, so this match is inherently best-effort. Guard against the
    // specific bug where a null fullName silently matched against an
    // empty-string picName -- which never matches a NULL picName column in
    // SQL, so the check always passed vacuously for any user with no
    // stored full name, without anyone intending that as a valid outcome.
    final trimmedFullName = user.fullName?.trim();
    final relatedActivities = (trimmedFullName == null || trimmedFullName.isEmpty)
        ? const <ActivityEntity>[]
        : await (_db.select(
            _db.activities,
          )..where((t) => t.picName.equals(trimmedFullName))).get();

    if (relatedLogs.isNotEmpty || relatedActivities.isNotEmpty) {
      throw Exception(
        'Tidak dapat menghapus user karena masih memiliki riwayat aktivitas atau transaksi.',
      );
    }

    // Wrapped in a transaction so the audit trail entry can never be lost
    // (or the delete silently un-recorded) if the app is killed between the
    // two statements.
    await _db.transaction(() async {
      if (user.remoteId != null) {
        await (_db.update(_db.users)..where((t) => t.id.equals(id))).write(
          UsersCompanion(
            syncStatus: Value(domain_status.SyncStatus.pendingDelete),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await (_db.delete(_db.users)..where((t) => t.id.equals(id))).go();
      }

      await _auditLogRepository.logActivity(
        action: 'DELETE',
        targetTable: 'users',
        recordId: id.toString(),
        description: 'Deleted User: ${user.fullName}',
      );
    });
  }

  @override
  Future<domain.UserEntity?> getUserByRemoteId(String remoteId) async {
    final row = await (_db.select(
      _db.users,
    )..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
    if (row == null) return null;
    return _mapToDomain(row);
  }

  @override
  Future<domain.UserEntity?> getUserByUsername(String username) async {
    final normalized = username.toLowerCase();
    final row = await (_db.select(
      _db.users,
    )..where((t) => t.username.equals(normalized))).getSingleOrNull();
    if (row == null) return null;
    return _mapToDomain(row);
  }

  @override
  Future<domain.UserEntity?> getUserByEmail(String email) async {
    final normalized = email.toLowerCase();
    final row = await (_db.select(
      _db.users,
    )..where((t) => t.email.equals(normalized))).getSingleOrNull();
    if (row == null) return null;
    return _mapToDomain(row);
  }

  @override
  Future<domain.UserEntity?> getUserById(int id) async {
    final row = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _mapToDomain(row);
  }

  domain.UserEntity _mapToDomain(UserEntity row) {
    return domain.UserEntity(
      id: row.id,
      remoteId: row.remoteId,
      email: row.email,
      username: row.username,
      fullName: row.fullName,
      role: row.role,
      syncStatus: row.syncStatus.index,
    );
  }
}
