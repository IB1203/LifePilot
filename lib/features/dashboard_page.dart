import 'package:flutter/material.dart';

import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/insights.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../core/task_logic.dart';
import '../ui/clock_widgets.dart';
import '../ui/forms.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'habits_tab.dart';
import 'weekly_review_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.store,
    required this.onNavigate,
    required this.onOpenClock,
    required this.onQuickAction,
    super.key,
  });

  final LifePilotStore store;
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenClock;
  final ValueChanged<String> onQuickAction;

  @override
  Widget build(BuildContext context) {
    final now = store.now();
    final plan = store.notificationPlan();
    final sections = store.settings.visibleSections;
    return ListView(
      padding: pagePadding,
      children: [
        FadeSlideIn(
          index: 0,
          child: _Header(
            store: store,
            next: nextReminder(plan),
            onOpenClock: onOpenClock,
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(index: 1, child: _QuickActions(onAction: onQuickAction)),
        if (store.pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: Text(
                    '${store.pending.length} ${store.pending.length == 1 ? 'transaction' : 'transactions'} to review'),
                subtitle: const Text(
                    'From recurring entries or bank SMS. Nothing is recorded until you approve.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onNavigate(1),
              ),
            ),
          ),
        for (var i = 0; i < sections.length; i++)
          FadeSlideIn(
            key: ValueKey(sections[i]),
            index: i + 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _section(context, sections[i], now, plan),
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: () => _customize(context),
            icon: const Icon(Icons.tune),
            label: const Text('Customize home'),
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String id, DateTime now,
          List<PlannedNotification> plan) =>
      switch (id) {
        'today' => _TodayOverview(
            store: store, now: now, plan: plan, onOpen: () => onNavigate(2)),
        'finance' =>
          _FinanceOverview(store: store, now: now, onOpen: () => onNavigate(1)),
        'planner' =>
          _Planner(store: store, now: now, onOpen: () => onNavigate(2)),
        'bills' => _Bills(store: store, now: now, onOpen: () => onNavigate(1)),
        'insights' => _Insights(store: store, now: now),
        'goals' => _Goals(store: store, onOpen: () => onNavigate(1)),
        'recent' =>
          _Recent(store: store, now: now, onOpen: () => onNavigate(1)),
        'habits' => _HabitsSection(store: store, now: now),
        'review' => _ReviewSection(store: store, now: now),
        _ => const SizedBox.shrink(),
      };

  Future<void> _customize(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _CustomizeSheet(store: store),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.store,
    required this.next,
    required this.onOpenClock,
  });

  final LifePilotStore store;
  final PlannedNotification? next;
  final VoidCallback onOpenClock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final use24h = store.settings.use24HourClock;
    final onPrimary = scheme.onPrimary;
    return Card(
      color: scheme.primary,
      child: InkWell(
        onTap: onOpenClock,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Tick(
            interval: const Duration(minutes: 1),
            now: store.now,
            builder: (context, now) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greetingFor(now),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: onPrimary.withValues(alpha: 0.9))),
                const SizedBox(height: 2),
                Text(formatLongDate(now),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: onPrimary.withValues(alpha: 0.8))),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Tick(
                        now: store.now,
                        interval: Duration(
                            seconds: store.settings.showSeconds ? 1 : 30),
                        builder: (context, now) => FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatTime(now,
                                use24h: use24h,
                                seconds: store.settings.showSeconds),
                            semanticsLabel:
                                'Current time ${formatTime(now, use24h: use24h)}',
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: onPrimary,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Icon(Icons.schedule,
                        color: onPrimary.withValues(alpha: 0.8)),
                  ],
                ),
                const SizedBox(height: 10),
                _NextUp(next: next, store: store, color: onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextUp extends StatelessWidget {
  const _NextUp({required this.next, required this.store, required this.color});

  final PlannedNotification? next;
  final LifePilotStore store;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: color.withValues(alpha: 0.92));
    final item = next;
    if (item == null) {
      return Text('No upcoming reminders', style: style);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Next: ${item.title} · ${formatDateTime(item.at, use24h: store.settings.use24HourClock)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Tick(
            now: store.now,
            builder: (context, now) {
              final left = item.at.difference(now);
              return Text(
                left.isNegative
                    ? 'now'
                    : left.inHours < 1
                        ? formatStopwatch(left.inMilliseconds, tenths: false)
                        : formatDuration(left),
                style: style?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onAction});

  final ValueChanged<String> onAction;

  static const actions = [
    ('expense', Icons.north_east, 'Expense'),
    ('income', Icons.south_west, 'Income'),
    ('task', Icons.add_task, 'Task'),
    ('reminder', Icons.alarm_add, 'Reminder'),
    ('note', Icons.sticky_note_2_outlined, 'Note'),
    ('focus', Icons.timer_outlined, 'Focus'),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: actions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final (id, icon, label) = actions[index];
            return ActionChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              onPressed: () => onAction(id),
            );
          },
        ),
      );
}

class _TodayOverview extends StatelessWidget {
  const _TodayOverview({
    required this.store,
    required this.now,
    required this.plan,
    required this.onOpen,
  });

  final LifePilotStore store;
  final DateTime now;
  final List<PlannedNotification> plan;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final buckets = TaskBuckets.from(store.tasks, now);
    final completedToday = store.tasks
        .where((task) =>
            task.completedAt != null && isSameDay(task.completedAt!, now))
        .length;
    final reminders = plan
        .where((item) =>
            item.channel != ReminderChannel.alarms &&
            item.at.isBefore(now.add(const Duration(hours: 24))))
        .length;
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: "Today's overview", action: 'Tasks', onAction: onOpen),
        TileGrid(
          children: [
            StatTile(
              label: 'Due today',
              value: '${buckets.today.length}',
              icon: Icons.today_outlined,
              onTap: onOpen,
            ),
            StatTile(
              label: 'Completed',
              value: '$completedToday',
              icon: Icons.task_alt,
              color: colors.income,
              onTap: onOpen,
            ),
            StatTile(
              label: 'Reminders · 24h',
              value: '$reminders',
              icon: Icons.notifications_outlined,
              color: colors.warning,
              onTap: onOpen,
            ),
            StatTile(
              label: 'Overdue',
              value: '${buckets.overdue.length}',
              icon: Icons.error_outline,
              color: buckets.overdue.isEmpty ? scheme.outline : scheme.error,
              onTap: onOpen,
            ),
          ],
        ),
      ],
    );
  }
}

