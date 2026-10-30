import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/clock_ops.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../services/notification_service.dart';
import '../services/reminder_coordinator.dart';
import '../ui/clock_widgets.dart';
import '../ui/forms.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

enum ClockTab { clock, world, stopwatch, timer, focus, alarms }

class ClockPage extends StatelessWidget {
  const ClockPage(
      {required this.store, this.initialTab = ClockTab.clock, super.key});

  final LifePilotStore store;
  final ClockTab initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: ClockTab.values.length,
        initialIndex: initialTab.index,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Clock and time'),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.schedule), text: 'Clock'),
                Tab(icon: Icon(Icons.public), text: 'World'),
                Tab(icon: Icon(Icons.timer_outlined), text: 'Stopwatch'),
                Tab(icon: Icon(Icons.hourglass_bottom), text: 'Timer'),
                Tab(icon: Icon(Icons.self_improvement), text: 'Focus'),
                Tab(icon: Icon(Icons.alarm), text: 'Alarms'),
              ],
            ),
          ),
          body: AnimatedBuilder(
            animation: store,
            builder: (context, _) => TabBarView(
              children: [
                _ClockTab(store: store),
                _WorldTab(store: store),
                _StopwatchTab(store: store),
                _TimerTab(store: store),
                _FocusTab(store: store),
                _AlarmsTab(store: store),
              ],
            ),
          ),
        ),
      );
}

String _offsetLabel(Duration offset) {
  final sign = offset.isNegative ? '−' : '+';
  final minutes = offset.inMinutes.abs();
  return 'UTC$sign${minutes ~/ 60}${minutes % 60 == 0 ? '' : ':${(minutes % 60).toString().padLeft(2, '0')}'}';
}

// ---------------------------------------------------------------------------
// Live clock

