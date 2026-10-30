import 'finance_calc.dart';
import 'formatters.dart';
import 'local_store.dart';
import 'clock_ops.dart';
import 'models.dart';
import 'personal.dart';
import 'recurrence.dart';
import 'task_logic.dart';

/// A write the assistant proposes. Nothing is saved until the user confirms
/// and [AssistantEngine.execute] runs it through the store.
sealed class AssistantAction {
  const AssistantAction();

  /// True for actions that remove data; the confirm button is styled as
  /// destructive.
  bool get destructive => false;
}

class AddBillAction extends AssistantAction {
  const AddBillAction({
    required this.name,
    required this.kind,
    required this.amountPaise,
    required this.dueAt,
    required this.recurrence,
  });

  final String name;
  final BillKind kind;
  final int amountPaise;
  final DateTime dueAt;
  final Recurrence recurrence;
}

class GoalContributionAction extends AssistantAction {
  const GoalContributionAction({
    required this.goalId,
    required this.goalName,
    required this.amountPaise,
  });

  final String goalId;
  final String goalName;
  final int amountPaise;
}

class StartTimerAction extends AssistantAction {
  const StartTimerAction({
    required this.minutes,
    this.label = '',
    this.focus = false,
  });

  final int minutes;
  final String label;
  final bool focus;
}

class CompleteItemAction extends AssistantAction {
  const CompleteItemAction({
    required this.id,
    required this.title,
    required this.isHabit,
  });

  final String id;
  final String title;
  final bool isHabit;
}

class DeleteEntryAction extends AssistantAction {
  const DeleteEntryAction({required this.entry});

  final LedgerEntry entry;

  @override
  bool get destructive => true;
}

class AddEntryAction extends AssistantAction {
  const AddEntryAction({
    required this.kind,
    required this.amountPaise,
    required this.category,
    required this.title,
    required this.occurredAt,
    this.duplicateWarning,
  });

  final EntryKind kind;
  final int amountPaise;
  final String category;
  final String title;
  final DateTime occurredAt;
  final String? duplicateWarning;
}

class AddTaskAction extends AssistantAction {
  const AddTaskAction({
    required this.title,
    this.dueAt,
    this.dueHasTime = false,
    this.remind = false,
  });

  final String title;
  final DateTime? dueAt;
  final bool dueHasTime;

  /// True for "remind me" requests: a reminder at the due time is added.
  final bool remind;
}

class AssistantReply {
  const AssistantReply(this.text, {this.proposal, this.isQuestion = false});

  final String text;
  final AssistantAction? proposal;

  /// True when the assistant is waiting for more information.
  final bool isQuestion;
}

/// Parsed date/time fragments and the text left after removing them.
class ParsedWhen {
  const ParsedWhen({
    this.date,
    this.hour,
    this.minute = 0,
    this.ambiguousHour = false,
    this.exact,
    required this.rest,
  });

  final DateTime? date;
  final int? hour;
  final int minute;

  /// True for "at 7" without AM/PM.
  final bool ambiguousHour;

  /// Set for relative times such as "in 2 hours".
  final DateTime? exact;
  final String rest;

  bool get hasTime => hour != null || exact != null;
  bool get isEmpty => date == null && !hasTime && !ambiguousHour;

  DateTime? resolve(DateTime now) {
    if (exact != null) return exact;
    if (date == null && hour == null) return null;
    final day = date ?? now;
    final candidate = DateTime(
        day.year, day.month, day.day, hour ?? 0, hour == null ? 0 : minute);
    // "at 7 pm" with no date means the next 7 PM.
    if (date == null && hour != null && !candidate.isAfter(now)) {
      return DateTime(day.year, day.month, day.day + 1, hour!, minute);
    }
    return candidate;
  }
}

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

