import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/core/constants/env.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/remote/sync_service.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const supabaseUrl = String.fromEnvironment('TEST_SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('TEST_SUPABASE_ANON_KEY');
  const testEmail = String.fromEnvironment('TEST_SUPABASE_EMAIL');
  const testPassword = String.fromEnvironment('TEST_SUPABASE_PASSWORD');

  // SyncService.syncData() refuses to run unless Env.hasValidConfig is true,
  // and Env reads the *non-test* SUPABASE_URL / SUPABASE_ANON_KEY compile-time
  // defines. So the TEST_ vars alone are not enough -- without the app-level
  // pair, every sync in here returns "Sync disabled (Supabase not configured)"
  // and the test fails with a misleading error deep in the body. Require both
  // sets up front and say so, instead of failing cryptically at line ~100.
  final hasRemoteConfig =
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      testEmail.isNotEmpty &&
      testPassword.isNotEmpty &&
      Env.hasValidConfig;

  late AppDatabase db;
  late SyncService syncService;
  SupabaseClient? supabase;

  final testCategory =
      'INTEGRATION_TEST_${DateTime.now().millisecondsSinceEpoch}';

  setUpAll(() async {
    if (!hasRemoteConfig) {
      debugPrint(
        'Skipping remote sync integration setup. Provide ALL of: '
        'TEST_SUPABASE_URL, TEST_SUPABASE_ANON_KEY, TEST_SUPABASE_EMAIL, '
        'TEST_SUPABASE_PASSWORD, AND the app-level SUPABASE_URL + '
        'SUPABASE_ANON_KEY (SyncService gates on Env.hasValidConfig) via '
        '--dart-define to enable it.',
      );
      return;
    }

    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    supabase = Supabase.instance.client;
    await supabase!.auth.signInWithPassword(
      email: testEmail,
      password: testPassword,
    );
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    syncService = SyncService(db);
  });

  tearDown(() async {
    await db.close();
  });

  tearDownAll(() async {
    final client = supabase;
    if (client == null) return;
    try {
      await client.from('transactions').delete().eq('category', testCategory);
      await client.auth.signOut();
    } catch (e) {
      debugPrint('Remote integration cleanup failed: $e');
    }
  });

  test('Full Sync Cycle: Local Insert -> Push -> Remote Verify', () async {
    if (!hasRemoteConfig || supabase == null) {
      return;
    }

    final localId = await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion(
            type: const Value(domain.TransactionType.income),
            amount: const Value(10000.0),
            category: Value(testCategory),
            description: const Value('Test Sync'),
            date: Value(DateTime.now()),
            syncStatus: const Value(domain.SyncStatus.pendingCreate),
          ),
        );

    final localTx = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(localId))).getSingle();
    expect(localTx.syncStatus, domain.SyncStatus.pendingCreate);
    expect(localTx.remoteId, isNull);

    final result = await syncService.syncData();
    if (!result.isSuccess) {
      debugPrint('Sync Errors: ${result.errors}');
    }

    expect(result.isSuccess, isTrue);

    final syncedTx = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(localId))).getSingle();
    expect(syncedTx.syncStatus, domain.SyncStatus.synced);
    expect(syncedTx.remoteId, isNotNull);

    final remoteTx = await supabase!
        .from('transactions')
        .select()
        .eq('id', syncedTx.remoteId!)
        .maybeSingle();

    expect(remoteTx, isNotNull);
    expect(remoteTx!['category'], testCategory);
    expect((remoteTx['amount'] as num).toDouble(), 10000.0);
  });
}
