# LifePilot AI

LifePilot is an offline-first personal finance, planning and time app. INR is the default currency. Amounts are stored as integer paise, and every figure comes from records entered on this device.

## Install on an Android phone

1. On your phone, open **[the latest release](https://github.com/IB1203/LifePilot/releases/latest)** and download **`LifePilot.apk`**.
2. Open the downloaded file. If Android asks, allow your browser or file manager to **install unknown apps** (Settings › Apps › Special access › Install unknown apps).
3. Tap **Install**, then **Open**.

Needs Android 7.0 or newer. LifePilot is not on Google Play. To update, install a newer `LifePilot.apk` over the old one; your data is kept.

**If Play Protect blocks the install.** In India, Play Protect blocks apps installed from outside the Play Store that can read SMS, which LifePilot's optional bank-SMS feature needs. To install:

1. Open the **Play Store** › your profile picture › **Play Protect** › ⚙ (top right).
2. Turn off **Scan apps with Play Protect**.
3. Install `LifePilot.apk`.
4. Turn **Scan apps with Play Protect** back on.

LifePilot asks for SMS access only if you use the bank-SMS feature, and you can say no.

**Xiaomi, POCO and Redmi phones:** if HyperOS asks to scan the app or sign in to a Xiaomi account first, you can sign in, or turn off **Security › Settings › Scan apps before installing** for the install. When paying by UPI, tap **Allow** on "Show all your UPI apps", or use **Other UPI app**.

Everything stays on the phone: no account, no server, no ads. Camera, SMS and microphone are asked for only when you use the feature that needs them.

## Features

- **Home:** greeting, live clock, next reminder with countdown, today's task overview, monthly finances and budget progress, daily planner, upcoming bills, insights, savings goals and recent transactions. Sections can be reordered or hidden.
- **Clock:** digital and analog clock, world clock, stopwatch with laps, countdown timer, Pomodoro focus timer with statistics, and alarms.
- **Tasks:** priorities, statuses, due times, durations, subtasks, tags, projects and recurrence; smart lists, filters, calendar, timeline and overlap warnings.
- **Reminders:** several reminders per task, snooze, reschedule, cancel and history, plus bill, timer and alarm notifications.
- **Finance:** income and expenses with editing, search, filters, CSV export/import and duplicate warnings; monthly or weekly budgets with rollover; bills and subscriptions with confirmed payments; savings goals with contribution history; charts and rule-based insights; UPI app handoff.
- **Assistant:** deterministic offline commands such as “Add ₹250 for lunch” or “Remind me to pay the electricity bill tomorrow at 7 PM”. It asks before saving anything.
- **Accounts and recurring entries:** wallets with recorded balances and transfers; recurring income/expenses (salary, rent, SIPs) that prepare drafts for you to approve; bank-SMS import that turns transaction messages into drafts.
- **Habits and weekly review:** daily or weekday habits with streaks and reminders; a weekly summary of tasks, focus, habits and money.
- **Receipts and smart categories:** attach a photo to an expense; categories are suggested from your past entries.
- **UPI payments:** scan a UPI QR code (camera or photo) or enter a UPI ID, review payee, amount and warnings (look-alike IDs, reused names, large amounts), pick a UPI app, and get a draft expense when the app reports success. LifePilot never asks for the UPI PIN and never treats the app's report as bank confirmation.
- **Bank SMS:** scan the inbox, paste messages, or (opt-in) capture them as they arrive; per-bank parsing, scam messages held back with reporting shortcuts, UPI payments confirmed by the bank SMS, duplicates skipped, category rules, and balances/links removed from stored text.
- **Calculator:** More › Calculator, with phone-style percentages and "Add as expense".
- **Home-screen widget:** today's tasks, next reminder and this month's spending (amounts hidden while the app lock is on).
- **Security and data:** records and receipt photos encrypted on the device with an Android Keystore key; PIN app lock with fingerprint/face unlock (whole app or Finance only) and a lockout that grows after repeated wrong PINs; PIN re-entry before UPI payments, exports, restores and deleting data; screenshots and the recent-apps preview blocked while the lock is on; AES-256 encrypted backup files; monthly PDF/Excel reports.
- **Personalisation:** light/dark/system theme, accent colours, and a first-run setup.
- **More:** notes, notification and display settings, categories, JSON backup and restore.

Data is stored in a private file on the device, encrypted with a key kept in the Android Keystore. Android app backup and device-to-device transfer are disabled, and the key cannot move to another phone, so use More › Encrypted backup to move or keep your records. The clipboard JSON backup is plain text and is cleared from the clipboard after a minute. If you forget the app PIN, the only way back in is clearing app data, so keep an encrypted backup. Net recorded cash flow is income minus recorded expenses, not net worth. A UPI app launch is never treated as proof of payment.

## Notifications

On Android 13+ the app asks for notification permission when you first set a reminder. Reminders use inexact timing unless you allow "Alarms & reminders" in More › Notifications. Some phones delay background alarms under battery optimisation; set LifePilot to "Unrestricted" if reminders arrive late. Scheduled reminders are restored after a reboot.

## Run and build

From this directory:

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
flutter run            # with an Android device or emulator connected
```

The debug APK is written to `build\app\outputs\flutter-apk\app-debug.apk`.

Release build (shrunk, with Dart code obfuscated):

```powershell
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```

Keep `build/symbols` for each release to read crash stack traces. Without `android/key.properties` the release APK is signed with the debug key, which is fine for your own phone but must not be published; see [docs/release-signing.md](docs/release-signing.md).

If a build fails with "Unable to delete directory" under `build\`, OneDrive is locking build outputs. Stop Gradle (`android\gradlew --stop`), delete `build\app`, and build again, or exclude the `build` folder from OneDrive sync.

See [docs/architecture.md](docs/architecture.md) and [docs/implementation-plan.md](docs/implementation-plan.md) for design and remaining work.

## License

MIT. See [LICENSE](LICENSE).
