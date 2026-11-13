# M1.8 Your data: export and delete — design note

Date: 2026-11-12 — Author: lead — Status: approved by PM 2026-11-12 (D1 A, D2 A, D3 A, D4 A, D5 A, D6 A)

UI spec: `docs/ui/your-data.md` — Deck: `docs/slides/your-data.html`

Lead rulings during the build (2026-11-12), within the PM's approved options: G1 which settings travel; G2 Import is off while history isn't saved; G3 a debug profile leaves launch at login alone; G4 where "Checking the file…" and the refused message show; G5 imported history keeps its times (and, by R9 of 2026-11-13, never changes an item already shown); G6 no extra clean-up at the next launch; and the Delete everything order. Each is written into the sections below.

## Context

The plan lists M1.8 as small. The lead sizes it **large**:
- **Export:** it writes personal data (snippets, and history if chosen) out of the encrypted file into a file the user picks. That is a new place the data lives, outside Kusunga's control.
- **Import:** it reads a file the user picks, which is a new trust boundary. The file may be damaged or crafted.
- **Delete everything:** it removes the keychain key. No code does that today, and the result can't be undone.

Facts from the code (main at 914b75b, scout lookup):
- **Data:**
  - Snippets are in table `snippets`: id, name (1–100 characters), content, type (phone / email / link / address / other), position, created_at, updated_at, and `shortcut` (unique, v4).
  - History is in `clip_items`; settings are in `settings(key, value)`; the ignore list is in `ignored_apps(app_id, display_name, preset)`. Schema v6.
  - Clear history already exists (History ⋯ menu): `DELETE FROM clip_items`, then it removes `kusunga.db.bak` and `kusunga.db.unreadable-*`. `secure_delete` is on. There is no VACUUM.
- **Key:**
  - The DB key is in the login keychain on Mac (`flutter_secure_storage`, account `com.wnasoni.kusunga`, entry `history_db_key`).
  - On Windows it is in Credential Manager (`com.wnasoni.kusunga/history_db_key`, through Dart FFI).
  - `KeyStore` has read and write only, with no delete. The Windows vault has a delete method, used only in tests.
- **Files Kusunga writes** (app support folder):
  - `kusunga.db` and its `-wal` / `-shm` files, `kusunga.db.bak` and `kusunga.db.unreadable-*`;
  - `kusunga.log` and `kusunga.log.1`;
  - debug builds only: `profiles/<name>/`.
- **No file dialogs today.** There is no file-picker package, and the Mac sandbox has no `user-selected` file entitlement.
- **No JSON code today.**
- **Memory-only mode** (keychain unreachable) keeps history in `MemoryHistoryStore`, with a banner.

## Requirements and non-goals

Acceptance criteria (docs/PLAN.md):
- AC1: export snippets (and optionally history) as a JSON file; import the same file.
- AC2: "Delete all history" and "Delete everything" remove all stored data and the keychain key.

Requirements:
- **R1:** export writes only what the user chose, only to the file the user picked, and says plainly that the file is not encrypted (see D1).
- **R2:** import never runs or opens anything from the file. It accepts only Kusunga's own format, checks every field against the same rules the app uses, and rejects the whole file if it is damaged. Nothing is half-imported.
- **R3:** import never overwrites or deletes existing data (see D3).
- **R4:** Delete everything leaves nothing readable behind. The key goes first, so even a file that can't be removed can no longer be decrypted.
- **R5:** every destructive action asks first, says exactly what goes, and puts focus on Cancel.
- **R6:** export, import and delete work the same on Mac and Windows, and in memory-only mode where it makes sense.

Non-goals (this item):
- An encrypted export protected by a password (see D1; Later line).
- Import from other clipboard apps (Paste, Maccy, Ditto). Later line.
- Sync between devices (M3) and cloud backup.
- Automatic backups.

## Top 3 qualities

