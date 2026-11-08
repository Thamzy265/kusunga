#ifndef RUNNER_TYPED_SHORTCUT_POLICY_H_
#define RUNNER_TYPED_SHORTCUT_POLICY_H_

// M1.5 typed shortcuts on Windows: the buffer, the matcher, the key classes
// and the skip rules (docs/design/typed-shortcuts.md, "The buffer",
// "Matching and skip rules"; ADR 0004), with no Windows dependencies so that
// they can be tested anywhere (typed_shortcut_policy_test.cpp). The same rules
// as macos/Runner/TypedShortcutCore.swift. The Windows calls live in
// typed_shortcut_bridge.cpp.
//
// Privacy: typed keys exist only in TypedBuffer, in memory, at most 32
// characters, cleared after 5 s without a key and on every reset event.
// Nothing here logs or prints; only a snippet id and a delete count leave.

#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <iterator>
#include <mutex>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "clipboard_policy.h"

namespace kusunga {

// ---- Text helpers (UTF-8 from Dart, UTF-16 from ToUnicodeEx) ----

// Decodes UTF-8. Returns false for anything that is not valid UTF-8.
inline bool Utf8ToUtf32(const std::string& in, std::u32string* out) {
  out->clear();
  size_t i = 0;
  while (i < in.size()) {
    const auto b0 = static_cast<unsigned char>(in[i]);
    char32_t c;
    size_t n;
    if (b0 < 0x80) {
      c = b0;
      n = 1;
    } else if ((b0 & 0xE0) == 0xC0) {
      c = b0 & 0x1F;
      n = 2;
    } else if ((b0 & 0xF0) == 0xE0) {
      c = b0 & 0x0F;
      n = 3;
    } else if ((b0 & 0xF8) == 0xF0) {
      c = b0 & 0x07;
      n = 4;
    } else {
      return false;
    }
    if (i + n > in.size()) return false;
    for (size_t k = 1; k < n; k++) {
      const auto b = static_cast<unsigned char>(in[i + k]);
      if ((b & 0xC0) != 0x80) return false;
      c = (c << 6) | (b & 0x3F);
    }
    const char32_t min = n == 1 ? 0 : n == 2 ? 0x80 : n == 3 ? 0x800 : 0x10000;
    if (c < min || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) return false;
    out->push_back(c);
    i += n;
  }
  return true;
}

// Joins surrogate pairs; a lone surrogate is dropped.
inline std::u32string Utf16ToUtf32(const std::u16string& in) {
  std::u32string out;
  for (size_t i = 0; i < in.size(); i++) {
    const char16_t u = in[i];
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 < in.size() && in[i + 1] >= 0xDC00 && in[i + 1] <= 0xDFFF) {
        out.push_back(0x10000 + ((static_cast<char32_t>(u) - 0xD800) << 10) +
                      (static_cast<char32_t>(in[i + 1]) - 0xDC00));
        i++;
      }
      continue;
    }
    if (u >= 0xDC00 && u <= 0xDFFF) continue;
    out.push_back(u);
  }
  return out;
}

