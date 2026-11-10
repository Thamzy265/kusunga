// M1.6 tester: edge cases for capture_gate.h (docs/design/sensitive-content.md
// "Abuse cases", ADR 0005). No Windows dependencies:
//   clang++ -std=c++17 windows/runner/capture_gate_edge_test.cpp
// (see tool/test_windows_policy.sh). Not part of the Windows build.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <limits>
#include <string>

#include "app_id.h"
#include "capture_gate.h"

using namespace kusunga;

static int failures = 0;
#define CHECK(cond)                                         \
  do {                                                      \
    if (!(cond)) {                                          \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond); \
      failures++;                                           \
    }                                                       \
  } while (0)

namespace {

const ClipboardFlags kPlain{false, false, 0, false};
// Each secret marker on its own, and the unreadable CanInclude value.
const ClipboardFlags kExclude{true, false, 0, false};
const ClipboardFlags kNoHistory{false, true, 0, false};
const ClipboardFlags kViewerIgnore{false, false, 0, true};
const ClipboardFlags kUnreadable{false, true, 1, false, true};

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
  constexpr int64_t now = 5'000'000;
  constexpr int64_t kMax = std::numeric_limits<int64_t>::max();
  constexpr int64_t kMin = std::numeric_limits<int64_t>::min();

  // Pause values at the extremes.
  CHECK(IsPausedAt(kMax, now));
  CHECK(IsPausedAt(-1, kMax));  // until resumed: whatever the clock
  CHECK(!IsPausedAt(0, 0));
  CHECK(!IsPausedAt(now, now));
  CHECK(IsPausedAt(now + 1, now));
  {
    CaptureGate gate;
    gate.SetPause(kMin);  // anything below -1 means not paused
    CHECK(gate.paused_until() == 0);
    gate.SetPause(-2);
    CHECK(gate.paused_until() == 0);
    gate.SetPause(kMax);
    CHECK(gate.paused_until() == kMax);
  }

  // FILETIME edges.
  CHECK(FileTimeToEpochMs(116444736000000001ULL) == 0);  // 100 ns above 1970
  CHECK(FileTimeToEpochMs(116444736000000000ULL + 9999ULL) == 0);
  CHECK(FileTimeToEpochMs(116444736000000000ULL + 10000ULL) == 1);
  CHECK(FileTimeToEpochMs(std::numeric_limits<uint64_t>::max()) > 0);
  CHECK(FileTimeToEpochMs(116444735999999999ULL) == 0);

  // Every kind of secret marker wins over a pause and over the list, and the
  // source is never looked up.
  for (const ClipboardFlags& f :
       {kExclude, kNoHistory, kViewerIgnore, kUnreadable}) {
    CaptureGate gate;
    gate.SetPause(-1);
    gate.SetIgnored({"keepass.exe"});
    Lookup src{"keepass.exe"};
    const CaptureDecision d = DecideCapture(f, gate, now, std::ref(src));
    CHECK(d.outcome == CaptureOutcome::kSecret);
    CHECK(!d.source_unknown);
    CHECK(src.calls == 0);
  }
  // A secret copy is secret with no pause and an empty list too.
  {
    CaptureGate gate;
    Lookup src{""};
    CHECK(DecideCapture(kNoHistory, gate, now, std::ref(src)).outcome ==
          CaptureOutcome::kSecret);
  }

  // The source is looked up at most once per decision.
  {
    CaptureGate gate;
    gate.SetIgnored({"keepass.exe"});
    Lookup src{"notepad.exe"};
    DecideCapture(kPlain, gate, now, std::ref(src));
    CHECK(src.calls == 1);
  }

  // Unknown source while paused is "paused", not "unknown" (nothing is logged
  // twice), and an unknown source with an empty list is not reported.
  {
    CaptureGate gate;
    gate.SetPause(now + 1);
    gate.SetIgnored({"keepass.exe"});
    Lookup src{""};
    const CaptureDecision d = DecideCapture(kPlain, gate, now, std::ref(src));
    CHECK(d.outcome == CaptureOutcome::kPaused && !d.source_unknown);
    CHECK(src.calls == 0);
  }
  {
    CaptureGate gate;
    Lookup src{""};
    const CaptureDecision d = DecideCapture(kPlain, gate, now, std::ref(src));
    CHECK(d.outcome == CaptureOutcome::kRead && !d.source_unknown);
  }

