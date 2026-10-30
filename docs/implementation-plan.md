# Implementation plan

Status as of 29 October 2026. "Tested" means covered by automated tests in
`test/`; nothing has yet been run on a physical Android device.

## Delivered

| Area | Status | Notes |
|---|---|---|
| Theme, navigation, dashboard | Implemented, widget-tested | Material 3 light/dark, live clock header, next-reminder countdown, quick actions, reorderable/hideable sections, staggered entrance, reduced-motion support |
| Clock and time | Implemented, partly tested | Live digital/analog clock, 12/24 h, world clock (IANA zones), stopwatch with laps (tested), countdown timer with presets and labels, Pomodoro focus timer with history and statistics, alarms as repeating notifications |
| Tasks | Implemented, tested | Priority, status, due date/time, start time, duration, project, category, tags, subtasks, notes, recurrence with completion history; smart buckets, filters, search; month/week/day calendar; 30-day timeline; conflict detection; reschedule |
| Reminders | Implemented, plan tested; delivery not device-verified | Multiple offsets per task, snooze (5/10/15/30/60/custom), cancel, reschedule, history; bill, timer and alarm notifications; notification actions |
| Income and expenses | Implemented, tested | Add/edit/delete with undo, merchant, payment method, date and time, search, filters, sort, day grouping, duplicate warning, CSV export and import |
| Budgets | Implemented, tested | Monthly or weekly, rollover, alert threshold, utilization, remaining, history chart |
| Bills and subscriptions | Implemented, tested | Recurrence, reminders, confirmed payments with optional expense, payment history, undo, overdue status |
| Savings goals | Implemented, tested | Types, target date, contribution history, suggested monthly amount, animated progress |
| Reports and insights | Implemented, tested (calculations) | Income vs expenses, cash-flow history, daily spending, category donut, budget utilization, savings progress, recurring expenses; rule-based insights with stated basis |
| Offline assistant | Implemented, tested | Expenses/income, tasks, reminders, clarification (missing time, AM/PM, missing amount), confirmation, verification, finance and task questions, day planning |
| Notes | Implemented | Quick notes with pinning |
| Data | Implemented, tested | Schema v2 with migration and v1 backup copy, atomic writes, validated restore |
| Accounts and transfers | Implemented, tested | Recorded balances only; transfers never count as income or expense |
| Recurring entries | Implemented, tested | Due occurrences become drafts; nothing is recorded without approval |
| Bank SMS import | Implemented, parser tested; inbox reading not device-verified | READ_SMS is a restricted permission on Google Play; fine for private builds. Paste-messages fallback |
| Habits | Implemented, tested | Streaks, weekday schedules, past-day correction, reminders |
| Weekly review | Implemented, tested | Home section, More page, assistant ("How was my week?") |
| Receipts | Implemented; camera flow not device-verified | Photos copied to private storage; unreferenced files cleaned on start |
| Smart categories | Implemented, tested | Learned from past entries; manual choice always wins |
| Voice input | Implemented; not device-verified | Android speech recogniser; text is placed in the box for review |
| Assistant commands | Implemented, tested | Bills, goal contributions, timers/focus, complete task/habit, delete last entry (destructive confirm), weekly summary |
| App lock | Implemented, tested (PIN); biometrics not device-verified | PBKDF2-hashed PIN; lockout after every 5 wrong PINs (30 s, 1 min, 5 min, then 30 min), kept across restarts; relock after 30 s in background; PIN required to weaken any lock setting |
| Encryption at rest | Implemented, tested; migration verified on device | Records file, upgrade copies and receipt photos sealed with AES-256-GCM using a Keystore-wrapped key |
| Sensitive-action PIN | Implemented, tested | UPI handoff, CSV/report/backup export, restores, delete all; can be turned off (needs the PIN) |
| Screen and clipboard | Implemented; FLAG_SECURE not device-verified | Screenshots/recents blocked while locked unless allowed; copied backups/CSV marked sensitive and cleared after 1 min; pasted SMS/backup/CSV cleared after import |
| Release hardening | Release build verified on device | R8 shrinking, Dart obfuscation, signing from `android/key.properties`, logs silenced in release, bill notifications hidden on secure lock screens |
| App icon | Implemented, verified on device | Adaptive, round, themed (Android 13) launcher icons and a white notification icon |
| Encrypted backup | Implemented, tested | PBKDF2-HMAC-SHA256 + AES-256-GCM; share or save to phone; restore from file |
| PDF/Excel report | Implemented, tested | Monthly statement; PDF uses "Rs." because built-in PDF fonts lack the rupee glyph |
| Home-screen widget | Implemented, builds; not device-verified | `home_widget` plugin still applies the Kotlin Gradle plugin; future Flutter versions may require a plugin update |
| Themes and onboarding | Implemented, tested | System/light/dark, 8 accents; first-run setup for fresh installs only |
| Drag to reschedule | Implemented | Long-press a task in the calendar agenda and drop it on a day |

## Remaining work

