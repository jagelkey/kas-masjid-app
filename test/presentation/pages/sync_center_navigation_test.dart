import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/remote/sync_service.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';
import 'package:masjid_app/presentation/pages/sync_center_page.dart';
import 'package:masjid_app/presentation/widgets/app_components.dart';

/// Guards the Sync Center "Antrean Lokal" tiles. Every tile must be a live
/// shortcut to the section it summarizes -- Profil Masjid, Pengguna, and
/// Audit Log previously had no onTap and did nothing when tapped.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    if (GetIt.I.isRegistered<AppDatabase>()) {
      GetIt.I.unregister<AppDatabase>();
    }
    // SyncCenterPage reads pending counts via GetIt.I<AppDatabase>().
    GetIt.I.registerSingleton<AppDatabase>(db);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  // Placeholder destinations: the real pages pull in their own BLoCs/DI, but
  // all this test cares about is that the tile routes to the correct path.
  GoRouter buildRouter() {
    Widget dest(String path) => Scaffold(body: Center(child: Text('DEST:$path')));
    GoRoute leaf(String path) =>
        GoRoute(path: path, builder: (context, state) => dest(path));

    return GoRouter(
      initialLocation: '/settings/sync',
      routes: [
        GoRoute(
          path: '/settings/sync',
          builder: (context, state) => const SyncCenterPage(),
        ),
        leaf('/transactions'),
        leaf('/activities'),
        leaf('/qurban'),
        leaf('/settings'),
        leaf('/settings/users'),
        leaf('/settings/audit-logs'),
      ],
    );
  }

  Widget harness() => BlocProvider<SyncCubit>(
    create: (_) => SyncCubit(SyncService(db)),
    child: MaterialApp.router(routerConfig: buildRouter()),
  );

  // Tile title -> the route it must open. Order mirrors the page.
  const expectedRoutes = <String, String>{
    'Transaksi Kas': '/transactions',
    'Kegiatan': '/activities',
    'Qurban': '/qurban',
    'Profil Masjid': '/settings',
    'Pengguna': '/settings/users',
    'Audit Log': '/settings/audit-logs',
  };

  expectedRoutes.forEach((title, path) {
    testWidgets('Antrean Lokal tile "$title" opens $path', (tester) async {
      // Tall surface so the ListView materializes every tile (its children are
      // lazily built per viewport); otherwise the bottom tiles never mount.
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // widgetWithText(AppActionTile, ...) disambiguates the tile from the
      // "Qurban"/"Kas" mini-metric labels at the top of the page.
      final tile = find.widgetWithText(AppActionTile, title);
      expect(tile, findsOneWidget, reason: 'tile "$title" should render');

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(
        find.text('DEST:$path'),
        findsOneWidget,
        reason: 'tapping "$title" should navigate to $path',
      );
    });
  });
}
