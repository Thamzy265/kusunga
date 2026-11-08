// Tests for typed_shortcut_policy.h: the Windows typed-shortcut buffer,
// matcher, key classes and skip rules (M1.5, docs/design/typed-shortcuts.md;
// ADR 0004). No Windows dependencies, so this builds anywhere (see
// tool/test_windows_policy.sh). It is not part of the Windows build.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "typed_shortcut_policy.h"

using namespace kusunga;

static int failures = 0;
#define CHECK(cond)                                         \
  do {                                                      \
    if (!(cond)) {                                          \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond); \
      failures++;                                           \
    }                                                       \
  } while (0)

static TypedOutcome TypeText(TypedShortcutMatcher& m, const std::u32string& s,
                             const TypedKeyContext& ctx = TypedKeyContext{},
                             int64_t now = 0) {
  TypedOutcome last;
  for (char32_t c : s) {
    last = m.Handle(TypedKey::Text(std::u32string(1, c)), ctx, now);
  }
  return last;
}

static bool IsMatch(const TypedOutcome& o, int id, int count) {
  return o.kind == TypedOutcome::Kind::kMatched && o.snippet_id == id &&
         o.delete_count == count;
}

static bool IsSkip(const TypedOutcome& o, const char* code) {
  return o.kind == TypedOutcome::Kind::kSkipped && std::string(o.code) == code;
}

static bool IsNone(const TypedOutcome& o) {
  return o.kind == TypedOutcome::Kind::kNone;
}

static TypedShortcutMatcher Make() {
  TypedShortcutMatcher m;
  m.SetTable({{7, ";email"}});
  return m;
}

static void TestBuffer() {
  TypedBuffer b;
  b.Add(U"a", 0, false);
  b.Add(std::u32string(40, U'b'), 1, false);
  CHECK(b.Count() == 32);
  CHECK(b.Contents() == std::u32string(32, U'b'));
  CHECK(TypedBuffer::kMaxLength == 32);

  TypedBuffer idle;
  idle.Add(U";em", 1000, false);
  CHECK(!idle.ExpireIfIdle(5999));
  CHECK(idle.Count() == 3);
  CHECK(idle.ExpireIfIdle(6000));
  CHECK(idle.Count() == 0);
  CHECK(TypedBuffer::kIdleMs == 5000);

  TypedBuffer back;
  back.Add(U";emx", 0, false);
  back.Backspace(1);
  CHECK(back.Contents() == U";em");
  back.Clear();
  back.Backspace(2);
  CHECK(back.Count() == 0);
}

static void TestTable() {
  ShortcutTable t({{1, ";email"},
                   {2, "e"},
                   {3, std::string(33, ';')},
                   {4, "; x"},
                   {5, ";a\tb"},
                   {6, ";a\nb"},
                   {7, ";ok"},
                   {8, std::string("\xff\xfe", 2)}});  // not UTF-8
  CHECK(t.Size() == 2);

  ShortcutTable longest({{1, "il"}, {2, ";email"}});
  int id = 0, count = 0, length = 0;
  CHECK(longest.Match(U";email", &id, &count, &length));
  CHECK(id == 2 && count == 6 && length == 6);

  ShortcutTable cased({{1, ";email"}});
  CHECK(!cased.Match(U";Email", &id, &count, &length));

  // UTF-8 from Dart: ";é😀" is three characters.
  ShortcutTable utf({{1, ";\xc3\xa9\xf0\x9f\x98\x80"}});
  CHECK(utf.Match(U";é\U0001F600", &id, &count, &length));
  CHECK(count == 3);
}

