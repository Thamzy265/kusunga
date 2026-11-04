#ifndef RUNNER_PICKER_POLICY_H_
#define RUNNER_PICKER_POLICY_H_

// The rules of the Windows picker (design note `docs/design/history-picker.md`,
// "How paste works"), with no Windows dependencies so that they can be tested
// anywhere (picker_policy_test.cpp). The Windows calls live in
// picker_bridge.cpp, which only supplies a PastePlatform.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace kusunga {

// ---- Shortcut keys: the names Dart sends (lib/picker/shortcut.dart) ----

// The MOD_* values of RegisterHotKey.
constexpr uint32_t kModAlt = 0x1;
constexpr uint32_t kModControl = 0x2;
constexpr uint32_t kModShift = 0x4;
constexpr uint32_t kModWin = 0x8;

// Virtual-key code for a key name: a-z, 0-9, f1-f12 and space. False for
// anything else.
inline bool ParseKey(const std::string& name, uint32_t* vk) {
  if (name.size() == 1) {
    const char c = name[0];
    if (c >= 'a' && c <= 'z') {
      *vk = static_cast<uint32_t>(c - 'a' + 'A');
      return true;
    }
    if (c >= '0' && c <= '9') {
      *vk = static_cast<uint32_t>(c);
      return true;
    }
    return false;
  }
  if (name == "space") {
    *vk = 0x20;
    return true;
  }
  if (name.size() >= 2 && name.size() <= 3 && name[0] == 'f') {
    int n = 0;
    for (size_t i = 1; i < name.size(); i++) {
      if (name[i] < '0' || name[i] > '9') return false;
      n = n * 10 + (name[i] - '0');
    }
    if (name[1] == '0' || n < 1 || n > 12) return false;
    *vk = static_cast<uint32_t>(0x70 + n - 1);  // VK_F1 is 0x70
    return true;
  }
  return false;
}

// ctrl, alt, shift and meta (the Windows key). False for an unknown name.
inline bool ParseModifiers(const std::vector<std::string>& names,
                           uint32_t* mods) {
  uint32_t m = 0;
  for (const auto& n : names) {
    if (n == "ctrl") {
      m |= kModControl;
    } else if (n == "alt") {
      m |= kModAlt;
    } else if (n == "shift") {
      m |= kModShift;
    } else if (n == "meta") {
      m |= kModWin;
    } else {
      return false;
    }
  }
  *mods = m;
  return true;
}

// Shift alone would fire while typing: one of Ctrl, Alt or Win is needed.
inline bool IsUsableShortcut(uint32_t mods) {
  return (mods & (kModControl | kModAlt | kModWin)) != 0;
}

enum class HotKeyResult { kOk, kTaken, kInvalid };

// The answer Dart expects.
inline const char* HotKeyAnswer(HotKeyResult r) {
  switch (r) {
    case HotKeyResult::kOk:
      return "ok";
    case HotKeyResult::kTaken:
      return "taken";
    case HotKeyResult::kInvalid:
      break;
  }
  return "invalid";
}

// ---- Integrity levels (UIPI blocks SendInput into a higher level) ----

constexpr uint32_t kLowRid = 0x1000;
constexpr uint32_t kMediumRid = 0x2000;
constexpr uint32_t kHighRid = 0x3000;
constexpr uint32_t kSystemRid = 0x4000;

enum class SendDecision { kSend, kElevated, kUnknown };

// 0 means "could not be read". An unreadable level fails closed: nothing is
// sent.
inline SendDecision DecideSend(uint32_t own_level, uint32_t target_level) {
  if (own_level == 0 || target_level == 0) return SendDecision::kUnknown;
  return target_level > own_level ? SendDecision::kElevated
                                  : SendDecision::kSend;
}

// ---- Windows that are never a paste target ----

// The taskbar, the notification area, a menu and the desktop. When the picker
// is opened from the tray, the "window that had focus" can be one of these;
// Ctrl+V into them would be wrong, so the paste only copies.
inline bool IsShellWindowClass(const std::string& name) {
  static const char* const kClasses[] = {
      "Shell_TrayWnd",  "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow",
      "TrayNotifyWnd",  "#32768",                 "Progman",
      "WorkerW"};
  for (const char* c : kClasses) {
    if (name == c) return true;
  }
  return false;
}

// ---- Placement (UI spec, "Layout" and "Breakpoints") ----

struct Rect {
  int left, top, right, bottom;
  int Width() const { return right - left; }
  int Height() const { return bottom - top; }
};

constexpr double kPickerWidth = 560;
constexpr double kPickerHeight = 420;
constexpr double kMinWidth = 360;
constexpr double kMinHeight = 240;
constexpr double kToastWidth = 360;
constexpr double kToastHeight = 96;
constexpr double kToastGap = 12;

