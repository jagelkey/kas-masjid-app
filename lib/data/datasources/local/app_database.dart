import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain_status;

part 'app_database.g.dart';

class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    try {
      if (fromDb.isEmpty) return [];
      return List<String>.from(json.decode(fromDb));
    } catch (e) {
      // Handle legacy single string or invalid json
      if (fromDb.isNotEmpty) {
        // Remove trailing or leading brackets if malformed
        final cleaned = fromDb.replaceAll(RegExp(r'^\[|\]$'), '');
        if (cleaned.isNotEmpty && !cleaned.contains('","')) {
          return [cleaned];
        }
        // If it's a completely malformed json array, we still return something
        // but it's hard to recover gracefully. For safety, return as a single string
        // so it's not completely lost, or try to split by comma.
        return [fromDb];
      }
      return [];
    }
  }

  @override
  String toSql(List<String> value) {
    return json.encode(value);
  }
}

@DataClassName('TransactionEntity')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  IntColumn get type => intEnum<domain_status.TransactionType>()();
  RealColumn get amount => real()();
  TextColumn get category => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get date => dateTime()();
  TextColumn get proofPaths => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))(); // Local paths
  TextColumn get proofUrls => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))(); // Remote URLs
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceRef => text().nullable()();
  IntColumn get syncStatus => intEnum<domain_status.SyncStatus>().withDefault(
    const Constant(1),
  )(); // Default: PendingCreate
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('QurbanPackageEntity')
class QurbanPackages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get name => text()();
  RealColumn get monthlyAmount => real()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get syncStatus =>
      intEnum<domain_status.SyncStatus>().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('QurbanParticipantEntity')
class QurbanParticipants extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startMonth => dateTime()();
  RealColumn get monthlyAmount => real()();
  IntColumn get totalMonths => integer().withDefault(const Constant(10))();
  IntColumn get syncStatus =>
      intEnum<domain_status.SyncStatus>().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('QurbanPaymentEntity')
class QurbanPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  IntColumn get participantId => integer()();
  IntColumn get transactionId => integer().nullable()();
  RealColumn get amount => real()();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get note => text().nullable()();
  IntColumn get syncStatus =>
      intEnum<domain_status.SyncStatus>().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('ActivityEntity')
class Activities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get type => text()(); // Pengajian, Sholat Jumat, etc.
  DateTimeColumn get date => dateTime()();
  TextColumn get picName => text().nullable()();
  IntColumn get syncStatus =>
      intEnum<domain_status.SyncStatus>().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('MosqueProfileEntity')
class MosqueProfiles extends Table {
  IntColumn get id => integer().autoIncrement()(); // Should be only 1 row
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get remoteId => text().nullable()();
  IntColumn get syncStatus =>
      intEnum<domain_status.SyncStatus>().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('UserEntity')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()(); // Supabase Auth ID
  TextColumn get email => text()();
  TextColumn get username => text().nullable()();
  TextColumn get fullName => text().nullable()();
  TextColumn get role => text().withDefault(
    const Constant('viewer'),
  )(); // admin, bendahara, sekretaris, viewer
  IntColumn get syncStatus =>
      intEnum<domain_status.SyncStatus>().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('AuditLogEntity')
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get userId => text()();
  TextColumn get action => text()();
  TextColumn get targetTable => text().nullable()();
  TextColumn get recordId => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get syncStatus =>
      intEnum<domain_status.SyncStatus>().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: [
    Transactions,
    Activities,
    MosqueProfiles,
    Users,
    AuditLogs,
    QurbanPackages,
    QurbanParticipants,
    QurbanPayments,
  ],
)
@singleton
class AppDatabase extends _$AppDatabase {
  @factoryMethod
  factory AppDatabase.fromNoArgs() => AppDatabase();

