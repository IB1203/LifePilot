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
3. Optional reviewed notification-based transaction capture. (Bank statement import — CSV/Excel — was delivered in Phase 8; text PDF statements are still not read.)
4. Optional automatic posting of recurring entries (currently always drafts that need approval, by design).
5. Cloud sync between devices (backups are manual files today).
6. A true alarm-clock experience (full-screen, continuous ringing) would need native Android work; current alarms are high-priority notifications.
7. Hindi (and other) translations: needs string extraction for ~700 UI strings and review by a native speaker.
8. Releases are signed with the build computer's debug key by choice (no release key; see docs/release-signing.md). Google Play would need an upload key.
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

## Recurring entries and bank SMS fixes (delivered 6 November 2026)

Implemented and tested (`test/bank_sms_test.dart`, `test/sms_import_test.dart`, `test/recurring_detect_test.dart`); full suite 177 passing, analyzer clean. Not yet verified on a device.

- Available balance and card limit read from bank SMS (including balance-only messages), shown per account next to LifePilot's recorded balance.
- Smarter credited/debited detection: balances stripped before deciding, "credited to VPA/payee" counts as a debit, "has credit of"/"debit of" phrasing, executed e-mandate/autopay debits kept (set-up notices ignored), credit card bill payments flagged as transfers.
- A bank SMS confirms the matching recurring draft (salary, rent, SIP) instead of creating a second draft; an SMS that arrives before the due date is labelled with the rule.
- "Looks recurring" suggestions from history (weekly, monthly, quarterly, yearly), with add or "not recurring".
- Last-30-days credited/debited totals; monthly in/out of recurring entries; editing a paused rule no longer resumes it; the recurring form no longer uses its text fields after they are disposed (crashed in debug while the sheet closed).
- Fixed while testing: "Your a/c no. XXXXXX4321 is credited" was read as a payee being credited.

## Integration fixes (delivered 10 November 2026)

Found while reviewing the cross-module integration scenarios; all covered by
tests, analyzer clean, full suite passing.

- **Bank balances and Accounts agree.** A bank SMS balance for a bank that is
  not tracked yet now creates (or matches) an account instead of being left as
  an orphan, so the Accounts total matches the balance Home shows. SMS
  transactions are linked to the account their balance created or matched, and
  the Accounts tab can link older unlinked entries to the right account.
- **Safe to spend is explained, not just shown.** It now starts from the
  available balance when one is known (which already reflects money spent),
  sets aside bills still due, monthly EMIs and a buffer, and offers a
  "How this is calculated" breakdown.
- **The forecast says what it is built from.** It reports the confirmed
  starting balance, expected recurring income, scheduled bills and recurring
  payments, and the estimated day-to-day spending, behind a "details" sheet.
- **Month-end projection made explicit.** The figure was already
  "spent so far + daily pace × days left + bills still due"; the card now shows
  that wording so it cannot be misread as a whole-month average.
- **Salary plan uses recorded income.** Income recorded only in the current
  month now produces a plan ("Income recorded this month") instead of
  "No income yet".
- **Internal transfers never distort totals.** Entries classified as an
  internal transfer (for example a credit-card bill payment or an
  account-to-account move) are excluded from income, expense, category,
  budget and forecast totals.

## Phases 4–11 (from the November 2026 feature research)

All delivered on 6 November 2026 in order, each finished before the next: analyzer clean, 270 automated tests passing (`flutter test`), debug APK builds. None of it is verified on a physical device yet; see the device checklist below.

Every phase stays within the product invariants: offline, no paid API, no cloud account, and figures come only from the user's records. Each phase is finished and tested before the next one starts.

