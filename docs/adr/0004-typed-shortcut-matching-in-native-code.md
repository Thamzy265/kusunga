# 0004. Match typed shortcuts in native code; typed keys never leave it

Date: 2026-11-08

## Status

Accepted (PM, 2026-11-08)

## Context

From M1.5 Kusunga watches the keys the user types in every app, to notice snippet shortcuts such as `;email`.

- On Mac it uses a listen-only event tap (ListenEvent / Input Monitoring, ADR 0003).
- On Windows it uses a low-level keyboard hook.

These keys include personal text, and on Windows passwords too, because Windows has no "secure input" that hides password keys from hooks.

Two places can hold the typed keys and do the matching:

- A: the native code (Swift on Mac, C++ on Windows) keeps the buffer and matches it against a table of shortcut → snippet id from Dart. Native tells Dart only "snippet N matched, delete K characters".
- B: native forwards every typed character to Dart over the Flutter channel, and Dart matches.

Windows removes a low-level hook whose callback is too slow, so the hook can't wait for Dart.

## Decision

We will use option A:

- The typed-key buffer exists only in native memory. It holds at most 32 characters and is cleared after 5 s without typing, and on every reset event (design note M1.5).
- No channel message, log line, file or Dart object ever carries a typed character.
- The channel API carries shortcut tables, snippet ids, delete counts, status codes and the snippet text Kusunga pastes. It carries nothing typed.
- Keys sent by other software are ignored, if the PM agrees (M1.5 D5).

## Consequences

- **Easier:**
  - The privacy promise in the app is simple and true: typed keys never leave the small native buffer.
  - The reviewer checks one small native area and one channel API.
  - The hook answers each key quickly.
- **Harder:**
  - The matcher and buffer are written twice, in Swift and C++, each with its own unit tests.
  - Changing the matching rules means changing both.
- **Guarded by:**
  - a source guard test that the channel API has no field for typed text;
  - a native test that the buffer is at most 32 characters and clears after 5 s;
  - a log-code test.
- **Reversing it** (moving matching to Dart) would break the promise in the UI copy, so it needs a new ADR and a PM decision.
