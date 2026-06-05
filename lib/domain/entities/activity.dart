import 'package:equatable/equatable.dart';
import 'package:masjid_app/domain/entities/transaction.dart'; // For SyncStatus

class Activity extends Equatable {
  final int? id;
  final String? remoteId;
  final String title;
  final String? description;
  final String type; // Pengajian, Sholat Jumat, etc.
  final DateTime date;
  final String? picName;
  final SyncStatus syncStatus;

  const Activity({
    this.id,
    this.remoteId,
    required this.title,
    this.description,
    required this.type,
    required this.date,
    this.picName,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  @override
  List<Object?> get props => [
    id,
    remoteId,
    title,
    description,
    type,
    date,
    picName,
    syncStatus,
  ];
}
