// Tests for typed_shortcut_policy.h: the Windows typed-shortcut buffer,
// matcher, key classes and skip rules (M1.5, docs/design/typed-shortcuts.md;
// ADR 0004). No Windows dependencies, so this builds anywhere (see
// tool/test_windows_policy.sh). It is not part of the Windows build.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <set>
#include <string>
#include <thread>
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

  bool mods_down = false;
  int64_t now = 0;
  // When set, keys since the match come from here, as in the bridge.
  PendingMatch* pending = nullptr;
  uint32_t watch_id = 0;

  uintptr_t Foreground() override { return foreground; }
  int KeysSinceMatch() override {
    return pending ? pending->InputsSince(watch_id) : keys_after;
  }
  bool ModifiersDown() override { return mods_down; }
  int64_t NowMs() override { return now; }
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

// ---- R1: the hook thread, the field check worker, hook health ----

static void TestHookHealth() {
  // Input the hooks saw: alive.
  CHECK(!HookLooksRemoved(10000, 10000, false));
  CHECK(!HookLooksRemoved(10500, 10000, false));
  CHECK(!HookLooksRemoved(11000, 10000, false));
  // The system saw input more than 1 s after the hooks last ran: removed.
  CHECK(HookLooksRemoved(11001, 10000, false));
  // The hooks ran after the last input (a hook call is newer): alive.
  CHECK(!HookLooksRemoved(9000, 10000, false));
  // An administrator window or the secure desktop in front: our hooks are
  // not called for that input, so silence proves nothing.
  CHECK(!HookLooksRemoved(20000, 10000, true));
  // GetTickCount wraps after 49.7 days.
  CHECK(HookLooksRemoved(2000u, 0xFFFFFF00u, false));
  CHECK(!HookLooksRemoved(100u, 0xFFFFFF00u, false));
  CHECK(kHookCheckMs == 2000);
}

static void TestHookInbox() {
  HookInbox inbox;
  HookInbox::Batch b = inbox.Take();
  CHECK(!b.has_table && !b.has_ignored && !b.reset);
  inbox.PutTable({{1, ";a"}});
  inbox.PutTable({{2, ";bb"}});  // the latest table wins
  inbox.PutIgnored({"1password.exe"});
  inbox.PutReset();
  b = inbox.Take();
  CHECK(b.has_table && b.table.size() == 1 && b.table[0].first == 2);
  CHECK(b.has_ignored && b.ignored.count("1password.exe") == 1);
  CHECK(b.reset);
  b = inbox.Take();  // taken once
  CHECK(!b.has_table && !b.has_ignored && !b.reset);
  // Applying a batch on the hook thread's matcher.
  TypedShortcutMatcher m;
  inbox.PutTable({{7, ";email"}});
  b = inbox.Take();
  m.SetTable(b.table);
  CHECK(m.TableSize() == 1);
  // Two threads: the UI thread puts while the hook thread takes.
  HookInbox shared;
  std::thread ui([&] {
    for (int i = 0; i < 2000; i++) shared.PutTable({{i, ";x" + std::to_string(i)}});
  });
  int last = -1;
  for (int i = 0; i < 2000; i++) {
    HookInbox::Batch t = shared.Take();
    if (t.has_table) {
      CHECK(t.table.size() == 1 && t.table[0].first > last);
      last = t.table[0].first;
    }
  }
  ui.join();
  HookInbox::Batch t = shared.Take();
  if (t.has_table) last = t.table[0].first;
  CHECK(last == 1999);
}

static void TestFieldCheckQueue() {
  CHECK(FieldStateInTime(FieldState::kNormal, 1000, 1100) == FieldState::kNormal);
  CHECK(FieldStateInTime(FieldState::kNormal, 1000, 1101) == FieldState::kUnknown);
  CHECK(FieldStateInTime(FieldState::kPassword, 1000, 1001) == FieldState::kPassword);
  CHECK(FieldStateInTime(FieldState::kPassword, 1000, 5000) == FieldState::kUnknown);
  {  // The newest request wins; the worker takes it once.
    FieldCheckQueue q;
    q.Push({1, 6, 100, 1});
    q.Push({2, 4, 200, 2});
    FieldCheckRequest r{};
    CHECK(q.Pop(&r) && r.snippet_id == 2 && r.delete_count == 4 &&
          r.asked_ms == 200 && r.match_id == 2);
    q.Stop();
    CHECK(!q.Pop(&r));
  }
  {  // A worker waiting on the queue gets a request pushed from another
     // thread, and Stop wakes it.
    FieldCheckQueue q;
    std::vector<int> got;
    std::thread worker([&] {
      FieldCheckRequest r{};
      while (q.Pop(&r)) got.push_back(r.snippet_id);
    });
    q.Push({5, 3, 0, 7});
    for (int i = 0; i < 200 && got.empty(); i++) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    q.Stop();
    worker.join();
    CHECK(got.size() == 1 && got[0] == 5);
  }
}

