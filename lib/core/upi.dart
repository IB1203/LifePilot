import 'dart:math';

import 'formatters.dart';
import 'models.dart';

/// UPI payment links (`upi://pay?...`), as found in UPI QR codes, plus the
/// checks LifePilot runs before handing one to a UPI app. LifePilot never
/// moves money itself: the UPI app asks for the PIN and does the payment.

/// Largest amount accepted for a single payment. NPCI's general per-
/// transaction limit is ₹1,00,000; some merchant categories allow more, so
/// the bank or UPI app has the final say.
const upiMaxPaise = 500000 * 100;

final _vpaPattern =
    RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.\-_]{1,255}@[a-zA-Z][a-zA-Z0-9.\-]{1,63}$');

/// Returns why [value] is not a usable UPI ID, or null if it is.
String? validateVpa(String value) {
  final vpa = value.trim();
  if (vpa.isEmpty) return 'Enter the UPI ID.';
  if (!vpa.contains('@')) return 'A UPI ID looks like name@bank.';
  if (vpa.contains(' ')) return 'A UPI ID cannot contain spaces.';
  if (!_vpaPattern.hasMatch(vpa)) return 'This is not a valid UPI ID.';
  return null;
}

String normalizeVpa(String value) => value.trim().toLowerCase();

/// A payment request read from a UPI QR code or typed in.
class UpiRequest {
  const UpiRequest({
    required this.vpa,
    this.name = '',
    this.amountPaise,
    this.note = '',
    this.params = const {},
    this.fromQr = false,
  });

  final String vpa;
  final String name;

  /// Fixed by the QR code when set; the user cannot change it.
  final int? amountPaise;
  final String note;

  /// Every parameter from the original link, in order, so merchant fields
  /// (reference, merchant code, signature) reach the UPI app unchanged.
  final Map<String, String> params;
  final bool fromQr;

  /// Merchant QR codes carry a merchant category code.
  bool get isMerchant => (params['mc'] ?? '').isNotEmpty;
  bool get isSigned => (params['sign'] ?? '').isNotEmpty;
  bool get amountFixed => fromQr && amountPaise != null;
  String get displayName => name.trim().isEmpty ? vpa : name.trim();

  /// Builds the link for the UPI app. [amountPaise] is used only when the
  /// request has no fixed amount. Spaces are sent as %20, which every UPI
  /// app reads correctly (some show "+" literally).
  String toLink({int? amountPaise, String? note}) {
    final values = <String, String>{...params};
    values['pa'] = vpa;
    if (name.trim().isNotEmpty) values['pn'] = name.trim();
    final amount = this.amountPaise ?? amountPaise;
    if (amount != null) values['am'] = paiseToInput(amount);
    values['cu'] = 'INR';
    final text = note ?? this.note;
    values.remove('tn');
    if (text.trim().isNotEmpty) values['tn'] = text.trim();
    String encode(String value) =>
        Uri.encodeComponent(value).replaceAll('%40', '@');
    return 'upi://pay?${values.entries.map((e) => '${e.key}=${encode(e.value)}').join('&')}';
  }

  /// Reads a scanned or pasted UPI link. Throws [FormatException] with a
  /// message for the user when it is not a payment request LifePilot can
  /// pass on safely.
  static UpiRequest parse(String text) {
    final raw = text.trim();
    final lower = raw.toLowerCase();
    if (!lower.startsWith('upi://')) {
      throw const FormatException('This QR code is not a UPI payment code.');
    }
    if (!lower.startsWith('upi://pay')) {
      // upi://mandate and upi://collect set up autopay or pull money.
      throw const FormatException(
          'This QR code sets up a mandate or collect request, not a one-time payment. LifePilot only passes on payments.');
    }
    final query = raw.contains('?') ? raw.substring(raw.indexOf('?') + 1) : '';
    final params = <String, String>{};
    for (final part in query.split('&')) {
      if (part.isEmpty) continue;
      final split = part.indexOf('=');
      final key = (split < 0 ? part : part.substring(0, split)).trim();
      final value = split < 0 ? '' : part.substring(split + 1);
      String decoded;
      try {
        decoded = Uri.decodeQueryComponent(value);
      } on ArgumentError {
        decoded = value;
      }
      if (key.isEmpty) continue;
      // Keys are case-insensitive in practice; keep the standard spelling.
      final standard = key.toLowerCase();
      if (params.containsKey(standard)) {
        throw const FormatException(
            'This QR code repeats a payment field, which is not allowed.');
      }
      params[standard] = decoded.trim();
    }
    final vpa = params['pa'] ?? '';
    final problem = validateVpa(vpa);
    if (problem != null) {
      throw FormatException(vpa.isEmpty
          ? 'This QR code has no UPI ID to pay.'
          : 'The UPI ID in this QR code is not valid.');
    }
    final currency = params['cu'];
    if (currency != null &&
        currency.isNotEmpty &&
        currency.toUpperCase() != 'INR') {
      throw const FormatException(
          'Only payments in rupees (INR) are supported.');
    }
    int? amount;
    final am = params['am'];
    if (am != null && am.isNotEmpty) {
      amount = parseRupeesToPaise(am);
      if (amount == null || amount <= 0) {
        throw const FormatException('The amount in this QR code is not valid.');
      }
      if (amount > upiMaxPaise) {
        throw const FormatException('The amount in this QR code is too large.');
      }
    }
    return UpiRequest(
      vpa: vpa.trim(),
      name: params['pn'] ?? '',
      amountPaise: amount,
      note: params['tn'] ?? '',
      params: params,
      fromQr: true,
    );
  }
}

