import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain;

// Regression coverage for M11 (production audit, 2026-07-09): onUpgrade
// wraps every migration step in a try/catch, so a step that silently fails
// (e.g. a column never gets added) would otherwise go unnoticed until a
// query against that column crashes in the field. This doesn't replay the
// full historical version-1-to-current upgrade path (that needs Drift's
// schema-snapshot tooling, which this project hasn't set up) -- it checks
// that the current onCreate path actually produces every column/table/index
// the code depends on, and that the constraints added for M3 are truly
// enforced at runtime rather than just declared.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Schema smoke test', () {
    test('database opens and reports the expected schema version', () async {
      final result = await db.customSelect('PRAGMA user_version').getSingle();
      expect(result.data['user_version'], db.schemaVersion);
    });

    test('columns/tables added across historical migrations all exist', () async {
      // Each of these throws if the column/table is missing -- a cheap
      // proxy for "did a migration step actually run."
      await db.customSelect(
        'SELECT remote_id, sync_status, updated_at FROM mosque_profiles',
      ).get();
      await db.customSelect('SELECT username FROM users').get();
      await db.customSelect(
        'SELECT proof_paths, proof_urls, source, source_ref FROM transactions',
      ).get();
      await db.customSelect('SELECT * FROM qurban_packages').get();
      await db.customSelect('SELECT * FROM qurban_participants').get();
      await db.customSelect('SELECT * FROM qurban_payments').get();
      await db.customSelect('SELECT * FROM audit_logs').get();
    });

    test('partial unique index rejects a duplicate transactions.remote_id', () async {
      const dupRemoteId = 'dup-remote-id';
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              remoteId: const Value(dupRemoteId),
              type: domain.TransactionType.income,
              amount: 10000,
              category: 'Infaq',
              date: DateTime(2026, 1, 1),
            ),
          );

      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                remoteId: const Value(dupRemoteId),
                type: domain.TransactionType.income,
                amount: 20000,
                category: 'Infaq',
                date: DateTime(2026, 1, 2),
              ),
            ),
        throwsA(anything),
      );
    });

    test(
      'partial unique index allows multiple NULL remote_id (unsynced rows)',
      () async {
        // Two never-synced local rows both have remote_id == null -- the
        // partial index (WHERE remote_id IS NOT NULL) must not treat that
        // as a duplicate, or ordinary offline transaction entry would break.
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: domain.TransactionType.expense,
                amount: 5000,
                category: 'Operasional',
                date: DateTime(2026, 1, 1),
              ),
            );
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: domain.TransactionType.expense,
                amount: 6000,
                category: 'Operasional',
                date: DateTime(2026, 1, 2),
              ),
            );

        final rows = await db.select(db.transactions).get();
        expect(rows.length, 2);
      },
    );

    test(
      'partial unique index rejects a duplicate qurban_payments.remote_id',
      () async {
        const dupRemoteId = 'dup-payment-remote-id';
        await db
            .into(db.qurbanParticipants)
            .insert(
              QurbanParticipantsCompanion.insert(
                name: 'Test',
                startMonth: DateTime(2026, 1, 1),
                monthlyAmount: 250000,
              ),
            );
        final participantId = (await db
                .select(db.qurbanParticipants)
                .getSingle())
            .id;

        await db
            .into(db.qurbanPayments)
            .insert(
              QurbanPaymentsCompanion.insert(
                remoteId: const Value(dupRemoteId),
                participantId: participantId,
                amount: 250000,
                paymentDate: DateTime(2026, 1, 1),
              ),
            );

        expect(
          () => db
              .into(db.qurbanPayments)
              .insert(
                QurbanPaymentsCompanion.insert(
                  remoteId: const Value(dupRemoteId),
                  participantId: participantId,
                  amount: 250000,
                  paymentDate: DateTime(2026, 1, 2),
                ),
              ),
          throwsA(anything),
        );
      },
    );
  });
}