1. Run on physical Android devices (Android 13+ and an older version) to verify notification delivery, exact-alarm behaviour, notification actions, reboot restore, and battery-optimisation effects on common OEM skins.
2. Verify on device: SMS inbox import, receipt camera, voice input, biometrics and the home-screen widget.
3. Bank statement import formats beyond the app's own CSV; optional reviewed notification-based transaction capture.
4. Optional automatic posting of recurring entries (currently always drafts that need approval, by design).
5. Cloud sync between devices (backups are manual files today).
6. A true alarm-clock experience (full-screen, continuous ringing) would need native Android work; current alarms are high-priority notifications.
7. Hindi (and other) translations: needs string extraction for ~700 UI strings and review by a native speaker.
8. Create the release keystore (see docs/release-signing.md) before publishing.
9. Profile startup time, frame times and memory on a mid-range device.

## Phase 2: safer UPI payments (delivered)

| Area | Status | Notes |
| --- | --- | --- |
| QR scan to pay | Implemented, tested; camera and photo scanning verified on device | On-device ML Kit (`mobile_scanner`); only `upi://pay` is accepted; mandate/collect codes, foreign currency, repeated fields, bad IDs and bad amounts are rejected |
| Merchant QR fidelity | Implemented, tested | All QR fields (reference, merchant code, signature) are passed on unchanged; QR amounts are locked; signed QR notes cannot be edited |
| UPI ID checks | Implemented, tested | Format validation; look-alike detection against saved payees (edit distance and 0/o, 1/l, rn/m swaps); warning when a saved name appears with a new ID; first-payment and large-payment warnings |
| Saved payees | Implemented, tested | Saved only after a UPI app actually opened; tap to pay again; remove with the chip's x |
| Choose app and read result | Implemented, tested with a mocked app; not verified with a real UPI app (none installed on the test phone) | Lists installed UPI apps; launches with `startActivityForResult`; parses `Status`, `txnId`, `ApprovalRefNo`; success/pending creates a draft labelled "not bank-verified"; nothing is recorded automatically |
| Handoff history | Implemented, tested | Status per payment; a handoff whose app never opened is removed; long-press to remove |
| Anti-scam guidance | Implemented | Banner on the UPI tab; PIN re-entry and large-payment confirmation before every handoff |
| Calculator | Implemented, tested, verified on device | More › Calculator; phone-style percentages (1200 + 18% = 1416); session history; "Add as expense" |

Known limits: some UPI apps (notably Google Pay) decline or limit person-to-person payments started from another app, and apps differ in what result they return; LifePilot then shows "No result" and the user records the payment manually.

## Phase 3: better SMS capture (delivered)

| Area | Status | Notes |
| --- | --- | --- |
| Bank formats | Implemented, tested | HDFC, SBI, ICICI, Axis, Kotak, IDFC FIRST, Bank of Baroda, Canara, Union Bank, Paytm and generic formats (`test/bank_sms_test.dart`), written from published patterns with made-up numbers; real messages vary, so add failing ones as tests |
| Extraction | Implemented, tested | Date from the message (several formats, plausibility-checked), balance/limit never taken as the amount, `Rs:`/no-symbol amounts, UPI path names (`UPI/P2M/…/NAME`), VPAs, UPI ref/UTR, card/UPI/ATM/transfer, refunds and reversals |
| Sender check | Implemented, tested | 29 banks' registered sender IDs; user can add their own; unknown senders get a warning on the draft; phone-number senders are never treated as banks |
| Scam detection | Implemented, tested | Bank-style text from phone numbers, KYC/blocked/reward/disconnection lures, links from non-bank senders; held back in "Possible scam messages" with 1930 / cybercrime.gov.in / Sanchar Saathi shortcuts |
| Matching | Implemented, tested | A bank SMS confirms a matching UPI draft (reference, else amount and time) instead of duplicating it; already-recorded transactions are skipped |
| Warnings | Implemented, tested | Large debits not started from LifePilot; ATM withdrawals suggested as transfers |
| Category rules | Implemented, tested | "contains X → category", applied to SMS and UPI drafts before learned suggestions |
| Privacy | Implemented, tested | Drafts keep a copy without balances and links unless "Keep full message text" is on; "Forget stored message text"; only one-way fingerprints of used messages are kept; personal messages are never remembered |
| Real-time capture | Implemented; settings flow and receiver on/off verified on device; capture of a real incoming SMS not verified | Opt-in. The receiver component is disabled unless on; it keeps only bank-like messages, sealed with the device key, posts a notification (amounts hidden while the app lock is on) and LifePilot imports them on open |
| Play Store build | Not done (deliberately) | Google Play rejects SMS permissions for most finance apps. Publishing there needs a build without SMS permissions (paste-only), optionally with a notification-listener source; not needed while the app is sideloaded |

## Next (not started)

To be agreed with the user. Candidates from the roadmap: Phase 4 (statement import; Account Aggregator would need a regulated partner and a server) and Phase 5 (security tests, threat model, external review).
