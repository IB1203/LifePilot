import '../local_store.dart';
import '../models.dart';
import 'account_repository.dart';

/// [AccountRepository] backed by [LifePilotStore]. All writes route through
/// the single source of truth and notify listeners.
class LifePilotAccountRepository implements AccountRepository {
  const LifePilotAccountRepository(this.store);

  final LifePilotStore store;

  @override
  List<Account> get accounts => store.accounts;

  @override
  Account? accountById(String id) => store.accountById(id);

  @override
  Future<Account> addAccount(String name, AccountKind kind,
      {int openingBalancePaise = 0}) async {
    return store.addAccount(name, kind, openingBalancePaise: openingBalancePaise);
  }

  @override
  Future<void> updateAccount(Account updated) async {
    await store.updateAccount(updated);
  }

  @override
  Future<void> deleteAccount(String id) async {
    await store.deleteAccount(id);
  }
}