static void TestPendingMatch() {
  PendingMatch p;
  uintptr_t window = 0;
  int inputs = -1;
  CHECK(!p.Get(1, &window, &inputs));
  p.NoteInput();  // no match yet: nothing counted
  const uint32_t a = p.Begin(100);
  CHECK(a > 0);
  CHECK(p.Get(a, &window, &inputs) && window == 100 && inputs == 0);
  p.NoteInput();
  CHECK(p.Get(a, &window, &inputs) && inputs == 1);
  CHECK(p.InputsSince(a) == 1);
  // C2: a new match starts again from 0, and the older id is no longer
  // valid.
  const uint32_t b = p.Begin(200);
  CHECK(b != a);
  CHECK(!p.Get(a, &window, &inputs));
  CHECK(p.InputsSince(a) > 1000);  // "something happened": cancel
  CHECK(p.Get(b, &window, &inputs) && window == 200 && inputs == 0);
  p.End(a);  // ending the older one leaves the newer
  CHECK(p.Get(b, &window, &inputs));
  p.End(b);
  CHECK(!p.Get(b, &window, &inputs));
  const uint32_t c = p.Begin(1);
  p.Clear();
  CHECK(!p.Get(c, &window, &inputs));
  // Ids stay positive and fit in 23 bits when the counter wraps.
  PendingMatch wrap(kMaxMatchId - 1);
  CHECK(wrap.Begin(1) == kMaxMatchId);
  CHECK(wrap.Begin(1) == 1);
  CHECK(kMaxMatchId == 0x7FFFFF);
  // The hook thread counts while the UI thread reads.
  PendingMatch shared;
  const uint32_t s = shared.Begin(1);
  std::thread hook([&] {
    for (int i = 0; i < 1000; i++) shared.NoteInput();
  });
  for (int i = 0; i < 1000; i++) shared.Get(s, &window, &inputs);
  hook.join();
  CHECK(shared.Get(s, &window, &inputs) && inputs == 1000);
}

// C2: the match id travels from the field check to the UI thread packed
// with the delete count in one LPARAM, even a 32-bit one.
static void TestPackMatch() {
  for (const uint32_t id : {1u, 2u, 255u, 256u, kMaxMatchId}) {
    for (const int count : {1, 6, 32}) {
      int c = 0;
      uint32_t i = 0;
      const int64_t packed = PackMatch(count, id);
      CHECK(packed > 0 && packed <= 0x7FFFFFFF);
      UnpackMatch(packed, &c, &i);
      CHECK(c == count && i == id);
    }
  }
}

// C2: a replace for an older match is cancelled and sends nothing.
static void TestReplaceMatch() {
  FakeReplace p;
  ReplaceFlow flow(&p);
  PendingMatch pending;
  const uint32_t first = pending.Begin(100);
  const uint32_t second = pending.Begin(100);
  CHECK(ReplaceMatch(flow, pending, first, 6, "will@example.com") ==
        ReplaceResult::kCancelled);
  CHECK(p.log.empty());
  CHECK(ReplaceMatch(flow, pending, second, 4, "07700") ==
        ReplaceResult::kReplaced);
  CHECK(!pending.Get(second, nullptr, nullptr));  // answered once
  CHECK(ReplaceMatch(flow, pending, second, 4, "07700") ==
        ReplaceResult::kCancelled);
  // The window of the match, not whatever is in front now.
  const uint32_t third = pending.Begin(200);
  CHECK(ReplaceMatch(flow, pending, third, 4, "x") == ReplaceResult::kCancelled);
}

// C5: a mouse press after a match cancels its replacement.
static void TestMouseDownCancels() {
  TypedShortcutMatcher m = Make();
  PendingMatch pending;
  uint32_t id = 0;
  for (char32_t c : std::u32string(U";email")) {
    if (m.Handle(TypedKey::Text(std::u32string(1, c)), TypedKeyContext{}, 0)
            .kind == TypedOutcome::Kind::kMatched) {
      id = pending.Begin(100);
    }
  }
  CHECK(id != 0);
  OnMouseDown(m, pending);
  CHECK(pending.InputsSince(id) == 1);
  FakeReplace p;
  p.keys_after = pending.InputsSince(id);
  ReplaceFlow flow(&p);
  CHECK(ReplaceMatch(flow, pending, id, 6, "x") == ReplaceResult::kCancelled);
  CHECK(p.log.empty());
  // And the buffer is empty: ";em", a click, "ail" never fires.
  TypedShortcutMatcher half = Make();
  TypeText(half, U";em");
  OnMouseDown(half, pending);
  CHECK(half.BufferCount() == 0);
  CHECK(IsNone(TypeText(half, U"ail")));
}

