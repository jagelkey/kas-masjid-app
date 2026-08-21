// Regression tests for bugs found in the 2026-07-10 deep audit.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/local/auth_local_datasource.dart';
import 'package:masjid_app/data/repositories/qurban_repository_impl.dart';
import 'package:masjid_app/data/repositories/transaction_repository_impl.dart';
import 'package:masjid_app/domain/entities/audit_log.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain;
import 'package:masjid_app/domain/repositories/audit_log_repository.dart';
import 'package:masjid_app/presentation/blocs/transaction/transaction_bloc.dart';

class _NoopAuditLogRepository implements AuditLogRepository {
  @override
  Future<void> logActivity({
    required String action,
    String? targetTable,
    String? recordId,
    String? description,
  }) async {}

  @override
  Stream<List<AuditLog>> watchLogs() => Stream.value([]);
}

void main() {
  group('Provisioning an account for someone else', () {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    late Map<String, String> store;
    late AuthLocalDatasource auth;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      store = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'read':
            return store[key];
          case 'delete':
            store.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.from(store);
          case 'deleteAll':
            store.clear();
            return null;
          case 'containsKey':
            return store.containsKey(key);
        }
        return null;
      });
      auth = AuthLocalDatasource();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    // saveCredentials() always rewrote the single "last logged in email"
    // pointer. When an admin created a user offline, the device silently
    // adopted that new account on the next restart -- the admin came back as a
    // viewer, on their own phone.
    test('does not hijack the admin session on this device', () async {
      await auth.saveCredentials(
        email: 'Admin@Masjid.test',
        password: 'rahasia-admin',
        role: 'admin',
        userId: 'admin-uuid',
        metadata: const {'full_name': 'Admin'},
      );
      expect((await auth.getLastLoggedInUser())!.email, 'admin@masjid.test');

      await auth.saveCredentials(
        email: 'bob@masjid.test',
        password: 'rahasia-bob',
        role: 'viewer',
        userId: 'bob-uuid',
        metadata: const {'full_name': 'Bob'},
        markAsLastLoggedIn: false,
      );

      final current = await auth.getLastLoggedInUser();
      expect(
        current!.email,
        'admin@masjid.test',
        reason: 'the admin must remain the active user after provisioning Bob',
      );

      // Bob can still sign in offline on this device, and his role is stored
      // separately -- the point is only that he is not the *current* user.
      final bob = await auth.verifyCredentials('bob@masjid.test', 'rahasia-bob');
      expect(bob, isNotNull);
      expect(await auth.getStoredRole('bob@masjid.test'), 'viewer');
      expect(await auth.getStoredRole('admin@masjid.test'), 'admin');
    });
  });

  group('TransactionBloc filter reset', () {
    late AppDatabase db;
    late TransactionBloc bloc;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      bloc = TransactionBloc(
        TransactionRepositoryImpl(db, _NoopAuditLogRepository()),
      );
    });

    tearDown(() async {
      await bloc.close();
      await db.close();
    });

    // The old TransactionLoaded.copyWith() used `filterDateRange ?? this.filterDateRange`,
    // so an ApplyFilterEvent carrying nulls (the Reset button) could never clear a
    // filter. The visible list looked reset, but state.filterDateRange stayed stale --
    // and the PDF export reads its reported period straight off that field.
    test('ApplyFilterEvent with nulls actually clears an active filter', () async {
      final jan = DateTimeRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 31),
      );

      bloc.add(const TransactionsUpdated([]));
      await pumpEventQueue();
      expect(bloc.state, isA<TransactionLoaded>());

      bloc.add(ApplyFilterEvent(dateRange: jan, category: 'Infaq'));
      await pumpEventQueue();
      var loaded = bloc.state as TransactionLoaded;
      expect(loaded.filterDateRange, jan);
      expect(loaded.filterCategory, 'Infaq');

      // The Reset button dispatches exactly this.
      bloc.add(const ApplyFilterEvent(dateRange: null, type: null, category: null));
      await pumpEventQueue();
      loaded = bloc.state as TransactionLoaded;
      expect(loaded.filterDateRange, isNull);
      expect(loaded.filterCategory, isNull);
      expect(loaded.filterType, isNull);
    });

    // Once the filter is cleared, any later DB change (a sync pull, a new entry)
    // must not silently re-apply the old range via _onTransactionsUpdated.
    test('a cleared filter is not re-applied on the next DB update', () async {
      final tx = domain.Transaction(
        type: domain.TransactionType.income,
        amount: 5000,
        category: 'Infaq',
        date: DateTime(2026, 6, 15), // outside the January filter below
      );

      bloc.add(const TransactionsUpdated([]));
      await pumpEventQueue();

      bloc.add(
        ApplyFilterEvent(
          dateRange: DateTimeRange(
            start: DateTime(2026, 1, 1),
            end: DateTime(2026, 1, 31),
          ),
        ),
      );
      await pumpEventQueue();

      bloc.add(const ApplyFilterEvent());
      await pumpEventQueue();

      bloc.add(TransactionsUpdated([tx]));
      await pumpEventQueue();

      final loaded = bloc.state as TransactionLoaded;
      expect(loaded.filterDateRange, isNull);
      expect(
        loaded.filteredTransactions.length,
        1,
        reason: 'June transaction must survive: the January filter was reset',
      );
    });
  });

  // A qurban payment pulled from the server before its cash transaction reached
  // this device lands with transactionId = null. The link is recoverable via
  // transactions.source_ref, which holds the payment's remoteId.
  group('Qurban payment with a lost transaction link', () {
    late AppDatabase db;
    late QurbanRepositoryImpl qurban;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      qurban = QurbanRepositoryImpl(db, _NoopAuditLogRepository());
    });

    tearDown(() async => db.close());

    /// Adds a participant + payment, then reproduces the "pulled without its
    /// transaction" state: the payment forgets its link, but the transaction
    /// still carries source_ref = payment.remoteId. Both look synced.
    Future<QurbanPayment> seedPaymentWithBrokenLink() async {
      await qurban.addParticipant(
        QurbanParticipant(
          name: 'Peserta Sync',
          startMonth: DateTime.now(),
          monthlyAmount: 250000,
        ),
      );
      final participant =
          (await qurban.getParticipantProgress()).single.participant;

      await qurban.addPayment(
        QurbanPayment(
          participantId: participant.id!,
          amount: 250000,
          paymentDate: DateTime.now(),
        ),
      );
      final payment =
          (await qurban.getPaymentsForParticipant(participant.id!)).single;

      await (db.update(db.transactions)
            ..where((t) => t.id.equals(payment.transactionId!)))
          .write(const TransactionsCompanion(
            syncStatus: Value(domain.SyncStatus.synced),
          ));
      await (db.update(db.qurbanPayments)
            ..where((t) => t.id.equals(payment.id!)))
          .write(const QurbanPaymentsCompanion(
            transactionId: Value(null),
            syncStatus: Value(domain.SyncStatus.synced),
          ));

      return (await qurban.getPaymentsForParticipant(participant.id!)).single;
    }

    Future<List<TransactionEntity>> qurbanTransactions() =>
        (db.select(db.transactions)
              ..where((t) => t.source.equals(domain.TransactionSource.qurban)))
            .get();

    test('editing it does not create a second income transaction', () async {
      final broken = await seedPaymentWithBrokenLink();
      expect(broken.transactionId, isNull);
      expect((await qurbanTransactions()).length, 1);

      await qurban.updatePayment(broken.copyWith(amount: 300000));

      final txs = await qurbanTransactions();
      expect(
        txs.length,
        1,
        reason: 'a duplicate income row would inflate the cash balance',
      );
      expect(txs.single.amount, 300000);

      final relinked =
          (await qurban.getPaymentsForParticipant(broken.participantId)).single;
      expect(relinked.transactionId, txs.single.id);
    });

    test('deleting it does not orphan the income transaction', () async {
      final broken = await seedPaymentWithBrokenLink();

      await qurban.deletePayment(broken.id!);

      final txs = await qurbanTransactions();
      expect(txs.length, 1, reason: 'synced rows are soft-deleted, not removed');
      expect(
        txs.single.syncStatus,
        domain.SyncStatus.pendingDelete,
        reason: 'the income must be withdrawn with its payment',
      );
    });
  });

  group('Default qurban package seeding', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('masjid_seed_test');
      dbFile = File('${tempDir.path}/seed_test.sqlite');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('seeds the two defaults on a brand new database', () async {
      final db = AppDatabase(NativeDatabase(dbFile));
      final packages = await db.select(db.qurbanPackages).get();
      expect(packages.length, 2);
      expect(packages.map((p) => p.monthlyAmount).toList()..sort(), [
        250000.0,
        275000.0,
      ]);
      await db.close();
    });

    // Seeding used to run in beforeOpen on EVERY open, guarded only by
    // "are there zero packages?". An admin who deliberately deleted every
    // package got them recreated on the next app start -- and then re-pushed
    // to the server, undoing the deletion for every other device too.
    test('does not resurrect packages the admin deleted', () async {
      final first = AppDatabase(NativeDatabase(dbFile));
      expect((await first.select(first.qurbanPackages).get()).length, 2);
      await first.delete(first.qurbanPackages).go();
      expect((await first.select(first.qurbanPackages).get()).length, 0);
      await first.close();

      final reopened = AppDatabase(NativeDatabase(dbFile));
      final afterRestart = await reopened.select(reopened.qurbanPackages).get();
      await reopened.close();

      expect(
        afterRestart,
        isEmpty,
        reason: 'restarting the app must not re-seed deleted packages',
      );
    });
  });
}
