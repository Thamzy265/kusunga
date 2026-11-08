# M1.5 Typed shortcuts — design note

Date: 2026-11-08 — Size: large — keyboard monitoring in every app, a new trust boundary (keys typed in other apps, and keystrokes Kusunga posts into them), personal data (what the user types), a schema change and new native code on Mac and Windows — Phase: MVP — Status: draft, waiting for PM

## Context

Plan item M1.5 (`docs/PLAN.md`). M1.4 added saved snippets that the user pastes from the picker (⌘⇧V / Ctrl+Shift+V, then a tab switch, a search and Enter). For a snippet used many times a day, such as an email address, that is still several keys. M1.5 lets the user give a snippet a short code, such as `;email`. Typing the code in any app replaces it with the snippet.

ADR 0003 already planned for this. Kusunga stays in the App Sandbox and asks for two Mac permissions only: posting key events, which M1.3 already uses, and Input Monitoring for a listen-only event tap, which M1.5 adds. It never asks for the Accessibility API permission. Password fields turn on macOS "secure input", which stops event taps from seeing keys.

This is the most sensitive feature in M1. Kusunga sees every key the user types in every app. The design keeps what it sees as small, as short-lived and as hard to reach as possible.

## Requirements and non-goals

- Functional (ACs from the plan):
  - Each snippet can have a shortcut such as `;email`. Typing it in any app replaces it with the snippet.
  - Shortcuts do not fire in password fields or in apps on the ignore list.
  - A single switch turns typed shortcuts off.
- Also in scope:
  - **Shortcut rules:**
    - 2 to 32 characters, with no spaces or line breaks;
    - case-sensitive, so `;Email` and `;email` are different;
    - unique;
    - not the start of another shortcut, if PM decision D1 is A.
  - The editor checks each rule as the user types and says how to fix it.
  - The snippet list and the picker's Snippets tab show each shortcut. Picker search also matches it.
  - A "Typed shortcuts" section in the Snippets tab has the switch, a status line and the ignore list.
  - On Mac, an explanation comes before the Input Monitoring permission prompt, with a way to open System Settings.
  - Shortcuts never fire:
    - in Kusunga's own windows;
    - from keys sent by other software, if PM decision D5 is A;
    - in Windows apps running as administrator.
- Non-functional:
  - The key hook adds under 1 ms per key (p99) on the QA Mac and a Windows test PC.
  - The typed code is replaced within 150 ms (p95) for a snippet up to 1 KB.
  - No typed key, shortcut, snippet text or app name appears in any log, channel message or file. Logs hold codes only.
- Non-goals (each with a Later line below):
  - placeholders such as `{date}` or the cursor position;
  - undo with Backspace straight after a replacement;
  - per-app shortcut sets;
  - Chinese, Japanese and Korean input methods, and characters typed with dead keys (`´` then `e`);
  - apps running as administrator on Windows;
  - rich text.

## Top 3 qualities

| Quality | Target | How we check it |
|---|---|---|
| Privacy | Typed keys exist only in a native buffer of at most 32 characters. The buffer is in memory only and cleared after 5 s without typing, and on every reset event. No key crosses the Flutter channel, and none is logged or stored | Native unit tests of the buffer (size, idle clear, reset events); a source guard that the channel API has no key or text field; a log-code test; reviewer privacy check |
| Safety | A replacement never deletes text that isn't the shortcut. It never fires in a password field, an ignored app, Kusunga itself, an admin window, or from another program's keys | Native unit tests for each skip rule and each reset event; QA real-flow checks in TextEdit, a browser password field, Terminal with Secure Keyboard Entry, and an ignored app |
| Responsiveness | Under 1 ms per key in the hook; replacement within 150 ms (p95) | Native micro-benchmark in tests; QA timing from a screen recording |

## Estimate

Trivially small. One user types up to about 15 keys per second. There are at most 1,000 snippets, so at most 1,000 shortcuts of up to 32 characters each. Matching is a hash lookup of the buffer's last 2 to 32 characters on each key, which is at most 31 lookups. A replacement posts up to 32 Backspaces and one paste.

## Data

**Schema version 4** is one expand-only migration:

