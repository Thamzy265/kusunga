# Data protection impact assessment (DPIA) — Kusunga desktop beta

Date: 2026-11-19 — Author: lead (draft) — Plan item: M1.9f — Status: **draft, waiting for the PM's decisions and sign-off** — app facts checked against main by a scout lookup, 2026-11-19

Not legal advice. This follows the ICO's DPIA template structure (UK GDPR Article 35). Privacy regions: UK and EU.

## 1. Why a DPIA

The PM decided on 2026-11-08 that a short DPIA is written before the first beta (M1.5 D6). Screening against the ICO list:

| ICO trigger | Hit? | Why |
|---|---|---|
| Innovative / new technology | Possible | Keystroke watching for typed shortcuts (M1.5) and background clipboard capture |
| Invisible processing | Possible | Kusunga reads every copy and, when typed shortcuts are on, keys typed in other apps |
| Large-scale profiling, special category at scale, tracking, data matching, children, denial of service, biometric, genetic, risk of physical harm | No | Nothing leaves the device; no profiling; not aimed at children |

## 2. The processing

### Who is the controller?

- **The app on a user's device:** Kusunga is software the user runs on their own computer. The data never leaves the device and the maker never receives it. For the user this is mostly personal or household use. The maker (the PM) decides how the software processes data, so this DPIA treats the maker as responsible for privacy by design (Article 25), whether or not it is a controller for on-device data.
- **The beta itself:** the PM is the controller for tester contact details and tester feedback.

### What the app processes (on the device only)

| Data | Source | Where it is kept | How long | Notes |
|---|---|---|---|---|
| Copied text and links, with the time copied | The clipboard, in the background | Encrypted SQLite file (SQLite3 Multiple Ciphers); key in the OS keychain (Mac) or Credential Manager (Windows) | Newest N items (default 200, user-set up to 5,000) and the user's auto-delete period | Copies the source app marks concealed, transient or auto-generated (Mac) or excluded from clipboard history and monitoring (Windows), and copies from ignored apps, are never kept; there is no setting to turn this off |
| Saved snippets (name, content, type, optional typed shortcut) | Typed by the user | Same encrypted file | Until the user deletes them | May hold third parties' details the user chose to save (household use) |
| Ignored apps list | Preset password managers plus the user's choices | Same encrypted file | Until removed | Can hint at which password manager or bank app the user has |
| Settings (limit, expiry, paste mode, shortcuts on, pause) | The user | Same encrypted file | Until changed or Delete everything | Not personal on their own |
| Typed characters (rolling buffer) | Keys typed in any app, only while typed shortcuts are on | Native memory only, at most 32 characters | Cleared after 5 s without typing and on every reset; never written, logged or sent to Dart | Secure input fields (Mac) and password fields (Windows `IsPassword`) are skipped |
| Source app of a copy, and front app at match time | The OS | Native memory only | One check (under 5 ms); never stored or logged | Used to apply the ignored-apps list |
| Error log | The app | A local log file | Rotated; small | Each line is a time, a fixed event code and an optional number (`lib/log/app_log.dart`, `DiagLog.swift`); no text, paths or app names |
| Export file | The user, on request | Where the user saves it | As long as the user keeps it | **Not encrypted** (PM decision M1.8 D1); history included only if the user ticks it |

No network use. No analytics, crash reports or telemetry (plan D3). No third-party SDK sends data.

### What the beta processes (PM as controller)

