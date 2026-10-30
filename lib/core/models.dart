import 'recurrence.dart';

enum EntryKind { expense, income }

const paymentMethods = ['Cash', 'UPI', 'Card', 'Bank transfer', 'Other'];

DateTime? _date(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.parse(value) : null;

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) decode) =>
    value is List
        ? value.whereType<Map<String, dynamic>>().map(decode).toList()
        : <T>[];

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.category,
    required this.title,
    required this.occurredAt,
    this.note = '',
    this.paymentMethod = 'Other',
    this.merchant = '',
    this.billId,
    this.accountId,
    this.receiptPath,
    this.source,
  });

  final String id;
  final EntryKind kind;
  final int amountPaise;
  final String category;
  final String title;
  final DateTime occurredAt;
  final String note;
  final String paymentMethod;
  final String merchant;

  /// Set when the entry was recorded as the payment of a bill.
  final String? billId;

  /// Wallet or account the money came from or went to, if chosen.
  final String? accountId;

  /// Path of a receipt photo stored in the app's private folder.
  final String? receiptPath;

  /// Where the entry came from when not typed in: `recurring`, `sms`,
  /// `upi`, `assistant`, `import`.
  final String? source;

  bool get isIncome => kind == EntryKind.income;

  LedgerEntry copyWith({
    EntryKind? kind,
    int? amountPaise,
    String? category,
    String? title,
    DateTime? occurredAt,
    String? note,
    String? paymentMethod,
    String? merchant,
    String? accountId,
    bool clearAccount = false,
    String? receiptPath,
    bool clearReceipt = false,
  }) =>
      LedgerEntry(
        id: id,
        kind: kind ?? this.kind,
        amountPaise: amountPaise ?? this.amountPaise,
        category: category ?? this.category,
        title: title ?? this.title,
        occurredAt: occurredAt ?? this.occurredAt,
        note: note ?? this.note,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        merchant: merchant ?? this.merchant,
        billId: billId,
        accountId: clearAccount ? null : accountId ?? this.accountId,
        receiptPath: clearReceipt ? null : receiptPath ?? this.receiptPath,
        source: source,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'amountPaise': amountPaise,
        'category': category,
        'title': title,
        'occurredAt': occurredAt.toIso8601String(),
        'note': note,
        'paymentMethod': paymentMethod,
        'merchant': merchant,
        if (billId != null) 'billId': billId,
        if (accountId != null) 'accountId': accountId,
        if (receiptPath != null) 'receiptPath': receiptPath,
        if (source != null) 'source': source,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    final amount = json['amountPaise'] as int;
    final category = json['category'] as String;
    final title = json['title'] as String;
    if (amount <= 0 || category.trim().isEmpty || title.trim().isEmpty) {
      throw const FormatException('Invalid transaction in backup.');
    }
    return LedgerEntry(
      id: json['id'] as String,
      kind: EntryKind.values.byName(json['kind'] as String),
      amountPaise: amount,
      category: category,
      title: title,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      note: json['note'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? 'Other',
      merchant: json['merchant'] as String? ?? '',
      billId: json['billId'] as String?,
      accountId: json['accountId'] as String?,
      receiptPath: json['receiptPath'] as String?,
      source: json['source'] as String?,
    );
  }
}

enum BudgetPeriod { monthly, weekly }

class SpendingBudget {
  const SpendingBudget({
    required this.category,
    required this.limitPaise,
    this.period = BudgetPeriod.monthly,
    this.rollover = false,
    this.alertPercent = 80,
  });

  final String category;
  final int limitPaise;
  final BudgetPeriod period;

  /// When true, unspent money from the previous period is added to this
  /// period's limit (one period only, never compounding).
  final bool rollover;

  /// Utilization percentage at which the budget is flagged as approaching.
  final int alertPercent;

  Map<String, Object?> toJson() => {
        'category': category,
        'limitPaise': limitPaise,
        'period': period.name,
        'rollover': rollover,
        'alertPercent': alertPercent,
      };

  factory SpendingBudget.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String;
    final limit = json['limitPaise'] as int;
    if (category.trim().isEmpty || limit <= 0) {
      throw const FormatException('Invalid budget in backup.');
    }
    return SpendingBudget(
      category: category,
      limitPaise: limit,
      period: _enum(BudgetPeriod.values, json['period'], BudgetPeriod.monthly),
      rollover: json['rollover'] as bool? ?? false,
      alertPercent: json['alertPercent'] as int? ?? 80,
    );
  }
}

enum GoalType { emergency, travel, device, education, personal, custom }

extension GoalTypeLabel on GoalType {
  String get label => switch (this) {
        GoalType.emergency => 'Emergency fund',
        GoalType.travel => 'Travel',
        GoalType.device => 'Device purchase',
        GoalType.education => 'Education',
        GoalType.personal => 'Personal',
        GoalType.custom => 'Custom',
      };
}

class GoalContribution {
  const GoalContribution({
    required this.id,
    required this.amountPaise,
    required this.at,
    this.note = '',
  });

  final String id;
  final int amountPaise;
  final DateTime at;
  final String note;

  Map<String, Object?> toJson() => {
        'id': id,
        'amountPaise': amountPaise,
        'at': at.toIso8601String(),
        'note': note,
      };

