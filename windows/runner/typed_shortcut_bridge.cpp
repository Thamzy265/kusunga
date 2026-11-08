#include "typed_shortcut_bridge.h"

#include <flutter/standard_method_codec.h>
#include <uiautomation.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <functional>
#include <future>
#include <iterator>
#include <memory>
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
constexpr UINT kMsgMatched = WM_APP + 0x51;
constexpr UINT_PTR kIdleTimerId = 0x4B54;     // the 1 s idle clear
constexpr UINT_PTR kRestoreTimerId = 0x4B55;  // the 0.5 s restore (D2)

TypedShortcutBridge* g_bridge = nullptr;

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

// Rule 6: is the focused element a password field? UI Automation is asked
// on its own thread and given 100 ms; no answer in time is "can't tell",
// which means don't fire. Called only after a match, never on every key.
kusunga::FieldState FocusedFieldState() {
  auto promise = std::make_shared<std::promise<kusunga::FieldState>>();
  auto answer = promise->get_future();
  std::thread([promise] {
    kusunga::FieldState state = kusunga::FieldState::kUnknown;
    if (SUCCEEDED(::CoInitializeEx(nullptr, COINIT_MULTITHREADED))) {
      IUIAutomation* automation = nullptr;
      if (SUCCEEDED(::CoCreateInstance(__uuidof(CUIAutomation), nullptr,
                                       CLSCTX_INPROC_SERVER,
                                       __uuidof(IUIAutomation),
                                       reinterpret_cast<void**>(&automation))) &&
          automation) {
        IUIAutomationElement* element = nullptr;
        if (SUCCEEDED(automation->GetFocusedElement(&element)) && element) {
          BOOL is_password = FALSE;
          if (SUCCEEDED(element->get_CurrentIsPassword(&is_password))) {
            state = is_password ? kusunga::FieldState::kPassword
                                : kusunga::FieldState::kNormal;
          }
          element->Release();
        }
        automation->Release();
      }
      ::CoUninitialize();
    }
    promise->set_value(state);
  }).detach();
  if (answer.wait_for(std::chrono::milliseconds(kusunga::kFieldCheckLimitMs)) !=
      std::future_status::ready) {
    return kusunga::FieldState::kUnknown;
  }
  return answer.get();
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

  int KeysSinceMatch() override { return bridge_->keys_since_match_; }

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

  void Schedule(int ms, std::function<void()> work) override {
    work_ = std::move(work);
    ::SetTimer(bridge_->window_, kRestoreTimerId, static_cast<UINT>(ms),
               nullptr);
  }

  void RunScheduled() {
    ::KillTimer(bridge_->window_, kRestoreTimerId);
    auto work = std::move(work_);
    work_ = nullptr;
    if (work) work();
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
  std::function<void()> work_;
};

TypedShortcutBridge::TypedShortcutBridge(flutter::BinaryMessenger* messenger,
                                         HWND window,
                                         kusunga::OwnClipboardChanges* own)
    : window_(window), own_(own) {
  g_bridge = this;
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
  ::KillTimer(window_, kRestoreTimerId);
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  if (g_bridge == this) g_bridge = nullptr;
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
    matcher_.SetTable(entries);
    result->Success();
  } else if (method == "setIgnored") {
    ignored_.clear();
    const auto* list = Find(args, "appIds");
    if (list && std::holds_alternative<EncodableList>(*list)) {
      for (const auto& id : std::get<EncodableList>(*list)) {
        if (const auto* s = std::get_if<std::string>(&id)) ignored_.insert(*s);
      }
    }
    foreground_ = nullptr;  // looked up again on the next key
    matcher_.Reset();
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
    const auto* count = Find(args, "deleteCount");
    const auto* text = Find(args, "text");
    if (!count || !std::holds_alternative<int32_t>(*count) || !text ||
        !std::holds_alternative<std::string>(*text)) {
      result->Success(EncodableValue("failed"));
      return;
    }
    const int n = std::get<int32_t>(*count);
    if (n < 1 || n > static_cast<int>(kusunga::TypedBuffer::kMaxLength)) {
      result->Success(EncodableValue("failed"));
      return;
    }
    result->Success(EncodableValue(Replace(n, std::get<std::string>(*text))));
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
  if (keyboard_hook_) {
    SetStatus("on");
    return;
  }
  HINSTANCE instance = ::GetModuleHandleW(nullptr);
  keyboard_hook_ =
      ::SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardProc, instance, 0);
  mouse_hook_ = ::SetWindowsHookExW(WH_MOUSE_LL, MouseProc, instance, 0);
  if (!keyboard_hook_ || !mouse_hook_) {
    Stop("failed");
    return;
  }
  foreground_ = nullptr;
  ::SetTimer(window_, kIdleTimerId, 1000, nullptr);
  SetStatus("on");
}

