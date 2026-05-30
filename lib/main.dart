import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:masjid_app/core/di/injection.dart';
import 'package:masjid_app/core/router/app_router.dart';
import 'package:masjid_app/presentation/blocs/transaction/transaction_bloc.dart';
import 'package:masjid_app/domain/repositories/transaction_repository.dart';

import 'package:masjid_app/presentation/blocs/activity/activity_bloc.dart';
import 'package:masjid_app/domain/repositories/activity_repository.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/blocs/profile/profile_bloc.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';
import 'package:masjid_app/domain/repositories/mosque_profile_repository.dart';
import 'package:masjid_app/core/constants/env.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _bootstrapApp();
  runApp(const MyApp());
}

Future<void> _bootstrapApp() async {
  if (Env.hasValidConfig) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Supabase init failed: $e');
    }
  }

  configureDependencies();
  
  try {
    await initializeDateFormatting('id_ID', null);
  } catch (e) {
    debugPrint('Date formatting init failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => getIt<AuthBloc>()..add(CheckAuthStatus()),
        ),
        BlocProvider<TransactionBloc>(
          create: (context) => TransactionBloc(getIt<TransactionRepository>())
            ..add(LoadTransactions()),
        ),
        BlocProvider<ActivityBloc>(
          create: (context) => ActivityBloc(getIt<ActivityRepository>())
            ..add(LoadActivities()),
        ),
        BlocProvider<ProfileBloc>(
          create: (context) => ProfileBloc(getIt<MosqueProfileRepository>())
            ..add(LoadProfile()),
        ),
        BlocProvider<SyncCubit>(
          create: (context) => getIt<SyncCubit>(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Manajemen Kas Masjid',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
          textTheme: GoogleFonts.interTextTheme(),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          // cardTheme: CardTheme(
          //   elevation: 2,
          //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          // ),
        ),
        routerConfig: appRouter,
        locale: const Locale('id'),
      ),
    );
  }
}