// C9: the buffer is cleared exactly 5 s after the last key, by a timer the
// hook thread sets from this deadline.
static void TestIdleDeadline() {
  TypedShortcutMatcher m = Make();
  int64_t ms = -1;
  CHECK(!m.MsUntilIdleClear(0, &ms));  // nothing typed: no timer
  m.Handle(TypedKey::Text(U";"), TypedKeyContext{}, 1000);
  CHECK(m.MsUntilIdleClear(1000, &ms) && ms == 5000);
  CHECK(m.MsUntilIdleClear(3000, &ms) && ms == 3000);
  m.Handle(TypedKey::Text(U"e"), TypedKeyContext{}, 3000);
  CHECK(m.MsUntilIdleClear(3000, &ms) && ms == 5000);  // each key moves it
  m.Tick(7999);
  CHECK(m.BufferCount() == 2);
  CHECK(m.MsUntilIdleClear(7999, &ms) && ms == 1);  // fired early: set again
  m.Tick(8000);
  CHECK(m.BufferCount() == 0);
  CHECK(!m.MsUntilIdleClear(8000, &ms));  // cleared: no timer
  // Never negative; gone after a reset, a backspace to empty or a match.
  m.Handle(TypedKey::Text(U";"), TypedKeyContext{}, 0);
  CHECK(m.MsUntilIdleClear(9000, &ms) && ms == 0);
  m.Handle(TypedKey::Reset(), TypedKeyContext{}, 100);
  CHECK(!m.MsUntilIdleClear(100, &ms));
  m.Handle(TypedKey::Text(U";"), TypedKeyContext{}, 200);
  m.Handle(TypedKey::Backspace(), TypedKeyContext{}, 300);
  CHECK(!m.MsUntilIdleClear(300, &ms));
  TypeText(m, U";email", TypedKeyContext{}, 400);
  CHECK(!m.MsUntilIdleClear(400, &ms));
  // A key that types nothing does not move it.
  m.Handle(TypedKey::Text(U";"), TypedKeyContext{}, 0);
  m.Handle(TypedKey::Ignore(), TypedKeyContext{}, 4000);
  CHECK(m.MsUntilIdleClear(4000, &ms) && ms == 1000);
}

// C1: a modifier still held when the replacement starts (Shift for the
// last character, AltGr) would turn Backspace and Ctrl+V into Ctrl+Shift+V
// (Kusunga's own picker) or Ctrl+Alt+Backspace. Wait on a timer, never
// sleeping, up to 300 ms for it to be released; otherwise copy only and
// leave the code.
static int RunScheduledPoll(FakeReplace& p) {
  // The newest 10 ms poll, after the time it waits.
  for (size_t i = p.scheduled.size(); i-- > 0;) {
    if (p.scheduled[i].first == kPollMs) {
      auto work = std::move(p.scheduled[i].second);
      p.scheduled.erase(p.scheduled.begin() + static_cast<long>(i));
      p.now += kPollMs;
      work();
      return 1;
    }
  }
  return 0;
}

