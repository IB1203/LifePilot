import '../debts.dart';

/// Abstraction over debt persistence so features (Debts tab, Dashboard,
/// Assistant) depend on an interface instead of the god store.
abstract class DebtRepository {
  /// All debts.
  List<Debt> get debts;

  /// Debt by id, or null when not found.
  Debt? debtById(String id);

  /// Creates a debt and notifies listeners.
  Future<Debt> addDebt({
    required String name,
    required DebtKind kind,
    required int openingPaise,
    required DateTime startDate,
    double annualRatePercent = 0,
    int emiPaise = 0,
    String counterparty = '',
  });

  /// Replaces an existing debt.
  Future<void> updateDebt(Debt updated);

  /// Deletes a debt.
  Future<void> deleteDebt(String id);

  /// Records a repayment. For money the user owes, it can also be recorded
  /// as an expense (category Loans). A debt paid off is marked closed.
  Future<Debt> addDebtPayment(
    String debtId, {
    required int amountPaise,
    DateTime? at,
    String note = '',
    bool recordExpense = false,
    String? accountId,
  });
}