static void TestMatcher() {
  {
    auto m = Make();
    CHECK(IsNone(TypeText(m, U";emai")));
    CHECK(IsMatch(TypeText(m, U"l"), 7, 6));
    CHECK(m.BufferCount() == 0);  // a match clears the buffer
  }
  {
    // ;em, a click elsewhere, then ail never fires.
    auto m = Make();
    TypeText(m, U";em");
    m.Handle(TypedKey::Reset(), TypedKeyContext{}, 0);
    CHECK(m.BufferCount() == 0);
    CHECK(IsNone(TypeText(m, U"ail")));
  }
  {
    auto m = Make();
    TypeText(m, U";em");
    m.Reset();
    CHECK(m.BufferCount() == 0);
  }
  {
    auto m = Make();
    TypeText(m, U";ema", TypedKeyContext{}, 0);
    CHECK(IsNone(m.Handle(TypedKey::Text(U"il"), TypedKeyContext{}, 5000)));
  }
  {
    auto m = Make();
    TypeText(m, U";ema", TypedKeyContext{}, 0);
    m.Tick(4999);
    CHECK(m.BufferCount() == 4);
    m.Tick(5000);
    CHECK(m.BufferCount() == 0);
  }
  {
    auto m = Make();
    TypeText(m, U";emx");
    m.Handle(TypedKey::Backspace(), TypedKeyContext{}, 0);
    CHECK(IsMatch(TypeText(m, U"ail"), 7, 6));
  }
  {
    auto m = Make();
    TypeText(m, U";ema");
    CHECK(IsNone(m.Handle(TypedKey::Ignore(), TypedKeyContext{}, 0)));
    CHECK(IsMatch(TypeText(m, U"il"), 7, 6));
  }
  {
    // Skip rules keep the buffer.
    TypedKeyContext self;
    self.front_is_self = true;
    auto a = Make();
    CHECK(IsNone(TypeText(a, U";email", self)));

    TypedKeyContext ignored;
    ignored.front_ignored = true;
    auto b = Make();
    CHECK(IsSkip(TypeText(b, U";email", ignored), "shortcutSkippedIgnoredApp"));
    CHECK(b.BufferCount() == 6);

    TypedKeyContext admin;
    admin.front_elevated = true;
    auto c = Make();
    CHECK(IsSkip(TypeText(c, U";email", admin), "shortcutSkippedAdmin"));
  }
  {
    // Keys sent by other software (LLKHF_INJECTED) never fire (D5).
    TypedKeyContext injected;
    injected.injected = true;
    auto m = Make();
    CHECK(IsSkip(TypeText(m, U";email", injected), "shortcutSkippedInjected"));
    m.Reset();
    TypeText(m, U";emai", injected);
    CHECK(IsSkip(TypeText(m, U"l"), "shortcutSkippedInjected"));
    m.Reset();
    TypeText(m, U"xyz", injected);
    CHECK(IsMatch(TypeText(m, U";email"), 7, 6));
  }
  {
    auto m = Make();
    TypeText(m, U";ema");
    m.SetTable({{9, ";mob"}});
    CHECK(m.BufferCount() == 0);
    CHECK(IsNone(TypeText(m, U";email")));
    CHECK(IsMatch(TypeText(m, U";mob"), 9, 4));
  }
  {
    TypedShortcutMatcher empty;
    CHECK(IsNone(TypeText(empty, U";email")));
  }
}

static void TestFieldCheck() {
  // Rule 6: the focused field is checked only after a match; a password or
  // a field that can't be read means don't fire.
  CHECK(DecideField(FieldState::kNormal) == nullptr);
  CHECK(std::string(DecideField(FieldState::kPassword)) ==
        "shortcutSkippedPassword");
  CHECK(std::string(DecideField(FieldState::kUnknown)) ==
        "shortcutSkippedUnknownField");
  CHECK(kFieldCheckLimitMs == 100);
}

static void TestClassify() {
  KeyFlags none;
  CHECK(ClassifyWindowsKey(0x41, none, U"a").kind == TypedKey::Kind::kText);
  CHECK(ClassifyWindowsKey(0xBA, none, U";").text == U";");
  CHECK(ClassifyWindowsKey(0x08, none, U"\b").kind ==
        TypedKey::Kind::kBackspace);
  // Enter, Tab, Escape, Delete, arrows, Home, End, Page Up/Down, and the
  // Narrator keys Insert and Caps Lock.
  for (uint32_t vk : {0x0D, 0x09, 0x1B, 0x2E, 0x25, 0x26, 0x27, 0x28, 0x24,
                      0x23, 0x21, 0x22, 0x2D, 0x14}) {
    CHECK(ClassifyWindowsKey(vk, none, U"").kind == TypedKey::Kind::kReset);
  }
  KeyFlags ctrl;
  ctrl.ctrl = true;
  CHECK(ClassifyWindowsKey(0x56, ctrl, U"").kind == TypedKey::Kind::kReset);
  KeyFlags alt;
  alt.alt = true;
  CHECK(ClassifyWindowsKey(0x46, alt, U"").kind == TypedKey::Kind::kReset);
  KeyFlags win;
  win.win = true;
  CHECK(ClassifyWindowsKey(0x56, win, U"").kind == TypedKey::Kind::kReset);
  // AltGr (Ctrl + right Alt) types a character, as on a German layout.
  KeyFlags altgr;
  altgr.ctrl = true;
  altgr.alt = true;
  altgr.right_alt = true;
  CHECK(ClassifyWindowsKey(0x51, altgr, U"@").kind == TypedKey::Kind::kText);
  // No character, or a control character: ignored.
  CHECK(ClassifyWindowsKey(0x70, none, U"").kind == TypedKey::Kind::kIgnore);
  CHECK(ClassifyWindowsKey(0x41, none, U"\x01").kind ==
        TypedKey::Kind::kIgnore);
}

static void TestUtf() {
  CHECK(Utf16ToUtf32(u"a\U0001F600") == U"a\U0001F600");
  // A lone surrogate is dropped, never passed on as half a character.
  std::u16string lone;
  lone.push_back(static_cast<char16_t>(0xD800));
  lone.push_back(u'a');
  CHECK(Utf16ToUtf32(lone) == U"a");
}

