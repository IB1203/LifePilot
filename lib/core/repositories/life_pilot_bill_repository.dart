import '../local_store.dart';
import '../models.dart';
import '../recurrence.dart';
import 'bill_repository.dart';

/// [BillRepository] backed by [LifePilotStore]. All writes route through the
/// single source of truth and notify listeners.
class LifePilotBillRepository implements BillRepository {
  const LifePilotBillRepository(this.store);

  final LifePilotStore store;

  @override
  List<Bill> get bills => store.bills;

  @override
  Bill? billById(String id) => store.billById(id);

  @override
  Future<Bill> addBill({
    required String name,
    required BillKind kind,
    required int amountPaise,
    required DateTime nextDueAt,
    required Recurrence recurrence,
    String category = 'Bills',
    String notes = '',
    int remindDaysBefore = 3,
  }) async {
    return store.addBill(
      name: name,
      kind: kind,
      amountPaise: amountPaise,
      nextDueAt: nextDueAt,
      recurrence: recurrence,
      category: category,
      notes: notes,
      remindDaysBefore: remindDaysBefore,
    );
  }

  @override
  Future<void> updateBill(Bill updated) async {
    await store.updateBill(updated);
  }

  @override
  Future<void> deleteBill(String id) async {
    await store.deleteBill(id);
  }

  @override
  Future<void> markBillPaid(
    String id, {
    int? amountPaise,
    DateTime? paidAt,
    bool recordExpense = true,
    String paymentMethod = 'Other',
  }) async {
    await store.markBillPaid(
      id,
      amountPaise: amountPaise,
      paidAt: paidAt,
      recordExpense: recordExpense,
      paymentMethod: paymentMethod,
    );
  }

  @override
  Future<void> undoLastBillPayment(String id) async {
    await store.undoLastBillPayment(id);
  }
}
