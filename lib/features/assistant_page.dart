import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/assistant_engine.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../services/reminder_coordinator.dart';
import '../ui/forms.dart';
import '../ui/widgets.dart';

class _Message {
  const _Message(this.text, {this.isUser = false});

  final String text;
  final bool isUser;
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final _engine = AssistantEngine(widget.store);
  final _speech = SpeechToText();
  bool _listening = false;
  final List<_Message> _messages = [
    const _Message(
      'Hi, I’m your offline assistant. I can record expenses, create tasks and reminders, and answer questions about the records on this device. I always ask before saving anything.',
    ),
  ];
  AssistantAction? _pending;
  bool _executing = false;

  static const _suggestions = [
    'Add ₹250 for lunch',
    'Show my expenses this month',
    'Remind me to pay my electricity bill tomorrow at 7 PM',
    'Show my overdue tasks',
    'How much of my food budget remains?',
    'Compare my expenses with last month',
    'Show my upcoming bills',
    'Plan my day',
  ];

  @override
  void dispose() {
    _speech.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.offline_bolt_outlined,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Runs with fixed rules on your device. Nothing you type is sent to an AI service, and answers come only from your saved records.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final message in _messages)
                  _MessageBubble(message: message),
                if (_pending != null)
                  _ConfirmationCard(
                    action: _pending!,
                    busy: _executing,
                    onCancel: _cancel,
                    onConfirm: _confirm,
                    onEdit: _edit,
                  ),
                if (_pending == null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final suggestion in _messages.length == 1
                          ? _suggestions
                          : _suggestions.take(3))
                        ActionChip(
                          label: Text(suggestion),
                          onPressed: () => _submit(suggestion),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Ask or tell me something…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onSubmitted: _submit,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _listening ? 'Stop listening' : 'Speak',
                    onPressed: _toggleVoice,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                        color: _listening
                            ? Theme.of(context).colorScheme.error
                            : null),
                  ),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: () => _submit(_controller.text),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  void _submit(String raw) {
    final text = raw.trim();
    if (text.isEmpty || _executing) return;
    _controller.clear();
    final reply = _engine.handle(text);
    setState(() {
      _messages.add(_Message(text, isUser: true));
      _messages.add(_Message(reply.text));
      _pending = reply.proposal;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: motion(context, 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirm() async {
    final action = _pending;
    if (action == null || _executing) return;
    setState(() => _executing = true);
    String result;
    try {
      result = await _engine.execute(action);
      if (widget.store.storageError != null) {
        result = '$result\nWarning: ${widget.store.storageError}';
      }
    } on Object catch (error) {
      result = 'That could not be saved: $error';
    }
    if (!mounted) return;
    if (action is AddTaskAction && action.remind) {
      await ensureReminderPermission(context);
    }
    if (!mounted) return;
    setState(() {
      _executing = false;
      _pending = null;
      _messages.add(_Message(result));
    });
    _scrollToEnd();
  }

  void _cancel() {
    setState(() {
      _pending = null;
      _messages.add(const _Message('Okay, nothing was saved.'));
    });
  }

  /// Voice input through Android's speech recogniser. The recognised text is
  /// put in the input box so it can be checked before sending.
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    var available = false;
    try {
      available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    } on Object {
      available = false;
    }
    if (!mounted) return;
    if (!available) {
      showMessage(context,
          'Speech recognition is not available. Allow microphone access, and check that a speech service such as Google is installed.',
          error: true);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _controller.text = result.recognizedWords;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
      },
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  Future<void> _edit() async {
    final action = _pending;
    setState(() => _pending = null);
    switch (action) {
      case AddEntryAction():
        await showEntryForm(
          context,
          widget.store,
          template: LedgerEntry(
            id: '',
            kind: action.kind,
            amountPaise: action.amountPaise,
            category: action.category,
            title: action.title,
            occurredAt: action.occurredAt,
          ),
        );
      case AddTaskAction():
        await showTaskForm(context, widget.store, initialDue: action.dueAt);
      default:
        return;
    }
    if (mounted) {
      setState(() => _messages.add(const _Message(
          'I opened the full form. Anything you save there is recorded as usual.')));
    }
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: message.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 18),
          ),
        ),
        child: SelectableText(message.text),
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.action,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final AssistantAction action;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (heading, lines, warning) = switch (action) {
      AddEntryAction(
        :final kind,
        :final amountPaise,
        :final category,
        :final title,
        :final occurredAt,
        :final duplicateWarning
      ) =>
        (
          kind == EntryKind.income ? 'Save income?' : 'Save expense?',
          [
            formatMoney(amountPaise),
            '$title · $category',
            formatDateTime(occurredAt),
          ],
          duplicateWarning,
        ),
      AddTaskAction(
        :final title,
        :final dueAt,
        :final dueHasTime,
        :final remind
      ) =>
        (
          remind ? 'Set reminder?' : 'Create task?',
          [
            title,
            dueAt == null
                ? 'No due date'
                : dueHasTime
                    ? formatDateTime(dueAt)
                    : formatDate(dueAt),
            if (remind && dueAt != null) 'Notification at the due time',
          ],
          null,
        ),
      AddBillAction(
        :final name,
        :final amountPaise,
        :final dueAt,
        :final recurrence
      ) =>
        (
          'Track bill?',
          [
            formatMoney(amountPaise),
            name,
            'Next due ${formatDate(dueAt)} · ${recurrence.isNone ? 'one time' : recurrence.label}',
          ],
          null,
        ),
      GoalContributionAction(:final goalName, :final amountPaise) => (
          'Add to savings goal?',
          [formatMoney(amountPaise), goalName],
          null,
        ),
      StartTimerAction(:final minutes, :final focus, :final label) => (
          focus ? 'Start focus session?' : 'Start timer?',
          [
            focus ? 'Focus' : '$minutes min',
            if (label.isNotEmpty) label,
          ],
          null,
        ),
      CompleteItemAction(:final title, :final isHabit) => (
          isHabit ? 'Check in habit?' : 'Complete task?',
          [title],
          null,
        ),
      DeleteEntryAction(:final entry) => (
          'Delete this ${entry.isIncome ? 'income' : 'expense'}?',
          [
            formatMoney(entry.amountPaise),
            '${entry.title} · ${entry.category}',
            formatDateTime(entry.occurredAt),
          ],
          null,
        ),
    };
    final editable = action is AddEntryAction || action is AddTaskAction;
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(lines.first, style: theme.textTheme.titleLarge),
            for (final line in lines.skip(1)) Text(line),
            if (warning != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Possible duplicate: $warning')),
                ],
              ),
            ],
            const SizedBox(height: 10),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 4,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(
                    onPressed: busy ? null : onCancel,
                    child: const Text('Cancel')),
                if (editable)
                  TextButton(
                      onPressed: busy ? null : onEdit,
                      child: const Text('Edit')),
                FilledButton.icon(
                  style: action.destructive
                      ? FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError)
                      : null,
                  onPressed: busy ? null : onConfirm,
                  icon: Icon(
                      action.destructive ? Icons.delete_outline : Icons.check),
                  label: Text(busy
                      ? 'Working…'
                      : action.destructive
                          ? 'Delete'
                          : 'Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
