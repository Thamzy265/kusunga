# M1.7 Settings and expiry — design note

Date: 2026-11-10 — Author: lead — Status: approved by PM 2026-11-11 (D1 A, D2 A, D3 B, D4 B, D5 A)

UI spec: `docs/ui/settings-and-expiry.md` — Deck: `docs/slides/settings-and-expiry.html`

## Context

The plan lists M1.7 as small. The lead now sizes it **large**:
- it changes how long personal data is kept (auto-delete);
- it adds an OS integration on two platforms (launch at login);
- it moves controls across three screens.

Three of the five settings in the AC already exist:
- the history limit: the "Keep N items" field in the History tab (M1.2);
- the picker shortcut: "Change" in the History tab (M1.3);
- the ignore list: the Privacy tab (M1.6).

Two are new: auto-delete after a set time, and launch at login.

Facts from the code (main at 5bd2a6f):
- History rows are in `clip_items` with `created_at` and `last_copied_at`. A re-copy of the same text updates `last_copied_at` and keeps the row (`sqlite_history_store.dart` `insertOrBump`).
- `_trim` removes rows past the limit, oldest `last_copied_at` first, inside each write.
- `PRAGMA secure_delete = ON` is set on every open, so deleted text is overwritten in the file. The journal is the default rollback journal, not WAL, and the file is encrypted (ADR 0002).
- Snippets are in their own table and are never removed by the limit or by Clear history (M1.4 AC).
- Settings are integers in `settings(key, value)`, allowed keys in `HistoryStore.storedSettingKeys`. Schema version is 5.
- There is no launch-at-login code. The macOS deployment target is 12.0 (ADR 0003, M1.3). The app is sandboxed.

## Requirements and non-goals

Acceptance criteria (docs/PLAN.md):
- AC1: history limit, auto-delete after a set time (never / 1 day / 7 days / 30 days), shortcut, launch at login, ignore list.
- AC2: the most private choice is the default where there is one (for example launch at login off until the user turns it on).

Requirements:
- R1: an item is removed once its last copy is older than the chosen time. It never shows in History or the picker after that, even before the clean-up runs.
- R2: snippets are never removed by auto-delete.
- R3: changing to a shorter time that removes items asks first and says how many, like lowering the limit does today.
- R4: launch at login is off by default, and the switch always shows what the OS really has (the user can change it in System Settings or Task Manager).
- R5: when Kusunga starts at login, it starts in the menu bar or tray without opening its window.
- R6: all settings are in one place, so the user doesn't hunt for them (see D1).

Non-goals (this item):
- Auto-delete by item count per day, per-app expiry, or expiry for snippets.
- Expiry shorter than 1 day (for example 1 hour). Pause covers short private moments.
- Export and import of settings (M1.8).
- Windows installers and their own "start with Windows" option (M1.9).

## Top 3 qualities

1. **Privacy:** expired text is gone from the screen at once and from the file soon after; nothing is kept longer than the user chose.
2. **No surprise data loss:** an upgrade never deletes anyone's history on its own; a shorter time asks first.
3. **Truthful state:** the launch-at-login switch reflects the OS, not a copy in our database.

## Estimate

About 1.2× M1.6's Dart work and less native work: one Dart service, one migration, one Swift and one C++ bridge for login items, and a new Settings tab. Tests: expiry clock, migration, bridge fakes, UI states.

## Data

| Key (settings table) | Values | Default | Notes |
|---|---|---|---|
| `history_expiry_days` (new, schema v6) | 0 = never, 1, 7, 30 | See D3 | Integer like the other settings |

