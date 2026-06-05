import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/domain/repositories/transaction_repository.dart';

// Events
abstract class TransactionEvent extends Equatable {
  const TransactionEvent();
  @override
  List<Object?> get props => [];
}

class LoadTransactions extends TransactionEvent {}

class ApplyFilterEvent extends TransactionEvent {
  final DateTimeRange? dateRange;
  final TransactionType? type;
  final String? category;

  const ApplyFilterEvent({this.dateRange, this.type, this.category});

  @override
  List<Object?> get props => [dateRange, type, category];
}

class AddTransactionEvent extends TransactionEvent {
  final Transaction transaction;
  const AddTransactionEvent(this.transaction);
  @override
  List<Object?> get props => [transaction];
}

class UpdateTransactionEvent extends TransactionEvent {
  final Transaction transaction;
  const UpdateTransactionEvent(this.transaction);
  @override
  List<Object?> get props => [transaction];
}

class DeleteTransactionEvent extends TransactionEvent {
  final int id;
  const DeleteTransactionEvent(this.id);
  @override
  List<Object?> get props => [id];
}

// States
abstract class TransactionState extends Equatable {
  const TransactionState();
  @override
  List<Object?> get props => [];
}

class TransactionInitial extends TransactionState {}

class TransactionLoading extends TransactionState {}

class TransactionLoaded extends TransactionState {
  final List<Transaction> transactions;
  final List<Transaction> filteredTransactions; // Added for filtered view
  final double totalBalance;
  final double incomeThisMonth;
  final double expenseThisMonth;
  final DateTimeRange? filterDateRange;
  final TransactionType? filterType;
  final String? filterCategory;

  const TransactionLoaded({
    this.transactions = const [],
    this.filteredTransactions = const [],
    this.totalBalance = 0,
    this.incomeThisMonth = 0,
    this.expenseThisMonth = 0,
    this.filterDateRange,
    this.filterType,
    this.filterCategory,
  });

  @override
  List<Object?> get props => [
    transactions,
    filteredTransactions,
    totalBalance,
    incomeThisMonth,
    expenseThisMonth,
    filterDateRange,
    filterType,
    filterCategory,
  ];

  TransactionLoaded copyWith({
    List<Transaction>? transactions,
    List<Transaction>? filteredTransactions,
    double? totalBalance,
    double? incomeThisMonth,
    double? expenseThisMonth,
    DateTimeRange? filterDateRange,
    TransactionType? filterType,
    String? filterCategory,
  }) {
    return TransactionLoaded(
      transactions: transactions ?? this.transactions,
      filteredTransactions: filteredTransactions ?? this.filteredTransactions,
      totalBalance: totalBalance ?? this.totalBalance,
      incomeThisMonth: incomeThisMonth ?? this.incomeThisMonth,
      expenseThisMonth: expenseThisMonth ?? this.expenseThisMonth,
      filterDateRange: filterDateRange ?? this.filterDateRange,
      filterType: filterType ?? this.filterType,
      filterCategory: filterCategory ?? this.filterCategory,
    );
  }
}

class TransactionOperationFailure extends TransactionLoaded {
  final String operationMessage;

  TransactionOperationFailure(TransactionLoaded state, this.operationMessage)
    : super(
        transactions: state.transactions,
        filteredTransactions: state.filteredTransactions,
        totalBalance: state.totalBalance,
        incomeThisMonth: state.incomeThisMonth,
        expenseThisMonth: state.expenseThisMonth,
        filterDateRange: state.filterDateRange,
        filterType: state.filterType,
        filterCategory: state.filterCategory,
      );

  @override
  List<Object?> get props => [...super.props, operationMessage];
}

class TransactionOperationSuccess extends TransactionLoaded {
  final String operationMessage;

