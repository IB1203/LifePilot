import '../local_store.dart';
import '../models.dart';
import 'budget_repository.dart';

/// [BudgetRepository] backed by [LifePilotStore]. All writes route through the
/// single source of truth and notify listeners.
class LifePilotBudgetRepository implements BudgetRepository {
  const LifePilotBudgetRepository(this.store);

  final LifePilotStore store;

  @override
  List<SpendingBudget> get budgets => store.budgets;

  @override
  SpendingBudget? budgetByCategory(String category) {
    for (final budget in store.budgets) {
      if (budget.category == category) return budget;
    }
    return null;
  }

  @override
  Future<void> setBudget(
    String category,
    int limitPaise, {
    BudgetPeriod period = BudgetPeriod.monthly,
    bool rollover = false,
    int alertPercent = 80,
  }) async {
    await store.setBudget(
      category,
      limitPaise,
      period: period,
      rollover: rollover,
      alertPercent: alertPercent,
    );
  }

  @override
  Future<void> deleteBudget(String category) async {
    await store.deleteBudget(category);
  }
}