- Launch at login is **not stored**. The OS is the source of truth: `SMAppService.mainApp.status` on Mac, the `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value `Kusunga` on Windows.
- Migration v6 adds the key with `INSERT OR IGNORE`. The value depends on D3. Rollback: the key is ignored by older builds (they don't read it), so no down step is needed beyond deleting the row.

## Auto-delete

- **Which time counts (D2):** `last_copied_at`, so an item you copy again stays. This matches how the limit already picks the oldest.
- **Read filter:** every History and picker query adds `last_copied_at >= cutoff` while expiry is on. Nothing expired is shown, even if the clean-up hasn't run yet (R1).
- **Clean-up:** `DELETE FROM clip_items WHERE last_copied_at < cutoff`, in one write transaction:
  - at launch, after the migration;
  - every 15 minutes while Kusunga runs;
  - when the computer wakes and when Kusunga becomes active;
  - straight after the user picks a shorter time.
- `secure_delete` is already on, so deleted text is overwritten in the encrypted file.
- **Clock:** the cutoff is `now − days × 24 h` from the wall clock.
  - A clock set forward deletes early (the safe direction).
  - A clock set back keeps items longer until the clock is right; the read filter uses the same clock.
- **Shorter time:** count the rows that would go (`COUNT(*) WHERE last_copied_at < newCutoff`). If more than 0, show a confirm dialog built like the limit one (live count; Cancel keeps the old setting): "Delete items after 1 day? 143 older items will be deleted. Snippets aren't affected." At a count of 0 there is no dialog.
- **Longer time or Never:** no dialog; nothing is restored.
- **The limit still applies.** Both rules run; an item goes when either says so.
- **Pause:** auto-delete still runs while history is paused.

## Launch at login

- **Mac (macOS 13 and later):** `SMAppService.mainApp.register()` and `unregister()`. Status values:
  - `.enabled` → switch on;
  - `.notRegistered` → off;
  - `.requiresApproval` → switch on with the note "Allow Kusunga in System Settings › General › Login Items" and a button that calls `SMAppService.openSystemSettingsLoginItems()`;
  - `.notFound` or an error → switch off, note "Couldn't turn this on. Try again."
- Works inside the App Sandbox, with no helper app and no new entitlement.
- **Mac 12 (D4):** `SMAppService` needs macOS 13.
- **Windows:** write `"<full path to Kusunga.exe>" --login` to the HKCU Run value `Kusunga`; delete it to turn off. Per user, no admin rights.
  - While the switch is on, Kusunga rewrites the value at each launch, so a moved app keeps working.
  - Turned off in Task Manager: Windows sets `StartupApproved\Run` to disabled. Kusunga reads it and shows the switch off with the note "Turned off in Task Manager." Turning the switch on again writes the Run value, and the note says to allow it in Task Manager if it is still disabled. Kusunga never writes `StartupApproved`.
- **Starting hidden (R5):**
  - Windows: the `--login` argument.
  - Mac: `SMAppService` passes no argument. Kusunga checks the launch Apple event's `keyAELaunchedAsLogInItem`. If it can't be told reliably, the window opens as today. The developer reports which, and QA checks it.
- **Re-read the state** when the Settings tab opens and when Kusunga becomes active, so a change made in System Settings shows up.
- The channel gets two calls, `loginItemStatus` and `setLoginItem(bool)`. They carry no path or user data.

## Settings tab (D1)

A new **Settings** tab after Privacy, with two sections:

- **General:**
  - Launch at login (switch);
  - Picker shortcut (moved from History, the same control).
- **History:**
  - Keep (moved from History, the same field);
  - Auto-delete (a menu: Never / After 1 day / After 7 days / After 30 days);
  - a link "Ignored apps and pause are in Privacy".

The History tab header keeps its count line ("200 of 200 items") and the ⋯ menu. Tests that find the Keep field or Change on the History tab move to the Settings tab.

## Failure plan

| Failure | Behaviour | Log code |
|---|---|---|
| Clean-up delete fails (disk full, locked) | Items stay hidden by the read filter; retry at the next run; no user message unless it fails 3 runs in a row, then the warning banner "Couldn't remove old items. Kusunga will try again." | `historyExpiryFailed` |
| Saving a new auto-delete value fails | The menu goes back to the old value; "Couldn't save. Try again." under it | `settingSaveFailed` (new) |
| Login item call fails or needs approval | As above under Launch at login | `loginItemFailed`, `loginItemNeedsApproval` |
| Memory-only mode (keychain unavailable, M1.2) | Auto-delete still applies in memory; the setting resets at quit, with the existing "won't last" note | — |

## Observability

New log codes, with numbers only:
- `historyExpired <count>`;
- `historyExpiryFailed`;
- `settingSaveFailed`;
- `loginItemOn`, `loginItemOff`;
- `loginItemFailed <OS error number>`;
- `loginItemNeedsApproval`.

No text, no paths and no item ids. They are added to the Swift `knownCodes` list and the guard tests.

## Trust boundaries and abuse cases

- **Run key and login item:** other software running as the same user can already change these. Kusunga writes only its own quoted exe path. It never runs anything taken from the registry.
- **A clock set back hides nothing and leaks nothing:** items are just kept longer.
- **Someone at the unlocked computer turns auto-delete off:** that keeps more history. Visible in Settings; the same risk as the limit today.
- **Someone at the unlocked computer picks a shorter time:** this deletes history, after a confirm dialog. The same as Clear history today.
- **A crafted `history_expiry_days` value** (for example from M1.8 import later): only 0, 1, 7 and 30 are accepted; anything else means 0 with a log code.

## Privacy

Not legal advice.

| Field | Purpose | Lawful basis (PM decides) | Retention | Shared with | Notes |
|---|---|---|---|---|---|
| `history_expiry_days` | Remove history after the chosen time | Likely n/a, nothing leaves the device (plan D7) | Until changed | None | Encrypted file |
| Launch-at-login state | Start Kusunga at login | As above | Held by the OS, not by Kusunga | None | Not stored by Kusunga |

- This item reduces how long Kusunga keeps data. It adds no new personal data field.
- DPIA screening: no new trigger.
- Private defaults (AC2):
  - launch at login off;
  - auto-delete per D3.
- Privacy notice (M1.9): "History is removed after the time you choose in Settings."

## Decisions for the PM

| # | Decision | Options | Lead recommendation |
|---|---|---|---|
| D1 | Where do the settings live? | A: a new Settings tab, with Keep and the picker shortcut moved there; B: leave Keep and Change in History, add auto-delete next to Keep and launch at login in a new small Settings tab | A — one place for every setting (R6); Privacy keeps pause and the list |
| D2 | Which time starts the auto-delete clock? | A: the last time you copied it; B: the first time it was copied | A — something you keep copying is something you still use; it matches the limit |
| D3 | Default auto-delete | A: Never for everyone (today's behaviour); B: 30 days for new installs, Never for existing data; C: 7 days for new installs, Never for existing data | B — a limit on time by default for new users (AC2, privacy by default), without deleting anyone's existing history on upgrade |
| D4 | Launch at login on macOS 12 | A: raise the minimum macOS to 13 (ADR 0003 update); B: on macOS 12, show the switch off and disabled with "Needs macOS 13 or later" | B — no one is cut off now; revisit with the M1.9 minimum-macOS statement |
| D5 | When started at login, open the window? | A: no, start in the menu bar / tray only; B: open the window as today | A — a login start shouldn't put a window in front of the user |

Assumed unless the PM says otherwise: lawful basis n/a (nothing leaves the device); no ADR, because none of these choices is hard to reverse (D4 A would update ADR 0003).

## Rollout and rollback

- **Rollout:** ships with the normal build; migration v6 runs at launch.
- **Rollback:** revert the merge. Older builds ignore `history_expiry_days`. A login item registered by M1.7 stays registered after a rollback, so the rollback note tells the user to switch it off in System Settings or Task Manager first.

## Later lines (added to docs/PLAN.md 2026-11-11)

- Auto-delete after 1 hour — Pause covers short private moments — trigger: ≥ 5 beta requests — noted 2026-11-10 by lead
- Auto-delete per app — one global time covers personal use — trigger: ≥ 5 beta requests — noted 2026-11-10 by lead
