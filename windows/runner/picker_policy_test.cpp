// Tests for picker_policy.h: the rules of the Windows picker (shortcut keys,
// placement, the paste flow with its focus and administrator checks). No
// Windows dependencies, so this builds anywhere (see
// tool/test_windows_policy.sh). It is not part of the Windows build.
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

// A pretend Windows: time moves only when the flow sleeps.
class FakePlatform : public PastePlatform {
 public:
  std::vector<std::string> log;
  int now = 0;
  bool write_ok = true;
  uintptr_t foreground = 100;
  bool target_usable = true;
  int front_after_ms = 20;  // -1: never
  int activated_at = -1;
  int steal_at_ms = -1;
  int modifiers_until_ms = -1;  // -1 none, INT32_MAX forever
  uint32_t own_level = kMediumRid;
  uint32_t target_level = kMediumRid;

  bool WriteClipboard(const std::string& text) override {
    log.push_back("write");
    written = text;
    return write_ok;
  }
  void HidePicker() override { log.push_back("hide"); }
  bool IsUsableTarget(uintptr_t) override { return target_usable; }
  void Activate(uintptr_t) override {
    log.push_back("activate");
    activated_at = now;
  }
  uintptr_t Foreground() override {
    if (activated_at >= 0 && front_after_ms >= 0 &&
        now >= activated_at + front_after_ms && foreground != 300) {
      foreground = 200;
    }
    if (steal_at_ms >= 0 && now >= steal_at_ms) foreground = 300;
    return foreground;
  }
  uint32_t OwnIntegrity() override { return own_level; }
  uint32_t TargetIntegrity(uintptr_t) override { return target_level; }
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
  bool Did(const char* what) const {
    for (const auto& l : log)
      if (l == what) return true;
    return false;
  }
  std::string written;
};

