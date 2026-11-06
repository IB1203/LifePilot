import 'formatters.dart';
import 'local_store.dart';
import 'models.dart';
import 'personal.dart' show suggestCategory;
import 'sms_import.dart' show ruleCategory;

/// Bank statements exported from net banking as CSV or Excel. Banks lay
/// them out differently, so columns are found by their headings rather
/// than by position. Rows become drafts the user reviews, like bank SMS.

class StatementRow {
  const StatementRow({
    required this.date,
    required this.narration,
    required this.kind,
    required this.amountPaise,
    this.balancePaise,
  });

  final DateTime date;
  final String narration;
  final EntryKind kind;
  final int amountPaise;

  /// Balance after this row, if the statement has a balance column.
  final int? balancePaise;
}

class StatementParse {
  const StatementParse(this.rows, {this.skipped = 0, this.error});

  final List<StatementRow> rows;

  /// Rows under the header that were not transactions (totals, notes).
  final int skipped;

  /// Why nothing could be read, when [rows] is empty.
  final String? error;
}

String _norm(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z/ ]'), ' ')
    .replaceAll(RegExp(r'\s*/\s*'), '/')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// First column whose heading matches one of [names], in order of
/// preference. Short names ("dr", "cr", "bal") must match a whole word.
int? _column(List<String> header, List<String> names,
    {List<String> avoid = const []}) {
  for (final name in names) {
    for (var i = 0; i < header.length; i++) {
      final cell = header[i];
      if (avoid.any(cell.contains)) continue;
      final words = cell.split(' ');
      final matches = name.length <= 3
          ? words.contains(name)
          : cell == name || cell.startsWith(name) || cell.contains(' $name');
      if (matches) return i;
    }
  }
  return null;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

DateTime? _valid(int year, int month, int day) {
  if (year < 100) year += 2000;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  return date.month == month ? date : null;
}

/// Dates as Indian banks write them: day first (31/10/2026, 31-10-26,
/// 31 Oct 2026, 31-Oct-26), ISO (2026-10-31), or an Excel day number.
DateTime? parseStatementDate(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  var match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (match != null) {
    return _valid(
        int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
  }
  match = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2}|\d{4})\b')
      .firstMatch(text);
  if (match != null) {
    return _valid(
        int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!));
  }
  match =
      RegExp(r'^(\d{1,2})[\s\-/]*([A-Za-z]{3})[a-z]*[\s\-/,]*(\d{2}|\d{4})\b')
          .firstMatch(text);
  if (match != null) {
    final month = _months[match[2]!.toLowerCase()];
    if (month == null) return null;
    return _valid(int.parse(match[3]!), month, int.parse(match[1]!));
  }
  // Excel stores dates as days since 30 Dec 1899.
  final serial = double.tryParse(text);
  if (serial != null && serial > 20000 && serial < 80000) {
    // Calendar arithmetic, so a daylight-saving change cannot shift the day.
    return DateTime(1899, 12, 30 + serial.floor());
  }
  return null;
}

/// An amount cell: "1,234.50", "₹ 1,234.50", "1234.5 Cr", "-250", "(250)".
/// Returns the signed amount in paise, or null for an empty or text cell.
int? parseStatementAmount(String value) {
  var text = value.trim().toLowerCase();
  if (text.isEmpty || text == '-' || text == '0' || text == '0.00') return null;
  var sign = 1;
  if (text.endsWith('dr')) {
    sign = -1;
    text = text.substring(0, text.length - 2);
  } else if (text.endsWith('cr')) {
    text = text.substring(0, text.length - 2);
  }
  if (text.startsWith('(') && text.endsWith(')')) {
    sign = -sign;
    text = text.substring(1, text.length - 1);
  }
  text = text.replaceAll(RegExp(r'[₹,\s]|rs\.?|inr'), '');
  if (text.startsWith('-')) {
    sign = -sign;
    text = text.substring(1);
  } else if (text.startsWith('+')) {
    text = text.substring(1);
  }
  final paise = parseRupeesToPaise(text);
  return paise == null ? null : sign * paise;
}

