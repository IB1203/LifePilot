import '../local_store.dart';
import '../investments.dart';
import 'investment_repository.dart';

/// [InvestmentRepository] backed by [LifePilotStore]. All writes route through
/// the single source of truth and notify listeners.
class LifePilotInvestmentRepository implements InvestmentRepository {
  const LifePilotInvestmentRepository(this.store);

  final LifePilotStore store;

  @override
  List<Investment> get investments => store.investments;

  @override
  Investment? investmentById(String id) {
    for (final investment in store.investments) {
      if (investment.id == id) return investment;
    }
    return null;
  }

  @override
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
  }) async {
    return store.addInvestment(
      name: name,
      kind: kind,
      startDate: startDate,
      investedPaise: investedPaise,
      valuePaise: valuePaise,
      annualRatePercent: annualRatePercent,
      maturityDate: maturityDate,
      installmentPaise: installmentPaise,
      sipPaise: sipPaise,
      sipDay: sipDay,
    );
  }

  @override
  Future<void> updateInvestment(Investment updated) async {
    await store.updateInvestment(updated);
  }

  @override
  Future<void> deleteInvestment(String id) async {
    await store.deleteInvestment(id);
  }

  @override
  Future<void> addInvestmentFlow(
    String id,
    int amountPaise, {
    DateTime? at,
  }) async {
    await store.addInvestmentFlow(id, amountPaise, at: at);
  }

  @override
  Future<void> setInvestmentValue(String id, int valuePaise) async {
    await store.setInvestmentValue(id, valuePaise);
  }
}
