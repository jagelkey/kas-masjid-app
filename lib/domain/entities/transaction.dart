import 'package:equatable/equatable.dart';

enum TransactionType { income, expense }

enum SyncStatus { synced, pendingCreate, pendingUpdate, pendingDelete }

class TransactionSource {
  static const manual = 'manual';
  static const qurban = 'qurban';
}

class Transaction extends Equatable {
  final int? id; // Local ID
  final String? remoteId;
  final TransactionType type;
  final double amount;
  final String category;
  final String? description;
  final DateTime date;
  final List<String> proofPaths; // Local paths
  final List<String> proofUrls; // Remote URLs
  final String source;
  final String? sourceRef;
  final SyncStatus syncStatus;

  const Transaction({
    this.id,
    this.remoteId,
    required this.type,
    required this.amount,
    required this.category,
    this.description,
    required this.date,
    this.proofPaths = const [],
    this.proofUrls = const [],
    this.source = TransactionSource.manual,
    this.sourceRef,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  @override
  List<Object?> get props => [
    id,
    remoteId,
    type,
    amount,
    category,
    description,
    date,
    proofPaths,
    proofUrls,
    source,
    sourceRef,
    syncStatus,
  ];
}
