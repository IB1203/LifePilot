import '../models.dart';
import '../recurrence.dart';

/// Abstraction over bill persistence so features (Finance tabs, Dashboard,
/// Plan, Assistant) depend on an interface instead of the god store.
abstract class BillRepository {
  /// All bills.
  List<Bill> get bills;

  /// Bill by id, or null when not found.
  Bill? billById(String id);

  /// Creates a bill and notifies listeners.
  Future<Bill> addBill({
    required String name,
    required BillKind kind,
    required int amountPaise,
    required DateTime nextDueAt,
    required Recurrence recurrence,
    String category = 'Bills',
    String notes = '',
    int remindDaysBefore = 3,
  });

  /// Replaces an existing bill.
  Future<void> updateBill(Bill updated);

  /// Deletes a bill (payments and linked expenses stay).
  Future<void> deleteBill(String id);

  /// Records a confirmed payment for the bill's current due date and moves a
  /// recurring bill to its next due date. Optionally records an expense.
  Future<void> markBillPaid(
    String id, {
    int? amountPaise,
    DateTime? paidAt,
    bool recordExpense = true,
    String paymentMethod = 'Other',
  });

  /// Reverts the most recent payment, including its linked expense.
  Future<void> undoLastBillPayment(String id);
}