// Space, line break, control or another white-space character.
inline bool IsSpaceOrControl(char32_t c) {
  return c <= 0x20 || (c >= 0x7F && c <= 0xA0) || c == 0x1680 ||
         (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 ||
         c == 0x202F || c == 0x205F || c == 0x3000;
}

// ---- The buffer ----

class TypedBuffer {
 public:
  static constexpr size_t kMaxLength = 32;
  static constexpr int64_t kIdleMs = 5000;

  ~TypedBuffer() { Clear(); }

  void Add(const std::u32string& text, int64_t now_ms, bool injected) {
    for (char32_t c : text) {
      chars_.push_back(c);
      from_software_.push_back(injected);
    }
    if (chars_.size() > kMaxLength) {
      const size_t extra = chars_.size() - kMaxLength;
      std::fill(chars_.begin(), chars_.begin() + extra, U' ');
      chars_.erase(chars_.begin(), chars_.begin() + extra);
      from_software_.erase(from_software_.begin(),
                           from_software_.begin() + extra);
    }
    last_key_ms_ = now_ms;
    has_key_ = true;
  }

  void Backspace(int64_t now_ms) {
    if (!chars_.empty()) {
      chars_.back() = U' ';
      chars_.pop_back();
      from_software_.pop_back();
    }
    last_key_ms_ = now_ms;
    has_key_ = true;
  }

  // Overwrites before letting go, so no old character is left in memory.
  void Clear() {
    std::fill(chars_.begin(), chars_.end(), U' ');
    chars_.clear();
    chars_.shrink_to_fit();
    from_software_.clear();
    has_key_ = false;
  }

  // Empties the buffer if 5 s passed without a key. True if it did.
  bool ExpireIfIdle(int64_t now_ms) {
    if (!has_key_ || now_ms - last_key_ms_ < kIdleMs) return false;
    Clear();
    return true;
  }

  // How long until the idle clear is due: 5 s after the last key, never
  // negative. False when there is nothing to clear (C9).
  bool MsUntilIdleClear(int64_t now_ms, int64_t* ms) const {
    if (chars_.empty() || !has_key_) return false;
    *ms = std::max<int64_t>(0, last_key_ms_ + kIdleMs - now_ms);
    return true;
  }

  // True if any of the last [length] characters came from other software.
  bool LastHasInjected(size_t length) const {
    const size_t from = from_software_.size() - std::min(length, from_software_.size());
    for (size_t i = from; i < from_software_.size(); i++) {
      if (from_software_[i]) return true;
    }
    return false;
  }

  size_t Count() const { return chars_.size(); }
  const std::u32string& Contents() const { return chars_; }

 private:
  std::u32string chars_;
  std::vector<bool> from_software_;
  int64_t last_key_ms_ = 0;
  bool has_key_ = false;
};

// ---- The table: shortcut -> snippet id, from Dart (setTable) ----

class ShortcutTable {
 public:
  ShortcutTable() = default;

  // Entries that break the rules (2 to 32 characters, no spaces, line
  // breaks or control characters, valid UTF-8) are left out.
  explicit ShortcutTable(const std::vector<std::pair<int, std::string>>& in) {
    for (const auto& [id, utf8] : in) {
      std::u32string s;
      if (!Utf8ToUtf32(utf8, &s)) continue;
      if (s.size() < 2 || s.size() > TypedBuffer::kMaxLength) continue;
      if (std::any_of(s.begin(), s.end(), IsSpaceOrControl)) continue;
      longest_ = std::max(longest_, s.size());
      by_text_[s] = id;
    }
  }

  size_t Size() const { return by_text_.size(); }

  // The longest shortcut the buffer ends with. The delete count is in
  // characters (code points); see the M1.5 hand-off for dead keys and IMEs.
  bool Match(const std::u32string& buffer, int* id, int* delete_count,
             int* length) const {
    if (buffer.size() < 2 || longest_ == 0) return false;
    for (size_t n = std::min(buffer.size(), longest_); n >= 2; n--) {
      auto it = by_text_.find(buffer.substr(buffer.size() - n));
      if (it != by_text_.end()) {
        *id = it->second;
        *delete_count = static_cast<int>(n);
        *length = static_cast<int>(n);
        return true;
      }
    }
    return false;
  }

 private:
  std::unordered_map<std::u32string, int> by_text_;
  size_t longest_ = 0;
};

// ---- Keys ----

struct TypedKey {
  enum class Kind { kText, kBackspace, kReset, kIgnore };
  Kind kind = Kind::kIgnore;
  std::u32string text;

  static TypedKey Text(std::u32string t) { return {Kind::kText, std::move(t)}; }
  static TypedKey Backspace() { return {Kind::kBackspace, {}}; }
  static TypedKey Reset() { return {Kind::kReset, {}}; }
  static TypedKey Ignore() { return {Kind::kIgnore, {}}; }
};

struct KeyFlags {
  bool ctrl = false;
  bool alt = false;
  bool right_alt = false;  // with ctrl: AltGr
  bool win = false;
};

// [chars] is what ToUnicodeEx gave for the key (already UTF-32).
inline TypedKey ClassifyWindowsKey(uint32_t vk, const KeyFlags& f,
                                   const std::u32string& chars) {
  const bool altgr = f.ctrl && f.alt && f.right_alt;
  if (!altgr && (f.ctrl || f.alt)) return TypedKey::Reset();
  if (f.win) return TypedKey::Reset();
  if (vk == 0x08) return TypedKey::Backspace();  // VK_BACK
  switch (vk) {
    case 0x0D:  // VK_RETURN
    case 0x09:  // VK_TAB
    case 0x1B:  // VK_ESCAPE
    case 0x2E:  // VK_DELETE
    case 0x25:  // arrows
    case 0x26:
    case 0x27:
    case 0x28:
    case 0x24:  // VK_HOME
    case 0x23:  // VK_END
    case 0x21:  // VK_PRIOR
    case 0x22:  // VK_NEXT
    case 0x2D:  // VK_INSERT (Narrator key)
    case 0x14:  // VK_CAPITAL (Narrator key)
      return TypedKey::Reset();
    default:
      break;
  }
  if (chars.empty()) return TypedKey::Ignore();
  for (char32_t c : chars) {
    if (c < 0x20 || c == 0x7F) return TypedKey::Ignore();
  }
  return TypedKey::Text(chars);
}

// ---- Matching and skip rules ----

struct TypedKeyContext {
  bool front_is_self = false;   // rule 2
  bool front_ignored = false;   // rule 3
  bool injected = false;        // rule 4 (LLKHF_INJECTED, not our marker)
  bool front_elevated = false;  // rule 5 (or its level can't be read)
};

struct TypedOutcome {
  enum class Kind { kNone, kMatched, kSkipped };
  Kind kind = Kind::kNone;
  int snippet_id = 0;
  int delete_count = 0;
  const char* code = "";  // a log code for kSkipped

  static TypedOutcome None() { return {}; }
  static TypedOutcome Matched(int id, int count) {
    return {Kind::kMatched, id, count, ""};
  }
  static TypedOutcome Skipped(const char* code) {
    return {Kind::kSkipped, 0, 0, code};
  }
};

// The buffer plus the table and skip rules 2 to 5. One per app, used on the
// hook's thread only.
class TypedShortcutMatcher {
 public:
  void SetTable(const std::vector<std::pair<int, std::string>>& entries) {
    table_ = ShortcutTable(entries);
    buffer_.Clear();
  }

  void Reset() { buffer_.Clear(); }
  void Tick(int64_t now_ms) { buffer_.ExpireIfIdle(now_ms); }
  // When the hook thread's one-shot timer should call Tick next: exactly
  // 5 s after the last key; false for no timer (C9).
  bool MsUntilIdleClear(int64_t now_ms, int64_t* ms) const {
    return buffer_.MsUntilIdleClear(now_ms, ms);
  }
  size_t BufferCount() const { return buffer_.Count(); }
  size_t TableSize() const { return table_.Size(); }

  TypedOutcome Handle(const TypedKey& key, const TypedKeyContext& ctx,
                      int64_t now_ms) {
    buffer_.ExpireIfIdle(now_ms);
    switch (key.kind) {
      case TypedKey::Kind::kIgnore:
        return TypedOutcome::None();
      case TypedKey::Kind::kReset:
        buffer_.Clear();
        return TypedOutcome::None();
      case TypedKey::Kind::kBackspace:
        buffer_.Backspace(now_ms);
        return TypedOutcome::None();
      case TypedKey::Kind::kText:
        break;
    }
    buffer_.Add(key.text, now_ms, ctx.injected);
    int id = 0, count = 0, length = 0;
    if (!table_.Match(buffer_.Contents(), &id, &count, &length)) {
      return TypedOutcome::None();
    }
    // Skips keep the buffer. Keys from other software never fire, not even
    // when the user types only the last key (D5).
    if (buffer_.LastHasInjected(static_cast<size_t>(length))) {
      return TypedOutcome::Skipped("shortcutSkippedInjected");
    }
    if (ctx.front_is_self) return TypedOutcome::None();
    if (ctx.front_ignored) {
      return TypedOutcome::Skipped("shortcutSkippedIgnoredApp");
    }
    if (ctx.front_elevated) return TypedOutcome::Skipped("shortcutSkippedAdmin");
    buffer_.Clear();
    return TypedOutcome::Matched(id, count);
  }

 private:
  TypedBuffer buffer_;
  ShortcutTable table_;
};

// Rule 6: after a match, UI Automation's IsPassword for the focused element,
// with a 100 ms limit. "Can't tell" means don't fire.
enum class FieldState { kNormal, kPassword, kUnknown };
constexpr int kFieldCheckLimitMs = 100;

// Null if the shortcut may fire, otherwise the log code.
inline const char* DecideField(FieldState s) {
  switch (s) {
    case FieldState::kNormal:
      return nullptr;
    case FieldState::kPassword:
      return "shortcutSkippedPassword";
    case FieldState::kUnknown:
      break;
  }
  return "shortcutSkippedUnknownField";
}

// ---- Threads (R1) ----
//
// Both low-level hooks run on their own thread with its own message loop, so
// nothing else Kusunga does (Dart, the picker's paste, UI Automation) can
// make them answer late; Windows silently removes a hook that does. The
// matcher, the front-window state and the ignore set live on that thread
// only. These are the pieces other threads share with it.

// Settings the UI thread hands to the hook thread: put here under a short
// lock, then the hook thread is woken and takes them. Only the latest table
// and ignore set count.
class HookInbox {
 public:
  struct Batch {
    bool has_table = false;
    std::vector<std::pair<int, std::string>> table;
    bool has_ignored = false;
    std::set<std::string> ignored;
    bool reset = false;  // empty the buffer (a replacement happened)
  };

  void PutTable(std::vector<std::pair<int, std::string>> table) {
    std::lock_guard<std::mutex> lock(mutex_);
    next_.has_table = true;
    next_.table = std::move(table);
  }
  void PutIgnored(std::set<std::string> ignored) {
    std::lock_guard<std::mutex> lock(mutex_);
    next_.has_ignored = true;
    next_.ignored = std::move(ignored);
  }
  void PutReset() {
    std::lock_guard<std::mutex> lock(mutex_);
    next_.reset = true;
  }
  // The hook thread takes everything put since the last call.
  Batch Take() {
    std::lock_guard<std::mutex> lock(mutex_);
    Batch out = std::move(next_);
    next_ = Batch();
    return out;
  }

 private:
  std::mutex mutex_;
  Batch next_;
};

// Match ids (C2): an opaque counter, never anything typed. It fits in 23
// bits so it can travel with the delete count in one LPARAM (PackMatch).
constexpr uint32_t kMaxMatchId = 0x7FFFFF;

// The match Dart may still answer with "replace": its id, the window it
// happened in and how much the user did since (any of it cancels). Only
// the newest match is valid: a newer one makes older ids worthless, so a
// late "replace" for an older match never deletes text (C2). The hook
// thread begins it and counts; the UI thread reads and ends it.
class PendingMatch {
 public:
  explicit PendingMatch(uint32_t last_id = 0) : last_id_(last_id) {}

  uint32_t Begin(uintptr_t window) {
    std::lock_guard<std::mutex> lock(mutex_);
    last_id_ = last_id_ >= kMaxMatchId ? 1 : last_id_ + 1;
    id_ = last_id_;
    window_ = window;
    inputs_ = 0;
    return id_;
  }
  // A key or a mouse press by the user after the match.
  void NoteInput() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (id_ != 0) inputs_++;
  }
  // True if [id] is the newest match, with its window and input count.
  bool Get(uint32_t id, uintptr_t* window, int* inputs) const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (id == 0 || id != id_) return false;
    if (window) *window = window_;
    if (inputs) *inputs = inputs_;
    return true;
  }
  // Input since [id]; a large number when it is not the newest match, which
  // cancels a replacement.
  int InputsSince(uint32_t id) const {
    int inputs = 0;
    return Get(id, nullptr, &inputs) ? inputs : 1 << 30;
  }
  // [id] was answered: nothing is pending unless a newer match came.
  void End(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (id == id_) Reset();
  }
  void Clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    Reset();
  }

 private:
  void Reset() {
    id_ = 0;
    window_ = 0;
    inputs_ = 0;
  }

  mutable std::mutex mutex_;
  uint32_t last_id_;
  uint32_t id_ = 0;  // 0: nothing pending
  uintptr_t window_ = 0;
  int inputs_ = 0;
};

