# M1.3 History picker and paste — design note

Date: 2026-11-04 — Size: large — new OS permission (posting key events), global shortcut, focus handling across apps, new UI — Phase: MVP — Status: draft, waiting for PM

## Context

Plan item M1.3 (`docs/PLAN.md`). M1.2 keeps clipboard history in an encrypted store and shows it in the main window. Today the user must open Kusunga, find an item, click Copy, go back to their app and press Cmd+V. M1.3 makes this one step: a global shortcut opens a small picker over the current app; the user types to search, presses Enter, and the item is pasted where they were typing. Distribution and sandbox: ADR 0003.

## Requirements and non-goals

- Functional:
  - A global shortcut opens the picker over the current app. Default Cmd+Shift+V (Mac) / Ctrl+Shift+V (Windows); the user can change it in the main window.
  - Typing filters the list (case-insensitive, matches anywhere in the text). Up/Down move, Enter pastes the selected item into the app that was in focus, Esc closes with no change. Cmd/Ctrl+1–9 paste the first nine results.
  - Works with keyboard only and with VoiceOver and Narrator.
  - If macOS has not allowed Kusunga to post key events, Kusunga explains why and how to allow it, and meanwhile copies the item and tells the user to press Cmd+V.
  - Windows: if the target app runs as administrator (Kusunga cannot send keys to it), Kusunga copies the item and tells the user to press Ctrl+V.
  - A shortcut already taken by another app is reported, and the user can pick another.
- Non-functional:
  - Picker visible within 150 ms of the shortcut (p95); item pasted within 300 ms of Enter (p95).
  - Search over 5,000 items in under 50 ms per keystroke.
  - No network, no content in logs (as M1.2).
- Non-goals: snippets in the picker (M1.4 adds a tab), typed shortcuts (M1.5), pasting images or rich text, a picker on mobile, a separate menu-bar popover.

## Top 3 qualities

| Quality | Target | How we check it |
|---|---|---|
| Correct target | The item is pasted into the app and field that had focus, never into Kusunga or another app | Real-app QA with 3 target apps (TextEdit, a browser, a terminal) and Windows CI unit tests of the focus logic |
| Speed | Picker ≤ 150 ms, paste ≤ 300 ms (p95); search ≤ 50 ms at 5,000 items | QA timing on the real app; a search benchmark test |
| Accessibility | Full keyboard path; VoiceOver/Narrator read the search field, result count and each row | Widget tests (semantics, guidelines) and a PM VoiceOver check |

## Estimate

Trivially small: one user; a few dozen picker opens a day; search over at most 5,000 items held in memory as previews (2,000 UTF-16 units each, at most about 20 MB).

## Data

- No new personal data stored. New settings in the `settings` table: `picker_shortcut` (a key combination string, validated), `paste_mode` (`auto` | `copy_only`). Schema version 2 adds nothing structural (settings are key/value); the migration runner records the version step anyway so later migrations stay in order. Test: v1 → v2 keeps every item.
- The previously focused app (Mac process id / Windows window handle) is held in memory only while the picker is open, then dropped. Never stored or logged.
- Search runs in Dart over the in-memory list (already loaded for the main window). Full text for the chosen item is read from the store only on Enter.

## Options

### A: One Flutter window with two modes (recommended)