ParsedWhen parseWhen(String input, DateTime now) {
  // Match against lowercase text but cut the same spans from the original,
  // so the remaining title keeps its capitalization.
  var text = ' ${input.toLowerCase()} ';
  var original = ' $input ';
  if (original.length != text.length) original = text;
  void cut(Match match) {
    final blank = ' ' * (match.end - match.start);
    text = text.replaceRange(match.start, match.end, blank);
    original = original.replaceRange(match.start, match.end, blank);
  }

  DateTime? date;
  int? hour;
  var minute = 0;
  var ambiguous = false;
  DateTime? exact;
  final today = DateTime(now.year, now.month, now.day);

  final relative =
      RegExp(r'\bin\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\b')
          .firstMatch(text);
  if (relative != null) {
    final amount = int.parse(relative.group(1)!);
    final unit = relative.group(2)!;
    if (unit.startsWith('d')) {
      date = DateTime(now.year, now.month, now.day + amount);
    } else if (unit.startsWith('w')) {
      date = DateTime(now.year, now.month, now.day + 7 * amount);
    } else {
      exact = now.add(unit.startsWith('h')
          ? Duration(hours: amount)
          : Duration(minutes: amount));
    }
    cut(relative);
  }

  final dayWords = <RegExp, DateTime>{
    RegExp(r'\bday after tomorrow\b'):
        DateTime(now.year, now.month, now.day + 2),
    RegExp(r'\btomorrow\b'): DateTime(now.year, now.month, now.day + 1),
    RegExp(r'\byesterday\b'): DateTime(now.year, now.month, now.day - 1),
    RegExp(r'\b(today|tonight|this evening|this morning)\b'): today,
    RegExp(r'\bnext week\b'): DateTime(now.year, now.month, now.day + 7),
  };
  for (final MapEntry(key: pattern, value: value) in dayWords.entries) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    date ??= value;
    if (match.group(0) == 'tonight' || match.group(0) == 'this evening') {
      hour ??= 20;
    }
    cut(match);
    break;
  }

  if (date == null) {
    final weekday = RegExp(
            r'\b(?:on\s+|next\s+|this\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b')
        .firstMatch(text);
    if (weekday != null) {
      final target = _weekdays.indexOf(weekday.group(1)!) + 1;
      var delta = (target - now.weekday + 7) % 7;
      if (delta == 0 || weekday.group(0)!.trim().startsWith('next')) {
        delta = delta == 0 ? 7 : delta;
      }
      date = DateTime(now.year, now.month, now.day + delta);
      cut(weekday);
    }
  }

  if (date == null) {
    final dayMonth = RegExp(
            r'\b(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b')
        .firstMatch(text);
    final monthDay = RegExp(
            r'\b(?:on\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{1,2})(?:st|nd|rd|th)?\b')
        .firstMatch(text);
    final numeric = RegExp(r'\b(?:on\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b')
        .firstMatch(text);
    final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(text);
    int? day;
    int? month;
    int? year;
    Match? matched;
    if (iso != null) {
      year = int.parse(iso.group(1)!);
      month = int.parse(iso.group(2)!);
      day = int.parse(iso.group(3)!);
      matched = iso;
    } else if (dayMonth != null) {
      day = int.parse(dayMonth.group(1)!);
      month = _months[dayMonth.group(2)!];
      matched = dayMonth;
    } else if (monthDay != null) {
      day = int.parse(monthDay.group(2)!);
      month = _months[monthDay.group(1)!];
      matched = monthDay;
    } else if (numeric != null) {
      // Day/month order, as commonly written in India.
      day = int.parse(numeric.group(1)!);
      month = int.parse(numeric.group(2)!);
      final rawYear = numeric.group(3);
      if (rawYear != null) {
        year = int.parse(rawYear);
        if (year < 100) year += 2000;
      }
      matched = numeric;
    }
    if (day != null &&
        month != null &&
        month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= 31) {
      var candidate = DateTime(year ?? now.year, month, day);
      if (year == null && candidate.isBefore(today)) {
        candidate = DateTime(now.year + 1, month, day);
      }
      if (candidate.month == month) {
        date = candidate;
        cut(matched!);
      }
    }
  }

  final clock = RegExp(
          r'\b(?:at\s+|by\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?=\s|$|[.,!?])')
      .firstMatch(text);
  final twentyFour = RegExp(r'\b(?:at\s+|by\s+)?([01]?\d|2[0-3]):([0-5]\d)\b')
      .firstMatch(text);
  final bare = RegExp(r'\b(?:at|by)\s+(\d{1,2})\b(?!\s*(?:%|rupees|rs))')
      .firstMatch(text);
  if (clock != null) {
    final rawHour = int.parse(clock.group(1)!);
    final pm = clock.group(3)!.startsWith('p');
    if (rawHour >= 1 && rawHour <= 12) {
      hour = (rawHour % 12) + (pm ? 12 : 0);
      minute = int.tryParse(clock.group(2) ?? '') ?? 0;
      cut(clock);
    }
  } else if (twentyFour != null) {
    hour = int.parse(twentyFour.group(1)!);
    minute = int.parse(twentyFour.group(2)!);
    cut(twentyFour);
  } else if (bare != null) {
    final rawHour = int.parse(bare.group(1)!);
    if (rawHour >= 13 && rawHour <= 23) {
      hour = rawHour;
    } else if (rawHour >= 1 && rawHour <= 12) {
      hour = rawHour;
      ambiguous = true;
    }
    if (hour != null) cut(bare);
  } else {
    final part =
        RegExp(r'\b(in the |this )?(morning|afternoon|evening|noon|midday)\b')
            .firstMatch(text);
    if (part != null) {
      hour = switch (part.group(2)) {
        'morning' => 9,
        'afternoon' => 14,
        'evening' => 18,
        _ => 12,
      };
      cut(part);
    }
  }

  return ParsedWhen(
    date: date,
    hour: ambiguous ? null : hour,
    minute: minute,
    ambiguousHour: ambiguous,
    exact: exact,
    rest: original.replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

/// Amount in paise from text such as "₹250", "rs 1,200.50" or "250 rupees".
/// Plain numbers are accepted only when [allowBare] is true.
int? parseAmount(String text, {bool allowBare = true}) {
  final marked = RegExp(
          r'(?:₹|\brs\.?|\binr)\s*(\d[\d,]*(?:\.\d{1,2})?)|(\d[\d,]*(?:\.\d{1,2})?)\s*(?:rupees|rs\b|inr\b|/-)',
          caseSensitive: false)
      .firstMatch(text);
  if (marked != null) {
    return parseRupeesToPaise(marked.group(1) ?? marked.group(2)!);
  }
  if (!allowBare) return null;
  for (final match in RegExp(r'(?<![\d:/])(\d[\d,]*(?:\.\d{1,2})?)(?![\d:/])')
      .allMatches(text)) {
    final after = text.substring(match.end).trimLeft().toLowerCase();
    if (RegExp(
            r'^(am|pm|a\.m|p\.m|st\b|nd\b|rd\b|th\b|minutes?|mins?|hours?|hrs?|days?|weeks?|%)')
        .hasMatch(after)) {
      continue;
    }
    final before = text.substring(0, match.start).toLowerCase();
    if (RegExp(r'\b(at|by|in)\s*$').hasMatch(before)) continue;
    return parseRupeesToPaise(match.group(1)!);
  }
  return null;
}

const _categoryKeywords = <String, List<String>>{
  'Food': [
    'food',
    'lunch',
    'dinner',
    'breakfast',
    'snack',
    'coffee',
    'tea',
    'grocer',
    'restaurant',
    'swiggy',
    'zomato',
    'meal',
    'vegetable',
    'fruit',
  ],
  'Transport': [
    'fuel',
    'petrol',
    'diesel',
    'uber',
    'ola',
    'cab',
    'taxi',
    'auto',
    'bus',
    'train',
    'metro',
    'parking',
    'toll',
    'transport',
  ],
  'Bills': [
    'electricity',
    'water bill',
    'internet',
    'wifi',
    'broadband',
    'recharge',
    'bill',
    'gas',
    'dth',
  ],
  'Home': ['rent', 'maintenance', 'furniture', 'repair'],
  'Health': ['medicine', 'doctor', 'pharmacy', 'hospital', 'clinic', 'gym'],
  'Shopping': ['amazon', 'flipkart', 'clothes', 'shoes', 'shopping'],
  'Entertainment': ['movie', 'netflix', 'concert', 'game', 'spotify'],
  'Education': ['book', 'course', 'tuition', 'fees', 'exam'],
  'Travel': ['flight', 'hotel', 'trip', 'travel'],
  'Salary': ['salary', 'payroll'],
  'Freelance': ['freelance', 'client'],
  'Interest': ['interest', 'dividend'],
  'Gifts': ['gift'],
  'Refunds': ['refund', 'cashback'],
  'Business': ['business', 'sales'],
};

const _incomeCategories = {
  'Salary',
  'Freelance',
  'Interest',
  'Gifts',
  'Refunds',
  'Business',
};

class _Awaiting {
  const _Awaiting.reminderTime(this.title)
      : kind = _AwaitKind.time,
        date = null,
        hour = null,
        minute = 0,
        entryKind = null,
        category = null;

  const _Awaiting.meridiem(this.title, this.date, this.hour, this.minute)
      : kind = _AwaitKind.meridiem,
        entryKind = null,
        category = null;

  const _Awaiting.amount(this.title, this.entryKind, this.category, this.date)
      : kind = _AwaitKind.amount,
        hour = null,
        minute = 0;

  final _AwaitKind kind;
  final String title;
  final DateTime? date;
  final int? hour;
  final int minute;
  final EntryKind? entryKind;
  final String? category;
}

enum _AwaitKind { time, meridiem, amount }

/// Deterministic, offline command processor. It reads data only through the
/// store and never runs generated code or queries.
class AssistantEngine {
  AssistantEngine(this.store);

  final LifePilotStore store;
  _Awaiting? _awaiting;

  static const helpText = 'I work offline with simple rules. Try:\n'
      '• Add ₹250 for lunch\n'
      '• Received 50000 salary\n'
      '• Create a task to finish the report tomorrow\n'
      '• Remind me to pay the electricity bill tomorrow at 7 PM\n'
      '• Show my expenses this month\n'
      '• Compare my expenses with last month\n'
      '• How much of my food budget remains?\n'
      '• Show my overdue tasks · Show my upcoming bills\n'
      '• Plan my day · How was my week?\n'
      '• Add electricity bill 1200 due on 5th\n'
      '• Add 2000 to my emergency fund\n'
      '• Start a 10 minute timer · Start focus\n'
      '• Mark report as done · Delete my last expense';

  AssistantReply handle(String input) {
    final text = input.trim();
    if (text.isEmpty) return const AssistantReply(helpText);
    final now = store.now();
    final lower = text.toLowerCase();

    final awaiting = _awaiting;
    _awaiting = null;
    if (awaiting != null &&
        !RegExp(r'^(cancel|never ?mind|stop)\b').hasMatch(lower)) {
      final answer = _answerClarification(awaiting, text, now);
      if (answer != null) return answer;
    } else if (awaiting != null) {
      return const AssistantReply('Okay, I dropped that request.');
    }

    if (RegExp(r'^(help|what can you do|commands?)\b').hasMatch(lower)) {
      return const AssistantReply(helpText);
    }

    final reminder = RegExp(
            r'^(?:please\s+)?(?:remind me|set (?:a )?reminder|reminder)\s*(?:to|about|for|that)?\s+(.+)$',
            caseSensitive: false)
        .firstMatch(text);
    if (reminder != null) {
      return _taskRequest(reminder.group(1)!, now, remind: true);
    }

    final task = RegExp(
            r'^(?:please\s+)?(?:create|add|new|make)\s+(?:a\s+)?(?:task|todo|to-do)\s*(?:to|:|for|called)?\s+(.+)$',
            caseSensitive: false)
        .firstMatch(text);
    if (task != null) return _taskRequest(task.group(1)!, now, remind: false);

    final special = _billRequest(text, now) ??
        _goalRequest(text) ??
        _timerRequest(lower) ??
        _deleteRequest(lower) ??
        _completeRequest(text);
    if (special != null) return special;

    final entry = _entryRequest(text, now);
    if (entry != null) return entry;

    return AssistantReply(_query(lower, now));
  }

  static const _billKinds = <BillKind, List<String>>{
    BillKind.electricity: ['electricity', 'power', 'bescom', 'tneb', 'msedcl'],
    BillKind.internet: ['internet', 'wifi', 'wi-fi', 'broadband', 'fiber'],
    BillKind.mobile: ['mobile', 'phone', 'recharge', 'postpaid', 'prepaid'],
    BillKind.rent: ['rent'],
    BillKind.loan: ['loan', 'emi'],
    BillKind.insurance: ['insurance', 'premium', 'lic'],
    BillKind.subscription: [
      'subscription',
      'netflix',
      'spotify',
      'prime',
      'hotstar',
      'youtube',
    ],
  };

  AssistantReply? _billRequest(String text, DateTime now) {
    final lower = text.toLowerCase();
    if (!RegExp(
            r'^(?:please\s+)?(?:add|create|new|track|set up)\b.*\b(?:bill|subscription|emi)\b')
        .hasMatch(lower)) {
      return null;
    }
    var kind = BillKind.other;
    for (final MapEntry(key: candidate, value: words) in _billKinds.entries) {
      if (words.any(lower.contains)) {
        kind = candidate;
        break;
      }
    }
    // "due on 5th" or "due on the 5th" means the next such day of month.
    DateTime? due;
    final dayOfMonth = RegExp(
            r'\b(?:due\s+)?(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b(?!\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec))')
        .firstMatch(lower);
    var rest = text;
    if (dayOfMonth != null) {
      final day = int.parse(dayOfMonth.group(1)!);
      if (day >= 1 && day <= 31) {
        var candidate =
            addMonths(DateTime(now.year, now.month, 1), 0, anchorDay: day);
        if (candidate.isBefore(dateOnly(now))) {
          candidate =
              addMonths(DateTime(now.year, now.month, 1), 1, anchorDay: day);
        }
        due = candidate;
        rest = rest.replaceRange(dayOfMonth.start, dayOfMonth.end, ' ');
      }
    }
    final when = parseWhen(rest, now);
    due ??= when.date;
    final amount = parseAmount(when.rest);
    if (amount == null || due == null) {
      return const AssistantReply(
          'Tell me the amount and due date, for example: “Add electricity bill 1200 due on 5th”.',
          isQuestion: true);
    }
    final recurrence =
        RegExp(r'\b(yearly|annual|annually|every year)\b').hasMatch(lower)
            ? const Recurrence(Repeat.yearly)
            : RegExp(r'\b(quarterly|every 3 months)\b').hasMatch(lower)
                ? const Recurrence(Repeat.quarterly)
                : RegExp(r'\b(one[- ]time|once)\b').hasMatch(lower)
                    ? Recurrence.none
                    : const Recurrence(Repeat.monthly);
    var name = when.rest
        .replaceAll(
            RegExp(
                r'(?:₹|\brs\.?|\binr)\s*\d[\d,]*(?:\.\d{1,2})?|\b\d[\d,]*(?:\.\d{1,2})?\b',
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(
                r'\b(please|add|create|new|track|set up|a|an|my|the|of|for|bill|due|on|monthly|yearly|annual|quarterly|every|month|year|one[- ]time|once|rupees|amount)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'[^\w\s&\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) name = kind.label;
    name = _capitalize(name);
    if (kind != BillKind.other &&
        !name.toLowerCase().contains('bill') &&
        kind != BillKind.subscription &&
        kind != BillKind.loan) {
      name = '$name bill';
    }
    return AssistantReply(
      'Bill “$name” for ${formatMoney(amount)}, ${recurrence.isNone ? 'one time' : recurrence.label.toLowerCase()}, next due ${formatDate(due)}. Confirm to start tracking it.',
      proposal: AddBillAction(
        name: name,
        kind: kind,
        amountPaise: amount,
        dueAt: due,
        recurrence: recurrence,
      ),
    );
  }

  AssistantReply? _goalRequest(String text) {
    if (store.goals.isEmpty) return null;
    final match = RegExp(
            r'^(?:please\s+)?(?:add|put|save|contribute|move|deposit)\s+(.+?)\s+(?:to|into|towards|for|in)\s+(?:my\s+|the\s+)?(.+?)(?:\s+goal)?[.!]?$',
            caseSensitive: false)
        .firstMatch(text);
    if (match == null) return null;
    final target =
        match.group(2)!.toLowerCase().replaceAll(RegExp(r'\s+goal$'), '');
    final goals = store.goals.where((goal) {
      final name = goal.name.toLowerCase();
      return name == target || name.contains(target) || target.contains(name);
    }).toList();
    if (goals.length != 1) return null;
    final amount = parseAmount(match.group(1)!);
    if (amount == null) return null;
    final goal = goals.single;
    final after = goal.savedPaise + amount;
    return AssistantReply(
      'Add ${formatMoney(amount)} to “${goal.name}”? It would reach ${formatMoney(after)} of ${formatMoney(goal.targetPaise)}.',
      proposal: GoalContributionAction(
          goalId: goal.id, goalName: goal.name, amountPaise: amount),
    );
  }

  AssistantReply? _timerRequest(String lower) {
    if (!RegExp(r'\b(start|begin|set|run)\b').hasMatch(lower) ||
        !RegExp(r'\b(timer|focus|pomodoro|countdown)\b').hasMatch(lower)) {
      return null;
    }
    final focus = RegExp(r'\b(focus|pomodoro)\b').hasMatch(lower);
    final length = RegExp(
            r'(\d{1,3})\s*(?:-\s*)?(min|mins|minute|minutes|hour|hours|hr|hrs|h)\b')
        .firstMatch(lower);
    var minutes = length == null
        ? null
        : int.parse(length.group(1)!) *
            (length.group(2)!.startsWith('h') ? 60 : 1);
    if (focus && minutes == null) minutes = store.settings.focusMinutes;
    if (minutes == null || minutes <= 0 || minutes > 24 * 60) {
      return const AssistantReply(
          'How long should the timer run? For example: “Start a 10 minute timer”.',
          isQuestion: true);
    }
    final label = RegExp(r'\bfor\s+([a-z][a-z ]{1,30})$')
            .firstMatch(lower)
            ?.group(1)
            ?.trim() ??
        '';
    return AssistantReply(
      focus
          ? 'Start a ${store.settings.focusMinutes}-minute focus session${label.isEmpty ? '' : ' on $label'}?'
          : 'Start a $minutes-minute timer${label.isEmpty ? '' : ' for $label'}?',
      proposal: StartTimerAction(
          minutes: minutes, label: _capitalize(label), focus: focus),
    );
  }

  AssistantReply? _deleteRequest(String lower) {
    final match = RegExp(
            r'\b(delete|remove|undo)\b.*\b(last|latest|previous|recent)\b.*\b(expense|income|transaction|entry)\b')
        .firstMatch(lower);
    if (match == null) return null;
    final noun = match.group(3)!;
    final candidates = store.entries.where((entry) => switch (noun) {
          'expense' => entry.kind == EntryKind.expense,
          'income' => entry.kind == EntryKind.income,
          _ => true,
        });
    if (candidates.isEmpty) {
      return AssistantReply('There is no recorded $noun to delete.');
    }
    final entry = candidates.last;
    return AssistantReply(
      'Delete the most recently added ${entry.isIncome ? 'income' : 'expense'}: “${entry.title}”, ${formatMoney(entry.amountPaise)} on ${formatDate(entry.occurredAt)}? This cannot be undone here.',
      proposal: DeleteEntryAction(entry: entry),
    );
  }

  AssistantReply? _completeRequest(String text) {
    final match = RegExp(
            r'^(?:please\s+)?(?:mark|tick|complete|check off|check in|i (?:did|finished|completed))\s+(?:the\s+|my\s+)?(?:task\s+|habit\s+)?(.+?)(?:\s+(?:as\s+)?(?:done|complete|completed|finished))?(?:\s+today)?[.!]?$',
            caseSensitive: false)
        .firstMatch(text);
    if (match == null) return null;
    final name = match.group(1)!.trim().toLowerCase();
    if (name.isEmpty) return null;
    bool matches(String title) {
      final lower = title.toLowerCase();
      return lower == name || lower.contains(name) || name.contains(lower);
    }

    final today = store.now();
    final habits = store.habits
        .where((habit) => !habit.archived && matches(habit.name))
        .toList();
    final tasks = store.tasks
        .where((task) => !task.isDone && matches(task.title))
        .toList();
    final found = habits.length + tasks.length;
    if (found == 0) {
      return AssistantReply(
          'I could not find an open task or habit matching “${match.group(1)}”.');
    }
    if (found > 1) {
      final names = [
        for (final task in tasks) '• ${task.title} (task)',
        for (final habit in habits) '• ${habit.name} (habit)',
      ].take(6).join('\n');
      return AssistantReply('Which one do you mean?\n$names', isQuestion: true);
    }
    if (habits.isNotEmpty) {
      final habit = habits.single;
      if (habit.doneOn(today)) {
        return AssistantReply(
            '“${habit.name}” is already checked in for today.');
      }
      return AssistantReply('Check in “${habit.name}” for today?',
          proposal: CompleteItemAction(
              id: habit.id, title: habit.name, isHabit: true));
    }
    final task = tasks.single;
    return AssistantReply(
        'Mark “${task.title}” as done${task.recurrence.isNone ? '' : ' (the next occurrence will be scheduled)'}?',
        proposal:
            CompleteItemAction(id: task.id, title: task.title, isHabit: false));
  }

  AssistantReply? _answerClarification(
      _Awaiting awaiting, String text, DateTime now) {
    final when = parseWhen(text, now);
    switch (awaiting.kind) {
      case _AwaitKind.time:
        if (when.isEmpty) return null;
        return _taskFromWhen(awaiting.title, when, now, remind: true);
      case _AwaitKind.meridiem:
        final lower = text.toLowerCase();
        final pm =
            RegExp(r'\b(pm|p\.m|evening|night|afternoon)\b').hasMatch(lower);
        final am = RegExp(r'\b(am|a\.m|morning)\b').hasMatch(lower);
        if (pm == am) {
          if (!when.isEmpty) {
            return _taskFromWhen(awaiting.title, when, now, remind: true);
          }
          return null;
        }
        final hour = (awaiting.hour! % 12) + (pm ? 12 : 0);
        return _taskFromWhen(
          awaiting.title,
          ParsedWhen(
              date: awaiting.date,
              hour: hour,
              minute: awaiting.minute,
              rest: ''),
          now,
          remind: true,
        );
      case _AwaitKind.amount:
        final amount = parseAmount(text);
        if (amount == null) return null;
        return _proposeEntry(awaiting.entryKind!, amount, awaiting.category!,
            awaiting.title, awaiting.date ?? now, now);
    }
  }

  AssistantReply _taskRequest(String body, DateTime now,
      {required bool remind}) {
    final when = parseWhen(body, now);
    final title = _cleanTitle(when.rest);
    if (title.isEmpty) {
      return const AssistantReply(
          'What should the task be called? For example: “Create a task to call the bank tomorrow”.',
          isQuestion: true);
    }
    if (when.ambiguousHour) {
      final rawHour =
          RegExp(r'\b(?:at|by)\s+(\d{1,2})').firstMatch(body.toLowerCase());
      final hour = int.tryParse(rawHour?.group(1) ?? '') ?? 0;
      _awaiting = _Awaiting.meridiem(title, when.date, hour, when.minute);
      return AssistantReply('Did you mean $hour AM or $hour PM?',
          isQuestion: true);
    }
    if (remind && !when.hasTime) {
      if (when.date == null) {
        _awaiting = _Awaiting.reminderTime(title);
        return AssistantReply(
            'When should I remind you to $title? For example: “tomorrow at 9 AM”.',
            isQuestion: true);
      }
    }
    return _taskFromWhen(title, when, now, remind: remind);
  }

  AssistantReply _taskFromWhen(String title, ParsedWhen when, DateTime now,
      {required bool remind}) {
    var due = when.resolve(now);
    var hasTime = when.hasTime;
    if (remind && due != null && !hasTime) {
      // A reminder for a day without a time goes off at 9 AM.
      due = DateTime(due.year, due.month, due.day, 9);
      hasTime = true;
    }
    if (due != null && hasTime && !due.isAfter(now)) {
      return AssistantReply(
          '${formatDateTime(due, use24h: store.settings.use24HourClock)} has already passed. Please choose a later time.',
          isQuestion: true);
    }
    final proposal = AddTaskAction(
      title: _capitalize(title),
      dueAt: due,
      dueHasTime: hasTime,
      remind: remind || hasTime,
    );
    final when24 = store.settings.use24HourClock;
    final description = due == null
        ? 'with no due date'
        : hasTime
            ? 'due ${friendlyDay(due, now).toLowerCase()} at ${formatTime(due, use24h: when24)}'
            : 'due ${friendlyDay(due, now).toLowerCase()}';
    return AssistantReply(
      '${remind ? 'Reminder' : 'Task'} “${proposal.title}” $description. Review and confirm below.',
      proposal: proposal,
    );
  }

  AssistantReply? _entryRequest(String text, DateTime now) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(task|remind|reminder|budget|compare|show|how much|what)\b')
        .hasMatch(lower)) {
      return null;
    }
    final isIncome = RegExp(
            r'\b(income|received|receive|earned|got paid|salary|credited|refund)\b')
        .hasMatch(lower);
    final isExpense = RegExp(
            r'\b(spent|spend|expense|paid|pay|bought|buy|add|debited|cost)\b')
        .hasMatch(lower);
    if (!isIncome && !isExpense) return null;
    final kind = isIncome ? EntryKind.income : EntryKind.expense;
    final when = parseWhen(text, now);
    final amount = parseAmount(when.rest);
    final category = _inferCategory(lower, kind);
    final title = _entryTitle(when.rest, kind);
    final date = when.date;
    final occurredAt = date == null
        ? now
        : isSameDay(date, now)
            ? now
            : DateTime(date.year, date.month, date.day, 12);
    if (occurredAt.isAfter(now.add(const Duration(minutes: 1)))) {
      return const AssistantReply(
          'That date is in the future. I only record transactions that have happened. You can add a bill or task instead.');
    }
    if (amount == null) {
      if (!RegExp(r'\b(spent|paid|bought|received|earned|expense|income)\b')
          .hasMatch(lower)) {
        return null;
      }
      _awaiting = _Awaiting.amount(title, kind, category, occurredAt);
      return AssistantReply('How much was “$title”?', isQuestion: true);
    }
    return _proposeEntry(kind, amount, category, title, occurredAt, now);
  }

  AssistantReply _proposeEntry(EntryKind kind, int amount, String category,
      String title, DateTime occurredAt, DateTime now) {
    final candidate = LedgerEntry(
      id: '',
      kind: kind,
      amountPaise: amount,
      category: category,
      title: title,
      occurredAt: occurredAt,
    );
    final duplicates = findPossibleDuplicates(store.entries, candidate,
        window: const Duration(hours: 12));
    final warning = duplicates.isEmpty
        ? null
        : 'A similar ${kind.name} of ${formatMoney(amount)} (“${duplicates.first.title}”) was recorded ${friendlyDay(duplicates.first.occurredAt, now).toLowerCase()}.';
    return AssistantReply(
      'I prepared ${kind == EntryKind.income ? 'income' : 'an expense'} of ${formatMoney(amount)} in $category for ${friendlyDay(occurredAt, now).toLowerCase()}. Nothing is saved until you confirm.',
      proposal: AddEntryAction(
        kind: kind,
        amountPaise: amount,
        category: category,
        title: title,
        occurredAt: occurredAt,
        duplicateWarning: warning,
      ),
    );
  }

  /// Runs a confirmed action through the store and reports the stored result.
  Future<String> execute(AssistantAction action) async {
    switch (action) {
      case AddBillAction():
        final bill = await store.addBill(
          name: action.name,
          kind: action.kind,
          amountPaise: action.amountPaise,
          nextDueAt: action.dueAt,
          recurrence: action.recurrence,
        );
        if (store.billById(bill.id) == null) {
          return 'The bill could not be verified after saving. Please check Finance › Bills.';
        }
        return 'Tracking “${bill.name}”: ${formatMoney(bill.amountPaise)}, next due ${formatDate(bill.nextDueAt)}. You will be reminded ${bill.remindDaysBefore} days before, if notifications are allowed.';
      case GoalContributionAction():
        await store.contributeToGoal(action.goalId, action.amountPaise,
            note: 'Added by assistant');
        final goal =
            store.goals.where((item) => item.id == action.goalId).firstOrNull;
        if (goal == null) return 'That goal no longer exists.';
        return 'Added ${formatMoney(action.amountPaise)} to “${goal.name}”. Saved ${formatMoney(goal.savedPaise)} of ${formatMoney(goal.targetPaise)} (${(goal.progress * 100).round()}%).';
      case StartTimerAction():
        if (action.focus) {
          await store.focusStart(kind: FocusKind.focus, label: action.label);
          final ends = store.clock.focus.endsAt!;
          return 'Focus session started. It ends at ${formatTime(ends, use24h: store.settings.use24HourClock)}.';
        }
        await store.timerStart(Duration(minutes: action.minutes),
            label: action.label);
        final ends = store.clock.timer.endsAt!;
        return 'Timer started for ${action.minutes} minutes. It ends at ${formatTime(ends, use24h: store.settings.use24HourClock)}.';
      case CompleteItemAction():
        if (action.isHabit) {
          final habit =
              store.habits.where((item) => item.id == action.id).firstOrNull;
          if (habit == null) return 'That habit no longer exists.';
          if (!habit.doneOn(store.now())) await store.toggleHabit(action.id);
          final updated =
              store.habits.firstWhere((item) => item.id == action.id);
          return 'Checked in “${updated.name}”. Current streak: ${habitStreak(updated, store.now())} days.';
        }
        await store.setTaskStatus(action.id, TaskStatus.done);
        final task = store.taskById(action.id);
        if (task == null) return 'That task no longer exists.';
        return task.isDone
            ? 'Marked “${task.title}” as done.'
            : 'Completed “${task.title}”. Next occurrence: ${formatDate(task.dueAt!)}.';
      case DeleteEntryAction():
        await store.deleteEntry(action.entry.id);
        return store.entries.any((entry) => entry.id == action.entry.id)
            ? 'The entry could not be deleted.'
            : 'Deleted “${action.entry.title}” (${formatMoney(action.entry.amountPaise)}).';
      case AddEntryAction():
        final saved = await store.addEntry(
          kind: action.kind,
          amountPaise: action.amountPaise,
          category: action.category,
          title: action.title,
          occurredAt: action.occurredAt,
          note: 'Added by assistant',
        );
        if (!store.entries.any((entry) => entry.id == saved.id)) {
          return 'The transaction could not be verified after saving. Please check Finance.';
        }
        final monthTotal = store.spentInCategory(saved.category);
        return 'Saved ${saved.isIncome ? 'income' : 'expense'} “${saved.title}” for ${formatMoney(saved.amountPaise)} (${saved.category}, ${formatDate(saved.occurredAt)}).'
            '${saved.isIncome ? '' : '\n${saved.category} spending this month: ${formatMoney(monthTotal)}.'}';
      case AddTaskAction():
        final saved = await store.addTask(
          title: action.title,
          project: '',
          dueAt: action.dueAt,
          dueHasTime: action.dueHasTime,
          reminderOffsets:
              action.remind && action.dueAt != null ? const [0] : const [],
        );
        if (store.taskById(saved.id) == null) {
          return 'The task could not be verified after saving. Please check Tasks.';
        }
        final due = saved.dueAt;
        final use24h = store.settings.use24HourClock;
        return 'Saved task “${saved.title}”'
            '${due == null ? '' : saved.dueHasTime ? ' for ${formatDateTime(due, use24h: use24h)}' : ' due ${formatDate(due)}'}.'
            '${saved.reminderOffsets.isEmpty ? '' : '\nA notification is scheduled for ${formatDateTime(due!.subtract(Duration(minutes: saved.reminderOffsets.first)), use24h: use24h)}, if notifications are allowed.'}';
    }
  }

  String _query(String lower, DateTime now) {
    if (RegExp(r'\b(week|weekly)\b').hasMatch(lower) &&
        RegExp(r'\b(summary|review|how was|recap)\b').hasMatch(lower)) {
      return _weekly(now, previous: lower.contains('last week'));
    }
    if (lower.contains('overdue')) return _overdue(now);
    if (RegExp(r'\bplan\b.*\b(day|today)\b').hasMatch(lower)) {
      return _planDay(now);
    }
    if (lower.contains('compare') ||
        (lower.contains('last month') && lower.contains('vs'))) {
      return _compare(now);
    }
    if (lower.contains('bill')) return _bills(now);
    if (lower.contains('budget') || lower.contains('limit')) {
      return _budget(lower, now);
    }
    if (lower.contains('goal') || lower.contains('saving')) return _goals(now);
    if (RegExp(r'\b(cash ?flow|balance|net)\b').hasMatch(lower)) {
      final summary = store.thisMonth;
      return 'Recorded cash flow in ${monthLabel(now)}: ${formatMoney(summary.netCashFlow)}\n'
          '(${formatMoney(summary.income)} income − ${formatMoney(summary.expenses)} expenses). '
          'This is not net worth or a bank balance.';
    }
    if (RegExp(r'\b(spend|spent|expense|expenses|spending)\b')
        .hasMatch(lower)) {
      return _totals(lower, now, EntryKind.expense);
    }
    if (RegExp(r'\b(income|earn|earned|received)\b').hasMatch(lower)) {
      return _totals(lower, now, EntryKind.income);
    }
    if (RegExp(r'\b(task|tasks|todo|due|today|agenda|schedule)\b')
        .hasMatch(lower)) {
      return _todayTasks(now);
    }
    return 'I did not understand that.\n\n$helpText';
  }

  ({DateRange range, String label}) _period(String lower, DateTime now) {
    if (lower.contains('last month')) {
      return (
        range: monthRange(now, offset: -1),
        label: monthLabel(DateTime(now.year, now.month - 1))
      );
    }
    if (lower.contains('today')) return (range: dayRange(now), label: 'today');
    if (lower.contains('yesterday')) {
      return (range: dayRange(now, offset: -1), label: 'yesterday');
    }
    if (lower.contains('last week')) {
      return (range: weekRange(now, offset: -1), label: 'last week');
    }
    if (lower.contains('week')) {
      return (range: weekRange(now), label: 'this week');
    }
    if (lower.contains('year')) {
      return (range: yearRange(now), label: '${now.year}');
    }
    return (range: monthRange(now), label: monthLabel(now));
  }

  String _totals(String lower, DateTime now, EntryKind kind) {
    final period = _period(lower, now);
    final category = _mentionedCategory(lower);
    final total = sumEntries(store.entries,
        kind: kind, range: period.range, category: category);
    final noun = kind == EntryKind.expense ? 'Expenses' : 'Income';
    final scope = category == null ? '' : ' in $category';
    final count = store.entries
        .where((entry) =>
            entry.kind == kind &&
            period.range.contains(entry.occurredAt) &&
            (category == null || entry.category == category))
        .length;
    if (count == 0) {
      return 'No ${noun.toLowerCase()}$scope recorded for ${period.label}.';
    }
    final buffer = StringBuffer(
        '$noun$scope recorded for ${period.label}: ${formatMoney(total)} across $count ${count == 1 ? 'entry' : 'entries'}.');
    if (category == null) {
      final top = categoryTotals(store.entries, period.range, kind: kind)
          .entries
          .take(3);
      buffer.write('\nTop categories: ');
      buffer.write(top
          .map((item) => '${item.key} ${formatMoney(item.value)}')
          .join(' · '));
    }
    return buffer.toString();
  }

  String _compare(DateTime now) {
    final current = DateRange(monthRange(now).start, now);
    final previousStart = DateTime(now.year, now.month - 1);
    final previousDays = DateTime(now.year, now.month, 0).day;
    final sameDay = now.day > previousDays ? previousDays : now.day;
    final previousToDate = DateRange(
        previousStart,
        DateTime(previousStart.year, previousStart.month, sameDay, now.hour,
            now.minute));
    final thisTotal =
        sumEntries(store.entries, kind: EntryKind.expense, range: current);
    final lastToDate = sumEntries(store.entries,
        kind: EntryKind.expense, range: previousToDate);
    final lastFull = sumEntries(store.entries,
        kind: EntryKind.expense, range: monthRange(now, offset: -1));
    if (thisTotal == 0 && lastFull == 0) {
      return 'There are no expenses recorded this month or last month to compare.';
    }
    final difference = thisTotal - lastToDate;
    final direction = difference == 0
        ? 'the same as'
        : difference > 0
            ? '${formatMoney(difference)} more than'
            : '${formatMoney(-difference)} less than';
    final buffer = StringBuffer(
        'So far in ${monthLabel(now)} (1–${now.day}): ${formatMoney(thisTotal)}.\n'
        'Same period of ${monthLabel(previousStart)} (1–$sameDay): ${formatMoney(lastToDate)}.\n'
        'You have spent $direction last month at this point.\n'
        'All of ${monthLabel(previousStart)}: ${formatMoney(lastFull)}.');
    final currentCategories = categoryTotals(store.entries, current);
    final previousCategories = categoryTotals(store.entries, previousToDate);
    final changes = {
      for (final category in {
        ...currentCategories.keys,
        ...previousCategories.keys
      })
        category: (currentCategories[category] ?? 0) -
            (previousCategories[category] ?? 0),
    }.entries.where((item) => item.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    if (changes.isNotEmpty) {
      buffer.write('\nBiggest changes: ');
      buffer.write(changes
          .take(3)
          .map((item) =>
              '${item.key} ${item.value > 0 ? '+' : '−'}${formatMoney(item.value.abs())}')
          .join(' · '));
    }
    return buffer.toString();
  }

  String _budget(String lower, DateTime now) {
    if (store.budgets.isEmpty) return 'You have not set any budgets yet.';
    final category = _mentionedCategory(lower);
    final budgets = category == null
        ? store.budgets
        : store.budgets.where((budget) => budget.category == category).toList();
    if (budgets.isEmpty) return 'There is no budget for $category yet.';
    final lines = budgets.map((budget) {
      final status = budgetStatus(budget, store.entries, now);
      final period =
          budget.period == BudgetPeriod.weekly ? 'this week' : 'this month';
      return status.isOver
          ? '${budget.category}: ${formatMoney(status.spentPaise)} spent of ${formatMoney(status.limitPaise)} — ${formatMoney(-status.remainingPaise)} over $period.'
          : '${budget.category}: ${formatMoney(status.remainingPaise)} remains of ${formatMoney(status.limitPaise)} $period (${status.utilizationPercent}% used).';
    });
    return lines.join('\n');
  }

  String _bills(DateTime now) {
    final bills = upcomingBills(store.bills, now, withinDays: 30);
    if (bills.isEmpty) return 'No bills are due in the next 30 days.';
    return 'Upcoming bills:\n${bills.map((bill) {
      final overdue = isBillOverdue(bill, now);
      return '• ${bill.name}: ${formatMoney(bill.amountPaise)} ${overdue ? 'overdue since' : 'due'} ${friendlyDay(bill.nextDueAt, now).toLowerCase()}';
    }).join('\n')}';
  }

  String _goals(DateTime now) {
    if (store.goals.isEmpty) return 'You have no savings goals yet.';
    return store.goals.map((goal) {
      final suggestion = suggestedMonthlyContribution(goal, now);
      return '${goal.name}: ${formatMoney(goal.savedPaise)} of ${formatMoney(goal.targetPaise)} (${(goal.progress * 100).round()}%)'
          '${suggestion == null ? '' : ' · about ${formatMoney(suggestion)}/month to reach it by ${formatDate(goal.targetDate!)}'}';
    }).join('\n');
  }

  String _weekly(DateTime now, {bool previous = false}) {
    final review = WeeklyReview.build(
      entries: store.entries,
      tasks: store.tasks,
      sessions: store.focusSessions,
      habits: store.habits,
      budgets: store.budgets,
      bills: store.bills,
      now: now,
      previousWeek: previous,
    );
    final lines = [
      '${previous ? 'Last week' : 'This week'} (${formatShortDate(review.range.start)}–${formatShortDate(review.range.end.subtract(const Duration(days: 1)))}):',
      '• Tasks completed: ${review.tasksCompleted}${review.tasksOverdue == 0 ? '' : ' · overdue now: ${review.tasksOverdue}'}',
      '• Focus: ${formatDuration(Duration(minutes: review.focusMinutes))} in ${review.focusSessions} completed sessions',
      if (review.habitRate != null)
        '• Habits: ${(review.habitRate! * 100).round()}% of check-ins done',
      '• Spent ${formatMoney(review.summary.expenses)} (previous week ${formatMoney(review.previousExpenses)}); income ${formatMoney(review.summary.income)}',
      if (review.topCategories.isNotEmpty)
        '• Top spending: ${review.topCategories.entries.map((item) => '${item.key} ${formatMoney(item.value)}').join(', ')}',
      if (review.nextWeekBills.isNotEmpty)
        '• Bills next week: ${review.nextWeekBills.map((bill) => '${bill.name} ${formatMoney(bill.amountPaise)}').join(', ')}',
    ];
    return lines.join('\n');
  }

  String _overdue(DateTime now) {
    final overdue = TaskBuckets.from(store.tasks, now).overdue;
    if (overdue.isEmpty) return 'You have no overdue tasks.';
    return 'Overdue tasks (${overdue.length}):\n${overdue.map((task) => '• ${task.title} — due ${formatDate(task.dueAt!)}').join('\n')}';
  }

  String _todayTasks(DateTime now) {
    final buckets = TaskBuckets.from(store.tasks, now);
    if (buckets.today.isEmpty && buckets.overdue.isEmpty) {
      return 'Nothing is due today.${buckets.upcoming.isEmpty ? '' : ' Next up: ${buckets.upcoming.first.title} (${friendlyDay(buckets.upcoming.first.dueAt!, now)}).'}';
    }
    final use24h = store.settings.use24HourClock;
    final lines = [
      for (final task in buckets.today)
        '• ${task.title}${task.dueHasTime ? ' at ${formatTime(task.dueAt!, use24h: use24h)}' : ''}',
      for (final task in buckets.overdue) '• ${task.title} (overdue)',
    ];
    return 'Due today (${buckets.today.length})${buckets.overdue.isEmpty ? '' : ' and overdue (${buckets.overdue.length})'}:\n${lines.join('\n')}';
  }

  String _planDay(DateTime now) {
    final plan = planDay(store.tasks, now);
    if (plan.isEmpty) {
      return 'There are no open tasks for today to plan. Add tasks with due dates or estimates and ask again.';
    }
    final use24h = store.settings.use24HourClock;
    return 'Suggested plan for today (not saved):\n${plan.map((block) => '• ${formatTime(block.start, use24h: use24h)}–${formatTime(block.end, use24h: use24h)} ${block.task.title}${block.fixed ? '' : ' (suggested)'}${isOverdue(block.task, now) ? ' · overdue' : ''}').join('\n')}\n'
        'Fixed-time tasks keep their times; others are ordered by overdue status and priority.';
  }

  String? _mentionedCategory(String lower) {
    for (final category in store.categories) {
      if (RegExp('\\b${RegExp.escape(category.toLowerCase())}\\b')
          .hasMatch(lower)) {
        return category;
      }
    }
    for (final MapEntry(key: category, value: words)
        in _categoryKeywords.entries) {
      if (words.any((word) => lower.contains(word)) &&
          store.categories.contains(category)) {
        return category;
      }
    }
    return null;
  }

  String _inferCategory(String lower, EntryKind kind) {
    for (final category in store.categories) {
      if (RegExp('\\b${RegExp.escape(category.toLowerCase())}\\b')
              .hasMatch(lower) &&
          (kind == EntryKind.income) == _incomeCategories.contains(category)) {
        return category;
      }
    }
    for (final MapEntry(key: category, value: words)
        in _categoryKeywords.entries) {
      if ((kind == EntryKind.income) != _incomeCategories.contains(category)) {
        continue;
      }
      if (words.any((word) => lower.contains(word))) return category;
    }
    return 'Other';
  }

  String _entryTitle(String rest, EntryKind kind) {
    final purpose =
        RegExp(r'\b(?:for|on|from|at)\s+(.+)$', caseSensitive: false)
            .firstMatch(rest);
    var title = purpose?.group(1) ?? rest;
    title = title
        .replaceAll(
            RegExp(
                r'(?:₹|\brs\.?|\binr)\s*\d[\d,]*(?:\.\d{1,2})?|\d[\d,]*(?:\.\d{1,2})?\s*(?:rupees|rs\b|inr\b|/-)?',
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(
                r'\b(add|added|spent|spend|paid|pay|bought|buy|expense|income|received|receive|earned|got|credited|debited|i|my|an?|the|of|rupees)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'[^\w\s&\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) return kind == EntryKind.income ? 'Income' : 'Expense';
    return _capitalize(title);
  }

  String _cleanTitle(String text) => text
      .replaceAll(RegExp(r'^(to|about|that|for)\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+(on|at|by|due)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[.!?]+$'), '')
      .trim();

  String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}
