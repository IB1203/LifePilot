# Requirements and scope

## Product invariants

- Useful offline; no paid API, cloud account, or mandatory subscription.
- INR is the default display currency. Persist amounts as integer paise, never floating point.
- Financial figures always come from local records and deterministic calculations.
- No fake production financial records and no claim that UPI app launch proves payment.
- Local AI is constrained by typed tools and policy; no arbitrary SQL, code execution, or device access.
- Do not claim database or backup encryption until actually implemented and tested.

## Initial release scope

Expenses/income and categories; budgets and savings goals; dashboard and reports; tasks, projects, and local reminders; UPI handoff and manual transaction recording; a deterministic offline assistant; local backup and restore. Each feature requires validation, persistence, offline/error handling, tests, and an Android build before it is called complete.

## Phased delivery

1. UI foundation, SQLite/Drift, expenses, income, categories.
2. Budgets, savings, dashboard, reports.
3. Tasks, projects, recurrence, reminders.
4. UPI handoff, imports, optional reviewed notification capture.
5. Rule-based assistant, typed tools, authorization, confirmation, execution history.
6. Optional on-device LLM after runtime/model licensing and device evaluation.
7. Backup/security hardening, performance, release checks.

## UPI claims

Payment launch is a handoff. Record initiation separately from a user-confirmed transaction; only treat a response according to its documented integration contract. Notification-derived entries are candidate records, not verified settlement. Never request or persist UPI PINs, passwords, or OTPs.

## Testing expectations

Money calculations, date periods, recurrence and idempotency require unit tests. Database schema and migration paths require persistence tests. Forms, empty/error states, and confirmation workflows require widget tests. Integration tests cover offline persistence, import/export, reminders, and Android UPI handoff where feasible. Test commands are pending SDK availability.
