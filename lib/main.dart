import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/clock_ops.dart';
import 'core/local_store.dart';
import 'core/models.dart';
import 'core/secure.dart';
import 'features/assistant_page.dart';
import 'features/clock_page.dart';
import 'features/dashboard_page.dart';
import 'features/finance_page.dart';
import 'features/lock_screen.dart';
import 'features/more_page.dart';
import 'features/onboarding_page.dart';
import 'features/tasks_page.dart';
import 'services/device_security.dart';
import 'services/notification_service.dart';
import 'services/reminder_coordinator.dart';
import 'ui/forms.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds keep nothing in the system log; error messages can carry
  // record details.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  DataCipher? cipher;
  try {
    cipher = await loadDeviceCipher();
  } on Object {
    // Without the key an encrypted file stays untouched (see load) and a
    // plain one keeps working unencrypted; More › App lock shows the state.
    cipher = null;
  }
  late final LifePilotStore store;
  try {
    store = await LifePilotStore.load(cipher: cipher);
  } on Object {
    store = LifePilotStore.inMemory(
      error: 'Local storage is unavailable. Changes will not persist.',
    );
  }
  final coordinator = ReminderCoordinator(
    store,
    LocalReminderScheduler.isSupported
        ? LocalReminderScheduler()
        : NoopReminderScheduler(),
  );
  runApp(LifePilotApp(store: store, coordinator: coordinator));
  // Notification setup runs after the first frame so it does not delay startup.
  WidgetsBinding.instance.addPostFrameCallback((_) => coordinator.start());
}

class LifePilotApp extends StatefulWidget {
  const LifePilotApp({this.store, this.coordinator, super.key});

  final LifePilotStore? store;
  final ReminderCoordinator? coordinator;

  @override
  State<LifePilotApp> createState() => _LifePilotAppState();
}

class _LifePilotAppState extends State<LifePilotApp> {
  late final LifePilotStore _store = widget.store ?? LifePilotStore.inMemory();
  late final AppLockController _lock = AppLockController(_store);

  @override
  void initState() {
    super.initState();
    _store.addListener(_applyScreenSecurity);
    _applyScreenSecurity();
  }

  void _applyScreenSecurity() => setSecureScreen(_store.settings.secureScreen);

  @override
  void dispose() {
    _store.removeListener(_applyScreenSecurity);
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds only the app frame for theme and onboarding changes; the
    // shell below keeps its state because it is the same widget type.
    final app = ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final settings = _store.settings;
        final seed = Color(settings.accentColor);
        return MaterialApp(
          title: 'LifePilot AI',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, seed: seed),
          darkTheme: buildTheme(Brightness.dark, seed: seed),
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          home: settings.onboarded
              ? AppLockGate(
                  child:
                      AppShell(store: _store, coordinator: widget.coordinator),
                )
              : OnboardingPage(store: _store),
        );
      },
    );
    final scoped = AppLockScope(controller: _lock, child: app);
    final coordinator = widget.coordinator;
    return coordinator == null
        ? scoped
        : ReminderScope(coordinator: coordinator, child: scoped);
  }
}

class AppShell extends StatefulWidget {
  const AppShell({required this.store, this.coordinator, super.key});

  final LifePilotStore store;
  final ReminderCoordinator? coordinator;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _titles = ['Home', 'Finance', 'Tasks', 'Assistant', 'More'];
  static const _icons = [
    (Icons.home_outlined, Icons.home),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
    (Icons.check_circle_outline, Icons.check_circle),
    (Icons.auto_awesome_outlined, Icons.auto_awesome),
    (Icons.grid_view_outlined, Icons.grid_view),
  ];

  @override
  void initState() {
    super.initState();
    widget.coordinator?.navigation.addListener(_onNavigationRequest);
    widget.coordinator?.messages.addListener(_onMessage);
  }

