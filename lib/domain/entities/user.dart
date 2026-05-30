import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  final int? id;
  final String? remoteId;
  final String email;
  final String? username;
  final String? fullName;
  final String role; // admin, ketua, bendahara, sekretaris, viewer
  final int syncStatus; // 0: Synced, 1: PendingCreate, 2: PendingUpdate, 3: PendingDelete

  const UserEntity({
    this.id,
    this.remoteId,
    required this.email,
    this.username,
    this.fullName,
    this.role = 'viewer',
    this.syncStatus = 1,
  });

  @override
  List<Object?> get props =>
      [id, remoteId, email, username, fullName, role, syncStatus];

  UserEntity copyWith({
    int? id,
    String? remoteId,
    String? email,
    String? username,
    String? fullName,
    String? role,
    int? syncStatus,
  }) {
    return UserEntity(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      email: email ?? this.email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