static void TestModifierWait() {
  {  // No modifier: answered at once, as before.
    FakeReplace p;
    ReplaceFlow flow(&p);
    int answers = 0;
    ReplaceResult got = ReplaceResult::kFailed;
    flow.Start(6, "x", 100, [&](ReplaceResult r) {
      got = r;
      answers++;
    });
    CHECK(answers == 1 && got == ReplaceResult::kReplaced);
  }
  {  // Shift still down: nothing is sent until it is released.
    FakeReplace p;
    p.mods_down = true;
    ReplaceFlow flow(&p);
    int answers = 0;
    ReplaceResult got = ReplaceResult::kFailed;
    flow.Start(6, "x", 100, [&](ReplaceResult r) {
      got = r;
      answers++;
    });
    CHECK(answers == 0);
    CHECK(p.log.empty());
    CHECK(p.scheduled.size() == 1 && p.scheduled[0].first == kPollMs);
    CHECK(RunScheduledPoll(p) == 1);  // 10 ms: still down
    CHECK(answers == 0 && p.log.empty());
    p.mods_down = false;
    CHECK(RunScheduledPoll(p) == 1);  // 20 ms: released
    CHECK(answers == 1 && got == ReplaceResult::kReplaced);
    CHECK((p.log == std::vector<std::string>{"readPrevious", "write",
                                              "backspace6", "paste"}));
  }
  {  // Held for 300 ms: copy only; the code stays, nothing is read back.
    FakeReplace p;
    p.mods_down = true;
    ReplaceFlow flow(&p);
    int answers = 0;
    ReplaceResult got = ReplaceResult::kFailed;
    flow.Start(6, "x", 100, [&](ReplaceResult r) {
      got = r;
      answers++;
    });
    int polls = 0;
    while (answers == 0 && polls < 100) polls += RunScheduledPoll(p);
    CHECK(answers == 1 && got == ReplaceResult::kCopied);
    CHECK(p.now >= kModifierTimeoutMs && p.now <= kModifierTimeoutMs + kPollMs);
    CHECK((p.log == std::vector<std::string>{"write"}));
    CHECK(!p.saved);
    for (const auto& w : p.scheduled) CHECK(w.first != kRestoreDelayMs);
  }
  {  // Held, and the copy-only write fails: failed, code stays.
    FakeReplace p;
    p.mods_down = true;
    p.write_ok = false;
    ReplaceFlow flow(&p);
    ReplaceResult got = ReplaceResult::kReplaced;
    flow.Start(6, "x", 100, [&](ReplaceResult r) { got = r; });
    for (int i = 0; i < 100 && got == ReplaceResult::kReplaced; i++) {
      RunScheduledPoll(p);
    }
    CHECK(got == ReplaceResult::kFailed);
    for (const auto& l : p.log) CHECK(l.rfind("backspace", 0) != 0);
  }
  {  // A key typed during the wait cancels; nothing is written.
    FakeReplace p;
    p.mods_down = true;
    ReplaceFlow flow(&p);
    ReplaceResult got = ReplaceResult::kReplaced;
    flow.Start(6, "x", 100, [&](ReplaceResult r) { got = r; });
    p.keys_after = 1;
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(got == ReplaceResult::kCancelled);
    CHECK(p.log.empty());
  }
  {  // Another window in front after the wait: cancelled.
    FakeReplace p;
    p.mods_down = true;
    ReplaceFlow flow(&p);
    ReplaceResult got = ReplaceResult::kReplaced;
    flow.Start(6, "x", 100, [&](ReplaceResult r) { got = r; });
    p.foreground = 200;
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(got == ReplaceResult::kCancelled);
    CHECK(p.log.empty());
  }
  {  // A second replacement while one waits is cancelled at once.
    FakeReplace p;
    p.mods_down = true;
    ReplaceFlow flow(&p);
    ReplaceResult first = ReplaceResult::kFailed, second = ReplaceResult::kFailed;
    flow.Start(6, "x", 100, [&](ReplaceResult r) { first = r; });
    flow.Start(4, "y", 100, [&](ReplaceResult r) { second = r; });
    CHECK(second == ReplaceResult::kCancelled);
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(first == ReplaceResult::kReplaced);
  }
  {  // With the match id: a newer match during the wait cancels the older.
    FakeReplace p;
    PendingMatch pending;
    p.pending = &pending;
    p.mods_down = true;
    ReplaceFlow flow(&p);
    const uint32_t id = pending.Begin(100);
    p.watch_id = id;
    ReplaceResult got = ReplaceResult::kFailed;
    StartReplaceMatch(flow, pending, id, 6, "x",
                      [&](ReplaceResult r) { got = r; });
    pending.Begin(100);  // the user typed another shortcut meanwhile
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(got == ReplaceResult::kCancelled);
    CHECK(p.log.empty());
    // A stale id is answered at once.
    ReplaceResult stale = ReplaceResult::kFailed;
    StartReplaceMatch(flow, pending, id, 6, "x",
                      [&](ReplaceResult r) { stale = r; });
    CHECK(stale == ReplaceResult::kCancelled);
  }
  // A held modifier repeats (key-down after key-down); that is not input
  // that moves the cursor, so it never counts against the match.
  for (uint32_t vk : {0x10u, 0x11u, 0x12u, 0xA0u, 0xA1u, 0xA2u, 0xA3u, 0xA4u,
                      0xA5u, 0x5Bu, 0x5Cu}) {
    CHECK(IsModifierKey(vk));
  }
  for (uint32_t vk : {0x08u, 0x41u, 0x0Du, 0x25u, 0x14u, 0x70u}) {
    CHECK(!IsModifierKey(vk));
  }
  CHECK(kModifierTimeoutMs == 300 && kPollMs == 10);
}

// ---- Tester round 3: edges and interleavings of the R1/C1-C9/S1 logic ----

