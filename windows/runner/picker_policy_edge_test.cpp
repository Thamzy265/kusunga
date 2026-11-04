// Tester probes for picker_policy.h (M1.3): the focus and modifier time
// limits to the millisecond, a window that disappears or is stolen at each
// step, every damaged key name, and placement on odd screens. Builds anywhere
// (see tool/test_windows_policy.sh).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "picker_policy.h"

using namespace kusunga;

static int failures = 0;
#define CHECK(cond)                                         \
  do {                                                      \
    if (!(cond)) {                                          \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond); \
      failures++;                                           \
    }                                                       \
  } while (0)

// A pretend Windows. Time moves only when the flow sleeps, and the foreground
// can change at chosen moments, including the moment a call is made.
class Fake : public PastePlatform {
 public:
  std::vector<std::string> log;
  int now = 0;
  uintptr_t foreground = 100;  // the picker
  bool usable = true;
  int target_front_at = 20;     // absolute ms; -1 never
  int steal_after_calls = -1;   // after this many Foreground() calls, 300 wins
  int calls = 0;
  int gone_at = -1;             // the window is destroyed at this time
  int modifiers_until_ms = -1;
  uint32_t own = kMediumRid;
  uint32_t target = kMediumRid;
  std::string written;

  bool WriteClipboard(const std::string& t) override {
    written = t;
    log.push_back("write");
    return true;
  }
  void HidePicker() override { log.push_back("hide"); }
  bool IsUsableTarget(uintptr_t) override { return usable; }
  void Activate(uintptr_t) override { log.push_back("activate"); }
  uintptr_t Foreground() override {
    calls++;
    if (steal_after_calls >= 0 && calls > steal_after_calls) {
      foreground = 300;
    } else if (gone_at >= 0 && now >= gone_at) {
      foreground = 0;
    } else if (target_front_at >= 0 && now >= target_front_at) {
      foreground = 200;
    }
    return foreground;
  }
  uint32_t OwnIntegrity() override { return own; }
  uint32_t TargetIntegrity(uintptr_t) override { return target; }
  bool ModifiersDown() override {
    return modifiers_until_ms >= 0 && now < modifiers_until_ms;
  }
  void SendPaste() override { log.push_back("send@" + std::to_string(now)); }
  void Sleep(int ms) override { now += ms; }
  int NowMs() override { return now; }
  bool Sent() const {
    for (const auto& l : log)
      if (l.rfind("send", 0) == 0) return true;
    return false;
  }
  int SentAt() const {
    for (const auto& l : log)
      if (l.rfind("send", 0) == 0) return std::atoi(l.c_str() + 5);
    return -1;
  }
};

