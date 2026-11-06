import 'dart:math';

import 'formatters.dart';
import 'models.dart';

/// Reading bank and UPI transaction SMS: who sent it, whether it looks like
/// a scam, and what transaction it describes. Everything runs on the phone.
/// Parsed values are only ever turned into drafts the user approves.

// ---------------------------------------------------------------------------
// Senders

/// Registered SMS headers (DLT sender IDs) of major Indian banks and
/// payment banks. Messages arrive as e.g. `VM-HDFCBK` or `JD-HDFCBK-S`.
const knownBankSenders = <String, String>{
  'HDFCBK': 'HDFC Bank',
  'HDFCBN': 'HDFC Bank',
  'ICICIB': 'ICICI Bank',
  'ICICIT': 'ICICI Bank',
  'SBIINB': 'SBI',
  'SBIUPI': 'SBI',
  'SBIPSG': 'SBI',
  'CBSSBI': 'SBI',
  'ATMSBI': 'SBI',
  'SBICRD': 'SBI Card',
  'AXISBK': 'Axis Bank',
  'AXISMR': 'Axis Bank',
  'KOTAKB': 'Kotak Bank',
  'IDFCFB': 'IDFC FIRST Bank',
  'YESBNK': 'Yes Bank',
  'INDUSB': 'IndusInd Bank',
  'PNBSMS': 'Punjab National Bank',
  'BOIIND': 'Bank of India',
  'CANBNK': 'Canara Bank',
  'UNIONB': 'Union Bank of India',
  'BOBTXN': 'Bank of Baroda',
  'BOBSMS': 'Bank of Baroda',
  'CENTBK': 'Central Bank of India',
  'IDBIBK': 'IDBI Bank',
  'FEDBNK': 'Federal Bank',
  'RBLBNK': 'RBL Bank',
  'AUBANK': 'AU Small Finance Bank',
  'CITIBK': 'Citibank',
  'HSBCIN': 'HSBC',
  'DBSBNK': 'DBS Bank',
  'SCBANK': 'Standard Chartered',
  'IOBCHN': 'Indian Overseas Bank',
  'INDBNK': 'Indian Bank',
  'UCOBNK': 'UCO Bank',
  'PAYTMB': 'Paytm Payments Bank',
  'AIRBNK': 'Airtel Payments Bank',
  'IPBMSG': 'India Post Payments Bank',
};

enum SenderKind { bank, unknownHeader, phoneNumber, pasted }

class SmsSender {
  const SmsSender(this.kind, {this.header = '', this.bank});

  final SenderKind kind;

  /// The six-character sender ID, e.g. `HDFCBK`.
  final String header;
  final String? bank;
}

/// Works out who sent a message from its address. [extraSenders] are
/// sender IDs the user has marked as their bank's.
SmsSender classifySender(String address,
    {Iterable<String> extraSenders = const []}) {
  final value = address.trim();
  if (value.isEmpty || value == 'pasted') {
    return const SmsSender(SenderKind.pasted);
  }
  if (RegExp(r'^\+?\d[\d\s-]{5,}$').hasMatch(value)) {
    return SmsSender(SenderKind.phoneNumber, header: value);
  }
  final parts = value.toUpperCase().split('-');
  final header = parts.firstWhere(
      (part) => RegExp(r'^[A-Z0-9]{6}$').hasMatch(part),
      orElse: () => parts.length > 1 ? parts[1] : parts.first);
  final extra = extraSenders.map((item) => item.trim().toUpperCase());
  final bank =
      knownBankSenders[header] ?? (extra.contains(header) ? header : null);
  return SmsSender(bank == null ? SenderKind.unknownHeader : SenderKind.bank,
      header: header, bank: bank);
}

// ---------------------------------------------------------------------------
// Scam detection

final _link = RegExp(
    r'(https?://|www\.|bit\.ly|tinyurl|\b[a-z0-9-]+\.(?:xyz|top|click|link|live|online|site|icu|buzz)\b)',
    caseSensitive: false);
final _lure = RegExp(
    r'\b(kyc|pan card|pan (?:no|number|update)|aadhaa?r|(?:account|a/c|card|wallet|sim) (?:will be |has been |is )?(?:blocked|suspended|deactivated|closed)|blocked today|suspend|deactivat|expir(?:e|ed|ing) today|update your|verify your|reward points?|redeem|lottery|prize|you (?:have )?won|electricity (?:power |connection )?(?:will be )?(?:disconnect|cut)|disconnected tonight|claim (?:your|now))',
    caseSensitive: false);
