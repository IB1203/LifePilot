import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/csv.dart';
import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/insights.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../services/device_security.dart';
import '../ui/charts.dart';
import '../ui/forms.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'dashboard_page.dart' show EntryTile, InsightCard;
import 'lock_screen.dart' show confirmIdentity;
import 'money_extras.dart';
import 'upi_page.dart';

class FinancePage extends StatelessWidget {
  const FinancePage({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 9,
        child: Column(
          children: [
            Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Activity'),
                  Tab(text: 'Budgets'),
                  Tab(text: 'Bills'),
                  Tab(text: 'Recurring'),
                  Tab(text: 'Accounts'),
                  Tab(text: 'Goals'),
                  Tab(text: 'Reports'),
                  Tab(text: 'UPI'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(store: store),
                  _ActivityTab(store: store),
                  _BudgetsTab(store: store),
                  _BillsTab(store: store),
                  RecurringTab(store: store),
                  AccountsTab(store: store),
                  _GoalsTab(store: store),
                  _ReportsTab(store: store),
                  UpiTab(store: store),
                ],
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Overview

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final now = store.now();
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final month = summarize(store.entries, monthRange(now));
    final budgets = monthlyBudgetTotals(store.budgets, store.entries, now);
    final categories = categoryTotals(store.entries, monthRange(now));
    final current = DateRange(monthRange(now).start, now);
    final previousMonth = DateTime(now.year, now.month - 1);
    final previousDays = DateTime(now.year, now.month, 0).day;
    final sameDay = now.day > previousDays ? previousDays : now.day;
    final lastToDate = sumEntries(store.entries,
        kind: EntryKind.expense,
        range: DateRange(
            previousMonth,
            DateTime(previousMonth.year, previousMonth.month, sameDay, now.hour,
                now.minute)));
    final thisToDate =
        sumEntries(store.entries, kind: EntryKind.expense, range: current);
    final insights = buildInsights(
      entries: store.entries,
      budgets: store.budgets,
      bills: store.bills,
      goals: store.goals,
      now: now,
    );
    return ListView(
      padding: pagePadding,
      children: [
        if (store.pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Card(
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: Text(
                    '${store.pending.length} ${store.pending.length == 1 ? 'draft is' : 'drafts are'} waiting for review'),
                subtitle: const Text('Recurring entries and SMS transactions'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => DefaultTabController.of(context).animateTo(4),
              ),
            ),
          ),
        SectionHeader(title: monthLabel(now)),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Income',
                value: formatMoney(month.income),
                icon: Icons.south_west,
                color: colors.income,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Expenses',
                value: formatMoney(month.expenses),
                icon: Icons.north_east,
                color: colors.expense,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        StatTile(
          label: 'Net recorded cash flow',
          value: formatMoney(month.netCashFlow),
          icon: Icons.swap_vert,
          caption: 'Recorded income − recorded expenses. Not net worth.',
        ),
        if (budgets.limitPaise > 0) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly budgets', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                      '${formatMoney(budgets.spentPaise)} of ${formatMoney(budgets.limitPaise)} · ${(budgets.utilization * 100).round()}% used'),
                  const SizedBox(height: 8),
                  AnimatedBar(
                    value: budgets.utilization,
                    color: budgets.utilization > 1
                        ? theme.colorScheme.error
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    budgets.remainingPaise >= 0
                        ? '${formatMoney(budgets.remainingPaise)} remaining'
                        : '${formatMoney(-budgets.remainingPaise)} over budget',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Icon(
              thisToDate > lastToDate ? Icons.trending_up : Icons.trending_down,
              color: thisToDate > lastToDate ? colors.expense : colors.income,
            ),
            title: const Text('Compared with last month'),
            subtitle: Text(lastToDate == 0 && thisToDate == 0
                ? 'No expenses recorded in either period yet.'
                : '${formatMoney(thisToDate)} by day ${now.day} vs ${formatMoney(lastToDate)} by day $sameDay of ${shortMonthLabel(previousMonth)}'),
          ),
        ),
        const SectionHeader(title: 'Top spending categories'),
        if (categories.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.pie_chart_outline,
            title: 'No expenses this month',
            message: 'Category totals appear once you record expenses.',
            actionLabel: 'Add expense',
            onAction: () => showEntryForm(context, store),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DonutChart(
                slices: _slices(categories, colors.chart),
                centerLabel: 'Spent',
                centerValue: formatMoneyCompact(month.expenses),
              ),
            ),
          ),
        if (insights.isNotEmpty) ...[
          const SectionHeader(title: 'Insights'),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InsightCard(insight: insight),
            ),
        ],
      ],
    );
  }
}

