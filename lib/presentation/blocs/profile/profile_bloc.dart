import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/domain/entities/mosque_profile.dart';
import 'package:masjid_app/domain/repositories/mosque_profile_repository.dart';

// Events
abstract class ProfileEvent extends Equatable {
  const ProfileEvent();
  @override
  List<Object?> get props => [];
}

class LoadProfile extends ProfileEvent {}

class SaveProfile extends ProfileEvent {
  final MosqueProfile profile;
  const SaveProfile(this.profile);
  @override
  List<Object?> get props => [profile];
}

// States
abstract class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final MosqueProfile profile;
  final bool isSaving;
  const ProfileLoaded(this.profile, {this.isSaving = false});
  @override
  List<Object?> get props => [profile, isSaving];
}

class ProfileOperationFailure extends ProfileLoaded {
  final String operationMessage;
  const ProfileOperationFailure(super.profile, this.operationMessage);
  @override
  List<Object?> get props => [profile, isSaving, operationMessage];
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc
@injectable
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final MosqueProfileRepository _repository;

  ProfileBloc(this._repository) : super(ProfileInitial()) {
    on<LoadProfile>(_onLoadProfile);
    on<SaveProfile>(_onSaveProfile);
  }

  Future<void> _onLoadProfile(
    LoadProfile event,
    Emitter<ProfileState> emit,
  ) async {
    emit(ProfileLoading());
    try {
      final profile = await _repository.getProfile();
      if (profile != null) {
        emit(ProfileLoaded(profile));
      } else {
        // Return default empty profile if not found
        emit(
          const ProfileLoaded(
            MosqueProfile(name: 'Nama Masjid', address: 'Alamat Masjid'),
          ),
        );
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onSaveProfile(
    SaveProfile event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is ProfileLoaded) {
      emit(ProfileLoaded(event.profile, isSaving: true));
    } else {
      emit(ProfileLoading());
    }

    try {
      await _repository.saveProfile(event.profile);
      emit(ProfileLoaded(event.profile, isSaving: false));
    } catch (e) {
      if (state is ProfileLoaded) {
        emit(
          ProfileOperationFailure(
            (state as ProfileLoaded).profile,
            e.toString(),
          ),
        );
      } else {
        emit(ProfileError(e.toString()));
      }
    }
  }
}
