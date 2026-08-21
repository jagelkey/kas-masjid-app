import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/repositories/qurban_repository.dart';

abstract class QurbanEvent extends Equatable {
  const QurbanEvent();

  @override
  List<Object?> get props => [];
}

class LoadQurban extends QurbanEvent {}

class QurbanProgressUpdated extends QurbanEvent {
  final List<QurbanParticipantProgress> progress;

  const QurbanProgressUpdated(this.progress);

  @override
  List<Object?> get props => [progress];
}

class ApplyQurbanFilter extends QurbanEvent {
  final String query;
  final QurbanProgressStatus? status;

  const ApplyQurbanFilter({this.query = '', this.status});

  @override
  List<Object?> get props => [query, status];
}

class AddQurbanPackage extends QurbanEvent {
  final QurbanPackage package;

  const AddQurbanPackage(this.package);

  @override
  List<Object?> get props => [package];
}

class UpdateQurbanPackage extends QurbanEvent {
  final QurbanPackage package;

  const UpdateQurbanPackage(this.package);

  @override
  List<Object?> get props => [package];
}

class DeleteQurbanPackage extends QurbanEvent {
  final int id;

  const DeleteQurbanPackage(this.id);

  @override
  List<Object?> get props => [id];
}

class AddQurbanParticipant extends QurbanEvent {
  final QurbanParticipant participant;

  const AddQurbanParticipant(this.participant);

  @override
  List<Object?> get props => [participant];
}

class UpdateQurbanParticipant extends QurbanEvent {
  final QurbanParticipant participant;

  const UpdateQurbanParticipant(this.participant);

  @override
  List<Object?> get props => [participant];
}

class DeleteQurbanParticipant extends QurbanEvent {
  final int id;

  const DeleteQurbanParticipant(this.id);

  @override
  List<Object?> get props => [id];
}

class AddQurbanPayment extends QurbanEvent {
  final QurbanPayment payment;

  const AddQurbanPayment(this.payment);

  @override
  List<Object?> get props => [payment];
}

class UpdateQurbanPayment extends QurbanEvent {
  final QurbanPayment payment;

  const UpdateQurbanPayment(this.payment);

  @override
  List<Object?> get props => [payment];
}

class DeleteQurbanPayment extends QurbanEvent {
  final int id;

  const DeleteQurbanPayment(this.id);

  @override
  List<Object?> get props => [id];
}

abstract class QurbanState extends Equatable {
  const QurbanState();

  @override
  List<Object?> get props => [];
}

class QurbanInitial extends QurbanState {}

class QurbanLoading extends QurbanState {}

class QurbanLoaded extends QurbanState {
  final List<QurbanPackage> packages;
  final List<QurbanParticipantProgress> progress;
  final List<QurbanParticipantProgress> filteredProgress;
  final QurbanSummary summary;
  final String query;
  final QurbanProgressStatus? statusFilter;

  const QurbanLoaded({
    this.packages = const [],
    this.progress = const [],
    this.filteredProgress = const [],
    this.summary = const QurbanSummary(
      totalTarget: 0,
      totalCollected: 0,
      totalRemaining: 0,
      participantCount: 0,
      paidOffCount: 0,
      overdueCount: 0,
      overpaidCount: 0,
    ),
    this.query = '',
    this.statusFilter,
  });

  QurbanLoaded copyWith({
    List<QurbanPackage>? packages,
    List<QurbanParticipantProgress>? progress,
    List<QurbanParticipantProgress>? filteredProgress,
    QurbanSummary? summary,
    String? query,
    QurbanProgressStatus? statusFilter,
    bool clearStatusFilter = false,
  }) {
    return QurbanLoaded(
      packages: packages ?? this.packages,
      progress: progress ?? this.progress,
      filteredProgress: filteredProgress ?? this.filteredProgress,
      summary: summary ?? this.summary,
      query: query ?? this.query,
      statusFilter: clearStatusFilter
          ? null
          : statusFilter ?? this.statusFilter,
    );
  }

