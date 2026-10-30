import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/personal.dart';
import '../core/recurrence.dart';
import '../services/receipts.dart';
import '../services/reminder_coordinator.dart';
import 'widgets.dart';
import 'platform.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => child,
    );

Future<void> showEntryForm(
  BuildContext context,
  LifePilotStore store, {
  EntryKind kind = EntryKind.expense,
  LedgerEntry? entry,
  LedgerEntry? template,
  String? pendingId,
}) =>
    _sheet(
        context,
        _EntryForm(
            store: store,
            kind: entry?.kind ?? template?.kind ?? kind,
            entry: entry,
            template: template,
            pendingId: pendingId));

Future<void> showTaskForm(
  BuildContext context,
  LifePilotStore store, {
  LocalTask? task,
  DateTime? initialDue,
  bool reminder = false,
}) =>
    _sheet(
        context,
        _TaskForm(
            store: store,
            task: task,
            initialDue: initialDue,
            reminder: reminder));

Future<void> showBudgetForm(
  BuildContext context,
  LifePilotStore store, {
  SpendingBudget? budget,
}) =>
    _sheet(context, _BudgetForm(store: store, budget: budget));

Future<void> showGoalForm(
  BuildContext context,
  LifePilotStore store, {
  SavingsGoal? goal,
}) =>
    _sheet(context, _GoalForm(store: store, goal: goal));

Future<void> showContributionForm(
  BuildContext context,
  LifePilotStore store,
  SavingsGoal goal,
) =>
    _sheet(context, _ContributionForm(store: store, goal: goal));

Future<void> showBillForm(BuildContext context, LifePilotStore store,
        {Bill? bill}) =>
    _sheet(context, _BillForm(store: store, bill: bill));

Future<void> showMarkPaidForm(
        BuildContext context, LifePilotStore store, Bill bill) =>
    _sheet(context, _MarkPaidForm(store: store, bill: bill));

Future<void> showNoteForm(BuildContext context, LifePilotStore store,
        {QuickNote? note}) =>
    _sheet(context, _NoteForm(store: store, note: note));

Future<void> showAlarmForm(BuildContext context, LifePilotStore store,
        {Alarm? alarm}) =>
    _sheet(context, _AlarmForm(store: store, alarm: alarm));

/// Shared frame for form sheets: title, scrollable fields, and keyboard-safe
/// padding.
class _FormSheet extends StatelessWidget {
  const _FormSheet({
    required this.formKey,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: formKey,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      );
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.saving,
    required this.onPressed,
    this.icon = Icons.check,
  });

  final String label;
  final bool saving;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: FilledButton.icon(
          onPressed: saving ? null : onPressed,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon),
          label: Text(saving ? 'Saving…' : label),
        ),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );
}

const _gap = SizedBox(height: 12);

String? _amountValidator(String? value) =>
    parseRupeesToPaise(value ?? '') == null
        ? 'Enter an amount greater than zero, with up to 2 decimals.'
        : null;

String? _requiredText(String? value, String message) =>
    value == null || value.trim().isEmpty ? message : null;

TextFormField _amountField(TextEditingController controller, String label,
        {bool autofocus = false}) =>
    TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
          labelText: label, prefixText: '${MoneyFormat.symbol} '),
      validator: _amountValidator,
    );

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
        trailing: onClear == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
        onTap: onTap,
      );
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial,
        {DateTime? first, DateTime? last}) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(2000),
      lastDate: last ?? DateTime(2100),
    );

Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) =>
    showTimePicker(context: context, initialTime: initial);

// ---------------------------------------------------------------------------
// Income and expenses

class _EntryForm extends StatefulWidget {
  const _EntryForm({
    required this.store,
    required this.kind,
    this.entry,
    this.template,
    this.pendingId,
  });

  final LifePilotStore store;
  final EntryKind kind;
  final LedgerEntry? entry;

  /// When set, saving approves this draft instead of adding a new entry.
  final String? pendingId;

  /// Initial values for a new entry, e.g. from a UPI handoff.
  final LedgerEntry? template;

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  late EntryKind _kind;
  late String _category;
  String _paymentMethod = 'UPI';
  late DateTime _occurredAt;
  String? _accountId;
  String? _receiptPath;
  bool _categoryChosen = false;
  String? _suggested;
  bool _saving = false;
  bool _showDetails = false;
  String? _error;

