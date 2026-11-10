import 'dart:math';

import 'bank_sms.dart';
import 'formatters.dart';
import 'local_store.dart';
import 'models.dart';
import 'personal.dart' show suggestCategory;
import 'statement_import.dart';
import 'sms_import.dart';

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

/// Result of matching an identified bank to an existing account.
class AccountMatchResult {
  const AccountMatchResult({
    required this.account,
    required this.matchType,
    required this.confidence,
    this.isNew = false,
  });

  final Account account;
  /// exact_number, ifsc_number, masked_number, holder_bank, fuzzy, none.
  final String matchType;
  final double confidence;
  final bool isNew;
}

/// Matches an [identification] against existing accounts.
AccountMatchResult? matchAccountToIdentification(
  LifePilotStore store,
  BankIdentification identification, {
  bool createIfMissing = true,
}) {
  // 1. Exact account number hash
  if (identification.accountNumberHash != null &&
      identification.accountNumberHash!.isNotEmpty) {
    final existing = store.accounts.firstWhere(
      (a) => a.accountNumberHash == identification.accountNumberHash,
      orElse: () => const Account(
        id: '',
        name: '',
        kind: AccountKind.other,
      ),
    );
    if (existing.id.isNotEmpty) {
      return AccountMatchResult(
        account: existing,
        matchType: 'exact_number',
        confidence: 1.0,
      );
    }
  }

  // 2. IFSC + masked account number
  if (identification.ifscCode != null &&
      identification.accountNumberMasked != null &&
      identification.ifscCode!.isNotEmpty &&
      identification.accountNumberMasked!.isNotEmpty) {
    final existing = store.accounts.firstWhere(
      (a) => a.ifscCode == identification.ifscCode &&
          a.accountNumberMasked == identification.accountNumberMasked,
      orElse: () => const Account(
        id: '',
        name: '',
        kind: AccountKind.other,
      ),
    );
    if (existing.id.isNotEmpty) {
      return AccountMatchResult(
        account: existing,
        matchType: 'ifsc_number',
        confidence: 0.95,
      );
    }
  }

  // 3. Masked account number + bank name
  if (identification.accountNumberMasked != null &&
      identification.bankName != null &&
      identification.accountNumberMasked!.isNotEmpty &&
      identification.bankName!.isNotEmpty) {
    final existing = store.accounts.firstWhere(
      (a) => a.accountNumberMasked == identification.accountNumberMasked &&
          a.bankName?.toLowerCase() == identification.bankName!.toLowerCase(),
      orElse: () => const Account(
        id: '',
        name: '',
        kind: AccountKind.other,
      ),
    );
    if (existing.id.isNotEmpty) {
      return AccountMatchResult(
        account: existing,
        matchType: 'masked_number',
        confidence: 0.85,
      );
    }
  }

  // 4. Account holder + bank name
  if (identification.accountHolder != null &&
      identification.bankName != null &&
      identification.accountHolder!.isNotEmpty &&
      identification.bankName!.isNotEmpty) {
    final existing = store.accounts.firstWhere(
      (a) => a.accountHolder?.toLowerCase() ==
              identification.accountHolder!.toLowerCase() &&
          a.bankName?.toLowerCase() == identification.bankName!.toLowerCase(),
      orElse: () => const Account(
        id: '',
        name: '',
        kind: AccountKind.other,
      ),
    );
    if (existing.id.isNotEmpty) {
      return AccountMatchResult(
        account: existing,
        matchType: 'holder_bank',
        confidence: 0.7,
      );
    }
  }

  // 5. Bank name only (fuzzy)
  if (identification.bankName != null &&
      identification.bankName!.isNotEmpty &&
      identification.confidence >= 0.5) {
    final existing = store.accounts.firstWhere(
      (a) => a.bankName?.toLowerCase() ==
          identification.bankName!.toLowerCase(),
      orElse: () => const Account(
        id: '',
        name: '',
        kind: AccountKind.other,
      ),
    );
    if (existing.id.isNotEmpty) {
      return AccountMatchResult(
        account: existing,
        matchType: 'fuzzy',
        confidence: 0.4,
      );
    }
  }

  // 6. Create new account if allowed
  if (createIfMissing && identification.isConfident) {
    final newAccount = Account(
      id: _newId(),
      name: identification.accountHolder != null &&
              identification.accountHolder!.isNotEmpty
          ? '${identification.bankName ?? 'Bank'} - ${identification.accountHolder}'
          : identification.bankName ?? 'Bank Account',
      kind: identification.accountType?.toLowerCase() == 'credit' ||
              identification.accountType?.toLowerCase() == 'card'
          ? AccountKind.card
          : AccountKind.bank,
      openingBalancePaise: identification.openingBalance ?? 0,
      bankName: identification.bankName,
      accountHolder: identification.accountHolder,
      accountNumberMasked: identification.accountNumberMasked,
      accountNumberHash: identification.accountNumberHash,
      ifscCode: identification.ifscCode,
      accountType: identification.accountType,
      currentBalancePaise: identification.closingBalance,
      availableBalancePaise: identification.closingBalance,
      lastStatementBalancePaise: identification.closingBalance,
      lastUpdatedAt: identification.statementPeriodEnd,
      verificationStatus: identification.confidence >= 0.7
          ? 'matched'
          : 'unidentified',
    );
    return AccountMatchResult(
      account: newAccount,
      matchType: 'none',
      confidence: identification.confidence,
      isNew: true,
    );
  }

  return null;
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

String _newId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final random = Random.secure().nextInt(100000);
  return '${now}_$random'.toString();
}

