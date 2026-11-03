#include "picker_bridge.h"

#include <dwmapi.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <shellscalingapi.h>

#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "clipboard_policy.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kPickerChannel[] = "com.wnasoni.kusunga/picker";
constexpr UINT_PTR kOpenTimerId = 0x4B53;  // the 300 ms fallback
constexpr UINT kOpenFallbackMs = 300;

const EncodableValue* Find(const EncodableMap* map, const char* key) {
  if (!map) return nullptr;
  auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

std::wstring ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        out.data(), size);
  return out;
}

// The integrity level (RID) of a process, or 0 if it cannot be read. A medium
// process cannot open the token of a higher-level (administrator) process:
// "access denied" therefore means "higher", and is reported as such, so that
// the right message is shown.
uint32_t IntegrityOf(HANDLE process) {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(process, TOKEN_QUERY, &token)) {
    return ::GetLastError() == ERROR_ACCESS_DENIED ? kusunga::kHighRid : 0;
  }
  DWORD size = 0;
  ::GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &size);
  uint32_t rid = 0;
  if (size > 0) {
    std::vector<BYTE> buffer(size);
    if (::GetTokenInformation(token, TokenIntegrityLevel, buffer.data(), size,
                              &size)) {
      auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buffer.data());
      const DWORD count = *::GetSidSubAuthorityCount(label->Label.Sid);
      if (count > 0) rid = *::GetSidSubAuthority(label->Label.Sid, count - 1);
    }
  }
  ::CloseHandle(token);
  return rid;
}

bool IsOurWindow(HWND window) {
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  return pid == ::GetCurrentProcessId();
}

std::string ClassNameOf(HWND window) {
  char name[256] = {0};
  const int n = ::GetClassNameA(window, name, 255);
  return n > 0 ? std::string(name, static_cast<size_t>(n)) : std::string();
}

}  // namespace

// What the paste flow needs from Windows.
class WinPastePlatform : public kusunga::PastePlatform {
 public:
  WinPastePlatform(PickerBridge* bridge, HWND window, UINT format_own)
      : bridge_(bridge), window_(window), format_own_(format_own) {}

  bool WriteClipboard(const std::string& text) override {
    const std::wstring wide = ToWide(text);
    if (wide.empty() && !text.empty()) return false;
    const bool opened = kusunga::OpenWithRetry(
        [this] { return ::OpenClipboard(window_) != FALSE; },
        [](int ms) { ::Sleep(static_cast<DWORD>(ms)); });
    if (!opened) return false;
    bool ok = false;
    ::EmptyClipboard();
    const size_t bytes = (wide.size() + 1) * sizeof(wchar_t);
    HGLOBAL memory = ::GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory) {
      void* data = ::GlobalLock(memory);
      if (data) {
        std::memcpy(data, wide.c_str(), bytes);
        ::GlobalUnlock(memory);
        // The clipboard owns the memory after a successful SetClipboardData.
        if (::SetClipboardData(CF_UNICODETEXT, memory)) {
          ok = true;
        } else {
          ::GlobalFree(memory);
        }
      } else {
        ::GlobalFree(memory);
      }
    }
    if (ok && format_own_ != 0) {
      // Our own marker: the watcher then only moves the item to the top, and
      // only if it is already saved.
      HGLOBAL marker = ::GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
      if (marker) {
        void* data = ::GlobalLock(marker);
        if (data) {
          *static_cast<DWORD*>(data) = 1;
          ::GlobalUnlock(marker);
          if (!::SetClipboardData(format_own_, marker)) ::GlobalFree(marker);
        } else {
          ::GlobalFree(marker);
        }
      }
    }
    ::CloseClipboard();
    return ok;
  }

  void HidePicker() override { bridge_->HidePickerForPaste(); }

  bool IsUsableTarget(uintptr_t window) override {
    HWND hwnd = reinterpret_cast<HWND>(window);
    if (!::IsWindow(hwnd) || IsOurWindow(hwnd)) return false;
    return !kusunga::IsShellWindowClass(ClassNameOf(hwnd));
  }

  void Activate(uintptr_t window) override {
    HWND hwnd = reinterpret_cast<HWND>(window);
    if (::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
    ::SetForegroundWindow(hwnd);
  }

  uintptr_t Foreground() override {
    return reinterpret_cast<uintptr_t>(::GetForegroundWindow());
  }

  uint32_t OwnIntegrity() override { return IntegrityOf(::GetCurrentProcess()); }

  uint32_t TargetIntegrity(uintptr_t window) override {
    DWORD pid = 0;
    ::GetWindowThreadProcessId(reinterpret_cast<HWND>(window), &pid);
    if (pid == 0) return 0;
    HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) {
      return ::GetLastError() == ERROR_ACCESS_DENIED ? kusunga::kHighRid : 0;
    }
    const uint32_t level = IntegrityOf(process);
    ::CloseHandle(process);
    return level;
  }

  bool ModifiersDown() override {
    for (int vk : {VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN}) {
      if (::GetAsyncKeyState(vk) & 0x8000) return true;
    }
    return false;
  }

  void SendPaste() override {
    INPUT inputs[4] = {};
    for (auto& input : inputs) input.type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = VK_CONTROL;
    inputs[1].ki.wVk = 'V';
    inputs[2].ki.wVk = 'V';
    inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
    inputs[3].ki.wVk = VK_CONTROL;
    inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
    ::SendInput(4, inputs, sizeof(INPUT));
  }

  void Sleep(int ms) override { ::Sleep(static_cast<DWORD>(ms)); }
  int NowMs() override { return static_cast<int>(::GetTickCount64() & 0x7FFFFFFF); }

 private:
  PickerBridge* bridge_;
  HWND window_;
  UINT format_own_;
};

