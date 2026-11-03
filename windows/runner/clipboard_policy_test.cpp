// Tests for clipboard_policy.h. The policy has no Windows dependencies, so
// this builds anywhere:  clang++ -std=c++17 windows/runner/clipboard_policy_test.cpp
// (see tool/test_windows_policy.sh). It is not part of the Windows build.
#include <cstdio>
#include <cstdlib>

#include "clipboard_policy.h"

using namespace kusunga;

static int failures = 0;
#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond);      \
      failures++;                                                \
    }                                                            \
  } while (0)

int main() {
  // Secret formats: any one of the three is enough.
  CHECK(!IsSecret({false, false, 0, false}));
  CHECK(IsSecret({true, false, 0, false}));   // ExcludeClipboardContentFromMonitorProcessing
  CHECK(IsSecret({false, true, 0, false}));   // CanIncludeInClipboardHistory = 0
  CHECK(!IsSecret({false, true, 1, false}));  // = 1 means allowed
  CHECK(IsSecret({false, false, 0, true}));   // Clipboard Viewer Ignore
  CHECK(IsSecret({true, true, 1, true}));

  // Size: the limit is 1,048,576 characters; the buffer holds a terminator.
  CHECK(CheckSize(0) == SizeCheck::kEmpty);
  CHECK(CheckSize(2) == SizeCheck::kEmpty);  // just a terminator
  CHECK(CheckSize(2 * 10 + 2) == SizeCheck::kOk);
  CHECK(CheckSize(kMaxChars * 2 + 2) == SizeCheck::kOk);
  CHECK(CheckSize(kMaxChars * 2 + 4) == SizeCheck::kTooLarge);
  CHECK(CheckSize(500u * 1024 * 1024) == SizeCheck::kTooLarge);
  CHECK(MaxBufferBytes() == kMaxChars * 2 + 2);

  // Characters actually found after copying.
  CHECK(ExceedsLimit(kMaxChars) == false);
  CHECK(ExceedsLimit(kMaxChars + 1) == true);

  // Only a new clipboard sequence number is a new copy.
  CHECK(!IsNewCopy(7, 7));
  CHECK(IsNewCopy(7, 8));

  // Retry: up to 3 attempts, 50 ms apart, never sleeping after the last.
  {
    int opens = 0, sleeps = 0, slept_ms = 0;
    bool ok = OpenWithRetry([&] { opens++; return opens == 3; },
                            [&](int ms) { sleeps++; slept_ms += ms; });
    CHECK(ok && opens == 3 && sleeps == 2 && slept_ms == 100);
  }
  {
    int opens = 0, sleeps = 0;
    bool ok = OpenWithRetry([&] { opens++; return false; },
                            [&](int) { sleeps++; });
    CHECK(!ok && opens == 3 && sleeps == 2);
  }
  {
    int opens = 0, sleeps = 0;
    bool ok = OpenWithRetry([&] { opens++; return true; },
                            [&](int) { sleeps++; });
    CHECK(ok && opens == 1 && sleeps == 0);
  }

  if (failures == 0) std::printf("all clipboard policy checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
