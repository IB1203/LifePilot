import 'bank_sms.dart';
import 'local_store.dart';
import 'models.dart';
import 'personal.dart' show suggestCategory;

typedef SmsMessage = ({String address, String body, DateTime date});

/// What a batch of messages would do to the store. Nothing is saved until
/// [LifePilotStore.applySmsImport] is called.
class SmsImport {
  final drafts = <PendingEntry>[];

  /// UPI drafts that a bank SMS now confirms: draft id → bank name.
  final confirmations = <({String pendingId, String key, String bank})>[];

  /// Messages describing a transaction that is already recorded.
  final duplicates = <String>[];
  final suspicious = <SuspiciousSms>[];

  /// Keys of every message this import used, to mark them as seen.
  Iterable<String> get handled => [
        ...drafts.map((draft) => draft.sourceKey!),
        ...confirmations.map((item) => item.key),
        ...duplicates,
        ...suspicious.map((item) => item.key),
      ];

  bool get isEmpty =>
      drafts.isEmpty && confirmations.isEmpty && suspicious.isEmpty;

  String summary() {
    final parts = [
      if (drafts.isNotEmpty)
        '${drafts.length} draft${drafts.length == 1 ? '' : 's'} to review',
      if (confirmations.isNotEmpty)
        '${confirmations.length} UPI payment${confirmations.length == 1 ? '' : 's'} confirmed by your bank',
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
    if (parsed == null) continue;
    final date = parsed.date;
    final occurredAt = date == null ||
            (date.year == message.date.year &&
                date.month == message.date.month &&
                date.day == message.date.day)
        ? message.date
        : DateTime(date.year, date.month, date.day, 12);
    final bankName =
        sender.bank ?? (sender.header.isEmpty ? 'your bank' : sender.header);

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

    // 2. Already recorded, or already waiting as a draft.
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

    // 3. A new draft.
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
    final warnings = [
      if (sender.kind == SenderKind.unknownHeader)
        'Sent by ${sender.header}, which is not a known bank sender. Check it is genuine before approving, or add it as your bank in Bank SMS settings.',
      if (atm)
        'Cash withdrawals move money into cash rather than spend it. If you track a cash wallet, record a transfer instead.',
      if (parsed.kind == EntryKind.expense &&
          !atm &&
          parsed.amountPaise >= settings.largePaymentPaise)
        'Large debit not started from LifePilot. If you did not make it, call your bank and the 1930 cyber-fraud helpline straight away.',
    ];
    result.drafts.add(PendingEntry(
      id: '',
      source: 'sms',
      sourceKey: key,
      createdAt: store.now(),
      sourceText:
          settings.keepSmsText ? message.body.trim() : redactSms(message.body),
      warning: warnings.join(' '),
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
        note: parsed.reference == null ? '' : 'Ref ${parsed.reference}',
        source: 'sms',
      ),
    ));
  }
  return result;
}
