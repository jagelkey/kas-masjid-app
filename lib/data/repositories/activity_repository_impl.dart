import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/domain/entities/activity.dart' as domain;
import 'package:masjid_app/domain/entities/transaction.dart' as domain_status;
import 'package:masjid_app/domain/repositories/activity_repository.dart';

import 'package:masjid_app/domain/repositories/audit_log_repository.dart';

@LazySingleton(as: ActivityRepository)
class ActivityRepositoryImpl implements ActivityRepository {
  final AppDatabase _db;
  final AuditLogRepository _auditLogRepository;

  ActivityRepositoryImpl(this._db, this._auditLogRepository);

  @override
  Stream<List<domain.Activity>> watchActivities() {
    return (_db.select(_db.activities)
          ..where(
            (t) => t.syncStatus.isNotValue(
              domain_status.SyncStatus.pendingDelete.index,
            ),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
          ]))
        .watch()
        .map((rows) => rows.map((row) => _mapToDomain(row)).toList());
  }

  @override
  Future<List<domain.Activity>> getActivities() async {
    final rows =
        await (_db.select(_db.activities)
              ..where(
                (t) => t.syncStatus.isNotValue(
                  domain_status.SyncStatus.pendingDelete.index,
                ),
              )
              ..orderBy([
                (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
              ]))
            .get();
    return rows.map((row) => _mapToDomain(row)).toList();
  }

  @override
  Future<void> addActivity(domain.Activity activity) async {
    // Wrapped in a transaction so the audit trail entry can never be lost
    // (or the write silently un-recorded) if the app is killed between the
    // two statements.
    await _db.transaction(() async {
      await _db
          .into(_db.activities)
          .insert(
            ActivitiesCompanion(
              remoteId: Value(activity.remoteId),
              title: Value(activity.title),
              description: Value(activity.description),
              type: Value(activity.type),
              date: Value(activity.date),
              picName: Value(activity.picName),
              syncStatus: Value(domain_status.SyncStatus.pendingCreate),
            ),
          );

      await _auditLogRepository.logActivity(
        action: 'CREATE',
        targetTable: 'activities',
        description: 'Activity: ${activity.title} (${activity.type})',
      );
    });
  }

  @override
  Future<void> updateActivity(domain.Activity activity) async {
    if (activity.id == null) return;

    // Check existing sync status and remoteId
    final existing = await (_db.select(
      _db.activities,
    )..where((t) => t.id.equals(activity.id!))).getSingleOrNull();

    if (existing == null) return;

    final newSyncStatus =
        existing.syncStatus == domain_status.SyncStatus.pendingCreate
        ? domain_status.SyncStatus.pendingCreate
        : domain_status.SyncStatus.pendingUpdate;

    await _db.transaction(() async {
      await (_db.update(
        _db.activities,
      )..where((t) => t.id.equals(activity.id!))).write(
        ActivitiesCompanion(
          title: Value(activity.title),
          description: Value(activity.description),
          type: Value(activity.type),
          date: Value(activity.date),
          picName: Value(activity.picName),
          syncStatus: Value(newSyncStatus),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _auditLogRepository.logActivity(
        action: 'UPDATE',
        targetTable: 'activities',
        recordId: activity.id.toString(),
        description: 'Updated Activity: ${activity.title}',
      );
    });
  }

  @override
  Future<void> deleteActivity(int id) async {
    final activity = await (_db.select(
      _db.activities,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (activity == null) return;

    await _db.transaction(() async {
      if (activity.remoteId != null) {
        await (_db.update(
          _db.activities,
        )..where((t) => t.id.equals(id))).write(
          ActivitiesCompanion(
            syncStatus: Value(domain_status.SyncStatus.pendingDelete),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await (_db.delete(_db.activities)..where((t) => t.id.equals(id))).go();
      }

      await _auditLogRepository.logActivity(
        action: 'DELETE',
        targetTable: 'activities',
        recordId: id.toString(),
        description: 'Deleted Activity: ${activity.title}',
      );
    });
  }

  domain.Activity _mapToDomain(ActivityEntity row) {
    return domain.Activity(
      id: row.id,
      remoteId: row.remoteId,
      title: row.title,
      description: row.description,
      type: row.type,
      date: row.date,
      picName: row.picName,
      syncStatus: row.syncStatus,
    );
  }
}
