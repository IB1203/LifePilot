import '../models.dart';

/// Abstraction over account persistence so features (Accounts page, Money
/// Glance, entry forms) depend on an interface instead of the god store.
abstract class AccountRepository {
  /// All accounts, archived included.
  List<Account> get accounts;

  /// Account by id, or null when not found.
  Account? accountById(String id);

  /// Creates an account and notifies listeners. [openingBalancePaise] seeds
  /// the running balance.
  Future<Account> addAccount(String name, AccountKind kind,
      {int openingBalancePaise = 0});

  /// Replaces an existing account.
  Future<void> updateAccount(Account updated);

  /// Deletes an account. Entries keep their amounts but lose the link, and
  /// transfers involving it are removed.
  Future<void> deleteAccount(String id);
}