  @override
  void dispose() {
    widget.coordinator?.navigation.removeListener(_onNavigationRequest);
    widget.coordinator?.messages.removeListener(_onMessage);
    super.dispose();
  }

  void _onNavigationRequest() {
    final target = widget.coordinator?.navigation.value;
    if (target == null || !mounted) return;
    widget.coordinator!.navigation.value = null;
    switch (target) {
      case 'tasks':
        _navigate(2);
      case 'finance':
        _navigate(1);
      default:
        _openClock(ClockTab.timer);
    }
  }

  void _onMessage() {
    final text = widget.coordinator?.messages.value;
    if (text == null || !mounted) return;
    widget.coordinator!.messages.value = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.route_outlined,
                      size: 19, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(_selectedIndex == 0
                    ? 'LifePilot'
                    : _titles[_selectedIndex]),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Reminders',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => ReminderHistoryPage(store: widget.store)),
                ),
                icon: const Icon(Icons.notifications_none),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => _navigate(4),
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              DashboardPage(
                store: widget.store,
                onNavigate: _navigate,
                onOpenClock: () => _openClock(ClockTab.clock),
                onQuickAction: _quickAction,
              ),
              FinancePage(store: widget.store),
              TasksPage(store: widget.store),
              AssistantPage(store: widget.store),
              MorePage(store: widget.store, onOpenClock: _openClock),
            ],
          ),
          floatingActionButton: _selectedIndex == 3
              ? null
              : FloatingActionButton.extended(
                  onPressed: _showQuickAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _navigate,
            destinations: [
              for (var index = 0; index < _titles.length; index++)
                NavigationDestination(
                  icon: Icon(_icons[index].$1),
                  selectedIcon: Icon(_icons[index].$2),
                  label: _titles[index],
                ),
            ],
          ),
        ),
      );

  Future<void> _navigate(int index) async {
    // With a finance-only lock, ask for the PIN before showing Finance.
    if (index == 1 && !await ensureFinanceUnlocked(context)) return;
    if (mounted) setState(() => _selectedIndex = index);
  }

  void _openClock(ClockTab tab) => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ClockPage(store: widget.store, initialTab: tab),
        ),
      );

  void _quickAction(String id) {
    final store = widget.store;
    switch (id) {
      case 'expense':
        showEntryForm(context, store, kind: EntryKind.expense);
      case 'income':
        showEntryForm(context, store, kind: EntryKind.income);
      case 'task':
        showTaskForm(context, store);
      case 'reminder':
        showTaskForm(context, store, reminder: true);
      case 'note':
        showNoteForm(context, store);
      case 'focus':
        if (!store.clock.focus.isActive) {
          store.focusStart(kind: FocusKind.focus);
        }
        _openClock(ClockTab.focus);
      case 'bill':
        showBillForm(context, store);
    }
  }

  static const _quickActions = [
    ('expense', Icons.north_east, 'Expense', 'Record money spent'),
    ('income', Icons.south_west, 'Income', 'Record money received'),
    ('task', Icons.add_task, 'Task', 'Add something to your plan'),
    ('reminder', Icons.alarm_add, 'Reminder', 'Get notified at a time'),
    ('bill', Icons.receipt_outlined, 'Bill', 'Track a recurring payment'),
    ('note', Icons.sticky_note_2_outlined, 'Note', 'Jot something down'),
    ('focus', Icons.self_improvement, 'Focus session', 'Start a focus timer'),
  ];

  Future<void> _showQuickAdd() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text('Quick add',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
              ),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.9,
                children: [
                  for (final (id, icon, title, detail) in _quickActions)
                    Tooltip(
                      message: detail,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(sheetContext, id),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Theme.of(sheetContext)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(icon,
                                  color: Theme.of(sheetContext)
                                      .colorScheme
                                      .primary),
                            ),
                            const SizedBox(height: 6),
                            Text(title,
                                textAlign: TextAlign.center,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .labelMedium),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) _quickAction(picked);
  }
}
