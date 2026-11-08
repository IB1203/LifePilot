import '../investments.dart';

/// Abstraction over investment persistence so features (Investments tab,
/// Dashboard) depend on an interface instead of the god store.
abstract class InvestmentRepository {
  /// All investments.
  List<Investment> get investments;

  /// Investment by id, or null when not found.
  Investment? investmentById(String id);

  /// Adds an investment. [investedPaise] (for an FD, the principal) is
  /// recorded as money put in on [startDate].
  Future<Investment> addInvestment({
    required String name,
    required InvestmentKind kind,
    required DateTime startDate,
    int investedPaise = 0,
    int? valuePaise,
    double annualRatePercent = 0,
    DateTime? maturityDate,
    int installmentPaise = 0,
    int sipPaise = 0,
    int? sipDay,
  });

  /// Replaces an existing investment.
  Future<void> updateInvestment(Investment updated);

  /// Deletes an investment.
  Future<void> deleteInvestment(String id);

  /// Money put in (positive) or taken out (negative).
  Future<void> addInvestmentFlow(
    String id,
    int amountPaise, {
    DateTime? at,
  });

  /// Sets the current value of an investment.
  Future<void> setInvestmentValue(String id, int valuePaise);
}