void TypedShortcutBridge::Stop(const char* status) {
  if (keyboard_hook_) ::UnhookWindowsHookEx(keyboard_hook_);
  if (mouse_hook_) ::UnhookWindowsHookEx(mouse_hook_);
  keyboard_hook_ = nullptr;
  mouse_hook_ = nullptr;
  ::KillTimer(window_, kIdleTimerId);
  matcher_.Reset();
  has_match_ = false;
  SetStatus(status);
}

LRESULT CALLBACK TypedShortcutBridge::KeyboardProc(int code, WPARAM wparam,
                                                   LPARAM lparam) {
  if (code == HC_ACTION && g_bridge &&
      (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN)) {
    g_bridge->OnKey(*reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam));
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
}

LRESULT CALLBACK TypedShortcutBridge::MouseProc(int code, WPARAM wparam,
                                                LPARAM lparam) {
  if (code == HC_ACTION && g_bridge) {
    switch (wparam) {
      case WM_LBUTTONDOWN:
      case WM_RBUTTONDOWN:
      case WM_MBUTTONDOWN:
      case WM_XBUTTONDOWN:
        g_bridge->matcher_.Reset();
        break;
      default:
        break;
    }
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
}

void TypedShortcutBridge::UpdateForeground(HWND foreground) {
  if (foreground == foreground_) return;
  // A new front window: the cursor is somewhere else.
  foreground_ = foreground;
  matcher_.Reset();
  DWORD pid = 0;
  ::GetWindowThreadProcessId(foreground, &pid);
  foreground_self_ = pid == ::GetCurrentProcessId();
  const std::wstring path = pid ? ImagePathOf(pid) : std::wstring();
  foreground_ignored_ = !path.empty() && ignored_.count(AppIdOf(path)) > 0;
  // An administrator window, or one whose level can't be read (rule 5).
  foreground_elevated_ =
      kusunga::DecideSend(IntegrityOfProcess(::GetCurrentProcess()),
                          pid ? IntegrityOfPid(pid) : 0) !=
      kusunga::SendDecision::kSend;
}

void TypedShortcutBridge::OnKey(const KBDLLHOOKSTRUCT& key) {
  // Kusunga's own Backspaces and Ctrl+V.
  if (kusunga::IsOwnKey(key.dwExtraInfo)) return;
  if (has_match_) keys_since_match_++;
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
      key.vkCode, flags, n > 0 ? kusunga::Utf16ToUtf32(typed) : std::u32string());
  std::fill(typed.begin(), typed.end(), u' ');

  kusunga::TypedKeyContext context;
  context.front_is_self = foreground_self_;
  context.front_ignored = foreground_ignored_;
  context.injected = (key.flags & LLKHF_INJECTED) != 0;
  context.front_elevated = foreground_elevated_;
  const kusunga::TypedOutcome outcome =
      matcher_.Handle(typed_key, context, NowMs());
  if (outcome.kind == kusunga::TypedOutcome::Kind::kMatched) {
    // The field check and the channel call happen off the hook, which must
    // answer fast or Windows removes it.
    match_window_ = foreground;
    has_match_ = true;
    keys_since_match_ = 0;
    ::PostMessageW(window_, kMsgMatched,
                   static_cast<WPARAM>(outcome.snippet_id),
                   static_cast<LPARAM>(outcome.delete_count));
  }
}

void TypedShortcutBridge::OnMatched(int snippet_id, int delete_count) {
  if (!enabled_ || !has_match_) return;
  // Rule 6: a password field, or one that can't be read, never gets a
  // snippet.
  if (kusunga::DecideField(FocusedFieldState()) != nullptr) {
    has_match_ = false;
    return;
  }
  EncodableMap args;
  args[EncodableValue("snippetId")] = EncodableValue(snippet_id);
  args[EncodableValue("deleteCount")] = EncodableValue(delete_count);
  channel_->InvokeMethod("matched", std::make_unique<EncodableValue>(args));
}

std::string TypedShortcutBridge::Replace(int delete_count,
                                         const std::string& text) {
  const bool had_match = has_match_;
  const HWND window = match_window_;
  std::string answer = "cancelled";
  if (enabled_ && had_match) {
    answer = kusunga::ReplaceResultName(replace_flow_->Run(
        delete_count, text, reinterpret_cast<uintptr_t>(window)));
  }
  has_match_ = false;
  keys_since_match_ = 0;
  matcher_.Reset();
  return answer;
}

std::optional<LRESULT> TypedShortcutBridge::HandleMessage(UINT message,
                                                          WPARAM wparam,
                                                          LPARAM lparam) {
  if (message == kMsgMatched) {
    OnMatched(static_cast<int>(wparam), static_cast<int>(lparam));
    return 0;
  }
  if (message == WM_TIMER && wparam == kIdleTimerId) {
    matcher_.Tick(NowMs());
    return 0;
  }
  if (message == WM_TIMER && wparam == kRestoreTimerId) {
    replace_platform_->RunScheduled();
    return 0;
  }
  return std::nullopt;
}