  bool get _isExpense => _kind == EntryKind.expense;
  bool get _editing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry ?? widget.template;
    _kind = widget.kind;
    _occurredAt = entry?.occurredAt ?? widget.store.now();
    if (entry != null) {
      _amount.text = paiseToInput(entry.amountPaise);
      _title.text = entry.title;
      _merchant.text = entry.merchant;
      _note.text = entry.note;
      _category = entry.category;
      _paymentMethod = entry.paymentMethod;
      _accountId = widget.store.accountById(entry.accountId)?.id;
      _receiptPath = entry.receiptPath;
      _categoryChosen = true;
      _showDetails = entry.merchant.isNotEmpty || entry.note.isNotEmpty;
    } else {
      _category = _defaultCategory(_kind);
    }
  }

  String _defaultCategory(EntryKind kind) {
    final preferred = kind == EntryKind.expense ? 'Food' : 'Salary';
    return widget.store.categories.contains(preferred)
        ? preferred
        : widget.store.categories.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Suggests a category from similar past entries until the user picks one.
  void _suggestFrom(String text) {
    if (_categoryChosen) return;
    final suggestion = suggestCategory(widget.store.entries, text, kind: _kind);
    if (suggestion == null || !widget.store.categories.contains(suggestion)) {
      if (_suggested != null) setState(() => _suggested = null);
      return;
    }
    setState(() {
      _category = suggestion;
      _suggested = suggestion;
    });
  }

  void _chooseCategory(String category) => setState(() {
        _category = category;
        _categoryChosen = true;
        _suggested = null;
      });

  Future<void> _attachReceipt(bool camera) async {
    try {
      final path =
          await captureReceipt(camera: camera, cipher: widget.store.dataCipher);
      if (path == null || !mounted) return;
      setState(() => _receiptPath = path);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not attach the photo: $error');
      }
    }
  }

  List<String> get _quickCategories {
    const expense = [
      'Food',
      'Transport',
      'Shopping',
      'Bills',
      'Health',
      'Entertainment',
    ];
    const income = [
      'Salary',
      'Freelance',
      'Business',
      'Interest',
      'Gifts',
      'Refunds'
    ];
    final picks = (_isExpense ? expense : income)
        .where(widget.store.categories.contains)
        .toList();
    if (!picks.contains(_category)) picks.insert(0, _category);
    return picks;
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.store.categories;
    return _FormSheet(
      formKey: _formKey,
      title: _editing
          ? 'Edit ${_isExpense ? 'expense' : 'income'}'
          : (_isExpense ? 'Add expense' : 'Add income'),
      children: [
        if (!_editing) ...[
          SegmentedButton<EntryKind>(
            segments: const [
              ButtonSegment(
                  value: EntryKind.expense,
                  icon: Icon(Icons.north_east),
                  label: Text('Expense')),
              ButtonSegment(
                  value: EntryKind.income,
                  icon: Icon(Icons.south_west),
                  label: Text('Income')),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) => setState(() {
              _kind = selection.first;
              _category = _defaultCategory(_kind);
            }),
          ),
          _gap,
        ],
        _amountField(_amount, 'Amount', autofocus: !_editing),
        _gap,
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final item in _quickCategories)
              ChoiceChip(
                label: Text(item),
                selected: _category == item,
                onSelected: (_) => _chooseCategory(item),
              ),
            ActionChip(
              avatar: const Icon(Icons.more_horiz, size: 18),
              label: const Text('More'),
              onPressed: () async {
                final picked = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => SimpleDialog(
                    title: const Text('Category'),
                    children: [
                      for (final item in categories)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(dialogContext, item),
                          child: Text(item),
                        ),
                    ],
                  ),
                );
                if (picked != null) _chooseCategory(picked);
              },
            ),
          ],
        ),
        _gap,
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: _suggestFrom,
          decoration: InputDecoration(
            labelText:
                _isExpense ? 'Description (optional)' : 'Source (optional)',
            hintText: _category,
            helperText: _suggested == null
                ? null
                : 'Category suggested from similar entries: $_suggested',
          ),
        ),
        _gap,
        Text('Payment method', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final method in paymentMethods)
              ChoiceChip(
                label: Text(method),
                selected: _paymentMethod == method,
                onSelected: (_) => setState(() => _paymentMethod = method),
              ),
          ],
        ),
        if (widget.store.accounts.any((account) => !account.archived)) ...[
          _gap,
          Text(_isExpense ? 'Paid from' : 'Received into',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Not set'),
                selected: _accountId == null,
                onSelected: (_) => setState(() => _accountId = null),
              ),
              for (final account
                  in widget.store.accounts.where((item) => !item.archived))
                ChoiceChip(
                  label: Text(account.name),
                  selected: _accountId == account.id,
                  onSelected: (_) => setState(() => _accountId = account.id),
                ),
            ],
          ),
        ],
        _PickerTile(
          icon: Icons.event_outlined,
          label:
              '${friendlyDay(_occurredAt, widget.store.now())}, ${formatTime(_occurredAt, use24h: widget.store.settings.use24HourClock)}',
          onTap: _pickWhen,
        ),
        if (_receiptPath != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_receiptPath!),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
            title: const Text('Receipt attached'),
            onTap: () =>
                showReceipt(context, _receiptPath!, widget.store.dataCipher),
            trailing: IconButton(
              tooltip: 'Remove receipt',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _receiptPath = null),
            ),
          )
        else if (_isExpense)
          Wrap(
            spacing: 8,
            children: [
              if (!isDesktop)
                ActionChip(
                  avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Photo receipt'),
                  onPressed: () => _attachReceipt(true),
                ),
              ActionChip(
                avatar: const Icon(Icons.image_outlined, size: 18),
                label: Text(isDesktop ? 'Attach receipt' : 'From gallery'),
                onPressed: () => _attachReceipt(false),
              ),
            ],
          ),
        if (!_showDetails)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showDetails = true),
              icon: const Icon(Icons.add),
              label: Text(_isExpense ? 'Merchant and note' : 'Note'),
            ),
          )
        else ...[
          if (_isExpense) ...[
            TextFormField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(labelText: 'Merchant (optional)'),
            ),
            _gap,
          ],
          TextFormField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
        _ErrorText(_error),
        _SaveButton(
          label: _editing
              ? 'Save changes'
              : widget.pendingId != null
                  ? 'Approve and save'
                  : 'Save ${_isExpense ? 'expense' : 'income'}',
          saving: _saving,
          onPressed: _save,
        ),
      ],
    );
  }

  Future<void> _pickWhen() async {
    final date = await _pickDate(context, _occurredAt,
        last: widget.store.now().add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await _pickTime(context, TimeOfDay.fromDateTime(_occurredAt));
    setState(() => _occurredAt = DateTime(date.year, date.month, date.day,
        time?.hour ?? _occurredAt.hour, time?.minute ?? _occurredAt.minute));
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final amount = parseRupeesToPaise(_amount.text)!;
    final title = _title.text.trim().isEmpty ? _category : _title.text.trim();
    final draft = LedgerEntry(
      id: widget.entry?.id ?? '',
      kind: _kind,
      amountPaise: amount,
      category: _category,
      title: title,
      occurredAt: _occurredAt,
      paymentMethod: _paymentMethod,
      merchant: _merchant.text.trim(),
      note: _note.text.trim(),
      accountId: _accountId,
      receiptPath: _receiptPath,
    );
    if (!_editing) {
      final duplicates = findPossibleDuplicates(widget.store.entries, draft);
      if (duplicates.isNotEmpty) {
        final match = duplicates.first;
        final proceed = await confirmAction(
          context,
          title: 'Possible duplicate',
          message:
              '“${match.title}” for ${formatMoney(match.amountPaise)} was already recorded on ${formatDateTime(match.occurredAt)}. Save this one too?',
          confirmLabel: 'Save anyway',
        );
        if (!proceed || !mounted) return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (_editing) {
        final previousReceipt = widget.entry!.receiptPath;
        await widget.store.updateEntry(widget.entry!.copyWith(
          kind: draft.kind,
          amountPaise: draft.amountPaise,
          category: draft.category,
          title: draft.title,
          occurredAt: draft.occurredAt,
          paymentMethod: draft.paymentMethod,
          merchant: draft.merchant,
          note: draft.note,
          accountId: draft.accountId,
          clearAccount: draft.accountId == null,
          receiptPath: draft.receiptPath,
          clearReceipt: draft.receiptPath == null,
        ));
        if (previousReceipt != null && previousReceipt != draft.receiptPath) {
          await deleteReceiptFile(previousReceipt);
        }
      } else if (widget.pendingId != null) {
        final saved =
            await widget.store.approvePending(widget.pendingId!, edited: draft);
        messenger?.showSnackBar(SnackBar(
            content: Text('Recorded ${formatMoney(saved.amountPaise)}')));
      } else {
        final saved = await widget.store.addEntry(
          kind: draft.kind,
          amountPaise: draft.amountPaise,
          category: draft.category,
          title: draft.title,
          occurredAt: draft.occurredAt,
          paymentMethod: draft.paymentMethod,
          merchant: draft.merchant,
          note: draft.note,
          accountId: draft.accountId,
          receiptPath: draft.receiptPath,
        );
        messenger?.showSnackBar(SnackBar(
          content: Text(
              '${_isExpense ? 'Expense' : 'Income'} of ${formatMoney(saved.amountPaise)} saved'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.store.deleteEntry(saved.id),
          ),
        ));
      }
      if (widget.store.storageError != null) {
        throw StateError(widget.store.storageError!);
      }
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not save: ${error is StateError ? error.message : error}';
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tasks and reminders

const _reminderChoices = <int, String>{
  0: 'At time',
  5: '5 min',
  10: '10 min',
  15: '15 min',
  30: '30 min',
  60: '1 hour',
  1440: '1 day',
};

const _durationChoices = <int?, String>{
  null: 'No estimate',
  15: '15 min',
  30: '30 min',
  45: '45 min',
  60: '1 hour',
  90: '1.5 hours',
  120: '2 hours',
  180: '3 hours',
};

const _repeatChoices = [
  Recurrence.none,
  Recurrence(Repeat.daily),
  Recurrence(Repeat.weekdays),
  Recurrence(Repeat.weekly),
  Recurrence(Repeat.monthly),
  Recurrence(Repeat.yearly),
];

class _TaskForm extends StatefulWidget {
  const _TaskForm({
    required this.store,
    this.task,
    this.initialDue,
    this.reminder = false,
  });

  final LifePilotStore store;
  final LocalTask? task;
  final DateTime? initialDue;
  final bool reminder;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _project = TextEditingController();
  final _category = TextEditingController();
  final _tags = TextEditingController();
  final _notes = TextEditingController();
  final _newSubtask = TextEditingController();
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  DateTime? _start;
  int? _duration;
  TaskPriority _priority = TaskPriority.medium;
  TaskStatus _status = TaskStatus.todo;
  Recurrence _recurrence = Recurrence.none;
  Set<int> _reminders = {};
  List<Subtask> _subtasks = [];
  bool _showMore = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    if (task != null) {
      _title.text = task.title;
      _description.text = task.description;
      _project.text = task.project;
      _category.text = task.category;
      _tags.text = task.tags.join(', ');
      _notes.text = task.notes;
      _dueDate = task.dueAt;
      _dueTime = task.dueAt != null && task.dueHasTime
          ? TimeOfDay.fromDateTime(task.dueAt!)
          : null;
      _start = task.startAt;
      _duration = task.durationMinutes;
      _priority = task.priority;
      _status = task.status;
      _recurrence = task.recurrence;
      _reminders = task.reminderOffsets.toSet();
      _subtasks = [...task.subtasks];
      _showMore = task.description.isNotEmpty ||
          task.subtasks.isNotEmpty ||
          task.notes.isNotEmpty ||
          task.tags.isNotEmpty ||
          task.startAt != null;
    } else if (widget.reminder) {
      final next = widget.store.now().add(const Duration(hours: 1));
      _dueDate = widget.initialDue ?? next;
      _dueTime = TimeOfDay(hour: next.hour, minute: 0);
      _reminders = {0};
    } else if (widget.initialDue != null) {
      _dueDate = widget.initialDue;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _description,
      _project,
      _category,
      _tags,
      _notes,
      _newSubtask,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  DateTime? get _due => _dueDate == null
      ? null
      : DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day,
          _dueTime?.hour ?? 0, _dueTime?.minute ?? 0);

  @override
  Widget build(BuildContext context) {
    final use24h = widget.store.settings.use24HourClock;
    final now = widget.store.now();
    final due = _due;
    return _FormSheet(
      formKey: _formKey,
      title: _editing
          ? 'Edit task'
          : widget.reminder
              ? 'New reminder'
              : 'New task',
      children: [
        TextFormField(
          controller: _title,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: widget.reminder ? 'Remind me to…' : 'Task'),
          validator: (value) => _requiredText(value, 'Add a title.'),
        ),
        _gap,
        Text('Priority', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<TaskPriority>(
          showSelectedIcon: false,
          segments: [
            for (final priority in TaskPriority.values)
              ButtonSegment(value: priority, label: Text(priority.label)),
          ],
          selected: {_priority},
          onSelectionChanged: (value) =>
              setState(() => _priority = value.first),
        ),
        const SizedBox(height: 4),
        _PickerTile(
          icon: Icons.event_outlined,
          label: due == null
              ? 'Add a due date'
              : 'Due ${friendlyDay(due, now)}${_dueTime == null ? '' : ', ${formatTime(due, use24h: use24h)}'}',
          onTap: _pickDue,
          onClear: due == null
              ? null
              : () => setState(() {
                    _dueDate = null;
                    _dueTime = null;
                    _reminders = {};
                  }),
        ),
        if (due != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(
                avatar: const Icon(Icons.schedule, size: 18),
                label: Text(_dueTime == null
                    ? 'Add time'
                    : formatTime(due, use24h: use24h)),
                onPressed: _pickDueTime,
              ),
              if (_dueTime != null)
                ActionChip(
                  label: const Text('All day'),
                  onPressed: () => setState(() => _dueTime = null),
                ),
            ],
          ),
          _gap,
          Text(
              _dueTime == null
                  ? 'Remind me (at 9:00 AM on the day)'
                  : 'Remind me before',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final MapEntry(key: minutes, value: label)
                  in _reminderChoices.entries)
                if (_dueTime != null || minutes == 0 || minutes == 1440)
                  FilterChip(
                    label: Text(_dueTime == null && minutes == 0
                        ? 'On the day'
                        : label),
                    selected: _reminders.contains(minutes),
                    onSelected: (selected) => setState(() => selected
                        ? _reminders.add(minutes)
                        : _reminders.remove(minutes)),
                  ),
            ],
          ),
          _gap,
          DropdownButtonFormField<Recurrence>(
            initialValue: _repeatChoices.contains(_recurrence)
                ? _recurrence
                : Recurrence.none,
            decoration: const InputDecoration(labelText: 'Repeat'),
            items: [
              for (final rule in _repeatChoices)
                DropdownMenuItem(value: rule, child: Text(rule.label)),
            ],
            onChanged: (value) =>
                setState(() => _recurrence = value ?? Recurrence.none),
          ),
        ],
        _gap,
        DropdownButtonFormField<int?>(
          initialValue:
              _durationChoices.containsKey(_duration) ? _duration : null,
          decoration: const InputDecoration(labelText: 'Estimated duration'),
          items: [
            for (final MapEntry(key: minutes, value: label)
                in _durationChoices.entries)
              DropdownMenuItem(value: minutes, child: Text(label)),
          ],
          onChanged: (value) => setState(() => _duration = value),
        ),
        _gap,
        TextFormField(
          controller: _project,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Project (optional)'),
        ),
        if (widget.store.projects.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              children: [
                for (final project in widget.store.projects.take(6))
                  ActionChip(
                    label: Text(project),
                    onPressed: () => setState(() => _project.text = project),
                  ),
              ],
            ),
          ),
        if (!_showMore)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showMore = true),
              icon: const Icon(Icons.expand_more),
              label: const Text('Status, subtasks, tags and notes'),
            ),
          )
        else
          ..._moreFields(context, use24h, now),
        _ErrorText(_error),
        _SaveButton(
          label: _editing
              ? 'Save changes'
              : (widget.reminder ? 'Set reminder' : 'Add task'),
          icon: widget.reminder ? Icons.alarm_add : Icons.add_task,
          saving: _saving,
          onPressed: _save,
        ),
      ],
    );
  }

  List<Widget> _moreFields(BuildContext context, bool use24h, DateTime now) => [
        _gap,
        DropdownButtonFormField<TaskStatus>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            for (final status in TaskStatus.values)
              DropdownMenuItem(value: status, child: Text(status.label)),
          ],
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
        _gap,
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        _gap,
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _tags,
                decoration: const InputDecoration(
                    labelText: 'Tags', hintText: 'home, urgent'),
              ),
            ),
          ],
        ),
        _PickerTile(
          icon: Icons.play_circle_outline,
          label: _start == null
              ? 'Add a start time'
              : 'Starts ${friendlyDay(_start!, now)}, ${formatTime(_start!, use24h: use24h)}',
          onTap: _pickStart,
          onClear: _start == null ? null : () => setState(() => _start = null),
        ),
        Text('Subtasks', style: Theme.of(context).textTheme.labelLarge),
        for (final subtask in _subtasks)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: subtask.done,
            title: Text(subtask.title),
            onChanged: (value) => setState(() {
              final index = _subtasks.indexOf(subtask);
              _subtasks[index] = subtask.copyWith(done: value ?? false);
            }),
            secondary: IconButton(
              tooltip: 'Remove subtask',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _subtasks.remove(subtask)),
            ),
          ),
        TextField(
          controller: _newSubtask,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Add a subtask',
            suffixIcon: IconButton(
              tooltip: 'Add subtask',
              icon: const Icon(Icons.add),
              onPressed: _addSubtask,
            ),
          ),
          onSubmitted: (_) => _addSubtask(),
        ),
        _gap,
        TextFormField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
      ];

  void _addSubtask() {
    final text = _newSubtask.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(widget.store.newSubtask(text));
      _newSubtask.clear();
    });
  }

  Future<void> _pickDue() async {
    final now = widget.store.now();
    final picked = await _pickDate(context, _dueDate ?? now,
        first: DateTime(now.year - 1));
    if (picked == null) return;
    setState(() {
      _dueDate = picked;
      if (_reminders.isEmpty && _dueTime == null) _reminders = {0};
    });
  }

  Future<void> _pickDueTime() async {
    final picked = await _pickTime(
        context, _dueTime ?? const TimeOfDay(hour: 9, minute: 0));
    if (picked == null) return;
    setState(() {
      _dueTime = picked;
      _reminders.remove(1440);
      if (_reminders.isEmpty) {
        _reminders = {widget.store.settings.defaultReminderMinutes};
      }
    });
  }

  Future<void> _pickStart() async {
    final base = _start ?? _dueDate ?? widget.store.now();
    final date = await _pickDate(context, base);
    if (date == null || !mounted) return;
    final time = await _pickTime(context, TimeOfDay.fromDateTime(base));
    if (time == null) return;
    setState(() => _start =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final due = _due;
    final now = widget.store.now();
    if (widget.reminder && (due == null || _dueTime == null)) {
      setState(() => _error = 'Choose a date and time for the reminder.');
      return;
    }
    if (due != null &&
        _dueTime != null &&
        _reminders.isNotEmpty &&
        !_reminders.any(
            (offset) => due.subtract(Duration(minutes: offset)).isAfter(now))) {
      setState(() => _error =
          'All chosen reminder times are in the past. Pick a later time or change the reminder.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final tags = _tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final reminders = _reminders.toList()..sort();
    try {
      if (_editing) {
        await widget.store.updateTask(widget.task!.copyWith(
          title: _title.text.trim(),
          description: _description.text.trim(),
          project: _project.text.trim(),
          category: _category.text.trim(),
          tags: tags,
          notes: _notes.text.trim(),
          dueAt: due,
          clearDue: due == null,
          dueHasTime: _dueTime != null,
          startAt: _start,
          clearStart: _start == null,
          durationMinutes: _duration,
          clearDuration: _duration == null,
          priority: _priority,
          status: _status,
          recurrence: due == null ? Recurrence.none : _recurrence,
          reminderOffsets: reminders,
          subtasks: _subtasks,
        ));
      } else {
        await widget.store.addTask(
          title: _title.text,
          project: _project.text,
          description: _description.text,
          category: _category.text,
          tags: tags,
          notes: _notes.text,
          dueAt: due,
          dueHasTime: _dueTime != null,
          startAt: _start,
          durationMinutes: _duration,
          priority: _priority,
          status: _status,
          recurrence: due == null ? Recurrence.none : _recurrence,
          reminderOffsets: reminders,
          subtasks: _subtasks.map((item) => item.title).toList(),
        );
      }
      if (widget.store.storageError != null) {
        throw StateError(widget.store.storageError!);
      }
      if (!mounted) return;
      if (due != null && reminders.isNotEmpty) {
        await ensureReminderPermission(context);
      }
      if (!mounted) return;
      showMessage(
          context,
          _editing
              ? 'Task updated'
              : (widget.reminder ? 'Reminder set' : 'Task added'));
      Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not save: ${error is StateError ? error.message : error}';
        });
      }
    }
  }
}