1. **Privacy:** the user decides what leaves the encrypted file, and is told the export is readable by anyone who opens it.
2. **Safety:** a damaged or crafted file changes nothing, and nothing is deleted without a clear question.
3. **Completeness:** Delete everything really is everything, including the key.

## Estimate

About 0.8× M1.7. The work:
- a JSON format with a validator;
- export, import and delete services;
- a key delete on both platforms;
- file dialogs (a new package and a Mac entitlement);
- a "Your data" section in Settings.

Tests: format round trip, validator abuse cases, delete order, UI states.

## Export file

- **Format:** JSON, UTF-8, saved as `kusunga-export-YYYY-MM-DD.json` by default.
  ```json
  {
    "format": "kusunga-export",
    "version": 1,
    "exported_at": "2026-11-12T09:30:00Z",
    "snippets": [
      {"name": "Phone", "content": "…", "type": "phone", "shortcut": ";ph", "position": 0}
    ],
    "history": [
      {"content": "…", "kind": "text", "created_at": "…", "last_copied_at": "…"}
    ],
    "settings": {"history_limit": 200, "history_expiry_days": 30, "typed_shortcuts_on": 0},
    "ignored_apps": [{"app_id": "com.agilebits.onepassword7", "display_name": "1Password 7"}]
  }
  ```
- **Contents:**
  - `history` is present only when the user ticks "Include history" (D2).
  - `settings` and `ignored_apps` are present per D5. The settings are exactly `history_limit`, `history_expiry_days`, `typed_shortcuts_on` and `paste_mode` (lead ruling G1).
  - The picker shortcut, the pause (`history_paused_until`) and launch at login are **not** exported: the shortcut is per machine, the pause is a state rather than a setting, and the OS holds launch at login.
- **Writing:**
  - Kusunga writes the export to a temporary file next to the target and renames it, so a failed export never leaves half a file. Where that temporary file can't be made (the Mac sandbox allows only the file the user picked), it writes the picked file directly and removes it again if the write fails.
  - **The temporary file can't be planted (T7):**
    - its name is `<picked name>.kusunga-tmp-<32 random hex digits>` (128 bits from a secure random source);
    - it is made with `O_CREAT | O_EXCL`, which fails if anything is already at that name, including a link;
    - it is opened without truncating and written only once it is known to still be a plain file, so it is never written through a link.
  - **A direct write never follows a link either:** if the picked path is a link, the export fails with "Couldn't save the export. Try again."
  - **Leftovers:** plain temporary files that an earlier export to the same path left behind (a crash while writing) are removed. Only Kusunga's own names count, including `<picked name>.kusunga-tmp` from builds before T7. Links are never followed or removed.
  - It never writes to any other path.
- **Size:** at most 5,000 history items (the limit's maximum) plus every snippet. No cap is needed on export.
- **The file is not encrypted** (D1). The dialog says so before the save dialog opens.

## Import

- The user picks a `.json` file.
- **Kusunga refuses the whole file** when:
  - it is over 20 MB;
  - it isn't UTF-8 JSON;
  - `format` isn't `kusunga-export`, or `version` is higher than Kusunga knows;
  - any item breaks the app's own rules:
    - name 1–100 characters;
    - type in the list;
    - content within the history item size limit, and history text that isn't blank (capture's own rule, T1);
    - no text with half a character (a lone UTF-16 surrogate) in a name, content, history item or ignored app. UTF-8 can't store it, so what was saved would differ from the file (T2);
    - shortcut valid under the M1.5 rules;
    - timestamps in the one form Kusunga writes (UTC, `2026-11-12T09:30:00.000Z`, with the fraction optional), naming a moment that exists: no 31 February or month 13 (T9);
    - a `created_at` or `last_copied_at` no more than 24 hours after the import time (lead ruling 2026-11-12). The check runs when the file is checked, against the clock at that moment. Such an item would sort first and never expire. This rule and the next one need the import time, so they run right after the file is decoded (`checkImportTimes`), not inside the decoder;
    - settings values are allowed values (the same checks as M1.7), and whole numbers where the setting is a number: 1.0 is refused (T3);
    - app ids are under 255 characters.