class _FinanceOverview extends StatelessWidget {
  const _FinanceOverview(
      {required this.store, required this.now, required this.onOpen});

  final LifePilotStore store;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final summary = summarize(store.entries, monthRange(now));
    final budgets = monthlyBudgetTotals(store.budgets, store.entries, now);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: '${monthLabel(now)} finances',
            action: 'Finance',
            onAction: onOpen),
        Card(
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Net recorded cash flow',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(summary.netCashFlow),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: summary.netCashFlow < 0 ? colors.expense : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Figure(
                            label: 'Income',
                            value: formatMoney(summary.income),
                            color: colors.income,
                            icon: Icons.south_west),
                      ),
                      Expanded(
                        child: _Figure(
                            label: 'Expenses',
                            value: formatMoney(summary.expenses),
                            color: colors.expense,
                            icon: Icons.north_east),
                      ),
                    ],
                  ),
                  if (budgets.limitPaise > 0) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              'Budgets ${(budgets.utilization * 100).round()}% used',
                              style: theme.textTheme.labelLarge),
                        ),
                        Text(
                          budgets.remainingPaise >= 0
                              ? '${formatMoney(budgets.remainingPaise)} left'
                              : '${formatMoney(-budgets.remainingPaise)} over',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedBar(
                      value: budgets.utilization,
                      color: budgets.utilization > 1
                          ? theme.colorScheme.error
                          : budgets.utilization >= 0.8
                              ? colors.warning
                              : null,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Based only on entries you record. Not a bank balance or net worth.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      );
}

class _Planner extends StatelessWidget {
  const _Planner(
      {required this.store, required this.now, required this.onOpen});

