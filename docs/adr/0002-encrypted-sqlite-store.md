# 0002. Encrypted SQLite store with the key in the OS keychain

Date: 2026-11-03

## Status

Proposed (accepted when the PM approves the M1.2 deck)

## Context

Kusunga stores everything the user copies (M1.2) and later their snippets (M1.4). The data is personal and can be sensitive. Other processes running as the same user can read files in the user's folders, and backups copy them. We need search (M1.3 picker), a hard item limit, dedupe and safe schema changes.

Options considered:

- A: SQLite encrypted as a whole with SQLite3 Multiple Ciphers via `package:sqlite3` 3.x build options; a random 256-bit key in Mac Keychain / Windows Credential Manager (`flutter_secure_storage`).
- B: Plain SQLite, with each content field encrypted by the app (AES-GCM via `package:cryptography`). Metadata (times, counts, hashes) stays readable, and search needs decrypting every row in memory.
- C: An encrypted JSON file rewritten on every change. Simple, but slow and risky at 5,000 items, with no transactions.

`sqlcipher_flutter_libs` is end of life (it does nothing since 0.7.0); its replacement is `package:sqlite3` 3.x.

## Decision

We will use option A. The app creates the key on first run and never writes it to disk or logs. If the keychain is unavailable, history is kept in memory only and is never written unencrypted.

## Consequences

- Easier: SQL search, constraints and transactions on encrypted data; one file to delete; backups are unreadable without the key.
- Harder: the native SQLite build must include the cipher on both OSes (check `PRAGMA cipher` at start-up and refuse to store if it is missing); Windows builds need testing in CI.
- Mac Keychain access for an unsigned or ad-hoc-signed development build may be limited; signed builds may be needed earlier than M1.9 (PM decision on the M1.2 deck).
- Losing the keychain item makes old history unreadable by design. The app then starts a new history and tells the user.
- Changing the store later means a migration with a backup copy and tests from every earlier schema version.
