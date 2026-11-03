// Tests for clipboard_policy.h. The policy has no Windows dependencies, so
// this builds anywhere:  clang++ -std=c++17 windows/runner/clipboard_policy_test.cpp
// (see tool/test_windows_policy.sh). It is not part of the Windows build.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>

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


  // ---- Tester additions (M1.2): edge cases ----

  // IsSecret: every one of the 8 flag combinations (value 0 and 1).
  for (int mask = 0; mask < 8; mask++) {
    for (uint32_t value : {0u, 1u, 2u, 0xFFFFFFFFu}) {
      ClipboardFlags f{(mask & 1) != 0, (mask & 2) != 0, value, (mask & 4) != 0};
      bool expected = f.exclude_from_monitor || f.viewer_ignore ||
                      (f.has_can_include && value == 0);
      CHECK(IsSecret(f) == expected);
    }
  }
  // A value is meaningless when the format is not there.
  CHECK(!IsSecret({false, false, 0, false}));
  CHECK(!IsSecret({false, false, 0xFFFFFFFFu, false}));
  // Any non-zero DWORD in CanIncludeInClipboardHistory means "allowed".
  CHECK(!IsSecret({false, true, 2, false}));
  CHECK(!IsSecret({false, true, 0x80000000u, false}));
  CHECK(!IsSecret({false, true, 0xFFFFFFFFu, false}));
  // ... but a zero is not rescued by other benign flags.
  CHECK(IsSecret({false, true, 0, false}));
  // Value-initialised flags (all false) are not secret.
  CHECK(!IsSecret(ClipboardFlags{}));

  // CheckSize: sizes around every boundary, odd sizes, and extremes.
  CHECK(CheckSize(1) == SizeCheck::kEmpty);
  CHECK(CheckSize(3) == SizeCheck::kOk);  // odd: one char and a stray byte
  CHECK(CheckSize(sizeof(char16_t) + 1) == SizeCheck::kOk);
  CHECK(CheckSize(MaxBufferBytes() - 1) == SizeCheck::kOk);
  CHECK(CheckSize(MaxBufferBytes()) == SizeCheck::kOk);
  CHECK(CheckSize(MaxBufferBytes() + 1) == SizeCheck::kTooLarge);
  CHECK(CheckSize(MaxBufferBytes() + 2) == SizeCheck::kTooLarge);
  CHECK(CheckSize(SIZE_MAX) == SizeCheck::kTooLarge);
  CHECK(CheckSize(SIZE_MAX - 1) == SizeCheck::kTooLarge);
  CHECK(CheckSize(static_cast<size_t>(1) << 32) == SizeCheck::kTooLarge);
  CHECK(CheckSize((static_cast<size_t>(1) << 32) + 2) == SizeCheck::kTooLarge);
  // Statically: the limit is 1 MiB of characters, two bytes each.
  static_assert(kMaxChars == 1048576, "limit is 1,048,576 UTF-16 characters");
  static_assert(MaxBufferBytes() == 2097154, "limit chars plus a NUL");
  static_assert(sizeof(char16_t) == 2, "UTF-16 units are two bytes");
  // Monotonic: once too large, always too large; empty only at the bottom.
  {
    bool seen_ok = false, seen_large = false, bad_order = false;
    for (size_t n = 0; n < 64; n++) {
      SizeCheck c = CheckSize(n);
      if (c == SizeCheck::kOk) seen_ok = true;
      if (c == SizeCheck::kEmpty && seen_ok) bad_order = true;
      if (c == SizeCheck::kTooLarge) seen_large = true;
    }
    CHECK(seen_ok && !seen_large && !bad_order);
  }

  // ExceedsLimit around the boundary and at extremes.
  CHECK(!ExceedsLimit(0));
  CHECK(!ExceedsLimit(1));
  CHECK(!ExceedsLimit(kMaxChars - 1));
  CHECK(!ExceedsLimit(kMaxChars));
  CHECK(ExceedsLimit(kMaxChars + 1));
  CHECK(ExceedsLimit(SIZE_MAX));
  // A block that CheckSize lets through can still hold too many characters
  // (no terminator before the end): the second check must catch it.
  CHECK(CheckSize(MaxBufferBytes()) == SizeCheck::kOk);
  CHECK(!ExceedsLimit((MaxBufferBytes()) / sizeof(char16_t) - 1));
  CHECK(ExceedsLimit((MaxBufferBytes() + 2) / sizeof(char16_t)));

  // IsNewCopy: wrap-around, zero and repeated numbers.
  CHECK(IsNewCopy(0xFFFFFFFFu, 0));
  CHECK(IsNewCopy(0, 0xFFFFFFFFu));
  CHECK(!IsNewCopy(0, 0));
  CHECK(!IsNewCopy(0xFFFFFFFFu, 0xFFFFFFFFu));
  CHECK(IsNewCopy(8, 7));  // a counter that went down is still a change
  CHECK(IsNewCopy(1, 0));

  // OpenWithRetry: exact attempt counts and delays, and success on each try.
  static_assert(kOpenAttempts == 3, "three attempts");
  static_assert(kOpenRetryDelayMs == 50, "50 ms apart");
  for (int succeed_on = 1; succeed_on <= 3; succeed_on++) {
    int opens = 0, sleeps = 0, slept = 0;
    bool ok = OpenWithRetry([&] { return ++opens == succeed_on; },
                            [&](int ms) { sleeps++; slept += ms; });
    CHECK(ok);
    CHECK(opens == succeed_on);
    CHECK(sleeps == succeed_on - 1);
    CHECK(slept == 50 * (succeed_on - 1));
  }
  {
    // Succeeds only on a fourth try: must give up after three.
    int opens = 0, sleeps = 0, slept = 0;
    bool ok = OpenWithRetry([&] { return ++opens == 4; },
                            [&](int ms) { sleeps++; slept += ms; });
    CHECK(!ok && opens == 3 && sleeps == 2 && slept == 100);
  }
  {
    // The delay is never zero and never longer than the design says.
    int last = -1;
    OpenWithRetry([] { return false; }, [&](int ms) { last = ms; });
    CHECK(last == 50);
  }

  if (failures == 0) std::printf("all clipboard policy checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