// [scale] is the DPI scale (1.0 at 96 dpi); [work] is in pixels.
// 560 x 420 points, centred across the work area and in its upper part. On a
// screen narrower than 800 points the width is 90% of it (at least 360).
inline Rect PickerFrame(Rect work, double scale) {
  const double screen_w = work.Width() / scale;
  const double screen_h = work.Height() / scale;
  double w = kPickerWidth;
  if (screen_w < 800) w = std::max(kMinWidth, screen_w * 0.9);
  w = std::min(w, screen_w);
  // Never taller than the screen, even when the screen is shorter than the
  // minimum height (the list scrolls).
  const double h = std::min(
      screen_h,
      std::max(kMinHeight, std::min({kPickerHeight, screen_h * 0.8, screen_h})));
  const int width = static_cast<int>(std::lround(w * scale));
  const int height = static_cast<int>(std::lround(h * scale));
  const int left = work.left + (work.Width() - width) / 2;
  int top = work.top + work.Height() / 6;
  if (top + height > work.bottom) top = std::max(work.top, work.bottom - height);
  return Rect{left, top, left + width, top + height};
}

// Just below and to the right of the pointer, kept inside [work].
inline Rect ToastFrame(int pointer_x, int pointer_y, Rect work, double scale) {
  const int width = static_cast<int>(std::lround(kToastWidth * scale));
  const int height = static_cast<int>(std::lround(kToastHeight * scale));
  const int gap = static_cast<int>(std::lround(kToastGap * scale));
  int left = pointer_x + gap;
  int top = pointer_y + gap;
  left = std::max(work.left, std::min(left, work.right - width));
  top = std::max(work.top, std::min(top, work.bottom - height));
  return Rect{left, top, left + width, top + height};
}

// The index of the area that contains the point; the first one if none does;
// -1 if there are no areas.
inline int PickAreaContaining(int x, int y, const std::vector<Rect>& areas) {
  for (size_t i = 0; i < areas.size(); i++) {
    const Rect& r = areas[i];
    if (x >= r.left && x < r.right && y >= r.top && y < r.bottom) {
      return static_cast<int>(i);
    }
  }
  return areas.empty() ? -1 : 0;
}

// ---- Esc: what the picker gives back (E1) ----

struct ClosePlan {
  bool show_manage;
  bool activate_kusunga;
  bool reactivate_target;
};

// The history window comes back without being activated, and the window the
// user was in gets the focus back. Kusunga is activated only if it was the
// window in front (there is no other target).
inline ClosePlan PlanClose(bool manage_was_visible, bool has_target) {
  return ClosePlan{manage_was_visible, manage_was_visible && !has_target,
                   has_target};
}

// ---- Putting the history window back after the picker or the toast (W1) ----

enum class RestoreShow {
  kHide,
  kMinimizedNoActivate,
  kShowNoActivate,
  kShowActivate,
  kShowMaximizedActivate
};

// A window that was hidden stays hidden and a minimised one stays minimised
// (it keeps its taskbar button); neither is ever activated by the restore.
// Only a history window that was on screen is shown again, and activated only
// if [activate].
// A maximised window is maximised again only on the activating path
// (SW_SHOWMAXIMIZED always activates); otherwise it returns at normal size.
inline RestoreShow DecideRestoreShow(bool was_visible, bool was_minimised,
                                     bool show_manage, bool activate,
                                     bool was_maximised = false) {
  if (was_visible && was_minimised) return RestoreShow::kMinimizedNoActivate;
  if (!was_visible || !show_manage) return RestoreShow::kHide;
  if (!activate) return RestoreShow::kShowNoActivate;
  return was_maximised ? RestoreShow::kShowMaximizedActivate
                       : RestoreShow::kShowActivate;
}

// The saved window style must not carry WS_MINIMIZE (0x20000000) or
// WS_MAXIMIZE (0x01000000): the window is positioned at its normal rectangle,
// and the minimised or maximised state is applied afterwards by the show
// command.
inline uintptr_t StyleForRestore(uintptr_t saved_style) {
  return saved_style & ~static_cast<uintptr_t>(0x20000000 | 0x01000000);
}

// The rectangle (in screen coordinates) to put the window back at. A normal
// window: its real rectangle. A minimised or maximised one: GetWindowPlacement's
// rcNormalPosition, which is relative to the primary monitor's work area, so
// the work-area origin is added.
inline Rect RectToRestore(bool is_normal, Rect window_rect, Rect normal_position,
                          int work_origin_x, int work_origin_y) {
  if (is_normal) return window_rect;
  return Rect{normal_position.left + work_origin_x,
              normal_position.top + work_origin_y,
              normal_position.right + work_origin_x,
              normal_position.bottom + work_origin_y};
}