PickerBridge::PickerBridge(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  format_own_ = ::RegisterClipboardFormatW(L"com.wnasoni.kusunga.self");
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kPickerChannel, &codec);
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleCall(call, std::move(result));
      });
}

PickerBridge::~PickerBridge() {
  UnregisterShortcut();
  ::KillTimer(window_, kOpenTimerId);
}

void PickerBridge::HandleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const std::string& method = call.method_name();

  if (method == "registerShortcut") {
    const auto* key = Find(args, "key");
    const auto* mods = Find(args, "modifiers");
    const std::string* key_text = key ? std::get_if<std::string>(key) : nullptr;
    const EncodableList* list =
        mods ? std::get_if<EncodableList>(mods) : nullptr;
    if (!key_text || !list) {
      result->Success(EncodableValue("invalid"));
      return;
    }
    std::vector<std::string> names;
    for (const auto& item : *list) {
      const std::string* name = std::get_if<std::string>(&item);
      if (!name) {
        result->Success(EncodableValue("invalid"));
        return;
      }
      names.push_back(*name);
    }
    result->Success(EncodableValue(RegisterShortcut(*key_text, names)));
  } else if (method == "unregisterShortcut") {
    UnregisterShortcut();
    result->Success();
  } else if (method == "openPicker") {
    BeginOpen();
    result->Success();
  } else if (method == "closePicker") {
    ClosePicker();
    result->Success();
  } else if (method == "paste") {
    const auto* text = Find(args, "text");
    const auto* post = Find(args, "post");
    const std::string* text_value =
        text ? std::get_if<std::string>(text) : nullptr;
    if (!text_value) {
      result->Success(EncodableValue("failed"));
      return;
    }
    const bool* post_flag = post ? std::get_if<bool>(post) : nullptr;
    const bool send = post_flag ? *post_flag : true;
    result->Success(EncodableValue(RunPasteFlow(*text_value, send)));
  } else if (method == "showToast") {
    ShowToast();
    result->Success();
  } else if (method == "hideToast") {
    HideToast();
    result->Success();
  } else if (method == "canPost" || method == "requestPostAccess") {
    // Windows needs no permission to send keys (administrator windows are
    // handled in the paste flow).
    result->Success(EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

// ---- The shortcut ----

const char* PickerBridge::RegisterShortcut(
    const std::string& key, const std::vector<std::string>& modifiers) {
  uint32_t vk = 0;
  uint32_t mods = 0;
  if (!kusunga::ParseKey(key, &vk) ||
      !kusunga::ParseModifiers(modifiers, &mods) ||
      !kusunga::IsUsableShortcut(mods)) {
    return kusunga::HotKeyAnswer(kusunga::HotKeyResult::kInvalid);
  }
  if (hotkey_id_ != 0 && vk == hotkey_vk_ && mods == hotkey_mods_) {
    return kusunga::HotKeyAnswer(kusunga::HotKeyResult::kOk);
  }
  // The new shortcut is registered before the old one is released, so a
  // refused one never leaves the user without a shortcut.
  const int new_id = hotkey_id_ == 1 ? 2 : 1;
  if (!::RegisterHotKey(window_, new_id, mods | MOD_NOREPEAT, vk)) {
    return kusunga::HotKeyAnswer(::GetLastError() == ERROR_HOTKEY_ALREADY_REGISTERED
                                     ? kusunga::HotKeyResult::kTaken
                                     : kusunga::HotKeyResult::kInvalid);
  }
  if (hotkey_id_ != 0) ::UnregisterHotKey(window_, hotkey_id_);
  hotkey_id_ = new_id;
  hotkey_vk_ = vk;
  hotkey_mods_ = mods;
  return kusunga::HotKeyAnswer(kusunga::HotKeyResult::kOk);
}

void PickerBridge::UnregisterShortcut() {
  if (hotkey_id_ != 0) ::UnregisterHotKey(window_, hotkey_id_);
  hotkey_id_ = 0;
  hotkey_vk_ = 0;
  hotkey_mods_ = 0;
}

std::optional<LRESULT> PickerBridge::HandleMessage(UINT message, WPARAM wparam,
                                                   LPARAM lparam) {
  switch (message) {
    case WM_GETMINMAXINFO:
      // The history window has a minimum size (360 x 400); the picker and the
      // toast are smaller, so while they show there is no minimum.
      if (mode_ != Mode::kNormal && lparam != 0) {
        auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
        info->ptMinTrackSize.x = 0;
        info->ptMinTrackSize.y = 0;
        return 0;
      }
      break;
    case WM_HOTKEY:
      if (hotkey_id_ != 0 && static_cast<int>(wparam) == hotkey_id_) {
        BeginOpen();
        return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kOpenTimerId) {
        ShowPendingPicker();
        return 0;
      }
      break;
    case WM_ACTIVATE:
      // The picker lost focus (a click outside, another window came forward).
      // The message still goes on to the default handling.
      if (LOWORD(wparam) == WA_INACTIVE) WindowDeactivated();
      break;
  }
  return std::nullopt;
}

// ---- Opening, closing and the window shapes ----

void PickerBridge::BeginOpen() {
  if (pasting_ || open_pending_ || mode_ == Mode::kPicker) return;
  HWND front = ::GetForegroundWindow();
  target_ = (front && !IsOurWindow(front)) ? front : nullptr;
  open_pending_ = true;
  // Dart switches the window to the picker first; if it does not answer, the
  // picker is shown after 300 ms anyway.
  ::SetTimer(window_, kOpenTimerId, kOpenFallbackMs, nullptr);
  channel_->InvokeMethod(
      "shortcutPressed", nullptr,
      std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
          [this](const EncodableValue*) { ShowPendingPicker(); },
          [this](const std::string&, const std::string&, const EncodableValue*) {
            ShowPendingPicker();
          },
          [this]() { ShowPendingPicker(); }));
}

void PickerBridge::ShowPendingPicker() {
  if (!open_pending_) return;
  open_pending_ = false;
  ::KillTimer(window_, kOpenTimerId);
  EnterPicker();
}

kusunga::Rect PickerBridge::WorkAreaAtPointer(double* scale) const {
  POINT pointer{0, 0};
  ::GetCursorPos(&pointer);
  HMONITOR monitor = ::MonitorFromPoint(pointer, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  kusunga::Rect work{0, 0, 1280, 800};
  if (monitor && ::GetMonitorInfo(monitor, &info)) {
    work = kusunga::Rect{info.rcWork.left, info.rcWork.top, info.rcWork.right,
                         info.rcWork.bottom};
  }
  // The scale of the screen the pointer is on (not the one the window was on).
  UINT dpi_x = 0;
  UINT dpi_y = 0;
  if (!monitor ||
      FAILED(::GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
    dpi_x = ::GetDpiForWindow(window_);
  }
  *scale = kusunga::ScaleFromDpi(dpi_x);
  return work;
}

void PickerBridge::SaveWindow() {
  if (saved_) return;
  saved_style_ = ::GetWindowLongPtr(window_, GWL_STYLE);
  saved_ex_style_ = ::GetWindowLongPtr(window_, GWL_EXSTYLE);
  saved_placement_ = WINDOWPLACEMENT{};
  saved_placement_.length = sizeof(saved_placement_);
  ::GetWindowPlacement(window_, &saved_placement_);
  saved_visible_ = ::IsWindowVisible(window_) != FALSE;
  saved_minimised_ = ::IsIconic(window_) != FALSE;
  saved_ = true;
}

// Puts the style and the position back without showing or activating anything
// (SetWindowPlacement would show a hidden window and activate it). The caller
// then shows the window as DecideRestoreShow says.
void PickerBridge::RestoreWindow(bool show_manage, bool activate) {
  if (!saved_) return;
  const bool was_visible = saved_visible_;
  const bool was_minimised = saved_minimised_;
  ::SetWindowLongPtr(window_, GWL_STYLE, saved_style_);
  ::SetWindowLongPtr(window_, GWL_EXSTYLE, saved_ex_style_);
  const RECT& r = saved_placement_.rcNormalPosition;
  ::SetWindowPos(window_, HWND_NOTOPMOST, r.left, r.top, r.right - r.left,
                 r.bottom - r.top, SWP_NOACTIVATE | SWP_FRAMECHANGED);
  saved_ = false;
  switch (kusunga::DecideRestoreShow(was_visible, was_minimised, show_manage,
                                     activate)) {
    case kusunga::RestoreShow::kHide:
      ::ShowWindow(window_, SW_HIDE);
      break;
    case kusunga::RestoreShow::kMinimizedNoActivate:
      ::ShowWindow(window_, SW_SHOWMINNOACTIVE);
      break;
    case kusunga::RestoreShow::kShowNoActivate:
      ::ShowWindow(window_, SW_SHOWNOACTIVATE);
      break;
    case kusunga::RestoreShow::kShowActivate:
      ::ShowWindow(window_, SW_SHOW);
      ::SetForegroundWindow(window_);
      break;
  }
}

void PickerBridge::ApplySmallShape(kusunga::Rect frame, bool no_activate) {
  if (::IsZoomed(window_) || ::IsIconic(window_)) {
    ::ShowWindow(window_,
                 kusunga::ShowCommandToOpenSmallWindow(no_activate) ==
                         kusunga::ShowCommand::kShowNoActivate
                     ? SW_SHOWNOACTIVATE
                     : SW_RESTORE);
  }
  LONG_PTR style = saved_style_;
  style &= ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW);
  style |= WS_POPUP;
  LONG_PTR ex_style = saved_ex_style_ | WS_EX_TOOLWINDOW;  // no taskbar button
  if (no_activate) ex_style |= WS_EX_NOACTIVATE;
  ::SetWindowLongPtr(window_, GWL_STYLE, style);
  ::SetWindowLongPtr(window_, GWL_EXSTYLE, ex_style);
  // Rounded corners where Windows 11 supports it (ignored elsewhere).
  const int corner = 2;  // DWMWCP_ROUND
  ::DwmSetWindowAttribute(window_, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */,
                          &corner, sizeof(corner));
  UINT flags = SWP_FRAMECHANGED | SWP_SHOWWINDOW;
  if (no_activate) flags |= SWP_NOACTIVATE;
  ::SetWindowPos(window_, HWND_TOPMOST, frame.left, frame.top, frame.Width(),
                 frame.Height(), flags);
}

void PickerBridge::EnterPicker() {
  if (mode_ == Mode::kNormal) {
    manage_was_visible_ = ::IsWindowVisible(window_) && !::IsIconic(window_);
  } else if (mode_ == Mode::kToast) {
    manage_was_visible_ = false;
  }
  SaveWindow();
  mode_ = Mode::kPicker;
  double scale = 1.0;
  const kusunga::Rect work = WorkAreaAtPointer(&scale);
  ApplySmallShape(kusunga::PickerFrame(work, scale), false);
  ::SetForegroundWindow(window_);
}

void PickerBridge::LeavePicker(bool show_manage, bool activate) {
  if (mode_ != Mode::kPicker) return;
  mode_ = Mode::kNormal;
  RestoreWindow(show_manage, activate);
}

void PickerBridge::HidePickerForPaste() { LeavePicker(false, false); }

// Esc: the history window comes back without being activated and the window
// the user was in gets the focus back (Kusunga only if it was in front).
void PickerBridge::ClosePicker() {
  if (mode_ != Mode::kPicker) return;
  HWND previous = target_;
  const bool has_target =
      previous && ::IsWindow(previous) && !IsOurWindow(previous);
  const kusunga::ClosePlan plan =
      kusunga::PlanClose(manage_was_visible_, has_target);
  LeavePicker(plan.show_manage, plan.activate_kusunga);
  if (plan.reactivate_target) {
    if (::IsIconic(previous)) ::ShowWindow(previous, SW_RESTORE);
    ::SetForegroundWindow(previous);
  }
  target_ = nullptr;
}

void PickerBridge::WindowDeactivated() {
  if (mode_ != Mode::kPicker || pasting_) return;
  LeavePicker(manage_was_visible_, false);
  target_ = nullptr;
  channel_->InvokeMethod("dismissed", nullptr);
}

void PickerBridge::ShowToast() {
  if (mode_ == Mode::kPicker) return;
  SaveWindow();
  mode_ = Mode::kToast;
  POINT pointer{0, 0};
  ::GetCursorPos(&pointer);
  double scale = 1.0;
  const kusunga::Rect work = WorkAreaAtPointer(&scale);
  ApplySmallShape(kusunga::ToastFrame(pointer.x, pointer.y, work, scale), true);
}

void PickerBridge::HideToast() {
  if (mode_ != Mode::kToast) return;
  mode_ = Mode::kNormal;
  RestoreWindow(false, false);
}

std::string PickerBridge::RunPasteFlow(const std::string& text, bool post) {
  pasting_ = true;
  WinPastePlatform platform(this, window_, format_own_);
  const kusunga::PasteResult result = kusunga::RunPaste(
      platform, text, reinterpret_cast<uintptr_t>(target_), post);
  target_ = nullptr;
  pasting_ = false;
  return kusunga::PasteResultName(result);
}