  final LifePilotStore store;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final blocks = planDay(store.tasks, now).take(5).toList();
    final use24h = store.settings.use24HourClock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: 'Daily planner', action: 'All tasks', onAction: onOpen),
        if (blocks.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.event_available_outlined,
            title: 'Nothing planned for today',
            message:
                'Tasks due today or without a date appear here in a suggested order.',
            actionLabel: 'Add a task',
            onAction: () => showTaskForm(context, store, initialDue: now),
          )
        else
          CardList(
            indent: 72,
            children: [
              for (final block in blocks)
                ListTile(
                  leading: SizedBox(
                    width: 48,
                    child: Text(
                      formatTime(block.start, use24h: use24h),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: block.fixed ? FontWeight.w700 : null,
                          ),
                    ),
                  ),
                  title: Text(block.task.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${formatDuration(block.end.difference(block.start))}'
                    '${block.fixed ? '' : ' · suggested slot'}'
                    '${isOverdue(block.task, now) ? ' · overdue' : ''}',
                  ),
                  trailing: Checkbox(
                    value: false,
                    onChanged: (_) => store.toggleTask(block.task.id),
                  ),
                  onTap: () => showTaskForm(context, store, task: block.task),
                ),
            ],
          ),
      ],
    );
  }
}

class _Bills extends StatelessWidget {
  const _Bills({required this.store, required this.now, required this.onOpen});