  factory GoalContribution.fromJson(Map<String, dynamic> json) {
    final amount = json['amountPaise'] as int;
    if (amount <= 0) {
      throw const FormatException('Invalid goal contribution in backup.');
    }
    return GoalContribution(
      id: json['id'] as String,
      amountPaise: amount,
      at: DateTime.parse(json['at'] as String),
      note: json['note'] as String? ?? '',
    );
  }
}

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetPaise,
    required this.createdAt,
    this.contributions = const [],
    this.targetDate,
    this.type = GoalType.custom,
  });

  final String id;
  final String name;
  final int targetPaise;
  final DateTime createdAt;
  final List<GoalContribution> contributions;
  final DateTime? targetDate;
  final GoalType type;

  int get savedPaise =>
      contributions.fold(0, (sum, item) => sum + item.amountPaise);

  int get remainingPaise =>
      savedPaise >= targetPaise ? 0 : targetPaise - savedPaise;

  double get progress =>
      targetPaise <= 0 ? 0 : (savedPaise / targetPaise).clamp(0.0, 1.0);

  SavingsGoal copyWith({
    String? name,
    int? targetPaise,
    List<GoalContribution>? contributions,
    DateTime? targetDate,
    bool clearTargetDate = false,
    GoalType? type,
  }) =>
      SavingsGoal(
        id: id,
        name: name ?? this.name,
        targetPaise: targetPaise ?? this.targetPaise,
        createdAt: createdAt,
        contributions: contributions ?? this.contributions,
        targetDate: clearTargetDate ? null : targetDate ?? this.targetDate,
        type: type ?? this.type,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'targetPaise': targetPaise,
        'savedPaise': savedPaise,
        'createdAt': createdAt.toIso8601String(),
        'targetDate': targetDate?.toIso8601String(),
        'type': type.name,
        'contributions': contributions.map((item) => item.toJson()).toList(),
      };

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final target = json['targetPaise'] as int;
    final createdAt = DateTime.parse(json['createdAt'] as String);
    if (name.trim().isEmpty || target <= 0) {
      throw const FormatException('Invalid savings goal in backup.');
    }
    var contributions = _list(json['contributions'], GoalContribution.fromJson);
    // Version 1 stored only a running total. Keep it as an opening balance.
    if (json['contributions'] == null) {
      final saved = json['savedPaise'] as int? ?? 0;
      if (saved < 0) {
        throw const FormatException('Invalid savings goal in backup.');
      }
      contributions = [
        if (saved > 0)
          GoalContribution(
            id: '${json['id']}-opening',
            amountPaise: saved,
            at: createdAt,
            note: 'Saved before contribution history',
          ),
      ];
    }
    return SavingsGoal(
      id: json['id'] as String,
      name: name,
      targetPaise: target,
      createdAt: createdAt,
      contributions: contributions,
      targetDate: _date(json['targetDate']),
      type: _enum(GoalType.values, json['type'], GoalType.custom),
    );
  }
}

enum TaskPriority { low, medium, high, urgent }

extension TaskPriorityLabel on TaskPriority {
  String get label => switch (this) {
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
        TaskPriority.urgent => 'Urgent',
      };
}

enum TaskStatus { backlog, todo, inProgress, blocked, done }

extension TaskStatusLabel on TaskStatus {
  String get label => switch (this) {
        TaskStatus.backlog => 'Backlog',
        TaskStatus.todo => 'To do',
        TaskStatus.inProgress => 'In progress',
        TaskStatus.blocked => 'Blocked',
        TaskStatus.done => 'Done',
      };
}

