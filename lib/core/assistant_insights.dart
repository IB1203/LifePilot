import 'cash_plan.dart';
import 'debts.dart';
import 'finance_calc.dart';
import 'formatters.dart';
import 'investments.dart';
import 'local_store.dart';
import 'models.dart';
import 'money_glance.dart';

/// Answers to money questions: can I afford it, where can I cut back,
/// anything unusual, what is coming, debts, net worth, investments and
/// subscriptions. Each answer shows the numbers it used and what they are
/// based on; nothing is guessed and nothing is advice.

String _money(int paise) => formatMoney(paise, reveal: true);

/// Amounts written as "50000", "₹50,000", "50k", "1.5 lakh".
int? questionAmount(String text) {
  final scaled = RegExp(
          r'(\d+(?:\.\d+)?)\s*(k|thousand|lakhs?|lacs?|l|cr|crores?)\b',
          caseSensitive: false)
      .firstMatch(text);
  if (scaled != null) {
    final value = double.parse(scaled.group(1)!);
    final unit = scaled.group(2)!.toLowerCase();
    final multiplier = unit == 'k' || unit == 'thousand'
        ? 1000
        : unit.startsWith('c')
            ? 10000000
            : 100000;
    return (value * multiplier * 100).round();
  }
  final match = RegExp(r'(?:₹|rs\.?|inr)?\s*(\d[\d,]*(?:\.\d{1,2})?)',
          caseSensitive: false)
      .firstMatch(text);
  return match == null ? null : parseRupeesToPaise(match.group(1)!);
}

final _question = RegExp(
    r'\?\s*$|^(can|could|should|shall|will|would|where|what|how|when|which|is|am|do|does|show|list|tell|give|any)\b',
    caseSensitive: false);

/// The answer to a money question in [text], or null when it is not one.
String? answerMoneyQuestion(LifePilotStore store, String text) {
  final lower = text.toLowerCase().trim();
  final now = store.now();
  if (RegExp(r'\bafford\b|^(can|should|could) i (buy|get|spend|purchase)\b')
      .hasMatch(lower)) {
    final amount = questionAmount(lower);
    return amount == null
        ? 'How much does it cost? Try “Can I afford ₹50,000?”'
        : _afford(store, amount, now);
  }
  if (!_question.hasMatch(lower)) return null;
  if (RegExp(
          r'\b(cut back|cut down|cut costs|reduce|save more|spend less|overspend\w*|where .*\b(save|cut))\b')
      .hasMatch(lower)) {
    return _cutBack(store, now);
  }
  if (RegExp(r'\b(unusual|strange|suspicious|odd|weird|anomal\w*|fraud)\b')
      .hasMatch(lower)) {
    return _unusual(store, now);
  }
  if (RegExp(
          r'\b(forecast|month[- ]end|end of (the )?month|run out|run short|next \d+ days|cash ?flow forecast|will i have)\b')
      .hasMatch(lower)) {
    return _forecast(store, now);
  }
  if (RegExp(r'\b(debts?|loans?|emis?|owe|debt[- ]free|borrowed|lent)\b')
      .hasMatch(lower)) {
    return _debts(store, now);
  }
  if (RegExp(r'\bnet ?worth\b').hasMatch(lower)) return _netWorth(store, now);
  if (RegExp(r'\b(investments?|portfolio|sips?|mutual funds?|xirr|returns?)\b')
      .hasMatch(lower)) {
    return _investments(store, now);
  }
  if (RegExp(r'\bsubscriptions?\b').hasMatch(lower)) {
    return _subscriptions(store, now);
  }
  if (RegExp(r'\b(health score|financial health|how am i doing)\b')
      .hasMatch(lower)) {
    return _health(store, now);
  }
  return null;
}