// Any mouse button press (C5): the cursor may have moved, so the buffer
// empties, and a match still waiting for its replacement counts it as
// input, which cancels the replacement.
inline void OnMouseDown(TypedShortcutMatcher& matcher, PendingMatch& pending) {
  matcher.Reset();
  pending.NoteInput();
}

// The delete count (1 to 32) and the match id in one positive number that
// fits a 32-bit LPARAM, for the field check's message to the UI thread.
inline int64_t PackMatch(int delete_count, uint32_t match_id) {
  return (static_cast<int64_t>(match_id & kMaxMatchId) << 8) |
         (delete_count & 0xFF);
}
inline void UnpackMatch(int64_t packed, int* delete_count, uint32_t* match_id) {
  *delete_count = static_cast<int>(packed & 0xFF);
  *match_id = static_cast<uint32_t>(packed >> 8) & kMaxMatchId;
}

// Rule 6 runs on its own persistent thread (UI Automation can take long, or
// hang in a busy app). The hook thread only pushes a request; a newer one
// replaces an older one not yet taken.
struct FieldCheckRequest {
  int snippet_id;
  int delete_count;
  int64_t asked_ms;
  uint32_t match_id;
};

class FieldCheckQueue {
 public:
  void Push(const FieldCheckRequest& r) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      latest_ = r;
      has_ = true;
    }
    wake_.notify_one();
  }
  // Waits for a request. False once stopped.
  bool Pop(FieldCheckRequest* out) {
    std::unique_lock<std::mutex> lock(mutex_);
    wake_.wait(lock, [this] { return has_ || stopped_; });
    if (stopped_) return false;
    *out = latest_;
    has_ = false;
    return true;
  }
  void Stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopped_ = true;
    }
    wake_.notify_all();
  }

 private:
  std::mutex mutex_;
  std::condition_variable wake_;
  FieldCheckRequest latest_{0, 0, 0, 0};
  bool has_ = false;
  bool stopped_ = false;
};

