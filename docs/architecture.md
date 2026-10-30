# Architecture

## Layers

```
lib/
  main.dart                 App shell, five destinations, quick add, notification wiring
  core/                     Pure Dart: no widgets, unit-tested
    models.dart             Records (v2 schema) with tolerant JSON for v1 data
    local_store.dart        LifePilotStore: the single source of truth + persistence
    recurrence.dart         Repeat rules (daily, weekdays, weekly, monthly, …)
    finance_calc.dart       Period ranges, summaries, budgets, goals, duplicates, bills
    insights.dart           Offline rule-based insights, each with its basis
    task_logic.dart         Task buckets, filters, conflict detection, day planning
    reminder_plan.dart      Computes the notifications that should exist
    clock_ops.dart          Stopwatch, timer and focus-timer operations
    csv.dart                Transaction CSV export and import
    assistant_engine.dart   Deterministic command parser and typed actions
    formatters.dart         Money (integer paise), dates, times, durations
  services/
    notification_service.dart  flutter_local_notifications wrapper (+ no-op for tests)
    reminder_coordinator.dart  Keeps scheduled notifications in sync with the store
  ui/                       Theme, shared widgets, clock widgets, charts, forms
  features/                 Home, Finance, Tasks, Assistant, More, Clock screens
```

Screens never query or calculate directly against raw lists for money; they call
functions in `core/` that take records and return results. State management is
the existing `ChangeNotifier` store, observed with `AnimatedBuilder`; no new
state-management dependency was added.

## Persistence

`LifePilotStore` keeps records in memory and writes one versioned JSON file
(`lifepilot.local.v1.json`, name kept for compatibility) in the app's private
support directory after every change. Writes go to a temporary file that then
replaces the data file, so an interrupted write cannot corrupt it.

Schema version 2 adds bills, focus sessions, alarms, notes, reminder history,
settings and timer state, and extends tasks, goals, budgets and transactions.
On first launch after upgrading, version 1 data is read, the original file is
copied to `lifepilot.local.v1.v1.backup.json`, and the data is rewritten as v2.
If the backup copy cannot be written, the app keeps the data read-only rather
than overwrite the original. Unreadable or newer-version files are left untouched
and saving is disabled with a visible message. Restore validates every record
before replacing anything.

### Encryption at rest

On Android the file is sealed with AES-256-GCM (`DataCipher` in
`core/secure.dart`). The 256-bit data key is generated once by
`DeviceKey.kt`, wrapped with a non-exportable AES key in the Android Keystore,
and stored wrapped in private shared preferences; Dart receives it over the
`lifepilot/security` method channel at startup. An existing plain file, and
any plain schema-upgrade copies, are encrypted on first launch: each sealed
copy is decrypted and compared before it replaces the original. If that check
fails the app keeps saving unencrypted rather than risk the data. If a sealed
file exists but the key cannot be loaded, the file is left untouched and
saving is disabled. Receipt photos are sealed the same way (`.lps` files) and
older plain photos are converted at startup. The key never leaves the device,
and cloud backup and device transfer are excluded by
`data_extraction_rules.xml`, so moving phones needs an encrypted backup file.

JSON was kept instead of moving to SQLite: data volumes for one person are small,
the existing file already had versioning and backup/restore, and a database
migration would add risk without a measured need. Revisit if transaction counts
reach tens of thousands.

## Reminders and notifications

`buildNotificationPlan` (pure, tested) turns tasks, bills, alarms and running
timers into a list of `PlannedNotification`s with stable ids derived from their
content. `ReminderCoordinator` syncs the system's pending notifications to that
list on start, 400 ms after any change, and whenever the app returns to the
foreground. This single reconciliation step handles creation, cancellation,
rescheduling, snoozing and completion, prevents duplicates, and picks up
time-zone or daylight-saving changes. Recurring reminders are expanded on the
local wall clock, up to 8 occurrences within 30 days, and refreshed each sync.
At most 60 notifications are scheduled at once (Android allows 500).

Scheduling uses exact alarms only when the user has granted "Alarms & reminders";
otherwise inexact, which Android may delay to save battery. The plugin's boot
receiver restores scheduled notifications after a reboot. Task notifications
have "Snooze 10 min" and "Mark done" actions; these open the app to apply the
change, so all writes stay on the main isolate.

## Product boundaries

- No fabricated financial records or automatic bank/UPI reconciliation.
- Net recorded cash flow is income minus expenses the user recorded, never net worth.
- Bills are paid only when the user confirms a payment.
- No claim that app data or backups are encrypted.
- No UPI PIN, password, or OTP collection; a UPI app launch is only a handoff.
- The assistant proposes typed actions; writes happen only after the user confirms.
- An optional local language model is not part of this implementation.