final _bankish = RegExp(
    r'\b(bank|a/?c|account|debited|credited|upi|card|kyc|net ?banking)\b',
    caseSensitive: false);

/// Why a message looks like a scam, or null. Messages from registered bank
/// sender IDs are trusted, since those headers cannot be used by others.
String? scamReason(SmsSender sender, String body) {
  if (sender.kind == SenderKind.bank) return null;
  final lure = _lure.hasMatch(body);
  final link = _link.hasMatch(body);
  if (sender.kind == SenderKind.phoneNumber && _bankish.hasMatch(body)) {
    return 'Sent from a phone number but written like a bank message. Banks send from registered names such as HDFCBK or SBIINB, never from mobile numbers.';
  }
  if (lure && (link || sender.kind == SenderKind.phoneNumber)) {
    return 'Pressures you about KYC, a blocked account, a reward or a disconnection and asks you to click or call. Banks and utilities do not ask for this by SMS.';
  }
  if (link && _bankish.hasMatch(body) && sender.kind != SenderKind.pasted) {
    return 'A link in a bank-style message from a sender that is not a known bank. Do not open it.';
  }
  return null;
}

/// Removes what a stored copy of a message does not need: balances and
/// links. Banks already mask account numbers.
String redactSms(String body) => body
    .replaceAll(
        RegExp(
            r'(?:total\s+)?(?:avl|avbl|avail|available|updated|clear|net)\.?\s*(?:bal|balance|lmt|limit)[^.;\n]*(?:\.\d{1,2})?',
            caseSensitive: false),
        '[balance hidden]')
    .replaceAll(
        RegExp(r'https?://\S+|www\.\S+', caseSensitive: false), '[link]')
    .trim();

// ---------------------------------------------------------------------------
// Parsing

enum SmsChannel { upi, card, atm, transfer }

/// A balance or available credit limit written in a bank message.
class SmsBalance {
  const SmsBalance(this.paise, {this.isLimit = false});

  /// Negative when the bank marks the balance as owed (`Dr`).
  final int paise;

  /// True for a card's available credit limit rather than money held.
  final bool isLimit;
}

final _balancePattern = RegExp(
  r'\b(?<!(?:minimum|min|average|avg|monthly|outstanding|loan|due|statement)\.?\s{0,2})'
  r'(?:(?:avl|avbl|avail|available|updated|new|net|clear|closing|current)\.?\s*)?'
  r'(?:a/?c\s*)?(bal(?:ance)?|lmt|limit)\b'
  r'(?:\s+(?:in|of)\s+(?:your\s+)?(?:a/?c|acct|account)(?:\s*(?:no\.?)?\s*[x*]*\d{3,4})?)?'
  r'(?:\s*is)?'
  r'[\s.:\-]*(?:rs\.?|inr|₹)?[\s.:]*(-)?\s*(\d[\d,]*(?:\.\d{1,2})?)\s*(cr|dr)?\b',
  caseSensitive: false,
);

/// The available balance (or card limit) a message reports, if any. When a
/// message has both, the account balance wins over a credit limit.
SmsBalance? smsBalance(String body) {
  final text = body.replaceAll(RegExp(r'\s+'), ' ');
  SmsBalance? limit;
  for (final match in _balancePattern.allMatches(text)) {
    final value = parseRupeesToPaise(match.group(3)!);
    // A bare "0" can be a real balance; parseRupeesToPaise rejects it.
    final paise = value ??
        (RegExp(r'^0[0,]*(?:\.0{1,2})?$').hasMatch(match.group(3)!) ? 0 : null);
    if (paise == null) continue;
    final owed =
        match.group(2) != null || (match.group(4)?.toLowerCase() == 'dr');
    final isLimit = match.group(1)!.toLowerCase().startsWith('l');
    final result = SmsBalance(owed ? -paise : paise, isLimit: isLimit);
    if (!isLimit) return result;
    limit ??= result;
  }
  return limit;
}

class ParsedSms {
  const ParsedSms({
    required this.kind,
    required this.amountPaise,
    required this.counterparty,
    this.accountHint,
    this.reference,
    this.date,
    this.channel = SmsChannel.transfer,
    this.isRefund = false,
    this.balance,
    this.isAutoPay = false,
    this.isCardBillPayment = false,
  });

  final EntryKind kind;
  final int amountPaise;

  /// Merchant, payee, or payer as written in the message; may be empty.
  final String counterparty;

  /// Last digits of the account or card, e.g. "1234".
  final String? accountHint;

  /// UPI reference (RRN), UTR or transaction id.
  final String? reference;

