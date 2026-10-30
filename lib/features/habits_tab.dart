import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/personal.dart';
import '../services/reminder_coordinator.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class HabitsTab extends StatelessWidget {
  const HabitsTab({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final now = store.now();
    final active = store.habits.where((habit) => !habit.archived).toList();
    final archived = store.habits.where((habit) => habit.archived).toList();
    final dueToday = active.where((habit) => habit.appliesOn(now)).toList();
    final doneToday = dueToday.where((habit) => habit.doneOn(now)).length;
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
          title: dueToday.isEmpty
              ? 'Habits'
              : 'Today · $doneToday of ${dueToday.length} done',
          action: 'New habit',
          onAction: () => showHabitForm(context, store),
        ),
        if (active.isEmpty)
          EmptyState(
            icon: Icons.local_fire_department_outlined,
            title: 'No habits yet',
            message:
                'Track small daily routines — walking, reading, water, medicine — and build streaks.',
            actionLabel: 'Add a habit',
            onAction: () => showHabitForm(context, store),
          )
        else ...[
          if (dueToday.isNotEmpty) ...[
            AnimatedBar(
              value: doneToday / dueToday.length,
              color: AppColors.of(context).income,
            ),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < active.length; i++)
            FadeSlideIn(
              key: ValueKey(active[i].id),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HabitCard(store: store, habit: active[i], now: now),
              ),
            ),
        ],
        if (archived.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Archived (${archived.length})'),
            children: [
              for (final habit in archived)
                ListTile(
                  title: Text(habit.name),
                  trailing: TextButton(
                    onPressed: () =>
                        store.updateHabit(habit.copyWith(archived: false)),
                    child: const Text('Restore'),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class HabitCard extends StatelessWidget {
  const HabitCard({
    required this.store,
    required this.habit,
    required this.now,
    this.compact = false,
    super.key,
  });

  final LifePilotStore store;
  final Habit habit;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final today = dateOnly(now);
    final applies = habit.appliesOn(today);
    final done = habit.doneOn(today);
    final streak = habitStreak(habit, now);
    final rate = habitCompletion(habit, now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: done ? 'Undo today' : 'Mark done today',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    store.toggleHabit(habit.id);
                  },
                  icon: AnimatedSwitcher(
                    duration: motion(context, 220),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      done ? Icons.check_circle : Icons.radio_button_unchecked,
                      key: ValueKey(done),
                      size: 30,
                      color: done ? colors.income : theme.colorScheme.outline,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(habit.name, style: theme.textTheme.titleSmall),
                      Text(
                        [
                          if (!applies) 'Not scheduled today',
                          habit.weekdays.isEmpty
                              ? 'Every day'
                              : habit.weekdays.map(weekdayShort).join(', '),
                          if (!compact) '${(rate * 100).round()}% in 30 days',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Pill(
                  icon: Icons.local_fire_department_outlined,
                  label: '$streak',
                  color: streak > 0 ? colors.warning : null,
                ),
                if (!compact)
                  PopupMenuButton<String>(
                    tooltip: 'Habit options',
                    onSelected: (value) async {
                      switch (value) {
                        case 'edit':
                          await showHabitForm(context, store, habit: habit);
                        case 'archive':
                          await store
                              .updateHabit(habit.copyWith(archived: true));
                        case 'delete':
                          if (await confirmAction(context,
                              title: 'Delete “${habit.name}”?',
                              message: 'Its check-in history is removed too.',
                              confirmLabel: 'Delete',
                              destructive: true)) {
                            await store.deleteHabit(habit.id);
                          }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'archive', child: Text('Archive')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 8, top: 4),
                child: Row(
                  children: [
                    for (var offset = 6; offset >= 0; offset--)
                      Expanded(
                        child: _DayDot(
                          store: store,
                          habit: habit,
                          day: DateTime(
                              today.year, today.month, today.day - offset),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.store, required this.habit, required this.day});

  final LifePilotStore store;
  final Habit habit;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = habit.doneOn(day);
    final applies =
        habit.appliesOn(day) && !day.isBefore(dateOnly(habit.createdAt));
    return Semantics(
      label:
          '${weekdayName(day)}: ${done ? 'done' : applies ? 'not done' : 'not scheduled'}',
      button: applies,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Past days can be corrected, for example if you forgot to tick.
        onTap: applies ? () => store.toggleHabit(habit.id, day: day) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            children: [
              Text(weekdayShort(day.weekday).substring(0, 1),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppColors.of(context).income
                      : applies
                          ? scheme.surfaceContainerHighest
                          : null,
                  border:
                      applies ? null : Border.all(color: scheme.outlineVariant),
                ),
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showHabitForm(BuildContext context, LifePilotStore store,
    {Habit? habit}) async {
  final name = TextEditingController(text: habit?.name ?? '');
  final days = {...?habit?.weekdays};
  int? reminder = habit?.reminderMinutes;
  final formKey = GlobalKey<FormState>();
  var saving = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Form(
          key: formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(habit == null ? 'New habit' : 'Edit habit',
                  style: Theme.of(sheetContext).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                autofocus: habit == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Habit', hintText: 'Walk 30 minutes'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Name the habit.'
                    : null,
              ),
              const SizedBox(height: 12),
              Text(days.isEmpty ? 'Every day' : 'On selected days',
                  style: Theme.of(sheetContext).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(weekdayShort(day)),
                      selected: days.contains(day),
                      onSelected: (on) => setSheetState(
                          () => on ? days.add(day) : days.remove(day)),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily reminder'),
                subtitle: reminder == null
                    ? null
                    : Text(formatTime(
                        DateTime(2000, 1, 1, reminder! ~/ 60, reminder! % 60),
                        use24h: store.settings.use24HourClock)),
                value: reminder != null,
                onChanged: (on) async {
                  if (!on) {
                    setSheetState(() => reminder = null);
                    return;
                  }
                  final picked = await showTimePicker(
                    context: sheetContext,
                    initialTime: const TimeOfDay(hour: 20, minute: 0),
                  );
                  if (picked != null) {
                    setSheetState(
                        () => reminder = picked.hour * 60 + picked.minute);
                  }
                },
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setSheetState(() => saving = true);
                        final weekdays = days.length == 7
                            ? <int>[]
                            : (days.toList()..sort());
                        if (habit == null) {
                          await store.addHabit(name.text,
                              weekdays: weekdays, reminderMinutes: reminder);
                        } else {
                          await store.updateHabit(habit.copyWith(
                            name: name.text.trim(),
                            weekdays: weekdays,
                            reminderMinutes: reminder,
                            clearReminder: reminder == null,
                          ));
                        }
                        if (!sheetContext.mounted) return;
                        if (reminder != null) {
                          await ensureReminderPermission(sheetContext);
                        }
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                child: Text(saving ? 'Saving…' : 'Save habit'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  name.dispose();
}
