import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/data/datasources/remote/sync_service.dart';

class SyncState extends Equatable {
  final bool isSyncing;
  final bool isSuccess;
  final List<String> errorMessages;

  const SyncState({
    this.isSyncing = false,
    this.isSuccess = true,
    this.errorMessages = const [],
  });

  @override
  List<Object?> get props => [isSyncing, isSuccess, errorMessages];

  factory SyncState.initial() => const SyncState();
  factory SyncState.loading() => const SyncState(isSyncing: true);
  factory SyncState.success() =>
      const SyncState(isSuccess: true, isSyncing: false);
  factory SyncState.failure(List<String> messages) =>
      SyncState(isSuccess: false, isSyncing: false, errorMessages: messages);
}

@injectable
class SyncCubit extends Cubit<SyncState> {
  final SyncService _syncService;
  StreamSubscription? _syncStatusSubscription;
  StreamSubscription? _syncResultSubscription;

  SyncCubit(this._syncService) : super(SyncState.initial()) {
    // Listen to loading status
    _syncStatusSubscription = _syncService.isSyncing.listen((isSyncing) {
      if (isSyncing) {
        emit(SyncState.loading());
      }
      // We rely on onSyncResult to set the final state (success/failure)
    });

    // Listen to results (success/failure)
    _syncResultSubscription = _syncService.onSyncResult.listen((result) {
      if (result.isSuccess) {
        emit(SyncState.success());
      } else {
        emit(SyncState.failure(result.errors));
      }
    });

    // Trigger initial sync on startup
    Future.microtask(() => forceSync());
  }

  @override
  Future<void> close() {
    _syncStatusSubscription?.cancel();
    _syncResultSubscription?.cancel();
    return super.close();
  }

  Future<void> forceSync() async {
    await _syncService.syncData();
  }

  void clearError() {
    emit(const SyncState(isSuccess: true, isSyncing: false, errorMessages: []));
  }
}