/// Quick reschedule choices for a task, with a custom date and time option.
Future<void> showRescheduleSheet(
    BuildContext context, LifePilotStore store, LocalTask task) async {
  final now = store.now();
  final time = task.dueHasTime && task.dueAt != null
      ? TimeOfDay.fromDateTime(task.dueAt!)
      : const TimeOfDay(hour: 9, minute: 0);
  DateTime at(DateTime day) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);
  final laterToday = now.add(const Duration(hours: 3));
  var toSaturday = (DateTime.saturday - now.weekday + 7) % 7;
  if (toSaturday == 0) toSaturday = 7;
  final options = <(String, DateTime, bool)>[
    if (laterToday.day == now.day)
      (
        'Later today (${formatTime(DateTime(now.year, now.month, now.day, laterToday.hour), use24h: store.settings.use24HourClock)})',
        DateTime(now.year, now.month, now.day, laterToday.hour),
        true
      ),
    (
      'Tomorrow',
      at(DateTime(now.year, now.month, now.day + 1)),
      task.dueHasTime
    ),
    (
      'Saturday',
      at(DateTime(now.year, now.month, now.day + toSaturday)),
      task.dueHasTime
    ),
    (
      'Next week',
      at(DateTime(now.year, now.month, now.day + 8 - now.weekday)),
      task.dueHasTime
    ),
  ];
  final choice = await showModalBottomSheet<Object>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Reschedule “${task.title}”',
                style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final option in options)
            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: Text(option.$1),
              subtitle: Text(formatDate(option.$2)),
              onTap: () => Navigator.pop(sheetContext, option),
            ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Pick date and time'),
            onTap: () => Navigator.pop(sheetContext, 'custom'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice is (String, DateTime, bool)) {
    await store.rescheduleTask(task.id, choice.$2, hasTime: choice.$3);
  } else {
    final date = await _pickDate(context, task.dueAt ?? now);
    if (date == null || !context.mounted) return;
    final picked = await _pickTime(context, time);
    await store.rescheduleTask(
      task.id,
      DateTime(date.year, date.month, date.day, picked?.hour ?? 0,
          picked?.minute ?? 0),
      hasTime: picked != null,
    );
  }
  if (context.mounted) showMessage(context, 'Task rescheduled');
}