class Subtask {
  const Subtask({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  Subtask copyWith({String? title, bool? done}) =>
      Subtask(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
        id: json['id'] as String,
        title: json['title'] as String,
        done: json['done'] as bool? ?? false,
      );
}

class LocalTask {
  const LocalTask({
    required this.id,
    required this.title,
    required this.project,
    required this.createdAt,
    this.dueAt,
    this.dueHasTime = false,
    this.startAt,
    this.durationMinutes,
    this.description = '',
    this.notes = '',
    this.category = '',
    this.tags = const [],
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.todo,
    this.subtasks = const [],
    this.recurrence = Recurrence.none,
    this.reminderOffsets = const [],
    this.snoozedUntil,
    this.completedAt,
    this.completionHistory = const [],
  });

  final String id;
  final String title;
  final String project;
  final DateTime createdAt;

  /// Due date. When [dueHasTime] is false only the date part is meaningful.
  final DateTime? dueAt;
  final bool dueHasTime;
  final DateTime? startAt;
  final int? durationMinutes;
  final String description;
  final String notes;
  final String category;
  final List<String> tags;
  final TaskPriority priority;
  final TaskStatus status;
  final List<Subtask> subtasks;
  final Recurrence recurrence;

  /// Minutes before [dueAt] at which to remind. 0 means at the due time.
  final List<int> reminderOffsets;
  final DateTime? snoozedUntil;
  final DateTime? completedAt;

  /// Completion times of earlier occurrences of a recurring task.
  final List<DateTime> completionHistory;

  bool get isDone => status == TaskStatus.done;

  /// Scheduled block for calendar conflict detection, when it has a time.
  ({DateTime start, DateTime end})? get timeBlock {
    final start = startAt ?? (dueHasTime ? dueAt : null);
    if (start == null) return null;
    final minutes = durationMinutes ?? 0;
    if (startAt != null && dueAt != null && dueHasTime && minutes == 0) {
      return dueAt!.isAfter(start) ? (start: start, end: dueAt!) : null;
    }
    if (minutes <= 0) return null;
    return (start: start, end: start.add(Duration(minutes: minutes)));
  }

  LocalTask copyWith({
    String? title,
    String? project,
    DateTime? dueAt,
    bool clearDue = false,
    bool? dueHasTime,
    DateTime? startAt,
    bool clearStart = false,
    int? durationMinutes,
    bool clearDuration = false,
    String? description,
    String? notes,
    String? category,
    List<String>? tags,
    TaskPriority? priority,
    TaskStatus? status,
    List<Subtask>? subtasks,
    Recurrence? recurrence,
    List<int>? reminderOffsets,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
    DateTime? completedAt,
    bool clearCompleted = false,
    List<DateTime>? completionHistory,
    // Kept for compatibility with version 1 callers.
    bool? isDone,
  }) =>
      LocalTask(
        id: id,
        title: title ?? this.title,
        project: project ?? this.project,
        createdAt: createdAt,
        dueAt: clearDue ? null : dueAt ?? this.dueAt,
        dueHasTime: clearDue ? false : dueHasTime ?? this.dueHasTime,
        startAt: clearStart ? null : startAt ?? this.startAt,
        durationMinutes:
            clearDuration ? null : durationMinutes ?? this.durationMinutes,
        description: description ?? this.description,
        notes: notes ?? this.notes,
        category: category ?? this.category,
        tags: tags ?? this.tags,
        priority: priority ?? this.priority,
        status: isDone == null
            ? status ?? this.status
            : (isDone ? TaskStatus.done : TaskStatus.todo),
        subtasks: subtasks ?? this.subtasks,
        recurrence: recurrence ?? this.recurrence,
        reminderOffsets: reminderOffsets ?? this.reminderOffsets,
        snoozedUntil: clearSnooze ? null : snoozedUntil ?? this.snoozedUntil,
        completedAt: clearCompleted ? null : completedAt ?? this.completedAt,
        completionHistory: completionHistory ?? this.completionHistory,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'project': project,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
        'dueHasTime': dueHasTime,
        'startAt': startAt?.toIso8601String(),
        'durationMinutes': durationMinutes,
        'description': description,
        'notes': notes,
        'category': category,
        'tags': tags,
        'priority': priority.name,
        'status': status.name,
        'isDone': isDone,
        'subtasks': subtasks.map((item) => item.toJson()).toList(),
        'recurrence': recurrence.toJson(),
        'reminderOffsets': reminderOffsets,
        'snoozedUntil': snoozedUntil?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'completionHistory':
            completionHistory.map((item) => item.toIso8601String()).toList(),
      };

  factory LocalTask.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String;
    if (title.trim().isEmpty) {
      throw const FormatException('Invalid task in backup.');
    }
    final legacyDone = json['isDone'] as bool? ?? false;
    final status = json['status'] == null
        ? (legacyDone ? TaskStatus.done : TaskStatus.todo)
        : _enum(TaskStatus.values, json['status'], TaskStatus.todo);
    final history = json['completionHistory'];
    return LocalTask(
      id: json['id'] as String,
      title: title,
      project: json['project'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueAt: _date(json['dueAt']),
      dueHasTime: json['dueHasTime'] as bool? ?? false,
      startAt: _date(json['startAt']),
      durationMinutes: json['durationMinutes'] as int?,
      description: json['description'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      category: json['category'] as String? ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      priority:
          _enum(TaskPriority.values, json['priority'], TaskPriority.medium),
      status: status,
      subtasks: _list(json['subtasks'], Subtask.fromJson),
      recurrence: Recurrence.fromJson(json['recurrence']),
      reminderOffsets:
          (json['reminderOffsets'] as List?)?.whereType<int>().toList() ??
              const [],
      snoozedUntil: _date(json['snoozedUntil']),
      completedAt: _date(json['completedAt']),
      completionHistory: history is List
          ? history.whereType<String>().map(DateTime.parse).toList()
          : const [],
    );
  }
}

/// A payment handed to a UPI app. [status] is what the app reported back
/// ('opened' until it does); it is never proof that money was sent.
class PaymentHandoff {
  const PaymentHandoff({
    required this.id,
    required this.payee,
    required this.amountPaise,
    required this.createdAt,
    this.vpa = '',
    this.appName = '',
    this.reference = '',
    this.status = 'opened',
    this.bankReference = '',
    this.fromQr = false,
  });

  final String id;
  final String payee;
  final int amountPaise;
  final DateTime createdAt;
  final String vpa;
  final String appName;

  /// LifePilot's own reference sent as `tr`, when the payment allowed it.
  final String reference;

  /// opened, success, submitted, failure, cancelled or unknown.
  final String status;

  /// Transaction or approval reference the UPI app reported.
  final String bankReference;
  final bool fromQr;

  PaymentHandoff copyWith({String? status, String? bankReference}) =>
      PaymentHandoff(
        id: id,
        payee: payee,
        amountPaise: amountPaise,
        createdAt: createdAt,
        vpa: vpa,
        appName: appName,
        reference: reference,
        status: status ?? this.status,
        bankReference: bankReference ?? this.bankReference,
        fromQr: fromQr,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'payee': payee,
        'amountPaise': amountPaise,
        'createdAt': createdAt.toIso8601String(),
        if (vpa.isNotEmpty) 'vpa': vpa,
        if (appName.isNotEmpty) 'appName': appName,
        if (reference.isNotEmpty) 'reference': reference,
        'status': status,
        if (bankReference.isNotEmpty) 'bankReference': bankReference,
        if (fromQr) 'fromQr': true,
      };

  factory PaymentHandoff.fromJson(Map<String, dynamic> json) {
    final payee = json['payee'] as String;
    final amount = json['amountPaise'] as int;
    if (payee.trim().isEmpty || amount <= 0) {
      throw const FormatException('Invalid UPI handoff in backup.');
    }
    return PaymentHandoff(
      id: json['id'] as String,
      payee: payee,
      amountPaise: amount,
      createdAt: DateTime.parse(json['createdAt'] as String),
      vpa: json['vpa'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? 'opened',
      bankReference: json['bankReference'] as String? ?? '',
      fromQr: json['fromQr'] as bool? ?? false,
    );
  }
}

/// Someone the user has paid by UPI and chose to save. Saved payees are
/// compared against new UPI IDs to spot look-alikes.
class Payee {
  const Payee({
    required this.id,
    required this.name,
    required this.vpa,
    required this.createdAt,
    this.lastPaidAt,
    this.timesPaid = 0,
  });

  final String id;
  final String name;
  final String vpa;
  final DateTime createdAt;
  final DateTime? lastPaidAt;
  final int timesPaid;

  Payee copyWith({String? name, DateTime? lastPaidAt, int? timesPaid}) => Payee(
        id: id,
        name: name ?? this.name,
        vpa: vpa,
        createdAt: createdAt,
        lastPaidAt: lastPaidAt ?? this.lastPaidAt,
        timesPaid: timesPaid ?? this.timesPaid,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'vpa': vpa,
        'createdAt': createdAt.toIso8601String(),
        'lastPaidAt': lastPaidAt?.toIso8601String(),
        'timesPaid': timesPaid,
      };

  factory Payee.fromJson(Map<String, dynamic> json) {
    final vpa = (json['vpa'] as String).trim();
    if (!vpa.contains('@')) {
      throw const FormatException('Invalid saved payee in backup.');
    }
    return Payee(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      vpa: vpa,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastPaidAt: json['lastPaidAt'] is String
          ? DateTime.tryParse(json['lastPaidAt'] as String)
          : null,
      timesPaid: json['timesPaid'] as int? ?? 0,
    );
  }
}

enum BillKind {
  electricity,
  internet,
  mobile,
  rent,
  loan,
  insurance,
  subscription,
  other,
}

extension BillKindLabel on BillKind {
  String get label => switch (this) {
        BillKind.electricity => 'Electricity',
        BillKind.internet => 'Internet',
        BillKind.mobile => 'Mobile recharge',
        BillKind.rent => 'Rent',
        BillKind.loan => 'Loan payment',
        BillKind.insurance => 'Insurance premium',
        BillKind.subscription => 'Subscription',
        BillKind.other => 'Other',
      };
}

class BillPayment {
  const BillPayment({
    required this.id,
    required this.dueAt,
    required this.paidAt,
    required this.amountPaise,
    this.entryId,
  });

  final String id;

  /// The due date this payment settled.
  final DateTime dueAt;
  final DateTime paidAt;
  final int amountPaise;

  /// Linked expense entry, when the user chose to record one.
  final String? entryId;

  Map<String, Object?> toJson() => {
        'id': id,
        'dueAt': dueAt.toIso8601String(),
        'paidAt': paidAt.toIso8601String(),
        'amountPaise': amountPaise,
        'entryId': entryId,
      };

  factory BillPayment.fromJson(Map<String, dynamic> json) => BillPayment(
        id: json['id'] as String,
        dueAt: DateTime.parse(json['dueAt'] as String),
        paidAt: DateTime.parse(json['paidAt'] as String),
        amountPaise: json['amountPaise'] as int,
        entryId: json['entryId'] as String?,
      );
}

/// A scheduled obligation. It is only paid when the user confirms a payment;
/// passing the due date never marks it paid.
class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.kind,
    required this.amountPaise,
    required this.nextDueAt,
    this.recurrence = const Recurrence(Repeat.monthly),
    this.remindDaysBefore = 2,
    this.category = 'Bills',
    this.notes = '',
    this.payments = const [],
    this.active = true,
  });

  final String id;
  final String name;
  final BillKind kind;
  final int amountPaise;
  final DateTime nextDueAt;
  final Recurrence recurrence;
  final int remindDaysBefore;
  final String category;
  final String notes;
  final List<BillPayment> payments;

  /// False once a one-time bill is paid or the user stops tracking it.
  final bool active;

  Bill copyWith({
    String? name,
    BillKind? kind,
    int? amountPaise,
    DateTime? nextDueAt,
    Recurrence? recurrence,
    int? remindDaysBefore,
    String? category,
    String? notes,
    List<BillPayment>? payments,
    bool? active,
  }) =>
      Bill(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        amountPaise: amountPaise ?? this.amountPaise,
        nextDueAt: nextDueAt ?? this.nextDueAt,
        recurrence: recurrence ?? this.recurrence,
        remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
        category: category ?? this.category,
        notes: notes ?? this.notes,
        payments: payments ?? this.payments,
        active: active ?? this.active,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'amountPaise': amountPaise,
        'nextDueAt': nextDueAt.toIso8601String(),
        'recurrence': recurrence.toJson(),
        'remindDaysBefore': remindDaysBefore,
        'category': category,
        'notes': notes,
        'payments': payments.map((item) => item.toJson()).toList(),
        'active': active,
      };

  factory Bill.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final amount = json['amountPaise'] as int;
    if (name.trim().isEmpty || amount <= 0) {
      throw const FormatException('Invalid bill in backup.');
    }
    return Bill(
      id: json['id'] as String,
      name: name,
      kind: _enum(BillKind.values, json['kind'], BillKind.other),
      amountPaise: amount,
      nextDueAt: DateTime.parse(json['nextDueAt'] as String),
      recurrence: Recurrence.fromJson(json['recurrence']),
      remindDaysBefore: json['remindDaysBefore'] as int? ?? 2,
      category: json['category'] as String? ?? 'Bills',
      notes: json['notes'] as String? ?? '',
      payments: _list(json['payments'], BillPayment.fromJson),
      active: json['active'] as bool? ?? true,
    );
  }
}

