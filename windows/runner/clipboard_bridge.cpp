#include "clipboard_bridge.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <cstring>
#include <memory>
#include <string>

#include "clipboard_policy.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kEventsChannel[] =
    "com.wnasoni.kusunga/clipboard/events";
constexpr char kClipboardChannel[] = "com.wnasoni.kusunga/clipboard";
constexpr char kLifecycleChannel[] = "com.wnasoni.kusunga/lifecycle";

// How long to wait for Dart to close the database when Windows ends the
// session.
constexpr DWORD kFlushTimeoutMs = 3000;

std::string ToUtf8(const wchar_t* text, size_t length) {
  if (length == 0) return std::string();
  int size = ::WideCharToMultiByte(CP_UTF8, 0, text, static_cast<int>(length),
                                   nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text, static_cast<int>(length), out.data(),
                        size, nullptr, nullptr);
  return out;
}

EncodableMap Event(const char* type) {
  EncodableMap map;
  map[EncodableValue("type")] = EncodableValue(type);
  return map;
}

// Closes the clipboard when it goes out of scope.
struct OpenClipboardGuard {
  ~OpenClipboardGuard() { ::CloseClipboard(); }
};

// Reads the DWORD of a format such as CanIncludeInClipboardHistory.
bool ReadDword(UINT format, uint32_t* value) {
  HANDLE handle = ::GetClipboardData(format);
  if (!handle) return false;
  if (::GlobalSize(handle) < sizeof(uint32_t)) return false;
  void* data = ::GlobalLock(handle);
  if (!data) return false;
  std::memcpy(value, data, sizeof(uint32_t));
  ::GlobalUnlock(handle);
  return true;
}

}  // namespace

ClipboardBridge::ClipboardBridge(flutter::BinaryMessenger* messenger,
                                 HWND window)
    : window_(window) {
  format_exclude_ =
      ::RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
  format_can_include_ = ::RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
  format_viewer_ignore_ = ::RegisterClipboardFormatW(L"Clipboard Viewer Ignore");

  const auto& codec = flutter::StandardMethodCodec::GetInstance();

  events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger, kEventsChannel, &codec);
  events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            Start(std::move(sink));
            return nullptr;
          },
          [this](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            Stop();
            return nullptr;
          }));

  clipboard_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kClipboardChannel, &codec);
  clipboard_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "accessBehavior") {
          result->Success(EncodableValue("unsupported"));
        } else {
          result->NotImplemented();
        }
      });

  lifecycle_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kLifecycleChannel, &codec);
  lifecycle_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "quit") {
          // Dart has already flushed. End the message loop in main.cpp.
          result->Success();
          ::PostQuitMessage(0);
        } else {
          result->NotImplemented();
        }
      });
}

ClipboardBridge::~ClipboardBridge() { Stop(); }

void ClipboardBridge::Start(
    std::unique_ptr<flutter::EventSink<EncodableValue>> sink) {
  sink_ = std::move(sink);
  if (listening_) return;
  // What is on the clipboard now was copied before we started: remember its
  // sequence number so the first WM_CLIPBOARDUPDATE is not read.
  last_sequence_ = ::GetClipboardSequenceNumber();
  listening_ = ::AddClipboardFormatListener(window_) != FALSE;
  if (!listening_) {
    Emit([] {
      auto e = Event("error");
      e[EncodableValue("code")] = EncodableValue("listener");
      return e;
    }());
  }
}

void ClipboardBridge::Stop() {
  if (listening_) {
    ::RemoveClipboardFormatListener(window_);
    listening_ = false;
  }
  sink_.reset();
}

void ClipboardBridge::Emit(EncodableMap event) {
  if (sink_) sink_->Success(EncodableValue(std::move(event)));
}

