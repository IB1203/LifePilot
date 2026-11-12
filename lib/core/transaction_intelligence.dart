import 'formatters.dart';
import 'local_store.dart';
import 'personal.dart' show accountBalance;
import 'statement_import.dart';

// ---------------------------------------------------------------------------
// Bank account identification

/// Extracted identity of a bank from a statement header.
class BankIdentification {
  const BankIdentification({
    this.bankName,
    this.accountHolder,
    this.accountNumberMasked,
    this.accountNumberHash,
    this.ifscCode,
    this.accountType,
    this.openingBalance,
    this.closingBalance,
    this.statementPeriodStart,
    this.statementPeriodEnd,
    this.currency = 'INR',
    this.confidence = 0.0,
    this.matchMethod,
  });

  final String? bankName;
  final String? accountHolder;
  final String? accountNumberMasked;
  final String? accountNumberHash;
  final String? ifscCode;
  final String? accountType;
  final int? openingBalance;
  final int? closingBalance;
  final DateTime? statementPeriodStart;
  final DateTime? statementPeriodEnd;
  final String currency;

  /// Confidence from 0.0 to 1.0 that this identification is correct.
  final double confidence;

  /// How the identification was made: header, ifsc, account, fuzzy.
  final String? matchMethod;

  bool get isConfident => confidence >= 0.6;
}

/// Identifies a bank from statement header text using heuristics.
BankIdentification identifyBankFromStatement(
  String headerText, {
  String? ifscHint,
  String? accountNumberHint,
}) {
  final text = headerText.toLowerCase();

  // Known bank name patterns
  final knownBanks = {
    'bank of baroda': 'Bank of Baroda',
    'baroda': 'Bank of Baroda',
    'sbi': 'State Bank of India',
    'state bank of india': 'State Bank of India',
    'state bank': 'State Bank of India',
    'hdfc': 'HDFC Bank',
    'hdfc bank': 'HDFC Bank',
    'icici': 'ICICI Bank',
    'icici bank': 'ICICI Bank',
    'axis': 'Axis Bank',
    'axis bank': 'Axis Bank',
    'kotak': 'Kotak Mahindra Bank',
    'kotak mahindra': 'Kotak Mahindra Bank',
    'idfc': 'IDFC First Bank',
    'idfc first': 'IDFC First Bank',
    'yes bank': 'Yes Bank',
    'yesbank': 'Yes Bank',
    'indusind': 'IndusInd Bank',
    'indusind bank': 'IndusInd Bank',
    'punjab national': 'Punjab National Bank',
    'pnb': 'Punjab National Bank',
    'canara': 'Canara Bank',
    'canara bank': 'Canara Bank',
    'union bank': 'Union Bank of India',
    'unionbank': 'Union Bank of India',
    'central bank': 'Central Bank of India',
    'bank of india': 'Bank of India',
    'boi': 'Bank of India',
    'uco': 'UCO Bank',
    'uco bank': 'UCO Bank',
    'indian bank': 'Indian Bank',
    'indian overseas': 'Indian Overseas Bank',
    'iob': 'Indian Overseas Bank',
    'bank of maharashtra': 'Bank of Maharashtra',
    'bom': 'Bank of Maharashtra',
    'paytm': 'Paytm Payments Bank',
    'airtel': 'Airtel Payments Bank',
    'jio': 'Jio Payments Bank',
    'federal': 'Federal Bank',
    'federal bank': 'Federal Bank',
    'rbl': 'RBL Bank',
    'rbl bank': 'RBL Bank',
    'dbs': 'DBS Bank',
    'dbs bank': 'DBS Bank',
    'standard chartered': 'Standard Chartered',
    'scb': 'Standard Chartered',
    'citibank': 'Citibank',
    'citi': 'Citibank',
    'hsbc': 'HSBC',
    'hsbc bank': 'HSBC',
  };

  String? detectedBank;
  double confidence = 0.0;

  for (final entry in knownBanks.entries) {
    if (text.contains(entry.key)) {
      detectedBank = entry.value;
      confidence = 0.8;
      // Longer match = higher confidence
      if (entry.key.length > 8) confidence = 0.9;
      break;
    }
  }

  // IFSC code pattern: 4 char bank code + 0 + 6 char branch
  String? ifscCode;
  final ifscMatch = RegExp(r'[A-Z]{4}0[A-Z0-9]{6}').firstMatch(headerText);
  if (ifscMatch != null) {
    ifscCode = ifscMatch.group(0);
    if (detectedBank == null) {
      confidence = 0.5;
    } else {
      confidence = 0.95;
    }
  } else if (ifscHint != null) {
    ifscCode = ifscHint;
    if (detectedBank == null) {
      confidence = 0.5;
    } else {
      confidence = 0.95;
    }
  }

  // Account number patterns
  String? accountNumberMasked;
  String? accountNumberHash;
  final accMatch = RegExp(
    r'(?:a/c|account|acct|a/c no|account no|account number)[:\s]*([\dxX*]{4,}[\dxX*]*)',
    caseSensitive: false,
  ).firstMatch(headerText);
  if (accMatch != null) {
    final raw = accMatch.group(1)!;
    final masked = raw.replaceAllMapped(
      RegExp(r'[\dxX]{4}[\dxX*]*'),
      (m) =>
          'XXXX ${m.group(0)!.substring(m.group(0)!.length - 4)}',
    );
    accountNumberMasked = masked;
    accountNumberHash = _hashString(raw);
  } else if (accountNumberHint != null) {
    accountNumberMasked = accountNumberHint.length > 4
        ? 'XXXX ${accountNumberHint.substring(accountNumberHint.length - 4)}'
        : accountNumberHint;
    accountNumberHash = _hashString(accountNumberHint);
  }

  // Account type hints
  String? accountType;
  if (RegExp(r'\bsavings\b', caseSensitive: false).hasMatch(headerText)) {
    accountType = 'savings';
  } else if (RegExp(r'\bcurrent\b', caseSensitive: false)
      .hasMatch(headerText)) {
    accountType = 'current';
  } else if (RegExp(r'\bsalary\b', caseSensitive: false).hasMatch(headerText)) {
    accountType = 'salary';
  } else if (RegExp(r'\bcredit card\b', caseSensitive: false)
      .hasMatch(headerText)) {
    accountType = 'credit_card';
  }

  // Balance extraction
  int? openingBalance;
  int? closingBalance;
  final obMatch = RegExp(
    r'(?:opening|opening balance|opened bal|ob)[:\s]*₹?\s*([\d,]+\.?\d*)',
    caseSensitive: false,
  ).firstMatch(headerText);
  if (obMatch != null) {
    final val = parseRupeesToPaise(obMatch.group(1)!);
    if (val != null) openingBalance = val;
  }
  final cbMatch = RegExp(
    r'(?:closing|closing balance|closing bal|cb|balance at|balance as on)[:\s]*₹?\s*([\d,]+\.?\d*)',
    caseSensitive: false,
  ).firstMatch(headerText);
  if (cbMatch != null) {
    final val = parseRupeesToPaise(cbMatch.group(1)!);
    if (val != null) closingBalance = val;
  }

  // Date period extraction
  DateTime? periodStart;
  DateTime? periodEnd;
  final periodMatch = RegExp(
    r'(?:period|from|statement period)[:\s]*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\s*(?:to|-)\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
    caseSensitive: false,
  ).firstMatch(headerText);
  if (periodMatch != null) {
    periodStart = parseStatementDate(periodMatch.group(1)!);
    periodEnd = parseStatementDate(periodMatch.group(2)!);
  }

  return BankIdentification(
    bankName: detectedBank,
    accountHolder: null, // Not typically in header
    accountNumberMasked: accountNumberMasked,
    accountNumberHash: accountNumberHash,
    ifscCode: ifscCode,
    accountType: accountType,
    openingBalance: openingBalance,
    closingBalance: closingBalance,
    statementPeriodStart: periodStart,
    statementPeriodEnd: periodEnd,
    confidence: confidence,
    matchMethod: ifscCode != null ? 'ifsc' : detectedBank != null ? 'header' : 'fuzzy',
  );
}