enum FocusKind { focus, shortBreak, longBreak }

extension FocusKindLabel on FocusKind {
  String get label => switch (this) {
        FocusKind.focus => 'Focus',
        FocusKind.shortBreak => 'Short break',
        FocusKind.longBreak => 'Long break',
      };
}

class FocusSession {
  const FocusSession({
    required this.id,
    required this.label,
    required this.kind,
    required this.startedAt,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.completed,
  });

  final String id;
  final String label;
  final FocusKind kind;
  final DateTime startedAt;
  final int plannedSeconds;
  final int actualSeconds;
  final bool completed;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'startedAt': startedAt.toIso8601String(),
        'plannedSeconds': plannedSeconds,
        'actualSeconds': actualSeconds,
        'completed': completed,
      };

  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Focus',
        kind: _enum(FocusKind.values, json['kind'], FocusKind.focus),
        startedAt: DateTime.parse(json['startedAt'] as String),
        plannedSeconds: json['plannedSeconds'] as int? ?? 0,
        actualSeconds: json['actualSeconds'] as int? ?? 0,
        completed: json['completed'] as bool? ?? false,
      );
}

class Alarm {
  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = '',
    this.enabled = true,
    this.weekdays = const [],
  });

  final String id;
  final int hour;
  final int minute;
  final String label;
  final bool enabled;

  /// ISO weekdays (1 = Monday). Empty means every day.
  final List<int> weekdays;

  Alarm copyWith({
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
    List<int>? weekdays,
  }) =>
      Alarm(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        weekdays: weekdays ?? this.weekdays,
      );

  /// Next time this alarm fires after [now].
  DateTime nextFire(DateTime now) {
    for (var day = 0; day <= 7; day++) {
      final candidate =
          DateTime(now.year, now.month, now.day + day, hour, minute);
      if (!candidate.isAfter(now)) continue;
      if (weekdays.isEmpty || weekdays.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'weekdays': weekdays,
      };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
        id: json['id'] as String,
        hour: json['hour'] as int,
        minute: json['minute'] as int,
        label: json['label'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        weekdays:
            (json['weekdays'] as List?)?.whereType<int>().toList() ?? const [],
      );
}

class QuickNote {
  const QuickNote({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;

  QuickNote copyWith({String? text, bool? pinned, DateTime? updatedAt}) =>
      QuickNote(
        id: id,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pinned': pinned,
      };

  factory QuickNote.fromJson(Map<String, dynamic> json) => QuickNote(
        id: json['id'] as String,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        pinned: json['pinned'] as bool? ?? false,
      );
}

class ReminderLogEntry {
  const ReminderLogEntry({
    required this.at,
    required this.title,
    required this.action,
    this.taskId,
  });

  final DateTime at;
  final String title;

  /// For example: snoozed 10 min, completed, rescheduled, cancelled.
  final String action;
  final String? taskId;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'title': title,
        'action': action,
        'taskId': taskId,
      };

  factory ReminderLogEntry.fromJson(Map<String, dynamic> json) =>
      ReminderLogEntry(
        at: DateTime.parse(json['at'] as String),
        title: json['title'] as String? ?? '',
        action: json['action'] as String? ?? '',
        taskId: json['taskId'] as String?,
      );
}

const dashboardSectionIds = [
  'today',
  'finance',
  'planner',
  'habits',
  'bills',
  'insights',
  'goals',
  'review',
  'recent',
];

String dashboardSectionLabel(String id) => switch (id) {
      'today' => "Today's overview",
      'finance' => 'Finance overview',
      'planner' => 'Daily planner',
      'habits' => 'Habits',
      'bills' => 'Upcoming bills',
      'insights' => 'Insights',
      'goals' => 'Savings goals',
      'review' => 'Weekly review',
      'recent' => 'Recent transactions',
      _ => id,
    };

enum AppThemeMode { system, light, dark }

enum LockScope { app, finance }

/// Accent colours offered in settings (ARGB).
const accentChoices = <int>[
  0xFF167D72, // teal (default)
  0xFF3F51B5, // indigo
  0xFF7B4FA0, // purple
  0xFFC2185B, // rose
  0xFFE0752D, // orange
  0xFF2E7D32, // green
  0xFF00838F, // cyan
  0xFF5D6B7A, // slate
];

class AppSettings {
  const AppSettings({
    this.use24HourClock = false,
    this.showSeconds = true,
    this.analogClock = false,
    this.currencySymbol = '₹',
    this.worldClocks = const ['Europe/London', 'America/New_York'],
    this.dashboardOrder = dashboardSectionIds,
    this.hiddenSections = const [],
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.defaultReminderMinutes = 15,
    this.themeMode = AppThemeMode.system,
    this.accentColor = 0xFF167D72,
    this.lockEnabled = false,
    this.lockScope = LockScope.app,
    this.lockUseBiometrics = true,
    this.pinHash,
    this.pinSalt,
    this.onboarded = true,
    this.salaryDay,
    this.pinFailures = 0,
    this.pinLockedUntil,
    this.confirmSensitive = true,
    this.allowScreenshots = false,
    this.largePaymentPaise = 1000000,
    this.smsCapture = false,
    this.keepSmsText = false,
    this.extraSmsSenders = const [],
  });

  final bool use24HourClock;
  final bool showSeconds;
  final bool analogClock;
  final String currencySymbol;
  final List<String> worldClocks;
  final List<String> dashboardOrder;
  final List<String> hiddenSections;
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int defaultReminderMinutes;
  final AppThemeMode themeMode;
  final int accentColor;
  final bool lockEnabled;
  final LockScope lockScope;
  final bool lockUseBiometrics;

  /// PBKDF2 hash and salt of the app-lock PIN, base64. Never the PIN itself.
  final String? pinHash;
  final String? pinSalt;
  final bool onboarded;

  /// Day of month salary usually arrives, from onboarding.
  final int? salaryDay;

  /// Wrong PINs entered in a row, kept across restarts so closing the app
  /// does not reset the lockout.
  final int pinFailures;
  final DateTime? pinLockedUntil;

  /// Ask for the PIN again before payments, exports, restores and turning
  /// the lock off.
  final bool confirmSensitive;

  /// With the lock on, screenshots and the recent-apps preview are blocked
  /// unless this is set.
  final bool allowScreenshots;

  /// UPI payments at or above this ask for an extra confirmation.
  final int largePaymentPaise;

  /// Read bank SMS as they arrive (Android, needs SMS permission).
  final bool smsCapture;

  /// Keep the full text of bank messages on drafts instead of a copy with
  /// balances and links removed.
  final bool keepSmsText;

  /// Sender IDs the user marked as their bank's, e.g. a cooperative bank.
  final List<String> extraSmsSenders;

  /// Whether the window should be hidden from screenshots and recent apps.
  bool get secureScreen => lockEnabled && !allowScreenshots;

  /// Visible dashboard sections in display order, including any sections
  /// added in later versions that an older saved order does not mention.
  List<String> get visibleSections => [
        ...dashboardOrder.where(dashboardSectionIds.contains),
        ...dashboardSectionIds.where((id) => !dashboardOrder.contains(id)),
      ].where((id) => !hiddenSections.contains(id)).toList();

  AppSettings copyWith({
    bool? use24HourClock,
    bool? showSeconds,
    bool? analogClock,
    String? currencySymbol,
    List<String>? worldClocks,
    List<String>? dashboardOrder,
    List<String>? hiddenSections,
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? defaultReminderMinutes,
    AppThemeMode? themeMode,
    int? accentColor,
    bool? lockEnabled,
    LockScope? lockScope,
    bool? lockUseBiometrics,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    bool? onboarded,
    int? salaryDay,
    int? pinFailures,
    DateTime? pinLockedUntil,
    bool clearPinLockout = false,
    bool? confirmSensitive,
    bool? allowScreenshots,
    int? largePaymentPaise,
    bool? smsCapture,
    bool? keepSmsText,
    List<String>? extraSmsSenders,
  }) =>
      AppSettings(
        use24HourClock: use24HourClock ?? this.use24HourClock,
        showSeconds: showSeconds ?? this.showSeconds,
        analogClock: analogClock ?? this.analogClock,
        currencySymbol: currencySymbol ?? this.currencySymbol,
        worldClocks: worldClocks ?? this.worldClocks,
        dashboardOrder: dashboardOrder ?? this.dashboardOrder,
        hiddenSections: hiddenSections ?? this.hiddenSections,
        focusMinutes: focusMinutes ?? this.focusMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        defaultReminderMinutes:
            defaultReminderMinutes ?? this.defaultReminderMinutes,
        themeMode: themeMode ?? this.themeMode,
        accentColor: accentColor ?? this.accentColor,
        lockEnabled: lockEnabled ?? this.lockEnabled,
        lockScope: lockScope ?? this.lockScope,
        lockUseBiometrics: lockUseBiometrics ?? this.lockUseBiometrics,
        pinHash: clearPin ? null : pinHash ?? this.pinHash,
        pinSalt: clearPin ? null : pinSalt ?? this.pinSalt,
        onboarded: onboarded ?? this.onboarded,
        salaryDay: salaryDay ?? this.salaryDay,
        pinFailures: clearPinLockout ? 0 : pinFailures ?? this.pinFailures,
        pinLockedUntil:
            clearPinLockout ? null : pinLockedUntil ?? this.pinLockedUntil,
        confirmSensitive: confirmSensitive ?? this.confirmSensitive,
        allowScreenshots: allowScreenshots ?? this.allowScreenshots,
        largePaymentPaise: largePaymentPaise ?? this.largePaymentPaise,
        smsCapture: smsCapture ?? this.smsCapture,
        keepSmsText: keepSmsText ?? this.keepSmsText,
        extraSmsSenders: extraSmsSenders ?? this.extraSmsSenders,
      );

  Map<String, Object?> toJson() => {
        'use24HourClock': use24HourClock,
        'showSeconds': showSeconds,
        'analogClock': analogClock,
        'currencySymbol': currencySymbol,
        'worldClocks': worldClocks,
        'dashboardOrder': dashboardOrder,
        'hiddenSections': hiddenSections,
        'focusMinutes': focusMinutes,
        'shortBreakMinutes': shortBreakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'defaultReminderMinutes': defaultReminderMinutes,
        'themeMode': themeMode.name,
        'accentColor': accentColor,
        'lockEnabled': lockEnabled,
        'lockScope': lockScope.name,
        'lockUseBiometrics': lockUseBiometrics,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'onboarded': onboarded,
        'salaryDay': salaryDay,
        'pinFailures': pinFailures,
        'pinLockedUntil': pinLockedUntil?.toIso8601String(),
        'confirmSensitive': confirmSensitive,
        'allowScreenshots': allowScreenshots,
        'largePaymentPaise': largePaymentPaise,
        'smsCapture': smsCapture,
        'keepSmsText': keepSmsText,
        'extraSmsSenders': extraSmsSenders,
      };

  factory AppSettings.fromJson(Object? source) {
    if (source is! Map) return const AppSettings();
    List<String> strings(Object? value, List<String> fallback) =>
        value is List ? value.whereType<String>().toList() : fallback;
    int minutes(Object? value, int fallback) =>
        value is int && value > 0 && value <= 24 * 60 ? value : fallback;
    const defaults = AppSettings();
    final pinHash = source['pinHash'] as String?;
    final pinSalt = source['pinSalt'] as String?;
    return AppSettings(
      use24HourClock: source['use24HourClock'] as bool? ?? false,
      showSeconds: source['showSeconds'] as bool? ?? true,
      analogClock: source['analogClock'] as bool? ?? false,
      currencySymbol: source['currencySymbol'] as String? ?? '₹',
      worldClocks: strings(source['worldClocks'], defaults.worldClocks),
      dashboardOrder:
          strings(source['dashboardOrder'], defaults.dashboardOrder),
      hiddenSections: strings(source['hiddenSections'], const []),
      focusMinutes: minutes(source['focusMinutes'], 25),
      shortBreakMinutes: minutes(source['shortBreakMinutes'], 5),
      longBreakMinutes: minutes(source['longBreakMinutes'], 15),
      defaultReminderMinutes: source['defaultReminderMinutes'] is int
          ? source['defaultReminderMinutes'] as int
          : 15,
      themeMode:
          _enum(AppThemeMode.values, source['themeMode'], AppThemeMode.system),
      accentColor: source['accentColor'] as int? ?? defaults.accentColor,
      // A lock without a stored PIN could never be opened; treat it as off.
      lockEnabled: (source['lockEnabled'] as bool? ?? false) &&
          pinHash != null &&
          pinSalt != null,
      lockScope: _enum(LockScope.values, source['lockScope'], LockScope.app),
      lockUseBiometrics: source['lockUseBiometrics'] as bool? ?? true,
      pinHash: pinHash,
      pinSalt: pinSalt,
      // Settings saved before onboarding existed belong to existing users.
      onboarded: source['onboarded'] as bool? ?? true,
      salaryDay: source['salaryDay'] as int?,
      pinFailures: source['pinFailures'] as int? ?? 0,
      pinLockedUntil: source['pinLockedUntil'] is String
          ? DateTime.tryParse(source['pinLockedUntil'] as String)
          : null,
      confirmSensitive: source['confirmSensitive'] as bool? ?? true,
      allowScreenshots: source['allowScreenshots'] as bool? ?? false,
      largePaymentPaise: source['largePaymentPaise'] is int &&
              (source['largePaymentPaise'] as int) > 0
          ? source['largePaymentPaise'] as int
          : defaults.largePaymentPaise,
      smsCapture: source['smsCapture'] as bool? ?? false,
      keepSmsText: source['keepSmsText'] as bool? ?? false,
      extraSmsSenders: strings(source['extraSmsSenders'], const []),
    );
  }
}

/// A wallet or account the user tracks, such as Cash or a bank account.
/// Its balance is computed from the opening balance and recorded entries;
/// it is never read from a bank.
enum AccountKind { cash, bank, upi, card, wallet, other }

extension AccountKindLabel on AccountKind {
  String get label => switch (this) {
        AccountKind.cash => 'Cash',
        AccountKind.bank => 'Bank account',
        AccountKind.upi => 'UPI',
        AccountKind.card => 'Card',
        AccountKind.wallet => 'Wallet',
        AccountKind.other => 'Other',
      };
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    this.openingBalancePaise = 0,
    this.archived = false,
  });

  final String id;
  final String name;
  final AccountKind kind;

  /// May be negative, for example a credit card that starts with dues.
  final int openingBalancePaise;
  final bool archived;

  Account copyWith({
    String? name,
    AccountKind? kind,
    int? openingBalancePaise,
    bool? archived,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        openingBalancePaise: openingBalancePaise ?? this.openingBalancePaise,
        archived: archived ?? this.archived,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'openingBalancePaise': openingBalancePaise,
        'archived': archived,
      };

  factory Account.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    if (name.trim().isEmpty) {
      throw const FormatException('Invalid account in backup.');
    }
    return Account(
      id: json['id'] as String,
      name: name,
      kind: _enum(AccountKind.values, json['kind'], AccountKind.other),
      openingBalancePaise: json['openingBalancePaise'] as int? ?? 0,
      archived: json['archived'] as bool? ?? false,
    );
  }
}

