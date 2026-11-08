import 'dart:math' as math;

import 'formatters.dart';
import 'reminder_plan.dart';

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// Investments with values the user enters. LifePilot never fetches market
/// prices: deposits are valued with their own interest rate, everything
/// else at the last value the user typed in, always shown with its date.

enum InvestmentKind {
  mutualFund,
  stock,
  fixedDeposit,
  recurringDeposit,
  ppf,
  epf,
  nps,
  gold,
  other,
}

extension InvestmentKindLabel on InvestmentKind {
  String get label => switch (this) {
        InvestmentKind.mutualFund => 'Mutual fund',
        InvestmentKind.stock => 'Stocks',
        InvestmentKind.fixedDeposit => 'Fixed deposit',
        InvestmentKind.recurringDeposit => 'Recurring deposit',
        InvestmentKind.ppf => 'PPF',
        InvestmentKind.epf => 'EPF',
        InvestmentKind.nps => 'NPS',
        InvestmentKind.gold => 'Gold',
        InvestmentKind.other => 'Other',
      };

  /// Deposits whose value follows from their rate, not a typed-in value.
  bool get isDeposit =>
      this == InvestmentKind.fixedDeposit ||
      this == InvestmentKind.recurringDeposit;
}

/// Money put in (positive) or taken out (negative) on a date.
class InvestmentFlow {
  const InvestmentFlow(
      {required this.id, required this.amountPaise, required this.at});

  final String id;
  final int amountPaise;
  final DateTime at;

  Map<String, Object?> toJson() =>
      {'id': id, 'amountPaise': amountPaise, 'at': at.toIso8601String()};

  factory InvestmentFlow.fromJson(Map<String, dynamic> json) => InvestmentFlow(
        id: json['id'] as String,
        amountPaise: json['amountPaise'] as int,
        at: DateTime.parse(json['at'] as String),
      );
}

class Investment {
  const Investment({
    required this.id,
    required this.name,
    required this.kind,
    this.flows = const [],
    this.valuePaise,
    this.valueAsOf,
    this.annualRatePercent = 0,
    this.startDate,
    this.maturityDate,
    this.installmentPaise = 0,
    this.sipPaise = 0,
    this.sipDay,
    this.closed = false,
  });

  final String id;
  final String name;
  final InvestmentKind kind;

  /// Money in and out, used for invested amount and XIRR. For deposits the
  /// flows are derived from the deposit terms instead.
  final List<InvestmentFlow> flows;

  /// Current value as the user last entered it (not for deposits).
  final int? valuePaise;
  final DateTime? valueAsOf;

  /// Deposits: interest rate, start and maturity dates; for an FD the
  /// principal is the first flow, for an RD [installmentPaise] each month.
  final double annualRatePercent;
  final DateTime? startDate;
  final DateTime? maturityDate;
  final int installmentPaise;

  /// Monthly SIP amount and day of month, for the SIP calendar.
  final int sipPaise;
  final int? sipDay;
  final bool closed;

  Investment copyWith({
    String? name,
    List<InvestmentFlow>? flows,
    int? valuePaise,
    DateTime? valueAsOf,
    double? annualRatePercent,
    DateTime? startDate,
    DateTime? maturityDate,
    int? installmentPaise,
    int? sipPaise,
    int? sipDay,
    bool clearSip = false,
    bool? closed,
  }) =>
      Investment(
        id: id,
        name: name ?? this.name,
        kind: kind,
        flows: flows ?? this.flows,
        valuePaise: valuePaise ?? this.valuePaise,
        valueAsOf: valueAsOf ?? this.valueAsOf,
        annualRatePercent: annualRatePercent ?? this.annualRatePercent,
        startDate: startDate ?? this.startDate,
        maturityDate: maturityDate ?? this.maturityDate,
        installmentPaise: installmentPaise ?? this.installmentPaise,
        sipPaise: clearSip ? 0 : sipPaise ?? this.sipPaise,
        sipDay: clearSip ? null : sipDay ?? this.sipDay,
        closed: closed ?? this.closed,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'flows': flows.map((item) => item.toJson()).toList(),
        if (valuePaise != null) 'valuePaise': valuePaise,
        if (valueAsOf != null) 'valueAsOf': valueAsOf!.toIso8601String(),
        if (annualRatePercent != 0) 'annualRatePercent': annualRatePercent,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (maturityDate != null)
          'maturityDate': maturityDate!.toIso8601String(),
        if (installmentPaise != 0) 'installmentPaise': installmentPaise,
        if (sipPaise != 0) 'sipPaise': sipPaise,
        if (sipDay != null) 'sipDay': sipDay,
        if (closed) 'closed': true,
      };

