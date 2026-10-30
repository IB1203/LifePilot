/// Currency display settings. Amounts are always stored as integer minor
/// units (paise for INR); only the presentation is configurable.
class MoneyFormat {
  static String symbol = '₹';
}

const _monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdaysLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String formatMoney(int paise) {
  final negative = paise < 0;
  final absolute = paise.abs();
  final rupees = absolute ~/ 100;
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  final digits = rupees.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 &&
        (digits.length - index == 3 ||
            (digits.length - index > 3 &&
                (digits.length - index - 3) % 2 == 0))) {
      grouped.write(',');
    }
    grouped.write(digits[index]);
  }
  return '${negative ? '-' : ''}${MoneyFormat.symbol}$grouped.$fraction';
}

/// Whole-unit amount for compact labels such as chart axes, e.g. ₹3.2K.
String formatMoneyCompact(int paise) {
  final rupees = paise.abs() / 100;
  final sign = paise < 0 ? '-' : '';
  final symbol = MoneyFormat.symbol;
  if (rupees >= 10000000) {
    return '$sign$symbol${(rupees / 10000000).toStringAsFixed(1)}Cr';
  }
  if (rupees >= 100000) {
    return '$sign$symbol${(rupees / 100000).toStringAsFixed(1)}L';
  }
  if (rupees >= 1000) {
    return '$sign$symbol${(rupees / 1000).toStringAsFixed(1)}K';
  }
  return '$sign$symbol${rupees.round()}';
}

/// Plain decimal text for an amount, suitable for an editable field.
String paiseToInput(int paise) =>
    '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

int? parseRupeesToPaise(String input) {
  final normalized = input.trim().replaceAll(',', '');
  final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final rupees = int.tryParse(match.group(1)!);
  final fraction = int.tryParse((match.group(2) ?? '').padRight(2, '0')) ?? 0;
  if (rupees == null || rupees > (0x7fffffffffffffff - fraction) ~/ 100) {
    return null;
  }
  final amount = rupees * 100 + fraction;
  return amount > 0 ? amount : null;
}

String formatDate(DateTime date) =>
    '${date.day} ${_monthsShort[date.month - 1]} ${date.year}';

String formatShortDate(DateTime date) =>
    '${date.day} ${_monthsShort[date.month - 1]}';

String monthLabel(DateTime date) =>
    '${_monthsLong[date.month - 1]} ${date.year}';

String shortMonthLabel(DateTime date) => _monthsShort[date.month - 1];

String weekdayName(DateTime date) => _weekdaysLong[date.weekday - 1];

String weekdayShort(int isoWeekday) =>
    _weekdaysLong[isoWeekday - 1].substring(0, 3);

String formatLongDate(DateTime date) =>
    '${weekdayName(date)}, ${date.day} ${_monthsLong[date.month - 1]} ${date.year}';

String formatTime(DateTime time, {bool use24h = false, bool seconds = false}) {
  final minute = time.minute.toString().padLeft(2, '0');
  final second = seconds ? ':${time.second.toString().padLeft(2, '0')}' : '';
  if (use24h) {
    return '${time.hour.toString().padLeft(2, '0')}:$minute$second';
  }
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:$minute$second ${time.hour < 12 ? 'AM' : 'PM'}';
}

String formatDateTime(DateTime value, {bool use24h = false}) =>
    '${formatShortDate(value)}, ${formatTime(value, use24h: use24h)}';

/// "1h 05m", "12m", "45s".
String formatDuration(Duration duration) {
  final negative = duration.isNegative;
  final value = duration.abs();
  final days = value.inDays;
  final hours = value.inHours % 24;
  final minutes = value.inMinutes % 60;
  final String text;
  if (days > 0) {
    text = '${days}d ${hours}h';
  } else if (value.inHours > 0) {
    text = '${value.inHours}h ${minutes.toString().padLeft(2, '0')}m';
  } else if (value.inMinutes > 0) {
    text = '${value.inMinutes}m';
  } else {
    text = '${value.inSeconds}s';
  }
  return negative ? '-$text' : text;
}

/// Stopwatch-style text: "05:23.4" or "1:05:23.4".
String formatStopwatch(int milliseconds, {bool tenths = true}) {
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  final fraction = tenths ? '.${(duration.inMilliseconds % 1000) ~/ 100}' : '';
  return hours > 0
      ? '$hours:$minutes:$seconds$fraction'
      : '$minutes:$seconds$fraction';
}

/// "in 2h 15m", "5m ago", "now".
String formatRelative(DateTime target, DateTime now) {
  final difference = target.difference(now);
  if (difference.inSeconds.abs() < 60) return 'now';
  return difference.isNegative
      ? '${formatDuration(difference.abs())} ago'
      : 'in ${formatDuration(difference)}';
}

/// "Today", "Tomorrow", "Yesterday", weekday within a week, or a date.
String friendlyDay(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final difference = day.difference(today).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  if (difference == -1) return 'Yesterday';
  if (difference > 1 && difference < 7) return weekdayName(date);
  return date.year == now.year ? formatShortDate(date) : formatDate(date);
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String greetingFor(DateTime now) {
  if (now.hour < 5) return 'Good night';
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}