The existing window switches between "manage" mode (today's history screen) and "picker" mode: a small, borderless, always-on-top window centred on the screen with the mouse pointer. Native code records the focused app before showing it, and after Enter hides the window, gives focus back, and posts the paste keystroke.

- Benefits: one Flutter engine, one store connection (no cross-engine database locking), reuses the history list, theme and tests.
- Costs: the main window cannot be open in manage mode while the picker shows (opening the picker hides manage mode; Esc restores it if it was open). Window resizing and position must be animated carefully to avoid a flash.
- Effort: medium.

### B: A second window with its own Flutter engine (`desktop_multi_window`)

- Benefits: the picker and manage window can both be open; picker window can be tuned separately.
- Costs: two Dart isolates each opening the encrypted database (SQLite locking, two keychain reads, double memory), or a message bridge between engines; a new dependency; more native glue on both OSes.
- Effort: high.

## Decision

A. B doubles the hardest parts (keychain, encrypted store) for a small benefit. Not hard to reverse, so no ADR beyond ADR 0003 for the sandbox and distribution.

## How paste works

Mac (Swift, inside the App Sandbox):
1. Shortcut via Carbon `RegisterEventHotKey` (needs no permission; works in the sandbox).
2. On the shortcut: remember `NSWorkspace.shared.frontmostApplication`; show the picker window and make Kusunga active.
3. On Enter: write the item's full text to the pasteboard, adding our own type `com.wnasoni.kusunga.self` so the watcher knows it is ours and only moves the item to the top; hide the picker; `activate()` the remembered app; wait until it is frontmost (poll every 10 ms, up to 500 ms); then, if `CGPreflightPostEventAccess()` is true, post Cmd+V with `CGEvent` to the session tap.
4. If posting is not allowed: the item stays on the clipboard; a small toast near the pointer says "Copied — press ⌘V to paste", and the main window shows the permission card next time it opens. `CGRequestPostEventAccess()` is called only when the user presses "Allow pasting" on that card (never on its own).

Windows (C++):
1. Shortcut via `RegisterHotKey` on the main window.
2. On the shortcut: remember `GetForegroundWindow()`; show the picker; Kusunga gets foreground because it handled the hotkey.
3. On Enter: write `CF_UNICODETEXT` plus our own registered format `com.wnasoni.kusunga.self`; hide; `SetForegroundWindow(remembered)`; confirm with `GetForegroundWindow()` (up to 500 ms); then `SendInput` Ctrl+V.
4. Before sending, compare integrity levels (`OpenProcessToken` + `TokenIntegrityLevel`). If the target is higher (admin), skip `SendInput` and show "Copied — press Ctrl+V to paste" (UIPI would block it silently).
5. If the remembered window is gone: copy only and show the same toast.

Shortcut conflicts: `RegisterEventHotKey` / `RegisterHotKey` fail if the combination is taken; Kusunga shows "That shortcut is used by another app. Choose another." and keeps the previous one.

Keys held down: before posting Cmd+V, wait until the user has released the picker's modifier keys (up to 300 ms) so the target app does not see Cmd+Shift+V.

## Failure plan

No network. Failure paths:

- Shortcut cannot be registered at start-up: tray menu item "Open picker" still works; banner in the main window "Kusunga's shortcut ⌘⇧V is used by another app. Choose another."
- Target app quit while the picker was open: copy only + toast.
- Focus not returned within 500 ms: copy only + toast; never post keys into Kusunga itself or an unknown app.
- PostEvent permission missing (Mac) or target is admin (Windows): copy only + toast.
- History still opening (keychain prompt) when the shortcut fires: picker opens with "Opening your history…" and the in-memory items; no wait on the keychain.
- Memory-only mode (M1.2): picker works from memory.

## Observability

Log codes only: `hotkeyRegisterFailed`, `pasteFocusTimeout`, `pastePermissionMissing`, `pasteTargetElevated`, `pasteTargetGone`. No content, no app names, no window titles. QA watches picker-open and paste latency.

## Trust boundaries and abuse cases

- Boundaries: (1) other apps receiving our synthetic keystroke; (2) the OS permission to post events; (3) the clipboard, which other apps can read after we write the item; (4) screen sharing and screenshots while the picker is visible.
- Abuse cases:
  - As a malicious app that steals focus right after the picker closes, I receive the paste so that I get the user's text — mitigation: post Cmd+V only after confirming the remembered app is frontmost; otherwise copy only.
  - As a malicious app, I fake Kusunga's own pasteboard marker so that my content is treated as Kusunga's and skips the secret check — mitigation: the "self" marker only causes "move to top" for text that is already in history (hash match); unknown text with the marker is treated like any other copy, with the secret check.
  - As someone watching the screen (or a screen recording), I see the picker list — mitigation: the picker shows previews only (one line each), nothing until the shortcut is pressed; a "hide previews when screen is shared" option is a Later line.
  - As a user in a password field, I paste with the picker — allowed (normal behaviour); the history never contains secret-marked copies in the first place (M1.2).
  - As an attacker with an admin window in front, I try to make Kusunga inject keys into it — mitigation: integrity check; Kusunga never sends keys to higher-integrity windows.
- New permission: PostEvent only (Mac). We never request Accessibility (ADR 0003).

## Privacy

Not legal advice. Items marked "PM decides" need the PM's decision before the developer starts.

| Field | Purpose | Lawful basis (PM decides) | Retention | Shared with | Notes |
|---|---|---|---|---|---|
| Picker shortcut, paste mode | Respect the user's settings | n/a — the data never leaves the device | Until the app data is deleted | None | Not personal |
| Which app had focus | Paste back into it | n/a — as above | In memory while the picker is open only | None | Never stored or logged |

- Fields removed: window titles and app names are never read for display or logs.
- DPIA screening: no new triggers beyond M1.2 (the short DPIA before the beta stands). The picker adds no new processing of content.
- Children likely: no. Automated decisions: none. Special category data: none new.
- New vendors / SDKs: none (native code only; no new pub packages planned).
- Private defaults: the permission is requested only when the user asks ("Allow pasting"); the picker shows nothing until the shortcut is pressed.
- Export, delete, rectify: unchanged from M1.2.
- Escalated to PM: default shortcut; whether the clipboard keeps the pasted item afterwards (decisions on the deck).

## Rollout and rollback

- Schema version 2 (version bump only). The migration runner keeps the `.bak` copy until success.
- Rollback: revert the merge. A v1 build seeing a v2 database runs memory-only with the "incompatible" banner and leaves the file untouched (M1.2 C1). Confirm by launching the old build: banner shows, file unchanged. To fully undo, the user updates again.
- CI: change the macOS job from `macos-latest` to a pinned `macos-15` runner label to reduce queueing (four cancelled runs in M1.2), with the reviewer checking the change.

## Later lines

- Hide previews in the picker while the screen is being shared or recorded — needs screen-capture detection — trigger: ≥ 5 beta users ask, or the M2 vault ships — noted 2026-11-04 by lead
- Mac App Store build — App Review risk for posting Cmd+V (ADR 0003) — trigger: ≥ 50 requests for an App Store version, or > 20% of website visitors leave at the download step — noted 2026-11-04 by lead
- Fuzzy (typo-tolerant) search — substring search is enough at 5,000 items — trigger: ≥ 10 beta users report "can't find" in feedback — noted 2026-11-04 by lead
