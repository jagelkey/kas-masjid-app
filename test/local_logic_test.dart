import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/repositories/transaction_repository_impl.dart';
import 'package:masjid_app/data/repositories/activity_repository_impl.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain;
import 'package:masjid_app/domain/entities/activity.dart' as activity_domain;
import 'package:masjid_app/domain/entities/audit_log.dart';
import 'package:masjid_app/domain/repositories/audit_log_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';

// Manual Mock
class MockAuditLogRepository implements AuditLogRepository {
  @override
  Future<void> logActivity({
    required String action,
    String? targetTable,
    String? recordId,
    String? description,
  }) async {
    // No-op for test
    return Future.value();
  }

  @override
  Stream<List<AuditLog>> watchLogs() {
    return Stream.value([]);
  }
}

void main() {
  late AppDatabase db;
  late TransactionRepositoryImpl repository;
  late ActivityRepositoryImpl activityRepository;
  late MockAuditLogRepository mockAuditLogRepository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockAuditLogRepository = MockAuditLogRepository();
    repository = TransactionRepositoryImpl(db, mockAuditLogRepository);
    activityRepository = ActivityRepositoryImpl(db, mockAuditLogRepository);
  });

  tearDown(() async {
    await db.close();
  });

  group('TransactionRepository Logic', () {
    test('Add Transaction updates balance correctly', () async {
      // Initial balance should be 0
      expect(await repository.getTotalBalance(), 0.0);

      // Add Income
      final income = domain.Transaction(
        type: domain.TransactionType.income,
        amount: 10000.0,
        category: 'Infaq',
        description: 'Jumat',
        date: DateTime.now(),
        syncStatus: domain.SyncStatus.pendingCreate,
      );
      await repository.addTransaction(income);

      expect(await repository.getTotalBalance(), 10000.0);

      // Add Expense
      final expense = domain.Transaction(
        type: domain.TransactionType.expense,
        amount: 3000.0,
        category: 'Cleaning',
        description: 'Sapu',
        date: DateTime.now(),
        syncStatus: domain.SyncStatus.pendingCreate,
      );
      await repository.addTransaction(expense);

      expect(await repository.getTotalBalance(), 7000.0); // 10000 - 3000
    });

    test('Monthly totals are calculated correctly', () async {
      final now = DateTime.now();
      // Transaction in current month
      await repository.addTransaction(
        domain.Transaction(
          type: domain.TransactionType.income,
          amount: 5000.0,
          category: 'Current Month',
          date: now,
          syncStatus: domain.SyncStatus.pendingCreate,
        ),
      );

      // Transaction in previous month (safely subtract 40 days)
      await repository.addTransaction(
        domain.Transaction(
          type: domain.TransactionType.income,
          amount: 2000.0,
          category: 'Last Month',
          date: now.subtract(const Duration(days: 40)),
          syncStatus: domain.SyncStatus.pendingCreate,
        ),
      );

      expect(await repository.getIncomeThisMonth(), 5000.0);
    });

    test('Delete transaction marks as pendingDelete if synced', () async {
      // 1. Add a transaction that is "synced" (simulated)
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: domain.TransactionType.income,
              amount: 1000.0,
              category: 'Test',
              date: DateTime.now(),
              remoteId: const Value('remote-123'),
              syncStatus: const Value(domain.SyncStatus.synced),
            ),
          );

      // Get the inserted ID
      final tx = await (db.select(db.transactions)..limit(1)).getSingle();

      // 2. Delete it
      await repository.deleteTransaction(tx.id);

      // 3. Verify it is NOT deleted from DB, but marked as pendingDelete
      final deletedTx = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(tx.id))).getSingle();
      expect(deletedTx.syncStatus, domain.SyncStatus.pendingDelete);
    });

    test('Delete transaction removes record if NOT synced', () async {
      // 1. Add a local-only transaction
      await repository.addTransaction(
        domain.Transaction(
          type: domain.TransactionType.income,
          amount: 1000.0,
          category: 'Local',
          date: DateTime.now(),
          syncStatus: domain.SyncStatus.pendingCreate,
        ),
      );

      final tx = await (db.select(db.transactions)..limit(1)).getSingle();

      // 2. Delete it
      await repository.deleteTransaction(tx.id);

      // 3. Verify it is GONE
      final result = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(tx.id))).getSingleOrNull();
      expect(result, isNull);
    });

    test(
      'Update transaction preserves pendingCreate if remoteId is null',
      () async {
        // 1. Add local transaction
        final t = domain.Transaction(
          type: domain.TransactionType.income,
          amount: 1000.0,
          category: 'Test',
          date: DateTime.now(),
          syncStatus: domain.SyncStatus.pendingCreate,
        );
        await repository.addTransaction(t);
        final inserted = await (db.select(
          db.transactions,
        )..limit(1)).getSingle();

        // 2. Update it
        final updated = domain.Transaction(
          id: inserted.id,
          type: domain.TransactionType.income,
          amount: 2000.0,
          category: 'Test',
          date: DateTime.now(),
          syncStatus: domain.SyncStatus.pendingCreate,
        );
        await repository.updateTransaction(updated);

        // 3. Verify status is STILL pendingCreate
        final result = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(inserted.id))).getSingle();
        expect(result.syncStatus, domain.SyncStatus.pendingCreate);
        expect(result.amount, 2000.0);
      },
    );

    test('Update transaction sets pendingUpdate if remoteId exists', () async {
      // 1. Add synced transaction
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: domain.TransactionType.income,
              amount: 1000.0,
              category: 'Test',
              date: DateTime.now(),
              remoteId: const Value('remote-123'),
              syncStatus: const Value(domain.SyncStatus.synced),
            ),
          );
      final inserted = await (db.select(db.transactions)..limit(1)).getSingle();

      // 2. Update it
      final updated = domain.Transaction(
        id: inserted.id,
        remoteId: inserted.remoteId,
        type: domain.TransactionType.income,
        amount: 2000.0,
        category: 'Test',
        date: DateTime.now(),
        syncStatus: domain.SyncStatus.synced,
      );
      await repository.updateTransaction(updated);

      // 3. Verify status is pendingUpdate
      final result = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(inserted.id))).getSingle();
      expect(result.syncStatus, domain.SyncStatus.pendingUpdate);
      expect(result.amount, 2000.0);
    });
  });

  group('ActivityRepository Logic', () {
    test(
      'Update activity preserves pendingCreate if remoteId is null',
      () async {
        // 1. Add local activity
        final a = activity_domain.Activity(
          title: 'Pengajian',
          type: 'Kajian',
          date: DateTime.now(),
          syncStatus: domain.SyncStatus.pendingCreate,
        );
        await activityRepository.addActivity(a);
        final inserted = await (db.select(db.activities)..limit(1)).getSingle();

        // 2. Update it
        final updated = activity_domain.Activity(
          id: inserted.id,
          title: 'Pengajian Rutin',
          type: 'Kajian',
          date: DateTime.now(),
          syncStatus: domain.SyncStatus.pendingCreate,
        );
        await activityRepository.updateActivity(updated);

        // 3. Verify status is STILL pendingCreate
        final result = await (db.select(
          db.activities,
        )..where((t) => t.id.equals(inserted.id))).getSingle();
        expect(result.syncStatus, domain.SyncStatus.pendingCreate);
        expect(result.title, 'Pengajian Rutin');
      },
    );

    test('Update activity sets pendingUpdate if remoteId exists', () async {
      // 1. Add synced activity
      await db
          .into(db.activities)
          .insert(
            ActivitiesCompanion.insert(
              title: 'Sholat Jumat',
              type: 'Ibadah',
              date: DateTime.now(),
              remoteId: const Value('remote-act-123'),
              syncStatus: const Value(domain.SyncStatus.synced),
            ),
          );
      final inserted = await (db.select(db.activities)..limit(1)).getSingle();

      // 2. Update it
      final updated = activity_domain.Activity(
        id: inserted.id,
        remoteId: inserted.remoteId,
        title: 'Sholat Jumat Berjamaah',
        type: 'Ibadah',
        date: DateTime.now(),
        syncStatus: domain.SyncStatus.synced,
      );
      await activityRepository.updateActivity(updated);

      // 3. Verify status is pendingUpdate
      final result = await (db.select(
        db.activities,
      )..where((t) => t.id.equals(inserted.id))).getSingle();
      expect(result.syncStatus, domain.SyncStatus.pendingUpdate);
      expect(result.title, 'Sholat Jumat Berjamaah');
    });
  });
}