static void TestRound3Ids() {
  uintptr_t w = 0;
  int n = 0;
  {  // Wrap: ... max-1, max, 1; never 0; a huge start also lands on 1.
    PendingMatch p(kMaxMatchId - 2);
    CHECK(p.Begin(1) == kMaxMatchId - 1);
    CHECK(p.Begin(1) == kMaxMatchId);
    const uint32_t wrapped = p.Begin(1);
    CHECK(wrapped == 1);
    CHECK(!p.Get(kMaxMatchId, &w, &n));  // the old id is dead after the wrap
    CHECK(p.Get(1, &w, &n));
    PendingMatch huge(0xFFFFFFFFu);
    CHECK(huge.Begin(1) == 1);
    PendingMatch beyond(kMaxMatchId + 1);
    CHECK(beyond.Begin(1) == 1);
  }
  {  // Ids that were never given out are refused.
    PendingMatch p;
    const uint32_t id = p.Begin(5);
    CHECK(!p.Get(0, &w, &n));
    CHECK(!p.Get(id + 1, &w, &n));
    CHECK(!p.Get(id | 0x800000u, &w, &n));  // bit 24 set: not the same id
    CHECK(!p.Get(0xFFFFFFFFu, &w, &n));
    CHECK(p.InputsSince(0) > 1000);
  }
  {  // After the wrap an id from long ago can never be taken for the new one
     // unless it really is the same number, and the count starts again.
    PendingMatch p(kMaxMatchId);
    const uint32_t first = p.Begin(1);  // 1
    p.NoteInput();
    p.NoteInput();
    p.End(first);
    CHECK(!p.Get(first, &w, &n));
    CHECK(p.Begin(2) == 2);
    CHECK(p.Get(2, &w, &n) && n == 0 && w == 2);
  }
  {  // Ending twice, or ending something never begun, changes nothing.
    PendingMatch p;
    const uint32_t a = p.Begin(1);
    p.End(a);
    p.End(a);
    p.End(0);
    const uint32_t b = p.Begin(2);
    p.End(a);  // a is old: b stays
    CHECK(p.Get(b, &w, &n));
    p.NoteInput();
    p.Begin(3);
    CHECK(p.InputsSince(p.Begin(3)) == 0);  // a new match counts from zero
  }
  {  // Packing: every delete count, ids at the edges, always positive int32.
    for (const uint32_t id : {1u, 0x7FFFFEu, kMaxMatchId, 0x400000u, 0x123456u}) {
      for (int count = 1; count <= 32; count++) {
        int c = 0;
        uint32_t i = 0;
        const int64_t packed = PackMatch(count, id);
        CHECK(packed > 0 && packed <= 0x7FFFFFFFLL);
        UnpackMatch(packed, &c, &i);
        CHECK(c == count && i == id);
      }
    }
    // An id over 23 bits can never turn negative or touch the count.
    int c = 0;
    uint32_t i = 0;
    UnpackMatch(PackMatch(32, 0xFFFFFFFFu), &c, &i);
    CHECK(c == 32 && i == kMaxMatchId);
  }
}

static void TestRound3HookHealth() {
  const uint32_t t = 100000;
  CHECK(!HookLooksRemoved(t + 1000, t, false));  // exactly 1 s: alive
  CHECK(HookLooksRemoved(t + 1001, t, false));   // just over: removed
  CHECK(!HookLooksRemoved(t, t, false));
  CHECK(!HookLooksRemoved(0, 0, false));
  CHECK(!HookLooksRemoved(t, t + 5000, false));  // a hook call after the input
  CHECK(!HookLooksRemoved(t + 999999, t, true));  // hidden front: never
  // Wrap of the 32-bit tick: 1000 ms and 1001 ms across zero.
  CHECK(!HookLooksRemoved(984u, 0xFFFFFFF0u, false));  // 16 + 984 = 1000
  CHECK(HookLooksRemoved(985u, 0xFFFFFFF0u, false));   // 1001
  CHECK(!HookLooksRemoved(0xFFFFFFF0u, 984u, false));  // hook newer across wrap
  // Half the range ahead is read as "the hook is newer" (signed difference).
  CHECK(!HookLooksRemoved(0x80000000u, 0, false));
  CHECK(HookLooksRemoved(0x7FFFFFFFu, 0, false));
  CHECK(kHookSilenceMs == 1000 && kHookCheckMs == 2000);
}

static void TestRound3Inbox() {
  {  // Interleavings: Put, Take, Put, Take.
    HookInbox in;
    in.PutIgnored({"a.exe"});
    HookInbox::Batch b = in.Take();
    CHECK(b.has_ignored && !b.has_table && !b.reset);
    in.PutTable({{1, ";a"}});
    in.PutIgnored({"b.exe"});
    in.PutIgnored({});  // an empty list is a real update, not "nothing"
    b = in.Take();
    CHECK(b.has_table && b.has_ignored && b.ignored.empty());
    CHECK(!in.Take().has_ignored);
  }
  {  // An empty table is a real update too (all shortcuts removed).
    HookInbox in;
    in.PutTable({});
    HookInbox::Batch b = in.Take();
    CHECK(b.has_table && b.table.empty());
  }
  {  // The reset flag stays until taken, and is not lost by other puts.
    HookInbox in;
    in.PutReset();
    in.PutTable({{1, ";a"}});
    in.PutReset();
    HookInbox::Batch b = in.Take();
    CHECK(b.reset && b.has_table);
    CHECK(!in.Take().reset);
  }
  {  // Many writers: nothing is torn, the table is always one whole put.
    HookInbox in;
    std::thread a([&] {
      for (int i = 0; i < 500; i++) in.PutTable({{1, ";aa"}, {2, ";ab"}});
    });
    std::thread b([&] {
      for (int i = 0; i < 500; i++) in.PutTable({{3, ";ba"}, {4, ";bb"}, {5, ";bc"}});
    });
    for (int i = 0; i < 500; i++) {
      HookInbox::Batch t = in.Take();
      if (t.has_table) {
        CHECK((t.table.size() == 2 && t.table[0].first == 1) ||
              (t.table.size() == 3 && t.table[0].first == 3));
      }
    }
    a.join();
    b.join();
  }
  // The field check's late answer rule at the edges.
  CHECK(FieldStateInTime(FieldState::kNormal, 0, 100) == FieldState::kNormal);
  CHECK(FieldStateInTime(FieldState::kNormal, 0, 101) == FieldState::kUnknown);
  CHECK(FieldStateInTime(FieldState::kPassword, 0, 100) == FieldState::kPassword);
  CHECK(FieldStateInTime(FieldState::kUnknown, 0, 0) == FieldState::kUnknown);
  CHECK(FieldStateInTime(FieldState::kNormal, 500, 400) == FieldState::kNormal);
  CHECK(DecideField(FieldStateInTime(FieldState::kNormal, 0, 101)) != nullptr);
}

