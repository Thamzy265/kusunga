// Tests for capture_gate.h (M1.6: secret markers, then the pause, then the
// source app against the ignore list, all before any text is read; ADR
// 0005). No Windows dependencies, so this builds anywhere:
//   clang++ -std=c++17 windows/runner/capture_gate_test.cpp
// (see tool/test_windows_policy.sh). It is not part of the Windows build.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>

#include "capture_gate.h"

using namespace kusunga;

static int failures = 0;
#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond);      \
      failures++;                                                \
    }                                                            \
  } while (0)

namespace {

const ClipboardFlags kPlain{false, false, 0, false};
const ClipboardFlags kSecret{true, false, 0, false};

// A source lookup that counts how often it was asked.
struct Lookup {
  std::string value;
  int calls = 0;
  std::string operator()() {
    calls++;
    return value;
  }
};

}  // namespace

int main() {
  constexpr int64_t now = 1'000'000;

  // The pause value: 0 not paused, -1 until resumed, else an end time.
  CHECK(!IsPausedAt(0, now));
  CHECK(IsPausedAt(-1, now));
  CHECK(IsPausedAt(now + 1, now));
  CHECK(!IsPausedAt(now, now));  // at the end time the pause is over
  CHECK(!IsPausedAt(now - 1, now));
  {
    CaptureGate gate;
    gate.SetPause(-7);  // anything else below -1 means not paused
    CHECK(gate.paused_until() == 0);
    gate.SetPause(-1);
    CHECK(gate.paused_until() == -1);
  }

  // Windows FILETIME (100 ns since 1601) to ms since 1970.
  CHECK(FileTimeToEpochMs(116444736000000000ULL) == 0);
  CHECK(FileTimeToEpochMs(116444736000000000ULL + 10000ULL * 1500) == 1500);
  CHECK(FileTimeToEpochMs(0) == 0);  // before 1970: never negative

  // The source: the clipboard owner's process, else the foreground window's.
  {
    Lookup owner{"keepass.exe"}, fg{"notepad.exe"};
    CHECK(ChooseSource(std::ref(owner), std::ref(fg)) == "keepass.exe");
    CHECK(fg.calls == 0);  // not asked when the owner is known
  }
  {
    Lookup owner{""}, fg{"notepad.exe"};
    CHECK(ChooseSource(std::ref(owner), std::ref(fg)) == "notepad.exe");
    CHECK(owner.calls == 1 && fg.calls == 1);
  }
  {
    Lookup owner{""}, fg{""};
    CHECK(ChooseSource(std::ref(owner), std::ref(fg)).empty());
  }

  // Order 1: a secret copy is secret, whatever the pause or the list.
  {
    CaptureGate gate;
    gate.SetPause(-1);
    gate.SetIgnored({"keepass.exe"});
    Lookup src{"keepass.exe"};
    const CaptureDecision d = DecideCapture(kSecret, gate, now, std::ref(src));
    CHECK(d.outcome == CaptureOutcome::kSecret);
    CHECK(src.calls == 0);
  }
  // Order 2: paused skips without looking for the source.
  {
    CaptureGate gate;
    gate.SetPause(now + 15 * 60 * 1000);
    gate.SetIgnored({"keepass.exe"});
    Lookup src{"keepass.exe"};
    const CaptureDecision d = DecideCapture(kPlain, gate, now, std::ref(src));
    CHECK(d.outcome == CaptureOutcome::kPaused);
    CHECK(!d.source_unknown);
    CHECK(src.calls == 0);
  }
  // ...until its end time on the wall clock.
  {
    CaptureGate gate;
    gate.SetPause(now + 1000);
    Lookup src{""};
    CHECK(DecideCapture(kPlain, gate, now + 999, std::ref(src)).outcome ==
          CaptureOutcome::kPaused);
    CHECK(DecideCapture(kPlain, gate, now + 1000, std::ref(src)).outcome ==
          CaptureOutcome::kRead);
  }
  // Order 3: an app on the list is skipped; any other app is read.
  {
    CaptureGate gate;
    gate.SetIgnored({"keepass.exe", "1password.exe"});
    Lookup vault{"keepass.exe"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(vault)).outcome ==
          CaptureOutcome::kIgnoredApp);
    Lookup editor{"notepad.exe"};
    const CaptureDecision d = DecideCapture(kPlain, gate, now, std::ref(editor));
    CHECK(d.outcome == CaptureOutcome::kRead);
    CHECK(!d.source_unknown);
  }
  // Exe names are compared in lower case.
  {
    CaptureGate gate;
    gate.SetIgnored({"keepass.exe"});
    Lookup src{"KeePass.EXE"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(src)).outcome ==
          CaptureOutcome::kIgnoredApp);
  }
  // An unknown source fails open: read as today, and said so for the log.
  {
    CaptureGate gate;
    gate.SetIgnored({"keepass.exe"});
    Lookup src{""};
    const CaptureDecision d = DecideCapture(kPlain, gate, now, std::ref(src));
    CHECK(d.outcome == CaptureOutcome::kRead);
    CHECK(d.source_unknown);
  }
  // With an empty list the source is never looked up.
  {
    CaptureGate gate;
    Lookup src{"keepass.exe"};
    const CaptureDecision d = DecideCapture(kPlain, gate, now, std::ref(src));
    CHECK(d.outcome == CaptureOutcome::kRead);
    CHECK(!d.source_unknown);
    CHECK(src.calls == 0);
  }
  // The list is replaced, not added to.
  {
    CaptureGate gate;
    gate.SetIgnored({"a.exe"});
    gate.SetIgnored({"b.exe"});
    Lookup a{"a.exe"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(a)).outcome ==
          CaptureOutcome::kRead);
  }

  // R6: while paused, a copy is skipped before the clipboard is opened:
  // no open, no wait, no "locked".
  {
    CaptureGate gate;
    gate.SetPause(-1);
    int opens = 0, sleeps = 0;
    CHECK(OpenUnlessPaused(gate, now, [&] { opens++; return false; },
                           [&](int) { sleeps++; }) == OpenStep::kPaused);
    CHECK(opens == 0);
    CHECK(sleeps == 0);
    gate.SetPause(now + 1);
    CHECK(OpenUnlessPaused(gate, now, [&] { opens++; return true; },
                           [&](int) { sleeps++; }) == OpenStep::kPaused);
    CHECK(opens == 0);
  }
  // Not paused (or the pause just ended): opened as before, with the retry.
  {
    CaptureGate gate;
    gate.SetPause(now);  // ends now: over
    int opens = 0, sleeps = 0;
    CHECK(OpenUnlessPaused(gate, now, [&] { return ++opens == 2; },
                           [&](int) { sleeps++; }) == OpenStep::kOpened);
    CHECK(opens == 2);
    CHECK(sleeps == 1);
    opens = 0;
    sleeps = 0;
    CHECK(OpenUnlessPaused(gate, now, [&] { opens++; return false; },
                           [&](int) { sleeps++; }) == OpenStep::kLocked);
    CHECK(opens == kOpenAttempts);
    CHECK(sleeps == kOpenAttempts - 1);
  }

  if (failures == 0) std::printf("all capture gate checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