- Unknown fields are ignored. Nothing in the file is run, opened or followed as a path.
- **Where import is offered (lead ruling G2):** only while history is saved. In memory-only, incompatible and backup-failed sessions the Import… button is disabled, with the line "Import isn't available right now, because history isn't being saved."
- **Merge (D3):**
  - Snippets are added after the existing ones. A snippet with the same name and content as an existing one is skipped.
  - If an imported shortcut is already used, the imported snippet is added without a shortcut, and the summary says how many.
  - History items keep the file's times (lead ruling G5). A `last_copied_at` earlier than its `created_at` is stored with `created_at` set to `last_copied_at` (lead ruling 2026-11-12). An item already shown is left exactly as it is (lead ruling R9, 2026-11-13): its last copy, its creation time and its place in the list don't change, and it counts as already here. The summary says "{n} history {item was/items were} already here.", so duplicates never double. Only a hidden, expired item that comes back is revived the way Undo does (the newer last copy and the older creation time), and it needs room like a new item. Items already older than the current auto-delete time are not added; the confirm count shows only the items that will be added, and the summary says how many were left out.
  - **An import never deletes history (R1, PM decision "Never remove", 2026-11-13).** "Nothing you have now will be changed or removed" stays true:
    - imported items fill only the free room under the limit (the limit minus the items shown now), newest imported first. The rest are not added, and the summary says "{n} history {item/items} didn't fit under your history limit and {wasn't/weren't} added." Nothing is trimmed at the end of an import;
    - a text already shown is left as it is and needs no room (R9). A text that would bring back an item already hidden by auto-delete needs a place, like a new one;
    - with "Also use the settings in this file" ticked, the file's history limit is not applied if it is lower than the number of items shown, and its auto-delete time is not applied if it would delete an item shown now. Items already hidden by the auto-delete time in use don't count, because they go at its next clean-up anyway. The other settings and the ignored apps still apply. The summary then says "Your history limit and auto-delete weren't changed, because that would delete items. Change them in Settings.", or names only the one kept: "Your history limit wasn't changed, because that would delete items. Change it in Settings." or "Your auto-delete time wasn't changed, because that would delete items. Change it in Settings." (lead copy, 2026-11-13);
    - the room, and which auto-delete time decides "too old", follow what is really applied, so the confirm counts with and without the tick match what the import does.
  - **History counts are items, not file lines (T4).** The confirm text, the toast and `dataImportedHistory` count the items the import adds. A line that repeats another line or matches an item already shown adds none, and neither does one that doesn't fit (R1). Kusunga works out the confirm count by running the import in a transaction that it always rolls back, so the count matches what the import will do. It runs it twice: with and without the file's settings. The confirm text follows the "Also use the settings in this file" tick box, because the file's limit and auto-delete time can change the count. With the box ticked and the file's auto-delete time applied, items older than it count as too old, not as added. If the count can't be worked out (more than 1,000 snippets, or a write error), the confirm shows the items not older than the auto-delete time, as before, and the import then fails with "Couldn't import. Nothing was changed."
  - "This file has nothing to import." shows when no snippet and no history item would be added, with or without the settings, and the file has no settings or ignored apps either.
  - **A settings-only file can be imported (lead ruling R4, 2026-11-13).** When nothing else would be added but the file has settings or ignored apps, the confirm reads "This file has settings and ignored apps, but no snippets or history." It shows the "Also use the settings in this file" tick box, and Import works only when the box is ticked. When an import adds nothing but applies the file's settings or ignored apps, the toast begins "Imported the settings and ignored apps in this file." instead of "Imported 0 snippets and 0 history items.", followed by every sentence that applies (lead ruling R8, 2026-11-13).
  - Settings and ignored apps from the file are applied only if the user ticks "Also use the settings in this file" (D5). They take effect at once: the limit, auto-delete, typed shortcuts, the paste mode and the ignore list. A limit or auto-delete time that would delete items is not applied (R1, above).
  - Ignored apps are added; none are removed or renamed. An id that is one of the presets comes back marked as a preset.
  - A file that would take the snippets past 1,000 fails as a write failure: "Couldn't import. Nothing was changed."
