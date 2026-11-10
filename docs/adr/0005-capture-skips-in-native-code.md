# 0005. Decide capture skips in native code; the source app never leaves it

Date: 2026-11-10

## Status

Proposed (waiting for PM, M1.6)

## Context

M1.6 stops history capture for copies made in apps on the ignore list, and while the user has paused history. Kusunga must work out which app a copy came from. On Mac that is the pasteboard source marker or the front app; on Windows, the clipboard owner's process. Today, native code skips secret-marked copies before reading them (M1.2), and Dart decides everything else.

Two places can make the new skip decisions:

- A: the native clipboard watcher, given the ignore list and the pause end time by Dart, skips before reading the text. The source app never crosses the channel.
- B: native code sends the source app with every copy, and Dart decides.

## Decision

We will use option A:

- The native watcher on Mac and Windows checks, in this order: secret markers, then the pause end time against the wall clock, then the source app against the ignore list. All three checks happen before any clipboard text is read.
- The source app id exists only in native memory during one check. It is not stored, not logged and not sent over the channel.
- The clipboard event to Dart keeps its current fields (text and the own flag) and gains none.

## Consequences

- **Easier:**
  - The privacy promise is simple: a copy from an ignored app, or made while paused, is never read.
  - A pause ends on time even if Dart's timer runs late after sleep.
- **Harder:**
  - The rule is written twice, in Swift and C++, each with unit tests.
  - A "copied from" label would need a new ADR.
- **Guarded by:**
  - a channel guard test that the clipboard event has no app field;
  - native unit tests of the check order;
  - a log-code test.