| Data | Purpose | Lawful basis | Retention | Shared with |
|---|---|---|---|---|
| Tester name and email | Invite testers, send builds and updates | **PM decides** (lead suggests consent, or legitimate interests for a small invited beta) | **PM decides** (lead suggests: delete when the beta ends) | Nobody |
| Tester feedback by email (D7 A) | Fix beta bugs | **PM decides** (lead suggests legitimate interests) | **PM decides** (lead suggests: 90 days after M1 ships) | Nobody; the email provider as the PM's processor |
| Download logs (testers' IP addresses) | Serving files | GitHub's own processing (GitHub Releases, D4 A) | GitHub's policy | GitHub |

Distribution: Apple notarisation and the Microsoft Store (D1 A) receive the app binary only, never user data. Testers who install through the Store have a relationship with Microsoft under Microsoft's own terms.

## 3. Consultation

- Testers: the beta guide explains what Kusunga captures and how to turn things off, and asks for feedback on it.
- No DPO is required for this project (no large-scale or systematic monitoring by the maker). Not legal advice; the PM may want a short legal check before a public release.

## 4. Necessity and proportionality

- **Purpose:** let the user paste again what they copied, and paste saved text with a shortcut. Each data item above is needed for that, and nothing else is kept (source app, paste counts and window titles were removed at design time).
- **Data minimisation:** history is capped (default 200); auto-delete is available; the typed-key buffer is 32 characters in memory for 5 s; secret-marked copies are never kept.
- **Private defaults:** typed shortcuts off until turned on; launch at login off (Kusunga never registers itself until the user turns it on); the password-manager ignore list on; secret-marked copies always skipped.
- **User rights:** the user controls everything locally: delete one item, clear history, Delete everything (including the key), export (portability), edit (rectify).
- **Transparency:** in-app permission explanations; the About section with the licence (M1.9a); a short privacy note in the beta guide (approved by the PM with the release).
- **No international transfer** from the app. The beta email and GitHub Releases are the only off-device processing.

## 5. Risks

Likelihood and severity: remote / possible / probable; minimal / significant / severe.

| # | Risk to people | Likelihood | Severity | Overall |
|---|---|---|---|---|
| R1 | Someone with access to the unlocked computer reads clipboard history (passwords, bank details, health information copied by the user) | Possible | Significant | Medium |
| R2 | Malware on the device reads the history file or the key | Possible | Severe | Medium |
| R3 | Keystroke watching captures passwords or private messages typed in other apps | Remote | Severe | Medium |
| R4 | The user does not realise Kusunga keeps what they copy (invisible processing) | Possible | Significant | Medium |
| R5 | An unencrypted export file is left in a shared or synced folder | Possible | Significant | Medium |
| R6 | Data is not fully deleted (backups, a second running copy on Windows) | Possible | Significant | Medium |
| R7 | A tester includes clipboard content or other personal data in feedback | Possible | Significant | Medium |
| R8 | A trojaned download is passed off as Kusunga | Remote | Severe | Medium |
| R9 | Special category data (health, beliefs) is copied by the user and kept | Probable | Significant | Medium |

## 6. Measures

| Risk | Measures | Effect | Residual |
|---|---|---|---|
| R1 | History capped and auto-delete available; the user can clear history or pause capture; the picker shows nothing until the shortcut | Reduced | Medium — Kusunga cannot protect against someone using the user's unlocked account |
| R2 | Encrypted at rest; key in the OS keychain; on Mac the key moves to the data-protection keychain bound to Kusunga's signing team (M1.9c, ADR 0007) | Reduced | Low |
| R3 | Off by default; native-only 32-character buffer cleared after 5 s; never stored, logged or sent to Dart (ADR 0004); secure-input and password fields skipped; ignore list; keys from other software ignored | Reduced | Low |
| R4 | Permission explanations; beta guide privacy note; pause and ignore controls; tray icon shows Kusunga is running | Reduced | Low |
| R5 | The export dialog says "The file isn't encrypted. Anyone who opens it can read it."; history only if chosen | Reduced | Medium — accepted by PM decision M1.8 D1 |
| R6 | Delete everything closes the database before deleting and removes the key, so backup copies cannot be read; partial deletion is shown to the user; single instance on Windows (M1.9d, PM W3 A) | Reduced | Low |
| R7 | Beta guide: never paste clipboard content in a report; feedback by private email (D7 A); retention limit (PM decides) | Reduced | Low |
| R8 | Notarised Mac builds and Store-signed Windows builds; SHA-256 list on the release page; signing keys only on the PM's Mac (ADR 0006) | Reduced | Low |
| R9 | Same as R1 and R2; data stays on the device; the user can delete it | Reduced | Medium |

## 7. Decisions and sign-off (PM)

| Item | Decision | Date |
|---|---|---|
| Lawful basis for tester contact details | **PM decides** | |
| Retention for tester contact details | **PM decides** | |
| Lawful basis for tester feedback | **PM decides** | |
| Retention for tester feedback | **PM decides** | |
| Feedback email address (D7 A) | **PM decides** | |
| Residual risks R1, R5 and R9 (medium) accepted | **PM decides** | |
| DPIA approved; the beta may go ahead on these terms | **PM signs** | |

Review this DPIA when: sync (M3), mobile (M4), any analytics or crash reports, or any data leaving the device is planned.
