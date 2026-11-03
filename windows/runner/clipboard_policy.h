#ifndef RUNNER_CLIPBOARD_POLICY_H_
#define RUNNER_CLIPBOARD_POLICY_H_

// The rules for which copies Kusunga may read and save, with no Windows
// dependencies so that they can be tested anywhere (clipboard_policy_test.cpp).

#include <cstddef>
#include <cstdint>

namespace kusunga {

// Longest text we keep, in UTF-16 characters (same limit as the Dart side).
constexpr size_t kMaxChars = 1048576;

// What the clipboard says about the copy, found by asking whether each format
// is present, before any text is read.
struct ClipboardFlags {
  // "ExcludeClipboardContentFromMonitorProcessing" is present.
  bool exclude_from_monitor;
  // "CanIncludeInClipboardHistory" is present, and its DWORD value is below.
  bool has_can_include;
  uint32_t can_include_value;
  // "Clipboard Viewer Ignore" is present.
  bool viewer_ignore;
};

// A copy a password manager (or Windows) marked as not for history. It is
// never read or saved.
inline bool IsSecret(const ClipboardFlags& f) {
  return f.exclude_from_monitor || (f.has_can_include && f.can_include_value == 0) ||
         f.viewer_ignore;
}

enum class SizeCheck { kEmpty, kOk, kTooLarge };

// The most bytes a CF_UNICODETEXT block may hold: the characters and one
// terminating NUL.
constexpr size_t MaxBufferBytes() { return (kMaxChars + 1) * sizeof(char16_t); }

// Decides from the size of the clipboard block alone, before copying it, so a
// 500 MB copy is never read into memory.
inline SizeCheck CheckSize(size_t block_bytes) {
  if (block_bytes <= sizeof(char16_t)) return SizeCheck::kEmpty;
  if (block_bytes > MaxBufferBytes()) return SizeCheck::kTooLarge;
  return SizeCheck::kOk;
}

// The block can be larger than its text: check the real length too.
inline bool ExceedsLimit(size_t chars) { return chars > kMaxChars; }

// WM_CLIPBOARDUPDATE also arrives once when we start listening. Only a new
// sequence number is a new copy.
inline bool IsNewCopy(uint32_t last_sequence, uint32_t sequence) {
  return sequence != last_sequence;
}

constexpr int kOpenAttempts = 3;
constexpr int kOpenRetryDelayMs = 50;

// Another app can hold the clipboard open. Try up to 3 times, 50 ms apart,
// then give up on this copy. [open] returns true on success; [sleep_ms]
// waits. Never sleeps after the last attempt.
template <typename OpenFn, typename SleepFn>
bool OpenWithRetry(OpenFn open, SleepFn sleep_ms) {
  for (int attempt = 1; attempt <= kOpenAttempts; attempt++) {
    if (open()) return true;
    if (attempt < kOpenAttempts) sleep_ms(kOpenRetryDelayMs);
  }
  return false;
}

}  // namespace kusunga

#endif  // RUNNER_CLIPBOARD_POLICY_H_