```sql
ALTER TABLE snippets ADD COLUMN shortcut TEXT
  CHECK (shortcut IS NULL OR (length(shortcut) BETWEEN 2 AND 32
         AND instr(shortcut, ' ') = 0 AND instr(shortcut, char(9)) = 0
         AND instr(shortcut, char(10)) = 0 AND instr(shortcut, char(13)) = 0));
CREATE UNIQUE INDEX idx_snippets_shortcut ON snippets (shortcut) WHERE shortcut IS NOT NULL;

CREATE TABLE ignored_apps (
  id INTEGER PRIMARY KEY,
  app_id TEXT NOT NULL UNIQUE CHECK (length(app_id) BETWEEN 1 AND 255),
  display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 100),
  preset INTEGER NOT NULL CHECK (preset IN (0, 1))
);
-- Seeded with the preset list (password managers); the developer checks each id.
INSERT INTO settings (key, value) VALUES ('typed_shortcuts_on', 0);
```

- `app_id` is the Mac bundle id (`com.1password.1password`) or the Windows executable name in lower case (`1password.exe`).
- The "not the start of another shortcut" rule is checked in the snippet service, in the same transaction as the save, because SQL can't express it. The store refuses a clash too.
- The preset rows can be removed. "Restore the preset list" puts them back.
- M1.6 reuses `ignored_apps` for history capture, so it isn't built twice.
- **Migration:** v3 → v4 adds a nullable column, an index, a table and a setting. Every existing snippet gets no shortcut. The M1.2 runner keeps the `.bak` until it succeeds. A v3 build seeing a v4 file runs memory-only with the "incompatible" banner, as before. A test checks that v3 → v4 keeps every history item, snippet, order and setting.
- **Not stored:** typed keys, how often a shortcut fires, or which app it fired in.

## Options

### A: Match in native code; keys never leave it (recommended)

- How it works:
  - The native hook keeps a rolling buffer of the last 32 typed characters.
  - Dart sends native a table of shortcut → snippet id. It sends no snippet text, and sends the table again after every change.
  - When the buffer ends with a shortcut and every skip check passes, native tells Dart one thing: "snippet id N matched, delete K characters".
  - Dart reads the snippet text and asks native to replace: K Backspaces, then the paste flow.
- Benefits:
  - Keys never cross into Dart, the channel, or anything a Dart log line could reach.
  - Each key is answered inside the hook, which is fast and keeps Windows from removing a slow hook.
- Costs:
  - The matcher is written twice, in Swift and C++, so it needs native tests on both.
  - The table is copied to native, a few KB.
- Effort: about 1.5× option B, because of the two native matchers and their tests.

### B: Send every key to Dart and match there

- How it works: the hook forwards every printable character to Dart over the channel, and Dart keeps the buffer and matches.
- Benefits: one matcher, in Dart, with the existing test setup.
- Costs and risks:
  - Every key the user types in every app crosses the channel. A Dart log line, an exception message or a debug tool can then expose a password typed where secure input is off. On Windows that is every password field.
  - The channel hop adds a few ms per key.
  - Windows removes a low-level hook that is too slow, so the hook can't wait for Dart.
- Effort: lower.

## Decision

Option A, recorded in ADR 0004 (`docs/adr/0004-typed-shortcut-matching-in-native-code.md`). It is hard to reverse, because the privacy promise in the UI copy depends on it. We give up a single shared matcher.

PM decisions D1 to D6 are open; see "Decisions for the PM".

## How it works

**Watching keys**

- **Mac:**
  - A listen-only `CGEventTap` for key-down and mouse-down events. It needs ListenEvent (Input Monitoring) and works inside the App Sandbox (ADR 0003).
  - Characters come from the event's Unicode string, so the keyboard layout is respected.
  - The tap is created only while the switch is on and Input Monitoring is granted.
- **Windows:**
  - `WH_KEYBOARD_LL` and `WH_MOUSE_LL` hooks on the runner's UI thread. They need no permission.
  - Characters come from `ToUnicodeEx` with the foreground thread's layout. Calling it must not change the dead-key state, which the developer checks.

**The buffer**

