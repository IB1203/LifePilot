import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'debts.dart';
import 'finance_calc.dart';
import 'formatters.dart';
import 'investments.dart';
import 'models.dart';
import 'personal.dart' show accountBalance;
import 'recurrence.dart';
import 'recurring_detect.dart';
import 'reminder_plan.dart';
import 'secure.dart';
import 'sms_import.dart';
import 'spending_habits.dart';
import 'statement_import.dart';
import 'tax_rules.dart';
import 'validation/finance_validator.dart';
import 'vault.dart';
import 'upi.dart';
import 'repositories/account_repository.dart';
import 'repositories/bill_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/debt_repository.dart';
import 'repositories/entry_repository.dart';
import 'repositories/investment_repository.dart';
import 'repositories/life_pilot_budget_repository.dart';
import 'repositories/life_pilot_debt_repository.dart';
import 'repositories/life_pilot_entry_repository.dart';
import 'repositories/life_pilot_investment_repository.dart';
import 'repositories/life_pilot_account_repository.dart';
import 'repositories/life_pilot_bill_repository.dart';

/// Last four digits found in a masked account number, e.g. "XXXX 1234".
String _trailingDigits(String? value) {
  if (value == null) return '';
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
}

/// The single source of truth for on-device records. Data is kept in memory
/// and written to one versioned JSON file in the app's private support
/// directory after every change. When a [DataCipher] is available the file
/// is encrypted with the device key.
class LifePilotStore extends ChangeNotifier {
  LifePilotStore._(this._dataFile,
      {DateTime Function()? clock, DataCipher? cipher})
      : _clock = clock ?? DateTime.now,
        _cipher = cipher;

  LifePilotStore.inMemory({String? error, DateTime Function()? clock})
      : _dataFile = null,
        _clock = clock ?? DateTime.now,
        _storageDisabled = error != null,
        storageError = error;

  /// File name kept from version 1 so existing installs find their data.
  static const _storageKey = 'lifepilot.local.v1';
  static const currentVersion = 3;
  static const defaultCategories = <String>[
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Health',
    'Home',
    'Education',
    'Entertainment',
    'Travel',
    'Salary',
    'Freelance',
    'Business',
    'Interest',
    'Gifts',
    'Refunds',
    'Loans',
    'Other',
  ];

  final File? _dataFile;
  final DateTime Function() _clock;
  DataCipher? _cipher;
  bool _storageDisabled = false;
  int _idCounter = 0;
  final List<LedgerEntry> entries = [];
  final List<SpendingBudget> budgets = [];
  final List<SavingsGoal> goals = [];
  final List<LocalTask> tasks = [];
  final List<PaymentHandoff> handoffs = [];
  final List<Bill> bills = [];
  final List<FocusSession> focusSessions = [];
  final List<Alarm> alarms = [];
  final List<QuickNote> notes = [];
  final List<ReminderLogEntry> reminderLog = [];
  final List<String> categories = [...defaultCategories];
  final List<Account> accounts = [];
  final List<AccountTransfer> transfers = [];
  final List<RecurringEntry> recurring = [];
  final List<PendingEntry> pending = [];
  final List<Habit> habits = [];
  final List<Payee> payees = [];
  final List<SuspiciousSms> suspiciousSms = [];
  final List<UnrecognizedSms> unrecognizedSms = [];
  final List<CategoryRule> categoryRules = [];

  /// Saved statement column layouts, per bank.
  final List<StatementMapping> statementMappings = [];

  /// Bank balance keys the user chose to ignore instead of adjusting to.
  final Set<String> ignoredBalanceKeys = {};

  /// Fingerprints of SMS messages and statement rows already turned into
  /// drafts or dismissed.
  final Set<String> seenSms = {};

  /// Latest balance or card limit each bank SMS reported, by account.
  final List<BankBalance> bankBalances = [];

  /// Running balance per account id: seeded from the opening balance, set
  /// from a bank SMS, and adjusted by every linked entry and transfer. When
  /// absent for an account, the balance is computed from opening plus
  /// recorded entries instead.
  final Map<String, int> _accountBalances = {};

  /// Recurring suggestions the user said are not recurring.
  final Set<String> dismissedSuggestions = {};

  /// Loans, card dues, and money borrowed or lent.
  final List<Debt> debts = [];

  /// Investments with values the user enters.
  final List<Investment> investments = [];

  /// Tax and GST rules the user imported or edited, as JSON by financial
  /// year. They replace the built-in rules for that year.
  final Map<String, String> taxRuleOverrides = {};

  /// Trips with their own budget.
  final List<Trip> trips = [];

  /// Documents and warranties; files are stored encrypted, outside the
  /// records file.
  final List<VaultItem> vault = [];
  AppSettings settings = const AppSettings();
  ClockState clock = const ClockState();
  String? storageError;

  /// Schema version the data was migrated from during this launch, if any.
  int? migratedFrom;

  /// Whether a plain records file was encrypted during this launch.
  bool encryptionUpgraded = false;

  /// Whether records are written encrypted with the device key.
  bool get encryptedAtRest => _dataFile != null && _cipher != null;

  /// Cipher for other private files, such as receipt photos.
  DataCipher? get dataCipher => _cipher;
  Future<void> _writeQueue = Future<void>.value();

  DateTime now() => _clock();

  /// Loads records from [directory] (the app's private support folder by
  /// default). With a [cipher], an existing plain file is encrypted in place
  /// once the encrypted copy has been checked; without one, an encrypted
  /// file is left untouched and the store does not save.
  static Future<LifePilotStore> load({
    Directory? directory,
    DateTime Function()? clock,
    DataCipher? cipher,
  }) async {
    LifePilotStore? store;
    try {
      final folder = directory ?? await getApplicationSupportDirectory();
      store = LifePilotStore._(File('${folder.path}/$_storageKey.json'),
          clock: clock, cipher: cipher);
      final file = store._dataFile!;
      if (!await file.exists()) {
        // A fresh install: show first-run setup.
        store.settings = store.settings.copyWith(onboarded: false);
        return store;
      }
      var raw = await file.readAsString();
      if (raw.trim().isEmpty) return store;
      final sealed = DataCipher.isSealedText(raw);
      if (sealed) {
        if (cipher == null) {
          store._storageDisabled = true;
          store.storageError =
              'Your records are encrypted with this phone\'s security key, which could not be loaded. They have been left untouched.';
          return store;
        }
        raw = await cipher.openText(raw);
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final version = _checkFormat(decoded);
      store._apply(decoded);
      if (version < currentVersion) {
        try {
          // Keep the original file before rewriting it in the new format.
          final backup =
              File('${folder.path}/$_storageKey.v$version.backup.json');
          if (!await backup.exists()) {
            await backup.writeAsString(
                cipher == null ? raw : await cipher.sealText(raw),
                flush: true);
          }
        } on Object {
          // Without a backup, do not overwrite the original file.
          store._storageDisabled = true;
          store.storageError =
              'Your data was read, but it could not be upgraded safely. Changes will not be saved.';
          return store;
        }
        store.migratedFrom = version;
      }
      if (cipher != null && !sealed) {
        await store._encryptPlainFiles(folder);
      } else if (version < currentVersion) {
        await store._changed();
      }
    } catch (_) {
      store ??= LifePilotStore.inMemory();
      store._resetCollections();
      store._storageDisabled = true;
      store.storageError =
          'Saved data could not be read. It has been left untouched.';
    }
    MoneyFormat.symbol = store.settings.currencySymbol;
    MoneyFormat.hidden = store.settings.hideAmounts;
    return store;
  }

  /// Replaces the plain records file, and plain copies kept from schema
  /// upgrades, with encrypted versions. Each encrypted file is decrypted and
  /// compared before it replaces the original. If that fails, records keep
  /// being saved unencrypted rather than risk losing them.
  Future<void> _encryptPlainFiles(Directory folder) async {
    final cipher = _cipher!;
    try {
      await _writeChecked(_dataFile!, jsonEncode(_toJson()), cipher);
      await for (final item in folder.list()) {
        final name = item.uri.pathSegments.last;
        if (item is! File ||
            !name.startsWith(_storageKey) ||
            !name.endsWith('.backup.json')) {
          continue;
        }
        final text = await item.readAsString();
        if (!DataCipher.isSealedText(text)) {
          await _writeChecked(item, text, cipher);
        }
      }
      encryptionUpgraded = true;
    } on Object {
      _cipher = null;
      await _changed();
    }
  }

  static Future<void> _writeChecked(
      File file, String clear, DataCipher cipher) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(await cipher.sealText(clear), flush: true);
    if (await cipher.openText(await temporary.readAsString()) != clear) {
      await temporary.delete();
      throw StateError('The encrypted copy did not match.');
    }
    await temporary.rename(file.path);
  }

  static int _checkFormat(Map<String, dynamic> root) {
    final version = root['version'];
    if (root['format'] != 'lifepilot-backup' ||
        version is! int ||
        version < 1 ||
        version > currentVersion) {
      throw const FormatException('Unsupported LifePilot data version.');
    }
    return version;
  }

  static List<T> _readList<T>(
    Map<String, dynamic> root,
    String key,
    T Function(Map<String, dynamic>) decode,
  ) {
    final value = root[key];
    if (value is! List) return <T>[];
    return value
        .whereType<Map<String, dynamic>>()
        .map(decode)
        .toList(growable: true);
  }