- **One transaction:** the whole import is one write transaction. If anything fails, nothing changes.
- **Confirm before import:**
  - Text: "Import 12 snippets and 340 history items? Nothing you have now will be changed or removed."
  - Then a summary toast: "Imported 12 snippets and 340 history items. 2 snippets were already here. 1 shortcut was already used, so that snippet has none."
- **While history is paused:** imported history items are still added (the user chose them). Ignored apps don't filter imported items.

## Delete all history and Delete everything (D4, D6)

- **Delete all history:**
  - This is today's Clear history (M1.2), offered again in the "Your data" section, with the same dialog and behaviour.
  - It keeps snippets, settings and the key.
  - It adds a `VACUUM` after the delete, so the file shrinks and freed pages are gone, not only zeroed.
- **Delete everything**, in this order (changed by the lead's ruling of 2026-11-12, so a failed key delete leaves Kusunga recording as before):
  1. Stop capture and timers.
  2. Delete the keychain key (Mac: the keychain entry; Windows: the credential). From this step on, the data can't be read. If the keychain refuses, start capture and timers again and stop here: nothing was deleted. If it doesn't answer in time, see "If the keychain doesn't answer" below.
  3. Close the database. Copies still waiting to be saved are dropped, not written.
  4. Write `deleteEverythingDone`, stop the log file, then delete the remaining files:
     - `kusunga.db`, `-wal`, `-shm`, `.bak` and `.unreadable-*`;
     - `kusunga.log` and `kusunga.log.1`;
     - debug only: the active profile folder.
  5. Turn launch at login off (D6).
  6. Kusunga shows "Everything is deleted. Kusunga will now quit." and quits. The next launch is a fresh start: a new key, an empty file and default settings.
- **If the key delete fails:** stop and delete nothing, show "Couldn't delete everything. Nothing was deleted. Try again.", and log `deleteEverythingFailed <errno>`.
- **If the keychain doesn't answer (T5, lead ruling 2026-11-12):** a keychain call that runs out of time can't be cancelled, so it may still remove the key later. Kusunga must never start recording again while that can happen. Each step below waits at most 30 s, so it takes at most 90 s in all:
  1. After 30 s, Kusunga reads the key again.
  2. **The key is gone:** the deletion carries on (close the database, then delete the files).
  3. **The key is still there, or the read fails:** capture stays stopped, and Kusunga waits for the outstanding call once more.
     - If the call succeeds, the deletion carries on.
     - If it refuses, Kusunga shows "Nothing was deleted" and starts recording again, as above.
  4. **No answer at all:** nothing is deleted or closed, and capture stays stopped for the rest of this run. Kusunga logs `deleteEverythingFailed` with no number, and shows "Kusunga couldn't confirm whether its key was deleted, so it has stopped recording and will now quit. Open Kusunga again. If your snippets and history are still there, try Delete everything again." Its only button is OK, which quits (Escape does the same). Quitting means nothing can start recording again while the old call is still running.
  5. **A late success stands:** if the call removes the key after that, the key is not written back, because the user asked for it to go (lead ruling B). The next launch handles a file with no key as in G6.
  - In memory-only mode the key delete is tried once. A time-out is logged and the rest goes on, because that session never opened the file with this key.
- **A folder that can't be listed (T6), or a data or profile folder that is itself a link (T8):** Kusunga never follows the link. Nothing in the folder it points to is deleted, and the link itself stays. Either way the folder counts as one file not removed, so the partial message below shows, never "Everything is deleted." It is logged as `deleteFileFailed`, with the OS error number when there is one. A data folder that isn't there at all has nothing left in it.
- **If a file delete fails after the key is gone:** carry on with the others, then show "Everything is deleted. 1 file couldn't be removed, but it can't be read any more." The next launch already handles a file with no key (lead ruling G6): it makes a new key, moves the old file aside as unreadable and shows the banner once; the next Clear history or Delete everything removes it.
  - **Only when that is true (lead ruling R7a, 2026-11-13).** "…but {it/they} can't be read any more" is said only when every file left is an encrypted database file and the key is gone. The encrypted files are `kusunga.db`, `-wal`, `-journal`, `.bak` and `.unreadable-*`. Otherwise Kusunga says "Everything is deleted. {n} {file/files} couldn't be removed." That covers:
    - anything else left: `kusunga.log` or `kusunga.log.1`; `kusunga.db-shm`, which is only the WAL's index and isn't encrypted; a link it couldn't remove; or a folder that couldn't be listed or is a link (T6, T8);
    - a memory-only session where the key delete failed, because the key may still be there.
  - A debug data profile keeps its own wording (T10).
- **In a debug data profile:** only the profile's own folder is deleted. The key is shared with the real history, so it is never deleted, and launch at login (which may be the real app's) is left alone (lead ruling G3). A rejected profile switch (memory only) deletes nothing on disk.
  - **Files left in a profile (T10):** a file the profile couldn't remove can still be read, because the key stays, so the partial message there doesn't claim it can't be read. It reads "Everything is deleted. {n} {file/files} in this test profile couldn't be removed." (lead's wording, 2026-11-12). The default data keeps its own partial message. A profile with nothing left shows the usual "Everything is deleted. Kusunga will now quit."