enum UpiRisk { info, caution, danger }

class UpiWarning {
  const UpiWarning(this.risk, this.message);

  final UpiRisk risk;
  final String message;

  @override
  String toString() => '${risk.name}: $message';
}

/// Checks a payment against saved payees and the user's large-payment
/// limit. Warnings are advice; the user decides.
List<UpiWarning> upiWarnings(
  UpiRequest request, {
  required int? amountPaise,
  required List<Payee> payees,
  required int largePaymentPaise,
}) {
  final warnings = <UpiWarning>[];
  final vpa = normalizeVpa(request.vpa);
  final known = payees.where((payee) => normalizeVpa(payee.vpa) == vpa);
  if (known.isEmpty) {
    final name = request.name.trim().toLowerCase();
    for (final payee in payees) {
      final savedVpa = normalizeVpa(payee.vpa);
      if (name.isNotEmpty && payee.name.trim().toLowerCase() == name) {
        warnings.add(UpiWarning(UpiRisk.danger,
            'You saved "${payee.name}" with a different UPI ID (${payee.vpa}). Scammers often reuse a familiar name.'));
      } else if (_lookAlike(vpa, savedVpa)) {
        warnings.add(UpiWarning(UpiRisk.danger,
            'This UPI ID looks very similar to ${payee.vpa} (${payee.name}), but is not the same.'));
      }
    }
    warnings.add(const UpiWarning(UpiRisk.caution,
        'First payment to this UPI ID. Check the name your UPI app shows before entering your PIN.'));
  }
  if (amountPaise != null && amountPaise >= largePaymentPaise) {
    warnings.add(UpiWarning(UpiRisk.caution,
        'Large payment: ${formatMoney(amountPaise)}. Double-check the amount.'));
  }
  if (request.amountFixed) {
    warnings.add(const UpiWarning(UpiRisk.info,
        'The amount was set by the QR code and cannot be changed here.'));
  }
  return warnings;
}

/// Two different IDs that differ by a character or two, or only in
/// characters that look alike (0/o, 1/l/i, rn/m).
bool _lookAlike(String a, String b) {
  if (a == b) return false;
  String skeleton(String value) => value
      .replaceAll('rn', 'm')
      .replaceAll('0', 'o')
      .replaceAll(RegExp('[1il|]'), 'l')
      .replaceAll(RegExp(r'[.\-_]'), '');
  if (skeleton(a) == skeleton(b)) return true;
  final longest = max(a.length, b.length);
  return longest >= 6 && editDistance(a, b) <= (longest >= 12 ? 2 : 1);
}

int editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] =
          min(min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost);
    }
    previous = current;
  }
  return previous[b.length];
}

/// What the UPI app said when it returned to LifePilot. This is the app's
/// own report and is not bank-verified.
enum UpiReported { success, submitted, failure, cancelled, unknown }

class UpiResponse {
  const UpiResponse({
    required this.status,
    this.transactionId = '',
    this.approvalRef = '',
    this.responseCode = '',
  });

  final UpiReported status;
  final String transactionId;
  final String approvalRef;
  final String responseCode;

  /// The reference to quote to a bank: approval number, else transaction id.
  String get reference => approvalRef.isNotEmpty ? approvalRef : transactionId;

  /// Parses the `response` text a UPI app returns, such as
  /// `txnId=AB12&responseCode=00&Status=SUCCESS&txnRef=LP1`. [resultOk] is
  /// whether Android reported RESULT_OK.
  static UpiResponse parse(String? response, {required bool resultOk}) {
    if (response == null || response.trim().isEmpty) {
      return UpiResponse(
          status: resultOk ? UpiReported.unknown : UpiReported.cancelled);
    }
    final values = <String, String>{};
    for (final part in response.split('&')) {
      final split = part.indexOf('=');
      if (split <= 0) continue;
      String value = part.substring(split + 1);
      try {
        value = Uri.decodeQueryComponent(value);
      } on ArgumentError {
        // Keep the raw text.
      }
      values[part.substring(0, split).trim().toLowerCase()] = value.trim();
    }
    final status = switch ((values['status'] ?? '').toUpperCase()) {
      'SUCCESS' => UpiReported.success,
      'SUBMITTED' || 'PENDING' => UpiReported.submitted,
      'FAILURE' || 'FAILED' => UpiReported.failure,
      _ => UpiReported.unknown,
    };
    return UpiResponse(
      status: status,
      transactionId: values['txnid'] ?? '',
      approvalRef: values['approvalrefno'] ?? '',
      responseCode: values['responsecode'] ?? '',
    );
  }
}