  /// Decodes everything first, then replaces the current data, so a
  /// malformed record leaves the existing data untouched.
  void _apply(Map<String, dynamic> root) {
    final decodedEntries = _readList(root, 'entries', LedgerEntry.fromJson);
    final decodedBudgets = _readList(root, 'budgets', SpendingBudget.fromJson);
    final decodedGoals = _readList(root, 'goals', SavingsGoal.fromJson);
    final decodedTasks = _readList(root, 'tasks', LocalTask.fromJson);
    final decodedHandoffs =
        _readList(root, 'handoffs', PaymentHandoff.fromJson);
    final decodedBills = _readList(root, 'bills', Bill.fromJson);
    final decodedSessions =
        _readList(root, 'focusSessions', FocusSession.fromJson);
    final decodedAlarms = _readList(root, 'alarms', Alarm.fromJson);
    final decodedNotes = _readList(root, 'notes', QuickNote.fromJson);
    final decodedLog =
        _readList(root, 'reminderLog', ReminderLogEntry.fromJson);
    final decodedSettings = AppSettings.fromJson(root['settings']);
    final decodedClock = ClockState.fromJson(root['clock']);
    final decodedAccounts = _readList(root, 'accounts', Account.fromJson);
    final decodedTransfers =
        _readList(root, 'transfers', AccountTransfer.fromJson);
    final decodedRecurring =
        _readList(root, 'recurring', RecurringEntry.fromJson);
    final decodedPending = _readList(root, 'pending', PendingEntry.fromJson);
    final decodedHabits = _readList(root, 'habits', Habit.fromJson);
    final decodedPayees = _readList(root, 'payees', Payee.fromJson);
    final decodedSuspicious =
        _readList(root, 'suspiciousSms', SuspiciousSms.fromJson);
    final decodedUnrecognized =
        _readList(root, 'unrecognizedSms', UnrecognizedSms.fromJson);
    final decodedRules =
        _readList(root, 'categoryRules', CategoryRule.fromJson);
    final decodedMappings =
        _readList(root, 'statementMappings', StatementMapping.fromJson);
    final storedIgnored = root['ignoredBalanceKeys'];
    final decodedIgnored = storedIgnored is List
        ? storedIgnored.whereType<String>().toSet()
        : <String>{};
    final storedSms = root['seenSms'];
    final decodedSms =
        storedSms is List ? storedSms.whereType<String>().toSet() : <String>{};
    final decodedBalances =
        _readList(root, 'bankBalances', BankBalance.fromJson);
    final storedRunning = root['accountBalances'];
    final decodedRunning = <String, int>{
      if (storedRunning is Map)
        for (final item in storedRunning.entries)
          if (item.key is String && item.value is int)
            item.key as String: item.value as int,
    };
    final decodedDebts = _readList(root, 'debts', Debt.fromJson);
    final decodedInvestments =
        _readList(root, 'investments', Investment.fromJson);
    final decodedTrips = _readList(root, 'trips', Trip.fromJson);
    final decodedVault = _readList(root, 'vault', VaultItem.fromJson);
    final storedRules = root['taxRules'];
    final decodedTaxRules = <String, String>{
      if (storedRules is Map)
        for (final entry in storedRules.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
    };
    // A stored file that no longer validates is dropped, not trusted.
    decodedTaxRules.removeWhere((_, source) {
      try {
        parseTaxRules(source);
        return false;
      } on FormatException {
        return true;
      }
    });
    final storedDismissed = root['dismissedSuggestions'];
    final decodedDismissed = storedDismissed is List
        ? storedDismissed.whereType<String>().toSet()
        : <String>{};
    final storedCategories = root['categories'];
    final decodedCategories = storedCategories is List
        ? storedCategories.whereType<String>().toList()
        : <String>[];
    for (final category in defaultCategories) {
      if (!decodedCategories.contains(category)) {
        decodedCategories.add(category);
      }
    }

    _resetCollections();
    entries.addAll(decodedEntries);
    budgets.addAll(decodedBudgets);
    goals.addAll(decodedGoals);
    tasks.addAll(decodedTasks);
    handoffs.addAll(decodedHandoffs);
    bills.addAll(decodedBills);
    focusSessions.addAll(decodedSessions);
    alarms.addAll(decodedAlarms);
    notes.addAll(decodedNotes);
    reminderLog.addAll(decodedLog);
    categories
      ..clear()
      ..addAll(decodedCategories);
    settings = decodedSettings;
    clock = decodedClock;
    accounts.addAll(decodedAccounts);
    transfers.addAll(decodedTransfers);
    recurring.addAll(decodedRecurring);
    pending.addAll(decodedPending);
    habits.addAll(decodedHabits);
    payees.addAll(decodedPayees);
    suspiciousSms.addAll(decodedSuspicious);
    unrecognizedSms.addAll(decodedUnrecognized);
    categoryRules.addAll(decodedRules);
    statementMappings.addAll(decodedMappings);
    ignoredBalanceKeys.addAll(decodedIgnored);
    seenSms.addAll(decodedSms);
    bankBalances.addAll(decodedBalances);
    _accountBalances
      ..clear()
      ..addAll(decodedRunning);
    debts.addAll(decodedDebts);
    investments.addAll(decodedInvestments);
    taxRuleOverrides.addAll(decodedTaxRules);
    trips.addAll(decodedTrips);
    vault.addAll(decodedVault);
    dismissedSuggestions.addAll(decodedDismissed);
    MoneyFormat.symbol = settings.currencySymbol;
    MoneyFormat.hidden = settings.hideAmounts;
  }

  void _resetCollections() {
    entries.clear();
    budgets.clear();
    goals.clear();
    tasks.clear();
    handoffs.clear();
    bills.clear();
    focusSessions.clear();
    alarms.clear();
    notes.clear();
    reminderLog.clear();
    accounts.clear();
    transfers.clear();
    recurring.clear();
    pending.clear();
    habits.clear();
    payees.clear();
    suspiciousSms.clear();
    unrecognizedSms.clear();
    categoryRules.clear();
    statementMappings.clear();
    ignoredBalanceKeys.clear();
    seenSms.clear();
    bankBalances.clear();
    _accountBalances.clear();
    dismissedSuggestions.clear();
    debts.clear();
    investments.clear();
    taxRuleOverrides.clear();
    trips.clear();
    vault.clear();
    categories
      ..clear()
      ..addAll(defaultCategories);
  }

  // ---------------------------------------------------------------------------
  // Derived values

  PeriodSummary get thisMonth => summarize(entries, monthRange(now()));

  int get monthIncome => thisMonth.income;

  int get monthExpenses => thisMonth.expenses;

  /// Recorded income minus recorded expenses this month. Not net worth.
  int get cashFlow => thisMonth.netCashFlow;

  List<LedgerEntry> get recentEntries {
    final sorted = [...entries]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return sorted;
  }

  List<LocalTask> get openTasks {
    final sorted = tasks.where((task) => !task.isDone).toList()
      ..sort((a, b) {
        if (a.dueAt == null && b.dueAt == null) {
          return a.createdAt.compareTo(b.createdAt);
        }
        if (a.dueAt == null) return 1;
        if (b.dueAt == null) return -1;
        return a.dueAt!.compareTo(b.dueAt!);
      });
    return sorted;
  }

  int spentInCategory(String category) => sumEntries(entries,
      kind: EntryKind.expense, range: monthRange(now()), category: category);

  List<String> get projects => {
        for (final task in tasks)
          if (task.project.trim().isNotEmpty) task.project.trim(),
      }.toList()
        ..sort();

  /// Notifications that should currently be scheduled.
  List<PlannedNotification> notificationPlan() => buildNotificationPlan(
        tasks: tasks,
        bills: bills,
        alarms: alarms,
        habits: habits,
        clock: clock,
        now: now(),
        use24h: settings.use24HourClock,
        extra: [
          ...maturityReminders(investments, now()),
          ...expiryReminders(vault, now()),
          ..._lendingNotifications(),
        ],
      );

  List<PlannedNotification> _lendingNotifications() {
    final current = now();
    final result = <PlannedNotification>[];
    for (final debt in debts) {
      if (!debt.owedToMe || debt.closed || debt.dueAt == null) continue;
      final outstanding = debtStatus(debt, asOf: current).outstandingPaise;
      if (outstanding <= 0) continue;
      final due = DateTime(debt.dueAt!.year, debt.dueAt!.month, debt.dueAt!.day,
          defaultReminderHour);
      final overdue = !due.isAfter(current);
      final at = overdue
          ? DateTime(current.year, current.month, current.day + 1,
              defaultReminderHour)
          : due;
      result.add(PlannedNotification(
        key: 'lend:${debt.id}:${debt.dueAt!.toIso8601String()}',
        at: at,
        title: overdue ? 'Money still to get back' : 'Money to get back',
        body:
            '${debt.name}: ${formatMoney(outstanding, reveal: true)}${overdue ? ' is overdue' : ' is due'}'
            '${debt.counterparty.isEmpty ? '' : ' from ${debt.counterparty}'}.',
        channel: ReminderChannel.bills,
        payload: 'debt:${debt.id}',
      ));
    }
    return result;
  }

  LocalTask? taskById(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Bill? billById(String id) {
    for (final bill in bills) {
      if (bill.id == id) return bill;
    }
    return null;
  }

  Debt? debtById(String id) {
    for (final debt in debts) {
      if (debt.id == id) return debt;
    }
    return null;
  }

  BillRepository get billRepository => _billRepository ??=
      LifePilotBillRepository(this);
  BillRepository? _billRepository;

  AccountRepository get accountRepository => _accountRepository ??=
      LifePilotAccountRepository(this);
  AccountRepository? _accountRepository;

  DebtRepository get debtRepository => _debtRepository ??=
      LifePilotDebtRepository(this);
  DebtRepository? _debtRepository;

  EntryRepository get entryRepository => _entryRepository ??=
      LifePilotEntryRepository(this);
  EntryRepository? _entryRepository;

  BudgetRepository get budgetRepository => _budgetRepository ??=
      LifePilotBudgetRepository(this);
  BudgetRepository? _budgetRepository;

  InvestmentRepository get investmentRepository => _investmentRepository ??=
      LifePilotInvestmentRepository(this);
  InvestmentRepository? _investmentRepository;

  // ---------------------------------------------------------------------------
  // Transactions

  Future<LedgerEntry> addEntry({
    required EntryKind kind,
    required int amountPaise,
    required String category,
    required String title,
    required DateTime occurredAt,
    String paymentMethod = 'Other',
    String note = '',
    String merchant = '',
    String subcategory = '',
    String? billId,
    String? accountId,
    String? receiptPath,
    String? source,
  }) async {
    final entry = LedgerEntry(
      subcategory: subcategory.trim(),
      id: _newId(),
      kind: kind,
      amountPaise: amountPaise,
      category: category,
      title: title.trim(),
      occurredAt: occurredAt,
      paymentMethod: paymentMethod,
      note: note.trim(),
      merchant: merchant.trim(),
      billId: billId,
      accountId: accountId,
      receiptPath: receiptPath,
      source: source,
    );
    entries.add(entry);
    await _changed();
    _adjustAccountBalance(accountId, amountPaise,
        isIncome: kind == EntryKind.income);
    return entry;
  }

  /// Adds an already-constructed [entry] (with a pre-existing [id]) and
  /// adjusts the linked account balance. Used by SMS and statement imports
  /// so that running balances stay in step with imported transactions.
  Future<void> addImportedEntry(LedgerEntry entry) async {
    entries.add(entry);
    await _changed();
    _adjustAccountBalance(entry.accountId, entry.amountPaise,
        isIncome: entry.isIncome);
  }

  /// Subcategories used before in [category], most used first.
  List<String> subcategoriesOf(String category) {
    final counts = <String, int>{};
    for (final entry in entries) {
      if (entry.category != category || entry.subcategory.isEmpty) continue;
      counts.update(entry.subcategory, (value) => value + 1, ifAbsent: () => 1);
    }
    return (counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!)));
  }

  Future<void> updateEntry(LedgerEntry updated) async {
    final index = entries.indexWhere((entry) => entry.id == updated.id);
    if (index < 0) throw StateError('That transaction no longer exists.');
    final old = entries[index];
    // Move any linked account balance from the old values to the new ones.
    _adjustAccountBalance(old.accountId, old.amountPaise,
        isIncome: !old.isIncome);
    entries[index] = updated;
    _adjustAccountBalance(updated.accountId, updated.amountPaise,
        isIncome: updated.isIncome);
    await _changed();
  }

  Future<void> deleteEntry(String id) async {
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final old = entries.removeAt(index);
    _adjustAccountBalance(old.accountId, old.amountPaise,
        isIncome: !old.isIncome);
    await _changed();
  }