List<DonutSlice> _slices(Map<String, int> totals, List<Color> palette) {
  final entries = totals.entries.toList();
  final top = entries.take(5).toList();
  final rest = entries.skip(5).fold(0, (sum, item) => sum + item.value);
  return [
    for (var i = 0; i < top.length; i++)
      DonutSlice(top[i].key, top[i].value, palette[i % palette.length]),
    if (rest > 0) DonutSlice('Other categories', rest, palette.last),
  ];
}

// ---------------------------------------------------------------------------
// Activity

enum _Period { week, month, lastMonth, year, all }

enum _Sort { newest, oldest, largest, smallest }

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({required this.store});

  final LifePilotStore store;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  final _search = TextEditingController();
  EntryKind? _kind;
  _Period _period = _Period.month;
  _Sort _sort = _Sort.newest;
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateRange? _range(DateTime now) => switch (_period) {
        _Period.week => weekRange(now),
        _Period.month => monthRange(now),
        _Period.lastMonth => monthRange(now, offset: -1),
        _Period.year => yearRange(now),
        _Period.all => null,
      };

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = store.now();
    final range = _range(now);
    final query = _search.text.trim().toLowerCase();
    final entries = store.entries.where((entry) {
      if (_kind != null && entry.kind != _kind) return false;
      if (range != null && !range.contains(entry.occurredAt)) return false;
      if (_category != null && entry.category != _category) return false;
      if (query.isEmpty) return true;
      return entry.title.toLowerCase().contains(query) ||
          entry.merchant.toLowerCase().contains(query) ||
          entry.note.toLowerCase().contains(query) ||
          entry.category.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => switch (_sort) {
            _Sort.newest => b.occurredAt.compareTo(a.occurredAt),
            _Sort.oldest => a.occurredAt.compareTo(b.occurredAt),
            _Sort.largest => b.amountPaise.compareTo(a.amountPaise),
            _Sort.smallest => a.amountPaise.compareTo(b.amountPaise),
          });
    final summary =
        summarize(entries, DateRange(DateTime(1900), DateTime(3000)));
    final colors = AppColors.of(context);
    final groupByDay = _sort == _Sort.newest || _sort == _Sort.oldest;
    final usedCategories =
        {for (final entry in store.entries) entry.category}.toList()..sort();

    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search description, merchant, note',
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (value, label) in const [
                (null, 'All'),
                (EntryKind.expense, 'Expenses'),
                (EntryKind.income, 'Income'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _kind == value,
                    onSelected: (_) => setState(() => _kind = value),
                  ),
                ),
              const SizedBox(width: 6),
              _MenuChip<_Period>(
                icon: Icons.date_range,
                label: switch (_period) {
                  _Period.week => 'This week',
                  _Period.month => 'This month',
                  _Period.lastMonth => 'Last month',
                  _Period.year => 'This year',
                  _Period.all => 'All time',
                },
                values: const {
                  _Period.week: 'This week',
                  _Period.month: 'This month',
                  _Period.lastMonth: 'Last month',
                  _Period.year: 'This year',
                  _Period.all: 'All time',
                },
                onSelected: (value) => setState(() => _period = value),
              ),
              const SizedBox(width: 6),
              _MenuChip<String?>(
                icon: Icons.category_outlined,
                label: _category ?? 'Any category',
                values: {
                  null: 'Any category',
                  for (final category in usedCategories) category: category,
                },
                onSelected: (value) => setState(() => _category = value),
              ),
              const SizedBox(width: 6),
              _MenuChip<_Sort>(
                icon: Icons.sort,
                label: switch (_sort) {
                  _Sort.newest => 'Newest',
                  _Sort.oldest => 'Oldest',
                  _Sort.largest => 'Largest',
                  _Sort.smallest => 'Smallest',
                },
                values: const {
                  _Sort.newest: 'Newest first',
                  _Sort.oldest: 'Oldest first',
                  _Sort.largest: 'Largest amount',
                  _Sort.smallest: 'Smallest amount',
                },
                onSelected: (value) => setState(() => _sort = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'} · '
                'in ${formatMoney(summary.income)} · out ${formatMoney(summary.expenses)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Import or export',
              icon: const Icon(Icons.import_export),
              onSelected: (value) => value == 'export'
                  ? _export(context, entries)
                  : _import(context),
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'export',
                    child: Text('Export shown entries as CSV')),
                PopupMenuItem(value: 'import', child: Text('Import CSV…')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: store.entries.isEmpty
                ? 'No transactions recorded'
                : 'No matches',
            message: store.entries.isEmpty
                ? 'Your entries will appear here.'
                : 'Try another period, category or search.',
            actionLabel: store.entries.isEmpty ? 'Add expense' : null,
            onAction: () => showEntryForm(context, store),
          )
        else
          ..._list(context, entries, now, groupByDay, colors),
      ],
    );
  }

  List<Widget> _list(BuildContext context, List<LedgerEntry> entries,
      DateTime now, bool groupByDay, AppColors colors) {
    final widgets = <Widget>[];
    var index = 0;
    while (index < entries.length) {
      final day = dateOnly(entries[index].occurredAt);
      final group = <LedgerEntry>[];
      while (index < entries.length &&
          (!groupByDay || isSameDay(entries[index].occurredAt, day))) {
        group.add(entries[index]);
        index++;
      }
      if (groupByDay) {
        final spent = sumEntries(group, kind: EntryKind.expense);
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(friendlyDay(day, now),
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              if (spent > 0)
                Text('−${formatMoney(spent)}',
                    style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ));
      }
      widgets.add(CardList(
        indent: 72,
        children: [
          for (final entry in group)
            Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) => _delete(context, entry),
              child: EntryTile(
                entry: entry,
                now: now,
                onTap: () => showEntryForm(context, widget.store, entry: entry),
              ),
            ),
        ],
      ));
    }
    return widgets;
  }

  Future<void> _delete(BuildContext context, LedgerEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.store.deleteEntry(entry.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Deleted “${entry.title}”'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.store.addEntry(
            kind: entry.kind,
            amountPaise: entry.amountPaise,
            category: entry.category,
            title: entry.title,
            occurredAt: entry.occurredAt,
            paymentMethod: entry.paymentMethod,
            note: entry.note,
            merchant: entry.merchant,
            billId: entry.billId,
          ),
        ),
      ));
  }

  Future<void> _export(BuildContext context, List<LedgerEntry> entries) async {
    if (entries.isEmpty) {
      showMessage(context, 'There are no entries to export.');
      return;
    }
    if (!await confirmIdentity(
        context, widget.store, 'Confirm to export your transactions')) {
      return;
    }
    final csv = entriesToCsv(entries);
    await copySensitive(csv);
    String? path;
    try {
      final folder = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (folder != null) {
        final now = widget.store.now();
        final stamp =
            '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
        final file = File('${folder.path}/lifepilot-transactions-$stamp.csv');
        await file.writeAsString(csv, flush: true);
        path = file.path;
      }
    } on Object {
      path = null;
    }
    if (!context.mounted) return;
    showMessage(
        context,
        path == null
            ? 'CSV for ${entries.length} entries copied. The clipboard is cleared after a minute.'
            : 'CSV saved to $path and copied. The clipboard is cleared after a minute.');
  }

  Future<void> _import(BuildContext context) async {
    final pasted = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final controller = TextEditingController(text: pasted?.text ?? '');
    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import transactions'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Paste CSV with a header row. Required columns: date, type (expense or income), amount. Optional: category, description, payment_method, merchant, note.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 10,
                decoration:
                    const InputDecoration(hintText: 'date,type,amount,…'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Review')),
        ],
      ),
    );
    controller.dispose();
    if (source == null || !context.mounted) return;
    final result = parseEntriesCsv(source);
    if (result.entries.isEmpty) {
      showMessage(context,
          result.errors.isEmpty ? 'No rows found.' : result.errors.first,
          error: true);
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Import ${result.entries.length} entries?',
      message: [
        '${result.entries.length} valid rows. Rows matching an existing entry (same day, amount and description) will be skipped.',
        if (result.errors.isNotEmpty)
          '${result.errors.length} rows will be ignored:\n${result.errors.take(5).join('\n')}',
      ].join('\n\n'),
      confirmLabel: 'Import',
    );
    if (!confirmed || !context.mounted) return;
    final counts = await widget.store.importEntries(result.entries);
    await clearClipboardIf(source);
    if (!context.mounted) return;
    showMessage(context,
        'Imported ${counts.added}${counts.skipped == 0 ? '' : ', skipped ${counts.skipped} duplicates'}.');
  }
}

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.values,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final Map<T, String> values;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final MapEntry(key: value, value: text) in values.entries)
            PopupMenuItem(value: value, child: Text(text)),
        ],
        child: Chip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          deleteIcon: const Icon(Icons.arrow_drop_down),
          onDeleted: () {},
        ),
      );
}

