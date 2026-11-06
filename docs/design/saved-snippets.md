# M1.4 Saved snippets — design note

Date: 2026-11-04 — Size: large — new data store (snippets table), new personal data the user types in (phone numbers, emails, addresses, possibly other people's details), new UI in the main window and the picker — Phase: MVP — Status: approved by PM 2026-11-04

## Context

Plan item M1.4 (`docs/PLAN.md`). M1.2 keeps clipboard history in an encrypted store, and M1.3 pastes from it with ⌘⇧V / Ctrl+Shift+V. History is temporary: the oldest items drop off at the limit. The PM's original idea also has things you paste often and never want to lose: your phone number, email address, links, your address. M1.4 adds these as **snippets**: saved by the user, never removed by the history limit, and shown in their own tab in the picker.

Typed shortcuts such as `;email` are M1.5. Bank and card details belong in the M2 vault (locked, masked, cleared from the clipboard after 30 seconds).

## Requirements and non-goals

- Functional (ACs from the plan):
  - Create, edit, delete and reorder snippets. Each has a name, content and type (phone, email, link, address, other).
  - Snippets show in the picker in their own tab. Pinning a history item turns it into a snippet.
  - Snippets are never removed by the history limit.
- Also in scope:
  - Delete has Undo (5 s), as in history.
  - Reordering works without dragging (Move up / Move down, and ⌥↑ / ⌥↓, or Alt+↑ / Alt+↓ on Windows); WCAG 2.5.7.
  - The type is suggested from the content (email, phone, link) and the user can change it.
  - Picker search covers name and content in the Snippets tab.
  - "Clear history" does not touch snippets. Its confirm text already says so (M1.2).
- Non-functional:
  - The picker stays visible within 150 ms (p95).
  - Search over 1,000 snippets and 5,000 history items takes under 50 ms per keystroke.
  - No content, names or types in any log: codes only, as in M1.3.
- Non-goals:
  - Typed shortcuts (M1.5).
  - Vault, masking and clipboard clearing (M2).
  - Folders, tags and colours.
  - Placeholders such as `{date}`.
  - Rich text and images.
  - Sync (M3), and export/import (M1.8).

## Top 3 qualities

| Quality | Target | How we check it |
|---|---|---|
| Data integrity | A saved snippet is never lost or changed by the history limit, Clear history, an app update or a failed write. Order stays exactly as the user set it | Store tests: limit, clear, migration v2 → v3 keeps every row. A crash mid-write leaves the old version (one transaction per change) |
| Privacy | Snippet text never leaves the device or appears in a log, and stays encrypted at rest | Reviewer privacy check; a log-code test; a store test that the file has no plain text |
| Accessibility | Create, edit, reorder, delete and paste all work with keyboard only and with VoiceOver and Narrator | Widget tests (semantics, the non-drag reorder) and the PM's VoiceOver check |

## Estimate

Trivially small: one user and a few dozen snippets (cap 1,000). Each snippet's name is at most 100 characters and its content at most 1 MiB, the history cap. The real total is a few KB, read once at start and held in memory.

## Data

New table in the **same encrypted database** as history. Schema version 3 is one migration and adds nothing to existing tables:

```sql
CREATE TABLE snippets (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  content TEXT NOT NULL CHECK (length(CAST(content AS BLOB)) BETWEEN 1 AND 1048576),
  type TEXT NOT NULL CHECK (type IN ('phone', 'email', 'link', 'address', 'other')),
  position INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_snippets_position ON snippets (position);
```

- **Order:** `position` is a whole number, renumbered 0..n−1 in one transaction on each move. Simple to reason about, and fine at 1,000 rows.
- **Names may repeat**, because the user may want two "Work email" snippets; the list tells them apart by content. Content may also repeat.
- **Cap:** at most 1,000 snippets. At the cap, the app refuses a new one with a message; the store checks too.
- **Pinning** a history item copies its full text (`contentOf`) into a new snippet. The suggested name is the first line, cut to 40 characters, and the type is suggested from the content. The history item stays where it is (PM decision D2).
- **Not stored:** where the content came from, or how often it is pasted. There's no use for it yet.
- **Migration:** v2 → v3 is expand-only, a new table. The runner keeps the `.bak` copy until success (M1.2). A v2 build seeing a v3 file runs memory-only with the "incompatible" banner and leaves the file untouched (M1.2 C1). A test checks that v2 → v3 keeps every history item and setting.
- **Memory-only mode** (keychain unreachable): snippets can't be saved. The Snippets tab shows the banner and disables New, Edit and Pin, so the user never types something that is lost on quit. The snippets can't be read in these modes, so the Snippets tabs are empty and say why (UI spec, Banners).

## Options

### A: Same encrypted database, new table (recommended)

A `SnippetStore` interface next to `HistoryStore`, on the same SQLite connection and key. `SqliteSnippetStore` and `MemorySnippetStore` are used for tests and memory-only mode.

- Benefits: one key, one file, one migration runner, one backup. It reuses the cipher check, the start-up error paths and the "newer file" guard. "Delete everything" (M1.8) removes one file and one key.
- Costs: a corrupt file loses both history and snippets, which the `.bak` copy and M1.8 export mitigate. The module boundary is kept in code rather than in a second file.
- Effort: medium.

### B: A separate encrypted file for snippets

- Benefits: a snippets file survives a history problem. It could get its own key and lock later (M2-style).
- Costs: two keychain items, and two possible keychain prompts on Mac with ad-hoc builds. Two migration runners, two sets of error banners, and harder "Delete everything" and export. Most benefits overlap with the M2 vault, which gets its own design.
- Effort: high.

## Decision

A. B doubles the keychain and start-up error work for a benefit the M2 vault covers better. This is not hard to reverse: moving the table to its own file later is a copy plus a migration. So there's no ADR.

## How it works

- **Main window:** two tabs at the top, **History** (today's screen) and **Snippets**.
  - The Snippets tab lists snippets in the user's order: name, type icon, one line of content and row actions (Paste is not there; Copy, Edit, Move up, Move down, Delete). **New snippet** opens an editor with Name, Type and Content, plus Save and Cancel.
  - A history row gets a **Save as snippet** action, which opens the same editor already filled in.
- **Picker:** two tabs, **History** and **Snippets**. ⌃Tab / ⌃⇧Tab (Ctrl+Tab on Windows) or a click switches between them. Search, Up/Down, Enter and ⌘1–9 work the same in both tabs, and the footer shows the active tab's count. Which tab opens first is PM decision D3.
- **Pasting a snippet** uses the M1.3 paste flow unchanged. Whether it adds the snippet to history is PM decision D1.
  - If the answer is "not added", the watcher skips the one clipboard change Kusunga itself made, matched by its own change number (Mac `changeCount`, Windows `GetClipboardSequenceNumber`) recorded at write time. No other app can fake this.
  - The existing `com.wnasoni.kusunga.self` marker is not trusted for this, because any app can set it (M1.3 abuse case).
- **Type suggestion:** reuse `clip_classifier.dart` for links, and add simple email and phone checks. A suggestion only; the user's choice wins.

## Failure plan

No network, so no outbound calls. The failure paths:

- **Save, edit, move or delete fails** (disk full, I/O error): the change is one transaction, so nothing half-saved. The editor stays open with the user's text and shows "Couldn't save the snippet. Try again.". A failed move leaves the old order, a failed delete keeps the row, and each gives a toast.
- **At the 1,000 cap:** New and Pin show "You have 1,000 snippets, the most Kusunga keeps. Delete one to add another."
- **Over 1 MiB, empty content or empty name:** the form says so under the field, and Save stays enabled but refuses the save. A pinned item can't be over the cap, because history has the same cap.
- **Memory-only or incompatible database:** as in Data. The banner explains, and editing is off.
- **Paste fails:** the M1.3 fallbacks apply (copy only plus toast).
- **Test data profile (Debug builds only; PM decision 2026-11-05, for the AC3 limit test):** launched with `-KusungaDataProfile <name>` (`[a-z0-9-]{1,32}`), every file (database, `.bak`, `.unreadable-*`, settings, log) is in `<support>/profiles/<name>/`, and the default folder is never read, migrated, trimmed, moved aside or deleted. It reuses the existing database key and never writes one: with no key yet it runs memory only. A mistyped or misspelled switch (`dataProfileRejected` 3; reviewer P1 and BUG-Q1, PM decision 2026-11-06 "Common slips + label check") is any argument other than the exact `-KusungaDataProfile` that, after any spaces or quotes, starts with `-`, `/` or any dash or minus (U+2010–2015, U+2212, U+FE63, U+FF0D) and holds "kusunga" and "profil" in any case; or that, in lower case without spaces, quotes, `_`, `/` and dashes, starts within 3 edits of `kusungadataprofile` (a letter dropped, added or changed, or two neighbours swapped), with or without a dash; or two neighbouring arguments, neither of them the exact switch, that do so read together. So `-KusungaDataProfile=qa`, `--KusungaDataProfile`, `-KusungaDataProfil`, `-KusungaDataProfle`, `-KusunagDataProfile`, `KusungaDataProfile`, `−KusungaDataProfile`, ` "-KusungaDataProfile"`, `/KusungaDataProfile` and `-Kusunga DataProfile qa` are all rejected; an unrelated argument would need 15 or more of the switch's 18 letters, in order, to come that close. Accepted limit (PM, 2026-11-06, Debug builds only, docs/status.md): a switch with a part left out (`-Profile`, `-DataProfile`, `-Kusunga`, BUG-Q1b) or with look-alike letters from other alphabets (BUG-Q1g) can still open the default folder; QA confirms the "Test profile: qa" label before any step that deletes data. Also not caught: more than 3 edits, and a switch split across three or more arguments. A rejected name or switch, or any link at `profiles/`, `profiles/<name>/` or inside it, including a hard link to a file of the default folder (`dataProfileRejected` 2), also runs memory only and creates no file, never on the default folder. The window shows "Test profile: <name>"; the log gets `dataProfileActive`, `dataProfileRejected` or `dataProfileNoKey`, never the name or path. The log is opened for each line, with a link check right before every open, so a link put in its place later is not written through. Accepted limit (PM, 2026-11-05, Debug builds only, docs/status.md): a hard link created between the check and the open, or a hard link to a file outside the default data folder (another profile's, for example), is not caught. Release builds ignore the switch.

## Observability

Log codes only, with no names, content or types:

- `snippetSaveFailed`
- `snippetDeleteFailed`
- `snippetMoveFailed`
- `snippetCapReached`
- `snippetsUnavailable` (memory-only or incompatible)
- `pasteSource` with a number: 0 = history, 1 = snippet

These are added to the closed code list (M1.3 B1). QA watches picker-open latency with snippets present.

## Trust boundaries and abuse cases

- Boundaries:
  1. Text the user types or pastes into the editor.
  2. History items, which may contain text from any app, being pinned.
  3. The clipboard when a snippet is pasted (other apps can read it).
  4. Screen sharing, where snippet previews are visible.
- Abuse cases:
  - **As a malicious app, I set Kusunga's self marker on my own clipboard text**, so that my text skips history or is treated as a snippet. Mitigation: skipping is by Kusunga's own change number, never by the marker. Nothing becomes a snippet without the user pressing Save.
  - **As a malicious app, I read the clipboard after a snippet is pasted**, so that I get the user's address or phone number. Mitigation: this is the same as any paste. The clipboard is shared on every OS, and M2 adds clipboard clearing for vault items. The editor has a note that bank and card details belong in the vault (D4).
  - **As someone watching the screen, I see snippet previews in the picker.** Mitigation: one-line previews only, nothing shown until the shortcut is pressed. The existing Later line covers hiding previews while sharing.
  - **As a user, I paste a huge or odd text** (NUL, RTL marks, 1 MiB) into the editor. Mitigation: the same caps and checks as history (M1.2 NUL fix). Names are single-line, newlines are removed and the name is capped at 100. Display never interprets markup.
  - **As a user, I lose snippets in a failed update.** Mitigation: the `.bak` copy and expand-only migration. A newer file is never touched by an older build.

## Privacy

Not legal advice. Items marked "PM decides" need the PM's decision before the developer starts.

| Field | Purpose | Lawful basis (PM decides) | Retention | Shared with | Notes |
|---|---|---|---|---|---|
| Snippet name | Lets the user find the snippet | n/a — the data never leaves the device; Kusunga processes it only for the user (as M1.2/M1.3) | Until the user deletes it, or "Delete everything" (M1.8) | None | Required; at most 100 characters |
| Snippet content | The text the user wants to paste | n/a — as above | As above | None | Required; may contain other people's details (a partner's phone number) that the user chose to save |
| Snippet type | Icon and type suggestion; M1.5 may use it | n/a — as above | As above | None | Suggested from the content; the user can change it |
| Position, created/updated time | Keep the user's order; show "edited 2 days ago" | n/a — as above | As above | None | Not personal on their own |