static void TestRound3Formats() {
  const ClipboardFormatInfo uni{13, ""};
  CHECK(CanRestoreClipboard({uni}));
  CHECK(CanRestoreClipboard({uni, uni}));
  CHECK(CanRestoreClipboard({{16, ""}, uni}));  // order does not matter
  CHECK(CanRestoreClipboard({{0xC001, "CanUploadToCloudClipboard"}, uni}));
  // Only markers, or only synthesized ANSI/OEM text: nothing to read.
  CHECK(!CanRestoreClipboard({{1, ""}, {7, ""}, {16, ""}}));
  CHECK(!CanRestoreClipboard({{0xC001, "CanIncludeInClipboardHistory"}}));
  // A marker name only counts for a registered format (0xC000 and up).
  CHECK(!CanRestoreClipboard({uni, {0xBFFF, "CanIncludeInClipboardHistory"}}));
  CHECK(!CanRestoreClipboard({uni, {2, "CanIncludeInClipboardHistory"}}));
  // Names are exact: case, spaces, prefixes.
  CHECK(!CanRestoreClipboard({uni, {0xC001, "canincludeinclipboardhistory"}}));
  CHECK(!CanRestoreClipboard({uni, {0xC001, " CanIncludeInClipboardHistory"}}));
  CHECK(!CanRestoreClipboard({uni, {0xC001, "Clipboard Viewer Ignore "}}));
  // Every non-text standard format blocks, one at a time.
  for (uint32_t id : {2u, 3u, 4u, 5u, 6u, 8u, 9u, 10u, 11u, 12u, 14u, 15u, 17u,
                      0x80u, 0x200u, 0x2FFu}) {
    CHECK(!CanRestoreClipboard({uni, {id, ""}}));
  }
  // Mixed: text and rich text and a marker still refuses.
  CHECK(!CanRestoreClipboard({uni, {0xC001, "CanUploadToCloudClipboard"},
                              {0xC002, "Rich Text Format"}}));
}

static void TestRound3Marks() {
  // Every way IsSecret can be true is covered by what a restore writes:
  // the restored copy sets exclude_from_monitor, which IsSecret reads.
  const ClipboardMarks m = RestoreMarks();
  ClipboardFlags written{};
  written.exclude_from_monitor = m.exclude_from_monitor;
  CHECK(IsSecret(written));
  ClipboardFlags history{};
  history.has_can_include = true;
  history.can_include_value = m.no_history ? 0 : 1;
  CHECK(IsSecret(history));
  CHECK(m.no_cloud);
  // Whatever the original copy used, nothing is weaker after the restore.
  for (int bits = 0; bits < 16; bits++) {
    ClipboardFlags f{};
    f.exclude_from_monitor = bits & 1;
    f.has_can_include = bits & 2;
    f.can_include_value = (bits & 2) ? 0 : 1;
    f.viewer_ignore = bits & 4;
    f.can_include_unreadable = (bits & 8) && f.has_can_include;
    if (IsSecret(f)) CHECK(m.exclude_from_monitor && m.no_history && m.no_cloud);
  }
  // The snippet itself is not marked no-history or no-cloud, only excluded
  // from monitors (it is pasted at once).
  CHECK(SnippetMarks().exclude_from_monitor);
}