// ---------------------------------------------------------------------------
// Centralized transaction import

/// Result of importing a batch of SMS messages and/or statement rows.
class ImportResult {
  const ImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.duplicates,
    required this.unrecognized,
    required this.accountMatches,
    required this.warnings,
  });

  final int created;
  final int updated;
  final int skipped;
  final int duplicates;
  final int unrecognized;
  final List<AccountMatchResult> accountMatches;
  final List<String> warnings;
}

/// Imports SMS messages through the centralized engine, deduplicating against
/// existing entries and statement-imported transactions.
Future<ImportResult> importSmsBatch(
  LifePilotStore store,
  Iterable<SmsMessage> messages, {
  bool autoCreateAccounts = true,
}) async {
  final created = <LedgerEntry>[];
  final updated = <LedgerEntry>[];
  int skipped = 0;
  int duplicates = 0;
  int unrecognized = 0;
  final warnings = <String>[];
  final accountMatches = <AccountMatchResult>[];

  for (final message in messages) {
    final key = smsFingerprint(message.address, message.body, message.date);
    if (store.seenSms.contains(key)) {
      duplicates++;
      continue;
    }

    final sender =
        classifySender(message.address,
            extraSenders: store.settings.extraSmsSenders);
    final reason = scamReason(sender, message.body);
    if (reason != null) {
      skipped++;
      continue;
    }
    if (sender.kind == SenderKind.phoneNumber) {
      skipped++;
      continue;
    }

    final parsed = parseBankSms(
      message.body,
      received: message.date,
      senderHeader: sender.header,
    );
    if (parsed == null) {
      if (looksLikeTransactionSms(message.body, sender)) {
        unrecognized++;
      }
      continue;
    }

    // Try to match/update existing transaction by reference or fingerprint
    final entry = _buildEntryFromSms(store, parsed, message,
        sourceType: 'sms');
    final existing = _findMatchingTransaction(store, entry,
        sourceReference: parsed.reference);
    if (existing != null) {
      // Update existing record to add SMS source
      final merged = existing.copyWith(
        sourceType: 'sms',
        sourceReference:
            parsed.reference ?? existing.sourceReference,
        validationStatus: parsed.kind == existing.kind
            ? ValidationStatus.verified
            : existing.validationStatus,
        confidenceScore: (existing.confidenceScore + 0.8) / 2,
      );
      store.entries[store.entries.indexWhere((e) => e.id == existing.id)] =
          merged;
      updated.add(merged);
      duplicates++;
    } else {
      await store.addImportedEntry(entry);
      created.add(entry);
    }

    // Note balance
    final balance = parsed.balance ??
        (sender.kind == SenderKind.bank ? smsBalance(message.body) : null);
    if (balance != null) {
      final bankName =
          sender.bank ?? (sender.header.isEmpty ? 'your bank' : sender.header);
      final bal = BankBalance(
        bank: bankName,
        accountHint:
            parsed.accountHint ?? smsAccountHint(message.body),
        paise: balance.paise,
        isLimit: balance.isLimit,
        at: message.date,
      );
      await store.applyBankBalanceReport(bal);
    }

    store.seenSms.add(key);
  }

  return ImportResult(
    created: created.length,
    updated: updated.length,
    skipped: skipped,
    duplicates: duplicates,
    unrecognized: unrecognized,
    accountMatches: accountMatches,
    warnings: warnings,
  );
}