  TransactionOperationSuccess(TransactionLoaded state, this.operationMessage)
    : super(
        transactions: state.transactions,
        filteredTransactions: state.filteredTransactions,
        totalBalance: state.totalBalance,
        incomeThisMonth: state.incomeThisMonth,
        expenseThisMonth: state.expenseThisMonth,
        filterDateRange: state.filterDateRange,
        filterType: state.filterType,
        filterCategory: state.filterCategory,
      );

  @override
  List<Object?> get props => [...super.props, operationMessage];
}

class TransactionError extends TransactionState {
  final String message;
  const TransactionError(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc
@injectable
class TransactionBloc extends Bloc<TransactionEvent, TransactionState> {
  final TransactionRepository _repository;

  TransactionBloc(this._repository) : super(TransactionInitial()) {
    on<LoadTransactions>(_onLoadTransactions, transformer: restartable());
    on<TransactionsUpdated>(_onTransactionsUpdated);
    on<AddTransactionEvent>(_onAddTransaction);
    on<UpdateTransactionEvent>(_onUpdateTransaction);
    on<DeleteTransactionEvent>(_onDeleteTransaction);
    on<ApplyFilterEvent>(_onApplyFilter);
  }

  Future<void> _onLoadTransactions(
    LoadTransactions event,
    Emitter<TransactionState> emit,
  ) async {
    emit(TransactionLoading());

    // Default filter: All time or maybe this month? For now, let's keep it empty (all time)
    // or we can initialize with current month if needed.

    await emit.forEach<List<Transaction>>(
      _repository.watchTransactions(), // Initial watch with no filters
      onData: (transactions) {
        add(TransactionsUpdated(transactions));
        return state;
      },
      onError: (e, s) => TransactionError('Gagal memuat data: ${e.toString()}'),
    );
  }

  Future<void> _onTransactionsUpdated(
    TransactionsUpdated event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      final totalBalance = await _repository.getTotalBalance();
      final income = await _repository.getIncomeThisMonth();
      final expense = await _repository.getExpenseThisMonth();

      // With the new logic, event.transactions IS ALREADY FILTERED by the repository stream
      // if we were using a reactive variable for filters.
      // However, since we are using a single stream subscription in _onLoadTransactions,
      // changing filters needs to RE-SUBSCRIBE.
      //
      // WAIT! The standard Bloc pattern for search/filter usually involves:
      // 1. Changing state variables
      // 2. Triggering a new fetch/subscription

      // Let's adapt. _onLoadTransactions is only called once at start.
      // To support dynamic DB filtering, we need to cancel previous subscription and start new one
      // OR use a StreamSwitch (RxDart) but we want to keep it simple.

      // CURRENT APPROACH IS HYBRID:
      // 1. We kept the Repository filter capability.
      // 2. But _onLoadTransactions uses NO filter.
      // 3. So event.transactions contains ALL data (except deleted).
      // 4. We can still use in-memory filtering for now OR refactor _onApplyFilter to re-subscribe.

      // Let's stick to in-memory for this specific bloc structure to avoid complexity of stream management
      // BUT we already implemented the repo method.
      // Ideally, we should restart the stream.

      // For now, let's use the IN-MEMORY logic as it's safer for this current turn without rewriting the whole bloc.
      // I will keep the in-memory logic but use the repo method for the initial load ensuring "pendingDelete" are ignored.

      List<Transaction> filtered = event.transactions;
      DateTimeRange? currentRange;
      TransactionType? currentType;
      String? currentCategory;

      if (state is TransactionLoaded) {
        final currentState = state as TransactionLoaded;
        currentRange = currentState.filterDateRange;
        currentType = currentState.filterType;
        currentCategory = currentState.filterCategory;
        filtered = _applyFilterLogic(
          event.transactions,
          currentRange,
          currentType,
          currentCategory,
        );
      } else {
        filtered = event.transactions;
      }

      emit(
        TransactionLoaded(
          transactions: event.transactions,
          filteredTransactions: filtered,
          totalBalance: totalBalance,
          incomeThisMonth: income,
          expenseThisMonth: expense,
          filterDateRange: currentRange,
          filterType: currentType,
          filterCategory: currentCategory,
        ),
      );
    } catch (e) {
      emit(TransactionError('Gagal memperbarui data: ${e.toString()}'));
    }
  }

  Future<void> _onApplyFilter(
    ApplyFilterEvent event,
    Emitter<TransactionState> emit,
  ) async {
    // Note: To fully utilize DB filtering, we would need to emit.forEach again with new params.
    // But standard Bloc `emit.forEach` doesn't support "switching" streams easily within the same handler
    // without cancelling the previous one manually.
    // For now, we will stick to in-memory filtering which is fast enough for <10k records.
    // The Repo update was still useful for "pendingDelete" exclusion globally.

    if (state is TransactionLoaded) {
      final currentState = state as TransactionLoaded;
      final filtered = _applyFilterLogic(
        currentState.transactions,
        event.dateRange,
        event.type,
        event.category,
      );

      emit(
        currentState.copyWith(
          filteredTransactions: filtered,
          filterDateRange: event.dateRange,
          filterType: event.type,
          filterCategory: event.category,
        ),
      );
    }
  }

  List<Transaction> _applyFilterLogic(
    List<Transaction> transactions,
    DateTimeRange? range,
    TransactionType? type,
    String? category,
  ) {
    return transactions.where((t) {
      bool matchDate = true;
      if (range != null) {
        // Normalize dates to ensure we cover the full day of the end range
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final end = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
        ).add(const Duration(days: 1));

        matchDate =
            t.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(end);
      }

      bool matchType = true;
      if (type != null) {
        matchType = t.type == type;
      }

      bool matchCategory = true;
      if (category != null && category.isNotEmpty) {
        matchCategory = t.category == category;
      }

      return matchDate && matchType && matchCategory;
    }).toList();
  }