// An answer later than 100 ms after the match counts as "can't tell", which
// means don't fire, whatever it said.
inline FieldState FieldStateInTime(FieldState s, int64_t asked_ms,
                                   int64_t answered_ms) {
  return answered_ms - asked_ms > kFieldCheckLimitMs ? FieldState::kUnknown : s;
}

// Hook health. Every 2 s the hook thread compares the last input the system
// saw (GetLastInputInfo) with the last time its own hooks ran (both
// GetTickCount). Input more than 1 s newer than any hook call means Windows
// removed the hooks: they are put back, and if that fails the status says
// "stopped". An administrator window or the secure desktop in front gets
// input our hooks never see, so then silence proves nothing.
constexpr int kHookCheckMs = 2000;
constexpr uint32_t kHookSilenceMs = 1000;

inline bool HookLooksRemoved(uint32_t last_input_tick, uint32_t last_hook_tick,
                             bool front_hidden_from_hooks) {
  if (front_hidden_from_hooks) return false;
  // Signed difference, so the 49.7-day wrap of GetTickCount is harmless.
  const int32_t newer = static_cast<int32_t>(last_input_tick - last_hook_tick);
  return newer > static_cast<int32_t>(kHookSilenceMs);
}

// ---- Replacing (design note, "Replacing"; PM decision D2 A) ----

