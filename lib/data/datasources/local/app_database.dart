import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
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
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration steps...
        if (from < 2) {
          try {
            await m.addColumn(mosqueProfiles, mosqueProfiles.remoteId);
            await m.addColumn(mosqueProfiles, mosqueProfiles.syncStatus);
            await m.addColumn(mosqueProfiles, mosqueProfiles.updatedAt);
          } catch (_) {}
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
          } catch (_) {}
        }
        if (from < 5) {
          try {
            await m.addColumn(users, users.username);
          } catch (_) {}
        }
        if (from < 6) {
          try {
            await m.addColumn(transactions, transactions.source);
          } catch (_) {}
          try {
            await m.addColumn(transactions, transactions.sourceRef);
          } catch (_) {}
          try {
            await m.createTable(qurbanPackages);
          } catch (_) {}
          try {
            await m.createTable(qurbanParticipants);
          } catch (_) {}
          try {
            await m.createTable(qurbanPayments);
          } catch (_) {}
        }

        // Ensure new tables are created during upgrade
        // Check if auditLogs table exists, if not create it
        // Since we can't easily check existence in Drift without custom query,
        // we can wrap createTable in try-catch or rely on Drift's createTable (which fails if exists)
        try {
          await m.createTable(auditLogs);
        } catch (_) {
          // Table likely already exists
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        await _seedDefaultQurbanPackages();
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
    });
  }
}