/// Builds a LedgerEntry from a parsed SMS.
LedgerEntry _buildEntryFromSms(
  LifePilotStore store,
  ParsedSms parsed,
  SmsMessage message, {
  required String sourceType,
}) {
  final counterparty = parsed.counterparty;
  final title = parsed.isRefund
      ? (counterparty.isEmpty ? 'Refund' : 'Refund from $counterparty')
      : counterparty.isNotEmpty
          ? counterparty
          : parsed.kind == EntryKind.income
              ? 'Money received'
              : 'Payment';

  final category = suggestCategory(store.entries, counterparty,
          kind: parsed.kind) ??
      'Other';

  String? accountId;
  final hint = parsed.accountHint;
  if (hint != null) {
    for (final account in store.accounts) {
      if (account.name.contains(hint)) {
        accountId = account.id;
        break;
      }
    }
  }
  if (accountId == null && parsed.accountHint != null) {
    final bankLower = parsed.accountHint!.toLowerCase();
    for (final account in store.accounts) {
      if (account.name.toLowerCase().contains(bankLower)) {
        accountId = account.id;
        break;
      }
    }
  }

  return LedgerEntry(
    id: _newId(),
    kind: parsed.kind,
    amountPaise: parsed.amountPaise,
    category: category,
    title: title,
    occurredAt: parsed.date ?? message.date,
    merchant: counterparty,
    paymentMethod: parsed.channel == SmsChannel.upi ? 'UPI' : 'Bank transfer',
    accountId: accountId,
    note: parsed.reference == null ? '' : 'Ref ${parsed.reference}',
    source: 'sms',
    sourceType: sourceType,
    sourceReference: parsed.reference,
    validationStatus: ValidationStatus.partiallyVerified,
    confidenceScore: 0.6,
  );
}

/// Finds an existing transaction that matches [entry] by reference, amount,
/// date, and counterparty.
LedgerEntry? _findMatchingTransaction(
  LifePilotStore store,
  LedgerEntry entry, {
  String? sourceReference,
}) {
  for (final existing in store.entries) {
    // Same reference number
    if (sourceReference != null &&
        existing.sourceReference == sourceReference &&
        existing.sourceReference!.isNotEmpty) {
      return existing;
    }
    // Same amount, direction, date, counterparty
    if (existing.kind == entry.kind &&
        existing.amountPaise == entry.amountPaise &&
        existing.occurredAt.difference(entry.occurredAt).inHours.abs() <= 24 &&
        existing.merchant.toLowerCase() == entry.merchant.toLowerCase() &&
        existing.merchant.isNotEmpty) {
      return existing;
    }
  }
  return null;
}

/// Finds an existing transaction that matches [entry] by reference, amount,

