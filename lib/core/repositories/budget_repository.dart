import '../models.dart';

/// Abstraction over budget persistence so features (Budgets tab, Dashboard)
/// depend on an interface instead of the god store.
abstract class BudgetRepository {
  /// All spending budgets.
  List<SpendingBudget> get budgets;

  /// Budget by category, or null when not found.
  SpendingBudget? budgetByCategory(String category);

  /// Creates or replaces a budget for [category].
  Future<void> setBudget(
    String category,
    int limitPaise, {
    BudgetPeriod period = BudgetPeriod.monthly,
    bool rollover = false,
    int alertPercent = 80,
  });

  /// Deletes a budget (expenses are not affected).
  Future<void> deleteBudget(String category);
}