  /// Applies the same correction to many past entries, then recalculates
  /// account balances. Returns how many entries changed.
  Future<int> bulkCorrectEntries({
    required bool Function(LedgerEntry entry) where,
    EntryKind? kind,
    String? category,
    String? paymentMethod,
    String? accountId,
    bool clearAccount = false,
  }) async {
    var changed = 0;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (!where(entry)) continue;
      entries[i] = entry.copyWith(
        kind: kind,
        category: category,
        paymentMethod: paymentMethod,
        accountId: accountId,
        clearAccount: clearAccount,
      );
      changed++;
    }
    if (changed > 0) {
      _recalculateBalances();
      await _changed();
    }
    return changed;
  }

  /// Merges [duplicateIds] into [keepId], combining their notes, and
  /// recalculates balances. Returns the kept entry, or null if it is gone.
  Future<LedgerEntry?> mergeEntries(
      String keepId, Iterable<String> duplicateIds) async {
    final keepIndex = entries.indexWhere((entry) => entry.id == keepId);
    if (keepIndex < 0) return null;
    var keep = entries[keepIndex];
    final remove = duplicateIds.toSet()..remove(keepId);
    final notes = <String>[
      if (keep.note.trim().isNotEmpty) keep.note.trim(),
    ];
    for (final entry in entries) {
      if (!remove.contains(entry.id)) continue;
      if (entry.note.trim().isNotEmpty && !notes.contains(entry.note.trim())) {
        notes.add(entry.note.trim());
      }
      if (keep.merchant.trim().isEmpty && entry.merchant.trim().isNotEmpty) {
        keep = keep.copyWith(merchant: entry.merchant.trim());
      }
      if (keep.accountId == null && entry.accountId != null) {
        keep = keep.copyWith(accountId: entry.accountId);
      }
    }
    entries[keepIndex] =
        keep.copyWith(note: notes.join(' · '));
    entries.removeWhere((entry) => remove.contains(entry.id));
    _recalculateBalances();
    await _changed();
    return entries[keepIndex];
  }

  /// Adds imported entries, skipping ones that duplicate an existing record
  /// (same kind, amount, day, and description). Returns counts.
  Future<({int added, int skipped})> importEntries(
      List<LedgerEntry> imported) async {
    var added = 0;
    var skipped = 0;
    for (final item in imported) {
      final duplicate = entries.any((entry) =>
          entry.kind == item.kind &&
          entry.amountPaise == item.amountPaise &&
          isSameDay(entry.occurredAt, item.occurredAt) &&
          entry.title.toLowerCase() == item.title.toLowerCase());
      if (duplicate) {
        skipped++;
        continue;
      }
      entries.add(LedgerEntry(
        id: _newId(),
        kind: item.kind,
        amountPaise: item.amountPaise,
        category: item.category,
        title: item.title,
        occurredAt: item.occurredAt,
        paymentMethod: item.paymentMethod,
        merchant: item.merchant,
        note: item.note,
      ));
      if (!categories.contains(item.category)) categories.add(item.category);
      added++;
    }
    if (added > 0) await _changed();
    return (added: added, skipped: skipped);
  }

  // ---------------------------------------------------------------------------
  // Budgets

  Future<void> setBudget(
    String category,
    int limitPaise, {
    BudgetPeriod period = BudgetPeriod.monthly,
    bool rollover = false,
    int alertPercent = 80,
  }) async {
    budgets.removeWhere((budget) => budget.category == category);
    budgets.add(SpendingBudget(
      category: category,
      limitPaise: limitPaise,
      period: period,
      rollover: rollover,
      alertPercent: alertPercent,
    ));
    if (!categories.contains(category)) categories.insert(0, category);
    await _changed();
  }

  Future<void> deleteBudget(String category) async {
    budgets.removeWhere((budget) => budget.category == category);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Savings goals

  Future<SavingsGoal> addGoal(
    String name,
    int targetPaise, {
    DateTime? targetDate,
    GoalType type = GoalType.custom,
  }) async {
    final goal = SavingsGoal(
      id: _newId(),
      name: name.trim(),
      targetPaise: targetPaise,
      createdAt: now(),
      targetDate: targetDate,
      type: type,
    );
    goals.add(goal);
    await _changed();
    return goal;
  }

  Future<void> updateGoal(SavingsGoal updated) async {
    final index = goals.indexWhere((goal) => goal.id == updated.id);
    if (index < 0) throw StateError('That goal no longer exists.');
    goals[index] = updated;
    await _changed();
  }

  Future<void> contributeToGoal(
    String id,
    int amountPaise, {
    String note = '',
    DateTime? at,
  }) async {
    final index = goals.indexWhere((goal) => goal.id == id);
    if (index < 0) return;
    goals[index] = goals[index].copyWith(contributions: [
      ...goals[index].contributions,
      GoalContribution(
        id: _newId(),
        amountPaise: amountPaise,
        at: at ?? now(),
        note: note.trim(),
      ),
    ]);
    await _changed();
  }

  Future<void> deleteContribution(String goalId, String contributionId) async {
    final index = goals.indexWhere((goal) => goal.id == goalId);
    if (index < 0) return;
    goals[index] = goals[index].copyWith(
      contributions: goals[index]
          .contributions
          .where((item) => item.id != contributionId)
          .toList(),
    );
    await _changed();
  }

  Future<void> deleteGoal(String id) async {
    goals.removeWhere((goal) => goal.id == id);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Tasks

  Future<LocalTask> addTask({
    required String title,
    required String project,
    DateTime? dueAt,
    bool dueHasTime = false,
    DateTime? startAt,
    int? durationMinutes,
    String description = '',
    String notes = '',
    String category = '',
    List<String> tags = const [],
    TaskPriority priority = TaskPriority.medium,
    TaskStatus status = TaskStatus.todo,
    List<String> subtasks = const [],
    Recurrence recurrence = Recurrence.none,
    List<int> reminderOffsets = const [],
  }) async {
    final task = LocalTask(
      id: _newId(),
      title: title.trim(),
      project: project.trim(),
      createdAt: now(),
      dueAt: dueAt,
      dueHasTime: dueAt != null && dueHasTime,
      startAt: startAt,
      durationMinutes: durationMinutes,
      description: description.trim(),
      notes: notes.trim(),
      category: category.trim(),
      tags: tags,
      priority: priority,
      status: status,
      subtasks: [
        for (final item in subtasks)
          if (item.trim().isNotEmpty) Subtask(id: _newId(), title: item.trim()),
      ],
      recurrence: _anchored(recurrence, dueAt),
      reminderOffsets: dueAt == null ? const [] : reminderOffsets,
    );
    tasks.add(task);
    await _changed();
    return task;
  }

  Future<void> updateTask(LocalTask updated) async {
    final index = tasks.indexWhere((task) => task.id == updated.id);
    if (index < 0) throw StateError('That task no longer exists.');
    final previous = tasks[index];
    tasks[index] = updated.copyWith(
      recurrence: _anchored(updated.recurrence, updated.dueAt),
      reminderOffsets: updated.dueAt == null ? const [] : null,
      clearSnooze: previous.dueAt != updated.dueAt,
    );
    if (previous.dueAt != updated.dueAt && updated.dueAt != null) {
      _log(updated.title, 'Rescheduled to ${formatDateTime(updated.dueAt!)}',
          updated.id);
    }
    await _changed();
  }

  Subtask newSubtask(String title) => Subtask(id: _newId(), title: title);

  /// Changes a task's status. Completing a recurring task records the
  /// completion and moves the task to its next occurrence.
  Future<void> setTaskStatus(String id, TaskStatus status) async {
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = tasks[index];
    final current = now();
    if (status == TaskStatus.done &&
        !task.recurrence.isNone &&
        task.dueAt != null) {
      final due = task.dueAt!;
      final startOfToday = dateOnly(current);
      var next = task.recurrence.next(due);
      while (next != null && next.isBefore(startOfToday)) {
        next = task.recurrence.next(next);
      }
      if (next != null) {
        final shift = next.difference(due);
        tasks[index] = task.copyWith(
          dueAt: next,
          startAt: task.startAt?.add(shift),
          status: TaskStatus.todo,
          subtasks: [
            for (final subtask in task.subtasks) subtask.copyWith(done: false)
          ],
          completedAt: current,
          completionHistory: [...task.completionHistory, current],
          clearSnooze: true,
        );
        _log(task.title, 'Completed · next ${formatDate(next)}', id);
        await _changed();
        return;
      }
    }
    tasks[index] = status == TaskStatus.done
        ? task.copyWith(
            status: status,
            completedAt: current,
            completionHistory: [...task.completionHistory, current],
            clearSnooze: true,
          )
        : task.copyWith(status: status, clearCompleted: true);
    if (status == TaskStatus.done) _log(task.title, 'Completed', id);
    await _changed();
  }

  Future<void> toggleTask(String id) async {
    final task = taskById(id);
    if (task == null) return;
    await setTaskStatus(id, task.isDone ? TaskStatus.todo : TaskStatus.done);
  }

  Future<void> toggleSubtask(String taskId, String subtaskId) async {
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) return;
    tasks[index] = tasks[index].copyWith(subtasks: [
      for (final subtask in tasks[index].subtasks)
        subtask.id == subtaskId
            ? subtask.copyWith(done: !subtask.done)
            : subtask,
    ]);
    await _changed();
  }

  Future<void> snoozeTask(String id, int minutes) async {
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0 || minutes <= 0) return;
    tasks[index] = tasks[index]
        .copyWith(snoozedUntil: now().add(Duration(minutes: minutes)));
    _log(tasks[index].title, 'Snoozed $minutes min', id);
    await _changed();
  }

  Future<void> rescheduleTask(String id, DateTime dueAt,
      {required bool hasTime}) async {
    final task = taskById(id);
    if (task == null) return;
    final shift = task.dueAt == null ? null : dueAt.difference(task.dueAt!);
    await updateTask(task.copyWith(
      dueAt: dueAt,
      dueHasTime: hasTime,
      startAt: shift == null ? null : task.startAt?.add(shift),
      reminderOffsets: task.reminderOffsets.isEmpty && hasTime
          ? [settings.defaultReminderMinutes]
          : null,
    ));
  }

  /// Removes all reminders from a task without changing its due date.
  Future<void> cancelTaskReminders(String id) async {
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    tasks[index] =
        tasks[index].copyWith(reminderOffsets: const [], clearSnooze: true);
    _log(tasks[index].title, 'Reminders cancelled', id);
    await _changed();
  }

  Future<void> deleteTask(String id) async {
    tasks.removeWhere((task) => task.id == id);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Bills

  Future<Bill> addBill({
    required String name,
    required BillKind kind,
    required int amountPaise,
    required DateTime nextDueAt,
    Recurrence recurrence = const Recurrence(Repeat.monthly),
    int remindDaysBefore = 2,
    String category = 'Bills',
    String notes = '',
  }) async {
    final bill = Bill(
      id: _newId(),
      name: name.trim(),
      kind: kind,
      amountPaise: amountPaise,
      nextDueAt: dateOnly(nextDueAt),
      recurrence: _anchored(recurrence, nextDueAt),
      remindDaysBefore: remindDaysBefore,
      category: category,
      notes: notes.trim(),
    );
    bills.add(bill);
    await _changed();
    return bill;
  }

  Future<void> updateBill(Bill updated) async {
    final index = bills.indexWhere((bill) => bill.id == updated.id);
    if (index < 0) throw StateError('That bill no longer exists.');
    bills[index] = updated.copyWith(
        recurrence: _anchored(updated.recurrence, updated.nextDueAt));
    await _changed();
  }

  /// Records a confirmed payment for the bill's current due date and moves a
  /// recurring bill to its next due date. Optionally records an expense.
  Future<void> markBillPaid(
    String id, {
    int? amountPaise,
    DateTime? paidAt,
    bool recordExpense = true,
    String paymentMethod = 'Other',
  }) async {
    final index = bills.indexWhere((bill) => bill.id == id);
    if (index < 0) return;
    final bill = bills[index];
    final amount = FinanceValidator.requirePositivePaise(
        amountPaise ?? bill.amountPaise, 'payment amount');
    final paid = paidAt ?? now();
    String? entryId;
    if (recordExpense) {
      entryId = _newId();
      entries.add(LedgerEntry(
        id: entryId,
        kind: EntryKind.expense,
        amountPaise: amount,
        category: bill.category,
        title: bill.name,
        occurredAt: paid,
        paymentMethod: paymentMethod,
        note: 'Bill due ${formatDate(bill.nextDueAt)}',
        billId: bill.id,
      ));
    }
    final next = bill.recurrence.next(bill.nextDueAt);
    bills[index] = bill.copyWith(
      amountPaise: amount,
      nextDueAt: next ?? bill.nextDueAt,
      active: next != null,
      payments: [
        ...bill.payments,
        BillPayment(
          id: _newId(),
          dueAt: bill.nextDueAt,
          paidAt: paid,
          amountPaise: amount,
          entryId: entryId,
        ),
      ],
    );
    await _changed();
  }

  /// Reverts the most recent payment, including its linked expense.
  Future<void> undoLastBillPayment(String id) async {
    final index = bills.indexWhere((bill) => bill.id == id);
    if (index < 0 || bills[index].payments.isEmpty) return;
    final bill = bills[index];
    final last = bill.payments.last;
    if (last.entryId != null) {
      entries.removeWhere((entry) => entry.id == last.entryId);
    }
    bills[index] = bill.copyWith(
      nextDueAt: last.dueAt,
      active: true,
      payments: bill.payments.sublist(0, bill.payments.length - 1),
    );
    await _changed();
  }

  Future<void> deleteBill(String id) async {
    bills.removeWhere((bill) => bill.id == id);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Clock, focus, alarms, notes, settings

  Future<void> updateClock(ClockState state) async {
    clock = state;
    await _changed();
  }

  Future<void> recordFocusSession({
    required String label,
    required FocusKind kind,
    required DateTime startedAt,
    required int plannedSeconds,
    required int actualSeconds,
    required bool completed,
  }) async {
    if (actualSeconds < 5) return;
    focusSessions.add(FocusSession(
      id: _newId(),
      label: label.trim(),
      kind: kind,
      startedAt: startedAt,
      plannedSeconds: plannedSeconds,
      actualSeconds: actualSeconds,
      completed: completed,
    ));
    if (focusSessions.length > 1000) focusSessions.removeAt(0);
    await _changed();
  }

  Future<void> saveAlarm(Alarm alarm) async {
    final index = alarms.indexWhere((item) => item.id == alarm.id);
    if (index < 0) {
      alarms.add(alarm);
    } else {
      alarms[index] = alarm;
    }
    alarms.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    await _changed();
  }

  Alarm newAlarm(int hour, int minute) =>
      Alarm(id: _newId(), hour: hour, minute: minute);

  Future<void> deleteAlarm(String id) async {
    alarms.removeWhere((alarm) => alarm.id == id);
    await _changed();
  }

  Future<QuickNote> addNote(String text) async {
    final created = now();
    final note = QuickNote(
        id: _newId(),
        text: text.trim(),
        createdAt: created,
        updatedAt: created);
    notes.insert(0, note);
    await _changed();
    return note;
  }

  Future<void> updateNote(QuickNote note) async {
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index < 0) return;
    notes[index] = note.copyWith(updatedAt: now());
    await _changed();
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((note) => note.id == id);
    await _changed();
  }

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    MoneyFormat.symbol = value.currencySymbol;
    MoneyFormat.hidden = value.hideAmounts;
    await _changed();
  }

  /// Counts a wrong app-lock PIN. Returns when the PIN pad opens again if
  /// this failure starts a lockout. Uses the wall clock, like the lock screen.
  Future<DateTime?> recordPinFailure() async {
    final failures = settings.pinFailures + 1;
    final wait = pinLockoutFor(failures);
    final until = wait == null ? null : DateTime.now().add(wait);
    settings = settings.copyWith(pinFailures: failures, pinLockedUntil: until);
    await _changed();
    return until;
  }

  Future<void> clearPinFailures() async {
    if (settings.pinFailures == 0 && settings.pinLockedUntil == null) return;
    settings = settings.copyWith(clearPinLockout: true);
    await _changed();
  }

  Future<void> addCategory(String category) async {
    final cleaned = category.trim();
    if (cleaned.isEmpty ||
        categories.any(
          (item) => item.toLowerCase() == cleaned.toLowerCase(),
        )) {
      return;
    }
    categories.insert(0, cleaned);
    await _changed();
  }

  Future<void> clearAllData() async {
    _resetCollections();
    clock = const ClockState();
    _storageDisabled = _dataFile == null;
    storageError = _dataFile == null ? storageError : null;
    await _changed();
  }

  /// Points entries and drafts that use the receipt at [from] to [to], for
  /// example after the photo was encrypted.
  Future<void> replaceReceiptPath(String from, String to) async {
    var changed = false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].receiptPath == from) {
        entries[i] = entries[i].copyWith(receiptPath: to);
        changed = true;
      }
    }
    for (var i = 0; i < pending.length; i++) {
      final draft = pending[i];
      if (draft.entry.receiptPath == from) {
        pending[i] = PendingEntry(
          id: draft.id,
          entry: draft.entry.copyWith(receiptPath: to),
          source: draft.source,
          createdAt: draft.createdAt,
          sourceKey: draft.sourceKey,
          sourceText: draft.sourceText,
          recurringId: draft.recurringId,
        );
        changed = true;
      }
    }
    if (changed) await _changed();
  }

  /// Records that a payment was handed to a UPI app. Recorded before the
  /// app opens, so a handoff is kept even if LifePilot is closed meanwhile.
  Future<PaymentHandoff> recordHandoff({
    required String payee,
    required int amountPaise,
    String vpa = '',
    String appName = '',
    String reference = '',
    bool fromQr = false,
  }) async {
    final handoff = PaymentHandoff(
      id: _newId(),
      payee: payee.trim(),
      amountPaise: amountPaise,
      createdAt: now(),
      vpa: vpa.trim(),
      appName: appName,
      reference: reference,
      fromQr: fromQr,
    );
    handoffs.insert(0, handoff);
    if (handoffs.length > 100) handoffs.removeLast();
    await _changed();
    return handoff;
  }

  /// Stores what the UPI app reported. A reported success or pending
  /// payment becomes a draft expense for the user to approve; it is never
  /// recorded automatically, because the report is not bank-verified.
  Future<PendingEntry?> reportHandoffResult(
      String handoffId, UpiResponse response) async {
    final index = handoffs.indexWhere((item) => item.id == handoffId);
    if (index < 0) return null;
    final handoff = handoffs[index].copyWith(
      status: response.status.name,
      bankReference: response.reference,
    );
    handoffs[index] = handoff;
    PendingEntry? draft;
    final key = 'upi:${handoff.id}';
    final reported = response.status == UpiReported.success ||
        response.status == UpiReported.submitted;
    if (reported && !pending.any((item) => item.sourceKey == key)) {
      final previous = entries
          .where((entry) =>
              handoff.vpa.isNotEmpty &&
              normalizeVpa(entry.merchant) == normalizeVpa(handoff.vpa))
          .fold<LedgerEntry?>(
              null,
              (latest, entry) =>
                  latest == null || entry.occurredAt.isAfter(latest.occurredAt)
                      ? entry
                      : latest);
      draft = PendingEntry(
        id: _newId(),
        source: 'upi',
        sourceKey: key,
        createdAt: now(),
        sourceText: [
          '${handoff.appName.isEmpty ? 'The UPI app' : handoff.appName} reported: ${response.status == UpiReported.success ? 'payment successful' : 'payment pending'}.',
          if (response.reference.isNotEmpty) 'Reference ${response.reference}.',
          'Not verified with your bank. Check your bank SMS or statement before approving.',
        ].join(' '),
        entry: LedgerEntry(
          id: '',
          kind: EntryKind.expense,
          amountPaise: handoff.amountPaise,
          category:
              ruleCategory(categoryRules, '${handoff.payee} ${handoff.vpa}') ??
                  previous?.category ??
                  'Other',
          title: handoff.payee,
          occurredAt: handoff.createdAt,
          paymentMethod: 'UPI',
          merchant: handoff.vpa.isEmpty ? handoff.payee : handoff.vpa,
          note:
              response.reference.isEmpty ? '' : 'UPI ref ${response.reference}',
        ),
      );
      pending.add(draft);
    }
    await _changed();
    return draft;
  }

  /// Removes a handoff whose UPI app never opened.
  Future<void> removeHandoff(String id) async {
    handoffs.removeWhere((item) => item.id == id);
    await _changed();
  }

  Payee? payeeFor(String vpa) {
    final wanted = normalizeVpa(vpa);
    for (final payee in payees) {
      if (normalizeVpa(payee.vpa) == wanted) return payee;
    }
    return null;
  }

  /// Saves a payee, or renames an existing one with the same UPI ID.
  Future<Payee> savePayee(String name, String vpa) async {
    final existing = payeeFor(vpa);
    final cleanName = name.trim().isEmpty ? vpa.trim() : name.trim();
    final Payee payee;
    if (existing != null) {
      payee = existing.copyWith(name: cleanName);
      payees[payees.indexOf(existing)] = payee;
    } else {
      payee = Payee(
          id: _newId(), name: cleanName, vpa: vpa.trim(), createdAt: now());
      payees.add(payee);
    }
    await _changed();
    return payee;
  }

  /// Notes a payment to a saved payee, for ordering by most used.
  Future<void> notePayeePaid(String vpa) async {
    final payee = payeeFor(vpa);
    if (payee == null) return;
    payees[payees.indexOf(payee)] =
        payee.copyWith(lastPaidAt: now(), timesPaid: payee.timesPaid + 1);
    await _changed();
  }

  Future<void> deletePayee(String id) async {
    payees.removeWhere((payee) => payee.id == id);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Accounts and transfers

  Account? accountById(String? id) {
    if (id == null) return null;
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  Future<Account> addAccount(String name, AccountKind kind,
      {int openingBalancePaise = 0}) async {
    final account = Account(
      id: _newId(),
      name: name.trim(),
      kind: kind,
      openingBalancePaise: openingBalancePaise,
    );
    accounts.add(account);
    _accountBalances[account.id] = openingBalancePaise;
    await _changed();
    return account;
  }

  Future<void> updateAccount(Account updated) async {
    final index = accounts.indexWhere((item) => item.id == updated.id);
    if (index < 0) throw StateError('That account no longer exists.');
    accounts[index] = updated;
    await _changed();
  }

  /// Adjusts the running balance of [accountId] by [delta] paise (positive
  /// for income/credit, negative for expense/debit). Only adjusts when a
  /// running balance exists (seeded from opening balance or a bank SMS).
  void _adjustAccountBalance(String? accountId, int amountPaise,
      {required bool isIncome}) {
    if (accountId == null) return;
    if (!_accountBalances.containsKey(accountId)) return;
    final delta = isIncome ? amountPaise : -amountPaise;
    _accountBalances[accountId] = (_accountBalances[accountId]!) + delta;
  }

  /// Matches a bank (and an optional last-four hint) to a tracked account: by
  /// the last four digits saved on the account or in its masked number, then
  /// by the bank name, then by a hint in the account's name. Returns null when
  /// nothing matches.
  Account? accountForBank(String bank, {String? hint}) {
    if (hint != null && hint.isNotEmpty) {
      for (final account in accounts.where((item) => !item.archived)) {
        final last4 = account.last4.isNotEmpty
            ? account.last4
            : _trailingDigits(account.accountNumberMasked);
        if (last4.isNotEmpty && last4 == hint) return account;
      }
    }
    final bankLower = bank.toLowerCase();
    final bankWords =
        bankLower.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    for (final account in accounts.where((item) => !item.archived)) {
      final nameLower = account.name.toLowerCase();
      // Direct containment either way.
      if (nameLower.contains(bankLower) || bankLower.contains(nameLower)) {
        return account;
      }
      final storedBank = account.bankName?.toLowerCase();
      if (storedBank != null &&
          storedBank.isNotEmpty &&
          (storedBank == bankLower ||
              storedBank.contains(bankLower) ||
              bankLower.contains(storedBank))) {
        return account;
      }
      // Any significant word from the bank name appearing in the account name.
      if (bankWords.any(nameLower.contains)) {
        return account;
      }
    }
    if (hint != null && hint.isNotEmpty) {
      for (final account in accounts.where((item) => !item.archived)) {
        if (account.name.contains(hint)) return account;
      }
    }
    return null;
  }

  /// Matches a bank-reported balance to a tracked account.
  Account? accountForBankBalance(BankBalance balance) =>
      accountForBank(balance.bank, hint: balance.accountHint);

  /// The account a bank-reported balance belongs to, creating a suggested
  /// bank account when none matches so the balance and its transactions are
  /// not left unlinked. A card's credit limit is not money held, so it does
  /// not create an account.
  Account? _accountForBalanceOrCreate(BankBalance balance) {
    final existing = accountForBankBalance(balance);
    if (existing != null) return existing;
    if (balance.isLimit) return null;
    final hint = balance.accountHint;
    final hasHint = hint != null && hint.isNotEmpty;
    final account = Account(
      id: _newId(),
      name: hasHint ? '${balance.bank} ••$hint' : balance.bank,
      kind: AccountKind.bank,
      last4: hasHint ? hint : '',
      bankName: balance.bank,
      accountNumberMasked: hasHint ? 'XXXX $hint' : null,
      currentBalancePaise: balance.paise,
      availableBalancePaise: balance.paise,
      lastStatementBalancePaise: balance.paise,
      lastUpdatedAt: balance.at,
      lastSyncedAt: balance.at,
      verificationStatus: hasHint ? 'matched' : 'unidentified',
    );
    accounts.add(account);
    return account;
  }

  /// When the latest bank SMS or statement set [account]'s balance.
  DateTime? lastSyncedFor(Account account) {
    var latest = account.lastSyncedAt;
    for (final balance in bankBalances) {
      if (accountForBankBalance(balance)?.id != account.id) continue;
      if (latest == null || balance.at.isAfter(latest)) latest = balance.at;
    }
    return latest;
  }

  /// The newest bank-reported balance for [account], if any.
  BankBalance? bankBalanceFor(Account account) {
    BankBalance? best;
    for (final balance in bankBalances) {
      if (accountForBankBalance(balance)?.id != account.id) continue;
      if (best == null || balance.at.isAfter(best.at)) best = balance;
    }
    return best;
  }

  /// Sets the account to the bank's balance and remembers when. Older
  /// reports are ignored so an out-of-order message cannot undo a newer one.
  bool _applyBankBalance(Account account, BankBalance balance,
      {bool force = false}) {
    if (!force &&
        account.lastSyncedAt != null &&
        balance.at.isBefore(account.lastSyncedAt!)) {
      return false;
    }
    _accountBalances[account.id] = balance.paise;
    final index = accounts.indexWhere((item) => item.id == account.id);
    if (index >= 0) {
      accounts[index] = account.copyWith(lastSyncedAt: balance.at);
    }
    return true;
  }

  /// Accepts the bank's balance for the account it belongs to.
  Future<void> adjustToBankBalance(BankBalance balance) async {
    final account = accountForBankBalance(balance);
    if (account != null) _applyBankBalance(account, balance, force: true);
    ignoredBalanceKeys.remove(balance.key);
    await _changed();
  }

  /// Applies a bank-reported balance to the matched account, updating the
  /// running balance, last sync time, and verification status. Notifies
  /// listeners so the UI refreshes immediately.
  Future<void> applyBankBalanceReport(BankBalance balance,
      {String? verificationStatus}) async {
    final account = accountForBankBalance(balance);
    if (account == null) return;
    if (!balance.at.isAfter(account.lastUpdatedAt ?? DateTime(1970))) return;
    final index = accounts.indexWhere((item) => item.id == account.id);
    if (index < 0) return;
    _accountBalances[account.id] = balance.paise;
    accounts[index] = account.copyWith(
      currentBalancePaise: balance.paise,
      availableBalancePaise: balance.paise,
      lastStatementBalancePaise: balance.paise,
      lastUpdatedAt: balance.at,
      lastSyncedAt: balance.at,
      verificationStatus: verificationStatus ?? 'verified',
    );
    await _changed();
  }

  /// Leaves LifePilot's recorded balance alone and stops offering this
  /// reported balance for adjustment.
  Future<void> ignoreBankBalance(BankBalance balance) async {
    ignoredBalanceKeys.add(balance.key);
    await _changed();
  }

  /// Recomputes every account's running balance from its opening balance,
  /// recorded entries and transfers. Used after correcting past entries.
  Future<void> recalculateBalances() async {
    _recalculateBalances();
    await _changed();
  }

  void _recalculateBalances() {
    for (final account in accounts) {
      _accountBalances[account.id] =
          accountBalance(account, entries, transfers);
    }
  }

  /// Running balance for [accountId]: the last value set by opening balance,
  /// a bank SMS, or adjusted by linked entries/transfers. Falls back to
  /// computing from opening balance plus recorded entries when none is set.
  int accountRunningBalance(String accountId) {
    if (_accountBalances.containsKey(accountId)) {
      final recorded = _accountBalances[accountId]!;
      final account = accounts.firstWhere((item) => item.id == accountId);
      // If no entries have adjusted this account yet (recorded balance still
      // equals the opening balance) and a bank SMS reported a newer balance
      // for a matched account, prefer the bank figure so the Accounts tab and
      // Plan tab agree.
      final hasEntries = entries.any((item) => item.accountId == accountId);
      if (!hasEntries && recorded == account.openingBalancePaise) {
        final bankBalance = bankBalanceFor(account);
        if (bankBalance != null &&
            (account.lastSyncedAt == null ||
                bankBalance.at.isAfter(account.lastSyncedAt!))) {
          return bankBalance.paise;
        }
      }
      return recorded;
    }
    final account = accounts.firstWhere((item) => item.id == accountId);
    return accountBalance(account, entries, transfers);
  }

  /// Deletes an account. Entries keep their amounts but lose the link, and
  /// transfers involving it are removed.
  Future<void> deleteAccount(String id) async {
    accounts.removeWhere((item) => item.id == id);
    transfers.removeWhere(
        (item) => item.fromAccountId == id || item.toAccountId == id);
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].accountId == id) {
        entries[i] = entries[i].copyWith(clearAccount: true);
      }
    }
    await _changed();
  }

  Future<AccountTransfer> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountPaise,
    DateTime? at,
    String note = '',
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Choose two different accounts.');
    }
    if (amountPaise <= 0) throw ArgumentError('Enter an amount.');
    final transfer = AccountTransfer(
      id: _newId(),
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountPaise: amountPaise,
      at: at ?? now(),
      note: note.trim(),
    );
    transfers.add(transfer);
    await _changed();
    // Money leaves the source account and arrives at the destination.
    _adjustAccountBalance(fromAccountId, amountPaise, isIncome: false);
    _adjustAccountBalance(toAccountId, amountPaise, isIncome: true);
    return transfer;
  }

  /// Edits a transfer. Both accounts are moved back from the old values and
  /// forward to the new ones, so the pair always stays in step.
  Future<AccountTransfer> updateTransfer(
    String id, {
    required String fromAccountId,
    required String toAccountId,
    required int amountPaise,
    DateTime? at,
    String note = '',
  }) async {
    final index = transfers.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('That transfer no longer exists.');
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Choose two different accounts.');
    }
    if (amountPaise <= 0) throw ArgumentError('Enter an amount.');
    final old = transfers[index];
    final updated = old.copyWith(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountPaise: amountPaise,
      at: at ?? old.at,
      note: note.trim(),
    );
    // Undo the old movement, then apply the new one.
    _adjustAccountBalance(old.fromAccountId, old.amountPaise, isIncome: true);
    _adjustAccountBalance(old.toAccountId, old.amountPaise, isIncome: false);
    _adjustAccountBalance(updated.fromAccountId, updated.amountPaise,
        isIncome: false);
    _adjustAccountBalance(updated.toAccountId, updated.amountPaise,
        isIncome: true);
    transfers[index] = updated;
    await _changed();
    return updated;
  }

  Future<void> deleteTransfer(String id) async {
    final index = transfers.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final old = transfers.removeAt(index);
    _adjustAccountBalance(old.fromAccountId, old.amountPaise, isIncome: true);
    _adjustAccountBalance(old.toAccountId, old.amountPaise, isIncome: false);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Recurring entries and drafts

  Future<RecurringEntry> addRecurring({
    required EntryKind kind,
    required int amountPaise,
    required String category,
    required String title,
    required Recurrence recurrence,
    required DateTime firstDate,
    String? accountId,
    String paymentMethod = 'Other',
  }) async {
    final rule = RecurringEntry(
      id: _newId(),
      kind: kind,
      amountPaise: amountPaise,
      category: category,
      title: title.trim(),
      recurrence: _anchored(recurrence, firstDate),
      nextDate: dateOnly(firstDate),
      accountId: accountId,
      paymentMethod: paymentMethod,
    );
    recurring.add(rule);
    _prepareRecurring();
    await _changed();
    return rule;
  }

  Future<void> updateRecurring(RecurringEntry updated) async {
    final index = recurring.indexWhere((item) => item.id == updated.id);
    if (index < 0) throw StateError('That rule no longer exists.');
    recurring[index] = updated.copyWith(
        recurrence: _anchored(updated.recurrence, updated.nextDate));
    _prepareRecurring();
    await _changed();
  }

  Future<void> deleteRecurring(String id) async {
    recurring.removeWhere((item) => item.id == id);
    pending.removeWhere((item) => item.recurringId == id);
    await _changed();
  }

  /// Creates drafts for recurring occurrences that are due today or earlier.
  /// Returns how many were created. Safe to call repeatedly.
  Future<int> prepareDueRecurring() async {
    final result = _prepareRecurring();
    if (result.changed) await _changed();
    return result.created;
  }

  /// Drafts due occurrences. [changed] is also true when a rule moved on
  /// without a new draft, because the payment was already recorded or a
  /// bank SMS draft was labelled with the rule instead.
  ({int created, bool changed}) _prepareRecurring() {
    final today = dateOnly(now());
    var created = 0;
    var changed = false;
    for (var i = 0; i < recurring.length; i++) {
      var rule = recurring[i];
      if (!rule.active) continue;
      // Cap catch-up so a rule left for years cannot flood the inbox.
      for (var step = 0; step < 24 && !rule.nextDate.isAfter(today); step++) {
        final key = 'recurring:${rule.id}:${rule.nextDate.toIso8601String()}';
        final due = DateTime(
            rule.nextDate.year, rule.nextDate.month, rule.nextDate.day, 9);
        bool expected(LedgerEntry entry) => matchesRecurring(
              kind: rule.kind,
              amountPaise: rule.amountPaise,
              title: rule.title,
              due: due,
              entry: entry,
            );
        // The bank SMS for this payment may have arrived first (salary a
        // day early): label that draft instead of drafting it twice.
        final smsDraft = pending.indexWhere((item) =>
            item.source != 'recurring' &&
            item.recurringId == null &&
            expected(item.entry));
        // Or it was already recorded, by hand or from SMS. Expenses need a
        // matching name here, so an unrelated payment of the same amount
        // does not swallow the draft.
        final recorded = entries.any((entry) =>
            entry.source != 'recurring' &&
            matchesRecurring(
              kind: rule.kind,
              amountPaise: rule.amountPaise,
              title: rule.title,
              due: due,
              entry: entry,
              requireName: true,
            ));
        if (smsDraft >= 0 || recorded) changed = true;
        if (smsDraft >= 0) {
          final draft = pending[smsDraft];
          pending[smsDraft] = draft.copyWith(
            recurringId: rule.id,
            entry: draft.entry.copyWith(
              title: rule.title,
              category: rule.category,
              accountId: draft.entry.accountId ?? rule.accountId,
            ),
          );
        } else if (recorded) {
          // Nothing to draft.
        } else if (!pending.any((item) => item.sourceKey == key)) {
          pending.add(PendingEntry(
            id: _newId(),
            source: 'recurring',
            sourceKey: key,
            recurringId: rule.id,
            createdAt: now(),
            entry: LedgerEntry(
              id: '',
              kind: rule.kind,
              amountPaise: rule.amountPaise,
              category: rule.category,
              title: rule.title,
              occurredAt: DateTime(rule.nextDate.year, rule.nextDate.month,
                  rule.nextDate.day, 9),
              paymentMethod: rule.paymentMethod,
              accountId: rule.accountId,
              source: 'recurring',
            ),
          ));
          created++;
        }
        final next = rule.recurrence.next(rule.nextDate);
        rule = next == null
            ? rule.copyWith(active: false)
            : rule.copyWith(nextDate: next);
        changed = true;
        if (next == null) break;
      }
      recurring[i] = rule;
    }
    return (created: created, changed: changed || created > 0);
  }

  /// Adds SMS-derived drafts, skipping messages already seen.
  Future<int> addSmsDrafts(
      List<({String key, String text, LedgerEntry entry})> drafts) async {
    var added = 0;
    for (final draft in drafts) {
      if (seenSms.contains(draft.key)) continue;
      seenSms.add(draft.key);
      pending.add(PendingEntry(
        id: _newId(),
        source: 'sms',
        sourceKey: draft.key,
        sourceText: draft.text,
        createdAt: now(),
        entry: draft.entry,
      ));
      added++;
    }
    if (added > 0) await _changed();
    return added;
  }

  /// Saves the result of [buildSmsImport]: new drafts, bank confirmations of
  /// UPI drafts and held-back suspicious messages. Every message used is
  /// remembered by fingerprint so it is never imported twice.
  Future<void> applySmsImport(SmsImport import) async {
    if (import.handled.isEmpty && import.balances.isEmpty) return;
    // Link bank-reported balances to accounts first, creating a suggested
    // account when the bank is not tracked yet, so the balance and the
    // transactions from the same bank are not left unlinked.
    for (final balance in import.balances.values) {
      // Only a report newer than the last sync may change a balance, so an
      // out-of-order or replayed message cannot undo a newer one.
      final existingIndex =
          bankBalances.indexWhere((item) => item.key == balance.key);
      final olderThanStored = existingIndex >= 0 &&
          balance.at.isBefore(bankBalances[existingIndex].at);
      if (olderThanStored) continue;
      if (existingIndex < 0) {
        bankBalances.add(balance);
      } else {
        bankBalances[existingIndex] = balance;
      }
      if (ignoredBalanceKeys.contains(balance.key)) continue;
      final account = _accountForBalanceOrCreate(balance);
      if (account != null) _applyBankBalance(account, balance, force: true);
    }
    // Add the drafts, linking each to the account its bank balance created or
    // matched so the transaction counts towards that account's balance.
    for (final draft in import.drafts) {
      var entry = draft.entry;
      if (entry.accountId == null) {
        final bank = import.draftBanks[draft.sourceKey];
        final account = bank == null ? null : accountForBank(bank);
        if (account != null) entry = entry.copyWith(accountId: account.id);
      }
      pending.add(PendingEntry(
        id: _newId(),
        entry: entry,
        source: draft.source,
        createdAt: draft.createdAt,
        sourceKey: draft.sourceKey,
        sourceText: draft.sourceText,
        warning: draft.warning,
        balancePaise: draft.balancePaise,
        autoPay: draft.autoPay,
        billId: draft.billId,
      ));
    }
    for (final match in import.recurringMatches) {
      final index = pending.indexWhere((draft) => draft.id == match.pendingId);
      if (index < 0) continue;
      final draft = pending[index];
      final expected = draft.entry.amountPaise;
      pending[index] = draft.copyWith(
        bankConfirmed: true,
        // The bank's amount and date are what actually happened.
        entry: draft.entry.copyWith(
          amountPaise: match.amountPaise,
          occurredAt: match.occurredAt,
          note: match.note.isEmpty ? null : match.note,
          merchant: match.merchant.isEmpty ? null : match.merchant,
        ),
        sourceText: match.sourceText,
        balancePaise: match.balancePaise,
        warning: match.amountPaise == expected
            ? null
            : 'Your bank shows ${formatMoney(match.amountPaise)}; the recurring entry expects ${formatMoney(expected)}. Edit the recurring entry if the amount has changed.',
      );
    }
    for (final item in import.unrecognized) {
      unrecognizedSms.removeWhere((existing) => existing.key == item.key);
      unrecognizedSms.insert(0, item);
    }
    if (unrecognizedSms.length > 100) {
      unrecognizedSms.removeRange(100, unrecognizedSms.length);
    }
    for (final confirmation in import.confirmations) {
      final index =
          pending.indexWhere((draft) => draft.id == confirmation.pendingId);
      if (index < 0) continue;
      final draft = pending[index];
      pending[index] = draft.copyWith(
        bankConfirmed: true,
        sourceText:
            '${draft.sourceText.replaceFirst(RegExp(r'\s*Not verified with your bank\..*$'), '')} Confirmed by a bank SMS from ${confirmation.bank}.'
                .trim(),
      );
    }
    for (final item in import.suspicious) {
      suspiciousSms.removeWhere((existing) => existing.key == item.key);
      suspiciousSms.insert(0, item);
    }
    if (suspiciousSms.length > 50) {
      suspiciousSms.removeRange(50, suspiciousSms.length);
    }
    seenSms.addAll(import.handled);
    await _changed();
  }

  /// Payments that look recurring but are not yet recurring entries.
  List<RecurringSuggestion> recurringSuggestions() => suggestRecurring(
        entries: entries,
        rules: recurring,
        now: now(),
        dismissed: dismissedSuggestions,
      );

  /// Turns a suggestion into a recurring entry, starting at its next date.
  Future<RecurringEntry> acceptSuggestion(RecurringSuggestion suggestion) =>
      addRecurring(
        kind: suggestion.kind,
        amountPaise: suggestion.amountPaise,
        category: suggestion.category,
        title: suggestion.title,
        recurrence: Recurrence(suggestion.repeat),
        firstDate: suggestion.nextDate,
        accountId: accountById(suggestion.accountId)?.id,
        paymentMethod: suggestion.paymentMethod,
      );

  Future<void> dismissSuggestion(String key) async {
    dismissedSuggestions.add(key);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Debts

  Future<Debt> addDebt({
    required String name,
    required DebtKind kind,
    required int openingPaise,
    required DateTime startDate,
    double annualRatePercent = 0,
    int emiPaise = 0,
    String counterparty = '',
    DateTime? dueAt,
  }) async {
    final debt = Debt(
      id: _newId(),
      name: name.trim(),
      kind: kind,
      openingPaise: openingPaise,
      startDate: dateOnly(startDate),
      annualRatePercent: annualRatePercent,
      emiPaise: emiPaise,
      counterparty: counterparty.trim(),
      dueAt: dueAt == null ? null : dateOnly(dueAt),
    );
    debts.add(debt);
    await _changed();
    return debt;
  }

  Future<void> updateDebt(Debt updated) async {
    final index = debts.indexWhere((item) => item.id == updated.id);
    if (index < 0) throw StateError('That debt no longer exists.');
    debts[index] = updated;
    await _changed();
  }

  Future<void> deleteDebt(String id) async {
    debts.removeWhere((item) => item.id == id);
    await _changed();
  }

  /// Records a repayment. For money the user owes, it can also be recorded
  /// as an expense (category Loans). A debt paid off is marked closed.
  Future<Debt> addDebtPayment(
    String debtId, {
    required int amountPaise,
    DateTime? at,
    String note = '',
    bool recordExpense = false,
    bool recordIncome = false,
    String? accountId,
  }) async {
    final index = debts.indexWhere((item) => item.id == debtId);
    if (index < 0) throw StateError('That debt no longer exists.');
    final debt = debts[index];
    final when = at ?? now();
    final amount = FinanceValidator.requirePositivePaise(
        amountPaise, 'payment amount');
    final owed = debtStatus(debt, asOf: when).outstandingPaise;
    FinanceValidator.rejectOverpayment(
        amountPaise: amount, owedPaise: owed, debtName: debt.name);
    var updated = debt.copyWith(payments: [
      ...debt.payments,
      DebtPayment(
          id: _newId(), amountPaise: amountPaise, at: when, note: note.trim()),
    ]);
    if (debtStatus(updated, asOf: when).outstandingPaise <= 0) {
      updated = updated.copyWith(closed: true);
    }
    debts[index] = updated;
    if (recordExpense && !debt.owedToMe) {
      entries.add(LedgerEntry(
        id: _newId(),
        kind: EntryKind.expense,
        amountPaise: amountPaise,
        category: 'Loans',
        title: debt.kind == DebtKind.creditCard
            ? '${debt.name} payment'
            : '${debt.name} EMI',
        occurredAt: when,
        note: note.trim(),
        accountId: accountId,
      ));
      _adjustAccountBalance(accountId, amountPaise, isIncome: false);
    }
    // Money lent coming back is an inflow, not income earned. It restores
    // the balance of the account the repayment went into.
    if (recordIncome && debt.owedToMe) {
      entries.add(LedgerEntry(
        id: _newId(),
        kind: EntryKind.income,
        amountPaise: amountPaise,
        category: 'Loans',
        title: 'Returned · ${debt.name}',
        occurredAt: when,
        note: note.trim().isEmpty
            ? 'Interest-free lending returned'
            : note.trim(),
        accountId: accountId,
      ));
      _adjustAccountBalance(accountId, amountPaise, isIncome: true);
    }
    await _changed();
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Investments

  /// Adds an investment. [investedPaise] (for an FD, the principal) is
  /// recorded as money put in on [startDate].
  Future<Investment> addInvestment({
    required String name,
    required InvestmentKind kind,
    required DateTime startDate,
    int investedPaise = 0,
    int? valuePaise,
    double annualRatePercent = 0,
    DateTime? maturityDate,
    int installmentPaise = 0,
    int sipPaise = 0,
    int? sipDay,
  }) async {
    FinanceValidator.requirePositivePaise(investedPaise, 'invested amount');
    final item = Investment(
      id: _newId(),
      name: name.trim(),
      kind: kind,
      flows: [
        if (investedPaise > 0 && kind != InvestmentKind.recurringDeposit)
          InvestmentFlow(
              id: _newId(),
              amountPaise: investedPaise,
              at: dateOnly(startDate)),
      ],
      valuePaise: kind.isDeposit ? null : valuePaise,
      valueAsOf: kind.isDeposit || valuePaise == null ? null : now(),
      annualRatePercent: annualRatePercent,
      startDate: dateOnly(startDate),
      maturityDate: maturityDate == null ? null : dateOnly(maturityDate),
      installmentPaise: installmentPaise,
      sipPaise: sipPaise,
      sipDay: sipPaise > 0 ? sipDay : null,
    );
    investments.add(item);
    await _changed();
    return item;
  }

  Future<void> updateInvestment(Investment updated) async {
    final index = investments.indexWhere((item) => item.id == updated.id);
    if (index < 0) throw StateError('That investment no longer exists.');
    investments[index] = updated;
    await _changed();
  }

  Future<void> deleteInvestment(String id) async {
    investments.removeWhere((item) => item.id == id);
    await _changed();
  }

  /// Money put in (positive) or taken out (negative). The current value
  /// moves by the same amount, since the user's last value no longer
  /// includes it.
  Future<void> addInvestmentFlow(String id, int amountPaise,
      {DateTime? at}) async {
    final index = investments.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('That investment no longer exists.');
    final item = investments[index];
    investments[index] = item.copyWith(
      flows: [
        ...item.flows,
        InvestmentFlow(id: _newId(), amountPaise: amountPaise, at: at ?? now()),
      ],
      valuePaise:
          item.valuePaise == null ? null : item.valuePaise! + amountPaise,
    );
    await _changed();
  }

  Future<void> setInvestmentValue(String id, int valuePaise) async {
    final index = investments.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('That investment no longer exists.');
    investments[index] =
        investments[index].copyWith(valuePaise: valuePaise, valueAsOf: now());
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Documents and warranties

  Future<VaultItem> addVaultItem({
    required String title,
    required VaultKind kind,
    String? filePath,
    String? fileName,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    int? amountPaise,
    String notes = '',
  }) async {
    final item = VaultItem(
      id: _newId(),
      title: title.trim(),
      kind: kind,
      createdAt: now(),
      filePath: filePath,
      fileName: fileName,
      purchaseDate: purchaseDate == null ? null : dateOnly(purchaseDate),
      expiryDate: expiryDate == null ? null : dateOnly(expiryDate),
      amountPaise: amountPaise,
      notes: notes.trim(),
    );
    vault.add(item);
    await _changed();
    return item;
  }

  /// Removes the record; returns its file path so the caller can delete it.
  Future<String?> deleteVaultItem(String id) async {
    final index = vault.indexWhere((item) => item.id == id);
    if (index < 0) return null;
    final item = vault.removeAt(index);
    await _changed();
    return item.filePath;
  }

  // ---------------------------------------------------------------------------
  // Trips

  Future<Trip> addTrip({
    required String name,
    required DateTime start,
    required DateTime end,
    required int budgetPaise,
  }) async {
    final trip = Trip(
      id: _newId(),
      name: name.trim(),
      start: dateOnly(start),
      end: dateOnly(end),
      budgetPaise: budgetPaise,
    );
    trips.add(trip);
    await _changed();
    return trip;
  }

  Future<void> deleteTrip(String id) async {
    trips.removeWhere((item) => item.id == id);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Tax and GST rules

  /// The rules JSON in use for [financialYear]: the user's own if they
  /// imported or edited one, else the built-in rules for that year, else
  /// the latest built-in year (with [exact] false).
  ({String source, bool custom, bool exact}) taxRulesFor(String financialYear) {
    final own = taxRuleOverrides[financialYear];
    if (own != null) return (source: own, custom: true, exact: true);
    final builtIn = builtInTaxRules[financialYear];
    if (builtIn != null) return (source: builtIn, custom: false, exact: true);
    final latest = (builtInTaxRules.keys.toList()..sort()).last;
    return (source: builtInTaxRules[latest]!, custom: false, exact: false);
  }

  /// Validates and saves rules for the year named inside them. Throws
  /// [FormatException] and changes nothing if they are invalid.
  Future<TaxRules> saveTaxRules(String source) async {
    final rules = parseTaxRules(source);
    taxRuleOverrides[rules.financialYear] =
        const JsonEncoder.withIndent('  ').convert(jsonDecode(source));
    await _changed();
    return rules;
  }

  Future<void> resetTaxRules(String financialYear) async {
    taxRuleOverrides.remove(financialYear);
    await _changed();
  }

  /// Splits a bill the user paid: their share is recorded as an expense and
  /// each other person's share as money lent to them.
  Future<void> splitBill({
    required String title,
    required int totalPaise,
    required List<String> people,
    required String category,
    DateTime? at,
    String? accountId,
  }) async {
    final names = <String>[];
    final seen = <String>{};
    for (final name in people) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
      names.add(trimmed);
    }
    if (names.isEmpty) throw ArgumentError('Add at least one other person.');
    final when = at ?? now();
    FinanceValidator.requirePositivePaise(totalPaise, 'total amount');
    final share = totalPaise ~/ (names.length + 1);
    if (share <= 0) {
      throw ArgumentError(
          'The bill is too small to split ${names.length + 1} ways.');
    }
    // The user's share absorbs any paise left over from dividing.
    final mine = totalPaise - share * names.length;
    entries.add(LedgerEntry(
      id: _newId(),
      kind: EntryKind.expense,
      amountPaise: mine,
      category: category,
      title: title.trim(),
      occurredAt: when,
      note:
          'Your share of ${formatMoney(totalPaise, reveal: true)}, split ${names.length + 1} ways',
      accountId: accountId,
    ));
    for (final name in names) {
      debts.add(Debt(
        id: _newId(),
        name: '${title.trim()} · $name',
        kind: DebtKind.lent,
        openingPaise: share,
        startDate: dateOnly(when),
        counterparty: name,
      ));
    }
    await _changed();
  }

  /// Saves a statement import: new drafts, the rows' keys so a re-import
  /// skips them, the closing balance under [balanceLabel] (usually the
  /// account's name), and the column layout for that bank.
  Future<void> applyStatementImport(StatementImport import,
      {String balanceLabel = 'Bank statement',
      String? accountId,
      String? bankName,
      String? accountHint,
      StatementMapping? mapping}) async {
    // Resolve the target account: explicit choice > bank-name/hint match >
    // auto-created suggested account. This keeps statement transactions and
    // balances linked to the right account instead of left unlinked.
    String? resolvedAccountId = accountId;
    if (resolvedAccountId == null) {
      final existing = accountForBank(bankName ?? '', hint: accountHint);
      if (existing != null) {
        resolvedAccountId = existing.id;
      } else if (bankName != null && bankName.isNotEmpty) {
        // Auto-create a suggested account so the balance and transactions are
        // not left unlinked. A card's credit limit is not money held.
        final hintDigits = accountHint ?? '';
        final hasHint = hintDigits.isNotEmpty;
        final newAccount = Account(
          id: _newId(),
          name: hasHint ? '$bankName ••$hintDigits' : bankName,
          kind: AccountKind.bank,
          last4: hintDigits,
          bankName: bankName,
          accountNumberMasked: hasHint ? 'XXXX $hintDigits' : null,
          currentBalancePaise: import.closing?.paise,
          availableBalancePaise: import.closing?.paise,
          lastStatementBalancePaise: import.closing?.paise,
          lastUpdatedAt: import.closing?.at,
          lastSyncedAt: import.closing?.at,
          verificationStatus: hasHint ? 'matched' : 'unidentified',
        );
        accounts.add(newAccount);
        resolvedAccountId = newAccount.id;
      }
    }
    // Link each draft to the resolved account so its balance impact lands
    // on the correct account and it is not left unlinked.
    for (final draft in import.drafts) {
      var entry = draft.entry;
      if (entry.accountId == null && resolvedAccountId != null) {
        entry = entry.copyWith(accountId: resolvedAccountId);
      }
      pending.add(PendingEntry(
        id: _newId(),
        entry: entry,
        source: draft.source,
        createdAt: draft.createdAt,
        sourceKey: draft.sourceKey,
        sourceText: draft.sourceText,
        balancePaise: draft.balancePaise,
      ));
    }
    seenSms.addAll(import.keys);
    if (mapping != null) {
      final saved = mapping.withBank(balanceLabel);
      final index = statementMappings.indexWhere(
          (item) => item.bank.toLowerCase() == saved.bank.toLowerCase());
      if (index < 0) {
        statementMappings.add(saved);
      } else {
        statementMappings[index] = saved;
      }
    }
    final closing = import.closing;
    if (closing != null) {
      final balance = BankBalance(
          bank: balanceLabel, paise: closing.paise, at: closing.at);
      final index = bankBalances.indexWhere((item) => item.key == balance.key);
      if (index < 0) {
        bankBalances.add(balance);
      } else if (!balance.at.isBefore(bankBalances[index].at)) {
        bankBalances[index] = balance;
      }
      // Apply to the resolved account only when we have one.
      if (resolvedAccountId != null && !ignoredBalanceKeys.contains(balance.key)) {
        final account = accountById(resolvedAccountId);
        if (account != null) _applyBankBalance(account, balance, force: true);
      }
    }
    await _changed();
  }

  /// Layout saved for [bank], if any.
  StatementMapping? statementMappingFor(String bank) {
    for (final mapping in statementMappings) {
      if (mapping.bank.toLowerCase() == bank.toLowerCase()) return mapping;
    }
    return null;
  }

  Future<void> dismissUnrecognized(String key) async {
    unrecognizedSms.removeWhere((item) => item.key == key);
    await _changed();
  }

  Future<void> forgetBankBalances() async {
    bankBalances.clear();
    await _changed();
  }

  Future<void> dismissSuspicious(String key) async {
    suspiciousSms.removeWhere((item) => item.key == key);
    await _changed();
  }

  /// Removes stored SMS text: held-back messages and the message text on
  /// SMS drafts. Fingerprints stay so old messages are not imported again;
  /// they are hashes and cannot be turned back into text.
  Future<void> forgetSmsText() async {
    suspiciousSms.clear();
    for (var i = 0; i < pending.length; i++) {
      if (pending[i].source == 'sms') {
        pending[i] = pending[i].copyWith(sourceText: '');
      }
    }
    await _changed();
  }

  Future<CategoryRule> addCategoryRule(String contains, String category) async {
    final rule = CategoryRule(
        id: _newId(), contains: contains.trim(), category: category);
    categoryRules.add(rule);
    await _changed();
    return rule;
  }

  Future<void> deleteCategoryRule(String id) async {
    categoryRules.removeWhere((rule) => rule.id == id);
    await _changed();
  }

  /// Records a draft as a real entry, optionally with edited values.
  Future<LedgerEntry> approvePending(String id, {LedgerEntry? edited}) async {
    final index = pending.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('That draft no longer exists.');
    final draft = pending.removeAt(index);
    final values = edited ?? draft.entry;
    final entry = LedgerEntry(
      id: _newId(),
      kind: values.kind,
      amountPaise: values.amountPaise,
      category: values.category,
      title: values.title,
      occurredAt: values.occurredAt,
      note: values.note,
      paymentMethod: values.paymentMethod,
      merchant: values.merchant,
      subcategory: values.subcategory,
      accountId: values.accountId,
      receiptPath: values.receiptPath,
      source: draft.source,
      billId: draft.billId ?? values.billId,
    );
    entries.add(entry);
    await _changed();
    // Auto-adjust the linked account's running balance. When the SMS reported
    // a balance after this transaction, trust it; otherwise adjust by the
    // entry amount (income adds, expense subtracts).
    final accountId = values.accountId;
    if (accountId != null && _accountBalances.containsKey(accountId)) {
      final smsBalance = edited == null ? draft.balancePaise : null;
      if (smsBalance != null) {
        _accountBalances[accountId] = smsBalance;
      } else {
        final current = _accountBalances[accountId]!;
        final delta =
            values.isIncome ? values.amountPaise : -values.amountPaise;
        _accountBalances[accountId] = current + delta;
      }
    }
    // If the draft was matched to an existing bill (e.g. a bill payment SMS),
    // mark the bill as paid. recordExpense is false because the entry above
    // already records the expense — we must not count it twice.
    if (draft.billId != null && draft.entry.kind == EntryKind.expense) {
      await billRepository.markBillPaid(
        draft.billId!,
        amountPaise: draft.entry.amountPaise,
        paidAt: draft.entry.occurredAt,
        recordExpense: false,
        paymentMethod: draft.entry.paymentMethod,
      );
    }
    return entry;
  }

  Future<void> dismissPending(String id) async {
    pending.removeWhere((item) => item.id == id);
    await _changed();
  }

  /// Reverses [entryId] by recording an offsetting entry of the opposite
  /// kind on the same account, linked via [refundLinkId]. The original entry
  /// is preserved in history; the reversal offsets its balance impact.
  /// Returns the reversal entry, or null if the original is not found.
  Future<LedgerEntry?> reverseEntry(String entryId) async {
    final index = entries.indexWhere((item) => item.id == entryId);
    if (index < 0) return null;
    final original = entries[index];
    final reversedKind =
        original.isIncome ? EntryKind.expense : EntryKind.income;
    final reversal = LedgerEntry(
      id: _newId(),
      kind: reversedKind,
      amountPaise: original.amountPaise,
      category: original.category,
      title: 'Reversal · ${original.title}',
      occurredAt: now(),
      paymentMethod: original.paymentMethod,
      merchant: original.merchant,
      subcategory: original.subcategory,
      accountId: original.accountId,
      receiptPath: original.receiptPath,
      source: 'reversal',
      sourceReference: 'reverse:${original.id}',
      refundLinkId: original.id,
      validationStatus: ValidationStatus.verified,
      confidenceScore: 1.0,
    );
    entries.add(reversal);
    await _changed();
    _adjustAccountBalance(
      reversal.accountId,
      reversal.amountPaise,
      isIncome: reversal.isIncome,
    );
    return reversal;
  }

  // ---------------------------------------------------------------------------
  // Habits

  Future<Habit> addHabit(String name,
      {List<int> weekdays = const [], int? reminderMinutes}) async {
    final habit = Habit(
      id: _newId(),
      name: name.trim(),
      createdAt: now(),
      weekdays: weekdays,
      reminderMinutes: reminderMinutes,
    );
    habits.add(habit);
    await _changed();
    return habit;
  }

  Future<void> updateHabit(Habit updated) async {
    final index = habits.indexWhere((item) => item.id == updated.id);
    if (index < 0) throw StateError('That habit no longer exists.');
    habits[index] = updated;
    await _changed();
  }

  /// Marks [day] (default today) done, or undone if it already was.
  Future<void> toggleHabit(String id, {DateTime? day}) async {
    final index = habits.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final target = dateOnly(day ?? now());
    final habit = habits[index];
    habits[index] = habit.copyWith(
      checkIns: habit.doneOn(target)
          ? habit.checkIns.where((item) => !isSameDay(item, target)).toList()
          : [...habit.checkIns, target],
    );
    await _changed();
  }

  Future<void> deleteHabit(String id) async {
    habits.removeWhere((item) => item.id == id);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Backup and persistence

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toJson());

  Future<void> restoreJson(String source) async {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('This is not a supported LifePilot backup.');
    }
    try {
      _checkFormat(root);
    } on FormatException {
      throw const FormatException('This is not a supported LifePilot backup.');
    }
    _apply(root);
    _storageDisabled = _dataFile == null;
    storageError = _dataFile == null ? storageError : null;
    await _changed();
  }

  Map<String, Object?> _toJson() => {
        'format': 'lifepilot-backup',
        'version': currentVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'entries': entries.map((entry) => entry.toJson()).toList(),
        'budgets': budgets.map((budget) => budget.toJson()).toList(),
        'goals': goals.map((goal) => goal.toJson()).toList(),
        'tasks': tasks.map((task) => task.toJson()).toList(),
        'handoffs': handoffs.map((handoff) => handoff.toJson()).toList(),
        'bills': bills.map((bill) => bill.toJson()).toList(),
        'focusSessions': focusSessions.map((item) => item.toJson()).toList(),
        'alarms': alarms.map((alarm) => alarm.toJson()).toList(),
        'notes': notes.map((note) => note.toJson()).toList(),
        'reminderLog': reminderLog.map((item) => item.toJson()).toList(),
        'categories': categories,
        'settings': settings.toJson(),
        'clock': clock.toJson(),
        'accounts': accounts.map((item) => item.toJson()).toList(),
        'transfers': transfers.map((item) => item.toJson()).toList(),
        'recurring': recurring.map((item) => item.toJson()).toList(),
        'pending': pending.map((item) => item.toJson()).toList(),
        'habits': habits.map((item) => item.toJson()).toList(),
        'payees': payees.map((item) => item.toJson()).toList(),
        'suspiciousSms': suspiciousSms.map((item) => item.toJson()).toList(),
        'unrecognizedSms': unrecognizedSms.map((item) => item.toJson()).toList(),
        'categoryRules': categoryRules.map((item) => item.toJson()).toList(),
        'statementMappings':
            statementMappings.map((item) => item.toJson()).toList(),
        'ignoredBalanceKeys': ignoredBalanceKeys.toList(),
        'seenSms': seenSms.toList(),
        'bankBalances': bankBalances.map((item) => item.toJson()).toList(),
        'accountBalances': _accountBalances,
        'dismissedSuggestions': dismissedSuggestions.toList(),
        'debts': debts.map((item) => item.toJson()).toList(),
        'investments': investments.map((item) => item.toJson()).toList(),
        'taxRules': taxRuleOverrides,
        'trips': trips.map((item) => item.toJson()).toList(),
        'vault': vault.map((item) => item.toJson()).toList(),
      };

  Recurrence _anchored(Recurrence recurrence, DateTime? date) {
    if (date == null || recurrence.anchorDay != null) return recurrence;
    return switch (recurrence.repeat) {
      Repeat.monthly || Repeat.quarterly || Repeat.yearly => Recurrence(
          recurrence.repeat,
          interval: recurrence.interval,
          anchorDay: date.day),
      _ => recurrence,
    };
  }

  void _log(String title, String action, String? taskId) {
    reminderLog.insert(
        0,
        ReminderLogEntry(
            at: now(), title: title, action: action, taskId: taskId));
    if (reminderLog.length > 200) reminderLog.removeLast();
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  /// Notifies listeners and queues a write. Writes go to a temporary file
  /// that then replaces the data file, so a crash mid-write cannot leave a
  /// half-written data file behind.
  Future<void> _changed() {
    if (_storageDisabled || _dataFile == null) {
      notifyListeners();
      return Future<void>.value();
    }
    storageError = null;
    notifyListeners();
    final file = _dataFile;
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      try {
        final temporary = File('${file.path}.tmp');
        final clear = jsonEncode(_toJson());
        final cipher = _cipher;
        await temporary.writeAsString(
            cipher == null ? clear : await cipher.sealText(clear),
            flush: true);
        await temporary.rename(file.path);
      } on Object {
        storageError = 'A change could not be saved to this device.';
        notifyListeners();
      }
    });
    return _writeQueue;
  }
}
