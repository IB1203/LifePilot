import '../models.dart';

/// Abstraction over transaction persistence so features (Activity tab,
/// Dashboard, Insights) depend on an interface instead of the god store.
abstract class EntryRepository {
  /// All ledger entries.
  List<LedgerEntry> get entries;

  /// Entry by id, or null when not found.
  LedgerEntry? entryById(String id);

  /// Adds a transaction and notifies listeners.
  Future<LedgerEntry> addEntry({
    required EntryKind kind,
    required int amountPaise,
    required String category,
    required String title,
    required DateTime occurredAt,
    String paymentMethod = 'Other',
    String note = '',
    String merchant = '',
    String subcategory = '',
    String? billId,
    String? accountId,
    String? receiptPath,
    String? source,
  });

  /// Replaces an existing entry.
  Future<void> updateEntry(LedgerEntry updated);

  /// Deletes an entry.
  Future<void> deleteEntry(String id);

  /// Adds imported entries, skipping ones that duplicate an existing record
  /// (same kind, amount, day, and description). Returns counts.
  Future<({int added, int skipped})> importEntries(
    List<LedgerEntry> imported,
  );
}
