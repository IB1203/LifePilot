import 'local_store.dart';
import 'models.dart';

/// Stopwatch, countdown and focus-timer operations. State is stored as
/// timestamps, so elapsed and remaining time stay correct when the app is in
/// the background or restarted.
extension ClockOps on LifePilotStore {
  // Stopwatch ---------------------------------------------------------------

  Future<void> stopwatchStart() async {
    if (clock.stopwatch.isRunning) return;
    await updateClock(clock.copyWith(
      stopwatch: StopwatchState(
        runningSince: now(),
        accumulatedMs: clock.stopwatch.accumulatedMs,
        lapsMs: clock.stopwatch.lapsMs,
      ),
    ));
  }

  Future<void> stopwatchPause() async {
    final state = clock.stopwatch;
    if (!state.isRunning) return;
    await updateClock(clock.copyWith(
      stopwatch: StopwatchState(
        accumulatedMs: state.elapsedMs(now()),
        lapsMs: state.lapsMs,
      ),
    ));
  }

  Future<void> stopwatchLap() async {
    final state = clock.stopwatch;
    if (!state.isRunning) return;
    await updateClock(clock.copyWith(
      stopwatch: StopwatchState(
        runningSince: state.runningSince,
        accumulatedMs: state.accumulatedMs,
        lapsMs: [...state.lapsMs, state.elapsedMs(now())],
      ),
    ));
  }

  Future<void> stopwatchReset() =>
      updateClock(clock.copyWith(stopwatch: const StopwatchState()));

  // Countdown timer -----------------------------------------------------------

  Future<void> timerStart(Duration duration, {String label = ''}) async {
    if (duration.inSeconds <= 0) return;
    final started = now();
    await updateClock(clock.copyWith(
      timer: CountdownState(
        label: label.trim(),
        totalMs: duration.inMilliseconds,
        remainingMs: duration.inMilliseconds,
        endsAt: started.add(duration),
        startedAt: started,
      ),
    ));
  }

  Future<void> timerPause() async {
    final state = clock.timer;
    if (!state.isRunning) return;
    await updateClock(clock.copyWith(
      timer: state.copyWith(
          remainingMs: state.remaining(now()), clearEndsAt: true),
    ));
  }

  Future<void> timerResume() async {
    final state = clock.timer;
    if (state.isRunning || state.remainingMs <= 0) return;
    await updateClock(clock.copyWith(
      timer: state.copyWith(
          endsAt: now().add(Duration(milliseconds: state.remainingMs))),
    ));
  }

  Future<void> timerReset() =>
      updateClock(clock.copyWith(timer: const CountdownState()));

  /// Adds time to an active timer, e.g. "+1 min".
  Future<void> timerExtend(Duration extra) async {
    final state = clock.timer;
    if (!state.isActive) return;
    await updateClock(clock.copyWith(
      timer: state.copyWith(
        totalMs: state.totalMs + extra.inMilliseconds,
        remainingMs:
            state.isRunning ? null : state.remainingMs + extra.inMilliseconds,
        endsAt: state.endsAt?.add(extra),
      ),
    ));
  }

  /// Clears a finished timer. Returns true when one had finished.
  Future<bool> settleTimer() async {
    final state = clock.timer;
    if (!state.isRunning || state.remaining(now()) > 0) return false;
    await timerReset();
    return true;
  }

  // Focus timer (Pomodoro) -----------------------------------------------------

  int focusLengthMs(FocusKind kind) => Duration(
              minutes: switch (kind) {
        FocusKind.focus => settings.focusMinutes,
        FocusKind.shortBreak => settings.shortBreakMinutes,
        FocusKind.longBreak => settings.longBreakMinutes,
      })
          .inMilliseconds;

