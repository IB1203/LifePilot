import 'dart:math' as math;

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// Loans, credit card dues, and money borrowed from or lent to people.
/// Interest is simple interest on the reducing balance, accrued daily
/// between payments (actual days / 365), which is how Indian lenders
/// compute EMI loans to within a rupee or two a month.

enum DebtKind { loan, creditCard, borrowed, lent }

extension DebtKindLabel on DebtKind {
  String get label => switch (this) {
        DebtKind.loan => 'Loan',
        DebtKind.creditCard => 'Credit card',
        DebtKind.borrowed => 'Borrowed from someone',
        DebtKind.lent => 'Lent to someone',
      };
}

class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.amountPaise,
    required this.at,
    this.note = '',
  });

  final String id;
  final int amountPaise;
  final DateTime at;
  final String note;

  Map<String, Object?> toJson() => {
        'id': id,
        'amountPaise': amountPaise,
        'at': at.toIso8601String(),
        if (note.isNotEmpty) 'note': note,
      };

  factory DebtPayment.fromJson(Map<String, dynamic> json) {
    final amount = json['amountPaise'] as int;
    if (amount <= 0) throw const FormatException('Invalid debt payment.');
    return DebtPayment(
      id: json['id'] as String,
      amountPaise: amount,
      at: DateTime.parse(json['at'] as String),
      note: json['note'] as String? ?? '',
    );
  }
}

class Debt {
  const Debt({
    required this.id,
    required this.name,
    required this.kind,
    required this.openingPaise,
    required this.startDate,
    this.annualRatePercent = 0,
    this.emiPaise = 0,
    this.counterparty = '',
    this.payments = const [],
    this.closed = false,
    this.dueAt,
  });

  final String id;
  final String name;
  final DebtKind kind;

  /// Amount outstanding on [startDate]: the loan amount for a new loan, or
  /// what is left today for one taken earlier.
  final int openingPaise;
  final DateTime startDate;

  /// Yearly interest rate in percent, e.g. 10.5. Zero for most personal
  /// loans between friends.
  final double annualRatePercent;

  /// Monthly instalment; zero when there is no fixed EMI.
  final int emiPaise;

  /// The person, for borrowed and lent money.
  final String counterparty;
  final List<DebtPayment> payments;
  final bool closed;

  /// When money lent is expected back. Used for overdue reminders.
  final DateTime? dueAt;

  /// Money someone owes the user, rather than the other way round.
  bool get owedToMe => kind == DebtKind.lent;

  /// Interest-free lending: money lent to someone with no interest charged.
  bool get isInterestFreeLending => kind == DebtKind.lent && annualRatePercent <= 0;

  Debt copyWith({
    String? name,
    DebtKind? kind,
    int? openingPaise,
    DateTime? startDate,
    double? annualRatePercent,
    int? emiPaise,
    String? counterparty,
    List<DebtPayment>? payments,
    bool? closed,
    DateTime? dueAt,
    bool clearDueDate = false,
  }) =>
      Debt(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        openingPaise: openingPaise ?? this.openingPaise,
        startDate: startDate ?? this.startDate,
        annualRatePercent: annualRatePercent ?? this.annualRatePercent,
        emiPaise: emiPaise ?? this.emiPaise,
        counterparty: counterparty ?? this.counterparty,
        payments: payments ?? this.payments,
        closed: closed ?? this.closed,
        dueAt: clearDueDate ? null : dueAt ?? this.dueAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'openingPaise': openingPaise,
        'startDate': startDate.toIso8601String(),
        'annualRatePercent': annualRatePercent,
        'emiPaise': emiPaise,
        if (counterparty.isNotEmpty) 'counterparty': counterparty,
        'payments': payments.map((item) => item.toJson()).toList(),
        if (closed) 'closed': true,
        if (dueAt != null) 'dueAt': dueAt!.toIso8601String(),
      };

  factory Debt.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final opening = json['openingPaise'] as int;
    final rate = (json['annualRatePercent'] as num?)?.toDouble() ?? 0;
    if (name.trim().isEmpty || opening <= 0 || rate < 0 || rate > 100) {
      throw const FormatException('Invalid debt in backup.');
    }
    return Debt(
      id: json['id'] as String,
      name: name,
      kind: _enum(DebtKind.values, json['kind'], DebtKind.loan),
      openingPaise: opening,
      startDate: DateTime.parse(json['startDate'] as String),
      annualRatePercent: rate,
      emiPaise: json['emiPaise'] as int? ?? 0,
      counterparty: json['counterparty'] as String? ?? '',
      payments: [
        for (final item in (json['payments'] as List? ?? const []))
          DebtPayment.fromJson((item as Map).cast<String, dynamic>()),
      ],
      closed: json['closed'] as bool? ?? false,
      dueAt: json['dueAt'] is String
          ? DateTime.tryParse(json['dueAt'] as String)
          : null,
    );
  }
}