  factory Investment.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final rate = (json['annualRatePercent'] as num?)?.toDouble() ?? 0;
    final sipDay = json['sipDay'] as int?;
    if (name.trim().isEmpty ||
        rate < 0 ||
        rate > 100 ||
        (json['installmentPaise'] as int? ?? 0) < 0 ||
        (json['sipPaise'] as int? ?? 0) < 0 ||
        (sipDay != null && (sipDay < 1 || sipDay > 31))) {
      throw const FormatException('Invalid investment in backup.');
    }
    DateTime? date(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return Investment(
      id: json['id'] as String,
      name: name,
      kind: _enum(InvestmentKind.values, json['kind'], InvestmentKind.other),
      flows: [
        for (final item in (json['flows'] as List? ?? const []))
          InvestmentFlow.fromJson((item as Map).cast<String, dynamic>()),
      ],
      valuePaise: json['valuePaise'] as int?,
      valueAsOf: date('valueAsOf'),
      annualRatePercent: (json['annualRatePercent'] as num?)?.toDouble() ?? 0,
      startDate: date('startDate'),
      maturityDate: date('maturityDate'),
      installmentPaise: json['installmentPaise'] as int? ?? 0,
      sipPaise: json['sipPaise'] as int? ?? 0,
      sipDay: json['sipDay'] as int?,
      closed: json['closed'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Deposit maths (quarterly compounding, as Indian banks use)

double _years(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays /
    365;

/// Value of [principalPaise] after the time from [from] to [to] at
/// [annualRatePercent], compounded quarterly.
int fdValue(
    int principalPaise, double annualRatePercent, DateTime from, DateTime to) {
  if (!to.isAfter(from)) return principalPaise;
  final years = _years(from, to);
  return (principalPaise * math.pow(1 + annualRatePercent / 400, 4 * years))
      .round();
}

/// Monthly instalments from [start] up to and including [to], capped at
/// the maturity date.
List<DateTime> rdInstallments(DateTime start, DateTime? maturity, DateTime to) {
  final dates = <DateTime>[];
  for (var month = 0; month < 600; month++) {
    final monthStart = DateTime(start.year, start.month + month);
    final last = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    final date = DateTime(monthStart.year, monthStart.month,
        start.day > last ? last : start.day);
    if (date.isAfter(to)) break;
    if (maturity != null && !date.isBefore(maturity)) break;
    dates.add(date);
  }
  return dates;
}

/// RD value on [to]: each instalment grows from its own date.
int rdValue(int installmentPaise, double annualRatePercent, DateTime start,
        DateTime? maturity, DateTime to) =>
    rdInstallments(start, maturity, to).fold(
        0,
        (sum, date) =>
            sum + fdValue(installmentPaise, annualRatePercent, date, to));

/// Money put in, as dated flows: the deposit terms for FDs and RDs, the
/// recorded flows otherwise.
List<InvestmentFlow> investedFlows(Investment item, DateTime now) {
  final start = item.startDate;
  if (item.kind == InvestmentKind.recurringDeposit && start != null) {
    return [
      for (final date in rdInstallments(start, item.maturityDate, now))
        InvestmentFlow(
            id: date.toIso8601String(),
            amountPaise: item.installmentPaise,
            at: date),
    ];
  }
  return item.flows;
}

int investedPaise(Investment item, DateTime now) =>
    investedFlows(item, now).fold(0, (sum, flow) => sum + flow.amountPaise);

/// Value of a fixed deposit on [to], growing each dated flow from its own date.
int _fdFlowsValue(
        List<InvestmentFlow> flows, double annualRatePercent, DateTime to) =>
    flows
        .where((flow) => !flow.at.isAfter(to))
        .fold(0,
            (sum, flow) =>
                sum + fdValue(flow.amountPaise, annualRatePercent, flow.at, to));

/// Value today, with what it is based on.
({int paise, String basis})? currentValue(Investment item, DateTime now) {
  final start = item.startDate;
  final end = item.maturityDate != null && item.maturityDate!.isBefore(now)
      ? item.maturityDate!
      : now;
  if (item.kind == InvestmentKind.fixedDeposit && start != null) {
    return (
      paise: _fdFlowsValue(item.flows, item.annualRatePercent, end),
      basis: 'Worked out at ${item.annualRatePercent}% a year',
    );
  }
  if (item.kind == InvestmentKind.recurringDeposit && start != null) {
    return (
      paise: rdValue(item.installmentPaise, item.annualRatePercent, start,
          item.maturityDate, end),
      basis: 'Worked out at ${item.annualRatePercent}% a year',
    );
  }
  final value = item.valuePaise;
  if (value == null) return null;
  return (
    paise: value,
    basis: item.valueAsOf == null
        ? 'Value you entered'
        : 'Value you entered on ${formatDate(item.valueAsOf!)}',
  );
}

/// Maturity amount of a deposit, or null for other investments.
int? maturityValue(Investment item) {
  final start = item.startDate;
  final maturity = item.maturityDate;
  if (start == null || maturity == null) return null;
  return switch (item.kind) {
    InvestmentKind.fixedDeposit =>
      _fdFlowsValue(item.flows, item.annualRatePercent, maturity),
    InvestmentKind.recurringDeposit => rdValue(item.installmentPaise,
        item.annualRatePercent, start, maturity, maturity),
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// Returns

/// Annualised return (XIRR) of money put in ([flows], positive = invested)
/// against [finalValuePaise] on [on]. Null when it cannot be worked out,
/// e.g. no money in or under a week of history.
double? xirr(List<InvestmentFlow> flows, int finalValuePaise, DateTime on) {
  if (flows.isEmpty) return null;
  final first =
      flows.map((flow) => flow.at).reduce((a, b) => a.isBefore(b) ? a : b);
  if (on.difference(first).inDays < 7) return null;
  // Investor's view: money in is negative, the final value positive.
  final cash = [
    for (final flow in flows)
      (amount: -flow.amountPaise.toDouble(), at: flow.at),
    (amount: finalValuePaise.toDouble(), at: on),
  ];
  double npv(double rate) => cash.fold(
      0.0,
      (sum, item) =>
          sum + item.amount / math.pow(1 + rate, _years(first, item.at)));
  // Bisection between −99% and +1000% a year: slow but always converges.
  var low = -0.99;
  var high = 10.0;
  var lowValue = npv(low);
  if (lowValue.sign == npv(high).sign) return null;
  for (var i = 0; i < 200; i++) {
    final mid = (low + high) / 2;
    final value = npv(mid);
    if (value.abs() < 0.5) return mid;
    if (value.sign == lowValue.sign) {
      low = mid;
      lowValue = value;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2;
}

class PortfolioLine {
  const PortfolioLine(this.item, this.investedPaise, this.value, this.xirr);

  final Investment item;
  final int investedPaise;
  final ({int paise, String basis})? value;
  final double? xirr;

  int? get gainPaise => value == null ? null : value!.paise - investedPaise;
}

class Portfolio {
  const Portfolio(this.lines);

  final List<PortfolioLine> lines;

  int get investedPaise =>
      lines.fold(0, (sum, line) => sum + line.investedPaise);

  /// Lines without a known value count at what was invested.
  int get valuePaise => lines.fold(
      0, (sum, line) => sum + (line.value?.paise ?? line.investedPaise));

  int get gainPaise => valuePaise - investedPaise;

  /// Value by kind, largest first.
  List<({InvestmentKind kind, int paise})> get allocation {
    final totals = <InvestmentKind, int>{};
    for (final line in lines) {
      totals.update(line.item.kind,
          (value) => value + (line.value?.paise ?? line.investedPaise),
          ifAbsent: () => line.value?.paise ?? line.investedPaise);
    }
    return [
      for (final MapEntry(key: kind, value: paise) in totals.entries)
        (kind: kind, paise: paise),
    ]..sort((a, b) => b.paise.compareTo(a.paise));
  }
}

Portfolio portfolio(Iterable<Investment> items, DateTime now) => Portfolio([
      for (final item in items.where((item) => !item.closed))
        () {
          final value = currentValue(item, now);
          final flows = investedFlows(item, now);
          return PortfolioLine(
            item,
            flows.fold(0, (sum, flow) => sum + flow.amountPaise),
            value,
            value == null ? null : xirr(flows, value.paise, now),
          );
        }(),
    ]);

// ---------------------------------------------------------------------------
// SIP calendar and maturity reminders

/// SIP dates from [from] to [to] inclusive.
List<({DateTime day, Investment item})> sipDates(
    Iterable<Investment> items, DateTime from, DateTime to) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  final dates = <({DateTime day, Investment item})>[];
  for (final item in items.where(
      (item) => !item.closed && item.sipPaise > 0 && item.sipDay != null)) {
    for (var month = DateTime(start.year, start.month);
        !month.isAfter(end);
        month = DateTime(month.year, month.month + 1)) {
      final last = DateTime(month.year, month.month + 1, 0).day;
      final day = DateTime(
          month.year, month.month, item.sipDay! > last ? last : item.sipDay!);
      if (!day.isBefore(start) && !day.isAfter(end)) {
        dates.add((day: day, item: item));
      }
    }
  }
  dates.sort((a, b) => a.day.compareTo(b.day));
  return dates;
}

/// Reminders a week before and on the day a deposit matures, so the money
/// can be renewed or moved.
List<PlannedNotification> maturityReminders(
    Iterable<Investment> items, DateTime now,
    {Duration horizon = const Duration(days: 30)}) {
  final until = now.add(horizon);
  final reminders = <PlannedNotification>[];
  for (final item in items.where((item) => !item.closed)) {
    final maturity = item.maturityDate;
    if (maturity == null) continue;
    final due = DateTime(
        maturity.year, maturity.month, maturity.day, defaultReminderHour);
    final amount = maturityValue(item);
    final value = amount == null ? '' : ' · about ${formatMoney(amount)}';
    for (final (label, at, body) in [
      (
        'week',
        due.subtract(const Duration(days: 7)),
        'Matures ${formatShortDate(due)}$value'
      ),
      ('due', due, 'Matures today$value'),
    ]) {
      if (!at.isAfter(now) || at.isAfter(until)) continue;
      reminders.add(PlannedNotification(
        key: 'investment:${item.id}:${due.toIso8601String()}:$label',
        at: at,
        title: item.name,
        body: body,
        channel: ReminderChannel.bills,
        payload: 'investment:${item.id}',
      ));
    }
  }
  return reminders;
}
