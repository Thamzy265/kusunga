#include "typed_shortcut_bridge.h"

#include <flutter/standard_method_codec.h>
#include <uiautomation.h>

#include <algorithm>
#include <cstring>
#include <functional>
#include <future>
#include <iterator>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "clipboard_bridge.h"
#include "picker_policy.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kShortcutsChannel[] = "com.wnasoni.kusunga/shortcuts";

// Posted to Kusunga's window (the UI thread).
constexpr UINT kMsgMatched = WM_APP + 0x51;    // the field check passed
constexpr UINT kMsgHookLost = WM_APP + 0x52;   // removed, and not put back
constexpr UINT kMsgHookState = WM_APP + 0x53;  // put back after Kusunga was
                                               // activated (wparam 1) or not
// The replacement's timers (the 0.5 s restore, D2; the 10 ms modifier
// poll, C1), on Kusunga's window: one id each, from this range.
constexpr UINT_PTR kFirstFlowTimerId = 0x4C00;
constexpr UINT_PTR kFlowTimerIds = 0x100;

// Posted to the hook thread's message-only window.
constexpr UINT kMsgInbox = WM_APP + 0x60;      // settings in the inbox
constexpr UINT kMsgReinstall = WM_APP + 0x61;  // put the hooks back
constexpr UINT kMsgQuit = WM_APP + 0x62;       // end the thread
constexpr UINT_PTR kIdleTimerId = 0x4B54;      // 5 s after the last key
constexpr UINT_PTR kHealthTimerId = 0x4B56;    // the 2 s hook check
constexpr wchar_t kHookWindowClass[] = L"KusungaTypedShortcutHook";

const EncodableValue* Find(const EncodableMap* map, const char* key) {
  if (!map) return nullptr;
  auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

int64_t NowMs() { return static_cast<int64_t>(::GetTickCount64()); }

std::string Utf8Of(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                         static_cast<int>(wide.size()), nullptr,
                                         0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                        out.data(), size, nullptr, nullptr);
  return out;
}

// The full path of a process's executable, or empty.
std::wstring ImagePathOf(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return std::wstring();
  wchar_t path[MAX_PATH] = {0};
  DWORD size = MAX_PATH;
  const BOOL ok = ::QueryFullProcessImageNameW(process, 0, path, &size);
  ::CloseHandle(process);
  return ok ? std::wstring(path, size) : std::wstring();
}

// "C:\...\1Password.exe" -> "1password.exe" (the app id, lower case).
std::string AppIdOf(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  std::wstring name = slash == std::wstring::npos ? path : path.substr(slash + 1);
  std::transform(name.begin(), name.end(), name.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
  return Utf8Of(name);
}

// The integrity level (RID) of a process, or 0 if it cannot be read. As in
// picker_bridge.cpp: "access denied" means a higher (administrator) level.
uint32_t IntegrityOfProcess(HANDLE process) {
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

uint32_t IntegrityOfPid(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) {
    return ::GetLastError() == ERROR_ACCESS_DENIED ? kusunga::kHighRid : 0;
  }
  const uint32_t level = IntegrityOfProcess(process);
  ::CloseHandle(process);
  return level;
}

// The window belongs to an administrator app, or its level can't be read
// (rule 5). Our hooks are not called for keys typed there either.
bool IsElevatedWindow(HWND window) {
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  return kusunga::DecideSend(IntegrityOfProcess(::GetCurrentProcess()),
                             pid ? IntegrityOfPid(pid) : 0) !=
         kusunga::SendDecision::kSend;
}

// The name people know an app by: its file description, or the executable
// name without ".exe".
std::string DisplayNameOf(const std::wstring& path) {
  DWORD ignored = 0;
  const DWORD size = ::GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (size > 0) {
    std::vector<BYTE> data(size);
    if (::GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
      struct Translation {
        WORD language;
        WORD code_page;
      }* translations = nullptr;
      UINT length = 0;
      if (::VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                           reinterpret_cast<void**>(&translations), &length) &&
          length >= sizeof(Translation)) {
        wchar_t key[64];
        swprintf_s(key, L"\\StringFileInfo\\%04x%04x\\FileDescription",
                   translations[0].language, translations[0].code_page);
        wchar_t* value = nullptr;
        UINT value_length = 0;
        if (::VerQueryValueW(data.data(), key, reinterpret_cast<void**>(&value),
                             &value_length) &&
            value && value_length > 1) {
          return Utf8Of(std::wstring(value));
        }
      }
    }
  }
  const size_t slash = path.find_last_of(L"\\/");
  std::wstring name = slash == std::wstring::npos ? path : path.substr(slash + 1);
  if (name.size() > 4 && _wcsicmp(name.c_str() + name.size() - 4, L".exe") == 0) {
    name.resize(name.size() - 4);
  }
  return Utf8Of(name);
}

