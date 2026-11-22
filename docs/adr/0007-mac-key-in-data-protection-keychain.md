# 0007. Keep the Mac history key in the data-protection keychain

Date: 2026-11-19

## Status

Proposed (M1.9 deck; the move itself was decided by the PM on 2026-11-03)

## Context

ADR 0002 keeps a random 256-bit history key in the OS keychain.

On Mac it is in the **login keychain** today (`flutter_secure_storage`, `usesDataProtectionKeychain: false`). The data-protection keychain needs a signed build with a `keychain-access-groups` entitlement, which needs the Apple Developer account.

Login-keychain items are protected by per-app access lists and the keychain password. Data-protection keychain items are tied to the app's signed team and access group, so other apps can't ask for them.

The PM decided on 2026-11-03 that the key moves before the first external beta, with no user's history moved aside.

## Decision

Signed release builds will keep `history_db_key` in the data-protection keychain, access group `$(AppIdentifierPrefix)com.wnasoni.kusunga`.

On each launch, before opening the DB, Kusunga:
1. uses the new item if it exists;
2. otherwise copies the old login-keychain item, after reading it back and opening the DB with it;
3. deletes the old item only after step 2 succeeds.

Builds without the entitlement (debug, profile, ad-hoc) keep using the login keychain and log `keychainMoveSkipped`.

"Delete everything" deletes the key from both places.

The team ID stays out of tracked files: it comes from `Local.xcconfig`.

## Consequences

- **Easier:** the key is bound to Kusunga's signing team. Fewer keychain prompts after the first signed install.
- **Harder:**
  - every shipped build must carry the entitlement;
  - a build from before the move can't find the key, so we never hand one out (rollback rule in the M1.9 design note);
  - dev builds behave differently from release builds, so QA must test the move on a signed build.
- **Not reversible by design:** we don't move keys back to the login keychain.