Future<void> showSnoozeSheet(
    BuildContext context, LifePilotStore store, LocalTask task) async {
  final minutes = await showModalBottomSheet<int>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Snooze “${task.title}”',
                style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final value in [5, 10, 15, 30, 60])
            ListTile(
              leading: const Icon(Icons.snooze),
              title: Text(value == 60 ? '1 hour' : '$value minutes'),
              onTap: () => Navigator.pop(sheetContext, value),
            ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Custom'),
            onTap: () => Navigator.pop(sheetContext, -1),
          ),
        ],
      ),
    ),
  );
  if (minutes == null || !context.mounted) return;
  var value = minutes;
  if (value == -1) {
    final controller = TextEditingController();
    final custom = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Snooze for'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'minutes'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Snooze'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (custom == null || custom <= 0 || custom > 7 * 24 * 60) return;
    value = custom;
  }
  await store.snoozeTask(task.id, value);
  if (!context.mounted) return;
  await ensureReminderPermission(context);
  if (context.mounted) showMessage(context, 'Snoozed for $value minutes');
}

// ---------------------------------------------------------------------------
// Budgets and goals

class _BudgetForm extends StatefulWidget {
  const _BudgetForm({required this.store, this.budget});

  final LifePilotStore store;
  final SpendingBudget? budget;

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  final _limit = TextEditingController();
  late String _category;
  BudgetPeriod _period = BudgetPeriod.monthly;
  bool _rollover = false;
  double _alert = 80;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    final unused = widget.store.categories.where((category) =>
        !widget.store.budgets.any((budget) => budget.category == category));
    _category = budget?.category ??
        (unused.contains('Food')
            ? 'Food'
            : unused.isEmpty
                ? widget.store.categories.first
                : unused.first);
    if (budget != null) {
      _limit.text = paiseToInput(budget.limitPaise);
      _period = budget.period;
      _rollover = budget.rollover;
      _alert = budget.alertPercent.toDouble();
    }
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        formKey: _formKey,
        title: widget.budget == null ? 'Set a budget' : 'Update budget',
        subtitle:
            'Spending is counted from expenses you record in this category.',
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final item in widget.store.categories)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: widget.budget != null
                ? null
                : (value) => setState(() => _category = value ?? _category),
          ),
          _gap,
          SegmentedButton<BudgetPeriod>(
            segments: const [
              ButtonSegment(
                  value: BudgetPeriod.monthly, label: Text('Monthly')),
              ButtonSegment(value: BudgetPeriod.weekly, label: Text('Weekly')),
            ],
            selected: {_period},
            onSelectionChanged: (value) =>
                setState(() => _period = value.first),
          ),
          _gap,
          _amountField(
              _limit,
              _period == BudgetPeriod.monthly
                  ? 'Monthly limit'
                  : 'Weekly limit'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Roll over unspent amount'),
            subtitle: const Text(
                'Adds what was left last period to this period’s limit.'),
            value: _rollover,
            onChanged: (value) => setState(() => _rollover = value),
          ),
          Text('Alert when ${_alert.round()}% is used',
              style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: _alert,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_alert.round()}%',
            onChanged: (value) => setState(() => _alert = value),
          ),
          if (widget.store.budgets.any((budget) =>
              budget.category == _category && widget.budget == null))
            const _ErrorText(
                'This category already has a budget. Saving replaces it.'),
          _ErrorText(_error),
          _SaveButton(label: 'Save budget', saving: _saving, onPressed: _save),
        ],
      );

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.store.setBudget(
        _category,
        parseRupeesToPaise(_limit.text)!,
        period: _period,
        rollover: _rollover,
        alertPercent: _alert.round(),
      );
      if (!mounted) return;
      showMessage(context, 'Budget saved');
      Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $error';
        });
      }
    }
  }
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.store, this.goal});

  final LifePilotStore store;
  final SavingsGoal? goal;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  GoalType _type = GoalType.emergency;
  DateTime? _targetDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    if (goal != null) {
      _name.text = goal.name;
      _target.text = paiseToInput(goal.targetPaise);
      _type = goal.type;
      _targetDate = goal.targetDate;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        formKey: _formKey,
        title: widget.goal == null ? 'Create a savings goal' : 'Edit goal',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final type in GoalType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: (_) => setState(() {
                    if (_name.text.isEmpty || _name.text == _type.label) {
                      _name.text = type == GoalType.custom ? '' : type.label;
                    }
                    _type = type;
                  }),
                ),
            ],
          ),
          _gap,
          TextFormField(
            controller: _name,
            autofocus: widget.goal == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Goal name'),
            validator: (value) => _requiredText(value, 'Name your goal.'),
          ),
          _gap,
          _amountField(_target, 'Target amount'),
          _PickerTile(
            icon: Icons.flag_outlined,
            label: _targetDate == null
                ? 'Add a target date (optional)'
                : 'Target date ${formatDate(_targetDate!)}',
            onTap: () async {
              final now = widget.store.now();
              final picked = await _pickDate(context,
                  _targetDate ?? DateTime(now.year + 1, now.month, now.day),
                  first: now);
              if (picked != null) setState(() => _targetDate = picked);
            },
            onClear: _targetDate == null
                ? null
                : () => setState(() => _targetDate = null),
          ),
          _ErrorText(_error),
          _SaveButton(
              label: widget.goal == null ? 'Create goal' : 'Save goal',
              saving: _saving,
              onPressed: _save),
        ],
      );

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final target = parseRupeesToPaise(_target.text)!;
      if (widget.goal == null) {
        await widget.store
            .addGoal(_name.text, target, targetDate: _targetDate, type: _type);
      } else {
        await widget.store.updateGoal(widget.goal!.copyWith(
          name: _name.text.trim(),
          targetPaise: target,
          targetDate: _targetDate,
          clearTargetDate: _targetDate == null,
          type: _type,
        ));
      }
      if (!mounted) return;
      showMessage(context, 'Goal saved');
      Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $error';
        });
      }
    }
  }
}

