enum Repeat {
  none,
  daily,
  weekdays,
  weekly,
  monthly,
  quarterly,
  yearly,
  everyNDays
}

/// A recurrence rule. Dates are advanced on the local wall clock, so a
/// 7:00 PM daily reminder stays at 7:00 PM across daylight-saving changes.
class Recurrence {
  const Recurrence(this.repeat, {this.interval = 1, this.anchorDay});

  static const none = Recurrence(Repeat.none);

  final Repeat repeat;

  /// Number of days between occurrences when [repeat] is [Repeat.everyNDays].
  final int interval;

  /// Preferred day of month for monthly/quarterly/yearly rules, so that a bill
  /// due on the 31st returns to the 31st after a shorter month.
  final int? anchorDay;

  bool get isNone => repeat == Repeat.none;

  String get label => switch (repeat) {
        Repeat.none => 'Does not repeat',
        Repeat.daily => 'Every day',
        Repeat.weekdays => 'Every weekday',
        Repeat.weekly => 'Every week',
        Repeat.monthly => 'Every month',
        Repeat.quarterly => 'Every 3 months',
        Repeat.yearly => 'Every year',
        Repeat.everyNDays => 'Every $interval days',
      };

  DateTime? next(DateTime from) {
    switch (repeat) {
      case Repeat.none:
        return null;
      case Repeat.daily:
        return _addDays(from, 1);
      case Repeat.weekdays:
        var next = _addDays(from, 1);
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = _addDays(next, 1);
        }
        return next;
      case Repeat.weekly:
        return _addDays(from, 7);
      case Repeat.everyNDays:
        return _addDays(from, interval < 1 ? 1 : interval);
      case Repeat.monthly:
        return addMonths(from, 1, anchorDay: anchorDay);
      case Repeat.quarterly:
        return addMonths(from, 3, anchorDay: anchorDay);
      case Repeat.yearly:
        return addMonths(from, 12, anchorDay: anchorDay);
    }
  }

  /// First occurrence strictly after [after], starting from [start].
  DateTime? nextAfter(DateTime start, DateTime after, {int maxSteps = 5000}) {
    var current = start;
    for (var step = 0; step < maxSteps; step++) {
      if (current.isAfter(after)) return current;
      final next = this.next(current);
      if (next == null) return null;
      current = next;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'repeat': repeat.name,
        'interval': interval,
        if (anchorDay != null) 'anchorDay': anchorDay,
      };

  static Recurrence fromJson(Object? json) {
    if (json is! Map) return none;
    final name = json['repeat'];
    final repeat = Repeat.values.where((value) => value.name == name);
    if (repeat.isEmpty) return none;
    return Recurrence(
      repeat.first,
      interval: (json['interval'] as int?) ?? 1,
      anchorDay: json['anchorDay'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Recurrence &&
      other.repeat == repeat &&
      other.interval == interval &&
      other.anchorDay == anchorDay;

  @override
  int get hashCode => Object.hash(repeat, interval, anchorDay);
}

DateTime _addDays(DateTime date, int days) => DateTime(date.year, date.month,
    date.day + days, date.hour, date.minute, date.second);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime addMonths(DateTime date, int months, {int? anchorDay}) {
  final firstOfTarget = DateTime(date.year, date.month + months);
  final wanted = anchorDay ?? date.day;
  final maxDay = daysInMonth(firstOfTarget.year, firstOfTarget.month);
  return DateTime(
    firstOfTarget.year,
    firstOfTarget.month,
    wanted > maxDay ? maxDay : wanted,
    date.hour,
    date.minute,
    date.second,
  );
}