  AppDatabase([QueryExecutor? e])
    : super(
        e ??
            driftDatabase(
              name: 'masjid_app',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Unique partial indexes on remote_id for all syncable tables.
        // Prevents duplicate local rows for the same remote record caused by
        // sync retry bugs or pull-merge errors.
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_remote_id_unique '
          'ON transactions(remote_id) WHERE remote_id IS NOT NULL',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_qurban_payments_remote_id_unique '
          'ON qurban_payments(remote_id) WHERE remote_id IS NOT NULL',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_qurban_packages_remote_id_unique '
          'ON qurban_packages(remote_id) WHERE remote_id IS NOT NULL',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_qurban_participants_remote_id_unique '
          'ON qurban_participants(remote_id) WHERE remote_id IS NOT NULL',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_activities_remote_id_unique '
          'ON activities(remote_id) WHERE remote_id IS NOT NULL',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_audit_logs_remote_id_unique '
          'ON audit_logs(remote_id) WHERE remote_id IS NOT NULL',
        );
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration steps...
        if (from < 2) {
          try {
            await m.addColumn(mosqueProfiles, mosqueProfiles.remoteId);
            await m.addColumn(mosqueProfiles, mosqueProfiles.syncStatus);
            await m.addColumn(mosqueProfiles, mosqueProfiles.updatedAt);
          } catch (e) {
            // Logged rather than silently swallowed -- this is expected to
            // fail with "duplicate column" on a device that already has
            // these columns, but a genuinely different failure here would
            // otherwise vanish with no trace and leave a column silently
            // never added.
            debugPrint('Migration step (from<2, mosqueProfiles columns): $e');
          }
        }
        if (from < 3) {
          await m.createTable(users);
        }
        if (from < 4) {
          try {
            await m.renameColumn(
              transactions,
              'proof_path',
              transactions.proofPaths,
            );
            await m.renameColumn(
              transactions,
              'proof_url',
              transactions.proofUrls,
            );
          } catch (e) {
            debugPrint('Migration step (from<4, rename proof columns): $e');
          }
        }
        if (from < 5) {
          try {
            await m.addColumn(users, users.username);
          } catch (e) {
            debugPrint('Migration step (from<5, users.username): $e');
          }
        }
        if (from < 6) {
          try {
            await m.addColumn(transactions, transactions.source);
          } catch (e) {
            debugPrint('Migration step (from<6, transactions.source): $e');
          }
          try {
            await m.addColumn(transactions, transactions.sourceRef);
          } catch (e) {
            debugPrint('Migration step (from<6, transactions.sourceRef): $e');
          }
          try {
            await m.createTable(qurbanPackages);
          } catch (e) {
            debugPrint('Migration step (from<6, qurbanPackages table): $e');
          }
          try {
            await m.createTable(qurbanParticipants);
          } catch (e) {
            debugPrint(
              'Migration step (from<6, qurbanParticipants table): $e',
            );
          }
          try {
            await m.createTable(qurbanPayments);
          } catch (e) {
            debugPrint('Migration step (from<6, qurbanPayments table): $e');
          }
          // auditLogs table introduced alongside qurban tables in v6.
          try {
            await m.createTable(auditLogs);
          } catch (e) {
            debugPrint('Migration step (from<6, auditLogs table): $e');
          }
        }

        if (from < 7) {
          // Partial unique indexes (NULL remote_id is exempt, since a row
          // not yet synced has none) guard against duplicate local rows
          // for the same remote transaction/payment silently double
          // counting money -- e.g. a push retried after a timeout where
          // the server actually already succeeded, or a pull-merge bug.
          // Wrapped in try/catch: if a device already has duplicate
          // remote_id values from before this fix, creating the index
          // fails on THAT device rather than blocking the app from
          // opening; such duplicates need manual cleanup, which this
          // migration intentionally does not attempt automatically.
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_remote_id_unique '
              'ON transactions(remote_id) WHERE remote_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('Skipping transactions.remote_id unique index: $e');
          }
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_qurban_payments_remote_id_unique '
              'ON qurban_payments(remote_id) WHERE remote_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint(
              'Skipping qurban_payments.remote_id unique index: $e',
            );
          }
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_qurban_packages_remote_id_unique '
              'ON qurban_packages(remote_id) WHERE remote_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint(
              'Skipping qurban_packages.remote_id unique index: $e',
            );
          }
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_qurban_participants_remote_id_unique '
              'ON qurban_participants(remote_id) WHERE remote_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint(
              'Skipping qurban_participants.remote_id unique index: $e',
            );
          }
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_activities_remote_id_unique '
              'ON activities(remote_id) WHERE remote_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('Skipping activities.remote_id unique index: $e');
          }
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_audit_logs_remote_id_unique '
              'ON audit_logs(remote_id) WHERE remote_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('Skipping audit_logs.remote_id unique index: $e');
          }
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');

        // Seed only when this local database is brand new, or when the v6
        // upgrade has just introduced the qurban tables. Seeding on every open
        // (guarded only by "are there zero packages?") meant an admin who
        // deliberately deleted every package got them silently recreated on the
        // next app start -- and then re-pushed to the server, undoing the
        // deletion for every other device too.
        final versionBefore = details.versionBefore;
        final qurbanTablesJustAdded =
            details.hadUpgrade && versionBefore != null && versionBefore < 6;
        if (details.wasCreated || qurbanTablesJustAdded) {
          await _seedDefaultQurbanPackages();
        }
      },
    );
  }

  Future<void> _seedDefaultQurbanPackages() async {
    final countExp = qurbanPackages.id.count();
    final row = await (selectOnly(
      qurbanPackages,
    )..addColumns([countExp])).getSingle();
    final count = row.read(countExp) ?? 0;
    if (count > 0) return;

    await batch((batch) {
      batch.insertAll(qurbanPackages, [
        QurbanPackagesCompanion.insert(
          remoteId: const Value('00000000-0000-4000-8000-000000250000'),
          name: 'Paket Qurban 250K',
          monthlyAmount: 250000,
          syncStatus: const Value(domain_status.SyncStatus.pendingCreate),
        ),
        QurbanPackagesCompanion.insert(
          remoteId: const Value('00000000-0000-4000-8000-000000275000'),
          name: 'Paket Qurban 275K',
          monthlyAmount: 275000,
          syncStatus: const Value(domain_status.SyncStatus.pendingCreate),
        ),
      ]);
    });
  }

  Future<void> clearAllData() {
    return transaction(() async {
      await delete(transactions).go();
      await delete(activities).go();
      await delete(mosqueProfiles).go();
      await delete(users).go();
      await delete(qurbanPayments).go();
      await delete(qurbanParticipants).go();
      await delete(qurbanPackages).go();
      await delete(auditLogs).go();
    });
  }
}