int main() {
  // ---- focus confirmation at the limit: 499, 500, 501 ms ----
  for (int d : {0, 1, 499, 500}) {
    Fake p;
    p.target_front_at = d;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kPasted);
    CHECK(p.Sent());
  }
  for (int d : {501, 502, 510, 1000}) {
    Fake p;
    p.target_front_at = d;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kFocusTimeout);
    CHECK(!p.Sent());
    CHECK(p.written == "x");  // still on the clipboard
  }

  // ---- focus stolen at every step after the confirmation ----
  // Foreground() is asked: once per poll until confirmed, then once more right
  // before sending. A thief that arrives at any of those moments stops the
  // keystroke.
  for (int after = 2; after < 8; after++) {
    Fake p;
    p.target_front_at = 20;  // confirmed on the 4th call (0, 10, 20 -> 3rd)
    p.steal_after_calls = after;
    PasteResult r = RunPaste(p, "x", 200, true);
    if (p.Sent()) {
      // Allowed only if the thief arrived after the last check.
      CHECK(r == PasteResult::kPasted);
    } else {
      CHECK(r == PasteResult::kFocusTimeout);
    }
  }
  {  // stolen between the confirmation and the send, modifiers still held
    Fake p;
    p.modifiers_until_ms = 100;
    p.steal_after_calls = 3;  // 3 polls to confirm, thief on the next ask
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kFocusTimeout);
    CHECK(!p.Sent());
  }

  // ---- the target quits at each point ----
  {  // before activation
    Fake p;
    p.usable = false;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kTargetGone);
    CHECK(!p.Sent());
  }
  {  // right after activation: the window is gone, foreground is nothing
    Fake p;
    p.gone_at = 0;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kFocusTimeout);
    CHECK(!p.Sent());
  }
  {  // while the modifier keys are being waited for
    Fake p;
    p.modifiers_until_ms = 200;
    p.gone_at = 100;
    CHECK(RunPaste(p, "x", 200, true) != PasteResult::kPasted);
    CHECK(!p.Sent());
  }

  // ---- modifier wait boundaries ----
  for (int until : {0, 1, 299, 300}) {
    Fake p;
    p.target_front_at = 0;
    p.modifiers_until_ms = until;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kPasted);
    CHECK(p.SentAt() >= until);
    CHECK(p.SentAt() <= 300 + 10);
  }

  // ---- administrator checks never send, whatever the timing ----
  for (uint32_t level : {kHighRid, kSystemRid, 0x3001u, 0x5000u}) {
    Fake p;
    p.target = level;
    p.modifiers_until_ms = 50;
    PasteResult r = RunPaste(p, "x", 200, true);
    CHECK(r == PasteResult::kTargetElevated);
    CHECK(!p.Sent());
  }
  {  // we run as administrator ourselves and the target is a normal app
    Fake p;
    p.own = kHighRid;
    p.target = kMediumRid;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kPasted);
  }
  {  // integrity unknown on either side: copy only, never send
    Fake a;
    a.own = 0;
    CHECK(RunPaste(a, "x", 200, true) == PasteResult::kCopyOnly);
    CHECK(!a.Sent());
    Fake b;
    b.target = 0;
    CHECK(RunPaste(b, "x", 200, true) == PasteResult::kCopyOnly);
    CHECK(!b.Sent());
  }
  {  // copy-only mode never reaches the integrity check or the keystroke
    Fake p;
    p.target = kSystemRid;
    CHECK(RunPaste(p, "x", 200, false) == PasteResult::kCopyOnly);
    CHECK(!p.Sent());
  }

  // ---- texts ----
  {  // NUL, bidi and a 1 MiB text are passed whole, byte for byte
    Fake p;
    std::string hostile("a\0b\xE2\x80\xAE" "c", 7);
    RunPaste(p, hostile, 200, true);
    CHECK(p.written == hostile && p.written.size() == 7);
    Fake q;
    std::string big(1024 * 1024, 'z');
    RunPaste(q, big, 200, true);
    CHECK(q.written.size() == big.size());
  }
  {  // our own window is never a target
    Fake p;
    p.usable = false;
    CHECK(RunPaste(p, "x", 100, true) == PasteResult::kTargetGone);
    CHECK(!p.Sent());
  }

  // ---- order of the steps: write, hide, activate, then send ----
  {
    Fake p;
    RunPaste(p, "x", 200, true);
    CHECK(p.log.size() == 4);
    CHECK(p.log[0] == "write" && p.log[1] == "hide" && p.log[2] == "activate");
  }

  // ---- key names: every damaged form is refused ----
  uint32_t vk = 0;
  const char* bad[] = {"",    " ",   "V",    "A",     "F1",   "f0",   "f13",
                       "f01", "f1 ", "f100", "f-1",   "f+1",  "fa",   "ff",
                       "vv",  "10",  "00",   "Space", "space ", "spac", "enter",
                       "tab", "esc", "é",    "\xC3\xA9", "\xEF\xBC\xA1" /*fullwidth A*/,
                       "\xD9\xA3" /*arabic 3*/, "-", "+", ",", "\t", "\n"};
  for (const char* b : bad) CHECK(!ParseKey(b, &vk));
  CHECK(!ParseKey(std::string("a\0", 2), &vk));
  CHECK(!ParseKey(std::string("\0", 1), &vk));
  CHECK(!ParseKey(std::string("f1\0", 3), &vk));
  CHECK(!ParseKey(std::string(100000, 'a'), &vk));
  // every good name has its own code
  std::vector<uint32_t> codes;
  std::vector<std::string> names;
  for (char c = 'a'; c <= 'z'; c++) names.push_back(std::string(1, c));
  for (char c = '0'; c <= '9'; c++) names.push_back(std::string(1, c));
  for (int i = 1; i <= 12; i++) names.push_back("f" + std::to_string(i));
  names.push_back("space");
  for (const auto& n : names) {
    CHECK(ParseKey(n, &vk));
    for (uint32_t c : codes) CHECK(c != vk);
    codes.push_back(vk);
  }
  CHECK(codes.size() == 49);

  // ---- modifier names ----
  uint32_t m = 0;
  CHECK(!ParseModifiers({"ctrl", "ctrl", "bogus"}, &m));
  CHECK(!ParseModifiers({"CTRL"}, &m));
  CHECK(!ParseModifiers({""}, &m));
  CHECK(!ParseModifiers({"win"}, &m));
  CHECK(!ParseModifiers({"cmd"}, &m));
  CHECK(ParseModifiers({"ctrl", "ctrl"}, &m) && m == kModControl);
  CHECK(ParseModifiers({"ctrl", "alt", "shift", "meta"}, &m) && m == 0xF);
  CHECK(IsUsableShortcut(0xF));
  CHECK(!IsUsableShortcut(kModShift));

  // ---- placement on odd screens ----
  {  // a second screen to the left, with negative coordinates
    Rect work{-1920, 0, 0, 1040};
    Rect f = PickerFrame(work, 1.0);
    CHECK(f.left >= work.left && f.right <= work.right);
    CHECK(f.top >= work.top && f.bottom <= work.bottom);
    Rect t = ToastFrame(-5, 1035, work, 1.0);
    CHECK(t.left >= work.left && t.right <= work.right);
    CHECK(t.top >= work.top && t.bottom <= work.bottom);
  }
  {  // 300% text-scaling laptop: 1280 x 720 points at scale 3
    Rect work{0, 0, 3840, 2160 - 120};
    Rect f = PickerFrame(work, 3.0);
    CHECK(f.Width() == 1680 && f.Height() == 1260);
    CHECK(f.bottom <= work.bottom && f.top >= work.top);
  }
  {  // a work area narrower than the minimum: never wider than the screen
    // (the spec's 240 point minimum height wins over a shorter screen)
    Rect work{0, 0, 320, 200};
    Rect f = PickerFrame(work, 1.0);
    CHECK(f.Width() <= work.Width());
    CHECK(f.top == work.top);
  }
  {  // a work area that is exactly the minimum
    Rect work{0, 0, 360, 240};
    Rect f = PickerFrame(work, 1.0);
    CHECK(f.Width() == 360 && f.Height() == 240);
    CHECK(f.left == 0 && f.top == 0);
  }
  {  // pointer outside every screen picks the first, never crashes
    std::vector<Rect> areas{{0, 0, 100, 100}};
    CHECK(PickAreaContaining(-50, -50, areas) == 0);
    CHECK(PickAreaContaining(100, 100, areas) == 0);  // edges are exclusive
    CHECK(PickAreaContaining(99, 99, areas) == 0);
  }

  // ---- shell windows ----
  CHECK(!IsShellWindowClass(""));
  CHECK(!IsShellWindowClass("shell_traywnd"));  // class names are case-exact
  CHECK(!IsShellWindowClass("Shell_TrayWnd "));
  CHECK(IsShellWindowClass("WorkerW"));

  if (failures == 0) std::printf("all picker edge checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
