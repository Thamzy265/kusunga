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
  bool saved = false;  // the platform holds the previous text
  int forgets = 0;
  bool SavePrevious() override {
    log.push_back("readPrevious");
    saved = has_previous;
    return has_previous;
  }
  void ForgetPrevious() override {
    saved = false;
    forgets++;
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
    if (!saved) return;
    restores++;
    sequence++;
  }
};

static void TestReplace() {
  {
    FakeReplace p;
    CHECK(ReplaceFlow(&p).Run(6, "will@example.com", 100) == ReplaceResult::kReplaced);
    // C3: the code is deleted only once the snippet is on the clipboard.
    CHECK((p.log == std::vector<std::string>{"readPrevious", "write",
                                              "backspace6", "paste"}));
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

// ---- Tester edge cases (M1.5): reset keys, skip-rule order, bounds, idle
// edges, characters and delete counts, replace races ----

static TypedKeyContext Ctx(bool self = false, bool ignored = false,
                           bool injected = false, bool elevated = false) {
  TypedKeyContext c;
  c.front_is_self = self;
  c.front_ignored = ignored;
  c.injected = injected;
  c.front_elevated = elevated;
  return c;
}

static void TestEdgeResetKeys() {
  // Every key that moves the cursor or is a command breaks ;em + ail.
  const uint32_t resets[] = {0x0D, 0x09, 0x1B, 0x2E, 0x25, 0x26, 0x27,
                             0x28, 0x24, 0x23, 0x21, 0x22, 0x2D, 0x14};
  for (uint32_t vk : resets) {
    auto m = Make();
    TypeText(m, U";em");
    TypedKey k = ClassifyWindowsKey(vk, KeyFlags{}, U"\r");
    CHECK(k.kind == TypedKey::Kind::kReset);
    m.Handle(k, TypedKeyContext{}, 1);
    CHECK(m.BufferCount() == 0);
    CHECK(IsNone(TypeText(m, U"ail")));
  }
  // Modifiers: Ctrl, Alt, Win reset; AltGr and Shift type.
  KeyFlags ctrl;
  ctrl.ctrl = true;
  KeyFlags alt;
  alt.alt = true;
  KeyFlags ralt_only;  // right Alt without Ctrl is not AltGr
  ralt_only.alt = true;
  ralt_only.right_alt = true;
  KeyFlags win;
  win.win = true;
  KeyFlags altgr;
  altgr.ctrl = true;
  altgr.alt = true;
  altgr.right_alt = true;
  KeyFlags ctrl_lalt;  // Ctrl + left Alt is not AltGr
  ctrl_lalt.ctrl = true;
  ctrl_lalt.alt = true;
  CHECK(ClassifyWindowsKey(0x41, ctrl, U"a").kind == TypedKey::Kind::kReset);
  CHECK(ClassifyWindowsKey(0x41, alt, U"a").kind == TypedKey::Kind::kReset);
  CHECK(ClassifyWindowsKey(0x41, ralt_only, U"a").kind == TypedKey::Kind::kReset);
  CHECK(ClassifyWindowsKey(0x41, win, U"a").kind == TypedKey::Kind::kReset);
  CHECK(ClassifyWindowsKey(0x41, ctrl_lalt, U"a").kind == TypedKey::Kind::kReset);
  CHECK(ClassifyWindowsKey(0x32, altgr, U"@").kind == TypedKey::Kind::kText);
  CHECK(ClassifyWindowsKey(0x41, KeyFlags{}, U"A").kind == TypedKey::Kind::kText);
  // Ctrl+Backspace deletes a word: a reset, not a Backspace.
  CHECK(ClassifyWindowsKey(0x08, ctrl, U"").kind == TypedKey::Kind::kReset);
  CHECK(ClassifyWindowsKey(0x08, KeyFlags{}, U"").kind == TypedKey::Kind::kBackspace);
  // Space is text; function keys and Shift type nothing; controls are ignored.
  CHECK(ClassifyWindowsKey(0x20, KeyFlags{}, U" ").kind == TypedKey::Kind::kText);
  CHECK(ClassifyWindowsKey(0x70, KeyFlags{}, U"").kind == TypedKey::Kind::kIgnore);
  CHECK(ClassifyWindowsKey(0x10, KeyFlags{}, U"").kind == TypedKey::Kind::kIgnore);
  CHECK(ClassifyWindowsKey(0x41, KeyFlags{}, std::u32string(1, 0x01)).kind ==
        TypedKey::Kind::kIgnore);
  CHECK(ClassifyWindowsKey(0x41, KeyFlags{}, std::u32string(1, 0x7F)).kind ==
        TypedKey::Kind::kIgnore);
  // Delete on an empty buffer stays empty and a new shortcut still fires.
  auto m = Make();
  for (int i = 0; i < 5; i++) m.Handle(TypedKey::Backspace(), TypedKeyContext{}, 0);
  CHECK(m.BufferCount() == 0);
  CHECK(IsMatch(TypeText(m, U";email"), 7, 6));
}

static void TestEdgeIdle() {
  {  // Backspace counts as a key for the idle clock.
    auto m = Make();
    TypeText(m, U";emx", TypedKeyContext{}, 0);
    m.Handle(TypedKey::Backspace(), TypedKeyContext{}, 4000);
    CHECK(IsMatch(TypeText(m, U"ail", TypedKeyContext{}, 8900), 7, 6));
  }
  {  // A key that types nothing does not.
    auto m = Make();
    TypeText(m, U";ema", TypedKeyContext{}, 0);
    m.Handle(TypedKey::Ignore(), TypedKeyContext{}, 4900);
    CHECK(IsNone(TypeText(m, U"il", TypedKeyContext{}, 5000)));
  }
  {  // Each key restarts the clock: 4999 + 4999 is alive, exactly 5000 is not.
    auto m = Make();
    TypeText(m, U";ema", TypedKeyContext{}, 0);
    m.Handle(TypedKey::Text(U"i"), TypedKeyContext{}, 4999);
    CHECK(IsMatch(m.Handle(TypedKey::Text(U"l"), TypedKeyContext{}, 9998), 7, 6));
    auto n = Make();
    TypeText(n, U";emai", TypedKeyContext{}, 0);
    CHECK(IsNone(n.Handle(TypedKey::Text(U"l"), TypedKeyContext{}, 5000)));
  }
  {  // A clock that starts late (first key at a large time) works the same.
    auto m = Make();
    TypeText(m, U";ema", TypedKeyContext{}, 1000000);
    m.Tick(1004999);
    CHECK(m.BufferCount() == 4);
    m.Tick(1005000);
    CHECK(m.BufferCount() == 0);
  }
}

static void TestEdgeSkips() {
  auto outcome = [](TypedKeyContext c) {
    auto m = Make();
    return TypeText(m, U";email", c);
  };
  // Order: injected, self (silent), ignored, admin.
  CHECK(IsSkip(outcome(Ctx(true, true, true, true)), "shortcutSkippedInjected"));
  CHECK(IsNone(outcome(Ctx(true, true, false, true))));
  CHECK(IsSkip(outcome(Ctx(false, true, false, true)), "shortcutSkippedIgnoredApp"));
  CHECK(IsSkip(outcome(Ctx(false, false, false, true)), "shortcutSkippedAdmin"));
  CHECK(IsMatch(outcome(Ctx()), 7, 6));
  {  // A skip keeps the buffer: correct and retype fires once the skip ends.
    auto m = Make();
    CHECK(IsSkip(TypeText(m, U";email", Ctx(false, true)), "shortcutSkippedIgnoredApp"));
    CHECK(m.BufferCount() == 6);
    m.Handle(TypedKey::Backspace(), TypedKeyContext{}, 1);
    CHECK(IsMatch(TypeText(m, U"l", TypedKeyContext{}, 1), 7, 6));
  }
  // One software key anywhere inside the shortcut blocks it.
  for (size_t bad = 0; bad < 6; bad++) {
    auto m = Make();
    TypedOutcome out;
    const std::u32string code = U";email";
    for (size_t i = 0; i < code.size(); i++) {
      out = m.Handle(TypedKey::Text(std::u32string(1, code[i])), Ctx(false, false, i == bad), 0);
    }
    CHECK(IsSkip(out, "shortcutSkippedInjected"));
  }
  {  // Software keys before the shortcut do not block it.
    auto m = Make();
    TypeText(m, U"hello ", Ctx(false, false, true));
    CHECK(IsMatch(TypeText(m, U";email"), 7, 6));
  }
  {  // A software key that was Backspaced away no longer blocks.
    auto m = Make();
    TypeText(m, U";emai");
    TypeText(m, U"x", Ctx(false, false, true));
    m.Handle(TypedKey::Backspace(), TypedKeyContext{}, 0);
    CHECK(IsMatch(TypeText(m, U"l"), 7, 6));
  }
  // Field check: fails closed.
  CHECK(DecideField(FieldState::kNormal) == nullptr);
  CHECK(std::string(DecideField(FieldState::kPassword)) == "shortcutSkippedPassword");
  CHECK(std::string(DecideField(FieldState::kUnknown)) == "shortcutSkippedUnknownField");
  CHECK(kFieldCheckLimitMs == 100);
}

static void TestEdgeBounds() {
  const std::u32string code = U";" + std::u32string(31, U'a');
  {
    TypedShortcutMatcher m;
    m.SetTable({{9, std::string(";") + std::string(31, 'a')}});
    TypeText(m, std::u32string(100, U'z'));
    CHECK(m.BufferCount() == 32);
    CHECK(IsMatch(TypeText(m, code), 9, 32));
  }
  {  // 33 characters is refused, not truncated.
    TypedShortcutMatcher m;
    m.SetTable({{9, std::string(";") + std::string(32, 'a')}});
    CHECK(m.TableSize() == 0);
  }
  {  // One huge key event never grows the buffer past 32.
    auto m = Make();
    m.Handle(TypedKey::Text(std::u32string(500, U'q')), TypedKeyContext{}, 0);
    CHECK(m.BufferCount() == 32);
  }
  {  // A multi-character event ending in the shortcut fires.
    auto m = Make();
    CHECK(IsMatch(m.Handle(TypedKey::Text(U"xx;email"), TypedKeyContext{}, 0), 7, 6));
  }
  {  // A shortcut inside another one fires first (finding, locked as is).
    TypedShortcutMatcher m;
    m.SetTable({{1, "ma"}, {2, ";email"}});
    const std::u32string typed = U";email";
    std::vector<TypedOutcome> outs;
    for (char32_t c : typed) {
      outs.push_back(m.Handle(TypedKey::Text(std::u32string(1, c)), TypedKeyContext{}, 0));
    }
    CHECK(IsMatch(outs[3], 1, 2));
    for (const auto& o : outs) CHECK(!IsMatch(o, 2, 6));
  }
  {  // Longest wins when two shortcuts end the same way.
    TypedShortcutMatcher m;
    m.SetTable({{1, "ab"}, {2, "xab"}});
    CHECK(IsMatch(TypeText(m, U"xab"), 2, 3));
    CHECK(IsMatch(TypeText(m, U"yab"), 1, 2));
  }
}

static void TestEdgeTable() {
  auto count = [](const std::string& s) {
    return ShortcutTable({{1, s}}).Size();
  };
  CHECK(count(std::string(32, 'a')) == 1);
  CHECK(count("ab") == 1);
  CHECK(count("\xF0\x9F\x98\x80\xF0\x9F\x98\x80") == 1);  // two emoji
  std::string e32;
  for (int i = 0; i < 32; i++) e32 += "\xF0\x9F\x98\x80";
  CHECK(count(e32) == 1);  // 32 code points = 128 bytes: counted as 32
  CHECK(count(e32 + "\xF0\x9F\x98\x80") == 0);
  CHECK(count("") == 0);
  CHECK(count("a") == 0);
  CHECK(count(std::string(33, 'a')) == 0);
  CHECK(count("a b") == 0);
  CHECK(count("a\xC2\xA0" "b") == 0);          // U+00A0
  CHECK(count("a\xC2\x85" "b") == 0);          // U+0085
  CHECK(count("a\xE2\x80\xA8" "b") == 0);      // U+2028
  CHECK(count("a\xE3\x80\x80" "b") == 0);      // U+3000
  CHECK(count("a\xE1\x9A\x80" "b") == 0);      // U+1680
  CHECK(count("a\xE2\x80\xAF" "b") == 0);      // U+202F
  CHECK(count(std::string("a\0b", 3)) == 0);   // NUL
  CHECK(count("a\x7F" "b") == 0);
  CHECK(count("a\r\nb") == 0);
  CHECK(count("a\x0B" "b") == 0);
  // Bad UTF-8 is refused: truncated, overlong, a surrogate, a lone
  // continuation, above U+10FFFF, a 5-byte form.
  CHECK(count("a\xE2\x82") == 0);
  CHECK(count("a\xC0\xAF") == 0);
  CHECK(count("a\xED\xA0\x80") == 0);
  CHECK(count("a\x80" "b") == 0);
  CHECK(count("a\xF4\x90\x80\x80") == 0);
  CHECK(count("a\xF8\x88\x80\x80\x80") == 0);
  // The refused set equals the Dart rule (lib/snippets/snippet_shortcut.dart).
  auto dart_refuses = [](char32_t r) {
    return r < 0x20 || r == 0x20 || r == 0x7F || (r >= 0x80 && r <= 0xA0) ||
           r == 0x1680 || (r >= 0x2000 && r <= 0x200A) || r == 0x2028 ||
           r == 0x2029 || r == 0x202F || r == 0x205F || r == 0x3000;
  };
  for (char32_t r = 0; r <= 0x10FFFF; r++) {
    CHECK(IsSpaceOrControl(r) == dart_refuses(r));
  }
  // Same text twice keeps the last id.
  ShortcutTable dup({{1, ";x1"}, {2, ";x1"}});
  CHECK(dup.Size() == 1);
  int id = 0, n = 0, len = 0;
  CHECK(dup.Match(U";x1", &id, &n, &len) && id == 2);
  // Case and canonical forms are compared exactly (the Swift copy treats
  // canonically equal strings as equal; see the hand-off).
  ShortcutTable cs({{1, ";Email"}, {2, "\xC3\xA9" "x"}});
  CHECK(!cs.Match(U";email", &id, &n, &len));
  CHECK(!cs.Match(U"éx", &id, &n, &len));
  CHECK(cs.Match(U"éx", &id, &n, &len) && id == 2);
}

static void TestEdgeUtf16() {
  CHECK(Utf16ToUtf32(u"a\xD83D\xDE00" "b") == U"a\U0001F600" "b");
  CHECK(Utf16ToUtf32(u"\xD83D" "a") == U"a");       // lone high surrogate dropped
  CHECK(Utf16ToUtf32(u"a\xDE00") == U"a");           // lone low surrogate dropped
  CHECK(Utf16ToUtf32(u"\xD83D") == U"");
  CHECK(Utf16ToUtf32(u"\xD83D\xD83D\xDE00") == U"\U0001F600");
  CHECK(Utf16ToUtf32(u"") == U"");
}

static void TestEdgeDeleteCounts() {
  // Windows counts code points: one Backspace per code point. Locks the
  // current rule, and the places it differs from what the Mac deletes.
  struct Case {
    std::u32string code;
    int code_points;
  };
  const Case cases[] = {
      {U";\U0001F44D\U0001F3FD", 3},                       // thumbs up + skin tone (Mac: 2)
      {U";\U0001F1EC\U0001F1E7", 3},                       // flag (Mac: 2)
      {U";\U0001F468‍\U0001F469‍\U0001F467", 6}, // family (Mac: 2)
      {U";é", 3},                                    // e + acute (Mac: 2)
      {U";é", 2},
      {U";日本", 3},
      {std::u32string(32, U'\U0001F600'), 32},
  };
  for (const auto& c : cases) {
    std::string utf8;
    for (char32_t ch : c.code) {  // tiny encoder for the test
      if (ch < 0x80) utf8 += static_cast<char>(ch);
      else if (ch < 0x800) {
        utf8 += static_cast<char>(0xC0 | (ch >> 6));
        utf8 += static_cast<char>(0x80 | (ch & 0x3F));
      } else if (ch < 0x10000) {
        utf8 += static_cast<char>(0xE0 | (ch >> 12));
        utf8 += static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
        utf8 += static_cast<char>(0x80 | (ch & 0x3F));
      } else {
        utf8 += static_cast<char>(0xF0 | (ch >> 18));
        utf8 += static_cast<char>(0x80 | ((ch >> 12) & 0x3F));
        utf8 += static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
        utf8 += static_cast<char>(0x80 | (ch & 0x3F));
      }
    }
    TypedShortcutMatcher m;
    m.SetTable({{4, utf8}});
    CHECK(IsMatch(TypeText(m, c.code), 4, c.code_points));
    CHECK(c.code_points >= 1 && c.code_points <= 32);
  }
}

static void TestEdgeReplace() {
  {  // A cancelled run leaves a pending restore alone.
    FakeReplace p;
    ReplaceFlow flow(&p);
    CHECK(flow.Run(6, "first", 100) == ReplaceResult::kReplaced);
    p.foreground = 200;
    CHECK(flow.Run(4, "second", 100) == ReplaceResult::kCancelled);
    p.scheduled[0].second();
    CHECK(p.restores == 1);
  }
  {  // Three in a row read the clipboard once and restore once.
    FakeReplace p;
    ReplaceFlow flow(&p);
    for (int i = 0; i < 3; i++) {
      CHECK(flow.Run(3, "s", 100) == ReplaceResult::kReplaced);
    }
    int reads = 0;
    for (const auto& l : p.log) reads += l == "readPrevious";
    CHECK(reads == 1);
    for (auto& w : p.scheduled) w.second();
    CHECK(p.restores == 1);
  }
  {  // The user copied between two shortcuts: the new copy is read again.
    FakeReplace p;
    ReplaceFlow flow(&p);
    flow.Run(3, "first", 100);
    p.sequence++;  // Ctrl+C
    flow.Run(3, "second", 100);
    int reads = 0;
    for (const auto& l : p.log) reads += l == "readPrevious";
    CHECK(reads == 2);
    for (auto& w : p.scheduled) w.second();
    CHECK(p.restores == 1);
  }
  {  // The key check happens before anything is sent or read.
    FakeReplace p;
    p.keys_after = 3;
    CHECK(ReplaceFlow(&p).Run(3, "x", 100) == ReplaceResult::kCancelled);
    CHECK(p.log.empty() && p.scheduled.empty());
  }
  {  // A failed write sends no paste and schedules no restore.
    FakeReplace p;
    p.write_ok = false;
    CHECK(ReplaceFlow(&p).Run(3, "x", 100) == ReplaceResult::kFailed);
    CHECK(p.scheduled.empty());
    for (const auto& l : p.log) CHECK(l != "paste");
  }
  CHECK(kRestoreDelayMs == 500);
  CHECK(kOwnKeyMarker == 0x4B534E47);
  CHECK(!IsOwnKey(0x4B534E48));
}

// S1: the text put back after a shortcut is always marked "don't keep",
// whatever marks it had, so a copy marked only CanIncludeInClipboardHistory=0
// (or not at all) never lands in Windows clipboard history, the cloud
// clipboard or another clipboard manager.
static void TestRestoreMarks() {
  ClipboardFlags history_only{};
  history_only.has_can_include = true;
  history_only.can_include_value = 0;
  CHECK(IsSecret(history_only));  // it was a secret copy
  const ClipboardMarks m = RestoreMarks();
  CHECK(m.exclude_from_monitor);
  CHECK(m.no_history);
  CHECK(m.no_cloud);
  // The same marks for a plain previous copy: never weaker.
  ClipboardFlags plain{};
  CHECK(!IsSecret(plain));
  CHECK(RestoreMarks().exclude_from_monitor && RestoreMarks().no_history &&
        RestoreMarks().no_cloud);
  // The snippet itself stays excluded from clipboard monitors.
  CHECK(SnippetMarks().exclude_from_monitor);
  // Nothing marked by default (the picker and "writeOwn" stay as they are).
  const ClipboardMarks none{};
  CHECK(!none.exclude_from_monitor && !none.no_history && !none.no_cloud);
}

// C4: the previous copy is put back only when every format was text or a
// "don't keep" marker; anything else (rich text, HTML, an image, files)
// leaves the snippet on the clipboard.
static void TestRestorableFormats() {
  const ClipboardFormatInfo unicode{13, ""}, ansi{1, ""}, oem{7, ""},
      locale{16, ""};
  CHECK(CanRestoreClipboard({unicode, ansi, oem, locale}));
  CHECK(CanRestoreClipboard(
      {unicode, {0xC001, "ExcludeClipboardContentFromMonitorProcessing"},
       {0xC002, "CanIncludeInClipboardHistory"},
       {0xC003, "CanUploadToCloudClipboard"},
       {0xC004, "Clipboard Viewer Ignore"},
       {0xC005, "com.wnasoni.kusunga.self"}}));
  CHECK(!CanRestoreClipboard({unicode, {0xC010, "Rich Text Format"}}));
  CHECK(!CanRestoreClipboard({unicode, {0xC011, "HTML Format"}}));
  CHECK(!CanRestoreClipboard({unicode, {2, ""}}));   // CF_BITMAP
  CHECK(!CanRestoreClipboard({unicode, {15, ""}}));  // CF_HDROP (files)
  CHECK(!CanRestoreClipboard({unicode, {8, ""}}));   // CF_DIB
  CHECK(!CanRestoreClipboard({}));
  CHECK(!CanRestoreClipboard({ansi}));  // no Unicode text to read
  CHECK(!CanRestoreClipboard(
      {{0xC001, "ExcludeClipboardContentFromMonitorProcessing"}}));
  // A registered name is matched exactly, not by prefix.
  CHECK(!CanRestoreClipboard({unicode, {0xC020, "CanIncludeInClipboardHistoryX"}}));
  CHECK(!CanRestoreClipboard({unicode, {0xC021, ""}}));  // unnamed custom
}

// C3: the snippet is written before anything is deleted, and the previous
// text is forgotten on every exit that schedules no restore.
static void TestWriteFirstAndForget() {
  {  // A failed write deletes nothing and keeps nothing.
    FakeReplace p;
    p.write_ok = false;
    CHECK(ReplaceFlow(&p).Run(6, "x", 100) == ReplaceResult::kFailed);
    for (const auto& l : p.log) CHECK(l.rfind("backspace", 0) != 0);
    CHECK(!p.saved);
  }
  {  // Nothing to put back: forgotten at once.
    FakeReplace p;
    p.has_previous = false;
    CHECK(ReplaceFlow(&p).Run(6, "x", 100) == ReplaceResult::kReplaced);
    CHECK(!p.saved);
  }
  {  // Kept for the restore, then forgotten once it is put back.
    FakeReplace p;
    ReplaceFlow flow(&p);
    CHECK(flow.Run(6, "x", 100) == ReplaceResult::kReplaced);
    CHECK(p.saved);
    p.scheduled[0].second();
    CHECK(p.restores == 1);
    CHECK(!p.saved);
  }
  {  // ... or forgotten when something else was copied meanwhile.
    FakeReplace p;
    ReplaceFlow flow(&p);
    flow.Run(6, "x", 100);
    p.sequence++;
    p.scheduled[0].second();
    CHECK(p.restores == 0);
    CHECK(!p.saved);
  }
  {  // A second shortcut takes the restore over; the first one's timer
     // neither restores nor forgets what the second still needs.
    FakeReplace p;
    ReplaceFlow flow(&p);
    flow.Run(6, "first", 100);
    flow.Run(4, "second", 100);
    p.scheduled[0].second();
    CHECK(p.saved && p.restores == 0);
    p.scheduled[1].second();
    CHECK(p.restores == 1 && !p.saved);
  }
  {  // The second write fails: the first restore still puts the text back.
    FakeReplace p;
    ReplaceFlow flow(&p);
    flow.Run(6, "first", 100);
    p.write_ok = false;
    CHECK(flow.Run(4, "second", 100) == ReplaceResult::kFailed);
    p.scheduled[0].second();
    CHECK(p.restores == 1 && !p.saved);
  }
}

int main() {
  TestWriteFirstAndForget();
  TestRestorableFormats();
  TestRestoreMarks();
  TestReplace();
  TestBuffer();
  TestTable();
  TestMatcher();
  TestFieldCheck();
  TestClassify();
  TestUtf();
  TestSpeed();
  TestEdgeResetKeys();
  TestEdgeIdle();
  TestEdgeSkips();
  TestEdgeBounds();
  TestEdgeTable();
  TestEdgeUtf16();
  TestEdgeDeleteCounts();
  TestEdgeReplace();
  if (failures == 0) std::printf("typed_shortcut_policy_test: all passed\n");
  return failures == 0 ? 0 : 1;
}