String _afford(LifePilotStore store, int amount, DateTime now) {
  final available = availableMoney(
    bankBalances: store.bankBalances,
    accounts: store.accounts,
    entries: store.entries,
    transfers: store.transfers,
  );
  final upcoming =
      upcomingCommitments(bills: store.bills, rules: store.recurring, now: now)
          .fold(0, (sum, item) => sum + item.amountPaise);
  final past = summarize(
      store.entries,
      DateRange(
          DateTime(now.year, now.month - 3), DateTime(now.year, now.month)));
  final monthlySpend = past.expenses ~/ 3;
  final monthlySurplus = past.netCashFlow ~/ 3;
  final lines = <String>[];
  int? free;
  if (available != null) {
    free = available.paise - upcoming - monthlySpend;
    lines.addAll([
      'Available: ${_money(available.paise)} (${available.basis.toLowerCase()})',
      '− due in the next 30 days: ${_money(upcoming)}',
      if (monthlySpend > 0)
        '− one month of usual spending kept as a cushion: ${_money(monthlySpend)}',
      '= free to spend: ${_money(free)}',
    ]);
  } else {
    final month = summarize(store.entries, monthRange(now));
    if (month.income > 0) {
      free = month.netCashFlow - upcoming;
      lines.addAll([
        'Income this month: ${_money(month.income)}',
        '− spent so far: ${_money(month.expenses)}',
        '− due in the next 30 days: ${_money(upcoming)}',
        '= left: ${_money(free)}',
        '(Add an account or scan bank SMS for a real balance.)',
      ]);
    }
  }
  if (free == null) {
    return 'I cannot tell yet: there is no balance or income recorded. Add an account with its balance, scan bank SMS, or record your income.';
  }
  final verdict = amount <= free
      ? 'Yes, ${_money(amount)} looks affordable. You would still have ${_money(free - amount)} free after your bills and a month\'s cushion.'
      : amount <= free + monthlySpend
          ? 'Possible, but ${_money(amount)} would eat into your one-month cushion by ${_money(amount - free)}.'
          : 'Not comfortably right now: it is ${_money(amount - (free < 0 ? 0 : free))} more than you have free.';
  final saving = amount > free && monthlySurplus > 0
      ? '\n\nSaving ${_money(monthlySurplus)} a month (your average over the last three months), you could afford it in about ${((amount - (free < 0 ? 0 : free)) / monthlySurplus).ceil()} month(s). A savings goal can track it.'
      : '';
  return '$verdict\n\n${lines.join('\n')}$saving\n\nBased only on your records; not financial advice.';
}

String _cutBack(LifePilotStore store, DateTime now) {
  final ideas = <String>[];
  final changes = compareWithLastMonth(store.entries, now)
      .where((change) => change.changePaise >= 50000)
      .take(3);
  for (final change in changes) {
    ideas.add(
        '${change.category}: ${_money(change.thisMonthPaise)} so far vs ${_money(change.lastMonthPaise)} by this point last month (+${_money(change.changePaise)}).');
  }
  for (final budget in store.budgets) {
    final forecast = budgetForecast(budget, store.entries, now);
    if (forecast != null && forecast.willExceed) {
      ideas.add(
          '${forecast.category} budget: heading for ${_money(forecast.projectedPaise)} against ${_money(forecast.limitPaise)} at this pace.');
    }
  }
  final subs = subscriptions(store.bills, store.recurring);
  if (subs.isNotEmpty) {
    final monthly = subs.fold(0, (sum, item) => sum + item.monthlyPaise);
    ideas.add(
        'Subscriptions: ${_money(monthly)} a month (${_money(monthly * 12)} a year) across ${subs.length}. Biggest: ${subs.first.name}, ${_money(subs.first.monthlyPaise)}/month. Cancel any you no longer use.');
  }
  final top = categoryTotals(store.entries, monthRange(now)).entries.take(2);
  if (ideas.isEmpty && top.isNotEmpty) {
    ideas.add(
        'Nothing has jumped compared with last month. Your largest categories this month are ${top.map((item) => '${item.key} (${_money(item.value)})').join(' and ')}; small cuts there matter most.');
  }
  if (ideas.isEmpty) {
    return 'Record a few weeks of expenses and I can point out where spending has grown.';
  }
  return 'Where you could cut back:\n${ideas.map((idea) => '• $idea').join('\n')}\n\nBased on your recorded expenses, budgets and subscriptions.';
}