// In dwExtraInfo of every key Kusunga sends (SendInput), so the hook never
// feeds Kusunga's own Backspaces and Ctrl+V back into the buffer.
constexpr uintptr_t kOwnKeyMarker = 0x4B534E47;  // "KSNG"

inline bool IsOwnKey(uintptr_t extra_info) { return extra_info == kOwnKeyMarker; }

// What a replacement needs from Windows. Window handles are plain numbers.
class ReplacePlatform {
 public:
  virtual ~ReplacePlatform() = default;
  virtual uintptr_t Foreground() = 0;
  // Keys the user typed since the match (any of them cancels).
  virtual int KeysSinceMatch() = 0;
  // Keeps the clipboard text now, in memory, to put back. False if the
  // clipboard holds no text, or anything besides text and markers
  // (CanRestoreClipboard).
  virtual bool SavePrevious() = 0;
  virtual void SendBackspaces(int n) = 0;
  // Writes the snippet (UTF-8) excluded from clipboard monitoring and
  // history, as Kusunga's own change, and gives its sequence number.
  virtual bool WriteSnippet(const std::string& text, uint32_t* sequence) = 0;
  virtual void SendPaste() = 0;
  virtual void Schedule(int ms, std::function<void()> work) = 0;
  virtual uint32_t Sequence() = 0;
  // Writes the saved text back as Kusunga's own change (RestoreMarks).
  virtual void RestorePrevious() = 0;
  // Overwrites and lets go of the saved text.
  virtual void ForgetPrevious() = 0;
};