// ---------------------------------------------------------------------------
// Budgets

class _BudgetsTab extends StatelessWidget {
  const _BudgetsTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final now = store.now();
    final statuses = store.budgets
        .map((budget) => budgetStatus(budget, store.entries, now))
        .toList()
      ..sort((a, b) => b.utilization.compareTo(a.utilization));
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
            title: 'Budgets',
            action: 'Add budget',
            onAction: () => showBudgetForm(context, store)),
        if (statuses.isEmpty)
          EmptyState(
            icon: Icons.savings_outlined,
            title: 'No budgets yet',
            message:
                'Set a monthly or weekly limit for a category and track spending against it.',
            actionLabel: 'Set a budget',
            onAction: () => showBudgetForm(context, store),
          )
        else
          for (var i = 0; i < statuses.length; i++)
            FadeSlideIn(
              key: ValueKey(statuses[i].budget.category),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BudgetCard(store: store, status: statuses[i]),
              ),
            ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.store, required this.status});

  final LifePilotStore store;
  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final budget = status.budget;
    final color = status.isOver
        ? theme.colorScheme.error
        : status.isApproaching
            ? colors.warning
            : null;
    final period =
        budget.period == BudgetPeriod.weekly ? 'this week' : 'this month';
    return Card(
      child: InkWell(
        onTap: () => _history(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(budget.category,
                        style: theme.textTheme.titleMedium),
                  ),
                  Pill(
                      label: budget.period == BudgetPeriod.weekly
                          ? 'Weekly'
                          : 'Monthly'),
                  PopupMenuButton<String>(
                    tooltip: 'Budget options',
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await showBudgetForm(context, store, budget: budget);
                      } else if (value == 'delete' &&
                          await confirmAction(context,
                              title: 'Delete ${budget.category} budget?',
                              message: 'Your expenses are not affected.',
                              confirmLabel: 'Delete',
                              destructive: true)) {
                        await store.deleteBudget(budget.category);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${formatMoney(status.spentPaise)} of ${formatMoney(status.limitPaise)} · ${status.utilizationPercent}%'),
                    const SizedBox(height: 8),
                    AnimatedBar(value: status.utilization / 100, color: color),
                    const SizedBox(height: 6),
                    Text(
                      status.isOver
                          ? '${formatMoney(-status.remainingPaise)} over $period'
                          : '${formatMoney(status.remainingPaise)} left $period'
                              '${status.carriedOverPaise > 0 ? ' · includes ${formatMoney(status.carriedOverPaise)} rolled over' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _history(BuildContext context) {
    final now = store.now();
    final history = budgetHistory(status.budget, store.entries, now);
    final colors = AppColors.of(context);
    final weekly = status.budget.period == BudgetPeriod.weekly;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${status.budget.category} budget vs actual',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              BarChart(
                labels: [
                  for (final item in history)
                    weekly
                        ? formatShortDate(item.range.start)
                        : shortMonthLabel(item.range.start),
                ],
                series: [
                  BarSeries('Limit', colors.chart[2].withValues(alpha: 0.5),
                      [for (final item in history) item.limit]),
                  BarSeries('Spent', colors.expense,
                      [for (final item in history) item.spent]),
                ],
              ),
              const SizedBox(height: 12),
              for (final item in history.reversed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(weekly
                      ? 'Week of ${formatShortDate(item.range.start)}'
                      : monthLabel(item.range.start)),
                  trailing: Text(
                      '${formatMoney(item.spent)} / ${formatMoney(item.limit)}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bills

class _BillsTab extends StatelessWidget {
  const _BillsTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final now = store.now();
    final active = store.bills.where((bill) => bill.active).toList()
      ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
    final settled = store.bills.where((bill) => !bill.active).toList();
    final monthly = monthlyRecurringObligations(store.bills);
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
            title: 'Bills and subscriptions',
            action: 'Add bill',
            onAction: () => showBillForm(context, store)),
        if (monthly > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StatTile(
              label: 'Recurring obligations',
              value: '${formatMoney(monthly)} / month',
              icon: Icons.autorenew,
              caption: 'Monthly equivalent of active recurring bills.',
            ),
          ),
        if (active.isEmpty)
          EmptyState(
            icon: Icons.receipt_outlined,
            title: 'No bills tracked',
            message:
                'Add rent, electricity, internet, recharges, loan EMIs, insurance or subscriptions to get due-date reminders.',
            actionLabel: 'Add a bill',
            onAction: () => showBillForm(context, store),
          )
        else
          for (final bill in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BillCard(store: store, bill: bill, now: now),
            ),
        if (settled.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Settled one-time bills (${settled.length})'),
            children: [
              for (final bill in settled)
                _BillCard(store: store, bill: bill, now: now),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          'Bills are marked paid only when you confirm. Opening a payment app does not confirm a payment.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.store, required this.bill, required this.now});

  final LifePilotStore store;
  final Bill bill;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final overdue = isBillOverdue(bill, now);
    final days = DateRange(dateOnly(now), dateOnly(bill.nextDueAt)).days;
    final (status, color) = !bill.active
        ? ('Settled', colors.income)
        : overdue
            ? ('Overdue', scheme.error)
            : days <= 3
                ? ('Due soon', colors.warning)
                : ('Scheduled', scheme.outline);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bill.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '${bill.kind.label} · ${bill.recurrence.isNone ? 'One time' : bill.recurrence.label}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(formatMoney(bill.amountPaise),
                    style: Theme.of(context).textTheme.titleMedium),
                PopupMenuButton<String>(
                  tooltip: 'Bill options',
                  onSelected: (value) => _action(context, value),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                        value: 'history', child: Text('Payment history')),
                    if (bill.payments.isNotEmpty)
                      const PopupMenuItem(
                          value: 'undo', child: Text('Undo last payment')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Pill(label: status, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bill.active
                        ? (overdue
                            ? 'Was due ${formatDate(bill.nextDueAt)}'
                            : 'Due ${friendlyDay(bill.nextDueAt, now).toLowerCase()} · ${formatDate(bill.nextDueAt)}')
                        : 'Paid ${formatDate(bill.payments.last.paidAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (bill.active)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showMarkPaidForm(context, store, bill),
                  icon: const Icon(Icons.task_alt, size: 18),
                  label: const Text('Mark paid'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _action(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        await showBillForm(context, store, bill: bill);
      case 'history':
        await showModalBottomSheet<void>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Text('${bill.name} payments',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (bill.payments.isEmpty)
                  const Text('No payments confirmed yet.')
                else
                  for (final payment in bill.payments.reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.task_alt),
                      title: Text(formatMoney(payment.amountPaise)),
                      subtitle: Text(
                          'Paid ${formatDate(payment.paidAt)} · for due date ${formatDate(payment.dueAt)}'),
                      trailing: payment.entryId == null
                          ? null
                          : const Tooltip(
                              message: 'Recorded as an expense',
                              child: Icon(Icons.receipt_long_outlined)),
                    ),
              ],
            ),
          ),
        );
      case 'undo':
        if (await confirmAction(context,
            title: 'Undo last payment?',
            message:
                'The due date returns to ${formatDate(bill.payments.last.dueAt)} and any linked expense is removed.',
            confirmLabel: 'Undo payment')) {
          await store.undoLastBillPayment(bill.id);
        }
      case 'delete':
        if (await confirmAction(context,
            title: 'Delete ${bill.name}?',
            message:
                'Its reminders and payment history are removed. Recorded expenses stay.',
            confirmLabel: 'Delete',
            destructive: true)) {
          await store.deleteBill(bill.id);
        }
    }
  }
}

// ---------------------------------------------------------------------------
// Goals

class _GoalsTab extends StatelessWidget {
  const _GoalsTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final saved = store.goals.fold(0, (sum, goal) => sum + goal.savedPaise);
    final target = store.goals.fold(0, (sum, goal) => sum + goal.targetPaise);
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
            title: 'Savings goals',
            action: 'New goal',
            onAction: () => showGoalForm(context, store)),
        if (store.goals.isEmpty)
          EmptyState(
            icon: Icons.flag_outlined,
            title: 'No savings goals yet',
            message:
                'Plan for an emergency fund, travel, a new device or education, and record contributions as you save.',
            actionLabel: 'Create a goal',
            onAction: () => showGoalForm(context, store),
          )
        else ...[
          Text(
              '${formatMoney(saved)} saved of ${formatMoney(target)} across ${store.goals.length} goals. Contributions are tracked separately from expenses.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          for (var i = 0; i < store.goals.length; i++)
            FadeSlideIn(
              key: ValueKey(store.goals[i].id),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _GoalCard(store: store, goal: store.goals[i]),
              ),
            ),
        ],
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.store, required this.goal});

  final LifePilotStore store;
  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) {
    final now = store.now();
    final suggestion = suggestedMonthlyContribution(goal, now);
    final theme = Theme.of(context);
    final reached = goal.remainingPaise == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProgressRing(
                  value: goal.progress,
                  size: 64,
                  color: reached ? AppColors.of(context).income : null,
                  child: reached
                      ? Icon(Icons.check, color: AppColors.of(context).income)
                      : Text('${(goal.progress * 100).round()}%',
                          style: theme.textTheme.labelLarge),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name, style: theme.textTheme.titleMedium),
                      Text(goal.type.label, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                          '${formatMoney(goal.savedPaise)} of ${formatMoney(goal.targetPaise)}'),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Goal options',
                  onSelected: (value) => _action(context, value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'history', child: Text('Contribution history')),
                    PopupMenuItem(value: 'edit', child: Text('Edit goal')),
                    PopupMenuItem(value: 'delete', child: Text('Delete goal')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                reached
                    ? 'Goal reached.'
                    : [
                        '${formatMoney(goal.remainingPaise)} remaining',
                        if (goal.targetDate != null)
                          'target ${formatDate(goal.targetDate!)}',
                        if (suggestion != null && goal.targetDate!.isAfter(now))
                          'about ${formatMoney(suggestion)}/month to stay on track',
                      ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (!reached)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showContributionForm(context, store, goal),
                  icon: const Icon(Icons.add),
                  label: const Text('Contribute'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _action(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        await showGoalForm(context, store, goal: goal);
      case 'delete':
        if (await confirmAction(context,
            title: 'Delete ${goal.name}?',
            message: 'Its contribution history is removed too.',
            confirmLabel: 'Delete',
            destructive: true)) {
          await store.deleteGoal(goal.id);
        }
      case 'history':
        await showModalBottomSheet<void>(
          context: context,
          builder: (sheetContext) => AnimatedBuilder(
            animation: store,
            builder: (sheetContext, _) {
              final current =
                  store.goals.where((item) => item.id == goal.id).firstOrNull;
              final items = [...?current?.contributions]
                ..sort((a, b) => b.at.compareTo(a.at));
              return SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    Text('${goal.name} contributions',
                        style: Theme.of(sheetContext).textTheme.titleLarge),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('No contributions yet.'),
                      ),
                    for (final item in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(formatMoney(item.amountPaise)),
                        subtitle: Text([
                          formatDate(item.at),
                          if (item.note.isNotEmpty) item.note,
                        ].join(' · ')),
                        trailing: IconButton(
                          tooltip: 'Delete contribution',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              store.deleteContribution(goal.id, item.id),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Reports

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.store});

  final LifePilotStore store;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  int _months = 6;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = store.now();
    final colors = AppColors.of(context);
    final history = monthlyHistory(store.entries, now, count: _months);
    final daily = dailyExpenses(store.entries, monthRange(now))
        .where((day) => !day.day.isAfter(now))
        .toList();
    final categories = categoryTotals(store.entries, monthRange(now));
    final hasData = store.entries.isNotEmpty;
    final statuses = store.budgets
        .map((budget) => budgetStatus(budget, store.entries, now))
        .toList();
    final recurring = store.bills
        .where((bill) => bill.active && !bill.recurrence.isNone)
        .toList();
    Widget card(String title, Widget child, {String? subtitle}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null)
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
          ),
        );
    return ListView(
      padding: pagePadding,
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader(title: 'Reports')),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 3, label: Text('3M')),
                ButtonSegment(value: 6, label: Text('6M')),
                ButtonSegment(value: 12, label: Text('12M')),
              ],
              selected: {_months},
              onSelectionChanged: (value) =>
                  setState(() => _months = value.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!hasData)
          EmptyState(
            icon: Icons.bar_chart,
            title: 'No data to chart yet',
            message:
                'Charts use only the transactions you record on this device.',
            actionLabel: 'Add expense',
            onAction: () => showEntryForm(context, store),
          )
        else ...[
          card(
            'Income vs expenses',
            BarChart(
              labels: [for (final m in history) shortMonthLabel(m.month)],
              series: [
                BarSeries('Income', colors.income,
                    [for (final m in history) m.summary.income]),
                BarSeries('Expenses', colors.expense,
                    [for (final m in history) m.summary.expenses]),
              ],
              semanticLabel: 'Monthly income and expenses',
            ),
            subtitle: 'Long-press a month for exact amounts.',
          ),
          card(
            'Net cash-flow history',
            LineChart(
              labels: [for (final m in history) shortMonthLabel(m.month)],
              values: [for (final m in history) m.summary.netCashFlow],
              color: Theme.of(context).colorScheme.primary,
            ),
            subtitle: 'Recorded income minus recorded expenses, per month.',
          ),
          card(
            'Daily spending · ${monthLabel(now)}',
            BarChart(
              labels: [for (final day in daily) '${day.day.day}'],
              series: [
                BarSeries('Spent', colors.expense,
                    [for (final day in daily) day.amount]),
              ],
              showEveryNthLabel: 5,
              height: 140,
            ),
            subtitle: daily.isEmpty
                ? null
                : 'Average ${formatMoney(daily.fold(0, (s, d) => s + d.amount) ~/ daily.length)} per day so far.',
          ),
          card(
            'Spending by category · ${monthLabel(now)}',
            categories.isEmpty
                ? const Text('No expenses recorded this month.')
                : DonutChart(
                    slices: _slices(categories, colors.chart),
                    centerLabel: 'Total',
                    centerValue: formatMoneyCompact(
                        categories.values.fold(0, (s, v) => s + v)),
                  ),
          ),
        ],
        if (statuses.isNotEmpty)
          card(
            'Budget utilization',
            Column(
              children: [
                for (final status in statuses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(status.budget.category)),
                            Text('${status.utilizationPercent}%'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        AnimatedBar(
                          value: status.utilization / 100,
                          color: status.isOver
                              ? Theme.of(context).colorScheme.error
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
        if (store.goals.isNotEmpty)
          card(
            'Savings progress',
            Column(
              children: [
                for (final goal in store.goals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(goal.name)),
                            Text(
                                '${formatMoneyCompact(goal.savedPaise)} / ${formatMoneyCompact(goal.targetPaise)}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        AnimatedBar(value: goal.progress, color: colors.income),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (recurring.isNotEmpty)
          card(
            'Recurring expenses',
            Column(
              children: [
                for (final bill in recurring)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(bill.name),
                    subtitle: Text(bill.recurrence.label),
                    trailing: Text(formatMoney(bill.amountPaise)),
                  ),
                const Divider(),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Monthly equivalent'),
                  trailing: Text(
                      formatMoney(monthlyRecurringObligations(store.bills)),
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
          ),
        Text('Reports describe recorded cash flow, not net worth.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// UPI handoff