  Future<void> _onAddTransaction(
    AddTransactionEvent event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.addTransaction(event.transaction);
      if (state is TransactionLoaded) {
        emit(
          TransactionOperationSuccess(
            state as TransactionLoaded,
            'Transaksi berhasil ditambahkan',
          ),
        );
      }
      // Stream will trigger update
    } catch (e) {
      if (state is TransactionLoaded) {
        emit(
          TransactionOperationFailure(
            state as TransactionLoaded,
            'Gagal menambah transaksi: ${e.toString()}',
          ),
        );
      } else {
        emit(TransactionError('Gagal menambah transaksi: ${e.toString()}'));
      }
    }
  }

  Future<void> _onUpdateTransaction(
    UpdateTransactionEvent event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.updateTransaction(event.transaction);
      if (state is TransactionLoaded) {
        emit(
          TransactionOperationSuccess(
            state as TransactionLoaded,
            'Transaksi berhasil diupdate',
          ),
        );
      }
    } catch (e) {
      if (state is TransactionLoaded) {
        emit(
          TransactionOperationFailure(
            state as TransactionLoaded,
            'Gagal mengupdate transaksi: ${e.toString()}',
          ),
        );
      } else {
        emit(TransactionError('Gagal mengupdate transaksi: ${e.toString()}'));
      }
    }
  }

  Future<void> _onDeleteTransaction(
    DeleteTransactionEvent event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.deleteTransaction(event.id);
      if (state is TransactionLoaded) {
        emit(
          TransactionOperationSuccess(
            state as TransactionLoaded,
            'Transaksi berhasil dihapus',
          ),
        );
      }
    } catch (e) {
      if (state is TransactionLoaded) {
        emit(
          TransactionOperationFailure(
            state as TransactionLoaded,
            'Gagal menghapus transaksi: ${e.toString()}',
          ),
        );
      } else {
        emit(TransactionError('Gagal menghapus transaksi: ${e.toString()}'));
      }
    }
  }
}

class TransactionsUpdated extends TransactionEvent {
  final List<Transaction> transactions;
  const TransactionsUpdated(this.transactions);
  @override
  List<Object?> get props => [transactions];
}