- Fields removed: the source app, paste counts and the last-pasted time. There's no use for them yet.
- DPIA screening: no new triggers. Users may store third parties' contact details on their own device, which is household use and never leaves the device. The short DPIA before the beta (M1.9) covers snippets too.
- Children likely: no. Automated decisions or profiling: none.
- Special category data: Kusunga doesn't ask for any, but a user could type anything into a snippet. It is encrypted at rest like history.
- New vendors, SDKs or transfers: none. No new pub packages are planned.
- Private defaults:
  - The picker opens on History unless the PM chooses otherwise (D3).
  - Pasted snippets are not added to history unless the PM chooses otherwise (D1).
  - Nothing is shown until the shortcut is pressed.
- Export, delete, rectify:
  - Edit is rectify.
  - Delete with Undo removes the row. Undo keeps the row in memory only, for 5 s.
  - Export and import are M1.8, and the plan already includes snippets.
- Record of processing and privacy notice: add "snippets you save" to the M1.9 privacy notice draft.
- Escalated to PM: D1–D4 below.

## Decisions for the PM

| # | Decision | Options | Lead recommendation |
|---|---|---|---|
| D1 | When you paste a snippet, does it also go into history? | A: No · B: Yes, like any copy | A — the snippet is already saved; adding it fills history with duplicates and puts personal details in a second place |
| D2 | When you pin a history item, does it stay in history? | A: Copy (stays in history and ages out normally) · B: Move (removed from history) | A — nothing disappears unexpectedly, and history keeps its order |
| D3 | Which tab does the picker open on? | A: History, always · B: The tab you used last · C: Snippets, always | A — the shortcut keeps one predictable behaviour; ⌃Tab is one key away |
| D4 | Bank and card details before the M2 vault | A: Allow, with a one-line note in the editor that the vault is coming · B: Allow, no note · C: Detect card numbers and IBANs and warn | A — honest and cheap; detection belongs to the M2 vault design |

## Rollout and rollback

- **Schema:** version 3, a new table only. The migration runner keeps the `.bak` until success.
- **Rollback:** revert the merge. An M1.3 build seeing a v3 file runs memory-only with the "incompatible" banner and leaves the file untouched (M1.2 C1), so snippets aren't lost, just not visible until the user updates again. Confirm by launching the old build: the banner shows, and the file hash is unchanged.
- **No feature flag:** a single user and a local app. The tab is the whole feature.

## Later lines

- Snippet placeholders (`{date}`, cursor position) — not needed for fixed text like a phone number — trigger: ≥ 10 beta requests — noted 2026-11-04 by lead
- Snippet folders or tags — a flat list is enough at a few dozen snippets — trigger: median beta user has > 50 snippets, or ≥ 10 requests — noted 2026-11-04 by lead
- Paste counts and "most used" ordering — no use until the list is long — trigger: median beta user has > 30 snippets — noted 2026-11-04 by lead