- The buffer holds at most 32 characters, which is the longest allowed shortcut.
- A key with a printable character is added. Backspace removes the last character.
- These reset the buffer to empty:
  - any mouse button press;
  - arrow keys, Home, End, Page Up and Page Down;
  - Enter, Tab, Escape and forward Delete;
  - any key held with ⌘ or Ctrl (on Windows also Alt, but not AltGr);
  - a change of the front app or window;
  - secure input turning on;
  - 5 s without a key;
  - the switch turning off;
  - a replacement.
- The mouse and navigation resets stop a false match after the cursor moved. For example: type `;em`, click elsewhere, type `ail`. Without the reset, Kusunga would delete the wrong 6 characters.

**Matching and skip rules**

On each added character, native checks whether the buffer ends with a shortcut. It skips the match, without clearing the buffer, when any of these is true:

1. Secure input is on (Mac). The tap gets no keys then anyway.
2. The front app is Kusunga, so the user can type `;email` in the editor.
3. The front app is on the ignore list.
4. The key was sent by software, not the keyboard, if D5 is A. On Mac the event's source process id isn't 0. On Windows `LLKHF_INJECTED` is set.
5. Windows: the front window belongs to a process running as administrator. Windows blocks our keys there anyway.
6. Windows: the focused field is a password field or can't be read. UI Automation `IsPassword` is checked only when a match happens, never on every key, with a 100 ms limit. "Can't tell" means don't fire.

**Replacing**

1. Check that the front app is still the one where the match happened. If not, cancel and send nothing.
2. Post K Backspaces, then write the snippet to the clipboard. The write is marked transient and concealed (Mac `org.nspasteboard.TransientType` and `ConcealedType`; Windows `ExcludeClipboardContentFromMonitorProcessing`), so other clipboard managers don't save it.
3. Post ⌘V or Ctrl+V with the M1.3 paste flow.
4. Then follow D2. If D2 is A, after 500 ms put back the previous clipboard text. If the previous clipboard held something other than text, leave the snippet there; Kusunga only handles text.
5. Kusunga's own posted keys carry a marker (Mac `eventSourceUserData`; Windows `dwExtraInfo`), so the hook never feeds them back into the buffer.
6. Kusunga's own clipboard writes are skipped by the history watcher using the M1.4 change-number check. A typed shortcut never adds to history, as decided for the picker in M1.4 D1.

**Dart side**

- `ShortcutService` keeps the table in step with the snippets and holds the switch setting.
- It shows the status: on, off, needs permission, paused by secure input, couldn't start.
- On a match it reads the snippet text and calls the native replace.
- The channel API has exactly these calls:
  - `setTable(entries: [{id, shortcut}])`;
  - `setIgnored(appIds)`;
  - `setEnabled(bool)`;
  - `status()`;
  - `replace(deleteCount, text)`;
  - the event `matched(snippetId, deleteCount)`.
- No call carries typed characters.

## Failure plan

No network, so there are no outbound calls.

