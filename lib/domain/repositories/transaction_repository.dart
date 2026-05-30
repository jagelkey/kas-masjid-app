import 'package:flutter/material.dart';
import 'package:masjid_app/domain/entities/transaction.dart';

abstract class TransactionRepository {
  Stream<List<Transaction>> watchTransactions({
    DateTimeRange? dateRange,
    TransactionType? type,
    String? category,
  });
  Future<List<Transaction>> getTransactions();
  Future<void> addTransaction(Transaction transaction);
  Future<void> updateTransaction(Transaction transaction);
  Future<void> deleteTransaction(int id);
  Future<double> getTotalBalance();
  Future<double> getIncomeThisMonth();
  Future<double> getExpenseThisMonth();
}