// The icon of an app as PNG bytes. Empty for now: the Windows list shows
// names only until the PM decides on icons (lead, M1.5 Q4). Kept apart so
// it can be added or left out without touching anything else.
std::vector<uint8_t> RunningAppIcon(const std::wstring& /*path*/) { return {}; }

struct WindowsOfApps {
  std::vector<std::pair<std::string, std::wstring>> apps;  // id, path
};

BOOL CALLBACK CollectWindow(HWND hwnd, LPARAM lparam) {
  auto* out = reinterpret_cast<WindowsOfApps*>(lparam);
  if (!::IsWindowVisible(hwnd) || ::GetWindow(hwnd, GW_OWNER) != nullptr) {
    return TRUE;
  }
  if (::GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) return TRUE;
  if (::GetWindowTextLengthW(hwnd) == 0) return TRUE;
  DWORD pid = 0;
  ::GetWindowThreadProcessId(hwnd, &pid);
  if (pid == 0 || pid == ::GetCurrentProcessId()) return TRUE;
  const std::wstring path = ImagePathOf(pid);
  if (path.empty()) return TRUE;
  const std::string id = AppIdOf(path);
  for (const auto& app : out->apps) {
    if (app.first == id) return TRUE;
  }
  out->apps.push_back({id, path});
  return TRUE;
}

}  // namespace

// What a replacement needs from Windows (typed_shortcut_policy.h).
class WinReplacePlatform : public kusunga::ReplacePlatform {
 public:
  explicit WinReplacePlatform(TypedShortcutBridge* bridge) : bridge_(bridge) {}

  ~WinReplacePlatform() override { Forget(); }

  uintptr_t Foreground() override {
    return reinterpret_cast<uintptr_t>(::GetForegroundWindow());
  }

  // From the pending match the hook thread counts into; none counts as
  // "something happened", so the replacement is cancelled.
  int KeysSinceMatch() override {
    return bridge_->pending_.InputsSince(bridge_->replacing_id_);
  }

  bool SavePrevious() override {
    Forget();
    if (!::OpenClipboard(bridge_->window_)) return false;
    // The formats first: a copy that is not all text is never read (C4).
    if (!kusunga::CanRestoreClipboard(ListFormats())) {
      ::CloseClipboard();
      return false;
    }
    bool found = false;
    HANDLE handle = ::GetClipboardData(CF_UNICODETEXT);
    if (handle) {
      const auto* data = static_cast<const wchar_t*>(::GlobalLock(handle));
      if (data) {
        const size_t max = ::GlobalSize(handle) / sizeof(wchar_t);
        saved_.assign(data, wcsnlen(data, max));
        ::GlobalUnlock(handle);
        found = true;
      }
    }
    ::CloseClipboard();
    has_saved_ = found;
    return found;
  }

  void SendBackspaces(int n) override {
    std::vector<INPUT> inputs(static_cast<size_t>(n) * 2);
    for (size_t i = 0; i < inputs.size(); i++) {
      inputs[i].type = INPUT_KEYBOARD;
      inputs[i].ki.wVk = VK_BACK;
      inputs[i].ki.dwFlags = (i % 2) ? KEYEVENTF_KEYUP : 0;
      inputs[i].ki.dwExtraInfo = kusunga::kOwnKeyMarker;
    }
    ::SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
  }

  bool WriteSnippet(const std::string& text, uint32_t* sequence) override {
    if (!WriteClipboardText(bridge_->window_, bridge_->format_own_, text,
                            bridge_->own_, kusunga::SnippetMarks())) {
      return false;
    }
    *sequence = ::GetClipboardSequenceNumber();
    return true;
  }

  void SendPaste() override {
    INPUT inputs[4] = {};
    for (auto& input : inputs) {
      input.type = INPUT_KEYBOARD;
      input.ki.dwExtraInfo = kusunga::kOwnKeyMarker;
    }
    inputs[0].ki.wVk = VK_CONTROL;
    inputs[1].ki.wVk = 'V';
    inputs[2].ki.wVk = 'V';
    inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
    inputs[3].ki.wVk = VK_CONTROL;
    inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
    ::SendInput(4, inputs, sizeof(INPUT));
  }

  // Same as the picker (picker_bridge.cpp).
  bool ModifiersDown() override {
    for (int vk : {VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN}) {
      if (::GetAsyncKeyState(vk) & 0x8000) return true;
    }
    return false;
  }