String _unusual(LifePilotStore store, DateTime now) {
  final since = now.subtract(const Duration(days: 30));
  final findings = <String>[];
  for (final entry in store.entries.where((entry) =>
      entry.kind == EntryKind.expense && entry.occurredAt.isAfter(since))) {
    final history = store.entries
        .where((item) =>
            item.kind == EntryKind.expense &&
            item.category == entry.category &&
            item.id != entry.id &&
            item.occurredAt.isBefore(entry.occurredAt))
        .map((item) => item.amountPaise)
        .toList()
      ..sort();
    if (history.length < 5) continue;
    final median = history[history.length ~/ 2];
    if (entry.amountPaise >= median * 3 &&
        entry.amountPaise - median >= 50000) {
      findings.add(
          '“${entry.title}” ${_money(entry.amountPaise)} on ${formatDate(entry.occurredAt)}: ${(entry.amountPaise / median).toStringAsFixed(1)}× your usual ${entry.category} expense (${_money(median)}).');
    }
  }
  for (final draft
      in store.pending.where((draft) => draft.warning.isNotEmpty)) {
    findings.add(
        'Waiting for review: “${draft.entry.title}” ${_money(draft.entry.amountPaise)}. ${draft.warning.split('. ').first}.');
  }
  if (store.suspiciousSms.isNotEmpty) {
    findings.add(
        '${store.suspiciousSms.length} message${store.suspiciousSms.length == 1 ? '' : 's'} held back as possible scams (Finance › Recurring).');
  }
  if (findings.isEmpty) {
    return 'Nothing unusual in the last 30 days: no expense was more than three times your usual amount for its category, and no flagged bank messages.';
  }
  return 'Worth a look:\n${findings.take(6).map((item) => '• $item').join('\n')}\n\nIf you did not make a payment, call your bank and the 1930 cyber-fraud helpline.';
}

String _forecast(LifePilotStore store, DateTime now) {
  final month = monthForecast(
      entries: store.entries,
      bills: store.bills,
      rules: store.recurring,
      now: now);
  final start = availableMoney(
    bankBalances: store.bankBalances,
    accounts: store.accounts,
    entries: store.entries,
    transfers: store.transfers,
  );
  final cash = forecastCash(
    startPaise: start?.paise,
    entries: store.entries,
    bills: store.bills,
    rules: store.recurring,
    now: now,
    investments: store.investments,
  );
  final shortfall = cash.shortfallDay;
  return [
    'By the end of ${monthLabel(now)} you are likely to have spent about ${_money(month.projectedPaise)}:',
    '${_money(month.spentPaise)} so far + ${_money(month.dailyPacePaise)}/day for ${month.daysLeft} days + ${_money(month.committedPaise)} of bills and recurring payments still due.',
    '',
    if (start != null) ...[
      'Next 60 days, starting from ${_money(start.paise)}: lowest ${_money(cash.lowestPaise)} on ${formatDate(cash.lowestDay)}, ${_money(cash.endPaise)} at the end.',
      if (shortfall != null)
        'Warning: money may run short around ${formatDate(shortfall)}.',
    ] else
      'Next 60 days, as a change from today: lowest ${_money(cash.lowestPaise)} on ${formatDate(cash.lowestDay)}. Add a balance to see real amounts.',
    '',
    'Based on your bills, recurring entries, SIPs and the last 30 days of spending. See Finance › Plan.',
  ].join('\n');
}

String _debts(LifePilotStore store, DateTime now) {
  final open = store.debts.where((debt) => !debt.closed).toList();
  if (open.isEmpty) {
    return 'No open loans or debts recorded. Add them under Finance › Debts.';
  }
  final totals = debtTotals(store.debts, asOf: now);
  final lines = <String>[
    'You owe ${_money(totals.owedPaise)}; others owe you ${_money(totals.lentPaise)}.',
    if (totals.monthlyPaise > 0)
      'Monthly payments: ${_money(totals.monthlyPaise)}.',
  ];
  for (final debt in open) {
    final status = debtStatus(debt, asOf: now);
    if (debt.owedToMe) {
      lines.add(
          '• ${debt.name}${debt.counterparty.isEmpty ? '' : ' (${debt.counterparty})'}: ${_money(status.outstandingPaise)} to get back.');
      continue;
    }
    final monthly = monthlyPaymentFor(debt, status.outstandingPaise);
    final plan =
        payoff(status.outstandingPaise, debt.annualRatePercent, monthly, now);
    lines.add('• ${debt.name}: ${_money(status.outstandingPaise)} left'
        '${plan == null ? (monthly > 0 ? ' — the payment does not cover the interest' : '') : ', cleared by ${monthLabel(plan.closesOn)} (${_money(plan.interestPaise)} more interest)'}.');
  }
  final avalanche =
      debtFreePlan(store.debts, PayoffStrategy.avalanche, asOf: now);
  final snowball =
      debtFreePlan(store.debts, PayoffStrategy.snowball, asOf: now);
  if (avalanche != null && snowball != null && avalanche.months > 0) {
    final cheaper = avalanche.interestPaise <= snowball.interestPaise
        ? (name: 'highest interest first', plan: avalanche)
        : (name: 'smallest balance first', plan: snowball);
    lines.add(
        '\nDebt-free in ${cheaper.plan.months} months paying ${cheaper.name} (${_money(cheaper.plan.interestPaise)} interest). Any extra payment shortens it — try the planner in Finance › Debts.');
  }
  return lines.join('\n');
}