/// Money moved between two of the user's own accounts. Not income or expense.
class AccountTransfer {
  const AccountTransfer({
    required this.id,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountPaise,
    required this.at,
    this.note = '',
  });

  final String id;
  final String fromAccountId;
  final String toAccountId;
  final int amountPaise;
  final DateTime at;
  final String note;

  Map<String, Object?> toJson() => {
        'id': id,
        'from': fromAccountId,
        'to': toAccountId,
        'amountPaise': amountPaise,
        'at': at.toIso8601String(),
        'note': note,
      };

  factory AccountTransfer.fromJson(Map<String, dynamic> json) {
    final amount = json['amountPaise'] as int;
    if (amount <= 0 || json['from'] == json['to']) {
      throw const FormatException('Invalid transfer in backup.');
    }
    return AccountTransfer(
      id: json['id'] as String,
      fromAccountId: json['from'] as String,
      toAccountId: json['to'] as String,
      amountPaise: amount,
      at: DateTime.parse(json['at'] as String),
      note: json['note'] as String? ?? '',
    );
  }
}

/// A rule that prepares an income or expense entry on a schedule. Each due
/// occurrence becomes a [PendingEntry] that the user approves; nothing is
/// recorded automatically.
class RecurringEntry {
  const RecurringEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.category,
    required this.title,
    required this.recurrence,
    required this.nextDate,
    this.accountId,
    this.paymentMethod = 'Other',
    this.active = true,
  });

  final String id;
  final EntryKind kind;
  final int amountPaise;
  final String category;
  final String title;
  final Recurrence recurrence;

  /// Date of the next occurrence that has not yet been prepared.
  final DateTime nextDate;
  final String? accountId;
  final String paymentMethod;
  final bool active;

  RecurringEntry copyWith({
    EntryKind? kind,
    int? amountPaise,
    String? category,
    String? title,
    Recurrence? recurrence,
    DateTime? nextDate,
    String? accountId,
    String? paymentMethod,
    bool? active,
  }) =>
      RecurringEntry(
        id: id,
        kind: kind ?? this.kind,
        amountPaise: amountPaise ?? this.amountPaise,
        category: category ?? this.category,
        title: title ?? this.title,
        recurrence: recurrence ?? this.recurrence,
        nextDate: nextDate ?? this.nextDate,
        accountId: accountId ?? this.accountId,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        active: active ?? this.active,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'amountPaise': amountPaise,
        'category': category,
        'title': title,
        'recurrence': recurrence.toJson(),
        'nextDate': nextDate.toIso8601String(),
        'accountId': accountId,
        'paymentMethod': paymentMethod,
        'active': active,
      };

  factory RecurringEntry.fromJson(Map<String, dynamic> json) {
    final amount = json['amountPaise'] as int;
    final title = json['title'] as String;
    if (amount <= 0 || title.trim().isEmpty) {
      throw const FormatException('Invalid recurring entry in backup.');
    }
    return RecurringEntry(
      id: json['id'] as String,
      kind: EntryKind.values.byName(json['kind'] as String),
      amountPaise: amount,
      category: json['category'] as String? ?? 'Other',
      title: title,
      recurrence: Recurrence.fromJson(json['recurrence']),
      nextDate: DateTime.parse(json['nextDate'] as String),
      accountId: json['accountId'] as String?,
      paymentMethod: json['paymentMethod'] as String? ?? 'Other',
      active: json['active'] as bool? ?? true,
    );
  }
}