String _hashString(String input) {
  var hash = 0;
  for (var i = 0; i < input.length; i++) {
    hash = ((hash << 5) - hash + input.codeUnitAt(i)) & 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Result of balance reconciliation.
class BalanceReconciliation {
  const BalanceReconciliation({
    required this.accountId,
    required this.statementBalance,
    required this.calculatedBalance,
    required this.difference,
    required this.status,
    this.at,
  });

  final String accountId;
  final int statementBalance;
  final int calculatedBalance;
  final int difference;
  final String status;
  final DateTime? at;

  bool get isReconciled => status == 'reconciled';
}

/// Synchronizes all account balances based on current entries and
/// bank-reported balances. Returns per-account reconciliation results.
List<BalanceReconciliation> synchronizeAllBalances(
  LifePilotStore store, {
  DateTime? asOf,
}) {
  final now = asOf ?? store.now();
  final results = <BalanceReconciliation>[];

  for (final account in store.accounts) {
    // Same rule as the Accounts tab: entries plus transfers in and out.
    final calculated = accountBalance(
      account,
      store.entries.where((e) => !e.occurredAt.isAfter(now)),
      store.transfers.where((t) => !t.at.isAfter(now)),
    );

    final reported = account.currentBalancePaise;
    final difference = reported != null ? reported - calculated : 0;
    final status = difference.abs() <= 100 ? 'reconciled' : 'mismatched';

    results.add(BalanceReconciliation(
      accountId: account.id,
      statementBalance: reported ?? calculated,
      calculatedBalance: calculated,
      difference: difference,
      status: status,
      at: now,
    ));
  }

  return results;
}