void ClipboardBridge::OnClipboardUpdate() {
  const uint32_t sequence = ::GetClipboardSequenceNumber();
  if (!kusunga::IsNewCopy(last_sequence_, sequence)) return;
  last_sequence_ = sequence;

  // Another app may hold the clipboard open: retry, then skip this copy.
  const bool opened = kusunga::OpenWithRetry(
      [this] { return ::OpenClipboard(window_) != FALSE; },
      [](int ms) { ::Sleep(static_cast<DWORD>(ms)); });
  if (!opened) {
    auto e = Event("error");
    e[EncodableValue("code")] = EncodableValue("locked");
    Emit(std::move(e));
    return;
  }
  OpenClipboardGuard guard;

  // Check the "do not save this" formats BEFORE reading any text.
  kusunga::ClipboardFlags flags{};
  flags.exclude_from_monitor =
      ::IsClipboardFormatAvailable(format_exclude_) != FALSE;
  flags.viewer_ignore =
      ::IsClipboardFormatAvailable(format_viewer_ignore_) != FALSE;
  if (::IsClipboardFormatAvailable(format_can_include_)) {
    // Present but unreadable counts as secret (fail closed).
    flags.has_can_include = true;
    flags.can_include_unreadable =
        !ReadDword(format_can_include_, &flags.can_include_value);
  }
  if (kusunga::IsSecret(flags)) {
    Emit(Event("concealed"));
    return;
  }

  if (!::IsClipboardFormatAvailable(CF_UNICODETEXT)) return;
  HANDLE handle = ::GetClipboardData(CF_UNICODETEXT);
  if (!handle) return;

  // Size first: a 500 MB copy is never read into memory.
  switch (kusunga::CheckSize(::GlobalSize(handle))) {
    case kusunga::SizeCheck::kEmpty:
      return;
    case kusunga::SizeCheck::kTooLarge:
      Emit(Event("tooLarge"));
      return;
    case kusunga::SizeCheck::kOk:
      break;
  }

  const wchar_t* data = static_cast<const wchar_t*>(::GlobalLock(handle));
  if (!data) return;
  // GlobalSize can be a few bytes more than the text: measure the real text.
  const size_t max_units = ::GlobalSize(handle) / sizeof(wchar_t);
  size_t length = 0;
  while (length < max_units && data[length] != L'\0') length++;
  // Each UTF-16 unit is at least one UTF-8 byte, so too many units is too
  // large; then check the real UTF-8 size.
  std::string text;
  bool too_large = kusunga::ExceedsLimit(length);
  if (!too_large) {
    text = ToUtf8(data, length);
    too_large = kusunga::ExceedsLimit(text.size());
  }
  ::GlobalUnlock(handle);

  if (too_large) {
    Emit(Event("tooLarge"));
    return;
  }
  auto e = Event("text");
  e[EncodableValue("text")] = EncodableValue(text);
  Emit(std::move(e));
}

// Asks Dart to flush and close the database, and waits (at most 3 seconds)
// while still handling messages, because Dart's answer arrives through this
// thread's message loop.
void ClipboardBridge::FlushDartBlocking() {
  // Shared with the callbacks: if we give up after the timeout and return,
  // Dart's late answer must not write to a dead stack variable.
  auto done = std::make_shared<bool>(false);
  lifecycle_->InvokeMethod(
      "flush", nullptr,
      std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
          [done](const EncodableValue*) { *done = true; },
          [done](const std::string&, const std::string&,
                 const EncodableValue*) { *done = true; },
          [done]() { *done = true; }));

  const DWORD start = ::GetTickCount();
  while (!*done && ::GetTickCount() - start < kFlushTimeoutMs) {
    MSG msg;
    while (!*done && ::PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
    if (!*done) ::MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
  }
}

std::optional<LRESULT> ClipboardBridge::HandleMessage(UINT message,
                                                      WPARAM wparam,
                                                      LPARAM) {
  switch (message) {
    case WM_CLIPBOARDUPDATE:
      OnClipboardUpdate();
      return 0;
    case WM_QUERYENDSESSION:
      // Another program can still refuse to end the session, so nothing is
      // closed yet. Allow it.
      return TRUE;
    case WM_ENDSESSION:
      // The session is really ending (log off, shut down, restart): flush.
      if (wparam) FlushDartBlocking();
      return 0;
  }
  return std::nullopt;
}
