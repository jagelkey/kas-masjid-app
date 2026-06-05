import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:injectable/injectable.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/domain/entities/transaction.dart' as domain;
import 'package:masjid_app/domain/repositories/transaction_repository.dart';

import 'package:masjid_app/domain/repositories/audit_log_repository.dart';

@LazySingleton(as: TransactionRepository)
class TransactionRepositoryImpl implements TransactionRepository {
  final AppDatabase _db;
  final AuditLogRepository _auditLogRepository;

  TransactionRepositoryImpl(this._db, this._auditLogRepository);

  @override
  Stream<List<domain.Transaction>> watchTransactions({
    DateTimeRange? dateRange,
    domain.TransactionType? type,
    String? category,
  }) {
    final query = _db.select(_db.transactions)
      ..where(
        (t) => t.syncStatus.isNotValue(domain.SyncStatus.pendingDelete.index),
      );

    if (dateRange != null) {
      query.where(
        (t) => t.date.isBetweenValues(
          dateRange.start.subtract(const Duration(seconds: 1)),
          dateRange.end.add(const Duration(seconds: 1)),
        ),
      );
    }

    if (type != null) {
      query.where((t) => t.type.equalsValue(type));
    }

    if (category != null && category.isNotEmpty) {
      query.where((t) => t.category.equals(category));
    }

    // Sort by date descending
    query.orderBy([
      (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
    ]);

    return query.watch().map((rows) {
      return rows.map((row) => _mapToDomain(row)).toList();
    });
  }

  @override
  Future<List<domain.Transaction>> getTransactions() async {
    final rows = await _db.select(_db.transactions).get();
    return rows.map((row) => _mapToDomain(row)).toList();
  }

  @override
  Future<void> addTransaction(domain.Transaction transaction) async {
    await _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion(
            remoteId: Value(transaction.remoteId),
            type: Value(transaction.type),
            amount: Value(transaction.amount),
            category: Value(transaction.category),
            description: Value(transaction.description),
            date: Value(transaction.date),
            proofPaths: Value(transaction.proofPaths),
            proofUrls: Value(transaction.proofUrls),
            source: Value(transaction.source),
            sourceRef: Value(transaction.sourceRef),
            syncStatus: Value(domain.SyncStatus.pendingCreate),
          ),
        );

    await _auditLogRepository.logActivity(
      action: 'CREATE',
      targetTable: 'transactions',
      description:
          'Transaction: ${transaction.category} - ${transaction.amount}',
    );
  }

  @override
  Future<void> updateTransaction(domain.Transaction transaction) async {
    if (transaction.id == null) return;

    // Check existing sync status and remoteId
    final existing = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(transaction.id!))).getSingleOrNull();

    if (existing == null) return;
    if (existing.source == domain.TransactionSource.qurban) {
      throw Exception(
        'Transaksi iuran qurban hanya bisa diedit dari menu Qurban',
      );
    }

    final newSyncStatus = existing.syncStatus == domain.SyncStatus.pendingCreate
        ? domain.SyncStatus.pendingCreate
        : domain.SyncStatus.pendingUpdate;

    await (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(transaction.id!))).write(
      TransactionsCompanion(
        type: Value(transaction.type),
        amount: Value(transaction.amount),
        category: Value(transaction.category),
        description: Value(transaction.description),
        date: Value(transaction.date),
        proofPaths: Value(transaction.proofPaths),
        proofUrls: Value(transaction.proofUrls),
        source: Value(transaction.source),
        sourceRef: Value(transaction.sourceRef),
        syncStatus: Value(newSyncStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _auditLogRepository.logActivity(
      action: 'UPDATE',
      targetTable: 'transactions',
      recordId: transaction.id.toString(),
      description:
          'Updated Transaction: ${transaction.category} - ${transaction.amount}',
    );
  }

  @override
  Future<void> deleteTransaction(int id) async {
    // Soft delete or Hard delete?
    // For sync, we usually need soft delete (mark as deleted) or keep track of deleted IDs.
    // For now, let's just mark as pendingDelete if it has remoteId, else hard delete.
    final transaction = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (transaction == null) return;
    if (transaction.source == domain.TransactionSource.qurban) {
      throw Exception(
        'Transaksi iuran qurban hanya bisa dihapus dari menu Qurban',
      );
    }

    if (transaction.remoteId != null) {
      // Mark for deletion on server
      await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          syncStatus: Value(domain.SyncStatus.pendingDelete),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      // Local only, safe to delete
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
    }

    await _auditLogRepository.logActivity(
      action: 'DELETE',
      targetTable: 'transactions',
      recordId: id.toString(),
      description:
          'Deleted Transaction: ${transaction.category} - ${transaction.amount}',
    );
  }

  @override
  Future<double> getTotalBalance() async {
    final incomeQuery = _db.selectOnly(_db.transactions)
      ..addColumns([_db.transactions.amount.sum()])
      ..where(_db.transactions.type.equalsValue(domain.TransactionType.income))
      ..where(
        _db.transactions.syncStatus.isNotValue(
          domain.SyncStatus.pendingDelete.index,
        ),
      );

    final expenseQuery = _db.selectOnly(_db.transactions)
      ..addColumns([_db.transactions.amount.sum()])
      ..where(_db.transactions.type.equalsValue(domain.TransactionType.expense))
      ..where(
        _db.transactions.syncStatus.isNotValue(
          domain.SyncStatus.pendingDelete.index,
        ),
      );

    final incomeResult = await incomeQuery.getSingle();
    final expenseResult = await expenseQuery.getSingle();

    final totalIncome = incomeResult.read(_db.transactions.amount.sum()) ?? 0.0;
    final totalExpense =
        expenseResult.read(_db.transactions.amount.sum()) ?? 0.0;

    return totalIncome - totalExpense;
  }

  @override
  Future<double> getIncomeThisMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    // Move to first day of next month and subtract 1 second to get the very end of current month
    final endOfMonth = DateTime(
      now.year,
      now.month + 1,
      1,
    ).subtract(const Duration(seconds: 1));

    final query = _db.select(_db.transactions)
      ..where((t) => t.type.equalsValue(domain.TransactionType.income))
      ..where((t) => t.date.isBetweenValues(startOfMonth, endOfMonth))
      ..where(
        (t) => t.syncStatus.isNotValue(domain.SyncStatus.pendingDelete.index),
      );

    final rows = await query.get();
    return rows.fold<double>(0.0, (sum, row) => sum + row.amount);
  }

  @override
  Future<double> getExpenseThisMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(
      now.year,
      now.month + 1,
      1,
    ).subtract(const Duration(seconds: 1));

    final query = _db.select(_db.transactions)
      ..where((t) => t.type.equalsValue(domain.TransactionType.expense))
      ..where((t) => t.date.isBetweenValues(startOfMonth, endOfMonth))
      ..where(
        (t) => t.syncStatus.isNotValue(domain.SyncStatus.pendingDelete.index),
      );

    final rows = await query.get();
    return rows.fold<double>(0.0, (sum, row) => sum + row.amount);
  }

  // Mappers
  domain.Transaction _mapToDomain(TransactionEntity row) {
    return domain.Transaction(
      id: row.id,
      remoteId: row.remoteId,
      type: row.type,
      amount: row.amount,
      category: row.category,
      description: row.description,
      date: row.date,
      proofPaths: row.proofPaths,
      proofUrls: row.proofUrls,
      source: row.source,
      sourceRef: row.sourceRef,
      syncStatus: row.syncStatus,
    );
  }
}