  @override
  List<Object?> get props => [
    packages,
    progress,
    filteredProgress,
    summary,
    query,
    statusFilter,
  ];
}

class QurbanOperationSuccess extends QurbanLoaded {
  final String operationMessage;
  final bool shouldPop;

  QurbanOperationSuccess(
    QurbanLoaded state,
    this.operationMessage, {
    this.shouldPop = false,
  }) : super(
         packages: state.packages,
         progress: state.progress,
         filteredProgress: state.filteredProgress,
         summary: state.summary,
         query: state.query,
         statusFilter: state.statusFilter,
       );

  @override
  List<Object?> get props => [...super.props, operationMessage, shouldPop];
}

class QurbanOperationFailure extends QurbanLoaded {
  final String operationMessage;

  QurbanOperationFailure(QurbanLoaded state, this.operationMessage)
    : super(
        packages: state.packages,
        progress: state.progress,
        filteredProgress: state.filteredProgress,
        summary: state.summary,
        query: state.query,
        statusFilter: state.statusFilter,
      );

  @override
  List<Object?> get props => [...super.props, operationMessage];
}

class QurbanError extends QurbanState {
  final String message;

  const QurbanError(this.message);

  @override
  List<Object?> get props => [message];
}

@injectable
class QurbanBloc extends Bloc<QurbanEvent, QurbanState> {
  final QurbanRepository _repository;

  QurbanBloc(this._repository) : super(QurbanInitial()) {
    on<LoadQurban>(_onLoadQurban, transformer: restartable());
    on<QurbanProgressUpdated>(_onProgressUpdated);
    on<ApplyQurbanFilter>(_onApplyFilter);
    on<AddQurbanPackage>(_onAddPackage);
    on<UpdateQurbanPackage>(_onUpdatePackage);
    on<DeleteQurbanPackage>(_onDeletePackage);
    on<AddQurbanParticipant>(_onAddParticipant);
    on<UpdateQurbanParticipant>(_onUpdateParticipant);
    on<DeleteQurbanParticipant>(_onDeleteParticipant);
    on<AddQurbanPayment>(_onAddPayment);
    on<UpdateQurbanPayment>(_onUpdatePayment);
    on<DeleteQurbanPayment>(_onDeletePayment);
  }

  Future<void> _onLoadQurban(
    LoadQurban event,
    Emitter<QurbanState> emit,
  ) async {
    emit(QurbanLoading());
    await emit.forEach<List<QurbanParticipantProgress>>(
      _repository.watchParticipantProgress(),
      onData: (progress) {
        add(QurbanProgressUpdated(progress));
        return state;
      },
      onError: (e, s) => QurbanError('Gagal memuat qurban: $e'),
    );
  }

  Future<void> _onProgressUpdated(
    QurbanProgressUpdated event,
    Emitter<QurbanState> emit,
  ) async {
    try {
      final packages = await _repository.getPackages();
      final current = state is QurbanLoaded ? state as QurbanLoaded : null;
      emit(
        _buildLoadedState(
          packages: packages,
          progress: event.progress,
          query: current?.query ?? '',
          statusFilter: current?.statusFilter,
        ),
      );
    } catch (e) {
      emit(QurbanError('Gagal memperbarui qurban: $e'));
    }
  }

  void _onApplyFilter(ApplyQurbanFilter event, Emitter<QurbanState> emit) {
    if (state is! QurbanLoaded) return;
    final current = state as QurbanLoaded;
    emit(
      _buildLoadedState(
        packages: current.packages,
        progress: current.progress,
        query: event.query,
        statusFilter: event.status,
      ),
    );
  }