static void TestSpeed() {
  std::vector<std::pair<int, std::string>> entries;
  for (int i = 0; i < 1000; i++) {
    entries.push_back({i, ";s" + std::to_string(i) + "x"});
  }
  TypedShortcutMatcher m;
  m.SetTable(entries);
  const auto start = std::chrono::steady_clock::now();
  for (int i = 0; i < 1000; i++) {
    m.Handle(TypedKey::Text(i % 2 ? U"a" : U"b"), TypedKeyContext{}, i);
  }
  const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::steady_clock::now() - start)
                      .count();
  CHECK(ms < 500);  // 1 ms per key budget (p99), with room to spare
}

// ---- Replacement (design note, "Replacing"; PM decision D2 A) ----

class FakeReplace : public ReplacePlatform {
 public:
  std::vector<std::string> log;
  uintptr_t foreground = 100;
  int keys_after = 0;
  bool has_previous = true;
  bool write_ok = true;
  uint32_t sequence = 10;
  std::vector<std::pair<int, std::function<void()>>> scheduled;
  int restores = 0;

  uintptr_t Foreground() override { return foreground; }
  int KeysSinceMatch() override { return keys_after; }
  bool SavePrevious() override {
    log.push_back("readPrevious");
    return has_previous;
  }
  void SendBackspaces(int n) override {
    log.push_back("backspace" + std::to_string(n));
  }
  bool WriteSnippet(const std::string&, uint32_t* seq) override {
    log.push_back("write");
    if (!write_ok) return false;
    *seq = ++sequence;
    return true;
  }
  void SendPaste() override { log.push_back("paste"); }
  void Schedule(int ms, std::function<void()> work) override {
    scheduled.push_back({ms, std::move(work)});
  }
  uint32_t Sequence() override { return sequence; }
  void RestorePrevious() override {
    restores++;
    sequence++;
  }
};

static void TestReplace() {
  {
    FakeReplace p;
    CHECK(ReplaceFlow(&p).Run(6, "will@example.com", 100) == ReplaceResult::kReplaced);
    CHECK((p.log == std::vector<std::string>{"readPrevious", "backspace6",
                                              "write", "paste"}));
    CHECK(p.scheduled.size() == 1 && p.scheduled[0].first == 500);
    p.scheduled[0].second();
    CHECK(p.restores == 1);
  }
  {
    // The user copied something else meanwhile: keep it.
    FakeReplace p;
    ReplaceFlow(&p).Run(6, "x", 100);
    p.sequence++;
    p.scheduled[0].second();
    CHECK(p.restores == 0);
  }
  {
    // Not text before: the snippet stays.
    FakeReplace p;
    p.has_previous = false;
    CHECK(ReplaceFlow(&p).Run(6, "x", 100) == ReplaceResult::kReplaced);
    CHECK(p.scheduled.empty());
  }
  {
    FakeReplace p;
    p.foreground = 200;
    CHECK(ReplaceFlow(&p).Run(6, "x", 100) == ReplaceResult::kCancelled);
    CHECK(p.log.empty());
  }
  {
    FakeReplace p;
    p.keys_after = 1;
    CHECK(ReplaceFlow(&p).Run(6, "x", 100) == ReplaceResult::kCancelled);
    CHECK(p.log.empty());
  }
  {
    FakeReplace p;
    p.write_ok = false;
    CHECK(ReplaceFlow(&p).Run(6, "x", 100) == ReplaceResult::kFailed);
    CHECK(p.log.back() == "write");
  }
  {
    // Two shortcuts within 0.5 s: the user's own text comes back.
    FakeReplace p;
    ReplaceFlow flow(&p);
    CHECK(flow.Run(6, "first", 100) == ReplaceResult::kReplaced);
    CHECK(flow.Run(4, "second", 100) == ReplaceResult::kReplaced);
    int reads = 0;
    for (const auto& l : p.log) reads += l == "readPrevious";
    CHECK(reads == 1);
    p.scheduled[0].second();
    CHECK(p.restores == 0);
    p.scheduled[1].second();
    CHECK(p.restores == 1);
  }
  CHECK(std::string(ReplaceResultName(ReplaceResult::kReplaced)) == "replaced");
  CHECK(std::string(ReplaceResultName(ReplaceResult::kCancelled)) ==
        "cancelled");
  CHECK(std::string(ReplaceResultName(ReplaceResult::kCopied)) == "copied");
  CHECK(std::string(ReplaceResultName(ReplaceResult::kFailed)) == "failed");
  // The marker on every key Kusunga sends (dwExtraInfo).
  CHECK(IsOwnKey(kOwnKeyMarker));
  CHECK(!IsOwnKey(0));
}

int main() {
  TestReplace();
  TestBuffer();
  TestTable();
  TestMatcher();
  TestFieldCheck();
  TestClassify();
  TestUtf();
  TestSpeed();
  if (failures == 0) std::printf("typed_shortcut_policy_test: all passed\n");
  return failures == 0 ? 0 : 1;
}