- **Memory-only mode:** the memory store is emptied, every file that exists is deleted, the key delete is attempted, and Kusunga quits.

## Platform work

- **File dialogs:** package `file_selector` (Flutter team, pub.dev). It uses `NSSavePanel` / `NSOpenPanel` on Mac and `IFileDialog` on Windows. This is a new dependency; the PM decides in D1's deck slide.
- **Mac sandbox:** add `com.apple.security.files.user-selected.read-write` to both entitlements files. Kusunga can then read or write only the file the user picks in the dialog.
- **Key delete:**
  - Mac: `flutter_secure_storage.delete`.
  - Windows: `CredDeleteW` through the existing FFI vault.
  - `KeyStore` gains `delete()`.

## Failure plan

| Failure | Behaviour | Log code |
|---|---|---|
| Export write fails (disk full, permission) | No file left; "Couldn't save the export. Try again." | `exportFailed <errno>` |
| Import file refused | Nothing changes; "This file can't be imported. It isn't a Kusunga export, or it is damaged." | `importRejected <reason number>` |
| Import write fails | Transaction rolled back; "Couldn't import. Nothing was changed." | `importFailed` |
| Key delete fails | Nothing deleted; error note; retry | `deleteEverythingFailed <errno>` |
| Key delete doesn't answer, and the key is still there after a second wait (T5) | Nothing deleted; capture stays stopped; note; OK quits | `deleteEverythingFailed` (no number) |
| File delete fails after the key is gone | Carry on; note says the file can't be read; cleaned up next launch | `deleteFileFailed <errno>` |

## Observability

New log codes, numbers only. The log takes one number per line, so the counts are on separate codes:
- `dataExported <snippets>` and, when history is included, `dataExportedHistory <history items>`
- `dataImported <snippets added>`, `dataImportedHistory <history items added>` and `dataImportSkipped <snippets already here + history items already here + history items past auto-delete + history items that didn't fit>`
- `importRejected <reason>`
- `importFailed`
- `exportFailed <errno>`
- `deleteEverythingDone`
- `deleteEverythingFailed <errno>`, with no number when the keychain never answered
- `deleteFileFailed <errno>`

There are no file names or paths. The log file is itself deleted by Delete everything, so `deleteEverythingDone` is written just before it is removed, and that is fine.

## Trust boundaries and abuse cases