// Forgets the saved previous text when it goes out of scope, unless a
// restore took it over (Keep). So every exit of a replacement that
// schedules no restore lets go of it (C3).
class SavedTextGuard {
 public:
  explicit SavedTextGuard(ReplacePlatform* p) : p_(p) {}
  ~SavedTextGuard() {
    if (!kept_) p_->ForgetPrevious();
  }
  SavedTextGuard(const SavedTextGuard&) = delete;
  SavedTextGuard& operator=(const SavedTextGuard&) = delete;
  void Keep() { kept_ = true; }

 private:
  ReplacePlatform* p_;
  bool kept_ = false;
};

// The snippet a shortcut pastes is excluded from clipboard monitors. The
// previous text put back after it (D2) is always marked with all three
// "don't keep" formats, whatever marks it had: a password manager may have
// used any one of them (CanIncludeInClipboardHistory=0 alone, for example),
// so marking it always is the only way never to make it weaker (S1).
inline ClipboardMarks SnippetMarks() { return {true, false, false}; }
inline ClipboardMarks RestoreMarks() { return {true, true, true}; }

// One clipboard format, as EnumClipboardFormats lists it: its number and,
// for a registered format (0xC000 and up), its name.
struct ClipboardFormatInfo {
  uint32_t id;
  std::string name;
};

// Whether the previous copy may be put back after a shortcut (design note,
// "Replacing" step 4; C4): only when every format was text or a "don't
// keep" marker, and Unicode text is there. Anything else (rich text, HTML,
// an image, files) leaves the snippet on the clipboard, because Kusunga
// only puts back text. Decided before any text is read.
inline bool CanRestoreClipboard(const std::vector<ClipboardFormatInfo>& formats) {
  constexpr uint32_t kText = 1, kOemText = 7, kUnicodeText = 13, kLocale = 16;
  static const char* const kMarkers[] = {
      "ExcludeClipboardContentFromMonitorProcessing",
      "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard",
      "Clipboard Viewer Ignore", "com.wnasoni.kusunga.self"};
  bool unicode = false;
  for (const auto& f : formats) {
    if (f.id == kUnicodeText) {
      unicode = true;
      continue;
    }
    if (f.id == kText || f.id == kOemText || f.id == kLocale) continue;
    const bool marker =
        f.id >= 0xC000 &&
        std::any_of(std::begin(kMarkers), std::end(kMarkers),
                    [&](const char* m) { return f.name == m; });
    if (!marker) return false;
  }
  return unicode;
}