/// A draft transaction waiting for the user to approve, edit or discard.
class PendingEntry {
  const PendingEntry({
    required this.id,
    required this.entry,
    required this.source,
    required this.createdAt,
    this.sourceKey,
    this.sourceText = '',
    this.recurringId,
    this.bankConfirmed = false,
    this.warning = '',
  });

  final String id;

  /// Proposed values; its id is empty until approved.
  final LedgerEntry entry;

  /// `recurring` or `sms`.
  final String source;
  final DateTime createdAt;

  /// Identity of the source item (an SMS fingerprint or recurring date),
  /// used to avoid preparing the same draft twice.
  final String? sourceKey;

  /// Original SMS text, shown so the user can check the parse.
  final String sourceText;
  final String? recurringId;

  /// A UPI app's report that a matching bank SMS has since confirmed.
  final bool bankConfirmed;

  /// Something the user should check before approving, e.g. an unknown
  /// sender or a large debit LifePilot did not start.
  final String warning;

  PendingEntry copyWith({
    String? sourceText,
    bool? bankConfirmed,
    String? warning,
  }) =>
      PendingEntry(
        id: id,
        entry: entry,
        source: source,
        createdAt: createdAt,
        sourceKey: sourceKey,
        sourceText: sourceText ?? this.sourceText,
        recurringId: recurringId,
        bankConfirmed: bankConfirmed ?? this.bankConfirmed,
        warning: warning ?? this.warning,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'entry': entry.toJson(),
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'sourceKey': sourceKey,
        'sourceText': sourceText,
        'recurringId': recurringId,
        if (bankConfirmed) 'bankConfirmed': true,
        if (warning.isNotEmpty) 'warning': warning,
      };

