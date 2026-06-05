import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/repositories/transaction_repository_impl.dart';
import 'package:masjid_app/data/repositories/activity_repository_impl.dart';
import 'package:masjid_app/data/repositories/qurban_repository_impl.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
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
  late QurbanRepositoryImpl qurbanRepository;
  late MockAuditLogRepository mockAuditLogRepository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockAuditLogRepository = MockAuditLogRepository();
    repository = TransactionRepositoryImpl(db, mockAuditLogRepository);
    activityRepository = ActivityRepositoryImpl(db, mockAuditLogRepository);
    qurbanRepository = QurbanRepositoryImpl(db, mockAuditLogRepository);
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

    test(
      'Update transaction preserves pendingCreate if remoteId is a local UUID',
      () async {
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: domain.TransactionType.income,
                amount: 1000.0,
                category: 'Local UUID',
                date: DateTime.now(),
                remoteId: const Value('local-temp-id'),
                syncStatus: const Value(domain.SyncStatus.pendingCreate),
              ),
            );

        final inserted = await (db.select(
          db.transactions,
        )..limit(1)).getSingle();

        await repository.updateTransaction(
          domain.Transaction(
            id: inserted.id,
            remoteId: inserted.remoteId,
            type: domain.TransactionType.income,
            amount: 2500.0,
            category: 'Local UUID Updated',
            date: DateTime.now(),
            syncStatus: domain.SyncStatus.pendingCreate,
          ),
        );

        final result = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(inserted.id))).getSingle();

        expect(result.syncStatus, domain.SyncStatus.pendingCreate);
        expect(result.amount, 2500.0);
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

  group('QurbanRepository Logic', () {
    test('Seed package defaults are available', () async {
      final packages = await qurbanRepository.getPackages();

      expect(
        packages.map((p) => p.monthlyAmount),
        containsAll([250000, 275000]),
      );
      expect(packages.every((p) => p.isActive), isTrue);
    });

    test('Participant custom amount produces 10 month target', () async {
      await qurbanRepository.addParticipant(
        QurbanParticipant(
          name: 'Ahmad',
          startMonth: DateTime(2026, 1),
          monthlyAmount: 300000,
        ),
      );

      final progress = await qurbanRepository.getParticipantProgress();

      expect(progress.single.participant.targetAmount, 3000000);
      expect(progress.single.participant.totalMonths, 10);
    });

    test(
      'Flexible payments calculate paid, remaining, and overpaid status',
      () async {
        await qurbanRepository.addParticipant(
          QurbanParticipant(
            name: 'Budi',
            startMonth: DateTime.now(),
            monthlyAmount: 250000,
          ),
        );
        final participant = (await qurbanRepository.getParticipantProgress())
            .single
            .participant;

        await qurbanRepository.addPayment(
          QurbanPayment(
            participantId: participant.id!,
            amount: 1000000,
            paymentDate: DateTime.now(),
          ),
        );
        var progress = (await qurbanRepository.getParticipantProgress()).single;
        expect(progress.paidAmount, 1000000);
        expect(progress.remainingAmount, 1500000);

        await qurbanRepository.addPayment(
          QurbanPayment(
            participantId: participant.id!,
            amount: 1600000,
            paymentDate: DateTime.now(),
          ),
        );
        progress = (await qurbanRepository.getParticipantProgress()).single;
        expect(progress.paidAmount, 2600000);
        expect(progress.status, QurbanProgressStatus.overpaid);
      },
    );

    test('Add payment creates linked qurban income transaction', () async {
      await qurbanRepository.addParticipant(
        QurbanParticipant(
          name: 'Chandra',
          startMonth: DateTime.now(),
          monthlyAmount: 275000,
        ),
      );
      final participant =
          (await qurbanRepository.getParticipantProgress()).single.participant;

      await qurbanRepository.addPayment(
        QurbanPayment(
          participantId: participant.id!,
          amount: 275000,
          paymentDate: DateTime.now(),
          note: 'Bulan 1',
        ),
      );

      final payment = (await qurbanRepository.getPaymentsForParticipant(
        participant.id!,
      )).single;
      final transaction = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(payment.transactionId!))).getSingle();

      expect(transaction.type, domain.TransactionType.income);
      expect(transaction.category, 'Iuran Qurban');
      expect(transaction.amount, 275000);
      expect(transaction.source, domain.TransactionSource.qurban);
      expect(transaction.sourceRef, payment.remoteId);
    });

    test(
      'Update and delete payment keeps linked transaction consistent',
      () async {
        await qurbanRepository.addParticipant(
          QurbanParticipant(
            name: 'Dedi',
            startMonth: DateTime.now(),
            monthlyAmount: 250000,
          ),
        );
        final participant = (await qurbanRepository.getParticipantProgress())
            .single
            .participant;

        await qurbanRepository.addPayment(
          QurbanPayment(
            participantId: participant.id!,
            amount: 250000,
            paymentDate: DateTime.now(),
          ),
        );
        final payment = (await qurbanRepository.getPaymentsForParticipant(
          participant.id!,
        )).single;

        await qurbanRepository.updatePayment(
          payment.copyWith(amount: 300000, note: 'Revisi'),
        );

        final updatedPayment =
            (await qurbanRepository.getPaymentsForParticipant(
              participant.id!,
            )).single;
        final transaction =
            await (db.select(db.transactions)
                  ..where((t) => t.id.equals(updatedPayment.transactionId!)))
                .getSingle();

        expect(updatedPayment.syncStatus, domain.SyncStatus.pendingCreate);
        expect(transaction.syncStatus, domain.SyncStatus.pendingCreate);
        expect(transaction.amount, 300000);

        await qurbanRepository.deletePayment(updatedPayment.id!);

        final remainingPayments = await qurbanRepository
            .getPaymentsForParticipant(participant.id!);
        final remainingTransaction =
            await (db.select(db.transactions)
                  ..where((t) => t.id.equals(updatedPayment.transactionId!)))
                .getSingleOrNull();

        expect(remainingPayments, isEmpty);
        expect(remainingTransaction, isNull);
      },
    );

    test('Update participant preserves pendingCreate status', () async {
      await qurbanRepository.addParticipant(
        QurbanParticipant(
          name: 'Eko',
          startMonth: DateTime.now(),
          monthlyAmount: 250000,
        ),
      );
      final participant =
          (await qurbanRepository.getParticipantProgress()).single.participant;

      await qurbanRepository.updateParticipant(
        participant.copyWith(name: 'Eko Prasetyo'),
      );

      final row = await (db.select(
        db.qurbanParticipants,
      )..where((t) => t.id.equals(participant.id!))).getSingle();
      expect(row.syncStatus, domain.SyncStatus.pendingCreate);
      expect(row.name, 'Eko Prasetyo');
    });
  });
}