int main() {
  // ---- shortcut keys ----
  uint32_t vk = 0;
  CHECK(ParseKey("v", &vk) && vk == 'V');
  CHECK(ParseKey("a", &vk) && vk == 'A');
  CHECK(ParseKey("z", &vk) && vk == 'Z');
  CHECK(ParseKey("0", &vk) && vk == '0');
  CHECK(ParseKey("9", &vk) && vk == '9');
  CHECK(ParseKey("f1", &vk) && vk == 0x70);
  CHECK(ParseKey("f12", &vk) && vk == 0x7B);
  CHECK(ParseKey("space", &vk) && vk == 0x20);
  for (const char* bad : {"", "V", "enter", "f13", "f0", "ab", "esc", "é", "tab"}) {
    vk = 7;
    CHECK(!ParseKey(bad, &vk));
  }
  {
    // Every allowed key is accepted and they are all different.
    std::vector<std::string> names;
    for (char c = 'a'; c <= 'z'; c++) names.push_back(std::string(1, c));
    for (char c = '0'; c <= '9'; c++) names.push_back(std::string(1, c));
    for (int n = 1; n <= 12; n++) names.push_back("f" + std::to_string(n));
    names.push_back("space");
    std::vector<uint32_t> seen;
    for (const auto& n : names) {
      uint32_t code = 0;
      CHECK(ParseKey(n, &code));
      for (uint32_t s : seen) CHECK(s != code);
      seen.push_back(code);
    }
    CHECK(names.size() == 26 + 10 + 12 + 1);
  }

  uint32_t mods = 0;
  CHECK(ParseModifiers({"ctrl", "shift"}, &mods) &&
        mods == (kModControl | kModShift));
  CHECK(ParseModifiers({"alt"}, &mods) && mods == kModAlt);
  CHECK(ParseModifiers({"meta"}, &mods) && mods == kModWin);
  CHECK(ParseModifiers({}, &mods) && mods == 0);
  CHECK(!ParseModifiers({"ctrl", "hyper"}, &mods));
  CHECK(!ParseModifiers({"Ctrl"}, &mods));
  CHECK(kModAlt == 0x1 && kModControl == 0x2 && kModShift == 0x4 &&
        kModWin == 0x8);  // the MOD_* values of RegisterHotKey

  CHECK(IsUsableShortcut(kModControl | kModShift));
  CHECK(IsUsableShortcut(kModAlt));
  CHECK(IsUsableShortcut(kModWin));
  CHECK(!IsUsableShortcut(kModShift));
  CHECK(!IsUsableShortcut(0));

  CHECK(HotKeyAnswer(HotKeyResult::kOk) == std::string("ok"));
  CHECK(HotKeyAnswer(HotKeyResult::kTaken) == std::string("taken"));
  CHECK(HotKeyAnswer(HotKeyResult::kInvalid) == std::string("invalid"));

  // ---- integrity levels ----
  CHECK(DecideSend(kMediumRid, kMediumRid) == SendDecision::kSend);
  CHECK(DecideSend(kMediumRid, kLowRid) == SendDecision::kSend);
  CHECK(DecideSend(kHighRid, kHighRid) == SendDecision::kSend);
  CHECK(DecideSend(kHighRid, kMediumRid) == SendDecision::kSend);
  CHECK(DecideSend(kMediumRid, kHighRid) == SendDecision::kElevated);
  CHECK(DecideSend(kMediumRid, kSystemRid) == SendDecision::kElevated);
  CHECK(DecideSend(kMediumRid, 0) == SendDecision::kUnknown);  // fail closed
  CHECK(DecideSend(0, kMediumRid) == SendDecision::kUnknown);

  // ---- windows that are never a paste target ----
  for (const char* shell : {"Shell_TrayWnd", "Shell_SecondaryTrayWnd",
                            "NotifyIconOverflowWindow", "TrayNotifyWnd", "#32768",
                            "Progman", "WorkerW"}) {
    CHECK(IsShellWindowClass(shell));
  }
  for (const char* app : {"Notepad", "Chrome_WidgetWin_1", "CabinetWClass", "", "shell_traywnd"}) {
    CHECK(!IsShellWindowClass(app));
  }

  // ---- placement ----
  {
    Rect work{0, 0, 1920, 1040};
    Rect f = PickerFrame(work, 1.0);
    CHECK(f.Width() == 560 && f.Height() == 420);
    CHECK(f.left + f.Width() / 2 == (work.left + work.right) / 2);
    CHECK(f.top == work.top + work.Height() / 6);
    CHECK(f.left >= work.left && f.right <= work.right && f.bottom <= work.bottom);

    Rect big{0, 0, 3840, 2080};  // a 4K screen at 200%
    Rect scaled = PickerFrame(big, 2.0);
    CHECK(scaled.Width() == 1120 && scaled.Height() == 840);
    CHECK(scaled.left >= big.left && scaled.right <= big.right &&
          scaled.bottom <= big.bottom);

    Rect small{0, 0, 700, 500};
    Rect s = PickerFrame(small, 1.0);
    CHECK(s.Width() == 630);  // 90% below 800
    CHECK(s.left >= small.left && s.right <= small.right && s.bottom <= small.bottom);

    Rect narrow{0, 0, 380, 600};
    CHECK(PickerFrame(narrow, 1.0).Width() == 360);

    Rect second{1920, -200, 3840, 880};
    Rect on_second = PickerFrame(second, 1.0);
    CHECK(on_second.left + on_second.Width() / 2 == (second.left + second.right) / 2);

    Rect tiny{0, 0, 1000, 200};  // shorter than the 240 point minimum
    Rect t = PickerFrame(tiny, 1.0);
    CHECK(t.Height() <= 200 && t.top >= 0 && t.bottom <= 200);

    Rect short_screen{0, 0, 1000, 400};
    Rect sh = PickerFrame(short_screen, 1.0);
    CHECK(sh.Height() <= 400 && sh.Height() >= 240);
    CHECK(sh.top >= 0 && sh.bottom <= 400);
  }
  {
    Rect work{0, 0, 1920, 1040};
    Rect t = ToastFrame(500, 500, work, 1.0);
    CHECK(t.Width() == 360 && t.Height() == 96);
    CHECK(t.left == 512 && t.top == 512);  // just below and right of the pointer
    for (auto p : {std::pair<int, int>{1919, 1039}, {1, 1}, {1919, 1}, {1, 1039}}) {
      Rect e = ToastFrame(p.first, p.second, work, 1.0);
      CHECK(e.left >= work.left && e.top >= work.top && e.right <= work.right &&
            e.bottom <= work.bottom);
    }
  }
  {
    Rect a{0, 0, 1000, 800}, b{1000, 0, 2000, 800};
    std::vector<Rect> screens{a, b};
    CHECK(PickAreaContaining(1500, 100, screens) == 1);
    CHECK(PickAreaContaining(10, 10, screens) == 0);
    CHECK(PickAreaContaining(5000, 5000, screens) == 0);
    CHECK(PickAreaContaining(0, 0, {}) == -1);
  }

  // ---- Esc (E1) ----
  {
    ClosePlan a = PlanClose(true, true);
    CHECK(a.show_manage && !a.activate_kusunga && a.reactivate_target);
    ClosePlan b = PlanClose(false, true);
    CHECK(!b.show_manage && !b.activate_kusunga && b.reactivate_target);
    ClosePlan c = PlanClose(true, false);  // Kusunga itself was in front
    CHECK(c.show_manage && c.activate_kusunga && !c.reactivate_target);
    ClosePlan d = PlanClose(false, false);
    CHECK(!d.show_manage && !d.activate_kusunga && !d.reactivate_target);
  }

  // ---- putting the history window back (W1) ----
  // was_visible, was_minimised, show_manage, activate
  CHECK(DecideRestoreShow(true, false, false, false) == RestoreShow::kHide);
  CHECK(DecideRestoreShow(false, false, false, false) == RestoreShow::kHide);
  CHECK(DecideRestoreShow(true, false, true, false) == RestoreShow::kShowNoActivate);
  CHECK(DecideRestoreShow(true, false, true, true) == RestoreShow::kShowActivate);
  // A minimised history window stays minimised, keeping its taskbar button,
  // and never takes the focus.
  CHECK(DecideRestoreShow(true, true, false, false) == RestoreShow::kMinimizedNoActivate);
  CHECK(DecideRestoreShow(true, true, true, true) == RestoreShow::kMinimizedNoActivate);
  // A window that was hidden is never shown by the restore, whatever is asked
  // (the picker comes from the tray with the history window closed).
  CHECK(DecideRestoreShow(false, false, true, true) == RestoreShow::kHide);
  // The toast path never activates.
  CHECK(ShowCommandToOpenSmallWindow(true) == ShowCommand::kShowNoActivate);
  CHECK(ShowCommandToOpenSmallWindow(false) == ShowCommand::kRestore);

  // ---- DPI of the pointer's monitor (W2) ----
  CHECK(ScaleFromDpi(96) == 1.0);
  CHECK(ScaleFromDpi(144) == 1.5);
  CHECK(ScaleFromDpi(192) == 2.0);
  CHECK(ScaleFromDpi(0) == 1.0);  // unknown: no scaling

  // ---- paste flow ----
  {
    FakePlatform p;
    CHECK(RunPaste(p, "hello", 200, true) == PasteResult::kPasted);
    CHECK(p.log.size() >= 4);
    CHECK(p.log[0] == "write" && p.log[1] == "hide" && p.log[2] == "activate");
    CHECK(p.Sent());
    CHECK(p.written == "hello");
  }
  {  // posts only after the target is in front
    FakePlatform p;
    p.front_after_ms = 120;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kPasted);
    CHECK(p.SentAt() >= 120);
  }
  {  // focus never comes back: give up at 500 ms, never send
    FakePlatform p;
    p.front_after_ms = -1;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kFocusTimeout);
    CHECK(!p.Sent());
    CHECK(p.now >= 500 && p.now <= 520);
    CHECK(p.written == "x");
  }
  {  // just in time, and just too late
    FakePlatform p;
    p.front_after_ms = 490;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kPasted);
    FakePlatform q;
    q.front_after_ms = 530;
    CHECK(RunPaste(q, "x", 200, true) == PasteResult::kFocusTimeout);
    CHECK(!q.Sent());
  }
  {  // no target, or a target that is gone or ours
    FakePlatform none;
    CHECK(RunPaste(none, "x", 0, true) == PasteResult::kTargetGone);
    CHECK(!none.Did("activate") && !none.Sent());
    FakePlatform gone;
    gone.target_usable = false;
    CHECK(RunPaste(gone, "x", 200, true) == PasteResult::kTargetGone);
    CHECK(!gone.Did("activate") && !gone.Sent());
    CHECK(gone.written == "x");
  }
  {  // copy-only mode still brings the app back
    FakePlatform p;
    CHECK(RunPaste(p, "x", 200, false) == PasteResult::kCopyOnly);
    CHECK(p.Did("activate") && !p.Sent());
  }
  {  // administrator window: no keys are sent
    FakePlatform p;
    p.target_level = kHighRid;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kTargetElevated);
    CHECK(!p.Sent() && p.Did("activate"));
  }
  {  // cannot tell the integrity level: copy only
    FakePlatform p;
    p.target_level = 0;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kCopyOnly);
    CHECK(!p.Sent());
  }
  {  // wait for Ctrl+Shift to be released
    FakePlatform p;
    p.modifiers_until_ms = 150;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kPasted);
    CHECK(p.SentAt() >= 150);
  }
  {  // held for ever: wait 300 ms, then copy only (lead decision: no keys
     // are sent while a modifier is still down)
    FakePlatform p;
    p.modifiers_until_ms = INT32_MAX;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kCopyOnly);
    CHECK(!p.Sent());
    CHECK(p.now >= 300 && p.now <= 20 + 300 + 30);
  }
  {  // released at the last moment: still pasted
    FakePlatform p;
    p.modifiers_until_ms = 20 + 290;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kPasted);
  }
  {  // focus stolen while waiting: never send
    FakePlatform p;
    p.modifiers_until_ms = 200;
    p.steal_at_ms = 100;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kFocusTimeout);
    CHECK(!p.Sent());
  }
  {  // another app in front from the start
    FakePlatform p;
    p.front_after_ms = -1;
    p.foreground = 300;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kFocusTimeout);
    CHECK(!p.Sent());
  }
  {  // clipboard cannot be written
    FakePlatform p;
    p.write_ok = false;
    CHECK(RunPaste(p, "x", 200, true) == PasteResult::kFailed);
    CHECK(!p.Did("activate") && !p.Sent() && p.Did("hide"));
  }
  {  // a long text is passed whole
    FakePlatform p;
    std::string big(100000, 'a');
    RunPaste(p, big, 200, true);
    CHECK(p.written == big);
  }
  {  // answers use the names Dart expects
    CHECK(std::string(PasteResultName(PasteResult::kPasted)) == "pasted");
    CHECK(std::string(PasteResultName(PasteResult::kFocusTimeout)) == "focusTimeout");
    CHECK(std::string(PasteResultName(PasteResult::kTargetGone)) == "targetGone");
    CHECK(std::string(PasteResultName(PasteResult::kTargetElevated)) == "targetElevated");
    CHECK(std::string(PasteResultName(PasteResult::kCopyOnly)) == "copyOnly");
    CHECK(std::string(PasteResultName(PasteResult::kFailed)) == "failed");
    CHECK(std::string(PasteResultName(PasteResult::kNoPermission)) == "noPermission");
  }

  if (failures == 0) std::printf("all picker policy checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