/// Reconciles a statement's closing balance against calculated balance.
BalanceReconciliation reconcileStatementBalance(
  LifePilotStore store,
  String accountId, {
  required int statementClosingBalance,
  required DateTime statementDate,
}) {
  final account = store.accounts.firstWhere(
    (a) => a.id == accountId,
    orElse: () => const Account(
      id: '',
      name: '',
      kind: AccountKind.other,
    ),
  );
  if (account.id.isEmpty) {
    return BalanceReconciliation(
      accountId: accountId,
      statementBalance: statementClosingBalance,
      calculatedBalance: 0,
      difference: statementClosingBalance,
      status: 'no_account',
    );
  }

  final entries = store.entries.where(
    (e) => e.accountId == accountId &&
        !e.occurredAt.isAfter(statementDate),
  );
  int incomeSum = 0;
  int expenseSum = 0;
  for (final e in entries) {
    if (e.isIncome) {
      incomeSum += e.amountPaise;
    } else {
      expenseSum += e.amountPaise;
    }
  }
  final calculated = account.openingBalancePaise + incomeSum - expenseSum;

  final difference = statementClosingBalance - calculated;
  final status = difference.abs() <= 100 ? 'reconciled' : 'mismatched';

  return BalanceReconciliation(
    accountId: accountId,
    statementBalance: statementClosingBalance,
    calculatedBalance: calculated,
    difference: difference,
    status: status,
    at: statementDate,
  );
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

/// Imports statement rows through the centralized engine.
Future<ImportResult> importStatementBatch(
  LifePilotStore store,
  List<StatementRow> rows, {
  BankIdentification? bankIdentification,
  String? accountId,
  bool autoCreateAccounts = true,
}) async {
  final created = <LedgerEntry>[];
  final updated = <LedgerEntry>[];
  int skipped = 0;
  int duplicates = 0;
  int unrecognized = 0;
  final warnings = <String>[];
  final accountMatches = <AccountMatchResult>[];

  Account? targetAccount;
  if (bankIdentification != null) {
    final match = matchAccountToIdentification(store, bankIdentification,
        createIfMissing: autoCreateAccounts);
    if (match != null) {
      targetAccount = match.account;
      accountMatches.add(match);
      if (match.isNew) {
        store.accounts.add(match.account);
      }
      // Update account balance from statement
      if (bankIdentification.closingBalance != null) {
        final index =
            store.accounts.indexWhere((a) => a.id == match.account.id);
        if (index >= 0) {
          store.accounts[index] = match.account.copyWith(
            currentBalancePaise: bankIdentification.closingBalance,
            availableBalancePaise: bankIdentification.closingBalance,
            lastStatementBalancePaise: bankIdentification.closingBalance,
            lastUpdatedAt: bankIdentification.statementPeriodEnd,
            verificationStatus: 'matched',
          );
        }
      }
    } else {
      warnings.add(
          'Could not identify bank account for this statement. Transactions will be imported without account linking.');
    }
  } else if (accountId != null) {
    targetAccount = store.accounts.firstWhere(
      (a) => a.id == accountId,
      orElse: () => const Account(
        id: '',
        name: '',
        kind: AccountKind.other,
      ),
    );
  }

  for (final row in rows) {
    if (row.kind == EntryKind.expense && row.amountPaise == 0) {
      skipped++;
      continue;
    }

    final entry = LedgerEntry(
      id: _newId(),
      kind: row.kind,
      amountPaise: row.amountPaise,
      category: row.classification == TransactionClassification.other
          ? 'Other'
          : row.classification.name,
      title: row.narration,
      occurredAt: row.date,
      merchant: row.narration,
      paymentMethod: 'Bank transfer',
      accountId: targetAccount?.id,
      note: row.balanceDifference != null
          ? 'Balance diff: ${formatMoney(row.balanceDifference!)}'
          : '',
      source: 'statement',
      sourceType: 'statement',
      sourceReference: statementKey(row),
      validationStatus: row.validationStatus,
      confidenceScore: row.confidenceScore,
      originalKind: row.columnDirection,
      refundLinkId: row.refundLinkId,
    );

    final existing = _findMatchingTransaction(store, entry,
        sourceReference: entry.sourceReference);
    if (existing != null) {
      final merged = existing.copyWith(
        sourceType: 'statement',
        sourceReference:
            entry.sourceReference ?? existing.sourceReference,
        validationStatus: row.validationStatus == ValidationStatus.verified
            ? ValidationStatus.verified
            : existing.validationStatus,
        confidenceScore: (existing.confidenceScore + row.confidenceScore) / 2,
      );
      store.entries[store.entries.indexWhere((e) => e.id == existing.id)] =
          merged;
      updated.add(merged);
      duplicates++;
    } else {
      await store.addImportedEntry(entry);
      created.add(entry);
    }
  }

  return ImportResult(
    created: created.length,
    updated: updated.length,
    skipped: skipped,
    duplicates: duplicates,
    unrecognized: unrecognized,
    accountMatches: accountMatches,
    warnings: warnings,
  );
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
    final entries = store.entries.where(
      (e) => e.accountId == account.id &&
          !e.occurredAt.isAfter(now),
    );
    int incomeSum = 0;
    int expenseSum = 0;
    for (final e in entries) {
      if (e.isIncome) {
        incomeSum += e.amountPaise;
      } else {
        expenseSum += e.amountPaise;
      }
    }
    final calculated = account.openingBalancePaise + incomeSum - expenseSum;

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
