#ifndef RUNNER_CLIPBOARD_POLICY_H_
#define RUNNER_CLIPBOARD_POLICY_H_

// The rules for which copies Kusunga may read and save, with no Windows
// dependencies so that they can be tested anywhere (clipboard_policy_test.cpp).

#include <cstddef>
#include <cstdint>

namespace kusunga {

// Longest text we keep: 1 MiB of UTF-8 bytes (same limit as Dart and the Mac).
constexpr size_t kMaxBytes = 1048576;

// GlobalSize can report a few bytes more than the text needs (allocation
// rounding), so the block size alone must not reject a text at the limit.
constexpr size_t kBlockSlackBytes = 16;

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
  // The CanIncludeInClipboardHistory format is there but its value could not
  // be read: fail closed and treat the copy as secret.
  bool can_include_unreadable = false;
};

// A copy a password manager (or Windows) marked as not for history. It is
// never read or saved.
inline bool IsSecret(const ClipboardFlags& f) {
  return f.exclude_from_monitor || (f.has_can_include && f.can_include_value == 0) ||
         f.viewer_ignore || (f.has_can_include && f.can_include_unreadable);
}

enum class SizeCheck { kEmpty, kOk, kTooLarge };

// The most bytes a CF_UNICODETEXT block may hold: the characters and one
// terminating NUL.
constexpr size_t MaxBufferBytes() { return (kMaxBytes + 1) * sizeof(char16_t); }

// Decides from the size of the clipboard block alone, before copying it, so a
// 500 MB copy is never read into memory. A text of N UTF-16 units needs at
// least N UTF-8 bytes, so a block much bigger than the limit cannot fit. Near
// the limit the real length decides (see ExceedsLimit).
inline SizeCheck CheckSize(size_t block_bytes) {
  if (block_bytes <= sizeof(char16_t)) return SizeCheck::kEmpty;
  if (block_bytes > MaxBufferBytes() + kBlockSlackBytes) {
    return SizeCheck::kTooLarge;
  }
  return SizeCheck::kOk;
}

// Checks the real text, not the block: first its UTF-16 length (each unit is
// at least one UTF-8 byte), then its UTF-8 size after conversion.
inline bool ExceedsLimit(size_t bytes_or_units) {
  return bytes_or_units > kMaxBytes;
}

// WM_CLIPBOARDUPDATE also arrives once when we start listening. Only a new
// sequence number is a new copy.
inline bool IsNewCopy(uint32_t last_sequence, uint32_t sequence) {
  return sequence != last_sequence;
}

// Kusunga's own clipboard changes that must not become history: a pasted or
// copied snippet (PM decision D1, M1.4). A change is matched by the sequence
// number GetClipboardSequenceNumber returns right after Kusunga's own write,
// which no other app can fake; never by the marker format, which any app can
// add.
class OwnClipboardChanges {
 public:
  // Before OpenClipboard. While Kusunga holds the clipboard open nobody else
  // can change it, so an update that arrives then is ours.
  void BeginWrite() { writing_ = true; }

  // After CloseClipboard, with GetClipboardSequenceNumber().
  void EndWrite(uint32_t sequence) {
    writing_ = false;
    has_recorded_ = true;
    recorded_ = sequence;
  }

  // The clipboard could not be opened: nothing changed.
  void CancelWrite() { writing_ = false; }

  // True once, for exactly our change. Any check uses the record up: a
  // newer number means another app wrote after us.
  bool Consume(uint32_t sequence) {
    if (writing_) return true;
    if (!has_recorded_) return false;
    has_recorded_ = false;
    return recorded_ == sequence;
  }

 private:
  bool writing_ = false;
  bool has_recorded_ = false;
  uint32_t recorded_ = 0;
};

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
