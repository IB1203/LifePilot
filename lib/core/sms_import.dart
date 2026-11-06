import 'bank_sms.dart';
import 'formatters.dart';
import 'local_store.dart';
import 'models.dart';
import 'personal.dart' show suggestCategory;
import 'recurring_detect.dart';

typedef SmsMessage = ({String address, String body, DateTime date});

/// A recurring draft that a bank SMS shows was actually paid or received.
typedef RecurringMatch = ({
  String pendingId,
  String key,
  String bank,
  int amountPaise,
  DateTime occurredAt,
  String note,
  String merchant,
  String sourceText,
  int? balancePaise,
});

/// What a batch of messages would do to the store. Nothing is saved until
/// [LifePilotStore.applySmsImport] is called.
class SmsImport {
  final drafts = <PendingEntry>[];

  /// UPI drafts that a bank SMS now confirms: draft id → bank name.
  final confirmations = <({String pendingId, String key, String bank})>[];

  /// Recurring drafts (salary, rent…) that a bank SMS confirms, so the
  /// same payment is not drafted twice.
  final recurringMatches = <RecurringMatch>[];

  /// Messages describing a transaction that is already recorded.
  final duplicates = <String>[];
  final suspicious = <SuspiciousSms>[];

  /// Latest balance per account seen in this batch.
  final balances = <String, BankBalance>{};

  /// Keys of every message this import used, to mark them as seen.
  Iterable<String> get handled => [
        ...drafts.map((draft) => draft.sourceKey!),
        ...confirmations.map((item) => item.key),
        ...recurringMatches.map((item) => item.key),
        ...duplicates,
        ...suspicious.map((item) => item.key),
      ];

  bool get isEmpty =>
      drafts.isEmpty &&
      confirmations.isEmpty &&
      recurringMatches.isEmpty &&
      suspicious.isEmpty &&
      balances.isEmpty;

  void _noteBalance(BankBalance balance) {
    final existing = balances[balance.key];
    if (existing == null || !balance.at.isBefore(existing.at)) {
      balances[balance.key] = balance;
    }
  }

  String summary() {
    final credited = drafts
        .where((draft) => draft.entry.isIncome)
        .fold(0, (sum, draft) => sum + draft.entry.amountPaise);
    final debited = drafts
        .where((draft) => !draft.entry.isIncome)
        .fold(0, (sum, draft) => sum + draft.entry.amountPaise);
    final flows = [
      if (credited > 0) 'credited ${formatMoney(credited)}',
      if (debited > 0) 'debited ${formatMoney(debited)}',
    ];
    final parts = [
      if (drafts.isNotEmpty)
        '${drafts.length} draft${drafts.length == 1 ? '' : 's'} to review'
            '${flows.isEmpty ? '' : ' (${flows.join(', ')})'}',
      if (confirmations.isNotEmpty)
        '${confirmations.length} UPI payment${confirmations.length == 1 ? '' : 's'} confirmed by your bank',
      if (recurringMatches.isNotEmpty)
        '${recurringMatches.length} recurring entr${recurringMatches.length == 1 ? 'y' : 'ies'} matched to your bank',
      if (balances.isNotEmpty)
        '${balances.length} balance${balances.length == 1 ? '' : 's'} updated',
      if (duplicates.isNotEmpty) '${duplicates.length} already recorded',
      if (suspicious.isNotEmpty)
        '${suspicious.length} possible scam message${suspicious.length == 1 ? '' : 's'} held back',
    ];
    return parts.isEmpty
        ? 'No new transaction messages.'
        : '${parts.join(', ')}.';
  }
}

/// Category from the user's rules, if one matches.
String? ruleCategory(Iterable<CategoryRule> rules, String text) {
  for (final rule in rules) {
    if (rule.matches(text)) return rule.category;
  }
  return null;
}

bool _sameDayish(DateTime a, DateTime b, {int days = 1}) =>
    a.difference(b).inHours.abs() <= days * 24 + 12;

bool _mentions(String text, String? reference) =>
    reference != null && reference.length >= 6 && text.contains(reference);

Set<String> _words(String value) => value
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.length >= 3)
    .toSet();

