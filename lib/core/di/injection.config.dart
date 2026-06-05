// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:supabase_flutter/supabase_flutter.dart' as _i454;

import '../../data/datasources/local/app_database.dart' as _i483;
import '../../data/datasources/local/auth_local_datasource.dart' as _i17;
import '../../data/datasources/remote/sync_service.dart' as _i745;
import '../../data/repositories/activity_repository_impl.dart' as _i453;
import '../../data/repositories/audit_log_repository_impl.dart' as _i255;
import '../../data/repositories/mosque_profile_repository_impl.dart' as _i969;
import '../../data/repositories/qurban_repository_impl.dart' as _i481;
import '../../data/repositories/transaction_repository_impl.dart' as _i611;
import '../../data/repositories/user_repository_impl.dart' as _i790;
import '../../domain/repositories/activity_repository.dart' as _i982;
import '../../domain/repositories/audit_log_repository.dart' as _i862;
import '../../domain/repositories/mosque_profile_repository.dart' as _i265;
import '../../domain/repositories/qurban_repository.dart' as _i85;
import '../../domain/repositories/transaction_repository.dart' as _i302;
import '../../domain/repositories/user_repository.dart' as _i271;
import '../../presentation/blocs/activity/activity_bloc.dart' as _i753;
import '../../presentation/blocs/auth/auth_bloc.dart' as _i141;
import '../../presentation/blocs/profile/profile_bloc.dart' as _i344;
import '../../presentation/blocs/qurban/qurban_bloc.dart' as _i315;
import '../../presentation/blocs/sync/sync_cubit.dart' as _i645;
import '../../presentation/blocs/transaction/transaction_bloc.dart' as _i937;
import '../services/pdf_service.dart' as _i182;
import 'register_module.dart' as _i291;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final registerModule = _$RegisterModule();
    gh.singleton<_i483.AppDatabase>(() => _i483.AppDatabase.fromNoArgs());
    gh.lazySingleton<_i454.SupabaseClient>(() => registerModule.supabaseClient);
    gh.lazySingleton<_i182.PdfService>(() => _i182.PdfService());
    gh.lazySingleton<_i17.AuthLocalDatasource>(
      () => _i17.AuthLocalDatasource(),
    );
    gh.lazySingleton<_i862.AuditLogRepository>(
      () => _i255.AuditLogRepositoryImpl(
        gh<_i483.AppDatabase>(),
        gh<_i17.AuthLocalDatasource>(),
      ),
    );
    gh.lazySingleton<_i265.MosqueProfileRepository>(
      () => _i969.MosqueProfileRepositoryImpl(
        gh<_i483.AppDatabase>(),
        gh<_i862.AuditLogRepository>(),
      ),
    );
    gh.lazySingleton<_i271.UserRepository>(
      () => _i790.UserRepositoryImpl(
        gh<_i483.AppDatabase>(),
        gh<_i862.AuditLogRepository>(),
      ),
    );
    gh.factory<_i344.ProfileBloc>(
      () => _i344.ProfileBloc(gh<_i265.MosqueProfileRepository>()),
    );
    gh.lazySingleton<_i745.SyncService>(
      () => _i745.SyncService(gh<_i483.AppDatabase>()),
    );
    gh.lazySingleton<_i982.ActivityRepository>(
      () => _i453.ActivityRepositoryImpl(
        gh<_i483.AppDatabase>(),
        gh<_i862.AuditLogRepository>(),
      ),
    );
    gh.lazySingleton<_i302.TransactionRepository>(
      () => _i611.TransactionRepositoryImpl(
        gh<_i483.AppDatabase>(),
        gh<_i862.AuditLogRepository>(),
      ),
    );
    gh.lazySingleton<_i85.QurbanRepository>(
      () => _i481.QurbanRepositoryImpl(
        gh<_i483.AppDatabase>(),
        gh<_i862.AuditLogRepository>(),
      ),
    );
    gh.factory<_i645.SyncCubit>(() => _i645.SyncCubit(gh<_i745.SyncService>()));
    gh.factory<_i753.ActivityBloc>(
      () => _i753.ActivityBloc(gh<_i982.ActivityRepository>()),
    );
    gh.factory<_i141.AuthBloc>(
      () => _i141.AuthBloc(
        gh<_i17.AuthLocalDatasource>(),
        gh<_i483.AppDatabase>(),
        gh<_i271.UserRepository>(),
      ),
    );
    gh.factory<_i937.TransactionBloc>(
      () => _i937.TransactionBloc(gh<_i302.TransactionRepository>()),
    );
    gh.factory<_i315.QurbanBloc>(
      () => _i315.QurbanBloc(gh<_i85.QurbanRepository>()),
    );
    return this;
  }
}

class _$RegisterModule extends _i291.RegisterModule {}