  // Matching: lower-casing, exactness, long ids, duplicates, non-ASCII.
  {
    CaptureGate gate;
    gate.SetIgnored({"keepass.exe", "keepass.exe", "1password.exe"});
    CHECK(gate.ignored().size() == 2);
    for (const char* name : {"KEEPASS.EXE", "KeePass.Exe", "keepass.exe"}) {
      Lookup src{name};
      CHECK(DecideCapture(kPlain, gate, now, std::ref(src)).outcome ==
            CaptureOutcome::kIgnoredApp);
    }
    // Not a prefix, suffix or substring match.
    for (const char* name : {"keepass", "xkeepass.exe", "keepass.exe.bak",
                             "keepass.exe ", " keepass.exe", "keepassxc.exe"}) {
      Lookup src{name};
      CHECK(DecideCapture(kPlain, gate, now, std::ref(src)).outcome ==
            CaptureOutcome::kRead);
    }
  }
  {
    const std::string big(10000, 'a');
    CaptureGate gate;
    gate.SetIgnored({big + ".exe"});
    Lookup hit{big + ".exe"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(hit)).outcome ==
          CaptureOutcome::kIgnoredApp);
    Lookup miss{big + "b.exe"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(miss)).outcome ==
          CaptureOutcome::kRead);
  }
  // Bytes above 127 (UTF-8 names) are left alone by the lower-casing.
  CHECK(LowerAscii("\xC3\x89t\xC3\xA9.EXE") == "\xC3\x89t\xC3\xA9.exe");
  CHECK(LowerAscii("") == "");
  {
    CaptureGate gate;
    gate.SetIgnored({"\xC3\xA9t\xC3\xA9.exe"});
    Lookup src{"\xC3\xA9t\xC3\xA9.EXE"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(src)).outcome ==
          CaptureOutcome::kIgnoredApp);
  }

  // Regression lock: list entries are compared as given, so they must be
  // lower case (Dart stores Windows ids lower case: the presets, and the
  // running-apps list). A mixed-case entry would never match, because the
  // source is lower-cased and the entry is not.
  {
    CaptureGate gate;
    gate.SetIgnored({"KeePass.exe"});
    Lookup src{"keepass.exe"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(src)).outcome ==
          CaptureOutcome::kRead);
  }

  // ChooseSource: an owner whose name can't be read falls back to the
  // foreground window; the fallback is asked once.
  {
    Lookup owner{""}, fg{"keepass.exe"};
    CHECK(ChooseSource(std::ref(owner), std::ref(fg)) == "keepass.exe");
    CHECK(owner.calls == 1 && fg.calls == 1);
  }

  // Replacing the list with an empty one stops skipping at once.
  {
    CaptureGate gate;
    gate.SetIgnored({"keepass.exe"});
    gate.SetIgnored({});
    Lookup src{"keepass.exe"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(src)).outcome ==
          CaptureOutcome::kRead);
    CHECK(src.calls == 0);
  }


  // R6 edges. A paused secret-marked copy: the clipboard is never opened, so
  // nothing can be sent for it (not even "concealed").
  {
    CaptureGate gate;
    gate.SetPause(-1);
    int opens = 0;
    CHECK(OpenUnlessPaused(gate, now, [&] { opens++; return true; },
                           [](int) {}) == OpenStep::kPaused);
    CHECK(opens == 0);
    gate.SetPause(kMax);
    CHECK(OpenUnlessPaused(gate, kMax - 1, [&] { opens++; return true; },
                           [](int) {}) == OpenStep::kPaused);
    CHECK(opens == 0);
  }
  // A pause that starts while the open is being retried: the clipboard is
  // open by then, but the decision still skips a plain copy, and a secret
  // copy is still secret.
  {
    CaptureGate gate;
    int opens = 0;
    const OpenStep step = OpenUnlessPaused(
        gate, now,
        [&] {
          if (++opens == 1) {
            gate.SetPause(-1);  // the user pauses during the retry
            return false;
          }
          return true;
        },
        [](int) {});
    CHECK(step == OpenStep::kOpened);
    Lookup src{"notepad.exe"};
    CHECK(DecideCapture(kPlain, gate, now, std::ref(src)).outcome ==
          CaptureOutcome::kPaused);
    CHECK(src.calls == 0);
    CHECK(DecideCapture(kNoHistory, gate, now, std::ref(src)).outcome ==
          CaptureOutcome::kSecret);
  }
  // Locked while not paused is still "locked" (the pause does not hide it).
  {
    CaptureGate gate;
    int opens = 0;
    CHECK(OpenUnlessPaused(gate, now, [&] { opens++; return false; },
                           [](int) {}) == OpenStep::kLocked);
    CHECK(opens == kOpenAttempts);
  }

  // R7: the shared exe-name rule.
  CHECK(ExeFileNameLower(L"\\\\server\\share\\KeePass.EXE") == L"keepass.exe");
  CHECK(ExeFileNameLower(L"C:\\a\\b\\") .empty());
  CHECK(ExeFileNameLower(L"\\") .empty());
  CHECK(ExeFileNameLower(L"/") .empty());
  // A name with a trailing space is kept as it is: it never equals a list id.
  CHECK(ExeFileNameLower(L"C:\\a\\keepass.exe ") == L"keepass.exe ");
  {
    const std::wstring long_name(5000, L'A');
    CHECK(ExeFileNameLower(L"C:\\" + long_name + L".EXE") ==
          std::wstring(5000, L'a') + L".exe");
  }

  if (failures == 0) std::printf("all capture gate edge checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