/// Reads [messages] into drafts, bank confirmations of UPI drafts,
/// duplicates of recorded entries, and suspicious messages.
SmsImport buildSmsImport(LifePilotStore store, Iterable<SmsMessage> messages) {
  final result = SmsImport();
  final settings = store.settings;
  final inBatch = <String>{};
  for (final message in messages) {
    final key = smsFingerprint(message.address, message.body, message.date);
    if (store.seenSms.contains(key) || !inBatch.add(key)) continue;
    final sender =
        classifySender(message.address, extraSenders: settings.extraSmsSenders);
    final reason = scamReason(sender, message.body);
    if (reason != null) {
      final snippet = redactSms(message.body);
      result.suspicious.add(SuspiciousSms(
        key: key,
        sender: message.address,
        reason: reason,
        snippet:
            snippet.length > 280 ? '${snippet.substring(0, 280)}…' : snippet,
        receivedAt: message.date,
      ));
      continue;
    }
    // Personal messages from phone numbers are never transactions.
    if (sender.kind == SenderKind.phoneNumber) continue;
    final parsed = parseBankSms(message.body, received: message.date);
    final bankName =
        sender.bank ?? (sender.header.isEmpty ? 'your bank' : sender.header);

    // Available balance: from a transaction message, or a balance-only
    // message ("Your a/c XX1234 balance is…") from a known bank sender.
    final balance = parsed?.balance ??
        (sender.kind == SenderKind.bank ? smsBalance(message.body) : null);
    if (balance != null) {
      result._noteBalance(BankBalance(
        bank: bankName,
        accountHint: parsed?.accountHint ?? smsAccountHint(message.body),
        paise: balance.paise,
        isLimit: balance.isLimit,
        at: message.date,
      ));
    }
    if (parsed == null) continue;
    final date = parsed.date;
    final occurredAt = date == null ||
            (date.year == message.date.year &&
                date.month == message.date.month &&
                date.day == message.date.day)
        ? message.date
        : DateTime(date.year, date.month, date.day, 12);
    final sourceText =
        settings.keepSmsText ? message.body.trim() : redactSms(message.body);
    final note = parsed.reference == null ? '' : 'Ref ${parsed.reference}';

    // 1. A bank SMS for a payment the user started from LifePilot.
    if (parsed.kind == EntryKind.expense) {
      final upiDrafts = store.pending.where((draft) =>
          draft.source == 'upi' &&
          !draft.bankConfirmed &&
          draft.entry.amountPaise == parsed.amountPaise &&
          !result.confirmations.any((item) => item.pendingId == draft.id));
      final byReference = upiDrafts
          .where((draft) => _mentions(draft.entry.note, parsed.reference));
      final byTime = upiDrafts.where((draft) {
        final gap = message.date.difference(draft.entry.occurredAt);
        return gap >= const Duration(hours: -1) &&
            gap <= const Duration(days: 3);
      });
      final match = byReference.isNotEmpty
          ? byReference.first
          : byTime.isNotEmpty
              ? byTime.first
              : null;
      if (match != null) {
        result.confirmations
            .add((pendingId: match.id, key: key, bank: bankName));
        continue;
      }
    }

    // 2. Salary, rent, a SIP… that a recurring entry already drafted.
    final probe = LedgerEntry(
      id: '',
      kind: parsed.kind,
      amountPaise: parsed.amountPaise,
      category: '',
      title: parsed.counterparty,
      merchant: parsed.counterparty,
      occurredAt: occurredAt,
    );
    final recurringDraft = store.pending
        .where((draft) =>
            draft.source == 'recurring' &&
            !draft.bankConfirmed &&
            !result.recurringMatches
                .any((item) => item.pendingId == draft.id) &&
            matchesRecurring(
              kind: draft.entry.kind,
              amountPaise: draft.entry.amountPaise,
              title: draft.entry.title,
              due: draft.entry.occurredAt,
              entry: probe,
            ))
        .firstOrNull;
    if (recurringDraft != null) {
      result.recurringMatches.add((
        pendingId: recurringDraft.id,
        key: key,
        bank: bankName,
        amountPaise: parsed.amountPaise,
        occurredAt: occurredAt,
        note: note,
        merchant: parsed.counterparty,
        sourceText: sourceText,
        balancePaise: balance?.isLimit == false ? balance!.paise : null,
      ));
      continue;
    }

    // 3. Already recorded, or already waiting as a draft.
    final counterpartyWords = _words(parsed.counterparty);
    final duplicate = store.entries.any((entry) =>
            entry.kind == parsed.kind &&
            entry.amountPaise == parsed.amountPaise &&
            (_mentions(entry.note, parsed.reference) ||
                (_sameDayish(entry.occurredAt, occurredAt) &&
                    (entry.source == 'upi' ||
                        counterpartyWords
                            .intersection(
                                _words('${entry.title} ${entry.merchant}'))
                            .isNotEmpty)))) ||
        store.pending.any((draft) =>
            draft.entry.amountPaise == parsed.amountPaise &&
            _mentions(draft.entry.note, parsed.reference)) ||
        result.drafts.any((draft) =>
            draft.entry.amountPaise == parsed.amountPaise &&
            _mentions(draft.entry.note, parsed.reference));
    if (duplicate) {
      result.duplicates.add(key);
      continue;
    }

    // 4. A new draft.
    final counterparty = parsed.counterparty;
    final atm = parsed.channel == SmsChannel.atm;
    final title = atm
        ? 'ATM cash withdrawal'
        : parsed.isRefund
            ? (counterparty.isEmpty ? 'Refund' : 'Refund from $counterparty')
            : counterparty.isNotEmpty
                ? counterparty
                : parsed.kind == EntryKind.income
                    ? 'Money received'
                    : 'Payment';
    final category =
        ruleCategory(store.categoryRules, '$counterparty ${message.body}') ??
            (parsed.isRefund ? 'Refunds' : null) ??
            suggestCategory(store.entries, counterparty, kind: parsed.kind) ??
            'Other';
    String? accountId;
    final hint = parsed.accountHint;
    if (hint != null) {
      for (final account in store.accounts) {
        if (account.name.contains(hint)) accountId = account.id;
      }
    }
    // A recurring entry already recorded around this date for about this
    // amount may be the same payment. Ask rather than silently skip it.
    final recordedRecurring = store.entries
        .where((entry) =>
            entry.source == 'recurring' &&
            entry.kind == parsed.kind &&
            closeAmount(entry.amountPaise, parsed.amountPaise) &&
            entry.occurredAt.difference(occurredAt).inHours.abs() <=
                5 * 24 + 12)
        .firstOrNull;
    final warnings = [
      if (sender.kind == SenderKind.unknownHeader)
        'Sent by ${sender.header}, which is not a known bank sender. Check it is genuine before approving, or add it as your bank in Bank SMS settings.',
      if (atm)
        'Cash withdrawals move money into cash rather than spend it. If you track a cash wallet, record a transfer instead.',
      if (parsed.isCardBillPayment)
        'Looks like a credit card bill payment. It moves money between your own accounts, so it is not ${parsed.kind == EntryKind.income ? 'income' : 'spending'}. If you track the card as an account, record a transfer instead.',
      if (recordedRecurring != null)
        'You already recorded “${recordedRecurring.title}” for ${formatMoney(recordedRecurring.amountPaise)} on ${formatDate(recordedRecurring.occurredAt)} from a recurring entry. Discard this if it is the same payment.',
      if (parsed.kind == EntryKind.expense &&
          !atm &&
          !parsed.isAutoPay &&
          parsed.amountPaise >= settings.largePaymentPaise)
        'Large debit not started from LifePilot. If you did not make it, call your bank and the 1930 cyber-fraud helpline straight away.',
    ];
    result.drafts.add(PendingEntry(
      id: '',
      source: 'sms',
      sourceKey: key,
      createdAt: store.now(),
      sourceText: sourceText,
      warning: warnings.join(' '),
      balancePaise: balance?.isLimit == false ? balance!.paise : null,
      autoPay: parsed.isAutoPay,
      entry: LedgerEntry(
        id: '',
        kind: parsed.kind,
        amountPaise: parsed.amountPaise,
        category: category,
        title: title,
        occurredAt: occurredAt,
        merchant: counterparty,
        paymentMethod: parsed.paymentMethod,
        accountId: accountId,
        note: note,
        source: 'sms',
      ),
    ));
  }
  return result;
}