  final LifePilotStore store;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final bills =
        upcomingBills(store.bills, now, withinDays: 14).take(3).toList();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: 'Upcoming bills', action: 'Bills', onAction: onOpen),
        if (bills.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.receipt_outlined,
            title: 'No bills due in the next two weeks',
            message:
                'Track rent, utilities and subscriptions to get reminders.',
            actionLabel: 'Add a bill',
            onAction: () => showBillForm(context, store),
          )
        else
          CardList(
            children: [
              for (final bill in bills)
                ListTile(
                  title: Text(bill.name),
                  subtitle: Text(
                    isBillOverdue(bill, now)
                        ? 'Overdue since ${formatShortDate(bill.nextDueAt)}'
                        : 'Due ${friendlyDay(bill.nextDueAt, now).toLowerCase()}',
                    style: isBillOverdue(bill, now)
                        ? TextStyle(color: scheme.error)
                        : null,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoney(bill.amountPaise),
                          style: Theme.of(context).textTheme.labelLarge),
                      IconButton(
                        tooltip: 'Mark ${bill.name} paid',
                        icon: const Icon(Icons.task_alt),
                        onPressed: () => showMarkPaidForm(context, store, bill),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({required this.store, required this.now});

  final LifePilotStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final insights = buildInsights(
      entries: store.entries,
      budgets: store.budgets,
      bills: store.bills,
      goals: store.goals,
      now: now,
    ).take(3).toList();
    if (insights.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Insights'),
        for (final insight in insights)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InsightCard(insight: insight),
          ),
      ],
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({required this.insight, super.key});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final (icon, color) = switch (insight.level) {
      InsightLevel.warning => (Icons.warning_amber_rounded, scheme.error),
      InsightLevel.attention => (Icons.flag_outlined, colors.warning),
      InsightLevel.info => (Icons.insights_outlined, scheme.primary),
    };
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: color),
          title: Text(insight.title,
              style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(insight.detail),
          childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Based on: ${insight.basis}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('For information only, not financial advice.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Goals extends StatelessWidget {
  const _Goals({required this.store, required this.onOpen});

  final LifePilotStore store;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (store.goals.isEmpty) return const SizedBox.shrink();
    final goals = store.goals.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: 'Savings goals', action: 'Goals', onAction: onOpen),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: goals.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final goal = goals[index];
              return SizedBox(
                width: 140,
                child: Card(
                  child: InkWell(
                    onTap: () => showContributionForm(context, store, goal),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          ProgressRing(
                            value: goal.progress,
                            child: Text('${(goal.progress * 100).round()}%',
                                style: Theme.of(context).textTheme.labelLarge),
                          ),
                          const SizedBox(height: 8),
                          Text(goal.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(
                              '${formatMoneyCompact(goal.remainingPaise)} to go',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.store, required this.now, required this.onOpen});

  final LifePilotStore store;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final recent = store.recentEntries.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: 'Recent transactions', action: 'See all', onAction: onOpen),
        if (recent.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.receipt_long_outlined,
            title: 'No transactions recorded',
            message: 'Add income or an expense to start your local record.',
            actionLabel: 'Add expense',
            onAction: () => showEntryForm(context, store),
          )
        else
          CardList(
            indent: 72,
            children: [
              for (final entry in recent)
                EntryTile(
                    entry: entry,
                    now: now,
                    onTap: () => showEntryForm(context, store, entry: entry)),
            ],
          ),
      ],
    );
  }
}

/// Transaction row shared by the dashboard and finance screens.
class EntryTile extends StatelessWidget {
  const EntryTile({
    required this.entry,
    required this.now,
    this.onTap,
    this.trailing,
    super.key,
  });

  final LedgerEntry entry;
  final DateTime now;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = entry.isIncome ? colors.income : colors.expense;
    final details = [
      entry.category,
      if (entry.merchant.isNotEmpty) entry.merchant,
      entry.paymentMethod,
      friendlyDay(entry.occurredAt, now),
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(entry.isIncome ? Icons.south_west : Icons.north_east,
            color: color, size: 20),
      ),
      title: Row(
        children: [
          Flexible(
            child:
                Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (entry.receiptPath != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.receipt_long_outlined,
                  size: 14,
                  semanticLabel: 'Has receipt',
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entry.isIncome ? '+' : '−'}${formatMoney(entry.amountPaise)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: entry.isIncome ? colors.income : null,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _CustomizeSheet extends StatefulWidget {
  const _CustomizeSheet({required this.store});

  final LifePilotStore store;

  @override
  State<_CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<_CustomizeSheet> {
  late final List<String> _order = [
    ...widget.store.settings.dashboardOrder.where(dashboardSectionIds.contains),
    ...dashboardSectionIds
        .where((id) => !widget.store.settings.dashboardOrder.contains(id)),
  ];
  late final Set<String> _hidden = {...widget.store.settings.hiddenSections};

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Customize home',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child:
                  Text('Drag to reorder. Turn off sections you do not need.'),
            ),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: true,
                onReorderItem: (from, to) => setState(() {
                  final item = _order.removeAt(from);
                  _order.insert(to, item);
                  _save();
                }),
                children: [
                  for (final id in _order)
                    SwitchListTile(
                      key: ValueKey(id),
                      title: Text(dashboardSectionLabel(id)),
                      value: !_hidden.contains(id),
                      onChanged: (value) => setState(() {
                        value ? _hidden.remove(id) : _hidden.add(id);
                        _save();
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );

  void _save() => widget.store.updateSettings(widget.store.settings.copyWith(
        dashboardOrder: List.of(_order),
        hiddenSections: _hidden.toList(),
      ));
}

class _HabitsSection extends StatelessWidget {
  const _HabitsSection({required this.store, required this.now});

  final LifePilotStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = store.habits
        .where((habit) => !habit.archived && habit.appliesOn(now))
        .toList();
    if (store.habits.where((habit) => !habit.archived).isEmpty) {
      return const SizedBox.shrink();
    }
    final done = today.where((habit) => habit.doneOn(now)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: today.isEmpty ? 'Habits' : 'Habits · $done of ${today.length}',
          action: 'All habits',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Habits')),
                body: AnimatedBuilder(
                  animation: store,
                  builder: (context, _) => HabitsTab(store: store),
                ),
              ),
            ),
          ),
        ),
        if (today.isEmpty)
          const Text('No habits are scheduled for today.')
        else
          for (final habit in today.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: HabitCard(
                  store: store, habit: habit, now: now, compact: true),
            ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.store, required this.now});

  final LifePilotStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // Most useful at the end and start of the week.
    final weekend = now.weekday == DateTime.sunday ||
        now.weekday == DateTime.monday ||
        now.weekday == DateTime.saturday;
    final review =
        buildWeeklyReview(store, previous: now.weekday == DateTime.monday);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: weekend ? scheme.tertiaryContainer : null,
      child: ListTile(
        leading: const Icon(Icons.insights_outlined),
        title: Text(now.weekday == DateTime.monday
            ? 'Your last week in review'
            : 'Your week so far'),
        subtitle: Text(
            '${review.tasksCompleted} tasks done · ${formatDuration(Duration(minutes: review.focusMinutes))} focus · ${formatMoney(review.summary.expenses)} spent'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => AnimatedBuilder(
                    animation: store,
                    builder: (context, _) => WeeklyReviewPage(store: store),
                  )),
        ),
      ),
    );
  }
}
