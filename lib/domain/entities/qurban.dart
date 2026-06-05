import 'package:equatable/equatable.dart';
import 'package:masjid_app/domain/entities/transaction.dart';

enum QurbanProgressStatus { notStarted, current, overdue, paidOff, overpaid }

class QurbanPackage extends Equatable {
  final int? id;
  final String? remoteId;
  final String name;
  final double monthlyAmount;
  final bool isActive;
  final SyncStatus syncStatus;

  const QurbanPackage({
    this.id,
    this.remoteId,
    required this.name,
    required this.monthlyAmount,
    this.isActive = true,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  QurbanPackage copyWith({
    int? id,
    String? remoteId,
    String? name,
    double? monthlyAmount,
    bool? isActive,
    SyncStatus? syncStatus,
  }) {
    return QurbanPackage(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      name: name ?? this.name,
      monthlyAmount: monthlyAmount ?? this.monthlyAmount,
      isActive: isActive ?? this.isActive,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  List<Object?> get props => [
    id,
    remoteId,
    name,
    monthlyAmount,
    isActive,
    syncStatus,
  ];
}

class QurbanParticipant extends Equatable {
  final int? id;
  final String? remoteId;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final DateTime startMonth;
  final double monthlyAmount;
  final int totalMonths;
  final SyncStatus syncStatus;

  const QurbanParticipant({
    this.id,
    this.remoteId,
    required this.name,
    this.phone,
    this.address,
    this.notes,
    required this.startMonth,
    required this.monthlyAmount,
    this.totalMonths = 10,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  double get targetAmount => monthlyAmount * totalMonths;

  QurbanParticipant copyWith({
    int? id,
    String? remoteId,
    String? name,
    String? phone,
    String? address,
    String? notes,
    DateTime? startMonth,
    double? monthlyAmount,
    int? totalMonths,
    SyncStatus? syncStatus,
  }) {
    return QurbanParticipant(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      startMonth: startMonth ?? this.startMonth,
      monthlyAmount: monthlyAmount ?? this.monthlyAmount,
      totalMonths: totalMonths ?? this.totalMonths,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  List<Object?> get props => [
    id,
    remoteId,
    name,
    phone,
    address,
    notes,
    startMonth,
    monthlyAmount,
    totalMonths,
    syncStatus,
  ];
}

class QurbanPayment extends Equatable {
  final int? id;
  final String? remoteId;
  final int participantId;
  final int? transactionId;
  final double amount;
  final DateTime paymentDate;
  final String? note;
  final SyncStatus syncStatus;

  const QurbanPayment({
    this.id,
    this.remoteId,
    required this.participantId,
    this.transactionId,
    required this.amount,
    required this.paymentDate,
    this.note,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  QurbanPayment copyWith({
    int? id,
    String? remoteId,
    int? participantId,
    int? transactionId,
    double? amount,
    DateTime? paymentDate,
    String? note,
    SyncStatus? syncStatus,
  }) {
    return QurbanPayment(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      participantId: participantId ?? this.participantId,
      transactionId: transactionId ?? this.transactionId,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      note: note ?? this.note,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  List<Object?> get props => [
    id,
    remoteId,
    participantId,
    transactionId,
    amount,
    paymentDate,
    note,
    syncStatus,
  ];
}

class QurbanParticipantProgress extends Equatable {
  final QurbanParticipant participant;
  final List<QurbanPayment> payments;
  final double paidAmount;
  final double dueAmount;

  const QurbanParticipantProgress({
    required this.participant,
    required this.payments,
    required this.paidAmount,
    required this.dueAmount,
  });

  double get targetAmount => participant.targetAmount;
  double get remainingAmount =>
      (targetAmount - paidAmount).clamp(0, double.infinity).toDouble();
  double get arrearsAmount => paidAmount >= targetAmount
      ? 0
      : (dueAmount - paidAmount).clamp(0, double.infinity).toDouble();
  int get paidMonthEquivalent => participant.monthlyAmount <= 0
      ? 0
      : paidAmount ~/ participant.monthlyAmount;

  QurbanProgressStatus get status {
    if (paidAmount > targetAmount) return QurbanProgressStatus.overpaid;
    if (paidAmount >= targetAmount) return QurbanProgressStatus.paidOff;
    if (DateTime.now().isBefore(participant.startMonth)) {
      return QurbanProgressStatus.notStarted;
    }
    if (arrearsAmount > 0) return QurbanProgressStatus.overdue;
    return QurbanProgressStatus.current;
  }

  @override
  List<Object?> get props => [participant, payments, paidAmount, dueAmount];
}

class QurbanSummary extends Equatable {
  final double totalTarget;
  final double totalCollected;
  final double totalRemaining;
  final int participantCount;
  final int paidOffCount;
  final int overdueCount;
  final int overpaidCount;

  const QurbanSummary({
    required this.totalTarget,
    required this.totalCollected,
    required this.totalRemaining,
    required this.participantCount,
    required this.paidOffCount,
    required this.overdueCount,
    required this.overpaidCount,
  });

  factory QurbanSummary.fromProgress(List<QurbanParticipantProgress> progress) {
    final totalTarget = progress.fold<double>(
      0,
      (sum, item) => sum + item.targetAmount,
    );
    final totalCollected = progress.fold<double>(
      0,
      (sum, item) => sum + item.paidAmount,
    );
    return QurbanSummary(
      totalTarget: totalTarget,
      totalCollected: totalCollected,
      totalRemaining: (totalTarget - totalCollected)
          .clamp(0, double.infinity)
          .toDouble(),
      participantCount: progress.length,
      paidOffCount: progress
          .where((p) => p.status == QurbanProgressStatus.paidOff)
          .length,
      overdueCount: progress
          .where((p) => p.status == QurbanProgressStatus.overdue)
          .length,
      overpaidCount: progress
          .where((p) => p.status == QurbanProgressStatus.overpaid)
          .length,
    );
  }

  @override
  List<Object?> get props => [
    totalTarget,
    totalCollected,
    totalRemaining,
    participantCount,
    paidOffCount,
    overdueCount,
    overpaidCount,
  ];
}