  Future<void> focusStart({FocusKind? kind, String? label}) async {
    final state = clock.focus;
    final phase = kind ?? state.kind;
    final length = focusLengthMs(phase);
    final started = now();
    await updateClock(clock.copyWith(
      focus: CountdownState(
        label: (label ?? state.label).trim(),
        kind: phase,
        totalMs: length,
        remainingMs: length,
        endsAt: started.add(Duration(milliseconds: length)),
        startedAt: started,
        completedFocusCount: state.completedFocusCount,
      ),
    ));
  }

  Future<void> focusPause() async {
    final state = clock.focus;
    if (!state.isRunning) return;
    await updateClock(clock.copyWith(
      focus: state.copyWith(
          remainingMs: state.remaining(now()), clearEndsAt: true),
    ));
  }

  Future<void> focusResume() async {
    final state = clock.focus;
    if (state.isRunning || state.remainingMs <= 0) return;
    await updateClock(clock.copyWith(
      focus: state.copyWith(
          endsAt: now().add(Duration(milliseconds: state.remainingMs))),
    ));
  }

  /// Stops the current phase early, recording the time spent as incomplete.
  Future<void> focusStop() async {
    final state = clock.focus;
    if (!state.isActive) return;
    await _recordFocus(state, completed: false);
    await updateClock(clock.copyWith(
      focus: CountdownState(
        label: state.label,
        kind: FocusKind.focus,
        completedFocusCount: state.completedFocusCount,
      ),
    ));
  }

  /// Records a finished phase and prepares the next one (not started).
  /// Returns the finished phase, or null when nothing has finished.
  Future<FocusKind?> settleFocus() async {
    final state = clock.focus;
    if (!state.isRunning || state.remaining(now()) > 0) return null;
    await _recordFocus(state, completed: true);
    final completed =
        state.completedFocusCount + (state.kind == FocusKind.focus ? 1 : 0);
    final next = state.kind != FocusKind.focus
        ? FocusKind.focus
        : (completed % 4 == 0 ? FocusKind.longBreak : FocusKind.shortBreak);
    final length = focusLengthMs(next);
    await updateClock(clock.copyWith(
      focus: CountdownState(
        label: state.label,
        kind: next,
        totalMs: length,
        remainingMs: length,
        completedFocusCount: completed,
      ),
    ));
    return state.kind;
  }

  Future<void> _recordFocus(CountdownState state, {required bool completed}) {
    final elapsed = state.totalMs - state.remaining(now());
    return recordFocusSession(
      label: state.label,
      kind: state.kind,
      startedAt: state.startedAt ?? now(),
      plannedSeconds: state.totalMs ~/ 1000,
      actualSeconds: elapsed ~/ 1000,
      completed: completed,
    );
  }
}

/// Focus statistics over recorded sessions.
class FocusStats {
  const FocusStats({
    required this.todayMinutes,
    required this.weekMinutes,
    required this.completedToday,
    required this.streakDays,
  });

  final int todayMinutes;
  final int weekMinutes;
  final int completedToday;

  /// Consecutive days, ending today or yesterday, with a completed session.
  final int streakDays;

  factory FocusStats.from(List<FocusSession> sessions, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    var todaySeconds = 0;
    var weekSeconds = 0;
    var completedToday = 0;
    final activeDays = <DateTime>{};
    for (final session in sessions.where((s) => s.kind == FocusKind.focus)) {
      final day = DateTime(session.startedAt.year, session.startedAt.month,
          session.startedAt.day);
      if (day == today) {
        todaySeconds += session.actualSeconds;
        if (session.completed) completedToday++;
      }
      if (!day.isBefore(weekStart)) weekSeconds += session.actualSeconds;
      if (session.completed) activeDays.add(day);
    }
    var streak = 0;
    var cursor = activeDays.contains(today)
        ? today
        : DateTime(today.year, today.month, today.day - 1);
    while (activeDays.contains(cursor)) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return FocusStats(
      todayMinutes: todaySeconds ~/ 60,
      weekMinutes: weekSeconds ~/ 60,
      completedToday: completedToday,
      streakDays: streak,
    );
  }
}
