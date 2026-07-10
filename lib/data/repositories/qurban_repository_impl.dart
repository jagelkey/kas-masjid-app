import 'dart:async';

import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as tx_domain;
import 'package:masjid_app/domain/repositories/audit_log_repository.dart';
import 'package:masjid_app/domain/repositories/qurban_repository.dart';
import 'package:uuid/uuid.dart';

@LazySingleton(as: QurbanRepository)
class QurbanRepositoryImpl implements QurbanRepository {
  static const _qurbanCategory = 'Iuran Qurban';
  static const _uuid = Uuid();

  final AppDatabase _db;
  final AuditLogRepository _auditLogRepository;

  QurbanRepositoryImpl(this._db, this._auditLogRepository);

  @override
  Stream<List<QurbanPackage>> watchPackages() {
    final query = _db.select(_db.qurbanPackages)
      ..where(
        (t) =>
            t.syncStatus.isNotValue(tx_domain.SyncStatus.pendingDelete.index),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.monthlyAmount)]);

    return query.watch().map((rows) => rows.map(_mapPackage).toList());
  }

  @override
  Stream<List<QurbanParticipantProgress>> watchParticipantProgress() {
    final controller = StreamController<List<QurbanParticipantProgress>>();
    StreamSubscription? participantSub;
    StreamSubscription? paymentSub;
    var closed = false;

    Future<void> emitProgress() async {
      if (closed) return;
      controller.add(await getParticipantProgress());
    }

    controller.onListen = () {
      participantSub = _db
          .select(_db.qurbanParticipants)
          .watch()
          .listen((_) => emitProgress(), onError: controller.addError);
      paymentSub = _db
          .select(_db.qurbanPayments)
          .watch()
          .listen((_) => emitProgress(), onError: controller.addError);
    };
    controller.onCancel = () async {
      closed = true;
      await participantSub?.cancel();
      await paymentSub?.cancel();
    };

    return controller.stream;
  }

  @override
  Stream<List<QurbanPayment>> watchPaymentsForParticipant(int participantId) {
    final query = _db.select(_db.qurbanPayments)
      ..where((t) => t.participantId.equals(participantId))
      ..where(
        (t) =>
            t.syncStatus.isNotValue(tx_domain.SyncStatus.pendingDelete.index),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
      ]);

    return query.watch().map((rows) => rows.map(_mapPayment).toList());
  }

  @override
  Future<List<QurbanPackage>> getPackages() async {
    final rows =
        await (_db.select(_db.qurbanPackages)..where(
              (t) => t.syncStatus.isNotValue(
                tx_domain.SyncStatus.pendingDelete.index,
              ),
            ))
            .get();
    rows.sort((a, b) => a.monthlyAmount.compareTo(b.monthlyAmount));
    return rows.map(_mapPackage).toList();
  }

  @override
  Future<List<QurbanParticipantProgress>> getParticipantProgress() async {
    final participantRows =
        await (_db.select(_db.qurbanParticipants)..where(
              (t) => t.syncStatus.isNotValue(
                tx_domain.SyncStatus.pendingDelete.index,
              ),
            ))
            .get();
    participantRows.sort((a, b) => a.name.compareTo(b.name));

    final paymentRows =
        await (_db.select(_db.qurbanPayments)..where(
              (t) => t.syncStatus.isNotValue(
                tx_domain.SyncStatus.pendingDelete.index,
              ),
            ))
            .get();
    final paymentsByParticipant = <int, List<QurbanPayment>>{};
    for (final row in paymentRows) {
      paymentsByParticipant
          .putIfAbsent(row.participantId, () => [])
          .add(_mapPayment(row));
    }

    return participantRows.map((row) {
      final participant = _mapParticipant(row);
      final payments = paymentsByParticipant[row.id] ?? const <QurbanPayment>[];
      final paidAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);
      return QurbanParticipantProgress(
        participant: participant,
        payments: payments,
        paidAmount: paidAmount,
        dueAmount: _calculateDueAmount(participant, DateTime.now()),
      );
    }).toList();
  }

  @override
  Future<List<QurbanPayment>> getPaymentsForParticipant(
    int participantId,
  ) async {
    final rows =
        await (_db.select(_db.qurbanPayments)
              ..where((t) => t.participantId.equals(participantId))
              ..where(
                (t) => t.syncStatus.isNotValue(
                  tx_domain.SyncStatus.pendingDelete.index,
                ),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.paymentDate,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return rows.map(_mapPayment).toList();
  }

  @override
  Future<void> addPackage(QurbanPackage package) async {
    final remoteId = package.remoteId ?? _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.qurbanPackages)
          .insert(
            QurbanPackagesCompanion.insert(
              remoteId: Value(remoteId),
              name: package.name.trim(),
              monthlyAmount: package.monthlyAmount,
              isActive: Value(package.isActive),
              syncStatus: const Value(tx_domain.SyncStatus.pendingCreate),
            ),
          );
      await _auditLogRepository.logActivity(
        action: 'CREATE',
        targetTable: 'qurban_packages',
        description: 'Paket qurban: ${package.name}',
      );
    });
  }

  @override
  Future<void> updatePackage(QurbanPackage package) async {
    if (package.id == null) return;
    final existing = await (_db.select(
      _db.qurbanPackages,
    )..where((t) => t.id.equals(package.id!))).getSingleOrNull();
    if (existing == null) return;

    await _db.transaction(() async {
      await (_db.update(
        _db.qurbanPackages,
      )..where((t) => t.id.equals(package.id!))).write(
        QurbanPackagesCompanion(
          name: Value(package.name.trim()),
          monthlyAmount: Value(package.monthlyAmount),
          isActive: Value(package.isActive),
          syncStatus: Value(_nextSyncStatus(existing.syncStatus)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _auditLogRepository.logActivity(
        action: 'UPDATE',
        targetTable: 'qurban_packages',
        recordId: package.id.toString(),
        description: 'Update paket qurban: ${package.name}',
      );
    });
  }

  @override
  Future<void> deletePackage(int id) async {
    final existing = await (_db.select(
      _db.qurbanPackages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return;

    await _db.transaction(() async {
      if (existing.syncStatus == tx_domain.SyncStatus.pendingCreate) {
        await (_db.delete(
          _db.qurbanPackages,
        )..where((t) => t.id.equals(id))).go();
      } else {
        await (_db.update(
          _db.qurbanPackages,
        )..where((t) => t.id.equals(id))).write(
          QurbanPackagesCompanion(
            isActive: const Value(false),
            syncStatus: const Value(tx_domain.SyncStatus.pendingDelete),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      await _auditLogRepository.logActivity(
        action: 'DELETE',
        targetTable: 'qurban_packages',
        recordId: id.toString(),
        description: 'Hapus paket qurban: ${existing.name}',
      );
    });
  }

  @override
  Future<void> addParticipant(QurbanParticipant participant) async {
    await _db.transaction(() async {
      await _db
          .into(_db.qurbanParticipants)
          .insert(
            QurbanParticipantsCompanion.insert(
              remoteId: Value(participant.remoteId ?? _uuid.v4()),
              name: participant.name.trim(),
              phone: Value(_emptyToNull(participant.phone)),
              address: Value(_emptyToNull(participant.address)),
              notes: Value(_emptyToNull(participant.notes)),
              startMonth: _normalizeMonth(participant.startMonth),
              monthlyAmount: participant.monthlyAmount,
              totalMonths: Value(participant.totalMonths),
              syncStatus: const Value(tx_domain.SyncStatus.pendingCreate),
            ),
          );
      await _auditLogRepository.logActivity(
        action: 'CREATE',
        targetTable: 'qurban_participants',
        description: 'Peserta qurban: ${participant.name}',
      );
    });
  }

  @override
  Future<void> updateParticipant(QurbanParticipant participant) async {
    if (participant.id == null) return;
    final existing = await (_db.select(
      _db.qurbanParticipants,
    )..where((t) => t.id.equals(participant.id!))).getSingleOrNull();
    if (existing == null) return;

    await _db.transaction(() async {
      await (_db.update(
        _db.qurbanParticipants,
      )..where((t) => t.id.equals(participant.id!))).write(
        QurbanParticipantsCompanion(
          name: Value(participant.name.trim()),
          phone: Value(_emptyToNull(participant.phone)),
          address: Value(_emptyToNull(participant.address)),
          notes: Value(_emptyToNull(participant.notes)),
          startMonth: Value(_normalizeMonth(participant.startMonth)),
          monthlyAmount: Value(participant.monthlyAmount),
          totalMonths: Value(participant.totalMonths),
          syncStatus: Value(_nextSyncStatus(existing.syncStatus)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _auditLogRepository.logActivity(
        action: 'UPDATE',
        targetTable: 'qurban_participants',
        recordId: participant.id.toString(),
        description: 'Update peserta qurban: ${participant.name}',
      );
    });
  }

  @override
  Future<void> deleteParticipant(int id) async {
    final existing = await (_db.select(
      _db.qurbanParticipants,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return;

    final payments =
        await (_db.select(_db.qurbanPayments)
              ..where((t) => t.participantId.equals(id))
              ..where(
                (t) => t.syncStatus.isNotValue(
                  tx_domain.SyncStatus.pendingDelete.index,
                ),
              ))
            .get();
    if (payments.isNotEmpty) {
      throw Exception('Peserta sudah memiliki pembayaran');
    }

    await _db.transaction(() async {
      if (existing.syncStatus == tx_domain.SyncStatus.pendingCreate) {
        await (_db.delete(
          _db.qurbanParticipants,
        )..where((t) => t.id.equals(id))).go();
      } else {
        await (_db.update(
          _db.qurbanParticipants,
        )..where((t) => t.id.equals(id))).write(
          QurbanParticipantsCompanion(
            syncStatus: const Value(tx_domain.SyncStatus.pendingDelete),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      await _auditLogRepository.logActivity(
        action: 'DELETE',
        targetTable: 'qurban_participants',
        recordId: id.toString(),
        description: 'Hapus peserta qurban: ${existing.name}',
      );
    });
  }

  @override
  Future<void> addPayment(QurbanPayment payment) async {
    await _db.transaction(() async {
      final participant = await _getParticipantOrThrow(payment.participantId);
      final paymentRemoteId = payment.remoteId ?? _uuid.v4();
      final transactionRemoteId = _uuid.v4();

      final transactionId = await _db
          .into(_db.transactions)
          .insert(
            TransactionsCompanion.insert(
              remoteId: Value(transactionRemoteId),
              type: tx_domain.TransactionType.income,
              amount: payment.amount,
              category: _qurbanCategory,
              description: Value(
                _buildPaymentDescription(participant, payment),
              ),
              date: payment.paymentDate,
              source: const Value(tx_domain.TransactionSource.qurban),
              sourceRef: Value(paymentRemoteId),
              syncStatus: const Value(tx_domain.SyncStatus.pendingCreate),
            ),
          );

      await _db
          .into(_db.qurbanPayments)
          .insert(
            QurbanPaymentsCompanion.insert(
              remoteId: Value(paymentRemoteId),
              participantId: payment.participantId,
              transactionId: Value(transactionId),
              amount: payment.amount,
              paymentDate: payment.paymentDate,
              note: Value(_emptyToNull(payment.note)),
              syncStatus: const Value(tx_domain.SyncStatus.pendingCreate),
            ),
          );

      await _auditLogRepository.logActivity(
        action: 'CREATE',
        targetTable: 'qurban_payments',
        recordId: payment.participantId.toString(),
        description: 'Pembayaran qurban: ${payment.amount}',
      );
    });
  }

  @override
  Future<void> updatePayment(QurbanPayment payment) async {
    if (payment.id == null) return;

    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.qurbanPayments,
      )..where((t) => t.id.equals(payment.id!))).getSingleOrNull();
      if (existing == null) return;

      final participant = await _getParticipantOrThrow(payment.participantId);
      final paymentRemoteId =
          existing.remoteId ?? payment.remoteId ?? _uuid.v4();
      // Recover the link before assuming there isn't one, otherwise editing a
      // payment that arrived via sync creates a duplicate income transaction.
      var transactionId = await _resolveLinkedTransactionId(existing);

      if (transactionId == null) {
        transactionId = await _db
            .into(_db.transactions)
            .insert(
              TransactionsCompanion.insert(
                remoteId: Value(_uuid.v4()),
                type: tx_domain.TransactionType.income,
                amount: payment.amount,
                category: _qurbanCategory,
                description: Value(
                  _buildPaymentDescription(participant, payment),
                ),
                date: payment.paymentDate,
                source: const Value(tx_domain.TransactionSource.qurban),
                sourceRef: Value(paymentRemoteId),
                syncStatus: const Value(tx_domain.SyncStatus.pendingCreate),
              ),
            );
      } else {
        final transaction = await (_db.select(
          _db.transactions,
        )..where((t) => t.id.equals(transactionId!))).getSingleOrNull();
        if (transaction != null) {
          await (_db.update(
            _db.transactions,
          )..where((t) => t.id.equals(transactionId!))).write(
            TransactionsCompanion(
              type: const Value(tx_domain.TransactionType.income),
              amount: Value(payment.amount),
              category: const Value(_qurbanCategory),
              description: Value(
                _buildPaymentDescription(participant, payment),
              ),
              date: Value(payment.paymentDate),
              source: const Value(tx_domain.TransactionSource.qurban),
              sourceRef: Value(paymentRemoteId),
              syncStatus: Value(_nextSyncStatus(transaction.syncStatus)),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      await (_db.update(
        _db.qurbanPayments,
      )..where((t) => t.id.equals(payment.id!))).write(
        QurbanPaymentsCompanion(
          remoteId: Value(paymentRemoteId),
          participantId: Value(payment.participantId),
          transactionId: Value(transactionId),
          amount: Value(payment.amount),
          paymentDate: Value(payment.paymentDate),
          note: Value(_emptyToNull(payment.note)),
          syncStatus: Value(_nextSyncStatus(existing.syncStatus)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _auditLogRepository.logActivity(
        action: 'UPDATE',
        targetTable: 'qurban_payments',
        recordId: payment.id.toString(),
        description: 'Update pembayaran qurban: ${payment.amount}',
      );
    });
  }

  @override
  Future<void> deletePayment(int id) async {
    await _db.transaction(() async {
      final payment = await (_db.select(
        _db.qurbanPayments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      // `return` here only exits this transaction callback (the delete
      // simply doesn't happen), not the outer method -- so the audit log
      // call must live in this same branch, not after the transaction,
      // otherwise a delete of a non-existent payment would still log a
      // phantom "deleted" entry.
      if (payment == null) return;

      await _deleteLinkedTransaction(await _resolveLinkedTransactionId(payment));

      if (payment.syncStatus == tx_domain.SyncStatus.pendingCreate) {
        await (_db.delete(
          _db.qurbanPayments,
        )..where((t) => t.id.equals(id))).go();
      } else {
        await (_db.update(
          _db.qurbanPayments,
        )..where((t) => t.id.equals(id))).write(
          QurbanPaymentsCompanion(
            syncStatus: const Value(tx_domain.SyncStatus.pendingDelete),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      await _auditLogRepository.logActivity(
        action: 'DELETE',
        targetTable: 'qurban_payments',
        recordId: id.toString(),
        description: 'Hapus pembayaran qurban',
      );
    });
  }

  // A payment pulled from the server before its cash transaction reached this
  // device stores transactionId = null. The link is still recoverable, because
  // every qurban transaction carries the payment's remoteId in source_ref.
  // Without this lookup, updatePayment() would mint a SECOND income
  // transaction for the same payment (cash balance too high by one payment)
  // and deletePayment() would leave the original income orphaned in the books.
  Future<int?> _resolveLinkedTransactionId(QurbanPaymentEntity payment) async {
    if (payment.transactionId != null) return payment.transactionId;
    final paymentRemoteId = payment.remoteId;
    if (paymentRemoteId == null) return null;

    final linked =
        await (_db.select(_db.transactions)
              ..where(
                (t) =>
                    t.sourceRef.equals(paymentRemoteId) &
                    t.source.equals(tx_domain.TransactionSource.qurban),
              )
              ..limit(1))
            .getSingleOrNull();
    return linked?.id;
  }

  Future<void> _deleteLinkedTransaction(int? transactionId) async {
    if (transactionId == null) return;
    final transaction = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    if (transaction == null) return;

    if (transaction.syncStatus == tx_domain.SyncStatus.pendingCreate) {
      await (_db.delete(
        _db.transactions,
      )..where((t) => t.id.equals(transactionId))).go();
    } else {
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(transactionId))).write(
        TransactionsCompanion(
          syncStatus: const Value(tx_domain.SyncStatus.pendingDelete),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<QurbanParticipantEntity> _getParticipantOrThrow(int id) async {
    final participant = await (_db.select(
      _db.qurbanParticipants,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (participant == null) {
      throw Exception('Peserta qurban tidak ditemukan');
    }
    return participant;
  }

  tx_domain.SyncStatus _nextSyncStatus(tx_domain.SyncStatus current) {
    return current == tx_domain.SyncStatus.pendingCreate
        ? tx_domain.SyncStatus.pendingCreate
        : tx_domain.SyncStatus.pendingUpdate;
  }

  double _calculateDueAmount(QurbanParticipant participant, DateTime now) {
    final start = _normalizeMonth(participant.startMonth);
    final current = _normalizeMonth(now);
    if (current.isBefore(start)) return 0;
    // No `+ 1`: the registration month itself is a grace period (0 due),
    // matching a normal monthly installment -- the first month only
    // becomes due once it has fully elapsed. The old `+ 1` made a
    // participant registered this month show as "overdue" immediately,
    // before they could possibly have paid anything yet.
    final dueMonths =
        ((current.year - start.year) * 12 + current.month - start.month)
            .clamp(0, participant.totalMonths)
            .toInt();
    return dueMonths * participant.monthlyAmount;
  }

  DateTime _normalizeMonth(DateTime date) => DateTime(date.year, date.month);

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _buildPaymentDescription(
    QurbanParticipantEntity participant,
    QurbanPayment payment,
  ) {
    final note = _emptyToNull(payment.note);
    final base = 'Iuran Qurban - ${participant.name}';
    return note == null ? base : '$base ($note)';
  }

  QurbanPackage _mapPackage(QurbanPackageEntity row) {
    return QurbanPackage(
      id: row.id,
      remoteId: row.remoteId,
      name: row.name,
      monthlyAmount: row.monthlyAmount,
      isActive: row.isActive,
      syncStatus: row.syncStatus,
    );
  }

  QurbanParticipant _mapParticipant(QurbanParticipantEntity row) {
    return QurbanParticipant(
      id: row.id,
      remoteId: row.remoteId,
      name: row.name,
      phone: row.phone,
      address: row.address,
      notes: row.notes,
      startMonth: row.startMonth,
      monthlyAmount: row.monthlyAmount,
      totalMonths: row.totalMonths,
      syncStatus: row.syncStatus,
    );
  }

  QurbanPayment _mapPayment(QurbanPaymentEntity row) {
    return QurbanPayment(
      id: row.id,
      remoteId: row.remoteId,
      participantId: row.participantId,
      transactionId: row.transactionId,
      amount: row.amount,
      paymentDate: row.paymentDate,
      note: row.note,
      syncStatus: row.syncStatus,
    );
  }
}