  int64_t NowMs() override { return ::NowMs(); }

  bool ClipboardEmpty() override { return ::CountClipboardFormats() == 0; }

  // WriteClipboardText opens the clipboard with Kusunga's window, so its
  // EmptyClipboard makes that window the owner (L3).
  bool OwnClear() override { return ::GetClipboardOwner() == bridge_->window_; }

  // A one-shot WM_TIMER on Kusunga's window; several can wait at once (a
  // restore and a modifier poll). Never sleeps.
  void Schedule(int ms, std::function<void()> work) override {
    UINT_PTR id = 0;
    for (UINT_PTR i = 0; i < kFlowTimerIds; i++) {
      const UINT_PTR candidate = kFirstFlowTimerId + (next_ + i) % kFlowTimerIds;
      if (work_.count(candidate) == 0) {
        id = candidate;
        break;
      }
    }
    if (id == 0) return;  // 256 timers waiting: cannot happen
    next_ = (id - kFirstFlowTimerId + 1) % kFlowTimerIds;
    work_[id] = std::move(work);
    ::SetTimer(bridge_->window_, id, static_cast<UINT>(std::max(ms, 1)),
               nullptr);
  }

  bool Owns(UINT_PTR id) const { return work_.count(id) > 0; }

  void RunScheduled(UINT_PTR id) {
    ::KillTimer(bridge_->window_, id);
    auto it = work_.find(id);
    if (it == work_.end()) return;
    auto work = std::move(it->second);
    work_.erase(it);
    if (work) work();
  }

  void CancelAll() {
    for (const auto& entry : work_) ::KillTimer(bridge_->window_, entry.first);
    work_.clear();
  }

  uint32_t Sequence() override { return ::GetClipboardSequenceNumber(); }

  // Always marked "don't keep", whatever marks the copy had (S1).
  void RestorePrevious() override {
    if (!has_saved_) return;
    std::string utf8 = Utf8Of(saved_);
    WriteClipboardText(bridge_->window_, bridge_->format_own_, utf8,
                       bridge_->own_, kusunga::RestoreMarks());
    std::fill(utf8.begin(), utf8.end(), ' ');
  }

  void ForgetPrevious() override { Forget(); }

 private:
  // Every format on the open clipboard, with the names of registered ones.
  static std::vector<kusunga::ClipboardFormatInfo> ListFormats() {
    std::vector<kusunga::ClipboardFormatInfo> formats;
    UINT format = 0;
    while ((format = ::EnumClipboardFormats(format)) != 0) {
      std::string name;
      if (format >= 0xC000) {
        wchar_t buffer[128] = {0};
        const int n = ::GetClipboardFormatNameW(format, buffer, 128);
        if (n > 0) name = Utf8Of(std::wstring(buffer, static_cast<size_t>(n)));
      }
      formats.push_back({static_cast<uint32_t>(format), name});
    }
    return formats;
  }

  // Overwrites the kept text before letting go of it.
  void Forget() {
    std::fill(saved_.begin(), saved_.end(), L' ');
    saved_.clear();
    has_saved_ = false;
  }

  TypedShortcutBridge* bridge_;
  std::wstring saved_;
  bool has_saved_ = false;
  std::map<UINT_PTR, std::function<void()>> work_;
  UINT_PTR next_ = 0;
};

// Rule 6 on its own persistent thread (R1): UI Automation in the
// multithreaded apartment, created once and kept. The hook thread only
// pushes a request; nobody waits for the answer. An answer later than
// 100 ms counts as "can't tell" (fail closed), so a busy or hung app can
// delay this thread but never the hooks or Kusunga's window. Only a
// passed check reaches the UI thread (kMsgMatched).
class FieldCheckWorker {
 public:
  explicit FieldCheckWorker(HWND ui_window)
      : ui_window_(ui_window), thread_([this] { Run(); }) {}

  ~FieldCheckWorker() {
    queue_.Stop();
    thread_.join();
  }

  FieldCheckWorker(const FieldCheckWorker&) = delete;
  FieldCheckWorker& operator=(const FieldCheckWorker&) = delete;

  // From the hook thread: returns at once.
  void Ask(int snippet_id, int delete_count, uint32_t match_id) {
    queue_.Push({snippet_id, delete_count, NowMs(), match_id});
  }

