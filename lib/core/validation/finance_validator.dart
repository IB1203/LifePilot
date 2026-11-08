/// Central validation for finance write paths so invalid data can never enter
/// the store, regardless of entry point (UI, SMS import, CSV import, JSON load).
class FinanceValidator {
  /// Returns [amount] if it is a positive paise value; otherwise throws.
  static int requirePositivePaise(int amount, String field) {
    if (amount <= 0) {
      throw ArgumentError('$field must be greater than zero.');
    }
    return amount;
  }

  /// Rejects a payment that exceeds what is still owed (incl. accrued interest).
  static void rejectOverpayment({
    required int amountPaise,
    required int owedPaise,
    required String debtName,
  }) {
    if (owedPaise <= 0) {
      throw StateError('$debtName is already settled.');
    }
    if (amountPaise > owedPaise) {
      throw StateError(
        'That is more than the ${_money(owedPaise)} still owed on $debtName.',
      );
    }
  }

  /// Validates a decoded [BillPayment] JSON map before constructing the model.
  static void validateBillPaymentJson(Map<String, dynamic> json) {
    final amount = json['amountPaise'];
    if (amount is! int || amount <= 0) {
      throw const FormatException('Bill payment amount must be positive.');
    }
  }

  static String _money(int paise) {
    final negative = paise < 0;
    final a = paise.abs();
    final rupees = a ~/ 100;
    final cents = a % 100;
    return '${negative ? '-' : ''}₹$rupees.${cents.toString().padLeft(2, '0')}';
  }
}
