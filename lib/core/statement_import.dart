import 'formatters.dart';
import 'local_store.dart';
import 'models.dart';
import 'personal.dart' show suggestCategory, dedupKeyForEntry;
import 'recurring_detect.dart' show matchesRecurring;
import 'sms_import.dart' show ruleCategory;

/// Bank statements exported from net banking as CSV or Excel. Banks lay
/// them out differently, so columns are found by their headings rather
/// than by position. Rows become drafts the user reviews, like bank SMS.

/// How a statement row's direction was worked out. The order matters:
/// a bank's own marker wins, then a balance change, then wording, and
/// anything left over is flagged for the user to review.
enum StatementDirectionSource { columns, marker, balance, keywords, review }

class StatementRow {
  const StatementRow({
    required this.date,
    required this.narration,
    required this.kind,
    required this.amountPaise,
    this.balancePaise,
    this.directionSource = StatementDirectionSource.review,
    this.needsReview = false,
    this.classification = TransactionClassification.other,
    this.validationStatus = ValidationStatus.unverified,
    this.confidenceScore = 0.0,
    this.columnDirection,
    this.balanceDirection,
    this.expectedBalance,
    this.actualBalance,
    this.balanceDifference,
    this.refundLinkId,
  });

  final DateTime date;
  final String narration;
  final EntryKind kind;
  final int amountPaise;

  /// Balance after this row, if the statement has a balance column.
  final int? balancePaise;
  final StatementDirectionSource directionSource;

  /// True when no marker, balance change or wording decided the direction.
  final bool needsReview;

  /// Financial classification separate from direction.
  final TransactionClassification classification;

  /// Validation status from balance reconciliation.
  final ValidationStatus validationStatus;

  /// Confidence score from 0.0 to 1.0.
  final double confidenceScore;

  /// Direction from DR/CR columns (may be reversed).
  final EntryKind? columnDirection;

  /// Direction from balance change analysis.
  final EntryKind? balanceDirection;

  /// Expected balance after this transaction.
  final int? expectedBalance;

  /// Actual balance from the statement.
  final int? actualBalance;

  /// Difference between expected and actual balance.
  final int? balanceDifference;

  /// ID of linked refund/original transaction.
  final String? refundLinkId;

  bool get isIncome => kind == EntryKind.income;

  /// The same row with money in and money out swapped.
  StatementRow flipped() => StatementRow(
        date: date,
        narration: narration,
        kind: kind == EntryKind.expense ? EntryKind.income : EntryKind.expense,
        amountPaise: amountPaise,
        balancePaise: balancePaise,
        directionSource: directionSource,
        needsReview: false,
        classification: classification,
        validationStatus: validationStatus,
        confidenceScore: confidenceScore,
        columnDirection: columnDirection,
        balanceDirection: balanceDirection,
        expectedBalance: expectedBalance,
        actualBalance: actualBalance,
        balanceDifference: balanceDifference,
        refundLinkId: refundLinkId,
      );

  StatementRow copyWith({
    EntryKind? kind,
    StatementDirectionSource? directionSource,
    bool? needsReview,
    TransactionClassification? classification,
    ValidationStatus? validationStatus,
    double? confidenceScore,
    EntryKind? columnDirection,
    EntryKind? balanceDirection,
    int? expectedBalance,
    int? actualBalance,
    int? balanceDifference,
    String? refundLinkId,
  }) =>
      StatementRow(
        date: date,
        narration: narration,
        kind: kind ?? this.kind,
        amountPaise: amountPaise,
        balancePaise: balancePaise,
        directionSource: directionSource ?? this.directionSource,
        needsReview: needsReview ?? this.needsReview,
        classification: classification ?? this.classification,
        validationStatus: validationStatus ?? this.validationStatus,
        confidenceScore: confidenceScore ?? this.confidenceScore,
        columnDirection: columnDirection ?? this.columnDirection,
        balanceDirection: balanceDirection ?? this.balanceDirection,
        expectedBalance: expectedBalance ?? this.expectedBalance,
        actualBalance: actualBalance ?? this.actualBalance,
        balanceDifference: balanceDifference ?? this.balanceDifference,
        refundLinkId: refundLinkId ?? this.refundLinkId,
      );

