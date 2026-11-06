import 'formatters.dart';

/// What could be read from the text of a photographed receipt. Every field
/// may be missing; the user checks them before saving.
class ReceiptFields {
  const ReceiptFields(
      {this.totalPaise, this.date, this.merchant, this.gstPaise});

  final int? totalPaise;
  final DateTime? date;
  final String? merchant;

  /// GST on the bill (CGST + SGST, or IGST), when printed.
  final int? gstPaise;

  /// Nothing useful: a name alone could be any line of text.
  bool get isEmpty => totalPaise == null && date == null;
}

final _amount = RegExp(
    r'(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+\.\d{1,2}|\d+)(?![\d%])',
    caseSensitive: false);

/// Total lines, strongest first. "Sub total" and "total qty" are not totals.
final _totalLabels = [
  RegExp(
      r'grand\s*total|net\s*(?:amount|payable|total)|amount\s*payable|total\s*payable|bill\s*amount|amount\s*due|total\s*amount',
      caseSensitive: false),
  RegExp(
      r'(?<!sub[\s-]?)\btotal\b(?!\s*(?:qty|quantity|items?|savings?|discount|tax))',
      caseSensitive: false),
];

final _gstLine = RegExp(r'\b(?:cgst|sgst|igst|utgst)\b', caseSensitive: false);

final _notMerchant = RegExp(
    r'tax\s*invoice|invoice|receipt|cash\s*memo|bill\s*(?:no|of)|gstin|gst\s*no|phone|tel|mob|date|time|www\.|@|thank|welcome|order|table|cashier|^\W*$',
    caseSensitive: false);

List<int> _amountsIn(String line) => [
      for (final match in _amount.allMatches(line))
        if (parseRupeesToPaise(match.group(1)!.replaceAll(',', ''))
            case final paise?)
          paise,
    ];

/// Reads the total, date, merchant and GST from receipt text. The total is
/// the largest amount on the strongest "total" line; failing that, the
/// largest amount with paise in the text.
ReceiptFields parseReceiptText(String text, {required DateTime now}) {
  final lines = [
    for (final line in text.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  int? total;
  for (final label in _totalLabels) {
    for (var i = 0; i < lines.length && total == null; i++) {
      if (!label.hasMatch(lines[i])) continue;
      var amounts =
          _amountsIn(lines[i].substring(label.firstMatch(lines[i])!.end));
      // OCR often puts the amount on the next line.
      if (amounts.isEmpty && i + 1 < lines.length) {
        amounts = _amountsIn(lines[i + 1]);
      }
      if (amounts.isNotEmpty) total = amounts.reduce((a, b) => a > b ? a : b);
    }
    if (total != null) break;
  }
  total ??= () {
    final decimals = [
      for (final line in lines)
        for (final match in RegExp(r'\d[\d,]*\.\d{2}\b').allMatches(line))
          if (parseRupeesToPaise(match.group(0)!.replaceAll(',', ''))
              case final paise?)
            paise,
    ];
    return decimals.isEmpty ? null : decimals.reduce((a, b) => a > b ? a : b);
  }();

  int? gst;
  for (final line in lines.where(_gstLine.hasMatch)) {
    final amounts =
        _amountsIn(line.replaceAll(RegExp(r'\d+(?:\.\d+)?\s*%'), ''));
    if (amounts.isNotEmpty) gst = (gst ?? 0) + amounts.last;
  }

  String? merchant;
  for (final line in lines.take(6)) {
    final letters = RegExp(r'[A-Za-z]').allMatches(line).length;
    if (letters < 3 || _notMerchant.hasMatch(line)) continue;
    if (RegExp(r'\d{5,}').hasMatch(line)) continue;
    merchant = line.replaceAll(RegExp(r'\s+'), ' ');
    if (merchant.length > 40) merchant = merchant.substring(0, 40).trim();
    break;
  }

  return ReceiptFields(
    totalPaise: total,
    date: _receiptDate(text, now),
    merchant: merchant,
    gstPaise: gst,
  );
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// The first date on the receipt within the last year (not in the future).
DateTime? _receiptDate(String text, DateTime now) {
  DateTime? check(int year, int month, int day) {
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month) return null;
    final today = DateTime(now.year, now.month, now.day);
    if (date.isAfter(today) ||
        date.isBefore(today.subtract(const Duration(days: 366)))) {
      return null;
    }
    return date;
  }

  for (final match in RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b')
      .allMatches(text)) {
    final date =
        check(int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!));
    if (date != null) return date;
  }
  for (final match
      in RegExp(r'\b(\d{1,2})[\s\-]?([A-Za-z]{3})[a-z]*[\s\-,]*(\d{4}|\d{2})\b')
          .allMatches(text)) {
    final month = _months[match[2]!.toLowerCase()];
    if (month == null) continue;
    final date = check(int.parse(match[3]!), month, int.parse(match[1]!));
    if (date != null) return date;
  }
  for (final match
      in RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').allMatches(text)) {
    final date =
        check(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
    if (date != null) return date;
  }
  return null;
}