  factory PendingEntry.fromJson(Map<String, dynamic> json) => PendingEntry(
        id: json['id'] as String,
        entry: LedgerEntry.fromJson(
            (json['entry'] as Map).cast<String, dynamic>()),
        source: json['source'] as String? ?? 'recurring',
        createdAt: DateTime.parse(json['createdAt'] as String),
        sourceKey: json['sourceKey'] as String?,
        sourceText: json['sourceText'] as String? ?? '',
        recurringId: json['recurringId'] as String?,
        bankConfirmed: json['bankConfirmed'] as bool? ?? false,
        warning: json['warning'] as String? ?? '',
      );
}

/// A message that looked like a scam. Kept so the user can see what was
/// held back and report it; only a redacted snippet is stored.
class SuspiciousSms {
  const SuspiciousSms({
    required this.key,
    required this.sender,
    required this.reason,
    required this.snippet,
    required this.receivedAt,
  });

  final String key;
  final String sender;
  final String reason;
  final String snippet;
  final DateTime receivedAt;

  Map<String, Object?> toJson() => {
        'key': key,
        'sender': sender,
        'reason': reason,
        'snippet': snippet,
        'receivedAt': receivedAt.toIso8601String(),
      };

  factory SuspiciousSms.fromJson(Map<String, dynamic> json) => SuspiciousSms(
        key: json['key'] as String,
        sender: json['sender'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
        receivedAt: DateTime.parse(json['receivedAt'] as String),
      );
}

/// "Payee or message contains [contains] → [category]". Rules win over the
/// category LifePilot learns from past entries.
class CategoryRule {
  const CategoryRule({
    required this.id,
    required this.contains,
    required this.category,
  });

  final String id;
  final String contains;
  final String category;

  bool matches(String text) =>
      contains.trim().isNotEmpty &&
      text.toLowerCase().contains(contains.trim().toLowerCase());

  Map<String, Object?> toJson() =>
      {'id': id, 'contains': contains, 'category': category};

  factory CategoryRule.fromJson(Map<String, dynamic> json) {
    final contains = (json['contains'] as String? ?? '').trim();
    final category = (json['category'] as String? ?? '').trim();
    if (contains.isEmpty || category.isEmpty) {
      throw const FormatException('Invalid category rule in backup.');
    }
    return CategoryRule(
        id: json['id'] as String, contains: contains, category: category);
  }
}

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.createdAt,
    this.weekdays = const [],
    this.checkIns = const [],
    this.reminderMinutes,
    this.archived = false,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// ISO weekdays the habit applies to. Empty means every day.
  final List<int> weekdays;

