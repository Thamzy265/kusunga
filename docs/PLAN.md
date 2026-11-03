# Kusunga plan

Phase: MVP. Approved by the PM on 2026-11-03 (deck: `docs/slides/mvp-plan.html`).

## Decided (PM, 2026-11-03)

- D1 tech stack: Flutter desktop UI + small native code (option A).
- D2 bank-details vault: its own milestone, M2.
- D3 crash reports and usage stats: none in M1.
- DPIA: a short DPIA before the beta (added to M1.9).
- Plan approved; M1.1 starts.
Research behind this plan: `docs/marketing/competitor-research.md`.

## Goal

One app that keeps your clipboard history and your saved snippets, and pastes them with a shortcut. Desktop (Mac and Windows) comes first, because only desktop allows full clipboard history. Mobile follows as a snippets keyboard with history synced from desktop.

## Open decisions (PM)

| # | Decision | Options | Lead recommendation | Needed before |
|---|---|---|---|---|
| D1 | Tech stack | A: Flutter desktop UI + small native code for clipboard, hotkeys and paste · B: Tauri (Rust + web UI) · C: fully native (Swift on Mac, C# on Windows) | A — one UI codebase that we can reuse for the mobile apps in M4; native code only where the OS needs it | M1.1 |
| D2 | Bank-details vault in the first release? | In M1 · Own milestone (M2) | M2 — it is the biggest privacy and security risk and needs its own design and review | M1 start |
| D3 | Crash reports and usage stats | None · Opt-in only, no clipboard content ever | None in M1; revisit with a trigger (see Later) | M1.1 |
| D4 | Product name "Kusunga" | Keep · Choose another | Keep, after a quick trademark and app-store name check | M1.9 |
| D5 | Code signing (Apple Developer Program, about £79/year; a Windows signing certificate) | Buy now · Buy before first beta | Before first beta (M1.9) — needed so Mac and Windows don't block the app | M1.9 |
| D6 | Pricing | Free core + one-off payment for sync · Subscription · Free | Free core + one-off sync unlock (users complain about Paste's subscription) | M3 |
| D7 | Lawful basis for any data that leaves the device | PM decides (likely contract for sync) | n/a in M1 — nothing leaves the device | M3 |

## M1 — Desktop MVP (Mac + Windows)

Everything stays on the device. No account, no server.

- [x] **M1.1 Project setup** — small. Repo, chosen stack, check command, CI on Mac and Windows, `qa-artifacts/` git-ignored.
  - AC: the check command runs on both OSes in CI and passes on an empty app that opens a window and a tray/menu-bar icon.
- [ ] **M1.2 Clipboard history capture** — large (new local data store, personal data).
  - AC: text and links copied in any app appear in history within 1 second.
  - AC: history keeps the newest N items; N is set in settings (default 200, range 10–5,000); the oldest item is removed when the limit is reached.
  - AC: duplicates move to the top instead of being saved twice.
  - AC: history is stored encrypted on disk, with the key in the OS keychain (Mac Keychain / Windows Credential Manager).
  - Brief note: save data safely on every exit path (tray Quit, Cmd+Q, Dock Quit, Windows logoff/WM_ENDSESSION), not only Dart's onQuit (reviewer note, 2026-11-03).
- [ ] **M1.3 History picker and paste** — large (OS permissions, UI).
  - Before start: ADR on macOS distribution channel (direct notarised vs Mac App Store) and App Sandbox, because synthetic paste and keystroke monitoring need Accessibility and are restricted in the sandbox (reviewer note, 2026-11-03).
  - AC: a global shortcut (default Cmd+Shift+V / Ctrl+Shift+V, changeable) opens a picker over the current app.
  - AC: type to search; arrow keys and Enter paste the item into the app that was in focus; Esc closes.
  - AC: the picker works with keyboard only and with a screen reader (VoiceOver, Narrator).
  - AC: if the Mac Accessibility permission is missing, the app explains why it is needed and how to grant it.
- [ ] **M1.4 Saved snippets** — large (new data store, personal data).
  - AC: create, edit, delete and reorder snippets with a name, content and type (phone, email, link, address, other).
  - AC: snippets show in the picker in their own tab, and pinning a history item turns it into a snippet.
  - AC: snippets are never removed by the history limit.
- [ ] **M1.5 Typed shortcuts** — large (keyboard monitoring, trust boundary).
  - AC: each snippet can have a shortcut such as `;email`; typing it in any app replaces it with the snippet.
  - AC: shortcuts do not fire in password fields or in apps on the ignore list.
  - AC: a single switch turns typed shortcuts off.
- [ ] **M1.6 Sensitive-content protection** — large (personal data).
  - AC: items marked concealed or transient by password managers (Mac `org.nspasteboard.ConcealedType` and related; Windows `ExcludeClipboardContentFromMonitorProcessing`) are never saved.
  - AC: an app ignore list (preset with common password managers and banking apps) stops capture from those apps.
  - AC: "Pause history" for 15 min / 1 h / until resumed, from the tray/menu bar.
- [ ] **M1.7 Settings and expiry** — small.
  - AC: history limit, auto-delete after a set time (never / 1 day / 7 days / 30 days), shortcut, launch at login, ignore list.
  - AC: the most private choice is the default where there is one (e.g. launch at login off until the user turns it on).
- [ ] **M1.8 Your data: export and delete** — small.
  - AC: export snippets (and optionally history) as a JSON file; import the same file.
  - AC: "Delete all history" and "Delete everything" remove all stored data and the keychain key.
- [ ] **M1.9 Signed installers and first beta** — large (release).
  - AC: a notarised Mac build and a signed Windows installer install and launch without OS security warnings.
  - AC: Hardened Runtime enabled for the macOS build (notarisation needs it).
  - AC: release notes and a rollback plan exist; the PM approves the release.
  - AC: a short DPIA is written in `docs/design/dpia.md` and the PM signs it off before the beta.

## M2 — Secure vault (bank details, IDs)

Needs its own design note, privacy section and deck before it starts.

- [ ] Vault for sensitive snippets: locked by Touch ID / Windows Hello, masked in the UI, never in history.
- [ ] Pasting a vault item marks it concealed and clears the clipboard after 30 seconds (setting).
- [ ] No card numbers or bank details ever leave the device in M2.

## M3 — Encrypted sync between devices

Needs its own design note, privacy section and deck. Decisions D6 and D7 first.

- [ ] Pair devices with a code; end-to-end encrypted; no account.
- [ ] Sync snippets and history; vault items sync only if the user turns it on.

## M4 — Mobile (iOS + Android)

Needs its own design note and deck. Mobile cannot record clipboard history in the background (iOS and Android rules).

- [ ] Snippets keyboard (iOS keyboard that does not need Full Access; Android keyboard).
- [ ] Save to Kusunga from the share sheet.
- [ ] History synced from desktop (after M3).

## Later

- Images and files in history — not needed for the core text use case — trigger: > 30% of beta users ask for it in feedback, or > 20 requests — noted 2026-11-03 by lead
- Linux desktop — small share of users — trigger: > 100 requests or > 5% of website visits from Linux — noted 2026-11-03 by lead
- Opt-in crash reports — not needed while the beta is small — trigger: > 200 active beta users — noted 2026-11-03 by lead
- Sharing snippets with a team — not part of the personal use case — trigger: > 20 requests from teams — noted 2026-11-03 by lead