 private:
  void Run() {
    const bool com =
        SUCCEEDED(::CoInitializeEx(nullptr, COINIT_MULTITHREADED));
    IUIAutomation* automation = nullptr;
    if (com &&
        SUCCEEDED(::CoCreateInstance(__uuidof(CUIAutomation), nullptr,
                                     CLSCTX_INPROC_SERVER,
                                     __uuidof(IUIAutomation),
                                     reinterpret_cast<void**>(&automation))) &&
        automation) {
      // A hung app must not keep this thread for UI Automation's default
      // 20 s: give up after 1 s (the answer is late and refused anyway).
      IUIAutomation2* timeouts = nullptr;
      if (SUCCEEDED(automation->QueryInterface(
              __uuidof(IUIAutomation2), reinterpret_cast<void**>(&timeouts))) &&
          timeouts) {
        timeouts->put_ConnectionTimeout(1000);
        timeouts->put_TransactionTimeout(1000);
        timeouts->Release();
      }
    }
    kusunga::FieldCheckRequest request{0, 0, 0, 0};
    while (queue_.Pop(&request)) {
      const kusunga::FieldState state = kusunga::FieldStateInTime(
          automation ? FocusedFieldState(automation)
                     : kusunga::FieldState::kUnknown,
          request.asked_ms, NowMs());
      // A password field, or one that can't be read in time, never gets a
      // snippet.
      if (kusunga::DecideField(state) == nullptr) {
        ::PostMessageW(ui_window_, kMsgMatched,
                       static_cast<WPARAM>(request.snippet_id),
                       static_cast<LPARAM>(kusunga::PackMatch(
                           request.delete_count, request.match_id)));
      }
    }
    if (automation) automation->Release();
    if (com) ::CoUninitialize();
  }

  static kusunga::FieldState FocusedFieldState(IUIAutomation* automation) {
    kusunga::FieldState state = kusunga::FieldState::kUnknown;
    IUIAutomationElement* element = nullptr;
    if (SUCCEEDED(automation->GetFocusedElement(&element)) && element) {
      BOOL is_password = FALSE;
      if (SUCCEEDED(element->get_CurrentIsPassword(&is_password))) {
        state = is_password ? kusunga::FieldState::kPassword
                            : kusunga::FieldState::kNormal;
      }
      element->Release();
    }
    return state;
  }

  HWND ui_window_;
  kusunga::FieldCheckQueue queue_;
  std::thread thread_;  // last, so the queue exists before it runs
};

// The hook thread (R1): WH_KEYBOARD_LL and WH_MOUSE_LL installed from here,
// so Windows calls them here, and this thread does nothing else. It owns
// the matcher, the front-window state and the ignore set; the UI thread
// reaches them only through the inbox (settings) and the pending match.
class HookThread;
HookThread* g_hook_thread = nullptr;  // set and read on the hook thread only

class HookThread {
 public:
  HookThread(HWND ui_window, kusunga::HookInbox* inbox,
             kusunga::PendingMatch* pending, FieldCheckWorker* field)
      : ui_window_(ui_window), inbox_(inbox), pending_(pending), field_(field) {}

  ~HookThread() { Stop(); }

  HookThread(const HookThread&) = delete;
  HookThread& operator=(const HookThread&) = delete;

  // Starts the thread and waits for its hooks. False if they could not be
  // installed (the thread has ended then).
  bool Start() {
    std::promise<bool> installed;
    std::future<bool> result = installed.get_future();
    thread_ = std::thread([this, &installed] { Run(&installed); });
    if (result.get()) return true;
    thread_.join();
    return false;
  }

  void Stop() {
    if (!thread_.joinable()) return;
    if (!hook_window_ || !::PostMessageW(hook_window_, kMsgQuit, 0, 0)) {
      ::PostThreadMessageW(thread_id_, WM_QUIT, 0, 0);
    }
    thread_.join();
    hook_window_ = nullptr;
  }

  // New settings are in the inbox.
  void Wake() {
    if (hook_window_) ::PostMessageW(hook_window_, kMsgInbox, 0, 0);
  }

  // Kusunga's window was activated: put the hooks back in any case.
  void Reinstall() {
    if (hook_window_) ::PostMessageW(hook_window_, kMsgReinstall, 0, 0);
  }

 private:
  void Run(std::promise<bool>* installed) {
    g_hook_thread = this;
    thread_id_ = ::GetCurrentThreadId();
    HINSTANCE instance = ::GetModuleHandleW(nullptr);
    WNDCLASSEXW window_class = {};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = WindowProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kHookWindowClass;
    ::RegisterClassExW(&window_class);  // fails harmlessly the second time
    HWND window = ::CreateWindowExW(0, kHookWindowClass, L"", 0, 0, 0, 0, 0,
                                    HWND_MESSAGE, nullptr, instance, nullptr);
    const bool ok = window != nullptr && Install();
    if (ok) {
      hook_window_ = window;
      ApplyInbox();
      ::SetTimer(window, kHealthTimerId, kusunga::kHookCheckMs, nullptr);
    }
    // After this the promise belongs to Start again; don't touch it.
    installed->set_value(ok);
    if (ok) {
      MSG message;
      while (::GetMessageW(&message, nullptr, 0, 0) > 0) {
        ::DispatchMessageW(&message);
      }
    } else if (window) {
      ::DestroyWindow(window);
    }
    Uninstall();
    matcher_.Reset();
    g_hook_thread = nullptr;
  }