// C3: the saved text is gone on every exit.
static void TestRound3Forget() {
  {  // Cancelled before anything is read: nothing was saved.
    FakeReplace p;
    p.foreground = 5;
    ReplaceFlow f(&p);
    CHECK(f.Run(3, "x", 100) == ReplaceResult::kCancelled);
    CHECK(!p.saved && p.log.empty());
  }
  {  // A failed write with a fresh read: forgotten, code stays, no restore.
    FakeReplace p;
    p.write_ok = false;
    ReplaceFlow f(&p);
    CHECK(f.Run(3, "x", 100) == ReplaceResult::kFailed);
    CHECK(!p.saved && p.forgets >= 1 && p.scheduled.empty());
    for (const auto& l : p.log) CHECK(l.rfind("backspace", 0) != 0 && l != "paste");
  }
  {  // The restore fires: restored once, then forgotten.
    FakeReplace p;
    ReplaceFlow f(&p);
    CHECK(f.Run(3, "x", 100) == ReplaceResult::kReplaced);
    CHECK(p.saved);
    p.scheduled[0].second();
    CHECK(p.restores == 1 && !p.saved);
    p.scheduled[0].second();  // a duplicate timer does nothing
    CHECK(p.restores == 1);
  }
  {  // The user copied meanwhile: no restore, but the saved text is forgotten.
    FakeReplace p;
    ReplaceFlow f(&p);
    f.Run(3, "x", 100);
    p.sequence++;
    p.scheduled[0].second();
    CHECK(p.restores == 0 && !p.saved);
  }
  {  // A second shortcut takes the restore over; the first timer does
     // nothing and does not forget the text the second one still holds.
    FakeReplace p;
    ReplaceFlow f(&p);
    f.Run(3, "a", 100);
    f.Run(3, "b", 100);
    CHECK(p.saved);
    p.scheduled[0].second();
    CHECK(p.restores == 0 && p.saved);
    p.scheduled[1].second();
    CHECK(p.restores == 1 && !p.saved);
  }
  {  // The second write fails while the first restore waits: the user's
     // text is still kept for it.
    FakeReplace p;
    ReplaceFlow f(&p);
    f.Run(3, "a", 100);
    p.write_ok = false;
    CHECK(f.Run(3, "b", 100) == ReplaceResult::kFailed);
    CHECK(p.saved);
    p.scheduled[0].second();
    CHECK(p.restores == 1 && !p.saved);
  }
  {  // The second write fails after the user copied something else: the
     // old restore must not put back stale text.
    FakeReplace p;
    ReplaceFlow f(&p);
    f.Run(3, "a", 100);
    p.sequence++;  // the user's copy
    p.write_ok = false;
    CHECK(f.Run(3, "b", 100) == ReplaceResult::kFailed);
    p.scheduled[0].second();
    CHECK(p.restores == 0);
    CHECK(!p.saved);
  }
  {  // No text before (an image): nothing saved, nothing restored.
    FakeReplace p;
    p.has_previous = false;
    ReplaceFlow f(&p);
    CHECK(f.Run(3, "x", 100) == ReplaceResult::kReplaced);
    CHECK(!p.saved && p.scheduled.empty());
  }
}

static void TestRound3ModifierWait() {
  // IsModifierKey: exactly the modifiers.
  for (uint32_t vk : {0x10u, 0x11u, 0x12u, 0xA0u, 0xA1u, 0xA2u, 0xA3u, 0xA4u,
                      0xA5u, 0x5Bu, 0x5Cu}) {
    CHECK(IsModifierKey(vk));
  }
  for (uint32_t vk : {0x41u, 0x14u, 0x90u, 0x91u, 0x5Du, 0x20u, 0x0Du, 0x08u,
                      0x00u, 0xFFu}) {
    CHECK(!IsModifierKey(vk));
  }
  auto start = [](FakeReplace&, ReplaceFlow& f, ReplaceResult* got, int* answers) {
    f.Start(6, "x", 100, [got, answers](ReplaceResult r) {
      *got = r;
      (*answers)++;
    });
  };
  {  // Released one poll before the timeout: replaces. At the timeout: copy.
    FakeReplace p;
    p.mods_down = true;
    ReplaceFlow f(&p);
    ReplaceResult got = ReplaceResult::kFailed;
    int answers = 0;
    start(p, f, &got, &answers);
    while (p.now < kModifierTimeoutMs - kPollMs) RunScheduledPoll(p);
    CHECK(answers == 0 && p.now == kModifierTimeoutMs - kPollMs);
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(answers == 1 && got == ReplaceResult::kReplaced);
  }
  {  // Held to exactly the timeout: copy only.
    FakeReplace p;
    p.mods_down = true;
    ReplaceFlow f(&p);
    ReplaceResult got = ReplaceResult::kFailed;
    int answers = 0;
    start(p, f, &got, &answers);
    while (answers == 0) RunScheduledPoll(p);
    CHECK(got == ReplaceResult::kCopied && p.now == kModifierTimeoutMs);
    CHECK(!p.saved);
  }
  {  // A mouse press during the wait (an input) cancels, even if released.
    FakeReplace p;
    PendingMatch pending;
    p.pending = &pending;
    p.watch_id = pending.Begin(100);
    p.mods_down = true;
    ReplaceFlow f(&p);
    ReplaceResult got = ReplaceResult::kReplaced;
    int answers = 0;
    start(p, f, &got, &answers);
    RunScheduledPoll(p);
    TypedShortcutMatcher m = Make();
    OnMouseDown(m, pending);
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(answers == 1 && got == ReplaceResult::kCancelled);
    CHECK(p.log.empty() && !p.saved);
  }
  {  // The same press while the modifiers stay down to the timeout: cancel,
     // not a copy (nothing is written).
    FakeReplace p;
    PendingMatch pending;
    p.pending = &pending;
    p.watch_id = pending.Begin(100);
    p.mods_down = true;
    ReplaceFlow f(&p);
    ReplaceResult got = ReplaceResult::kReplaced;
    int answers = 0;
    start(p, f, &got, &answers);
    pending.NoteInput();
    while (answers == 0) RunScheduledPoll(p);
    CHECK(got == ReplaceResult::kCancelled && p.log.empty());
  }
  {  // A held modifier's repeated key-downs are not input: still replaces.
    FakeReplace p;
    PendingMatch pending;
    p.pending = &pending;
    p.watch_id = pending.Begin(100);
    p.mods_down = true;
    ReplaceFlow f(&p);
    ReplaceResult got = ReplaceResult::kFailed;
    int answers = 0;
    start(p, f, &got, &answers);
    for (int i = 0; i < 5; i++) {
      if (!IsModifierKey(0xA0)) pending.NoteInput();  // what OnKey does
      RunScheduledPoll(p);
    }
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(got == ReplaceResult::kReplaced);
  }
  {  // A second match during the wait: its replace is cancelled, and the
     // first (now stale by id) is cancelled when it wakes. Locks today's
     // behaviour: the newest match is lost too (note in the hand-off).
    FakeReplace p;
    PendingMatch pending;
    p.pending = &pending;
    const uint32_t first = pending.Begin(100);
    p.watch_id = first;
    p.mods_down = true;
    ReplaceFlow f(&p);
    ReplaceResult r1 = ReplaceResult::kFailed, r2 = ReplaceResult::kFailed;
    int a1 = 0, a2 = 0;
    StartReplaceMatch(f, pending, first, 6, "one", [&](ReplaceResult r) { r1 = r; a1++; });
    const uint32_t second = pending.Begin(100);
    StartReplaceMatch(f, pending, second, 4, "two", [&](ReplaceResult r) { r2 = r; a2++; });
    CHECK(a2 == 1 && r2 == ReplaceResult::kCancelled);
    p.mods_down = false;
    RunScheduledPoll(p);
    CHECK(a1 == 1 && r1 == ReplaceResult::kCancelled);
    CHECK(p.log.empty());
  }
  {  // A replace for an id that was already answered never starts a wait.
    FakeReplace p;
    PendingMatch pending;
    ReplaceFlow f(&p);
    const uint32_t id = pending.Begin(100);
    int answers = 0;
    ReplaceResult got = ReplaceResult::kFailed;
    StartReplaceMatch(f, pending, id, 6, "x", [&](ReplaceResult r) { got = r; answers++; });
    CHECK(answers == 1 && got == ReplaceResult::kReplaced);
    StartReplaceMatch(f, pending, id, 6, "x", [&](ReplaceResult r) { got = r; answers++; });
    CHECK(answers == 2 && got == ReplaceResult::kCancelled);
    int backspaces = 0;
    for (const auto& l : p.log) backspaces += l.rfind("backspace", 0) == 0;
    CHECK(backspaces == 1);
  }
}