class _ContributionForm extends StatefulWidget {
  const _ContributionForm({required this.store, required this.goal});

  final LifePilotStore store;
  final SavingsGoal goal;

  @override
  State<_ContributionForm> createState() => _ContributionFormState();
}

class _ContributionFormState extends State<_ContributionForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final suggestion =
        suggestedMonthlyContribution(widget.goal, widget.store.now());
    if (suggestion != null) _amount.text = paiseToInput(suggestion);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        formKey: _formKey,
        title: 'Add to ${widget.goal.name}',
        subtitle:
            '${formatMoney(widget.goal.remainingPaise)} to go. Contributions are tracked separately from expenses.',
        children: [
          _amountField(_amount, 'Contribution', autofocus: true),
          _gap,
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          _SaveButton(
              label: 'Record contribution', saving: _saving, onPressed: _save),
        ],
      );

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final amount = parseRupeesToPaise(_amount.text)!;
    await widget.store
        .contributeToGoal(widget.goal.id, amount, note: _note.text);
    if (!mounted) return;
    final goal = widget.store.goals.firstWhere((g) => g.id == widget.goal.id);
    showMessage(
        context,
        goal.remainingPaise == 0
            ? '${goal.name} reached!'
            : '${formatMoney(amount)} added · ${(goal.progress * 100).round()}% saved');
    Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Bills

