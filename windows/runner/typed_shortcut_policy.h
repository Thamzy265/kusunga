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
#include <cstdint>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

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

}  // namespace kusunga

#endif  // RUNNER_TYPED_SHORTCUT_POLICY_H_
