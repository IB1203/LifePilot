import '../local_store.dart';
import '../models.dart';
import 'entry_repository.dart';

/// [EntryRepository] backed by [LifePilotStore]. All writes route through the
/// single source of truth and notify listeners.
class LifePilotEntryRepository implements EntryRepository {
  const LifePilotEntryRepository(this.store);

  final LifePilotStore store;

  @override
  List<LedgerEntry> get entries => store.entries;

  @override
  LedgerEntry? entryById(String id) {
    for (final entry in store.entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  @override
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
  }) async {
    return store.addEntry(
      kind: kind,
      amountPaise: amountPaise,
      category: category,
      title: title,
      occurredAt: occurredAt,
      paymentMethod: paymentMethod,
      note: note,
      merchant: merchant,
      subcategory: subcategory,
      billId: billId,
      accountId: accountId,
      receiptPath: receiptPath,
      source: source,
    );
  }

  @override
  Future<void> updateEntry(LedgerEntry updated) async {
    await store.updateEntry(updated);
  }

  @override
  Future<void> deleteEntry(String id) async {
    await store.deleteEntry(id);
  }

  @override
  Future<({int added, int skipped})> importEntries(
    List<LedgerEntry> imported,
  ) async {
    return store.importEntries(imported);
  }
}