enum class ShowCommand { kShowNoActivate, kRestore };

// How a minimised or maximised history window is made ready for the small
// shape: the toast must not take focus.
inline ShowCommand ShowCommandToOpenSmallWindow(bool no_activate) {
  return no_activate ? ShowCommand::kShowNoActivate : ShowCommand::kRestore;
}

// ---- Scale of a monitor (W2) ----

// 96 dpi is 1.0. 0 means "unknown".
inline double ScaleFromDpi(unsigned dpi) {
  return dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
}

// ---- The paste flow ----

// What the flow needs from Windows. Window handles are plain numbers here.
class PastePlatform {
 public:
  virtual ~PastePlatform() = default;
  // Puts the text (UTF-8) on the clipboard with our own marker format.
  virtual bool WriteClipboard(const std::string& text) = 0;
  virtual void HidePicker() = 0;
  // The window exists and is not one of ours.
  virtual bool IsUsableTarget(uintptr_t window) = 0;
  virtual void Activate(uintptr_t window) = 0;
  virtual uintptr_t Foreground() = 0;
  // The RID of the integrity level, 0 if it cannot be read.
  virtual uint32_t OwnIntegrity() = 0;
  virtual uint32_t TargetIntegrity(uintptr_t window) = 0;
  // Ctrl, Shift, Alt or Win is held down right now.
  virtual bool ModifiersDown() = 0;
  virtual void SendPaste() = 0;
  virtual void Sleep(int ms) = 0;
  virtual int NowMs() = 0;
};

enum class PasteResult {
  kPasted,
  kNoPermission,  // Mac only
  kFocusTimeout,
  kTargetGone,
  kTargetElevated,
  kCopyOnly,
  kFailed,
};

// The names Dart expects (lib/picker/channel_picker_port.dart).
inline const char* PasteResultName(PasteResult r) {
  switch (r) {
    case PasteResult::kPasted:
      return "pasted";
    case PasteResult::kNoPermission:
      return "noPermission";
    case PasteResult::kFocusTimeout:
      return "focusTimeout";
    case PasteResult::kTargetGone:
      return "targetGone";
    case PasteResult::kTargetElevated:
      return "targetElevated";
    case PasteResult::kCopyOnly:
      return "copyOnly";
    case PasteResult::kFailed:
      break;
  }
  return "failed";
}

constexpr int kFocusTimeoutMs = 500;
constexpr int kModifierTimeoutMs = 300;
constexpr int kPollMs = 10;

template <typename Condition>
bool WaitUntil(PastePlatform& p, int limit_ms, Condition condition) {
  const int start = p.NowMs();
  for (;;) {
    if (condition()) return true;
    if (p.NowMs() - start >= limit_ms) return false;
    p.Sleep(kPollMs);
  }
}

// Write the text, hide the picker, bring the remembered window back, confirm
// it is in front (up to 500 ms), and only then send Ctrl+V: not if the window
// is an administrator window (or its level is unknown), and not before the
// picker's modifier keys are released (up to 300 ms, otherwise copy only). The focus is checked
// again right before sending. Never sends into our own window or into any
// window that is not in front.
inline PasteResult RunPaste(PastePlatform& p, const std::string& text,
                            uintptr_t target, bool post) {
  const bool written = p.WriteClipboard(text);
  p.HidePicker();
  if (!written) return PasteResult::kFailed;

  if (target == 0 || !p.IsUsableTarget(target)) return PasteResult::kTargetGone;
  p.Activate(target);
  if (!WaitUntil(p, kFocusTimeoutMs, [&] { return p.Foreground() == target; })) {
    return PasteResult::kFocusTimeout;
  }
  if (!post) return PasteResult::kCopyOnly;

  switch (DecideSend(p.OwnIntegrity(), p.TargetIntegrity(target))) {
    case SendDecision::kElevated:
      return PasteResult::kTargetElevated;
    case SendDecision::kUnknown:
      return PasteResult::kCopyOnly;
    case SendDecision::kSend:
      break;
  }

  // A modifier still down after 300 ms: the app would see Ctrl+Shift+V, so no
  // keys are sent. The text stays on the clipboard (lead decision).
  if (!WaitUntil(p, kModifierTimeoutMs, [&] { return !p.ModifiersDown(); })) {
    return PasteResult::kCopyOnly;
  }
  if (p.Foreground() != target) return PasteResult::kFocusTimeout;
  p.SendPaste();
  return PasteResult::kPasted;
}

}  // namespace kusunga

#endif  // RUNNER_PICKER_POLICY_H_