  /// Transaction date written in the message, if any.
  final DateTime? date;
  final SmsChannel channel;
  final bool isRefund;

  /// Balance or card limit left after this transaction, if the bank said.
  final SmsBalance? balance;

  /// Taken by a standing instruction: e-mandate, autopay, NACH, ECS or SI.
  /// A strong sign that the payment repeats.
  final bool isAutoPay;

  /// "Payment received" on a credit card: money moving between the user's
  /// own accounts, not income.
  final bool isCardBillPayment;

  String get paymentMethod => switch (channel) {
        SmsChannel.upi => 'UPI',
        SmsChannel.card => 'Card',
        SmsChannel.atm => 'Other',
        SmsChannel.transfer => 'Bank transfer',
      };
}

final _ignoreSms = RegExp(
  r'\b(otp|one[- ]time password|verification code|will be (?:debited|deducted|charged)|'
  r'to be debited|is due|due on|due date|requested|request of|collect request|'
  r'your request|failed|declined|unsuccessful|reminder|offer|cashback upto|'
  r'pre-?approved|loan offer)\b',
  caseSensitive: false,
);

/// Standing-instruction words. Set-up notices are ignored; executed debits
/// are kept and marked as autopay.
final _autoPay = RegExp(
    r'\b(e-?mandate|auto-?pay|auto[- ]?debit|standing instruction|nach|ecs|si (?:executed|debit))\b',
    caseSensitive: false);
final _mandateSetup = RegExp(
    r'\b(registered|registration|set up|setup|activated|created|is set|has been set|modified|revoked|cancelled|paused)\b',
    caseSensitive: false);

final _debit = RegExp(
    r'\b(debited|spent|paid|sent|withdrawn|withdrawal|purchase|dr\b|deducted|'
    r'transferred to|trf to|debit of|has (?:a )?debit|charged)',
    caseSensitive: false);

final _credit = RegExp(
    r'\b(credited|received|deposited|refund(ed)?|revers(ed|al)|cr\b|'
    r'credit of(?! card)|has (?:a )?credit\b(?! card))',
    caseSensitive: false);

/// "credited to VPA x@y" / "credited to beneficiary": the payee's side of a
/// payment the user made. "credited to your a/c" / "to A/c XX1234" is not.
final _creditedToPayee = RegExp(
    r'\bcredited\s+to\s+(?!(?:your|ur|the|my|sb|savings?|current|salary|nre|nro|a/?c|acct|account|card|wallet)\b|[x*]+\d)\S',
    caseSensitive: false);

/// "...; SWIGGY credited." Names such as "Your a/c" or "Rs 500" are
/// filtered out by [_notPayee].
final _namedCredited = RegExp(
    r'[;.]\s*([A-Za-z][A-Za-z0-9 &._@\-]{1,39}?)\s+credited\b',
    caseSensitive: false);
final _notPayee = RegExp(
    r'^(?:your|ur|a/?c|acct|account|card|wallet|dear|hi|hello|salary|money|amount|refund)\b'
    r'|\b(?:rs|inr)\b|₹'
    // A masked account ("XXXXXX4321 is credited") or a passive verb.
    r'|^[x*]+\d|\b(?:is|was|has been|have been|been|got)$',
    caseSensitive: false);

List<Match> _payeeCredits(String text) => [
      ..._creditedToPayee.allMatches(text),
      ..._namedCredited
          .allMatches(text)
          .where((match) => !_notPayee.hasMatch(match.group(1)!.trim())),
    ];

/// A credit card bill payment: "Payment of Rs 5,000 received on your
/// credit card", or a bank debit "towards credit card payment". Not a card
/// purchase paid "via credit card".
final _cardBillPayment = RegExp(
    r'\b(?:payment|repayment)\b.{0,60}?\b(?:towards|on|for|against)\s+(?:your\s+)?'
    r'(?:(?!via\b|using\b|with\b|by\b|from\b)[a-z]+\s+){0,3}credit\s*card\b'
    r'|\bcredit\s*card\s+(?:bill\s+)?(?:payment|repayment|bill)\b',
    caseSensitive: false);

final _refund =
    RegExp(r'\b(refund(ed)?|revers(ed|al))\b', caseSensitive: false);