- **A crafted import file:**
  - huge (over 20 MB is refused before parsing);
  - deeply nested JSON (the parser's depth limit, with a test);
  - very long strings (rejected by the field rules);
  - a shortcut that would fire in password fields (refused by the M1.5 rules);
  - settings out of range (refused);
  - app ids made to hide a real app (the list only gains entries; the user sees them in Privacy).
- **An export left on a shared computer:** it is not encrypted. The dialog warns the user, and history is off by default.
- **Someone at the unlocked computer:**
  - exports history: the same risk as opening the History tab today;
  - runs Delete everything: asks first, focus on Cancel. The same risk as Clear history today, but wider.
- **A path in the file:** never followed. Kusunga reads only the file the user picked.

## Privacy

Not legal advice.

| Field | Purpose | Lawful basis (PM decides) | Retention | Shared with | Notes |
|---|---|---|---|---|---|
| Export file | Let the user keep or move their own data (data portability) | Likely n/a: the user makes the file on their own device (plan D7) | As long as the user keeps the file; Kusunga doesn't track it | Whoever the user gives it to | Not encrypted (D1); history only if chosen |
| Import | Bring the user's own data back | As above | As other snippets and history | None | Validated; merge only |

- This item adds the rights tools the UK and EU GDPR expect: portability (export) and erasure (delete). It adds no new data field.
- **DPIA screening:** no new trigger. The M1.9 DPIA should mention that exports are plain text.
- **Privacy notice (M1.9):** "You can export your snippets and history as a file. The file isn't encrypted. Delete everything removes all Kusunga data and its key from this computer."

## Decisions for the PM

| # | Decision | Options | Lead recommendation |
|---|---|---|---|
| D1 | Is the export file encrypted? | A: plain JSON, readable, with a clear warning; B: encrypted with a password the user types; C: plain JSON for snippets, password required to include history | A: matches the AC ("a JSON file"), makes portability simple, and needs no crypto code to review. Password export becomes a Later line (trigger: ≥ 5 beta requests). This also approves the new `file_selector` package and the Mac file entitlement |
| D2 | Is history in the export by default? | A: off, with an "Include history" tick box; B: on | A: the most private choice is the default (M1.7 AC2 principle) |
| D3 | What does import do with existing data? | A: merge (add, skip exact duplicates, never overwrite); B: replace everything; C: ask each time | A: no surprise data loss; "replace" can be done as Delete everything, then import |
| D4 | What does "Delete all history" do? | A: today's Clear history (keeps snippets, settings and key) plus a VACUUM, also offered in Settings; B: also deletes the key and starts a new one | A: the AC sentence reads "both remove all stored data and the key", but deleting the key for history only would also lose snippets. The lead reads the AC as history for one button, everything plus the key for the other |
| D5 | Are settings and the ignore list in the export? | A: yes, and on import they apply only if the user ticks "Also use the settings in this file"; B: no, snippets and history only | A: the M1.7 deck told you settings export was planned in M1.8 |
| D6 | After Delete everything | A: turn launch at login off and quit; B: stay open on an empty, fresh Kusunga | A: quitting is the simplest way to be sure nothing is still in memory; a login item would start a Kusunga the user just erased |

Assumed unless the PM says otherwise:
- lawful basis n/a (nothing leaves the device by Kusunga's action);
- no ADR, because none of these choices is hard to reverse;
- the size is large.

## Rollout and rollback

- **Rollout:** ships with the normal build. No schema change.
- **Rollback:** revert the merge. Export files already made stay where the user saved them. The Mac entitlement goes back to sandbox-only.

## Later lines (added to docs/PLAN.md 2026-11-12)

- Password-protected export — plain JSON matches the plan and the warning covers the risk — trigger: ≥ 5 beta requests — noted 2026-11-12 by lead
- Import from other clipboard apps (Paste, Maccy, Ditto, Windows clipboard history) — each needs its own format reader — trigger: ≥ 10 beta requests naming one app — noted 2026-11-12 by lead
