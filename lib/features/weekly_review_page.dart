import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/personal.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

WeeklyReview buildWeeklyReview(LifePilotStore store, {bool previous = false}) =>
    WeeklyReview.build(
      entries: store.entries,
      tasks: store.tasks,
      sessions: store.focusSessions,
      habits: store.habits,
      budgets: store.budgets,
      bills: store.bills,
      now: store.now(),
      previousWeek: previous,
    );

class WeeklyReviewPage extends StatefulWidget {
  const WeeklyReviewPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<WeeklyReviewPage> createState() => _WeeklyReviewPageState();
}

class _WeeklyReviewPageState extends State<WeeklyReviewPage> {
  // On Sunday and Monday the finished week is the more useful default.
  late bool _previous = widget.store.now().weekday == DateTime.monday;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final review = buildWeeklyReview(store, previous: _previous);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final change = review.summary.expenses - review.previousExpenses;
    final lastDay = review.range.end.subtract(const Duration(days: 1));
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly review')),
      body: ListView(
        padding: pagePadding,
        children: [
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Last week')),
              ButtonSegment(value: false, label: Text('This week')),
            ],
            selected: {_previous},
            onSelectionChanged: (value) =>
                setState(() => _previous = value.first),
          ),
          const SizedBox(height: 8),
          Text(
              '${formatShortDate(review.range.start)} – ${formatDate(lastDay)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium),
          const SectionHeader(title: 'Productivity'),
          TileGrid(children: [
            StatTile(
              label: 'Tasks completed',
              value: '${review.tasksCompleted}',
              icon: Icons.task_alt,
              color: colors.income,
            ),
            StatTile(
              label: 'Overdue now',
              value: '${review.tasksOverdue}',
              icon: Icons.error_outline,
              color: review.tasksOverdue == 0
                  ? theme.colorScheme.outline
                  : theme.colorScheme.error,
            ),
            StatTile(
              label: 'Focus time',
              value: formatDuration(Duration(minutes: review.focusMinutes)),
              icon: Icons.self_improvement,
              caption: '${review.focusSessions} completed sessions',
            ),
            StatTile(
              label: 'Habits',
              value: review.habitRate == null
                  ? '—'
                  : '${(review.habitRate! * 100).round()}%',
              icon: Icons.local_fire_department_outlined,
              color: colors.warning,
              caption: review.habitRate == null
                  ? 'No habits scheduled'
                  : 'of check-ins done',
            ),
          ]),
          const SectionHeader(title: 'Money'),
          TileGrid(children: [
            StatTile(
              label: 'Spent',
              value: formatMoney(review.summary.expenses),
              icon: Icons.north_east,
              color: colors.expense,
              caption: review.previousExpenses == 0 &&
                      review.summary.expenses == 0
                  ? null
                  : change == 0
                      ? 'Same as the week before'
                      : '${formatMoney(change.abs())} ${change > 0 ? 'more' : 'less'} than the week before',
            ),
            StatTile(
              label: 'Income',
              value: formatMoney(review.summary.income),
              icon: Icons.south_west,
              color: colors.income,
            ),
          ]),
          if (review.topCategories.isNotEmpty) ...[
            const SizedBox(height: 10),
            CardList(children: [
              for (final MapEntry(key: name, value: amount)
                  in review.topCategories.entries)
                ListTile(
                  dense: true,
                  title: Text(name),
                  trailing: Text(formatMoney(amount)),
                ),
            ]),
          ],
          if (review.budgets.isNotEmpty) ...[
            const SectionHeader(title: 'Budgets right now'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final status in review.budgets.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Text(status.budget.category)),
                              Text('${status.utilizationPercent}%'),
                            ]),
                            const SizedBox(height: 4),
                            AnimatedBar(
                              value: status.utilization / 100,
                              color: status.isOver
                                  ? theme.colorScheme.error
                                  : status.isApproaching
                                      ? colors.warning
                                      : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SectionHeader(title: 'Coming up next week'),
          if (review.nextWeekBills.isEmpty && review.nextWeekTasks.isEmpty)
            const EmptyState(
              compact: true,
              icon: Icons.event_available_outlined,
              title: 'Nothing scheduled',
              message: 'No bills or dated tasks fall in the following week.',
            )
          else
            CardList(children: [
              for (final bill in review.nextWeekBills)
                ListTile(
                  leading: Icon(Icons.receipt_outlined, color: colors.warning),
                  title: Text(bill.name),
                  subtitle: Text('Bill due ${formatDate(bill.nextDueAt)}'),
                  trailing: Text(formatMoney(bill.amountPaise)),
                ),
              for (final task in review.nextWeekTasks.take(8))
                ListTile(
                  leading: const Icon(Icons.task_alt),
                  title: Text(task.title),
                  subtitle: Text('Due ${formatDate(task.dueAt!)}'),
                ),
            ]),
          const SizedBox(height: 12),
          Text('Everything here comes from your own records on this device.',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