const _billRepeats = [
  Recurrence.none,
  Recurrence(Repeat.weekly),
  Recurrence(Repeat.monthly),
  Recurrence(Repeat.quarterly),
  Recurrence(Repeat.yearly),
];

class _BillForm extends StatefulWidget {
  const _BillForm({required this.store, this.bill});

  final LifePilotStore store;
  final Bill? bill;

  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  BillKind _kind = BillKind.electricity;
  late DateTime _due;
  Recurrence _recurrence = const Recurrence(Repeat.monthly);
  int _remindDays = 2;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final bill = widget.bill;
    final now = widget.store.now();
    _due = DateTime(now.year, now.month, now.day + 7);
    if (bill != null) {
      _name.text = bill.name;
      _amount.text = paiseToInput(bill.amountPaise);
      _notes.text = bill.notes;
      _kind = bill.kind;
      _due = bill.nextDueAt;
      _recurrence = Recurrence(bill.recurrence.repeat);
      _remindDays = bill.remindDaysBefore;
    } else {
      _name.text = _kind.label;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        formKey: _formKey,
        title: widget.bill == null ? 'Add a bill' : 'Edit bill',
        subtitle:
            'A bill stays unpaid until you confirm a payment. Passing the due date never marks it paid.',
        children: [
          DropdownButtonFormField<BillKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final kind in BillKind.values)
                DropdownMenuItem(value: kind, child: Text(kind.label)),
            ],
            onChanged: (value) => setState(() {
              if (value == null) return;
              if (_name.text.isEmpty || _name.text == _kind.label) {
                _name.text = value.label;
              }
              _kind = value;
              if (value == BillKind.insurance) {
                _recurrence = const Recurrence(Repeat.yearly);
              }
            }),
          ),
          _gap,
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (value) => _requiredText(value, 'Name the bill.'),
          ),
          _gap,
          _amountField(_amount, 'Amount'),
          _PickerTile(
            icon: Icons.event_outlined,
            label: 'Next due ${formatDate(_due)}',
            onTap: () async {
              final picked = await _pickDate(context, _due);
              if (picked != null) setState(() => _due = picked);
            },
          ),
          DropdownButtonFormField<Recurrence>(
            initialValue: _billRepeats.contains(_recurrence)
                ? _recurrence
                : const Recurrence(Repeat.monthly),
            decoration: const InputDecoration(labelText: 'Repeats'),
            items: [
              for (final rule in _billRepeats)
                DropdownMenuItem(
                  value: rule,
                  child: Text(rule.isNone ? 'One time' : rule.label),
                ),
            ],
            onChanged: (value) =>
                setState(() => _recurrence = value ?? _recurrence),
          ),
          _gap,
          DropdownButtonFormField<int>(
            initialValue: _remindDays,
            decoration: const InputDecoration(labelText: 'Reminder'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('On the due date only')),
              DropdownMenuItem(value: 1, child: Text('1 day before')),
              DropdownMenuItem(value: 2, child: Text('2 days before')),
              DropdownMenuItem(value: 3, child: Text('3 days before')),
              DropdownMenuItem(value: 7, child: Text('1 week before')),
            ],
            onChanged: (value) => setState(() => _remindDays = value ?? 2),
          ),
          _gap,
          TextFormField(
            controller: _notes,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Account or consumer number'),
          ),
          _ErrorText(_error),
          _SaveButton(label: 'Save bill', saving: _saving, onPressed: _save),
        ],
      );

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final amount = parseRupeesToPaise(_amount.text)!;
      if (widget.bill == null) {
        await widget.store.addBill(
          name: _name.text,
          kind: _kind,
          amountPaise: amount,
          nextDueAt: _due,
          recurrence: _recurrence,
          remindDaysBefore: _remindDays,
          notes: _notes.text,
        );
      } else {
        await widget.store.updateBill(widget.bill!.copyWith(
          name: _name.text.trim(),
          kind: _kind,
          amountPaise: amount,
          nextDueAt: dateOnly(_due),
          recurrence: _recurrence,
          remindDaysBefore: _remindDays,
          notes: _notes.text.trim(),
          active: true,
        ));
      }
      if (!mounted) return;
      await ensureReminderPermission(context);
      if (!mounted) return;
      showMessage(context, 'Bill saved');
      Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $error';
        });
      }
    }
  }
}