/// Reads a statement table (rows of cells). Finds the heading row within
/// the first 40 rows, then reads every row under it that has a date and an
/// amount.
StatementParse parseStatementTable(List<List<String>> table) {
  for (var h = 0; h < table.length && h < 40; h++) {
    final header = [for (final cell in table[h]) _norm(cell)];
    final date = _column(header,
            ['txn date', 'transaction date', 'tran date', 'date', 'value date'],
            avoid: ['value date']) ??
        _column(header, ['value date']);
    final narration = _column(header, [
      'narration',
      'description',
      'particulars',
      'transaction details',
      'transaction remarks',
      'remarks',
      'details',
    ]);
    final debit = _column(header, ['withdrawal', 'debit', 'dr amount', 'dr'],
        avoid: ['credit']);
    final credit = _column(header, ['deposit', 'credit', 'cr amount', 'cr'],
        avoid: ['debit', 'card']);
    final amount = _column(header, ['amount'],
        avoid: ['withdrawal', 'deposit', 'debit', 'credit', 'balance']);
    final type = _column(header, ['dr/cr', 'cr/dr', 'type', 'debit/credit']);
    final balance = _column(header, ['closing balance', 'balance', 'bal']);
    final hasAmounts = (debit != null && credit != null) || amount != null;
    if (date == null || narration == null || !hasAmounts) continue;

    final rows = <StatementRow>[];
    var skipped = 0;
    String cell(List<String> row, int? index) =>
        index == null || index >= row.length ? '' : row[index].trim();
    for (final row in table.skip(h + 1)) {
      if (row.every((value) => value.trim().isEmpty)) continue;
      final when = parseStatementDate(cell(row, date));
      int? signed;
      if (debit != null && credit != null) {
        final out = parseStatementAmount(cell(row, debit));
        final into = parseStatementAmount(cell(row, credit));
        if (out != null && out != 0) {
          signed = -out.abs();
        } else if (into != null && into != 0) {
          signed = into.abs();
        }
      } else {
        signed = parseStatementAmount(cell(row, amount));
        final marker = _norm(cell(row, type));
        if (signed != null && marker.isNotEmpty) {
          final out = marker.startsWith('d') || marker.contains('withdraw');
          signed = out ? -signed.abs() : signed.abs();
        }
      }
      if (when == null || signed == null || signed == 0) {
        skipped++;
        continue;
      }
      rows.add(StatementRow(
        date: when,
        narration: cell(row, narration).replaceAll(RegExp(r'\s+'), ' '),
        kind: signed < 0 ? EntryKind.expense : EntryKind.income,
        amountPaise: signed.abs(),
        balancePaise: parseStatementAmount(cell(row, balance)),
      ));
    }
    if (rows.isEmpty) {
      return StatementParse(const [],
          skipped: skipped,
          error: 'Found the columns but no transactions under them.');
    }
    return StatementParse(rows, skipped: skipped);
  }
  return const StatementParse([],
      error:
          'Could not find the Date, Description and amount columns. Export the statement as CSV or Excel from net banking and try again.');
}

// ---------------------------------------------------------------------------
// Narrations

final _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
const _noise = {
  'upi', 'neft', 'imps', 'rtgs', 'ach', 'nach', 'ecs', 'dr', 'cr', 'p2a', //
  'p2m', 'payment', 'pay', 'paid', 'to', 'from', 'by', 'trf', 'transfer',
  'inb', 'mb', 'ib', 'pos', 'ref', 'txn', 'collect', 'sent', 'received',
  'via', 'upiintent', 'na', 'null', 'ybl', 'axl', 'ibl', 'okaxis',
  'okhdfcbank', 'okicici', 'oksbi', 'paytm', 'yes bank', 'yesb', 'refund',
  'reversal', 'rev',
};

/// Words dropped inside a longer part ("POS 4567XXXX AMAZON PAY"): only
/// channel words, so names such as "Amazon Pay" stay whole.
const _wordNoise = {
  'pos', 'upi', 'neft', 'imps', 'rtgs', 'ach', 'nach', 'ecs', 'ref', 'txn', //
  'to', 'from', 'by', 'via', 'trf', 'transfer', 'dr', 'cr',
};

/// The payee or payer in a narration such as
/// `UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-430912345678-PAYMENT`,
/// `UPI/DR/430912345678/SWIGGY/YESB/swiggy@ybl/Payment` or
/// `NEFT-HDFCN52026110112345-ACME TECHNOLOGIES PVT LTD`.
String narrationParty(String narration) {
  final text = narration.trim();
  if (RegExp(r'\batm\b|\bcash wd|\bwdl\b', caseSensitive: false)
      .hasMatch(text)) {
    return 'ATM cash withdrawal';
  }
  final parts = text.split(RegExp(r'[-/|:]+')).map((part) => part.trim());
  String? vpa;
  for (final part in parts) {
    if (part.isEmpty) continue;
    if (part.contains('@')) {
      vpa ??= part;
      continue;
    }
    final lower = part.toLowerCase();
    if (_noise.contains(lower)) continue;
    if (_ifsc.hasMatch(part.toUpperCase())) continue;
    // References: anything with six or more digits.
    if (RegExp(r'\d{6,}').hasMatch(part)) continue;
    if (!RegExp(r'[A-Za-z]{2,}').hasMatch(part)) continue;
    // "POS 4567XXXX AMAZON": keep the words.
    final words = part
        .split(' ')
        .where((word) =>
            !RegExp(r'\d').hasMatch(word) &&
            !_wordNoise.contains(word.toLowerCase()))
        .join(' ')
        .trim();
    if (words.length >= 2) return words;
  }
  return vpa ?? (text.length > 40 ? '${text.substring(0, 40)}…' : text);
}

