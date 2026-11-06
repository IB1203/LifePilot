# Threat model (Phase 11, November 2026)

Scope: the features added in Phases 4–10 (bank balances from SMS, statement
import, receipt OCR, debts, investments, tax rules, document vault, trips) on
top of the existing security design (see `architecture.md` and the Phase 1
notes in `implementation-plan.md`). This is a self-review, not an external
audit; an independent review is still recommended before any public release.

## Assets

| Asset | Where it lives | Protection |
|---|---|---|
| Records (entries, balances, debts, investments, tax rules, trips, document metadata) | Records file in app-private storage | AES-256-GCM with a Keystore-wrapped key; atomic writes |
| Receipt photos | `receipts/` in app-private storage | Sealed with the device key (`.lps`) |
| Documents (warranties, policies, IDs) | `vault/` in app-private storage | Sealed with the device key; not included in backups |
| Bank SMS text | Only on drafts, redacted (no balances, links) unless the user keeps full text | Records-file encryption; "Forget stored message text" |
| Latest balance per account | Records file (one number per account, not the message) | Records-file encryption; "Forget" on the Available balance card |
| Backups | Files the user exports | PBKDF2-HMAC-SHA256 + AES-256-GCM with the user's password |

## Entry points and threats

| Entry point | Threat | Mitigation | Test |
|---|---|---|---|
| Restored backup | A crafted backup points a receipt or document at another app file (e.g. the records file), which LifePilot then reads, shares, encrypts or deletes | Every receipt and document file operation checks the path is directly inside its own folder and matches LifePilot's own file-name pattern (`safe_paths.dart`); others are ignored | `security_extras_test.dart` |
| Restored backup | A crafted document name escapes the share folder when a decrypted copy is made | Names reduced to a plain file name (`safeFileName`) | `security_extras_test.dart` |
| Restored backup | Invalid debts, investments, trips cause wrong maths or crashes | Validated on decode; the whole restore is refused and existing data kept | `security_extras_test.dart` |
| Imported or restored tax rules | Malformed rules give wrong tax, or crash the tax screen | Schema validation (ordered slabs, rates 0–100, whole rupees); every change shown as a diff before applying; invalid stored rules dropped on load | `tax_rules_test.dart`, `security_extras_test.dart` |
| Bank SMS | Scam messages, spoofed senders, balance tags flipping debit/credit | Known sender IDs, scam checks before parsing, balances stripped before deciding direction, drafts only (never auto-recorded) | `bank_sms_test.dart`, `sms_import_test.dart` |
| Statement files (CSV/Excel) | Huge or hostile files | Parsed in memory, file not kept, rows only become drafts after review; PDF and old `.xls` refused | `statement_import_test.dart` |
| Receipt OCR | Image or text sent off the phone | ML Kit on-device text recognition; no network use by LifePilot | — (device verification pending) |
| Sharing a document | Decrypted copies left in cache | Copies go to one cache folder that is emptied on every start | — |
| Shoulder surfing | Amounts visible in public | "Hide amounts" masks on-screen amounts and notification bodies; exports and assistant answers still show real amounts on purpose | `money_glance_test.dart` |

## Residual risks

- Decrypted shared copies exist in the app cache until the next start (Android may also keep a copy in the receiving app).
- Document files are not in backups; losing the phone loses them unless the originals are kept elsewhere (stated in the app).
- Bundled tax rules can go out of date; the app falls back to the latest year with a visible warning and lets the user import updated rules.
- OCR, statement import from real bank files, and SMS parsing of real messages still need verification on a device with real data.