static void TestRound3Idle() {
  int64_t ms = 0;
  TypedShortcutMatcher m = Make();
  m.Handle(TypedKey::Text(U";"), TypedKeyContext{}, 10000);
  CHECK(m.MsUntilIdleClear(10000, &ms) && ms == 5000);
  CHECK(m.MsUntilIdleClear(14999, &ms) && ms == 1);
  CHECK(m.MsUntilIdleClear(15000, &ms) && ms == 0);
  CHECK(m.MsUntilIdleClear(99999, &ms) && ms == 0);
  m.Tick(14999);
  CHECK(m.BufferCount() == 1);
  m.Tick(15000);
  CHECK(m.BufferCount() == 0 && !m.MsUntilIdleClear(15000, &ms));
  // A skipped match (ignored app) keeps the buffer and the deadline.
  TypedShortcutMatcher k = Make();
  TypeText(k, U";email", Ctx(false, true), 2000);
  CHECK(k.BufferCount() == 6);
  CHECK(k.MsUntilIdleClear(2000, &ms) && ms == 5000);
  // A software key also moves the deadline (it is in the buffer).
  TypedShortcutMatcher j = Make();
  j.Handle(TypedKey::Text(U";"), Ctx(false, false, true), 100);
  CHECK(j.MsUntilIdleClear(100, &ms) && ms == 5000);
  // Backspacing to empty drops the timer; a Backspace on a non-empty one
  // moves it.
  TypedShortcutMatcher b = Make();
  TypeText(b, U";e", TypedKeyContext{}, 0);
  b.Handle(TypedKey::Backspace(), TypedKeyContext{}, 3000);
  CHECK(b.MsUntilIdleClear(3000, &ms) && ms == 5000);
  b.Handle(TypedKey::Backspace(), TypedKeyContext{}, 3500);
  CHECK(!b.MsUntilIdleClear(3500, &ms));
}

int main() {
  TestModifierWait();
  TestIdleDeadline();
  TestMouseDownCancels();
  TestHookHealth();
  TestHookInbox();
  TestFieldCheckQueue();
  TestPendingMatch();
  TestPackMatch();
  TestReplaceMatch();
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
  TestRound3Ids();
  TestRound3HookHealth();
  TestRound3Inbox();
  TestRound3Formats();
  TestRound3Marks();
  TestRound3Forget();
  TestRound3ModifierWait();
  TestRound3Idle();
  if (failures == 0) std::printf("typed_shortcut_policy_test: all passed\n");
  return failures == 0 ? 0 : 1;
}