class _MarkPaidForm extends StatefulWidget {
  const _MarkPaidForm({required this.store, required this.bill});

  final LifePilotStore store;
  final Bill bill;

  @override
  State<_MarkPaidForm> createState() => _MarkPaidFormState();
}

class _MarkPaidFormState extends State<_MarkPaidForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late DateTime _paidAt;
  String _method = 'UPI';
  bool _recordExpense = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.text = paiseToInput(widget.bill.amountPaise);
    _paidAt = widget.store.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.bill.recurrence.next(widget.bill.nextDueAt);
    return _FormSheet(
      formKey: _formKey,
      title: 'Confirm payment',
      subtitle:
          '${widget.bill.name}, due ${formatDate(widget.bill.nextDueAt)}. Confirm only after you have paid.',
      children: [
        _amountField(_amount, 'Amount paid'),
        _PickerTile(
          icon: Icons.event_available_outlined,
          label: 'Paid on ${formatDate(_paidAt)}',
          onTap: () async {
            final picked =
                await _pickDate(context, _paidAt, last: widget.store.now());
            if (picked != null) setState(() => _paidAt = picked);
          },
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final method in paymentMethods)
              ChoiceChip(
                label: Text(method),
                selected: _method == method,
                onSelected: (_) => setState(() => _method = method),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Record as an expense'),
          subtitle: Text('Adds it to ${widget.bill.category} spending.'),
          value: _recordExpense,
          onChanged: (value) => setState(() => _recordExpense = value),
        ),
        Text(
          next == null
              ? 'This one-time bill will be marked settled.'
              : 'The next due date becomes ${formatDate(next)}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _SaveButton(
            label: 'Mark as paid',
            icon: Icons.task_alt,
            saving: _saving,
            onPressed: _save),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.store.markBillPaid(
      widget.bill.id,
      amountPaise: parseRupeesToPaise(_amount.text),
      paidAt: _paidAt,
      recordExpense: _recordExpense,
      paymentMethod: _method,
    );
    if (!mounted) return;
    showMessage(context, '${widget.bill.name} marked as paid');
    Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Notes and alarms

class _NoteForm extends StatefulWidget {
  const _NoteForm({required this.store, this.note});

  final LifePilotStore store;
  final QuickNote? note;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  final _formKey = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.note?.text);
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        formKey: _formKey,
        title: widget.note == null ? 'New note' : 'Edit note',
        children: [
          TextFormField(
            controller: _text,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Write something…'),
            validator: (value) => _requiredText(value, 'The note is empty.'),
          ),
          _SaveButton(label: 'Save note', saving: _saving, onPressed: _save),
        ],
      );

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    if (widget.note == null) {
      await widget.store.addNote(_text.text);
    } else {
      await widget.store
          .updateNote(widget.note!.copyWith(text: _text.text.trim()));
    }
    if (!mounted) return;
    showMessage(context, 'Note saved');
    Navigator.pop(context);
  }
}

