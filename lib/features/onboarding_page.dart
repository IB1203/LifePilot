import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/recurrence.dart';
import '../services/reminder_coordinator.dart';
import '../ui/widgets.dart';
import 'lock_screen.dart';

/// First-run setup. Every step is optional; anything entered becomes real
/// records (accounts, a recurring salary rule, budgets) that can be edited
/// later. Nothing is created for steps the user skips.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pages = PageController();
  int _page = 0;
  String _symbol = '₹';
  int _accent = accentChoices.first;
  final _salary = TextEditingController();
  int _salaryDay = 1;
  final Map<String, TextEditingController> _budgets = {
    for (final category in ['Food', 'Transport', 'Shopping', 'Bills'])
      category: TextEditingController(),
  };
  final Set<AccountKind> _accounts = {AccountKind.cash, AccountKind.bank};
  bool _finishing = false;

  static const _steps = 5;

  @override
  void dispose() {
    _pages.dispose();
    _salary.dispose();
    for (final controller in _budgets.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _next() {
    if (_page == _steps - 1) {
      _finish();
      return;
    }
    FocusScope.of(context).unfocus();
    _pages.nextPage(duration: motion(context, 280), curve: Curves.easeOutCubic);
  }

  Future<void> _finish({bool skipAll = false}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final store = widget.store;
    if (!skipAll) {
      for (final kind in _accounts) {
        await store.addAccount(kind.label, kind);
      }
      final salary = parseRupeesToPaise(_salary.text);
      if (salary != null) {
        final now = store.now();
        var first = DateTime(now.year, now.month, _salaryDay);
        if (first.isBefore(dateOnly(now))) {
          first = addMonths(first, 1, anchorDay: _salaryDay);
        }
        await store.addRecurring(
          kind: EntryKind.income,
          amountPaise: salary,
          category: 'Salary',
          title: 'Salary',
          recurrence: const Recurrence(Repeat.monthly),
          firstDate: first,
          paymentMethod: 'Bank transfer',
        );
      }
      for (final MapEntry(key: category, value: controller)
          in _budgets.entries) {
        final limit = parseRupeesToPaise(controller.text);
        if (limit != null) await store.setBudget(category, limit);
      }
    }
    await store.updateSettings(store.settings.copyWith(
      onboarded: true,
      currencySymbol: skipAll ? null : _symbol,
      accentColor: skipAll ? null : _accent,
      salaryDay: parseRupeesToPaise(_salary.text) == null ? null : _salaryDay,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  for (var i = 0; i < _steps; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: motion(context, 200),
                        height: 4,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: i <= _page
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: _finishing ? null : () => _finish(skipAll: true),
                    child: const Text('Skip setup'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _welcome(context),
                  _display(context),
                  _money(context),
                  _accountsStep(context),
                  _security(context),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: () => _pages.previousPage(
                          duration: motion(context, 280),
                          curve: Curves.easeOutCubic),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  Flexible(
                    child: FilledButton(
                      onPressed: _finishing ? null : _next,
                      child: Text(
                        _page == _steps - 1
                            ? (_finishing ? 'Setting up…' : 'Get started')
                            : 'Next',
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Widget _step(BuildContext context, IconData icon, String title,
          String subtitle, List<Widget> children) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          ...children,
        ],
      );

  Widget _welcome(BuildContext context) => _step(
        context,
        Icons.route_outlined,
        'Welcome to LifePilot',
        'Track money, plan tasks, build habits and manage your time — all on this phone. Nothing is sent to a server.',
        const [
          ListTile(
            leading: Icon(Icons.account_balance_wallet_outlined),
            title: Text('Budgets, bills, goals and reports'),
          ),
          ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('Tasks, reminders, habits and focus timer'),
          ),
          ListTile(
            leading: Icon(Icons.auto_awesome_outlined),
            title: Text('An offline assistant that asks before saving'),
          ),
          SizedBox(height: 8),
          Text(
              'This takes about a minute. Every step can be skipped and changed later.'),
        ],
      );

  Widget _display(BuildContext context) => _step(
        context,
        Icons.palette_outlined,
        'Make it yours',
        'Choose how amounts are shown and an accent colour.',
        [
          Text('Currency symbol',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final symbol in const ['₹', 'Rs ', '\$', '€', '£', 'AED '])
                ChoiceChip(
                  label: Text(symbol.trim()),
                  selected: _symbol == symbol,
                  onSelected: (_) => setState(() => _symbol = symbol),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Accent colour', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          AccentPicker(
            selected: _accent,
            onSelected: (color) => setState(() => _accent = color),
          ),
        ],
      );

  Widget _money(BuildContext context) => _step(
        context,
        Icons.payments_outlined,
        'Salary and budgets',
        'Your salary becomes a monthly reminder to record it — LifePilot never adds income on its own. Leave anything blank to skip it.',
        [
          TextField(
            controller: _salary,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
            ],
            decoration: InputDecoration(
              labelText: 'Monthly salary (optional)',
              prefixText: '$_symbol ',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _salaryDay,
            decoration: const InputDecoration(labelText: 'Usually paid on'),
            items: [
              for (var day = 1; day <= 31; day++)
                DropdownMenuItem(
                    value: day, child: Text('Day $day of the month')),
            ],
            onChanged: (value) => setState(() => _salaryDay = value ?? 1),
          ),
          const SizedBox(height: 20),
          Text('Monthly budgets (optional)',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final MapEntry(key: category, value: controller)
              in _budgets.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
                ],
                decoration: InputDecoration(
                  labelText: category,
                  prefixText: '$_symbol ',
                ),
              ),
            ),
        ],
      );

  Widget _accountsStep(BuildContext context) => _step(
        context,
        Icons.account_balance_outlined,
        'Where does your money go?',
        'Pick the wallets you use. You can tag each expense with one to see recorded balances. Opening balances can be set later.',
        [
          for (final kind
              in AccountKind.values.where((kind) => kind != AccountKind.other))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _accounts.contains(kind),
              title: Text(kind.label),
              onChanged: (on) => setState(() =>
                  on == true ? _accounts.add(kind) : _accounts.remove(kind)),
            ),
        ],
      );

  Widget _security(BuildContext context) => _step(
        context,
        Icons.shield_outlined,
        'Reminders and privacy',
        'Allow notifications so reminders, bills and timers can alert you. You can also protect the app with a PIN.',
        [
          OutlinedButton.icon(
            onPressed: () async {
              final coordinator = ReminderScope.maybeOf(context);
              final granted = await coordinator?.ensurePermission() ?? false;
              if (!context.mounted) return;
              showMessage(
                  context,
                  granted
                      ? 'Notifications allowed.'
                      : 'Notifications were not allowed. You can change this in More › Notifications.');
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Allow notifications'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.store.settings.lockEnabled
                ? null
                : () async {
                    final set = await showSetPinDialog(context, widget.store);
                    if (set && context.mounted) {
                      // The PIN was just chosen; do not lock the user out now.
                      AppLockScope.maybeOf(context)?.unlock();
                      setState(() {});
                    }
                  },
            icon: const Icon(Icons.pin_outlined),
            label: Text(widget.store.settings.lockEnabled
                ? 'PIN set'
                : 'Set an app PIN'),
          ),
        ],
      );
}

class AccentPicker extends StatelessWidget {
  const AccentPicker(
      {required this.selected, required this.onSelected, super.key});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final color in accentChoices)
            Semantics(
              label: 'Accent colour',
              selected: color == selected,
              button: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onSelected(color),
                child: AnimatedContainer(
                  duration: motion(context, 150),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: color == selected ? 3 : 0,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  child: color == selected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              ),
            ),
        ],
      );
}