/// Interest-free loans that are still outstanding past their due date.
List<({Debt debt, int outstandingPaise, int daysOverdue})> overdueLending(
  Iterable<Debt> debts,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final result = <({Debt debt, int outstandingPaise, int daysOverdue})>[];
  for (final debt in debts) {
    if (!debt.owedToMe || debt.closed || debt.dueAt == null) continue;
    final outstanding = debtStatus(debt, asOf: now).outstandingPaise;
    if (outstanding <= 0) continue;
    final due = DateTime(debt.dueAt!.year, debt.dueAt!.month, debt.dueAt!.day);
    if (!due.isBefore(today)) continue;
    result.add((
      debt: debt,
      outstandingPaise: outstanding,
      daysOverdue: today.difference(due).inDays,
    ));
  }
  result.sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));
  return result;
}

// ---------------------------------------------------------------------------
// Where a debt stands

class DebtStatus {
  const DebtStatus({
    required this.outstandingPaise,
    required this.interestPaidPaise,
    required this.principalPaidPaise,
  });

  /// Amount still owed, including interest accrued up to the status date.
  final int outstandingPaise;
  final int interestPaidPaise;
  final int principalPaidPaise;
}

int _interest(int balance, double ratePercent, DateTime from, DateTime to) {
  if (ratePercent <= 0 || balance <= 0 || !to.isAfter(from)) return 0;
  final days = DateTime.utc(to.year, to.month, to.day)
      .difference(DateTime.utc(from.year, from.month, from.day))
      .inDays;
  return (balance * ratePercent / 100 * days / 365).round();
}

/// Applies the payments in date order: each first pays the interest that
/// built up since the previous one, then reduces the principal. Interest
/// accrued since the last payment is added to the outstanding amount up to
/// [asOf] (default: now).
DebtStatus debtStatus(Debt debt, {DateTime? asOf}) {
  final payments = [...debt.payments]..sort((a, b) => a.at.compareTo(b.at));
  var balance = debt.openingPaise;
  var since = debt.startDate;
  var interestPaid = 0;
  var principalPaid = 0;
  for (final payment in payments) {
    final interest =
        _interest(balance, debt.annualRatePercent, since, payment.at);
    final toInterest = math.min(interest, payment.amountPaise);
    final toPrincipal = math.min(balance, payment.amountPaise - toInterest);
    // Interest not covered by the payment is added to what is owed.
    balance = balance - toPrincipal + (interest - toInterest);
    interestPaid += toInterest;
    principalPaid += toPrincipal;
    since = payment.at;
  }
  if (!debt.closed && balance > 0) {
    balance +=
        _interest(balance, debt.annualRatePercent, since, asOf ?? DateTime.now());
  }
  return DebtStatus(
    outstandingPaise: balance,
    interestPaidPaise: interestPaid,
    principalPaidPaise: principalPaid,
  );
}

/// Monthly instalment that repays [principalPaise] in [months] at
/// [annualRatePercent]: P·r·(1+r)^n / ((1+r)^n − 1), rounded up.
int emiFor(int principalPaise, double annualRatePercent, int months) {
  if (months <= 0) return principalPaise;
  if (annualRatePercent <= 0) return (principalPaise / months).ceil();
  final r = annualRatePercent / 1200;
  final factor = math.pow(1 + r, months);
  return (principalPaise * r * factor / (factor - 1)).ceil();
}

class Payoff {
  const Payoff(
      {required this.months,
      required this.interestPaise,
      required this.closesOn});

  final int months;
  final int interestPaise;
  final DateTime closesOn;
}

/// Months and total interest to clear [balancePaise] paying
/// [monthlyPaise] a month from [from], interest charged monthly. Null when
/// the payment does not cover the interest (the debt would never close)
/// or it would take more than 50 years.
Payoff? payoff(int balancePaise, double annualRatePercent, int monthlyPaise,
    DateTime from) {
  if (balancePaise <= 0) {
    return Payoff(months: 0, interestPaise: 0, closesOn: from);
  }
  if (monthlyPaise <= 0) return null;
  final r = annualRatePercent / 1200;
  var balance = balancePaise.toDouble();
  var interest = 0.0;
  for (var month = 1; month <= 600; month++) {
    final charge = balance * r;
    if (monthlyPaise <= charge) return null;
    interest += charge;
    balance = balance + charge - monthlyPaise;
    if (balance <= 0.5) {
      return Payoff(
        months: month,
        interestPaise: interest.round(),
        closesOn: DateTime(from.year, from.month + month, from.day),
      );
    }
  }
  return null;
}