class _ClockTab extends StatelessWidget {
  const _ClockTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final settings = store.settings;
    final theme = Theme.of(context);
    final plan = store.notificationPlan();
    final next = nextReminder(plan);
    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 16),
        if (settings.analogClock)
          const Center(child: AnalogClock(size: 220))
        else
          const SizedBox.shrink(),
        if (settings.analogClock) const SizedBox(height: 16),
        Tick(
          now: store.now,
          interval: Duration(seconds: settings.showSeconds ? 1 : 30),
          builder: (context, now) => Column(
            children: [
              FittedBox(
                child: Text(
                  formatTime(now,
                      use24h: settings.use24HourClock,
                      seconds: settings.showSeconds),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(formatLongDate(now), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${now.timeZoneName} · ${_offsetLabel(now.timeZoneOffset)} · week ${_isoWeek(now)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (next != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(next.title),
              subtitle: Text(
                  formatDateTime(next.at, use24h: settings.use24HourClock)),
              trailing: Tick(
                now: store.now,
                builder: (context, now) => Text(
                  formatRelative(next.at, now),
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('24-hour time'),
                value: settings.use24HourClock,
                onChanged: (value) => store
                    .updateSettings(settings.copyWith(use24HourClock: value)),
              ),
              SwitchListTile(
                title: const Text('Show seconds'),
                value: settings.showSeconds,
                onChanged: (value) =>
                    store.updateSettings(settings.copyWith(showSeconds: value)),
              ),
              SwitchListTile(
                title: const Text('Analog clock'),
                value: settings.analogClock,
                onChanged: (value) =>
                    store.updateSettings(settings.copyWith(analogClock: value)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static int _isoWeek(DateTime date) {
    final thursday =
        DateTime(date.year, date.month, date.day + 4 - date.weekday);
    final firstThursday = DateTime(thursday.year, 1, 4);
    final start = DateTime(firstThursday.year, firstThursday.month,
        firstThursday.day - firstThursday.weekday + 1);
    return DateTime.utc(thursday.year, thursday.month, thursday.day)
                .difference(DateTime.utc(start.year, start.month, start.day))
                .inDays ~/
            7 +
        1;
  }
}

// ---------------------------------------------------------------------------
// World clock

class _WorldTab extends StatefulWidget {
  const _WorldTab({required this.store});

  final LifePilotStore store;

  @override
  State<_WorldTab> createState() => _WorldTabState();
}

class _WorldTabState extends State<_WorldTab> {
  @override
  void initState() {
    super.initState();
    ensureTimeZones();
  }

  String _city(String id) => id.split('/').last.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final zones = store.settings.worldClocks
        .where((id) => tz.timeZoneDatabase.locations.containsKey(id))
        .toList();
    final use24h = store.settings.use24HourClock;
    return Tick(
      now: store.now,
      interval: const Duration(seconds: 30),
      builder: (context, now) => ListView(
        padding: pagePadding,
        children: [
          SectionHeader(
              title: 'World clock', action: 'Add city', onAction: _addCity),
          Card(
            child: _ZoneRow(
              icon: Icons.my_location,
              title: 'Local · ${now.timeZoneName}',
              subtitle: formatLongDate(now),
              time: formatTime(now, use24h: use24h),
            ),
          ),
          const SizedBox(height: 10),
          if (zones.isEmpty)
            EmptyState(
              icon: Icons.public,
              title: 'No cities added',
              message: 'Add cities to compare their time with yours.',
              actionLabel: 'Add city',
              onAction: _addCity,
            )
          else
            CardList(
              children: [
                for (final id in zones) _zoneTile(context, id, now, use24h),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Times use the IANA time-zone database, including daylight-saving rules.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _zoneTile(BuildContext context, String id, DateTime now, bool use24h) {
    final location = tz.getLocation(id);
    final remote = tz.TZDateTime.from(now, location);
    final wall = DateTime(
        remote.year, remote.month, remote.day, remote.hour, remote.minute);
    final difference = remote.timeZoneOffset - now.timeZoneOffset;
    final dayShift = DateTime.utc(remote.year, remote.month, remote.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    final relation = difference == Duration.zero
        ? 'Same time'
        : '${formatDuration(difference.abs())} ${difference.isNegative ? 'behind' : 'ahead'}';
    final day = switch (dayShift) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => formatShortDate(wall),
    };
    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => widget.store.updateSettings(widget.store.settings
          .copyWith(
              worldClocks: widget.store.settings.worldClocks
                  .where((item) => item != id)
                  .toList())),
      child: _ZoneRow(
        title: _city(id),
        subtitle: '$day · $relation · ${_offsetLabel(remote.timeZoneOffset)}',
        time: formatTime(wall, use24h: use24h),
      ),
    );
  }

  Future<void> _addCity() async {
    final ids = tz.timeZoneDatabase.locations.keys
        .where((id) => id.contains('/') && !id.startsWith('Etc/'))
        .toList()
      ..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CityPicker(ids: ids, city: _city),
    );
    if (picked == null) return;
    final current = widget.store.settings.worldClocks;
    if (current.contains(picked)) return;
    await widget.store.updateSettings(
        widget.store.settings.copyWith(worldClocks: [...current, picked]));
  }
}

/// Place and time on one row. Unlike a ListTile trailing widget, the time
/// keeps its natural width without squeezing the place name, even with
/// large system text.
class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.title,
    required this.subtitle,
    required this.time,
    this.icon,
  });

  final String title;
  final String subtitle;
  final String time;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 16),
          ],
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(time,
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CityPicker extends StatefulWidget {
  const _CityPicker({required this.ids, required this.city});

  final List<String> ids;
  final String Function(String) city;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final matches = widget.ids
        .where((id) => id.toLowerCase().replaceAll('_', ' ').contains(query))
        .take(80)
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search city or region, e.g. Dubai',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(widget.city(matches[index])),
                subtitle: Text(matches[index]),
                onTap: () => Navigator.pop(context, matches[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stopwatch

class _StopwatchTab extends StatelessWidget {
  const _StopwatchTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final state = store.clock.stopwatch;
    final theme = Theme.of(context);
    final laps = <int>[
      for (var i = 0; i < state.lapsMs.length; i++)
        state.lapsMs[i] - (i == 0 ? 0 : state.lapsMs[i - 1]),
    ];
    final fastest =
        laps.length > 1 ? laps.reduce((a, b) => a < b ? a : b) : null;
    final slowest =
        laps.length > 1 ? laps.reduce((a, b) => a > b ? a : b) : null;
    final elapsedText = state.isRunning
        ? Tick(
            now: store.now,
            interval: const Duration(milliseconds: 100),
            builder: (context, now) => _bigTime(context, state.elapsedMs(now)),
          )
        : _bigTime(context, state.elapsedMs(store.now()));
    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 32),
        Center(child: elapsedText),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: state.isRunning
                  ? store.stopwatchLap
                  : (state.accumulatedMs > 0 ? store.stopwatchReset : null),
              icon: Icon(
                  state.isRunning ? Icons.flag_outlined : Icons.restart_alt),
              label: Text(state.isRunning ? 'Lap' : 'Reset'),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                state.isRunning
                    ? store.stopwatchPause()
                    : store.stopwatchStart();
              },
              icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
              label: Text(state.isRunning
                  ? 'Pause'
                  : state.accumulatedMs > 0
                      ? 'Resume'
                      : 'Start'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (laps.isNotEmpty)
          CardList(
            children: [
              for (var i = laps.length - 1; i >= 0; i--)
                ListTile(
                  dense: true,
                  leading:
                      Text('Lap ${i + 1}', style: theme.textTheme.labelLarge),
                  title: Text(
                    formatStopwatch(laps[i]),
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: laps[i] == fastest
                          ? AppColors.of(context).income
                          : laps[i] == slowest
                              ? AppColors.of(context).expense
                              : null,
                    ),
                  ),
                  trailing: Text(formatStopwatch(state.lapsMs[i]),
                      style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          'Elapsed time is calculated from start timestamps, so it stays accurate if you leave the app.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _bigTime(BuildContext context, int ms) => Text(
        formatStopwatch(ms),
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

// ---------------------------------------------------------------------------
// Countdown timer

class _TimerTab extends StatefulWidget {
  const _TimerTab({required this.store});

  final LifePilotStore store;

  @override
  State<_TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<_TimerTab> {
  Duration _duration = const Duration(minutes: 5);
  String _label = '';
  final _custom = TextEditingController();

  static const _presets = [1, 3, 5, 10, 15, 20, 30, 45, 60];
  static const _labels = ['Study', 'Exercise', 'Cooking', 'Work', 'Break'];

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final state = store.clock.timer;
    final theme = Theme.of(context);
    if (state.isActive) {
      return ListView(
        padding: pagePadding,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Tick(
              now: store.now,
              interval: Duration(milliseconds: state.isRunning ? 250 : 60000),
              builder: (context, now) {
                final remaining = state.remaining(now);
                return CountdownRing(
                  progress: state.totalMs == 0 ? 0 : remaining / state.totalMs,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.label.isNotEmpty)
                        Text(state.label, style: theme.textTheme.titleMedium),
                      Text(
                        formatStopwatch(remaining + 999, tenths: false),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        state.isRunning
                            ? 'Ends ${formatTime(state.endsAt!, use24h: store.settings.use24HourClock)}'
                            : 'Paused',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: store.timerReset,
                icon: const Icon(Icons.stop),
                label: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () => store.timerExtend(const Duration(minutes: 1)),
                child: const Text('+1 min'),
              ),
              FilledButton.icon(
                onPressed:
                    state.isRunning ? store.timerPause : store.timerResume,
                icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
                label: Text(state.isRunning ? 'Pause' : 'Resume'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'A notification is scheduled for when the timer ends, so it works with the app closed if notifications are allowed.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }
    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 16),
        Center(
          child: Text(
            formatStopwatch(_duration.inMilliseconds, tenths: false),
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final minutes in _presets)
              ChoiceChip(
                label: Text(minutes == 60 ? '1 h' : '$minutes min'),
                selected: _duration == Duration(minutes: minutes),
                onSelected: (_) =>
                    setState(() => _duration = Duration(minutes: minutes)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _custom,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d:]'))
          ],
          decoration: const InputDecoration(
            labelText: 'Custom duration',
            hintText: 'Minutes, or h:mm:ss',
          ),
          onChanged: (value) {
            final parsed = _parseDuration(value);
            if (parsed != null) setState(() => _duration = parsed);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final label in _labels)
              ChoiceChip(
                label: Text(label),
                selected: _label == label,
                onSelected: (selected) =>
                    setState(() => _label = selected ? label : ''),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _duration.inSeconds <= 0
              ? null
              : () async {
                  await store.timerStart(_duration, label: _label);
                  if (context.mounted) await ensureReminderPermission(context);
                },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start timer'),
        ),
      ],
    );
  }

  static Duration? _parseDuration(String value) {
    final parts = value.split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.any((part) => part == null)) return null;
    final numbers = parts.cast<int>();
    final duration = switch (numbers.length) {
      1 => Duration(minutes: numbers[0]),
      2 => Duration(minutes: numbers[0], seconds: numbers[1]),
      3 =>
        Duration(hours: numbers[0], minutes: numbers[1], seconds: numbers[2]),
      _ => null,
    };
    if (duration == null || duration.inSeconds <= 0 || duration.inHours >= 24) {
      return null;
    }
    return duration;
  }
}

// ---------------------------------------------------------------------------
// Focus timer

class _FocusTab extends StatefulWidget {
  const _FocusTab({required this.store});

  final LifePilotStore store;

  @override
  State<_FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends State<_FocusTab> {
  late final _label =
      TextEditingController(text: widget.store.clock.focus.label);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final state = store.clock.focus;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final total =
        state.totalMs == 0 ? store.focusLengthMs(state.kind) : state.totalMs;
    final color = state.kind == FocusKind.focus
        ? theme.colorScheme.primary
        : colors.income;
    final stats = FocusStats.from(store.focusSessions, store.now());
    final recent = store.focusSessions.reversed.take(8).toList();
    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 8),
        Center(
          child: SegmentedButton<FocusKind>(
            showSelectedIcon: false,
            segments: [
              for (final kind in FocusKind.values)
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {state.kind},
            onSelectionChanged:
                state.isActive && state.remainingMs != state.totalMs
                    ? null
                    : (value) => store.updateClock(store.clock.copyWith(
                          focus: CountdownState(
                            label: state.label,
                            kind: value.first,
                            totalMs: store.focusLengthMs(value.first),
                            remainingMs: store.focusLengthMs(value.first),
                            completedFocusCount: state.completedFocusCount,
                          ),
                        )),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Tick(
            now: store.now,
            interval: Duration(milliseconds: state.isRunning ? 250 : 60000),
            builder: (context, now) {
              final remaining = state.isActive ? state.remaining(now) : total;
              return CountdownRing(
                progress: remaining / total,
                color: color,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.kind.label, style: theme.textTheme.titleMedium),
                    Text(
                      formatStopwatch(remaining + 999, tenths: false),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < state.completedFocusCount % 4
                                  ? color
                                  : theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _label,
          enabled: !state.isRunning,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What are you focusing on? (optional)',
            prefixIcon: Icon(Icons.edit_note),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (state.isActive && state.startedAt != null)
              OutlinedButton.icon(
                onPressed: store.focusStop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            FilledButton.icon(
              onPressed: () async {
                if (state.isRunning) {
                  await store.focusPause();
                } else if (state.isActive && state.startedAt != null) {
                  await store.focusResume();
                } else {
                  await store.focusStart(kind: state.kind, label: _label.text);
                  if (context.mounted) await ensureReminderPermission(context);
                }
              },
              icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
              label: Text(state.isRunning
                  ? 'Pause'
                  : state.isActive && state.startedAt != null
                      ? 'Resume'
                      : 'Start ${state.kind.label.toLowerCase()}'),
            ),
            IconButton(
              tooltip: 'Focus settings',
              onPressed: () => _settings(context),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        const SectionHeader(title: 'Focus statistics'),
        TileGrid(
          children: [
            StatTile(
                label: 'Today',
                value: formatDuration(Duration(minutes: stats.todayMinutes)),
                icon: Icons.today_outlined),
            StatTile(
                label: 'Sessions today',
                value: '${stats.completedToday}',
                icon: Icons.check_circle_outline),
            StatTile(
                label: 'This week',
                value: formatDuration(Duration(minutes: stats.weekMinutes)),
                icon: Icons.date_range),
            StatTile(
                label: 'Streak',
                value:
                    '${stats.streakDays} ${stats.streakDays == 1 ? 'day' : 'days'}',
                icon: Icons.local_fire_department_outlined),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SectionHeader(title: 'Recent sessions'),
          CardList(
            children: [
              for (final session in recent)
                ListTile(
                  dense: true,
                  leading: Icon(
                    session.completed ? Icons.check_circle : Icons.timelapse,
                    color: session.completed
                        ? colors.income
                        : theme.colorScheme.outline,
                  ),
                  title: Text(session.label.isEmpty
                      ? session.kind.label
                      : '${session.kind.label} · ${session.label}'),
                  subtitle: Text(formatDateTime(session.startedAt,
                      use24h: store.settings.use24HourClock)),
                  trailing: Text(
                      formatDuration(Duration(seconds: session.actualSeconds))),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _settings(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => AnimatedBuilder(
          animation: widget.store,
          builder: (sheetContext, _) {
            final settings = widget.store.settings;
            Widget slider(String label, int value, int max,
                    AppSettings Function(int) update) =>
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$label: $value min'),
                    Slider(
                      value: value.toDouble(),
                      min: 1,
                      max: max.toDouble(),
                      divisions: max - 1,
                      label: '$value',
                      onChanged: (v) =>
                          widget.store.updateSettings(update(v.round())),
                    ),
                  ],
                );
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Focus timer',
                        style: Theme.of(sheetContext).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    slider('Focus', settings.focusMinutes, 90,
                        (v) => settings.copyWith(focusMinutes: v)),
                    slider('Short break', settings.shortBreakMinutes, 30,
                        (v) => settings.copyWith(shortBreakMinutes: v)),
                    slider(
                        'Long break (after 4 sessions)',
                        settings.longBreakMinutes,
                        60,
                        (v) => settings.copyWith(longBreakMinutes: v)),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

// ---------------------------------------------------------------------------
// Alarms

class _AlarmsTab extends StatelessWidget {
  const _AlarmsTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final use24h = store.settings.use24HourClock;
    final now = store.now();
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
            title: 'Alarms',
            action: 'Add alarm',
            onAction: () => showAlarmForm(context, store)),
        if (store.alarms.isEmpty)
          EmptyState(
            icon: Icons.alarm,
            title: 'No alarms',
            message:
                'Set a time-of-day alert that repeats daily or on chosen days.',
            actionLabel: 'Add alarm',
            onAction: () => showAlarmForm(context, store),
          )
        else
          CardList(
            children: [
              for (final alarm in store.alarms)
                ListTile(
                  onTap: () => showAlarmForm(context, store, alarm: alarm),
                  title: Text(
                    formatTime(DateTime(2000, 1, 1, alarm.hour, alarm.minute),
                        use24h: use24h),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: alarm.enabled
                              ? null
                              : Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  subtitle: Text([
                    if (alarm.label.isNotEmpty) alarm.label,
                    alarm.weekdays.isEmpty
                        ? 'Every day'
                        : alarm.weekdays.map(weekdayShort).join(', '),
                    if (alarm.enabled)
                      'next ${formatRelative(alarm.nextFire(now), now)}',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: alarm.enabled,
                        onChanged: (value) =>
                            store.saveAlarm(alarm.copyWith(enabled: value)),
                      ),
                      IconButton(
                        tooltip: 'Delete alarm',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => store.deleteAlarm(alarm.id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          'Alarms are delivered as high-priority notifications using the alarm sound channel. '
          'For exact timing, allow “Alarms & reminders” in More › Notifications. '
          'They do not ring continuously or show a full-screen alarm like the system Clock app, and battery optimisation on some devices can delay them.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
