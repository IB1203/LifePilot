import '../local_store.dart';
import '../debts.dart';
import 'debt_repository.dart';

/// [DebtRepository] backed by [LifePilotStore]. All writes route through the
/// single source of truth and notify listeners.
class LifePilotDebtRepository implements DebtRepository {
  const LifePilotDebtRepository(this.store);

  final LifePilotStore store;

  @override
  List<Debt> get debts => store.debts;

  @override
  Debt? debtById(String id) => store.debtById(id);

  @override
  Future<Debt> addDebt({
    required String name,
    required DebtKind kind,
    required int openingPaise,
    required DateTime startDate,
    double annualRatePercent = 0,
    int emiPaise = 0,
    String counterparty = '',
  }) async {
    return store.addDebt(
      name: name,
      kind: kind,
      openingPaise: openingPaise,
      startDate: startDate,
      annualRatePercent: annualRatePercent,
      emiPaise: emiPaise,
      counterparty: counterparty,
    );
  }

  @override
  Future<void> updateDebt(Debt updated) async {
    await store.updateDebt(updated);
  }

  @override
  Future<void> deleteDebt(String id) async {
    await store.deleteDebt(id);
  }

  @override
  Future<Debt> addDebtPayment(
    String debtId, {
    required int amountPaise,
    DateTime? at,
    String note = '',
    bool recordExpense = false,
    String? accountId,
  }) async {
    return store.addDebtPayment(
      debtId,
      amountPaise: amountPaise,
      at: at,
      note: note,
      recordExpense: recordExpense,
      accountId: accountId,
    );
  }
}