| Phase | Theme | Contents | Size |
|---|---|---|---|
| 4 ✅ delivered 6 Nov 2026 | Money at a glance | "Your money at a glance" dashboard card (available, spent, saved, upcoming commitments); hide-amounts privacy toggle; net worth (accounts + goals − debts); predictive budgeting (month-end projection at the current pace) and a daily safe-to-spend amount; budget comparison between months; rule-based financial health score with each factor explained | M |
| 5 ✅ delivered 6 Nov 2026 | Bills, subscriptions and cash flow | Financial calendar (bills, recurring entries, salary, SIPs, goals); monthly subscription report; price-increase alerts when a recurring payment's amount changes; 30/60-day cash-flow forecast with a shortfall warning; salary allocation plan (suggestions only, never transfers) | M |
| 6 ✅ delivered 6 Nov 2026 | Debts and loans | Loans with EMI amortisation (outstanding principal, interest paid, closure date); credit card dues; money lent/borrowed with simple splitting and settle-up; debt-free planner comparing snowball and avalanche (total interest, months); debt-to-income ratio | L |
| 7 ✅ delivered 6 Nov 2026 | Investments (manual values) | FD, RD, PPF, EPF, NPS, gold, mutual funds, stocks; maturity calculations and reminders; SIP calendar; profit/loss and XIRR on the user's transactions; allocation chart. Always labelled as values the user entered, never live prices | L |
| 8 ✅ delivered 6 Nov 2026 | Import and capture | Bank statement import (CSV/Excel templates for major banks; text-based PDF where feasible); receipt OCR with on-device ML Kit (merchant, total, date) into a reviewable draft | L |
| 9 ✅ delivered 6 Nov 2026 | Assistant upgrades | "Can I afford ₹X?", "Where can I cut back?", unusual-transaction detection, forecast and debt questions; every answer shows its calculation and basis | M |
| 10 ✅ delivered 6 Nov 2026 | Extras | Subcategories; income tax estimate (old vs new regime) and GST calculator, driven by updatable rules (see below); encrypted document vault; no-spend challenge; spending heatmap; warranty tracker; trip budget | M each |
| 11 ✅ delivered 6 Nov 2026 (self-review) | Assurance | Threat model (`docs/threat-model.md`), security tests for crafted backups (`test/security_extras_test.dart`); fixed: receipt and document paths from a backup could point at other app files, and shared document names could escape their folder. An external review is still recommended before any public release | M |

### Tax and GST rules (Phase 10 design, requested 6 November 2026)

- The financial year containing today is selected by default (April–March; FY 2026-27 as of November 2026). Earlier years remain selectable.
- Rules are data, not code: one versioned JSON rules file per financial year, built into the app as data (`lib/core/tax_rules.dart`), with `schemaVersion`, `financialYear`, `source` (official URL) and `lastVerified` date. It covers new- and old-regime slabs, the rebate (87A), standard deduction, surcharge, cess, common deduction limits, and GST rate slabs.
- Updating when rules change, all offline: (1) import a rules JSON file, which is schema-validated, shown as a before/after diff and applied only after confirmation; (2) edit the values in-app; (3) "Reset to built-in rules". User rules are stored with the user's data and included in backups.
- GST calculator: add or remove GST at a chosen rate, with a CGST + SGST (intra-state) or IGST (inter-state) split; rates come from the same rules file.
- Bundled values are verified against incometaxindia.gov.in and cbic-gst.gov.in at implementation time, never from memory. Results are labelled as estimates, not tax advice.

### Device checklist for Phases 4–11

- Bank SMS on a real inbox: balances, credited/debited, salary/rent matched to recurring drafts.
- Statement import with a real CSV/Excel export from each bank used.
- Receipt OCR (Scan receipt) on printed bills; ML Kit adds a few MB to the APK.
- Maturity, warranty and policy reminders fire on time.
- Documents: add a photo and a PDF, view, share, delete.
- Tax: compare a known salary slip's tax with the estimate.

Not planned, because it conflicts with the invariants or needs regulation or a server:

- Account Aggregator integration: needs a regulated partner (FIU registration) and a server. Statement import (Phase 8) covers the need offline.
- Family groups, invites, shared budgets and role-based access: need accounts and a sync server. Phase 6 splitting/settle-up covers the personal side.
- Live market valuations: need a data feed. An optional public NAV download (AMFI) could be considered later as an explicit opt-in.
- Cloud backup, active-session management and login alerts: there are no user accounts. Encrypted backup files already cover backup.
- LLM chat assistant: the assistant stays local and rule-based with typed tools.
