import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/spending_habits.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Budgets tab extras: the no-spend challenge, a spending heatmap for the
/// month, and trip budgets.
class SpendingHabitsSection extends StatelessWidget {
  const SpendingHabitsSection({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final now = store.now();
    final stats = noSpendStats(store.entries, now);
    final heat = monthHeatmap(store.entries, now);
    final first = DateTime(now.year, now.month);
    final days = DateTime(now.year, now.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = ((leading + days) / 7).ceil() * 7;
    Color shade(int level) => level == 0
        ? theme.colorScheme.surfaceContainerHighest
        : colors.expense.withValues(alpha: 0.2 + level * 0.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'No-spend challenge'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.local_fire_department_outlined,
                    color: stats.currentStreak > 0 ? colors.warning : null,
                    size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${stats.noSpendDays} of ${stats.daysSoFar} days with no everyday spending',
                          style: theme.textTheme.titleSmall),
                      Text(
                        stats.currentStreak > 0
                            ? 'Current streak: ${stats.currentStreak} day${stats.currentStreak == 1 ? '' : 's'} · best this month ${stats.bestStreak}'
                            : 'Best streak this month: ${stats.bestStreak}. Try a no-spend day tomorrow.',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text('Bills, recurring payments and EMIs do not count.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionHeader(title: 'Spending in ${monthLabel(now)}'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    for (var day = 1; day <= 7; day++)
                      Expanded(
                        child: Text(weekdayShort(day).substring(0, 2),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cells,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, childAspectRatio: 1.2),
                  itemBuilder: (context, index) {
                    final number = index - leading + 1;
                    if (number < 1 || number > days) return const SizedBox();
                    final day = DateTime(now.year, now.month, number);
                    final amount = heat.totals[day];
                    final future = number > now.day;
                    return Tooltip(
                      message: amount == null
                          ? '${formatDate(day)}: nothing spent'
                          : '${formatDate(day)}: ${formatMoney(amount)}',
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: future ? null : shade(heat.level[day] ?? 0),
                          borderRadius: BorderRadius.circular(6),
                          border: stats.days.contains(day)
                              ? Border.all(color: colors.income, width: 1.5)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child:
                            Text('$number', style: theme.textTheme.labelSmall),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                    'Darker means more spent that day. Outlined days had no everyday spending.',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        SectionHeader(
          title: 'Trips',
          action: 'Add trip',
          onAction: () => showTripForm(context, store),
        ),
        if (store.trips.isEmpty)
          Text(
              'Planning a trip? Give it a budget and dates; every expense in those dates counts towards it.',
              style: theme.textTheme.bodySmall)
        else
          for (final trip in [
            ...store.trips
          ]..sort((a, b) => b.start.compareTo(a.start)))
            _TripCard(
                store: store, status: tripStatus(trip, store.entries, now)),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.store, required this.status});

  final LifePilotStore store;
  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = status.trip;
    final over = status.leftPaise < 0;
    final perDay = status.perDayPaise;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(trip.name, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Delete trip',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmAction(context,
                          title: 'Delete “${trip.name}”?',
                          message: 'Expenses are not affected.',
                          confirmLabel: 'Delete',
                          destructive: true)) {
                        await store.deleteTrip(trip.id);
                      }
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${formatDate(trip.start)} – ${formatDate(trip.end)} · ${trip.days} days',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                        '${formatMoney(status.spentPaise)} of ${formatMoney(trip.budgetPaise)}'),
                    const SizedBox(height: 6),
                    AnimatedBar(
                      value: status.spentPaise / trip.budgetPaise,
                      color: over ? theme.colorScheme.error : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      over
                          ? '${formatMoney(-status.leftPaise)} over budget'
                          : perDay != null
                              ? '${formatMoney(status.leftPaise)} left · ${formatMoney(perDay)} a day for ${status.daysLeft} day${status.daysLeft == 1 ? '' : 's'}'
                              : '${formatMoney(status.leftPaise)} left',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: over ? theme.colorScheme.error : null),
                    ),
                    if (status.byCategory.isNotEmpty)
                      Text(
                        status.byCategory.entries
                            .take(3)
                            .map((item) =>
                                '${item.key} ${formatMoney(item.value)}')
                            .join(' · '),
                        style: theme.textTheme.bodySmall,
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
}

Future<void> showTripForm(BuildContext context, LifePilotStore store) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TripForm(store: store),
    );

class _TripForm extends StatefulWidget {
  const _TripForm({required this.store});

  final LifePilotStore store;

  @override
  State<_TripForm> createState() => _TripFormState();
}

class _TripFormState extends State<_TripForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _budget = TextEditingController();
  late DateTimeRange _dates = DateTimeRange(
    start: dateOnly(widget.store.now()),
    end: dateOnly(widget.store.now()).add(const Duration(days: 3)),
  );

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('New trip',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'Goa, Diwali at home…'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Add a name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Budget', prefixText: '${MoneyFormat.symbol} '),
                validator: (value) => parseRupeesToPaise(value ?? '') == null
                    ? 'Enter an amount greater than zero.'
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_outlined),
                title: Text(
                    '${formatDate(_dates.start)} – ${formatDate(_dates.end)}'),
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    initialDateRange: _dates,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _dates = picked);
                },
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  await widget.store.addTrip(
                    name: _name.text,
                    start: _dates.start,
                    end: _dates.end,
                    budgetPaise: parseRupeesToPaise(_budget.text)!,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save trip'),
              ),
            ],
          ),
        ),
      );
}