class _AlarmForm extends StatefulWidget {
  const _AlarmForm({required this.store, this.alarm});

  final LifePilotStore store;
  final Alarm? alarm;

  @override
  State<_AlarmForm> createState() => _AlarmFormState();
}

class _AlarmFormState extends State<_AlarmForm> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.alarm?.label);
  late TimeOfDay _time = widget.alarm == null
      ? const TimeOfDay(hour: 7, minute: 0)
      : TimeOfDay(hour: widget.alarm!.hour, minute: widget.alarm!.minute);
  late final Set<int> _days = {...?widget.alarm?.weekdays};
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final use24h = widget.store.settings.use24HourClock;
    return _FormSheet(
      formKey: _formKey,
      title: widget.alarm == null ? 'New alarm' : 'Edit alarm',
      subtitle:
          'Alarms are high-priority notifications. They do not ring continuously like the system clock app.',
      children: [
        Center(
          child: TextButton(
            onPressed: () async {
              final picked = await _pickTime(context, _time);
              if (picked != null) setState(() => _time = picked);
            },
            child: Text(
              formatTime(DateTime(2000, 1, 1, _time.hour, _time.minute),
                  use24h: use24h),
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ),
        ),
        _gap,
        TextFormField(
          controller: _label,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Label (optional)'),
        ),
        _gap,
        Text(_days.isEmpty ? 'Repeats every day' : 'Repeats on selected days',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label: Text(weekdayShort(day)),
                selected: _days.contains(day),
                onSelected: (selected) => setState(
                    () => selected ? _days.add(day) : _days.remove(day)),
              ),
          ],
        ),
        _SaveButton(
            label: 'Save alarm',
            icon: Icons.alarm,
            saving: _saving,
            onPressed: _save),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final base =
        widget.alarm ?? widget.store.newAlarm(_time.hour, _time.minute);
    final days = _days.toList()..sort();
    final alarm = base.copyWith(
      hour: _time.hour,
      minute: _time.minute,
      label: _label.text.trim(),
      weekdays: days.length == 7 ? const [] : days,
      enabled: true,
    );
    await widget.store.saveAlarm(alarm);
    if (!mounted) return;
    await ensureReminderPermission(context);
    if (!mounted) return;
    final next = alarm.nextFire(widget.store.now());
    showMessage(context,
        'Alarm set for ${friendlyDay(next, widget.store.now()).toLowerCase()} ${formatTime(next, use24h: widget.store.settings.use24HourClock)}');
    Navigator.pop(context);
  }
}
