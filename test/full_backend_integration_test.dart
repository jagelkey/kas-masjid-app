// Comprehensive LIVE backend-integration audit: drives every offline-first
// entity through the REAL repositories + SyncService against the real Supabase
// project, proving each one round-trips (local create -> push -> server ->
// pull back on a fresh "device"). Self-skips unless all the required
// --dart-define values are supplied (see README). It creates uniquely-marked
// rows and deletes them again in tearDownAll; it never mutates real data (the
// singleton mosque profile is exercised with a no-op-value update only).
//
// Run:
//   flutter test test/full_backend_integration_test.dart \
//     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
//     --dart-define=TEST_SUPABASE_URL=... --dart-define=TEST_SUPABASE_ANON_KEY=... \
//     --dart-define=TEST_SUPABASE_EMAIL=... --dart-define=TEST_SUPABASE_PASSWORD=...
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/core/constants/env.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/local/auth_local_datasource.dart';
import 'package:masjid_app/data/datasources/remote/sync_service.dart';
import 'package:masjid_app/data/repositories/activity_repository_impl.dart';
import 'package:masjid_app/data/repositories/audit_log_repository_impl.dart';
import 'package:masjid_app/data/repositories/mosque_profile_repository_impl.dart';
import 'package:masjid_app/data/repositories/qurban_repository_impl.dart';
import 'package:masjid_app/data/repositories/transaction_repository_impl.dart';
import 'package:masjid_app/domain/entities/activity.dart' as act;
import 'package:masjid_app/domain/entities/mosque_profile.dart' as mp;
import 'package:masjid_app/domain/entities/qurban.dart' as q;
import 'package:masjid_app/domain/entities/transaction.dart' as domain;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const supabaseUrl = String.fromEnvironment('TEST_SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('TEST_SUPABASE_ANON_KEY');
  const testEmail = String.fromEnvironment('TEST_SUPABASE_EMAIL');
  const testPassword = String.fromEnvironment('TEST_SUPABASE_PASSWORD');

  final hasRemoteConfig = supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      testEmail.isNotEmpty &&
      testPassword.isNotEmpty &&
      Env.hasValidConfig;

  final marker = 'BACKEND_AUDIT_${DateTime.now().millisecondsSinceEpoch}';
  SupabaseClient? supabase;

  // NOTE: we deliberately do NOT call TestWidgetsFlutterBinding.ensureInitialized()
  // -- it routes every HttpClient request to a fake 400 response, which would
  // block the real Supabase calls this suite exists to make. The real
  // AuthLocalDatasource is safe to construct and use here without a mocked
  // secure store because, while signed in, AuditLogRepositoryImpl resolves the
  // actor from the online Supabase session and never reads secure storage.

  ({
    AppDatabase db,
    SyncService sync,
    TransactionRepositoryImpl tx,
    ActivityRepositoryImpl act,
    QurbanRepositoryImpl qurban,
    MosqueProfileRepositoryImpl profile,
  }) buildDevice() {
    final db = AppDatabase(NativeDatabase.memory());
    final audit = AuditLogRepositoryImpl(db, AuthLocalDatasource());
    return (
      db: db,
      sync: SyncService(db),
      tx: TransactionRepositoryImpl(db, audit),
      act: ActivityRepositoryImpl(db, audit),
      qurban: QurbanRepositoryImpl(db, audit),
      profile: MosqueProfileRepositoryImpl(db, audit),
    );
  }

  setUpAll(() async {
    if (!hasRemoteConfig) {
      debugPrint('Skipping full backend integration audit (see README for the '
          'six required --dart-define values, TEST_* plus app-level '
          'SUPABASE_URL/ANON_KEY).');
      return;
    }
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    supabase = Supabase.instance.client;
    await supabase!.auth
        .signInWithPassword(email: testEmail, password: testPassword);
  });

  tearDownAll(() async {
    final c = supabase;
    if (c == null) return;
    try {
      // participants cascade-delete their payments; the qurban-linked cash
      // transaction has ON DELETE SET NULL so it survives -- delete it by its
      // description, which contains the marker (the participant name). Regular
      // test transactions carry the marker as their category.
      await c.from('qurban_participants').delete().eq('name', marker);
      await c.from('transactions').delete().eq('category', marker);
      await c.from('transactions').delete().like('description', '%$marker%');
      await c.from('qurban_packages').delete().eq('name', marker);
      await c.from('activities').delete().eq('title', marker);
      // NOTE: audit_logs is intentionally append-only -- it has no DELETE
      // policy, so the marker'd log rows this run created CANNOT be removed via
      // the client (that immutability is correct for an audit trail). Running
      // this suite therefore leaves a few audit rows behind; purge them with
      // elevated DB access if needed:
      //   delete from audit_logs where description like '%BACKEND_AUDIT_%';
      await c.auth.signOut();
    } catch (e) {
      debugPrint('cleanup failed: $e');
    }
  });

  test('PUSH: every entity created via the real repositories reaches Supabase',
      () async {
    if (!hasRemoteConfig) return;
    final d = buildDevice();
    addTearDown(() => d.db.close());

    // --- create one of each through the ACTUAL app code paths ---
    await d.tx.addTransaction(domain.Transaction(
      type: domain.TransactionType.income,
      amount: 111000,
      category: marker,
      description: 'audit income',
      date: DateTime.now(),
    ));
    await d.tx.addTransaction(domain.Transaction(
      type: domain.TransactionType.expense,
      amount: 22000,
      category: marker,
      description: 'audit expense',
      date: DateTime.now(),
    ));
    await d.act.addActivity(act.Activity(
      title: marker,
      type: 'Pengajian',
      date: DateTime.now(),
      picName: 'Auditor',
    ));
    await d.qurban.addPackage(q.QurbanPackage(name: marker, monthlyAmount: 300000));
    await d.qurban.addParticipant(q.QurbanParticipant(
      name: marker,
      startMonth: DateTime.now(),
      monthlyAmount: 250000,
    ));
    final participant =
        (await d.qurban.getParticipantProgress()).single.participant;
    await d.qurban.addPayment(q.QurbanPayment(
      participantId: participant.id!,
      amount: 250000,
      paymentDate: DateTime.now(),
    ));

    final result = await d.sync.syncData();
    if (!result.isSuccess) debugPrint('sync errors: ${result.errors}');
    expect(result.isSuccess, isTrue,
        reason: 'a clean push of every entity must report no errors');

    // --- verify each entity actually landed on the server ---
    final txRows =
        await supabase!.from('transactions').select().eq('category', marker);
    expect(txRows.length, 2, reason: 'both cash transactions must be on server');

    final actRow = await supabase!
        .from('activities')
        .select()
        .eq('title', marker)
        .maybeSingle();
    expect(actRow, isNotNull);
    expect(actRow!['pic_name'], 'Auditor');

    final pkgRow = await supabase!
        .from('qurban_packages')
        .select()
        .eq('name', marker)
        .maybeSingle();
    expect(pkgRow, isNotNull);
    expect((pkgRow!['monthly_amount'] as num).toDouble(), 300000);

    final partRow = await supabase!
        .from('qurban_participants')
        .select()
        .eq('name', marker)
        .maybeSingle();
    expect(partRow, isNotNull);
    final partRemoteId = partRow!['id'] as String;

    final payRows = await supabase!
        .from('qurban_payments')
        .select()
        .eq('participant_id', partRemoteId);
    expect(payRows.length, 1, reason: 'the qurban payment must be on server');
    // the payment must be linked to a real cash transaction on the server
    expect(payRows.first['transaction_id'], isNotNull);
    final linkedTx = await supabase!
        .from('transactions')
        .select()
        .eq('id', payRows.first['transaction_id'])
        .maybeSingle();
    expect(linkedTx, isNotNull);
    expect(linkedTx!['source'], 'qurban');
    expect((linkedTx['amount'] as num).toDouble(), 250000);

    // audit_logs: the repo actions wrote logs; they must sync AND carry the
    // server-stamped created_by (the unforgeable actor column added 2026-07-11).
    final logs = await supabase!
        .from('audit_logs')
        .select()
        .like('description', '%$marker%');
    expect(logs.isNotEmpty, isTrue, reason: 'audit logs must reach the server');
    expect(logs.every((l) => l['created_by'] != null), isTrue,
        reason: 'every synced log must have a server-stamped created_by');
  });

  test('PULL: a fresh device pulls every entity back down', () async {
    if (!hasRemoteConfig) return;
    final d = buildDevice();
    addTearDown(() => d.db.close());

    final result = await d.sync.syncData();
    if (!result.isSuccess) debugPrint('pull errors: ${result.errors}');
    expect(result.isSuccess, isTrue);

    final txs = await (d.db.select(d.db.transactions)
          ..where((t) => t.category.equals(marker)))
        .get();
    expect(txs.length, 2, reason: 'both cash transactions must pull down');

    final acts = await (d.db.select(d.db.activities)
          ..where((t) => t.title.equals(marker)))
        .get();
    expect(acts.length, 1);

    final pkgs = await (d.db.select(d.db.qurbanPackages)
          ..where((t) => t.name.equals(marker)))
        .get();
    expect(pkgs.length, 1);

    final parts = await (d.db.select(d.db.qurbanParticipants)
          ..where((t) => t.name.equals(marker)))
        .get();
    expect(parts.length, 1);

    final pays = await (d.db.select(d.db.qurbanPayments)
          ..where((t) => t.participantId.equals(parts.single.id)))
        .get();
    expect(pays.length, 1, reason: 'the payment must pull down');
    expect(pays.single.transactionId, isNotNull,
        reason: 'and it must be re-linked to its local cash transaction');

    // mosque profile: the REAL singleton must pull down (read integration).
    final profile = await d.profile.getProfile();
    expect(profile, isNotNull,
        reason: 'the real mosque profile must sync down to a new device');
    expect((profile!.name).trim().isNotEmpty, isTrue);
  });

  test('STORAGE + mosque push: proof image uploads; profile push is a safe no-op',
      () async {
    if (!hasRemoteConfig) return;
    final d = buildDevice();
    addTearDown(() => d.db.close());

    // 1. proof image -> proofs bucket, and proof_url set on the transaction row
    final tmp = await File(
            '${Directory.systemTemp.path}/audit_proof_$marker.png')
        .create();
    // minimal 1x1 PNG
    await tmp.writeAsBytes(const [
      0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,
      0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,
      0x15,0xC4,0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,
      0x01,0x00,0x00,0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,
      0x45,0x4E,0x44,0xAE,0x42,0x60,0x82,
    ]);
    addTearDown(() async { if (await tmp.exists()) await tmp.delete(); });

    await d.tx.addTransaction(domain.Transaction(
      type: domain.TransactionType.income,
      amount: 5000,
      category: marker,
      description: 'audit proof',
      date: DateTime.now(),
      proofPaths: [tmp.path],
    ));
    final r1 = await d.sync.syncData();
    expect(r1.isSuccess, isTrue, reason: 'proof upload sync must succeed');

    final proofTx = await supabase!
        .from('transactions')
        .select()
        .eq('category', marker)
        .eq('description', 'audit proof')
        .maybeSingle();
    expect(proofTx, isNotNull);
    final proofUrls = proofTx!['proof_url'];
    expect(proofUrls, isNotNull,
        reason: 'proof_url must be populated after upload');
    final url = (proofUrls is List) ? proofUrls.first as String : proofUrls as String;
    expect(url.contains('/storage/v1/object/public/proofs/'), isTrue);
    // the uploaded object must actually exist in the bucket: download it back.
    final objectPath = url.split('/proofs/').last;
    final bytes = await supabase!.storage
        .from('proofs')
        .download(objectPath)
        .then<List<int>?>((b) => b)
        .catchError((_) => null);
    expect(bytes, isNotNull,
        reason: 'the uploaded proof object must be downloadable from the bucket');
    expect(bytes!.isNotEmpty, isTrue);

    // 2. mosque profile PUSH path, exercised without changing real data:
    //    pull the real profile, save it back with identical values, sync.
    final original = await d.profile.getProfile();
    expect(original, isNotNull);
    final before = await supabase!
        .from('mosque_profiles')
        .select('name,address,updated_at')
        .order('created_at', ascending: true)
        .limit(1)
        .single();
    await d.profile.saveProfile(mp.MosqueProfile(
      id: original!.id,
      name: original.name, // identical -> no data change
      address: original.address,
      logoPath: original.logoPath,
      logoUrl: original.logoUrl,
    ));
    final r2 = await d.sync.syncData();
    expect(r2.isSuccess, isTrue, reason: 'mosque profile push must succeed');
    final after = await supabase!
        .from('mosque_profiles')
        .select('name,address,updated_at')
        .order('created_at', ascending: true)
        .limit(1)
        .single();
    expect(after['name'], before['name'],
        reason: 'the no-op update must not change the real mosque name');
    expect(after['address'], before['address']);
  });
}