/// What the user pays each month on a debt: the EMI, or for a card without
/// one the usual minimum due (5% of the balance, at least ₹200).
int monthlyPaymentFor(Debt debt, int outstandingPaise) {
  if (debt.emiPaise > 0) return debt.emiPaise;
  if (debt.kind == DebtKind.creditCard && outstandingPaise > 0) {
    return math.min(outstandingPaise, math.max(20000, outstandingPaise ~/ 20));
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Debt-free planner

enum PayoffStrategy { snowball, avalanche }

extension PayoffStrategyLabel on PayoffStrategy {
  String get label => switch (this) {
        PayoffStrategy.snowball => 'Smallest balance first (snowball)',
        PayoffStrategy.avalanche => 'Highest interest first (avalanche)',
      };
}

class DebtFreePlan {
  const DebtFreePlan({
    required this.months,
    required this.interestPaise,
    required this.order,
  });

  final int months;
  final int interestPaise;

  /// Debt names in the order they are cleared.
  final List<String> order;
}

/// Simulates paying every open debt the user owes: each month interest is
/// charged, every debt gets its usual payment, and [extraPaise] plus the
/// payments freed by cleared debts go to the target debt chosen by
/// [strategy]. Null when the payments cannot outpace the interest within
/// 50 years.
DebtFreePlan? debtFreePlan(
  Iterable<Debt> debts,
  PayoffStrategy strategy, {
  int extraPaise = 0,
  DateTime? asOf,
}) {
  final open = [
    for (final debt in debts)
      if (!debt.closed && !debt.owedToMe)
        (
          debt: debt,
          balance:
              debtStatus(debt, asOf: asOf).outstandingPaise.toDouble()
        ),
  ].where((item) => item.balance > 0).toList();
  if (open.isEmpty) {
    return const DebtFreePlan(months: 0, interestPaise: 0, order: []);
  }
  final names = [for (final item in open) item.debt.name];
  final rates = [for (final item in open) item.debt.annualRatePercent / 1200];
  final balances = [for (final item in open) item.balance];
  final minimums = [
    for (final item in open)
      monthlyPaymentFor(item.debt, item.balance.round()).toDouble(),
  ];
  final budget = minimums.fold(0.0, (sum, value) => sum + value) + extraPaise;
  if (budget <= 0) return null;
  var interest = 0.0;
  var previousTotal = balances.fold(0.0, (sum, value) => sum + value);
  final order = <String>[];
  for (var month = 1; month <= 600; month++) {
    var available = budget;
    for (var i = 0; i < balances.length; i++) {
      if (balances[i] <= 0) continue;
      final charge = balances[i] * rates[i];
      interest += charge;
      balances[i] += charge;
    }
    // Usual payments first.
    for (var i = 0; i < balances.length; i++) {
      if (balances[i] <= 0) continue;
      final pay = math.min(minimums[i], balances[i]);
      balances[i] -= pay;
      available -= pay;
    }
    // Then everything left to targets, in strategy order.
    final targets = [
      for (var i = 0; i < balances.length; i++)
        if (balances[i] > 0) i,
    ]..sort((a, b) => strategy == PayoffStrategy.snowball
        ? balances[a].compareTo(balances[b])
        : rates[b] != rates[a]
            ? rates[b].compareTo(rates[a])
            : balances[a].compareTo(balances[b]));
    for (final i in targets) {
      if (available <= 0) break;
      final pay = math.min(available, balances[i]);
      balances[i] -= pay;
      available -= pay;
    }
    for (var i = 0; i < balances.length; i++) {
      if (balances[i] <= 0.5 && !order.contains(names[i])) {
        balances[i] = 0;
        order.add(names[i]);
      }
    }
    if (order.length == names.length) {
      return DebtFreePlan(
          months: month, interestPaise: interest.round(), order: order);
    }
    // Payments not even covering the interest: it would never clear.
    final total = balances.fold(0.0, (sum, value) => sum + value);
    if (total >= previousTotal - 0.5) return null;
    previousTotal = total;
  }
  return null;
}

/// Totals for the summary: what the user owes, what is owed to them, and
/// the monthly payments on their debts.
({int owedPaise, int lentPaise, int monthlyPaise}) debtTotals(
    Iterable<Debt> debts, {DateTime? asOf}) {
  var owed = 0;
  var lent = 0;
  var monthly = 0;
  for (final debt in debts.where((debt) => !debt.closed)) {
    final outstanding = debtStatus(debt, asOf: asOf).outstandingPaise;
    if (debt.owedToMe) {
      lent += outstanding;
    } else {
      owed += outstanding;
      if (outstanding > 0) monthly += monthlyPaymentFor(debt, outstanding);
    }
  }
  return (owedPaise: owed, lentPaise: lent, monthlyPaise: monthly);
}