/// Whether a message describes money coming in, going out, or neither.
/// Balances are removed first so "Avl Bal Rs 900 CR" cannot make a debit
/// look like a credit, and "credited" on the payee's side counts as a debit.
EntryKind? smsDirection(String text) {
  final plain = text.replaceAll(_balancePattern, ' ');
  final payeeSide = _payeeCredits(plain);
  bool isPayeeSide(Match match) => payeeSide
      .any((side) => match.start >= side.start && match.start < side.end);
  final debit = _debit.firstMatch(plain);
  final credit = _credit
      .allMatches(plain)
      .where((match) => !isPayeeSide(match))
      .firstOrNull;
  if (debit == null && credit == null) {
    // Only the payee was credited: the money left the user's account.
    return payeeSide.isEmpty ? null : EntryKind.expense;
  }
  if (credit == null) return EntryKind.expense;
  if (debit == null) return EntryKind.income;
  return debit.start < credit.start ? EntryKind.expense : EntryKind.income;
}

final _amountTag =
    RegExp(r'(?:rs[.:]?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
final _amountAfterVerb = RegExp(
    r'\b(?:debited|credited|withdrawn|deducted)\s+(?:by|with|for)\s+(?:rs[.:]?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false);
final _balanceBefore = RegExp(
    r'(?:bal|balance|limit|lmt|avl|avbl|available)[\s.:\-a-z]*$',
    caseSensitive: false);

/// The transaction amount: the first rupee amount that is not a balance or
/// credit limit.
int? _transactionAmount(String text) {
  for (final match in _amountTag.allMatches(text)) {
    final before = text.substring(max(0, match.start - 24), match.start);
    if (_balanceBefore.hasMatch(before)) continue;
    final value = parseRupeesToPaise(match.group(1)!);
    if (value != null) return value;
  }
  final verb = _amountAfterVerb.firstMatch(text);
  return verb == null ? null : parseRupeesToPaise(verb.group(1)!);
}

const _stop =
    r'(?=\s+(?:on|ref|refno|ref\s*no|upi|via|avl|avbl|from|using|with|txn|transaction|in|is|has|dated|not)\b|\s*[.,;(]|\s+-|\s*$)';
final _notAName = RegExp(
    r'^(?:(?:a/?c|acct|account|card|your|you|the|upi|neft|imps|rs|inr)\b|xx|₹|\d)',
    caseSensitive: false);
final _upiPath = RegExp(r'\bUPI/(?:P2[AM]/)?\d{6,}/([^/\n]+?)(?=/|\s|\.|$)',
    caseSensitive: false);
final _vpa = RegExp(r'\b([a-zA-Z0-9][\w.\-]*@[a-zA-Z][a-zA-Z0-9\-]+)\b');
final _creditedName = RegExp(
    r'[;.]\s*([A-Za-z0-9][A-Za-z0-9 &._\-]{1,39}?)\s+credited\b',
    caseSensitive: false);
final _expenseName = [
  RegExp(
      r'\b(?:trf to|to|at|towards|for)\s+(?:vpa\s+)?([A-Za-z0-9@._&\- ]{2,40}?)' +
          _stop,
      caseSensitive: false),
  RegExp(r'\binfo[:\-]\s*([A-Za-z0-9@._&\- /]{2,40})', caseSensitive: false),
];
final _incomeName = [
  RegExp(r'\bfrom\s+(?:vpa\s+)?([A-Za-z0-9@._&\- ]{2,40}?)' + _stop,
      caseSensitive: false),
  RegExp(r'\bby\s+(?:vpa\s+)?([A-Za-z0-9@._&\- ]{2,40}?)' + _stop,
      caseSensitive: false),
  RegExp(r'\binfo[:\-]\s*([A-Za-z0-9@._&\- /]{2,40})', caseSensitive: false),
];

String _clean(String value) => value
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[.\-\s]+$'), '')
    .trim();

String _counterparty(String text, EntryKind kind) {
  final path = _upiPath.firstMatch(text)?.group(1);
  if (path != null && !_notAName.hasMatch(path)) return _clean(path);
  final vpa = _vpa.firstMatch(text)?.group(1);
  if (vpa != null) return vpa;
  if (kind == EntryKind.expense) {
    final credited = _creditedName.firstMatch(text)?.group(1);
    if (credited != null && !_notAName.hasMatch(credited)) {
      return _clean(credited);
    }
  }
  for (final pattern
      in kind == EntryKind.expense ? _expenseName : _incomeName) {
    for (final match in pattern.allMatches(text)) {
      final value = _clean(match.group(1) ?? '');
      if (value.length >= 2 && !_notAName.hasMatch(value)) return value;
    }
  }
  return '';
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// The transaction date written in [text], if it is plausible for a
/// message received at [received] (up to 60 days earlier, or a day later
/// for time-zone slack).
DateTime? smsDate(String text, DateTime received) {
  int year(String value) {
    final number = int.parse(value);
    return value.length <= 2 ? 2000 + number : number;
  }

  final candidates = <DateTime?>[];
  for (final match
      in RegExp(r'\b(\d{4})[-/:](\d{1,2})[-/:](\d{1,2})\b').allMatches(text)) {
    candidates.add(_date(int.parse(match.group(1)!), int.parse(match.group(2)!),
        int.parse(match.group(3)!)));
  }
  for (final match
      in RegExp(r'\b(\d{1,2})[-/ ]?([A-Za-z]{3})[a-z]*[-/ ,]*(\d{4}|\d{2})\b')
          .allMatches(text)) {
    final month = _months[match.group(2)!.toLowerCase()];
    if (month == null) continue;
    candidates
        .add(_date(year(match.group(3)!), month, int.parse(match.group(1)!)));
  }
  for (final match in RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b')
      .allMatches(text)) {
    candidates.add(_date(year(match.group(3)!), int.parse(match.group(2)!),
        int.parse(match.group(1)!)));
  }
  final day = DateTime(received.year, received.month, received.day);
  for (final date in candidates.whereType<DateTime>()) {
    if (!date.isAfter(day.add(const Duration(days: 1))) &&
        !date.isBefore(day.subtract(const Duration(days: 60)))) {
      return date;
    }
  }
  return null;
}

DateTime? _date(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  return date.month == month ? date : null;
}

/// Last digits of the account or card a message is about, e.g. "1234".
String? smsAccountHint(String text) => RegExp(
        r'(?:a/?c|acct|account|card)\s*(?:no\.?)?\s*(?:ending\s*(?:with)?\s*)?[x*]*(\d{3,4})\b',
        caseSensitive: false)
    .firstMatch(text)
    ?.group(1);

/// Reads a bank or UPI transaction SMS. Returns null for messages that are
/// not completed transactions (OTPs, reminders, requests, offers, failures).
/// [received] lets the date in the message be checked for plausibility.
ParsedSms? parseBankSms(String body, {DateTime? received}) {
  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (_ignoreSms.hasMatch(text)) return null;
  final autoPay = _autoPay.hasMatch(text);
  // Mandate set-up, change or cancellation notices move no money.
  if (autoPay &&
      _mandateSetup.hasMatch(text) &&
      !RegExp(r'\b(debited|deducted|charged|paid)\b', caseSensitive: false)
          .hasMatch(text)) {
    return null;
  }
  final amount = _transactionAmount(text);
  if (amount == null || amount <= 0) return null;
  final kind = smsDirection(text);
  if (kind == null) return null;
  final counterparty = _counterparty(text, kind);
  final account = smsAccountHint(text);
  final pathRef = RegExp(r'\bUPI/(?:P2[AM]/)?(\d{6,})/', caseSensitive: false)
      .firstMatch(text)
      ?.group(1);
  final reference = pathRef ??
      RegExp(r'\b(?:upi(?:\s*ref(?:erence)?)?(?:\s*no)?|ref(?:erence)?(?:\s*no)?|refno|rrn|utr|txn\s*id|txn)[\s:.#-]*([A-Za-z0-9]{6,22})',
              caseSensitive: false)
          .allMatches(text)
          .map((match) => match.group(1)!)
          .where((value) => RegExp(r'\d{4}').hasMatch(value))
          .firstOrNull;
  final lower = text.toLowerCase();
  final channel = RegExp(r'\batm\b|withdrawn|cash withdrawal').hasMatch(lower)
      ? SmsChannel.atm
      : RegExp(r'\bupi\b|vpa\b').hasMatch(lower) || counterparty.contains('@')
          ? SmsChannel.upi
          : RegExp(r'\b(card|pos)\b').hasMatch(lower)
              ? SmsChannel.card
              : SmsChannel.transfer;
  return ParsedSms(
    kind: kind,
    amountPaise: amount,
    counterparty: counterparty,
    accountHint: account,
    reference: reference,
    date: received == null ? null : smsDate(text, received),
    channel: channel,
    isRefund: kind == EntryKind.income && _refund.hasMatch(text),
    balance: smsBalance(text),
    isAutoPay: autoPay,
    isCardBillPayment: _cardBillPayment.hasMatch(text),
  );
}

/// Stable identity for an SMS so it is never imported twice.
String smsFingerprint(String address, String body, DateTime date) {
  var hash = 0x811c9dc5;
  for (final unit
      in '$address|${date.millisecondsSinceEpoch}|$body'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'sms:${hash.toRadixString(16)}';
}