  Future<void> _onAddPackage(
    AddQurbanPackage event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.addPackage(event.package),
      'Paket qurban berhasil ditambahkan',
      'Gagal menambah paket qurban',
      refreshPackages: true,
    );
  }

  Future<void> _onUpdatePackage(
    UpdateQurbanPackage event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.updatePackage(event.package),
      'Paket qurban berhasil diperbarui',
      'Gagal memperbarui paket qurban',
      refreshPackages: true,
    );
  }

  Future<void> _onDeletePackage(
    DeleteQurbanPackage event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.deletePackage(event.id),
      'Paket qurban berhasil dihapus',
      'Gagal menghapus paket qurban',
      refreshPackages: true,
    );
  }

  Future<void> _onAddParticipant(
    AddQurbanParticipant event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.addParticipant(event.participant),
      'Peserta qurban berhasil ditambahkan',
      'Gagal menambah peserta qurban',
    );
  }

  Future<void> _onUpdateParticipant(
    UpdateQurbanParticipant event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.updateParticipant(event.participant),
      'Peserta qurban berhasil diperbarui',
      'Gagal memperbarui peserta qurban',
    );
  }

  Future<void> _onDeleteParticipant(
    DeleteQurbanParticipant event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.deleteParticipant(event.id),
      'Peserta qurban berhasil dihapus',
      'Gagal menghapus peserta qurban',
      shouldPop: true,
    );
  }

  Future<void> _onAddPayment(
    AddQurbanPayment event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.addPayment(event.payment),
      'Pembayaran qurban berhasil dicatat',
      'Gagal mencatat pembayaran qurban',
    );
  }

  Future<void> _onUpdatePayment(
    UpdateQurbanPayment event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.updatePayment(event.payment),
      'Pembayaran qurban berhasil diperbarui',
      'Gagal memperbarui pembayaran qurban',
    );
  }

  Future<void> _onDeletePayment(
    DeleteQurbanPayment event,
    Emitter<QurbanState> emit,
  ) async {
    await _runOperation(
      emit,
      () => _repository.deletePayment(event.id),
      'Pembayaran qurban berhasil dihapus',
      'Gagal menghapus pembayaran qurban',
    );
  }

  Future<void> _runOperation(
    Emitter<QurbanState> emit,
    Future<void> Function() operation,
    String successMessage,
    String failurePrefix, {
    bool refreshPackages = false,
    bool shouldPop = false,
  }) async {
    try {
      await operation();
      if (state is QurbanLoaded) {
        final current = state as QurbanLoaded;
        final packages = refreshPackages
            ? await _repository.getPackages()
            : current.packages;
        emit(
          QurbanOperationSuccess(
            current.copyWith(packages: packages),
            successMessage,
            shouldPop: shouldPop,
          ),
        );
      }
    } catch (e) {
      if (state is QurbanLoaded) {
        emit(
          QurbanOperationFailure(state as QurbanLoaded, '$failurePrefix: $e'),
        );
      } else {
        emit(QurbanError('$failurePrefix: $e'));
      }
    }
  }

  QurbanLoaded _buildLoadedState({
    required List<QurbanPackage> packages,
    required List<QurbanParticipantProgress> progress,
    required String query,
    required QurbanProgressStatus? statusFilter,
  }) {
    final filtered = _applyFilter(progress, query, statusFilter);
    return QurbanLoaded(
      packages: packages,
      progress: progress,
      filteredProgress: filtered,
      summary: QurbanSummary.fromProgress(progress),
      query: query,
      statusFilter: statusFilter,
    );
  }

  List<QurbanParticipantProgress> _applyFilter(
    List<QurbanParticipantProgress> progress,
    String query,
    QurbanProgressStatus? status,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    return progress.where((item) {
      final participant = item.participant;
      final matchesQuery =
          normalizedQuery.isEmpty ||
          participant.name.toLowerCase().contains(normalizedQuery) ||
          (participant.phone ?? '').toLowerCase().contains(normalizedQuery);
      final matchesStatus = status == null || item.status == status;
      return matchesQuery && matchesStatus;
    }).toList();
  }
}