  /// A card's balance usually means "amount owed", so a rising balance is a
  /// debit rather than a credit. Rows decided by a marker or by wording are
  /// already written from the cardholder's point of view and are unchanged.
  StatementRow forAccount({required bool creditCard}) {
    if (!creditCard ||
        directionSource != StatementDirectionSource.balance) {
      return this;
    }
    return copyWith(
      kind: kind == EntryKind.income ? EntryKind.expense : EntryKind.income,
    );
  }
}

class StatementParse {
  const StatementParse(this.rows,
      {this.skipped = 0, this.error, this.mapping});

  final List<StatementRow> rows;

  /// Rows under the header that were not transactions (totals, notes).
  final int skipped;

  /// Why nothing could be read, when [rows] is empty.
  final String? error;

  /// Column positions that were used, so they can be saved per bank.
  final StatementMapping? mapping;
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
  var match =
      RegExp(r'^(\d{4})[\-/.](\d{1,2})[\-/.](\d{1,2})').firstMatch(text);
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

/// How many consecutive rows of [rows], read in this order, move the
/// balance by exactly the row's amount.
int _balanceFit(List<_RawStatementRow> rows) {
  var fit = 0;
  for (var i = 1; i < rows.length; i++) {
    final before = rows[i - 1].balancePaise;
    final after = rows[i].balancePaise;
    if (before == null || after == null) continue;
    if ((after - before).abs() == rows[i].amountPaise.abs()) fit++;
  }
  return fit;
}

/// A balance cell. Unlike an amount cell, zero is a real value here: an
/// account emptied to 0.00 must still anchor the next row's balance change.
int? parseStatementBalance(String value) {
  final parsed = parseStatementAmount(value);
  if (parsed != null) return parsed;
  final digits = value
      .toLowerCase()
      .replaceAll(RegExp(r'[₹,\s()+\-]|rs\.?|inr|dr$|cr$'), '');
  return RegExp(r'^0+(?:\.0*)?$').hasMatch(digits) ? 0 : null;
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

/// Wording used only when a statement has neither a direction marker nor a
/// usable balance change. Kept narrower than SMS keywords so a payee name
/// cannot decide the direction.
final _debitWords = RegExp(
  r'\b(withdrawal|withdrawn|debit|dr|atm wdl|atm withdrawal|cash wd|'
  r'purchase|paid|payment to|sent|trf to|transfer to|to transfer|pos)\b',
  caseSensitive: false,
);
final _creditWords = RegExp(
  r'\b(deposit|deposited|credit|cr|refund|reversal|reversed|rev|'
  r'interest credit|salary|received|received from|credit from)\b',
  caseSensitive: false,
);

EntryKind? _keywordDirection(String narration) {
  final debit = _debitWords.firstMatch(narration);
  final credit = _creditWords.firstMatch(narration);
  if (debit == null && credit == null) return null;
  if (debit == null) return EntryKind.income;
  if (credit == null) return EntryKind.expense;
  return debit.start < credit.start ? EntryKind.expense : EntryKind.income;
}

/// Determines direction from a balance change: positive change = credit
/// (money in), negative change = debit (money out). For credit cards this is
/// inverted because the balance normally represents amount owed.
EntryKind? _balanceChangeKind(int change, bool creditCard) {
  if (change == 0) return null;
  final credit = creditCard ? change < 0 : change > 0;
  return credit ? EntryKind.income : EntryKind.expense;
}

class _RawStatementRow {
  _RawStatementRow({
    required this.index,
    required this.date,
    required this.narration,
    required this.amountPaise,
    this.markerKind,
    this.markerSource,
    this.balancePaise,
  });

  final int index;
  final DateTime date;
  final String narration;
  final int amountPaise;
  final EntryKind? markerKind;
  final StatementDirectionSource? markerSource;
  final int? balancePaise;

  EntryKind? kind;
  StatementDirectionSource source = StatementDirectionSource.review;
  bool needsReview = false;
  double confidenceScore = 0.0;
  ValidationStatus validationStatus = ValidationStatus.unverified;
  EntryKind? columnDirection;
  EntryKind? balanceDirection;
  int? expectedBalance;
  int? actualBalance;
  int? balanceDifference;
  String? refundLinkId;
}

/// Reads a statement table (rows of cells). Finds the heading row within
/// the first 40 rows, then reads every row under it that has a date and an
/// amount. A direction is decided in this order: the bank's own Dr/Cr marker
/// or debit/credit columns, then the change in the running balance, then
/// wording in the narration. Anything still unclear is kept and flagged for
/// review so no transaction is silently mis-signed.
StatementParse parseStatementTable(
  List<List<String>> table, {
  StatementMapping? mapping,
  bool creditCard = false,
}) {
  for (var h = 0; h < table.length && h < 40; h++) {
    final header = [for (final cell in table[h]) _norm(cell)];
    final saved = mapping != null &&
            mapping.header.length == header.length &&
            _sameHeader(mapping.header, header)
        ? mapping
        : null;
    final date = saved?.dateIndex ??
        _column(header,
                ['txn date', 'transaction date', 'tran date', 'date', 'value date'],
                avoid: ['value date']) ??
            _column(header, ['value date']);
    final narration = saved?.narrationIndex ??
        _column(header, [
          'narration',
          'description',
          'particulars',
          'transaction details',
          'transaction remarks',
          'remarks',
          'details',
        ]);
    final debit = saved?.debitIndex ??
        _column(header, ['withdrawal', 'debit', 'dr amount', 'dr'],
            avoid: ['credit']);
    final credit = saved?.creditIndex ??
        _column(header, ['deposit', 'credit', 'cr amount', 'cr'],
            avoid: ['debit', 'card']);
    final amount = saved?.amountIndex ??
        _column(header, ['amount'],
            avoid: ['withdrawal', 'deposit', 'debit', 'credit', 'balance']);
    final type = saved?.typeIndex ??
        _column(header, ['dr/cr', 'cr/dr', 'type', 'debit/credit']);
    final balance = saved?.balanceIndex ??
        _column(header, ['closing balance', 'balance', 'bal']);
    final hasAmounts = (debit != null && credit != null) || amount != null;
    if (date == null || narration == null || !hasAmounts) continue;
    final headerMapping = StatementMapping(
      bank: '',
      header: header,
      dateIndex: date,
      narrationIndex: narration,
      debitIndex: debit,
      creditIndex: credit,
      amountIndex: amount,
      typeIndex: type,
      balanceIndex: balance,
      creditCard: creditCard,
    );

    final raw = <_RawStatementRow>[];
    // Balance shown on rows without an amount, such as "Opening Balance".
    final balanceOnly = <int, int>{};
    var skipped = 0;
    String cell(List<String> row, int? index) =>
        index == null || index >= row.length ? '' : row[index].trim();
    var position = -1;
    for (final row in table.skip(h + 1)) {
      position++;
      if (row.every((value) => value.trim().isEmpty)) continue;
      final when = parseStatementDate(cell(row, date));
      if (when == null) {
        skipped++;
        continue;
      }
      int? amountPaise;
      EntryKind? markerKind;
      StatementDirectionSource? markerSource;
      if (debit != null && credit != null) {
        final out = parseStatementAmount(cell(row, debit));
        final into = parseStatementAmount(cell(row, credit));
        if (out != null && out != 0) {
          amountPaise = out.abs();
          markerKind = EntryKind.expense;
          markerSource = StatementDirectionSource.columns;
        } else if (into != null && into != 0) {
          amountPaise = into.abs();
          markerKind = EntryKind.income;
          markerSource = StatementDirectionSource.columns;
        }
      } else {
        final signed = parseStatementAmount(cell(row, amount));
        if (signed != null && signed != 0) {
          amountPaise = signed.abs();
        final marker = _norm(cell(row, type));
        if (signed < 0) {
          // Some banks write credits with a minus sign (bank liability view).
          // Trust the Dr/Cr column when it says so.
          final isCredit = marker.contains('cr') || marker.contains('credit');
          markerKind = isCredit ? EntryKind.income : EntryKind.expense;
          markerSource = StatementDirectionSource.marker;
        } else if (signed > 0 && marker.isNotEmpty) {
            final out =
                marker.startsWith('d') || marker.contains('withdraw');
            markerKind =
                out ? EntryKind.expense : EntryKind.income;
            markerSource = StatementDirectionSource.marker;
          }
        }
      }
      final rowBalance = parseStatementBalance(cell(row, balance));
      if (amountPaise == null || amountPaise == 0) {
        if (rowBalance != null) balanceOnly[position] = rowBalance;
        skipped++;
        continue;
      }
      raw.add(_RawStatementRow(
        index: position,
        date: when,
        narration: cell(row, narration).replaceAll(RegExp(r'\s+'), ' '),
        amountPaise: amountPaise,
        markerKind: markerKind,
        markerSource: markerSource,
        balancePaise: rowBalance,
      ));
    }
    if (raw.isEmpty) {
      return StatementParse(const [],
          skipped: skipped,
          error: 'Found the columns but no transactions under them.',
          mapping: headerMapping);
    }

    // Read balances in the order the statement lists them. When the file is
    // newest-first, walk it backwards; same-day transactions keep their
    // order either way.
    final oldestFirst = raw.first.date.isBefore(raw.last.date)
        ? true
        : raw.first.date.isAfter(raw.last.date)
            ? false
            // Same first and last date: the order whose balance changes
            // match the amounts is the real one.
            : _balanceFit(raw) >= _balanceFit(raw.reversed.toList());
    final chronological = oldestFirst ? raw : raw.reversed.toList();
    // Start from the opening balance printed beside the transactions, so the
    // first transaction's direction can be read from the balance change too.
    int? previousBalance;
    if (balanceOnly.isNotEmpty) {
      if (oldestFirst) {
        final before = balanceOnly.keys
            .where((index) => index < raw.first.index)
            .toList()
          ..sort();
        if (before.isNotEmpty) previousBalance = balanceOnly[before.last];
      } else {
        final after = balanceOnly.keys
            .where((index) => index > raw.last.index)
            .toList()
          ..sort();
        if (after.isNotEmpty) previousBalance = balanceOnly[after.first];
      }
    }
    for (final row in chronological) {
      final previous = previousBalance;
      final balanceKind = row.balancePaise != null && previous != null
          ? _balanceChangeKind(row.balancePaise! - previous, creditCard)
          : null;
      final columnKind = row.markerKind;
      final columnSource = row.markerSource;

      EntryKind? decidedKind;
      StatementDirectionSource decidedSource = StatementDirectionSource.review;
      double confidence;
      ValidationStatus validation;
      bool needsReviewFlag = false;

      // Balance change is the most reliable indicator of direction.
      if (balanceKind != null) {
        decidedKind = balanceKind;
        decidedSource = StatementDirectionSource.balance;
        final colAgrees = columnKind != null && columnKind == balanceKind;
        if (colAgrees) {
          confidence = 0.95;
          validation = ValidationStatus.verified;
        } else if (columnKind != null) {
          // Column says one thing, balance says another — flag for review.
          confidence = 0.30;
          validation = ValidationStatus.needsReview;
          needsReviewFlag = true;
        } else {
          confidence = 0.90;
          validation = ValidationStatus.verified;
        }
      } else if (columnKind != null) {
        decidedKind = columnKind;
        decidedSource = columnSource!;
        confidence = 0.60;
        validation = ValidationStatus.partiallyVerified;
      } else {
        final keyword = _keywordDirection(row.narration);
        if (keyword != null) {
          decidedKind = keyword;
          decidedSource = StatementDirectionSource.keywords;
          confidence = 0.40;
          validation = ValidationStatus.partiallyVerified;
        } else {
          decidedKind = EntryKind.expense;
          decidedSource = StatementDirectionSource.review;
          confidence = 0.10;
          validation = ValidationStatus.unverified;
          needsReviewFlag = true;
        }
      }

      row.kind = decidedKind;
      row.source = decidedSource;
      row.confidenceScore = confidence;
      row.validationStatus = validation;
      row.needsReview = needsReviewFlag;
      row.columnDirection = columnKind;
      row.balanceDirection = balanceKind;
      row.expectedBalance = previous != null
          ? previous + (decidedKind == EntryKind.income
              ? row.amountPaise
              : -row.amountPaise)
          : null;
      row.actualBalance = row.balancePaise;
      if (row.expectedBalance != null && row.balancePaise != null) {
        row.balanceDifference =
            row.balancePaise! - row.expectedBalance!;
      }

      if (row.balancePaise != null) previousBalance = row.balancePaise;
    }

    // Detect refunds/reversals: pairs of opposite-direction transactions with
    // matching amounts and refund-related wording.
    _detectRefunds(raw);

    final rows = [
      for (final row in raw)
        StatementRow(
          date: row.date,
          narration: row.narration,
          kind: row.kind ?? EntryKind.expense,
          amountPaise: row.amountPaise,
          balancePaise: row.balancePaise,
          directionSource: row.source,
          needsReview: row.needsReview,
          classification: _classifyTransaction(row),
          validationStatus: row.validationStatus,
          confidenceScore: row.confidenceScore,
          columnDirection: row.columnDirection,
          balanceDirection: row.balanceDirection,
          expectedBalance: row.expectedBalance,
          actualBalance: row.actualBalance,
          balanceDifference: row.balanceDifference,
          refundLinkId: row.refundLinkId,
        ),
    ];
    return StatementParse(rows, skipped: skipped, mapping: headerMapping);
  }
  return const StatementParse([],
      error:
          'Could not find the Date, Description and amount columns. Export the statement as CSV or Excel from net banking and try again.');
}

/// Detects refund/reversal pairs: opposite-direction transactions with
/// matching amounts and refund-related wording. Links them via
/// [refundLinkId] so they can be reviewed together.
void _detectRefunds(List<_RawStatementRow> rows) {
  final refundWords = RegExp(
    r'\b(refund|reversal|reversed|rev|chargeback|returned)\b',
    caseSensitive: false,
  );

  // Group row indices by rounded amount (within 50 paise tolerance).
  final byAmount = <int, List<int>>{};
  for (var i = 0; i < rows.length; i++) {
    final key = (rows[i].amountPaise ~/ 50) * 50;
    byAmount.putIfAbsent(key, () => <int>[]).add(i);
  }

  final linked = <int>{};
  for (final indices in byAmount.values) {
    if (indices.length < 2) continue;

    final incomeIdx = <int>[];
    final expenseIdx = <int>[];
    for (final i in indices) {
      if (linked.contains(i)) continue;
      if (rows[i].kind == EntryKind.income) {
        incomeIdx.add(i);
      } else {
        expenseIdx.add(i);
      }
    }

    for (final i in incomeIdx) {
      if (linked.contains(i)) continue;
      final incomeRow = rows[i];
        final isIncomeRefund = refundWords.hasMatch(incomeRow.narration);
      for (final j in expenseIdx) {
        if (linked.contains(j)) continue;
        final expenseRow = rows[j];
        final isExpenseRefund = refundWords.hasMatch(expenseRow.narration);

        // Link if either side mentions refund/reversal, or if amounts match
        // and dates are close (same day or adjacent).
        final daysDiff =
            (incomeRow.date.difference(expenseRow.date).inDays).abs();
        final isRefundPair =
            (isIncomeRefund || isExpenseRefund) && daysDiff <= 1;

        if (isRefundPair) {
          linked.add(i);
          linked.add(j);
          rows[i].refundLinkId = 'refund:${expenseRow.index}';
          rows[j].refundLinkId = 'refund:${incomeRow.index}';
          break;
        }
      }
    }
  }
}

/// Classifies a transaction based on narration keywords and direction.
TransactionClassification _classifyTransaction(_RawStatementRow row) {
  final text = row.narration.toLowerCase();
  final kind = row.kind;

  if (row.refundLinkId != null) return TransactionClassification.refund;

  if (kind == EntryKind.income) {
    if (RegExp(r'\b(salary|payroll|wages|credit from)\b').hasMatch(text)) {
      return TransactionClassification.income;
    }
    if (RegExp(r'\b(loan|borrowed|lent)\b').hasMatch(text)) {
      return TransactionClassification.loanReceived;
    }
    if (RegExp(r'\b(investment|withdraw|redeem|sell)\b').hasMatch(text)) {
      return TransactionClassification.investment;
    }
    return TransactionClassification.receivedMoney;
  }

  // expense side
  if (RegExp(r'\b(atm|cash withdrawal|cash wd|withdrawal)\b').hasMatch(text)) {
    return TransactionClassification.cashWithdrawal;
  }
  if (RegExp(r'\b(emi|loan repayment|loan pay|credit card bill)\b')
      .hasMatch(text)) {
    return TransactionClassification.debtPayment;
  }
  if (RegExp(r'\b(electricity|bill|recharge|broadband|water|gas)\b')
      .hasMatch(text)) {
    return TransactionClassification.bills;
  }
  if (RegExp(
          r'\b(amazon|flipkart|shopping|mall|store|retail|purchase)\b')
      .hasMatch(text)) {
    return TransactionClassification.shopping;
  }
  if (RegExp(
          r'\b(swiggy|zomato|restaurant|food|cafe|dominos|pizza|mcdonald)\b')
      .hasMatch(text)) {
    return TransactionClassification.food;
  }
  if (RegExp(
          r'\b(investment|sip|mutual fund|stock|groww|zerodha|deposit)\b')
      .hasMatch(text)) {
    return TransactionClassification.investment;
  }
  if (RegExp(r'\b(transfer|upi to|self|own account|neft|imps)\b')
      .hasMatch(text)) {
    return TransactionClassification.transfer;
  }

  return TransactionClassification.other;
}

bool _sameHeader(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The saved layout whose heading row appears in [table], if any. Used so a
/// bank's columns are remembered between imports.
StatementMapping? findStatementMapping(
    Iterable<StatementMapping> mappings, List<List<String>> table) {
  for (var h = 0; h < table.length && h < 40; h++) {
    final header = [for (final cell in table[h]) _norm(cell)];
    for (final mapping in mappings) {
      if (mapping.header.length == header.length &&
          _sameHeader(mapping.header, header)) {
        return mapping;
      }
    }
  }
  return null;
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

/// A recurring draft (salary, rent…) that a statement row shows was
/// actually paid or received.
typedef StatementRecurringMatch = ({
  String pendingId,
  int amountPaise,
  DateTime occurredAt,
  String narration,
  int? balancePaise,
});

class StatementImport {
  final drafts = <PendingEntry>[];

  /// Recurring drafts confirmed by a row, so the row is not drafted twice.
  final recurringMatches = <StatementRecurringMatch>[];

  /// Rows already in LifePilot (recorded, or waiting as drafts).
  var duplicates = 0;

  /// Rows imported before.
  var alreadyImported = 0;

  /// Keys of rows to remember, so a re-import skips them.
  final keys = <String>[];

  /// Rows whose direction could not be decided and should be checked.
  var needsReview = 0;

  /// Closing balance: the last row's balance, with its date.
  ({int paise, DateTime at})? closing;

  int get creditedPaise => drafts
      .where((draft) => draft.entry.isIncome)
      .fold(0, (sum, draft) => sum + draft.entry.amountPaise);
  int get debitedPaise => drafts
      .where((draft) => !draft.entry.isIncome)
      .fold(0, (sum, draft) => sum + draft.entry.amountPaise);
}

/// Whether a recorded entry and a statement narration name the same payee:
/// a word of the entry's title or merchant (3+ letters) appears in the
/// narration, or the bank reference in the entry's note does.
bool _samePayee(LedgerEntry entry, String narration) {
  final words = '${entry.title} ${entry.merchant}'
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.length >= 3)
      .toSet()
    ..removeAll(const {'upi', 'payment', 'transfer', 'imps', 'neft', 'txn'});
  final reference = RegExp(r'\d{6,}').firstMatch(entry.note)?.group(0);
  final text = narration.toLowerCase();
  if (reference != null && text.contains(reference)) return true;
  if (words.isEmpty) return false;
  final narrationWords = text.split(RegExp(r'[^a-z0-9]+')).toSet();
  return words.any(narrationWords.contains);
}

/// The type a statement draft is recorded with. Deliberately narrow: only
/// clear refunds, credit card bill payments and transfers to the user's own
/// accounts are taken out of income and spending. Anything else keeps the
/// default and counts by its direction.
TransactionClassification _draftClassification(StatementRow row,
    {required bool refund}) {
  if (refund) return TransactionClassification.refund;
  if (row.kind != EntryKind.expense) return TransactionClassification.other;
  final text = row.narration.toLowerCase();
  if (RegExp(r'\b(?:credit\s*card|cc)\s*(?:bill\s*)?(?:payment|pymt|repayment)\b|\bcard\s*bill\b')
          .hasMatch(text) ||
      RegExp(r'\b(?:self|own a/?c|own account)\b').hasMatch(text)) {
    return TransactionClassification.transfer;
  }
  return TransactionClassification.other;
}

/// Drafts for [rows] not yet in LifePilot. A recorded entry or draft of the
/// same direction and amount within two days counts as the same
/// transaction, each used once, so two equal payments are not merged.
StatementImport buildStatementImport(
    LifePilotStore store, List<StatementRow> rows,
    {String? accountId, bool creditCard = false}) {
  final result = StatementImport();
  final existing = [
    ...store.entries,
    for (final draft in store.pending) draft.entry,
  ];
  final recordedCount = store.entries.length;
  // The pending draft behind existing[i], if it is one.
  PendingEntry? draftAt(int i) =>
      i >= recordedCount ? store.pending[i - recordedCount] : null;
  bool linkedElsewhere(LedgerEntry entry) =>
      accountId != null &&
      entry.accountId != null &&
      entry.accountId != accountId;
  final used = <int>{};
  for (final original in rows) {
    final row = original.forAccount(creditCard: creditCard);
    if (row.needsReview) result.needsReview++;
    final key = statementKey(row);
    if (store.seenSms.contains(key) || result.keys.contains(key)) {
      result.alreadyImported++;
      continue;
    }
    result.keys.add(key);
    final match = () {
      final candidates = <int>[];
      for (var i = 0; i < existing.length; i++) {
        final entry = existing[i];
        if (used.contains(i) ||
            entry.kind != row.kind ||
            entry.amountPaise != row.amountPaise) {
          continue;
        }
        if (entry.occurredAt.difference(row.date).inHours.abs() > 60) {
          continue;
        }
        // Cash never appears on a bank statement, and an entry linked to
        // another account belongs to that account's statement.
        if (entry.paymentMethod == 'Cash') continue;
        if (linkedElsewhere(entry)) continue;
        candidates.add(i);
      }
      if (candidates.isNotEmpty) {
        // Prefer the entry that names the same payee; otherwise the closest
        // amount-and-date match (e.g. "Salary" against the employer's name).
        return candidates.firstWhere(
            (i) => _samePayee(existing[i], row.narration),
            orElse: () => candidates.first);
      }
      // A recurring entry (salary, rent, SIP…) drafted or recorded on its
      // due date: the bank may show it a few days off or for a slightly
      // different amount, which is still the same payment.
      final party = narrationParty(row.narration);
      final probe = LedgerEntry(
        id: '',
        kind: row.kind,
        amountPaise: row.amountPaise,
        category: '',
        title: party,
        merchant: party,
        occurredAt: row.date,
      );
      for (var i = 0; i < existing.length; i++) {
        final entry = existing[i];
        if (used.contains(i) ||
            entry.source != 'recurring' ||
            linkedElsewhere(entry)) {
          continue;
        }
        if (matchesRecurring(
          kind: entry.kind,
          amountPaise: entry.amountPaise,
          title: entry.title,
          due: entry.occurredAt,
          entry: probe,
        )) {
          return i;
        }
      }
      return -1;
    }();
    if (match >= 0) {
      used.add(match);
      result.duplicates++;
      // A recurring draft the bank has now confirmed takes the bank's
      // amount and date, as with a bank SMS.
      final draft = draftAt(match);
      if (draft != null && draft.source == 'recurring' && !draft.bankConfirmed) {
        result.recurringMatches.add((
          pendingId: draft.id,
          amountPaise: row.amountPaise,
          occurredAt: DateTime(row.date.year, row.date.month, row.date.day),
          narration: row.narration,
          balancePaise: row.balancePaise,
        ));
      }
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
    final dedupKey = dedupKeyForEntry(
      kind: row.kind,
      amountPaise: row.amountPaise,
      occurredAt: row.date,
      merchant: party,
    );
    // Skip if this transaction is already waiting as a draft from a
    // different source (e.g. SMS import) — same amount, date and merchant.
    // Within the same statement batch, exact duplicates are already handled
    // by the duplicate detection above.
    if (store.pending.any((d) => d.dedupKey == dedupKey)) {
      result.alreadyImported++;
      continue;
    }
    result.drafts.add(PendingEntry(
      id: '',
      source: 'statement',
      sourceKey: key,
      dedupKey: dedupKey,
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
        sourceType: 'statement',
        classification: _draftClassification(row, refund: refund),
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
