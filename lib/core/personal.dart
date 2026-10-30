export 'bank_sms.dart' show ParsedSms, parseBankSms, smsFingerprint;

import 'finance_calc.dart';
import 'formatters.dart';
import 'models.dart';
import 'task_logic.dart';

// ---------------------------------------------------------------------------
// Accounts

/// Recorded balance of an account: opening balance, plus income and minus
/// expenses linked to it, plus transfers in and minus transfers out. This is
/// only what the user recorded, not a balance read from a bank.
int accountBalance(
  Account account,
  Iterable<LedgerEntry> entries,
  Iterable<AccountTransfer> transfers,
) {
  var balance = account.openingBalancePaise;
  for (final entry in entries) {
    if (entry.accountId != account.id) continue;
    balance += entry.isIncome ? entry.amountPaise : -entry.amountPaise;
  }
  for (final transfer in transfers) {
    if (transfer.toAccountId == account.id) balance += transfer.amountPaise;
    if (transfer.fromAccountId == account.id) balance -= transfer.amountPaise;
  }
  return balance;
}

// ---------------------------------------------------------------------------
// Habits

/// Consecutive applicable days completed, ending today. If today is not done
/// yet, the streak still counts up to yesterday.
int habitStreak(Habit habit, DateTime now) {
  var day = dateOnly(now);
  if (!habit.doneOn(day)) day = DateTime(day.year, day.month, day.day - 1);
  var streak = 0;
  final start = dateOnly(habit.createdAt);
  for (var guard = 0; guard < 3660 && !day.isBefore(start); guard++) {
    if (habit.appliesOn(day)) {
      if (!habit.doneOn(day)) break;
      streak++;
    }
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// Share of applicable days completed over the last [days] days (including
/// today), counting only days since the habit was created.
double habitCompletion(Habit habit, DateTime now, {int days = 30}) {
  final today = dateOnly(now);
  final start = dateOnly(habit.createdAt);
  var applicable = 0;
  var done = 0;
  for (var offset = 0; offset < days; offset++) {
    final day = DateTime(today.year, today.month, today.day - offset);
    if (day.isBefore(start)) break;
    if (!habit.appliesOn(day)) continue;
    applicable++;
    if (habit.doneOn(day)) done++;
  }
  return applicable == 0 ? 0 : done / applicable;
}

// ---------------------------------------------------------------------------
// Weekly review

class WeeklyReview {
  const WeeklyReview({
    required this.range,
    required this.tasksCompleted,
    required this.tasksOverdue,
    required this.focusMinutes,
    required this.focusSessions,
    required this.habitRate,
    required this.summary,
    required this.previousExpenses,
    required this.topCategories,
    required this.budgets,
    required this.nextWeekBills,
    required this.nextWeekTasks,
  });

  final DateRange range;
  final int tasksCompleted;
  final int tasksOverdue;
  final int focusMinutes;
  final int focusSessions;

  /// Null when no habits apply this week.
  final double? habitRate;
  final PeriodSummary summary;
  final int previousExpenses;
  final Map<String, int> topCategories;
  final List<BudgetStatus> budgets;
  final List<Bill> nextWeekBills;
  final List<LocalTask> nextWeekTasks;

  /// Builds the review for the Monday-based week containing [now], or the
  /// previous week when [previousWeek] is true.
  factory WeeklyReview.build({
    required List<LedgerEntry> entries,
    required List<LocalTask> tasks,
    required List<FocusSession> sessions,
    required List<Habit> habits,
    required List<SpendingBudget> budgets,
    required List<Bill> bills,
    required DateTime now,
    bool previousWeek = false,
  }) {
    final range = weekRange(now, offset: previousWeek ? -1 : 0);
    final completions = tasks.fold<int>(
        0,
        (sum, task) =>
            sum + task.completionHistory.where(range.contains).length);
    final focus = sessions.where((session) =>
        session.kind == FocusKind.focus && range.contains(session.startedAt));
    var applicable = 0;
    var done = 0;
    final last =
        previousWeek ? range.end : DateTime(now.year, now.month, now.day + 1);
    for (final habit in habits.where((habit) => !habit.archived)) {
      for (var day = range.start;
          day.isBefore(last) && day.isBefore(range.end);
          day = DateTime(day.year, day.month, day.day + 1)) {
        if (day.isBefore(dateOnly(habit.createdAt)) || !habit.appliesOn(day)) {
          continue;
        }
        applicable++;
        if (habit.doneOn(day)) done++;
      }
    }
    final nextWeek = DateRange(range.end,
        DateTime(range.end.year, range.end.month, range.end.day + 7));
    return WeeklyReview(
      range: range,
      tasksCompleted: completions,
      tasksOverdue: tasks.where((task) => isOverdue(task, now)).length,
      focusMinutes:
          focus.fold<int>(0, (sum, session) => sum + session.actualSeconds) ~/
              60,
      focusSessions: focus.where((session) => session.completed).length,
      habitRate: applicable == 0 ? null : done / applicable,
      summary: summarize(entries, range),
      previousExpenses: sumEntries(entries,
          kind: EntryKind.expense, range: weekRange(range.start, offset: -1)),
      topCategories:
          Map.fromEntries(categoryTotals(entries, range).entries.take(3)),
      budgets: [
        for (final budget in budgets) budgetStatus(budget, entries, now),
      ]..sort((a, b) => b.utilization.compareTo(a.utilization)),
      nextWeekBills: bills
          .where((bill) => bill.active && nextWeek.contains(bill.nextDueAt))
          .toList()
        ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt)),
      nextWeekTasks: tasks
          .where((task) =>
              !task.isDone &&
              task.dueAt != null &&
              nextWeek.contains(task.dueAt!))
          .toList()
        ..sort(compareTasks),
    );
  }
}

// ---------------------------------------------------------------------------
// Category suggestions

const _stopWords = {
  'the',
  'and',
  'for',
  'from',
  'with',
  'paid',
  'payment',
  'upi',
  'via',
  'txn',
  'ref',
  'to',
  'at',
  'of',
  'on',
  'in',
  'a',
  'an',
  'by',
};

Iterable<String> _tokens(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.length >= 3 && !_stopWords.contains(word));

/// Suggests a category from past entries of the same kind whose description
/// or merchant share words with [text]. Returns null without a clear match.
String? suggestCategory(
  Iterable<LedgerEntry> entries,
  String text, {
  EntryKind kind = EntryKind.expense,
}) {
  final words = _tokens(text).toSet();
  if (words.isEmpty) return null;
  final scores = <String, double>{};
  for (final entry in entries) {
    if (entry.kind != kind) continue;
    final entryWords = {..._tokens(entry.title), ..._tokens(entry.merchant)};
    final overlap = words.intersection(entryWords).length;
    if (overlap == 0) continue;
    final exact = entry.title.trim().toLowerCase() ==
            text.trim().toLowerCase() ||
        (entry.merchant.isNotEmpty &&
            entry.merchant.trim().toLowerCase() == text.trim().toLowerCase());
    scores.update(entry.category, (value) => value + overlap + (exact ? 2 : 0),
        ifAbsent: () => overlap + (exact ? 2.0 : 0));
  }
  if (scores.isEmpty) return null;
  final ranked = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final best = ranked.first;
  // Require a clear winner so one stray match does not override the user.
  if (ranked.length > 1 && ranked[1].value >= best.value * 0.8) return null;
  return best.value >= 1 ? best.key : null;
}