  bool Install() {
    HINSTANCE instance = ::GetModuleHandleW(nullptr);
    keyboard_hook_ =
        ::SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardProc, instance, 0);
    mouse_hook_ = ::SetWindowsHookExW(WH_MOUSE_LL, MouseProc, instance, 0);
    last_hook_tick_ = ::GetTickCount();
    if (keyboard_hook_ && mouse_hook_) return true;
    Uninstall();
    return false;
  }

  void Uninstall() {
    if (keyboard_hook_) ::UnhookWindowsHookEx(keyboard_hook_);
    if (mouse_hook_) ::UnhookWindowsHookEx(mouse_hook_);
    keyboard_hook_ = nullptr;
    mouse_hook_ = nullptr;
  }

  bool Reinstalled() {
    Uninstall();
    matcher_.Reset();
    foreground_ = nullptr;
    return Install();
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    HookThread* self = g_hook_thread;
    if (self) {
      switch (message) {
        case kMsgInbox:
          self->ApplyInbox();
          return 0;
        case kMsgReinstall: {
          const bool ok = self->Reinstalled();
          ::PostMessageW(self->ui_window_, kMsgHookState, ok ? 1 : 0, 0);
          return 0;
        }
        case kMsgQuit:
          ::DestroyWindow(window);
          return 0;
        case WM_TIMER:
          if (wparam == kIdleTimerId) {
            self->matcher_.Tick(NowMs());
            self->ArmIdleTimer();  // fired a little early: set again
          } else if (wparam == kHealthTimerId) {
            self->CheckHealth();
          }
          return 0;
        case WM_DESTROY:
          ::PostQuitMessage(0);
          return 0;
        default:
          break;
      }
    }
    return ::DefWindowProcW(window, message, wparam, lparam);
  }

  static LRESULT CALLBACK KeyboardProc(int code, WPARAM wparam,
                                       LPARAM lparam) {
    HookThread* self = g_hook_thread;
    if (code == HC_ACTION && self) {
      self->last_hook_tick_ = ::GetTickCount();
      if (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN) {
        self->OnKey(*reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam));
      }
    }
    return ::CallNextHookEx(nullptr, code, wparam, lparam);
  }

  static LRESULT CALLBACK MouseProc(int code, WPARAM wparam, LPARAM lparam) {
    HookThread* self = g_hook_thread;
    if (code == HC_ACTION && self) {
      self->last_hook_tick_ = ::GetTickCount();
      switch (wparam) {
        case WM_LBUTTONDOWN:
        case WM_RBUTTONDOWN:
        case WM_MBUTTONDOWN:
        case WM_XBUTTONDOWN:
          // Also cancels a match still waiting for its replacement (C5).
          kusunga::OnMouseDown(self->matcher_, *self->pending_);
          break;
        default:
          break;
      }
    }
    return ::CallNextHookEx(nullptr, code, wparam, lparam);
  }

  // A one-shot timer exactly 5 s after the last key, on this thread (C9);
  // none when there is nothing to clear. SetTimer with the same id moves it.
  void ArmIdleTimer() {
    int64_t ms = 0;
    if (!hook_window_) return;
    if (!matcher_.MsUntilIdleClear(NowMs(), &ms)) {
      ::KillTimer(hook_window_, kIdleTimerId);
      return;
    }
    ::SetTimer(hook_window_, kIdleTimerId,
               static_cast<UINT>(std::max<int64_t>(ms, 10)), nullptr);
  }

  // Settings from the UI thread, applied here only.
  void ApplyInbox() {
    kusunga::HookInbox::Batch batch = inbox_->Take();
    if (batch.has_table) matcher_.SetTable(batch.table);
    if (batch.has_ignored) {
      ignored_ = std::move(batch.ignored);
      foreground_ = nullptr;  // looked up again on the next key
      matcher_.Reset();
    }
    if (batch.reset) matcher_.Reset();
  }

  // Windows removed the hooks (they were too slow, or the system was under
  // load): put them back once; if that fails, the UI says "stopped".
  void CheckHealth() {
    LASTINPUTINFO info = {};
    info.cbSize = sizeof(info);
    if (!::GetLastInputInfo(&info)) return;
    HWND front = ::GetForegroundWindow();
    const bool hidden = front == nullptr || IsElevatedWindow(front);
    if (!kusunga::HookLooksRemoved(info.dwTime, last_hook_tick_, hidden)) {
      return;
    }
    if (!Reinstalled()) ::PostMessageW(ui_window_, kMsgHookLost, 0, 0);
  }

  void UpdateForeground(HWND foreground) {
    if (foreground == foreground_) return;
    // A new front window: the cursor is somewhere else.
    foreground_ = foreground;
    matcher_.Reset();
    DWORD pid = 0;
    ::GetWindowThreadProcessId(foreground, &pid);
    foreground_self_ = pid == ::GetCurrentProcessId();
    const std::wstring path = pid ? ImagePathOf(pid) : std::wstring();
    foreground_ignored_ = !path.empty() && ignored_.count(AppIdOf(path)) > 0;
    foreground_elevated_ = IsElevatedWindow(foreground);
  }

  void OnKey(const KBDLLHOOKSTRUCT& key) {
    // Kusunga's own Backspaces and Ctrl+V.
    if (kusunga::IsOwnKey(key.dwExtraInfo)) return;
    // A held modifier repeats; it moves nothing, so it does not cancel a
    // replacement waiting for it to be released (C1).
    if (!kusunga::IsModifierKey(key.vkCode)) pending_->NoteInput();
    HWND foreground = ::GetForegroundWindow();
    UpdateForeground(foreground);

    kusunga::KeyFlags flags;
    flags.ctrl = (::GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
    flags.alt = (key.flags & LLKHF_ALTDOWN) != 0 ||
                (::GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
    flags.right_alt = (::GetAsyncKeyState(VK_RMENU) & 0x8000) != 0;
    flags.win = ((::GetAsyncKeyState(VK_LWIN) | ::GetAsyncKeyState(VK_RWIN)) &
                 0x8000) != 0;

    // The characters this key types in the front window's layout. Flag 0x4
    // keeps ToUnicodeEx from changing the keyboard state (dead keys).
    BYTE state[256] = {0};
    for (int vk : {VK_SHIFT, VK_CONTROL, VK_MENU, VK_RMENU, VK_LCONTROL,
                   VK_RCONTROL, VK_LSHIFT, VK_RSHIFT, VK_LMENU}) {
      if (::GetAsyncKeyState(vk) & 0x8000) state[vk] = 0x80;
    }
    if (::GetKeyState(VK_CAPITAL) & 0x1) state[VK_CAPITAL] = 0x1;
    const HKL layout =
        ::GetKeyboardLayout(::GetWindowThreadProcessId(foreground, nullptr));
    wchar_t units[8] = {0};
    const int n = ::ToUnicodeEx(key.vkCode, key.scanCode, state, units, 8, 0x4,
                                layout);
    std::u16string typed;
    for (int i = 0; i < n; i++) typed.push_back(static_cast<char16_t>(units[i]));
    std::fill(std::begin(units), std::end(units), L'\0');
    const kusunga::TypedKey typed_key = kusunga::ClassifyWindowsKey(
        key.vkCode, flags,
        n > 0 ? kusunga::Utf16ToUtf32(typed) : std::u32string());
    std::fill(typed.begin(), typed.end(), u' ');

    kusunga::TypedKeyContext context;
    context.front_is_self = foreground_self_;
    context.front_ignored = foreground_ignored_;
    context.injected = (key.flags & LLKHF_INJECTED) != 0;
    context.front_elevated = foreground_elevated_;
    const kusunga::TypedOutcome outcome =
        matcher_.Handle(typed_key, context, NowMs());
    ArmIdleTimer();
    if (outcome.kind == kusunga::TypedOutcome::Kind::kMatched) {
      // The field check and the channel call happen on other threads; this
      // returns at once.
      const uint32_t match_id =
          pending_->Begin(reinterpret_cast<uintptr_t>(foreground));
      field_->Ask(outcome.snippet_id, outcome.delete_count, match_id);
    }
  }

  HWND ui_window_;
  kusunga::HookInbox* inbox_;
  kusunga::PendingMatch* pending_;
  FieldCheckWorker* field_;
  std::thread thread_;
  DWORD thread_id_ = 0;
  HWND hook_window_ = nullptr;  // set before Start returns

  // The hook thread's own state.
  kusunga::TypedShortcutMatcher matcher_;
  std::set<std::string> ignored_;
  HHOOK keyboard_hook_ = nullptr;
  HHOOK mouse_hook_ = nullptr;
  DWORD last_hook_tick_ = 0;
  HWND foreground_ = nullptr;
  bool foreground_ignored_ = false;
  bool foreground_self_ = false;
  bool foreground_elevated_ = false;
};

TypedShortcutBridge::TypedShortcutBridge(flutter::BinaryMessenger* messenger,
                                         HWND window,
                                         kusunga::OwnClipboardChanges* own)
    : window_(window), own_(own) {
  format_own_ = ::RegisterClipboardFormatW(L"com.wnasoni.kusunga.self");
  replace_platform_ = std::make_unique<WinReplacePlatform>(this);
  replace_flow_ = std::make_unique<kusunga::ReplaceFlow>(replace_platform_.get());
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kShortcutsChannel, &codec);
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleCall(call, std::move(result));
      });
}