// ---------------------------------------------------------------------------
// Turning rows into drafts

String statementKey(StatementRow row) {
  var hash = 0x811c9dc5;
  for (final unit in '${row.date.toIso8601String()}|${row.kind.name}|'
          '${row.amountPaise}|${row.balancePaise}|${row.narration}'
      .codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'stmt:${hash.toRadixString(16)}';
}

class StatementImport {
  final drafts = <PendingEntry>[];

  /// Rows already in LifePilot (recorded, or waiting as drafts).
  var duplicates = 0;

  /// Rows imported before.
  var alreadyImported = 0;

  /// Keys of rows to remember, so a re-import skips them.
  final keys = <String>[];

  /// Closing balance: the last row's balance, with its date.
  ({int paise, DateTime at})? closing;

  int get creditedPaise => drafts
      .where((draft) => draft.entry.isIncome)
      .fold(0, (sum, draft) => sum + draft.entry.amountPaise);
  int get debitedPaise => drafts
      .where((draft) => !draft.entry.isIncome)
      .fold(0, (sum, draft) => sum + draft.entry.amountPaise);
}

/// Drafts for [rows] not yet in LifePilot. A recorded entry or draft of the
/// same direction and amount within two days counts as the same
/// transaction, each used once, so two equal payments are not merged.
StatementImport buildStatementImport(
    LifePilotStore store, List<StatementRow> rows,
    {String? accountId}) {
  final result = StatementImport();
  final existing = [
    ...store.entries,
    for (final draft in store.pending) draft.entry,
  ];
  final used = <int>{};
  for (final row in rows) {
    final key = statementKey(row);
    if (store.seenSms.contains(key) || result.keys.contains(key)) {
      result.alreadyImported++;
      continue;
    }
    result.keys.add(key);
    final match = () {
      for (var i = 0; i < existing.length; i++) {
        final entry = existing[i];
        if (used.contains(i) ||
            entry.kind != row.kind ||
            entry.amountPaise != row.amountPaise) {
          continue;
        }
        if (entry.occurredAt.difference(row.date).inHours.abs() <= 60) return i;
      }
      return -1;
    }();
    if (match >= 0) {
      used.add(match);
      result.duplicates++;
      continue;
    }
    final party = narrationParty(row.narration);
    final refund = row.kind == EntryKind.income &&
        RegExp(r'\b(refund|reversal|rev)\b', caseSensitive: false)
            .hasMatch(row.narration);
    final category = ruleCategory(store.categoryRules, row.narration) ??
        (refund ? 'Refunds' : null) ??
        suggestCategory(store.entries, party, kind: row.kind) ??
        'Other';
    result.drafts.add(PendingEntry(
      id: '',
      source: 'statement',
      sourceKey: key,
      createdAt: store.now(),
      sourceText: row.narration,
      balancePaise: row.balancePaise,
      entry: LedgerEntry(
        id: '',
        kind: row.kind,
        amountPaise: row.amountPaise,
        category: category,
        title: refund ? 'Refund · $party' : party,
        merchant: party,
        occurredAt: DateTime(row.date.year, row.date.month, row.date.day, 12),
        paymentMethod:
            RegExp(r'\bupi\b', caseSensitive: false).hasMatch(row.narration)
                ? 'UPI'
                : 'Bank transfer',
        accountId: accountId,
        source: 'statement',
      ),
    ));
  }
  // Statements run oldest-first or newest-first: the closing balance is on
  // the last row or the first.
  final withBalance = rows.where((row) => row.balancePaise != null).toList();
  if (withBalance.isNotEmpty) {
    final newestFirst = withBalance.first.date.isAfter(withBalance.last.date);
    final closing = newestFirst ? withBalance.first : withBalance.last;
    result.closing = (paise: closing.balancePaise!, at: closing.date);
  }
  return result;
}