  /// Days completed, stored as local dates at midnight.
  final List<DateTime> checkIns;

  /// Minutes after midnight for a daily reminder, if any.
  final int? reminderMinutes;
  final bool archived;

  bool appliesOn(DateTime day) =>
      weekdays.isEmpty || weekdays.contains(day.weekday);

  bool doneOn(DateTime day) => checkIns.any((item) =>
      item.year == day.year && item.month == day.month && item.day == day.day);

  Habit copyWith({
    String? name,
    List<int>? weekdays,
    List<DateTime>? checkIns,
    int? reminderMinutes,
    bool clearReminder = false,
    bool? archived,
  }) =>
      Habit(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        weekdays: weekdays ?? this.weekdays,
        checkIns: checkIns ?? this.checkIns,
        reminderMinutes:
            clearReminder ? null : reminderMinutes ?? this.reminderMinutes,
        archived: archived ?? this.archived,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'weekdays': weekdays,
        'checkIns': checkIns.map((day) => day.toIso8601String()).toList(),
        'reminderMinutes': reminderMinutes,
        'archived': archived,
      };

  factory Habit.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    if (name.trim().isEmpty) {
      throw const FormatException('Invalid habit in backup.');
    }
    final checkIns = json['checkIns'];
    return Habit(
      id: json['id'] as String,
      name: name,
      createdAt: DateTime.parse(json['createdAt'] as String),
      weekdays:
          (json['weekdays'] as List?)?.whereType<int>().toList() ?? const [],
      checkIns: checkIns is List
          ? checkIns.whereType<String>().map(DateTime.parse).toList()
          : const [],
      reminderMinutes: json['reminderMinutes'] as int?,
      archived: json['archived'] as bool? ?? false,
    );
  }
}

/// Stopwatch state stored as timestamps, so elapsed time stays correct after
/// the app is backgrounded or restarted.
class StopwatchState {
  const StopwatchState({
    this.runningSince,
    this.accumulatedMs = 0,
    this.lapsMs = const [],
  });

  final DateTime? runningSince;
  final int accumulatedMs;

  /// Cumulative elapsed time at each lap, in milliseconds.
  final List<int> lapsMs;

  bool get isRunning => runningSince != null;

  int elapsedMs(DateTime now) =>
      accumulatedMs +
      (runningSince == null
          ? 0
          : now.difference(runningSince!).inMilliseconds.clamp(0, 1 << 52));

  Map<String, Object?> toJson() => {
        'runningSince': runningSince?.toIso8601String(),
        'accumulatedMs': accumulatedMs,
        'lapsMs': lapsMs,
      };

  factory StopwatchState.fromJson(Object? json) => json is Map
      ? StopwatchState(
          runningSince: _date(json['runningSince']),
          accumulatedMs: json['accumulatedMs'] as int? ?? 0,
          lapsMs:
              (json['lapsMs'] as List?)?.whereType<int>().toList() ?? const [],
        )
      : const StopwatchState();
}

/// A countdown that is either running (has [endsAt]) or paused/idle
/// (has [remainingMs]). Used for both the plain timer and focus sessions.
class CountdownState {
  const CountdownState({
    this.label = '',
    this.totalMs = 0,
    this.remainingMs = 0,
    this.endsAt,
    this.startedAt,
    this.kind = FocusKind.focus,
    this.completedFocusCount = 0,
  });

  final String label;
  final int totalMs;
  final int remainingMs;
  final DateTime? endsAt;
  final DateTime? startedAt;

  /// Focus-timer phase. Ignored by the plain countdown timer.
  final FocusKind kind;
  final int completedFocusCount;

  bool get isRunning => endsAt != null;
  bool get isActive => isRunning || remainingMs > 0;

  int remaining(DateTime now) => endsAt == null
      ? remainingMs
      : endsAt!.difference(now).inMilliseconds.clamp(0, totalMs);

  CountdownState copyWith({
    String? label,
    int? totalMs,
    int? remainingMs,
    DateTime? endsAt,
    bool clearEndsAt = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    FocusKind? kind,
    int? completedFocusCount,
  }) =>
      CountdownState(
        label: label ?? this.label,
        totalMs: totalMs ?? this.totalMs,
        remainingMs: remainingMs ?? this.remainingMs,
        endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
        startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
        kind: kind ?? this.kind,
        completedFocusCount: completedFocusCount ?? this.completedFocusCount,
      );

  Map<String, Object?> toJson() => {
        'label': label,
        'totalMs': totalMs,
        'remainingMs': remainingMs,
        'endsAt': endsAt?.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'kind': kind.name,
        'completedFocusCount': completedFocusCount,
      };

  factory CountdownState.fromJson(Object? json) => json is Map
      ? CountdownState(
          label: json['label'] as String? ?? '',
          totalMs: json['totalMs'] as int? ?? 0,
          remainingMs: json['remainingMs'] as int? ?? 0,
          endsAt: _date(json['endsAt']),
          startedAt: _date(json['startedAt']),
          kind: _enum(FocusKind.values, json['kind'], FocusKind.focus),
          completedFocusCount: json['completedFocusCount'] as int? ?? 0,
        )
      : const CountdownState();
}

class ClockState {
  const ClockState({
    this.stopwatch = const StopwatchState(),
    this.timer = const CountdownState(),
    this.focus = const CountdownState(),
  });

  final StopwatchState stopwatch;
  final CountdownState timer;
  final CountdownState focus;

  ClockState copyWith({
    StopwatchState? stopwatch,
    CountdownState? timer,
    CountdownState? focus,
  }) =>
      ClockState(
        stopwatch: stopwatch ?? this.stopwatch,
        timer: timer ?? this.timer,
        focus: focus ?? this.focus,
      );

  Map<String, Object?> toJson() => {
        'stopwatch': stopwatch.toJson(),
        'timer': timer.toJson(),
        'focus': focus.toJson(),
      };

  factory ClockState.fromJson(Object? json) => json is Map
      ? ClockState(
          stopwatch: StopwatchState.fromJson(json['stopwatch']),
          timer: CountdownState.fromJson(json['timer']),
          focus: CountdownState.fromJson(json['focus']),
        )
      : const ClockState();
}