- **Input Monitoring not granted (Mac):** the switch stays on, but the status says "Needs Input Monitoring". The **Open System Settings** button opens Privacy & Security > Input Monitoring. Kusunga checks again when its window becomes active and starts the tap once permission is given. It never asks for the permission silently.
- **The tap is turned off by macOS** (`kCGEventTapDisabledByTimeout` or `ByUserInput`): turn it back on once and log `shortcutTapReenabled`. If that fails, show "Typed shortcuts stopped. Turn them off and on again." and log `shortcutTapFailed`.
- **Secure input is on for a long time** (for example Terminal's Secure Keyboard Entry): the status says "Paused while another app protects your typing". Nothing is lost.
- **Windows hook can't be installed:** show "Couldn't start typed shortcuts." and log `shortcutHookFailed` with the error code.
- **The front app changes between the match and the replacement:** cancel and send nothing (`shortcutCancelled`).
- **The paste fails** (no paste permission or the target app is gone): this uses the M1.3 fallback. The Backspaces have already been sent, so the code is gone. Kusunga leaves the snippet on the clipboard and shows the M1.3 toast "Copied. Press ⌘V to paste." Nothing is lost.
- **Memory-only or incompatible database:** snippets can't be read, so typed shortcuts are off. The status says "Typed shortcuts are off because snippets can't be opened right now." The switch is disabled.
- **Saving a shortcut fails** (clash, or disk error): the editor keeps the text and shows the reason under the field.

## Observability

Log codes only, with no keys, shortcuts, snippet text or app names:

- `shortcutFired`
- `shortcutCancelled`
- `shortcutSkippedIgnoredApp`
- `shortcutSkippedPassword`
- `shortcutSkippedUnknownField`
- `shortcutSkippedInjected`
- `shortcutSkippedAdmin`
- `shortcutTapReenabled`
- `shortcutTapFailed`
- `shortcutHookFailed`
- `shortcutPermissionMissing`
- `shortcutTableSize` (a number)

The two numbers to watch in QA are the hook time per key and the time to replace.

## Trust boundaries and abuse cases

- **Boundaries:**
  - keys typed in other apps, which may include passwords and personal text;
  - keys and mouse events sent by other software;
  - the front app's identity (bundle id or exe name), reported by the OS;
  - Kusunga's own posted keys and clipboard writes, which go into another app;
  - the shortcut and snippet table sent from Dart to native.
- **Abuse cases:**
  - "As another program on the computer, I send `;bank` into my own window so that Kusunga pastes the user's bank details where I can read them."
    - Mitigation: keys sent by software are ignored (D5 A), and the snippet's clipboard write is marked concealed.
  - "As malware with the user's permissions, I read Kusunga's memory or logs to get recent keystrokes."
    - Mitigation: the buffer is 32 characters at most, cleared after 5 s, and native only. Nothing is logged. There are no crash reports (D3). Malware that can read our memory could also run its own keylogger, so we don't defend further.
  - "As a web page, I make the user type something that matches a shortcut so that a snippet is pasted into my form."
    - Mitigation: only the user's own typing fires, and the user chose the shortcut. A leading symbol such as `;` makes accidental matches unlikely; the editor suggests it.
  - "As an attacker who can edit the database file, I add a shortcut such as `e` that deletes text as the user types."
    - Mitigation: the file is encrypted with a key in the keychain (ADR 0002). The CHECK constraint and native code both refuse shortcuts outside the rules.
  - "As a password field on Windows without secure input, I receive a snippet when the user types a shortcut by habit."
    - Mitigation: the UI Automation `IsPassword` check fails closed.
  - "As a remote-desktop or screen-sharing viewer, I see the snippet pasted."
    - Out of scope. The user chose to paste. The hidden-preview Later line covers the picker.
- **For the reviewer:** a source guard that no Swift or C++ log call, `print` or channel message has the buffer or a typed character in its arguments.

## Privacy

Not legal advice. Items marked "PM decides" need the PM's decision before the developer starts.

| Field | Purpose | Lawful basis (PM decides) | Retention | Shared with | Notes |
|---|---|---|---|---|---|
| Typed characters (rolling buffer) | To notice a shortcut as the user types it | PM decides. Likely n/a: it never leaves the device and isn't stored, as in plan D7 | At most 32 characters, in memory, cleared after 5 s without typing and on every reset; never written | None | Includes passwords where secure input or `IsPassword` doesn't apply. That's why it stays native-only |
| Snippet shortcut (`snippets.shortcut`) | To know which snippet to paste | PM decides. Likely n/a, as above | Until the user removes it or deletes the snippet | None | Optional; in the encrypted file; delete and rectify in the editor; export in M1.8 |
| Ignored apps (`ignored_apps`) | To stay quiet in sensitive apps | PM decides. Likely n/a, as above | Until the user removes it | None | Can show which password manager or banking app the user has; in the encrypted file |
| Front app id at match time | Skip rules | n/a, not kept | Used for that one check and not kept | None | Never logged |

- **Fields removed:** how often each shortcut fires, and which app it fired in. There's no use for either.
- **DPIA screening:** possible hits on "invisible processing" (Kusunga sees keys typed in other apps) and "new technology". The processing is on the user's own device, for them, and nothing leaves it. The PM must decide whether this needs a DPIA now or goes into the M1.9 DPIA (D6).
- **Children likely:** no. It's a productivity tool for adults; no change from M1.
- **Automated decisions or profiling:** none.
- **Special category data:** not collected. Snippets may hold it if the user types it in, as in M1.4.
- **New vendors, SDKs or transfers:** none. UI Automation and CGEventTap are part of the OS.
- **Private defaults:** typed shortcuts are off until the user turns them on (D3). No shortcut is set on any snippet by default. The ignore list starts with the preset password managers.
- **Export, delete, rectify:** shortcuts are edited and removed in the snippet editor, and deleting a snippet removes its shortcut. "Delete everything" (M1.8) removes them, and M1.8 export includes them. The buffer needs no delete; it clears itself.
- **Marketing consent:** n/a.
- **Record of processing and privacy notice:** add "typed-shortcut detection (on device, nothing stored)" to the privacy notice planned for M1.9, in plain words. The permission explanation in the app says the same.
- **Escalated to PM:** lawful basis (likely n/a), DPIA timing (D6), and the on-device keystroke monitoring itself.

## Rollout and rollback

- **Order:**
  1. Migration v4 and the editor field, with the switch hidden.
  2. Native buffer and matcher with unit tests, Mac first and then Windows.
  3. Replacement.
  4. The switch, the status and the ignore list.
- No feature flag is needed past MVP, because the switch is off by default (if D3 is A).
- **Rollback:** revert the merge. A v3 build that opens a v4 file runs memory-only with the "incompatible" banner and never changes the file (M1.2 C1). To roll back data too, the `.bak` from the migration is kept until the next successful start. QA confirms by opening a v4 file with the v3 build and checking that the banner shows and the file is unchanged.
- **Windows:** the developer can only compile and unit test the Windows runner in CI, which needs GitHub billing. Until then, Windows is built but not run (F5).

## Later lines

- Snippet placeholders — already in Later (M1.4).
- Undo a replacement with Backspace straight after it — not needed to paste fixed text — trigger: ≥ 10 beta requests, or ≥ 5 reports of an unwanted replacement — noted 2026-11-08 by lead
- Per-app shortcut sets (a shortcut only in some apps) — one global set covers personal use — trigger: ≥ 10 beta requests — noted 2026-11-08 by lead
- Shortcuts typed with input methods (Chinese, Japanese, Korean) and dead keys — shortcuts are usually ASCII such as `;email` — trigger: ≥ 5 beta reports of a shortcut that won't fire — noted 2026-11-08 by lead
- Shortcuts in Windows apps running as administrator (needs a separate elevated helper) — rare for personal use, and an elevated helper is a large security change — trigger: ≥ 5 beta reports — noted 2026-11-08 by lead
- Accept keys from on-screen keyboards and remote-desktop tools (only if D5 is A) — these are ignored for safety — trigger: ≥ 5 beta reports from users of on-screen keyboards or remote desktops — noted 2026-11-08 by lead

## Decisions for the PM

| # | Decision | Options | Lead recommendation |
|---|---|---|---|
| D1 | When does a shortcut fire? | A: As soon as its last character is typed. A shortcut may not be the start of another one · B: After the next space, Tab or Enter | A — fastest and most predictable. The rule is checked in the editor |
| D2 | What is on the clipboard after a typed shortcut? | A: What was there before; Kusunga puts it back after 0.5 s · B: The snippet, as with the picker · C: Type the text as keystrokes, without the clipboard | A — a shortcut shouldn't quietly replace what the user copied. C is slow for long text and breaks in some apps |
| D3 | Are typed shortcuts on or off for a new user? | A: Off until the user turns them on · B: On once a shortcut exists and permission is given | A — the most private default. Keyboard watching should be a clear choice |
| D4 | Ignore list in M1.5 | A: Build it now, with password managers preset, and M1.6 reuses it for history · B: Password fields only now, and the ignore list waits for M1.6 (the AC changes) | A — it's in the AC and the same list serves M1.6 |
| D5 | Keys sent by other software (on-screen keyboards, remote desktop, automation tools) | A: Ignored, so no other program can trigger a snippet · B: Accepted | A — stops another program from pulling out a saved snippet. Later line for the users this affects |
| D6 | DPIA for keystroke watching | A: Add it to the short DPIA already planned for M1.9, before the beta · B: Write a short DPIA now, before the developer starts | A — nothing leaves the device and there are no outside users before M1.9. The privacy section above is the screening |

Also for the PM: the lawful basis, which is likely n/a while nothing leaves the device, as in plan D7.
