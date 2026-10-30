import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calculator.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../ui/forms.dart';

/// A plain calculator with a running result, a short history for this
/// session, and a shortcut to record the result as an expense.
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  String _input = '';
  final _history = <({String expression, String result})>[];

  double? get _result => evaluateExpression(_input);

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (key) {
        case 'C':
          _input = '';
        case '⌫':
          if (_input.isNotEmpty) {
            _input = _input.substring(0, _input.length - 1);
          }
        case '=':
          final result = _result;
          if (result == null) return;
          final text = formatCalculatorResult(result);
          _history.insert(0, (expression: _input, result: text));
          if (_history.length > 20) _history.removeLast();
          _input = text;
        case '+' || '−' || '×' || '÷':
          // Replace a trailing operator instead of stacking them.
          if (_input.isNotEmpty && '+−×÷'.contains(_input[_input.length - 1])) {
            _input = _input.substring(0, _input.length - 1);
          }
          if (_input.isEmpty && key != '−') return;
          _input += key;
        case '.':
          final lastNumber =
              RegExp(r'[\d.]*$').firstMatch(_input)?.group(0) ?? '';
          if (lastNumber.contains('.')) return;
          _input += lastNumber.isEmpty ? '0.' : '.';
        default:
          if (_input.length < 60) _input += key;
      }
    });
  }

  Future<void> _addExpense() async {
    final result = _result;
    if (result == null || result <= 0) return;
    final paise = (result * 100).round();
    await showEntryForm(
      context,
      widget.store,
      template: LedgerEntry(
        id: '',
        kind: EntryKind.expense,
        amountPaise: paise,
        category: widget.store.categories.first,
        title: '',
        occurredAt: widget.store.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final result = _result;
    final showPreview = result != null &&
        _input.isNotEmpty &&
        formatCalculatorResult(result) != _input;
    const keys = [
      ['C', '(', ')', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['%', '0', '.', '⌫'],
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculator'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              tooltip: 'History',
              icon: const Icon(Icons.history),
              onPressed: _showHistory,
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // Six rows of keys share what is left after the display.
          final keyHeight =
              ((constraints.maxHeight - 120) / 6 - 8).clamp(36.0, 72.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _input.isEmpty ? '0' : _input,
                          key: const Key('calculator-input'),
                          style: text.displaySmall,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 32,
                        child: showPreview
                            ? Text(
                                '= ${formatCalculatorResult(result)}',
                                key: const Key('calculator-result'),
                                style: text.titleLarge
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    for (final row in keys)
                      Row(
                        children: [
                          for (final key in row)
                            Expanded(child: _key(context, key, keyHeight)),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              height: keyHeight,
                              child: OutlinedButton.icon(
                                onPressed: result != null && result > 0
                                    ? _addExpense
                                    : null,
                                icon: const Icon(Icons.add),
                                label: const FittedBox(
                                    child: Text('Add as expense')),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              height: keyHeight,
                              child: FilledButton(
                                onPressed: () => _press('='),
                                child: Text('=',
                                    style: text.headlineSmall
                                        ?.copyWith(color: scheme.onPrimary)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _key(BuildContext context, String key, double height) {
    final scheme = Theme.of(context).colorScheme;
    final isOperator = '÷×−+()%'.contains(key);
    final isClear = key == 'C';
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: height,
        child: Material(
          color: isClear
              ? scheme.errorContainer
              : isOperator
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _press(key),
            onLongPress: key == '⌫' ? () => _press('C') : null,
            child: Center(
              child: key == '⌫'
                  ? Icon(Icons.backspace_outlined,
                      semanticLabel: 'Delete', color: scheme.onSurface)
                  : Text(key,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: isClear
                                  ? scheme.onErrorContainer
                                  : isOperator
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurface)),
            ),
          ),
        ),
      ),
    );
  }

  void _showHistory() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          children: [
            for (final item in _history)
              ListTile(
                title: Text(item.result,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
                subtitle: Text(item.expression),
                onTap: () {
                  setState(() => _input = item.result);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      );
}
