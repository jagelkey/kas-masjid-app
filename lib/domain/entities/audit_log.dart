import 'package:equatable/equatable.dart';

class AuditLog extends Equatable {
  final int? id; // Local ID
  final String? remoteId;
  final String userId;
  final String action;
  final String? targetTable;
  final String? recordId;
  final String? description;
  final DateTime createdAt;
  final int syncStatus; // 0: Synced, 1: PendingCreate
  final String? userName;

  const AuditLog({
    this.id,
    this.remoteId,
    required this.userId,
    required this.action,
    this.targetTable,
    this.recordId,
    this.description,
    required this.createdAt,
    this.syncStatus = 1,
    this.userName,
  });

  @override
  List<Object?> get props => [
    id,
    remoteId,
    userId,
    action,
    targetTable,
    recordId,
    description,
    createdAt,
    syncStatus,
    userName,
  ];
}