String _netWorth(LifePilotStore store, DateTime now) {
  final debts = debtTotals(store.debts, asOf: now);
  final invested = portfolio(store.investments, now).valuePaise;
  final worth = netWorth(
    accounts: store.accounts,
    entries: store.entries,
    transfers: store.transfers,
    goals: store.goals,
    debtsPaise: debts.owedPaise,
    lentPaise: debts.lentPaise,
    investmentsPaise: invested,
  );
  if (worth == null) {
    return 'Add your accounts, savings, investments and loans and I can work out your net worth.';
  }
  return 'Net worth: ${_money(worth.paise)}\n'
      'Made up of: ${worth.basis}.'
      '${invested > 0 ? '\nInvestments: ${_money(invested)} (values you entered).' : ''}'
      '${debts.owedPaise > 0 ? '\nLoans and money owed: −${_money(debts.owedPaise)}.' : ''}\n'
      'Recorded balances only, not live bank data.';
}

String _investments(LifePilotStore store, DateTime now) {
  final book = portfolio(store.investments, now);
  if (book.lines.isEmpty) {
    return 'No investments recorded. Add them under Finance › Investments.';
  }
  final gain = book.gainPaise;
  final sip = store.investments
      .where((item) => !item.closed)
      .fold(0, (sum, item) => sum + item.sipPaise);
  return [
    'Invested ${_money(book.investedPaise)}, now worth ${_money(book.valuePaise)} '
        '(${gain >= 0 ? 'gain' : 'loss'} ${_money(gain.abs())}).',
    for (final line in book.lines)
      '• ${line.item.name}: ${line.value == null ? 'no value yet' : _money(line.value!.paise)}'
          '${line.xirr == null ? '' : ', ${(line.xirr! * 100).toStringAsFixed(1)}% a year'}',
    if (sip > 0) 'SIPs: ${_money(sip)} a month.',
    'Values are what you entered or worked out from deposit rates, not live prices.',
  ].join('\n');
}

String _subscriptions(LifePilotStore store, DateTime now) {
  final subs = subscriptions(store.bills, store.recurring);
  if (subs.isEmpty) {
    return 'No subscriptions found. Add them as bills (type Subscription) or recurring expenses.';
  }
  final monthly = subs.fold(0, (sum, item) => sum + item.monthlyPaise);
  final increases = priceIncreases(
      bills: store.bills,
      rules: store.recurring,
      entries: store.entries,
      now: now);
  return [
    'Subscriptions: ${_money(monthly)} a month, ${_money(monthly * 12)} a year.',
    for (final item in subs)
      '• ${item.name}: ${_money(item.monthlyPaise)}/month',
    for (final change in increases)
      '↑ ${change.name} went up ${change.percent}% (${_money(change.oldPaise)} → ${_money(change.newPaise)}).',
  ].join('\n');
}

String _health(LifePilotStore store, DateTime now) {
  final score = healthScore(
    entries: store.entries,
    budgets: store.budgets,
    bills: store.bills,
    goals: store.goals,
    now: now,
    monthlyDebtPaise: debtTotals(store.debts, asOf: now).monthlyPaise,
  );
  if (score == null) {
    return 'Not enough data for a health score yet. It needs at least two of: three months of income, a monthly budget, bill payments, or debts with EMIs.';
  }
  return [
    'Financial health: ${score.value}/100 (${score.label}).',
    for (final factor in score.factors)
      '• ${factor.name} ${(factor.score * 100).round()}%: ${factor.detail}${factor.tip.isEmpty ? '' : ' ${factor.tip}'}',
  ].join('\n');
}
