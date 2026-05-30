import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/domain/entities/activity.dart';
import 'package:masjid_app/domain/repositories/activity_repository.dart';

// Events
abstract class ActivityEvent extends Equatable {
  const ActivityEvent();
  @override
  List<Object?> get props => [];
}

class LoadActivities extends ActivityEvent {}

class AddActivityEvent extends ActivityEvent {
  final Activity activity;
  const AddActivityEvent(this.activity);
  @override
  List<Object?> get props => [activity];
}

class UpdateActivityEvent extends ActivityEvent {
  final Activity activity;
  const UpdateActivityEvent(this.activity);
  @override
  List<Object?> get props => [activity];
}

class DeleteActivityEvent extends ActivityEvent {
  final int id;
  const DeleteActivityEvent(this.id);
  @override
  List<Object?> get props => [id];
}

class ActivitiesUpdated extends ActivityEvent {
  final List<Activity> activities;
  const ActivitiesUpdated(this.activities);
  @override
  List<Object?> get props => [activities];
}

// States
abstract class ActivityState extends Equatable {
  const ActivityState();
  @override
  List<Object?> get props => [];
}

class ActivityInitial extends ActivityState {}

class ActivityLoading extends ActivityState {}

class ActivityLoaded extends ActivityState {
  final List<Activity> activities;
  const ActivityLoaded(this.activities);
  @override
  List<Object?> get props => [activities];
}

class ActivityOperationFailure extends ActivityLoaded {
  final String operationMessage;
  const ActivityOperationFailure(super.activities, this.operationMessage);
  @override
  List<Object?> get props => [activities, operationMessage];
}

class ActivityError extends ActivityState {
  final String message;
  const ActivityError(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc
@injectable
class ActivityBloc extends Bloc<ActivityEvent, ActivityState> {
  final ActivityRepository _repository;

  ActivityBloc(this._repository) : super(ActivityInitial()) {
    on<LoadActivities>(_onLoadActivities, transformer: restartable());
    on<AddActivityEvent>(_onAddActivity);
    on<UpdateActivityEvent>(_onUpdateActivity);
    on<DeleteActivityEvent>(_onDeleteActivity);
  }

  Future<void> _onLoadActivities(
    LoadActivities event,
    Emitter<ActivityState> emit,
  ) async {
    emit(ActivityLoading());
    await emit.forEach<List<Activity>>(
      _repository.watchActivities(),
      onData: (activities) => ActivityLoaded(activities),
      onError: (e, s) =>
          ActivityError('Gagal memuat kegiatan: ${e.toString()}'),
    );
  }

  Future<void> _onAddActivity(
    AddActivityEvent event,
    Emitter<ActivityState> emit,
  ) async {
    try {
      await _repository.addActivity(event.activity);
    } catch (e) {
      if (state is ActivityLoaded) {
        emit(
          ActivityOperationFailure(
            (state as ActivityLoaded).activities,
            'Gagal menambah kegiatan: ${e.toString()}',
          ),
        );
      } else {
        emit(ActivityError('Gagal menambah kegiatan: ${e.toString()}'));
      }
    }
  }

  Future<void> _onUpdateActivity(
    UpdateActivityEvent event,
    Emitter<ActivityState> emit,
  ) async {
    try {
      await _repository.updateActivity(event.activity);
    } catch (e) {
      if (state is ActivityLoaded) {
        emit(
          ActivityOperationFailure(
            (state as ActivityLoaded).activities,
            'Gagal mengupdate kegiatan: ${e.toString()}',
          ),
        );
      } else {
        emit(ActivityError('Gagal mengupdate kegiatan: ${e.toString()}'));
      }
    }
  }

  Future<void> _onDeleteActivity(
    DeleteActivityEvent event,
    Emitter<ActivityState> emit,
  ) async {
    try {
      await _repository.deleteActivity(event.id);
    } catch (e) {
      if (state is ActivityLoaded) {
        emit(
          ActivityOperationFailure(
            (state as ActivityLoaded).activities,
            'Gagal menghapus kegiatan: ${e.toString()}',
          ),
        );
      } else {
        emit(ActivityError('Gagal menghapus kegiatan: ${e.toString()}'));
      }
    }
  }
}
