# M1.8 Your data: export and delete — design note

Date: 2026-11-12 — Author: lead — Status: approved by PM 2026-11-12 (D1 A, D2 A, D3 A, D4 A, D5 A, D6 A)

UI spec: `docs/ui/your-data.md` — Deck: `docs/slides/your-data.html`

Lead rulings during the build (2026-11-12), within the PM's approved options: G1 which settings travel; G2 Import is off while history isn't saved; G3 a debug profile leaves launch at login alone; G4 where "Checking the file…" and the refused message show; G5 imported history keeps its times; G6 no extra clean-up at the next launch; and the Delete everything order. Each is written into the sections below.

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
    - content within the history item size limit;
    - shortcut valid under the M1.5 rules;
    - timestamps parse;
    - settings values are allowed values (the same checks as M1.7);
    - app ids are under 255 characters.
- Unknown fields are ignored. Nothing in the file is run, opened or followed as a path.
- **Where import is offered (lead ruling G2):** only while history is saved. In memory-only, incompatible and backup-failed sessions the Import… button is disabled, with the line "Import isn't available right now, because history isn't being saved."
- **Merge (D3):**
  - Snippets are added after the existing ones. A snippet with the same name and content as an existing one is skipped.
  - If an imported shortcut is already used, the imported snippet is added without a shortcut, and the summary says how many.
  - History items keep the file's times (lead ruling G5). An item already here merges the way Undo does: the newer last copy and the older creation time, so duplicates never double. Items already older than the current auto-delete time are not added; the confirm count shows only the items that will be added, and the summary says how many were left out. Then the history is trimmed to the limit as usual.
  - Settings and ignored apps from the file are applied only if the user ticks "Also use the settings in this file" (D5). They take effect at once: the limit, auto-delete, typed shortcuts, the paste mode and the ignore list.
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
  2. Delete the keychain key (Mac: the keychain entry; Windows: the credential). From this step on, the data can't be read. If the key delete fails, start capture and timers again and stop here: nothing was deleted.
  3. Close the database. Copies still waiting to be saved are dropped, not written.
  4. Write `deleteEverythingDone`, stop the log file, then delete the remaining files:
     - `kusunga.db`, `-wal`, `-shm`, `.bak` and `.unreadable-*`;
     - `kusunga.log` and `kusunga.log.1`;
     - debug only: the active profile folder.
  5. Turn launch at login off (D6).
  6. Kusunga shows "Everything is deleted. Kusunga will now quit." and quits. The next launch is a fresh start: a new key, an empty file and default settings.
- **If the key delete fails:** stop and delete nothing, show "Couldn't delete everything. Nothing was deleted. Try again.", and log `deleteEverythingFailed <errno>`.
- **If a file delete fails after the key is gone:** carry on with the others, then show "Everything is deleted. 1 file couldn't be removed, but it can't be read any more." The next launch already handles a file with no key (lead ruling G6): it makes a new key, moves the old file aside as unreadable and shows the banner once; the next Clear history or Delete everything removes it.
- **In a debug data profile:** only the profile's own folder is deleted. The key is shared with the real history, so it is never deleted, and launch at login (which may be the real app's) is left alone (lead ruling G3). A rejected profile switch (memory only) deletes nothing on disk.
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
| File delete fails after the key is gone | Carry on; note says the file can't be read; cleaned up next launch | `deleteFileFailed <errno>` |

## Observability

New log codes, numbers only. The log takes one number per line, so the counts are on separate codes:
- `dataExported <snippets>` and, when history is included, `dataExportedHistory <history items>`
- `dataImported <snippets added>`, `dataImportedHistory <history items added>` and `dataImportSkipped <snippets already here + history items past auto-delete>`
- `importRejected <reason>`
- `importFailed`
- `exportFailed <errno>`
- `deleteEverythingDone`
- `deleteEverythingFailed <errno>`
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