TypedShortcutBridge::~TypedShortcutBridge() {
  Stop("off");
  field_worker_ = nullptr;  // after the hook thread, which asks it
  replace_platform_->CancelAll();
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void TypedShortcutBridge::HandleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const std::string& method = call.method_name();
  if (method == "setTable") {
    std::vector<std::pair<int, std::string>> entries;
    const auto* list = Find(args, "entries");
    if (list && std::holds_alternative<EncodableList>(*list)) {
      for (const auto& row : std::get<EncodableList>(*list)) {
        const auto* map = std::get_if<EncodableMap>(&row);
        const auto* id = Find(map, "id");
        const auto* shortcut = Find(map, "shortcut");
        if (!id || !shortcut || !std::holds_alternative<std::string>(*shortcut)) {
          continue;
        }
        int value = 0;
        if (std::holds_alternative<int32_t>(*id)) {
          value = std::get<int32_t>(*id);
        } else if (std::holds_alternative<int64_t>(*id)) {
          value = static_cast<int>(std::get<int64_t>(*id));
        } else {
          continue;
        }
        entries.push_back({value, std::get<std::string>(*shortcut)});
      }
    }
    // Applied on the hook thread (now, or when it starts).
    inbox_.PutTable(std::move(entries));
    if (hook_thread_) hook_thread_->Wake();
    result->Success();
  } else if (method == "setIgnored") {
    std::set<std::string> ignored;
    const auto* list = Find(args, "appIds");
    if (list && std::holds_alternative<EncodableList>(*list)) {
      for (const auto& id : std::get<EncodableList>(*list)) {
        if (const auto* s = std::get_if<std::string>(&id)) ignored.insert(*s);
      }
    }
    inbox_.PutIgnored(std::move(ignored));
    if (hook_thread_) hook_thread_->Wake();
    result->Success();
  } else if (method == "setEnabled") {
    const auto* on = Find(args, "on");
    enabled_ = on && std::holds_alternative<bool>(*on) && std::get<bool>(*on);
    if (enabled_) {
      Start();
    } else {
      Stop("off");
    }
    result->Success(EncodableValue(status_));
  } else if (method == "status") {
    result->Success(EncodableValue(status_));
  } else if (method == "replace") {
    const auto* match = Find(args, "matchId");
    const auto* count = Find(args, "deleteCount");
    const auto* text = Find(args, "text");
    int64_t match_id = 0;
    if (match && std::holds_alternative<int32_t>(*match)) {
      match_id = std::get<int32_t>(*match);
    } else if (match && std::holds_alternative<int64_t>(*match)) {
      match_id = std::get<int64_t>(*match);
    }
    if (match_id < 1 || match_id > kusunga::kMaxMatchId || !count ||
        !std::holds_alternative<int32_t>(*count) || !text ||
        !std::holds_alternative<std::string>(*text)) {
      result->Success(EncodableValue("failed"));
      return;
    }
    const int n = std::get<int32_t>(*count);
    if (n < 1 || n > static_cast<int>(kusunga::TypedBuffer::kMaxLength)) {
      result->Success(EncodableValue("failed"));
      return;
    }
    // Answered now, or after the modifiers are released (C1).
    std::shared_ptr<flutter::MethodResult<EncodableValue>> reply(
        std::move(result));
    Replace(static_cast<uint32_t>(match_id), n, std::get<std::string>(*text),
            [reply](const char* answer) {
              reply->Success(EncodableValue(answer));
            });
  } else if (method == "runningApps") {
    WindowsOfApps found;
    ::EnumWindows(CollectWindow, reinterpret_cast<LPARAM>(&found));
    EncodableList apps;
    for (const auto& [id, path] : found.apps) {
      EncodableMap row;
      row[EncodableValue("appId")] = EncodableValue(id);
      row[EncodableValue("name")] = EncodableValue(DisplayNameOf(path));
      const std::vector<uint8_t> icon = RunningAppIcon(path);
      row[EncodableValue("icon")] =
          icon.empty() ? EncodableValue() : EncodableValue(icon);
      apps.push_back(EncodableValue(row));
    }
    result->Success(EncodableValue(apps));
  } else if (method == "requestListenAccess") {
    result->Success(EncodableValue(true));  // Windows asks for no permission
  } else if (method == "openInputMonitoringSettings") {
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void TypedShortcutBridge::SetStatus(const char* status) {
  if (status_ == status) return;
  status_ = status;
  EncodableMap args;
  args[EncodableValue("status")] = EncodableValue(status_);
  channel_->InvokeMethod("statusChanged",
                         std::make_unique<EncodableValue>(args));
}

void TypedShortcutBridge::Start() {
  if (hook_thread_) {
    SetStatus("on");
    return;
  }
  if (!field_worker_) field_worker_ = std::make_unique<FieldCheckWorker>(window_);
  auto thread = std::make_unique<HookThread>(window_, &inbox_, &pending_,
                                             field_worker_.get());
  if (!thread->Start()) {
    Stop("failed");
    return;
  }
  hook_thread_ = std::move(thread);
  SetStatus("on");
}

void TypedShortcutBridge::Stop(const char* status) {
  if (hook_thread_) {
    hook_thread_->Stop();
    hook_thread_ = nullptr;
  }
  pending_.Clear();
  SetStatus(status);
}

void TypedShortcutBridge::OnMatched(int snippet_id, int delete_count,
                                    uint32_t match_id) {
  // A newer match came meanwhile: Dart hears only about that one.
  if (!enabled_ || !pending_.Get(match_id, nullptr, nullptr)) return;
  EncodableMap args;
  args[EncodableValue("snippetId")] = EncodableValue(snippet_id);
  args[EncodableValue("deleteCount")] = EncodableValue(delete_count);
  args[EncodableValue("matchId")] =
      EncodableValue(static_cast<int64_t>(match_id));
  channel_->InvokeMethod("matched", std::make_unique<EncodableValue>(args));
}

void TypedShortcutBridge::Replace(uint32_t match_id, int delete_count,
                                  const std::string& text,
                                  std::function<void(const char*)> answer) {
  // An older or unknown match: cancelled, and nothing else changes (C2).
  // One at a time: another one still waiting for the modifiers wins.
  if (!enabled_ || replacing_id_ != 0 ||
      !pending_.Get(match_id, nullptr, nullptr)) {
    answer("cancelled");
    return;
  }
  replacing_id_ = match_id;
  kusunga::StartReplaceMatch(
      *replace_flow_, pending_, match_id, delete_count, text,
      [this, answer = std::move(answer)](kusunga::ReplaceResult result) {
        replacing_id_ = 0;
        // A replacement is a reset event; the hook thread empties its
        // buffer.
        inbox_.PutReset();
        if (hook_thread_) hook_thread_->Wake();
        answer(kusunga::ReplaceResultName(result));
      });
}

std::optional<LRESULT> TypedShortcutBridge::HandleMessage(UINT message,
                                                          WPARAM wparam,
                                                          LPARAM lparam) {
  switch (message) {
    case kMsgMatched: {
      int delete_count = 0;
      uint32_t match_id = 0;
      kusunga::UnpackMatch(static_cast<int64_t>(lparam), &delete_count,
                           &match_id);
      OnMatched(static_cast<int>(wparam), delete_count, match_id);
      return 0;
    }
    case kMsgHookLost:
      // Windows removed the hooks and they could not be put back.
      if (enabled_ && hook_thread_) Stop("stopped");
      return 0;
    case kMsgHookState:
      if (enabled_ && hook_thread_) {
        if (wparam) {
          SetStatus("on");
        } else {
          Stop("stopped");
        }
      }
      return 0;
    case WM_ACTIVATE:
      // Back in Kusunga: put the hooks back (Windows may have removed them
      // silently), or try to start again after "stopped" or "failed". Not
      // handled here, so the window still gets it.
      if (LOWORD(wparam) != WA_INACTIVE && enabled_) {
        if (hook_thread_) {
          hook_thread_->Reinstall();
        } else {
          Start();
        }
      }
      return std::nullopt;
    case WM_TIMER:
      if (replace_platform_->Owns(static_cast<UINT_PTR>(wparam))) {
        replace_platform_->RunScheduled(static_cast<UINT_PTR>(wparam));
        return 0;
      }
      return std::nullopt;
    default:
      return std::nullopt;
  }
}