enum class ReplaceResult { kReplaced, kCancelled, kCopied, kFailed };

// The names Dart expects (lib/shortcuts/channel_typed_shortcuts_port.dart).
inline const char* ReplaceResultName(ReplaceResult r) {
  switch (r) {
    case ReplaceResult::kReplaced:
      return "replaced";
    case ReplaceResult::kCancelled:
      return "cancelled";
    case ReplaceResult::kCopied:
      return "copied";
    case ReplaceResult::kFailed:
      break;
  }
  return "failed";
}

constexpr int kRestoreDelayMs = 500;

// Check nothing moved since the match, write the snippet, delete the code,
// paste, then put the previous text back after 0.5 s unless something else
// was copied meanwhile. One flow for the app: a second shortcut within 0.5 s
// takes the restore over, so the user's own text comes back, not the first
// snippet. [p] outlives the flow.
class ReplaceFlow {
 public:
  explicit ReplaceFlow(ReplacePlatform* p) : p_(p) {}

  ReplaceResult Run(int delete_count, const std::string& text,
                    uintptr_t match_window) {
    if (p_->Foreground() != match_window || p_->KeysSinceMatch() != 0) {
      return ReplaceResult::kCancelled;
    }
    // The platform still holds the user's own text from a restore waiting
    // for the first snippet, or reads the clipboard now.
    const bool reused = pending_ && p_->Sequence() == pending_mine_;
    const uint32_t earlier_mine = pending_mine_;
    pending_ = false;
    const bool has_text = reused || p_->SavePrevious();
    SavedTextGuard guard(p_);
    // The snippet first: if it can't be written, nothing is deleted and the
    // code stays where the user typed it (C3).
    uint32_t mine = 0;
    if (!p_->WriteSnippet(text, &mine)) {
      if (reused) {  // the earlier restore still puts the user's text back
        pending_ = true;
        pending_mine_ = earlier_mine;
        guard.Keep();
      }
      return ReplaceResult::kFailed;
    }
    p_->SendBackspaces(delete_count);
    p_->SendPaste();
    if (has_text) {
      pending_ = true;
      pending_mine_ = mine;
      guard.Keep();
      p_->Schedule(kRestoreDelayMs, [this, mine] { RestoreDue(mine); });
    }
    return ReplaceResult::kReplaced;
  }

 private:
  void RestoreDue(uint32_t mine) {
    if (!pending_ || pending_mine_ != mine) return;  // a newer one took over
    pending_ = false;
    if (p_->Sequence() == mine) p_->RestorePrevious();
    p_->ForgetPrevious();
  }

  ReplacePlatform* p_;
  bool pending_ = false;
  uint32_t pending_mine_ = 0;
};

// Replaces for [match_id] only if it is still the newest match (C2): an
// answer for an older match is cancelled and sends nothing. The match ends
// either way.
inline ReplaceResult ReplaceMatch(ReplaceFlow& flow, PendingMatch& pending,
                                  uint32_t match_id, int delete_count,
                                  const std::string& text) {
  uintptr_t window = 0;
  if (!pending.Get(match_id, &window, nullptr)) return ReplaceResult::kCancelled;
  const ReplaceResult result = flow.Run(delete_count, text, window);
  pending.End(match_id);
  return result;
}

}  // namespace kusunga

#endif  // RUNNER_TYPED_SHORTCUT_POLICY_H_
