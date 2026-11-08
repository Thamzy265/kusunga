#ifndef RUNNER_TYPED_SHORTCUT_BRIDGE_H_
#define RUNNER_TYPED_SHORTCUT_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <set>
#include <string>

#include "clipboard_policy.h"
#include "typed_shortcut_policy.h"

class WinReplacePlatform;

// M1.5 typed shortcuts on Windows: WH_KEYBOARD_LL and WH_MOUSE_LL hooks on
// the runner's UI thread (no permission needed), the matcher in
// typed_shortcut_policy.h, and the replacement. The rules are tested
// without Windows (typed_shortcut_policy_test.cpp); this file only supplies
// the Windows calls.
//
// Method channel "com.wnasoni.kusunga/shortcuts" (see
// lib/shortcuts/channel_typed_shortcuts_port.dart):
//  - Dart calls "setTable" {entries: [{id, shortcut}]}, "setIgnored"
//    {appIds}, "setEnabled" {on} and "status" (both answer a status name),
//    "replace" {deleteCount, text}, "runningApps" (names only for now; see
//    RunningAppIcon), "requestListenAccess" (true: Windows asks for no
//    permission) and "openInputMonitoringSettings" (nothing on Windows);
//  - native calls "matched" {snippetId, deleteCount} and "statusChanged"
//    {status}.
// Typed keys never leave the matcher's buffer (ADR 0004). The front window
// is known by handle and executable name, in memory only, never logged.
class TypedShortcutBridge {
 public:
  // [own] is shared with the clipboard watcher and outlives this bridge.
  TypedShortcutBridge(flutter::BinaryMessenger* messenger, HWND window,
                      kusunga::OwnClipboardChanges* own);
  ~TypedShortcutBridge();

  TypedShortcutBridge(const TypedShortcutBridge&) = delete;
  TypedShortcutBridge& operator=(const TypedShortcutBridge&) = delete;

  // Handles the bridge's own WM_APP message (a match, checked off the hook)
  // and WM_TIMER (the 1 s idle clear and the 0.5 s restore).
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  friend class WinReplacePlatform;

  static LRESULT CALLBACK KeyboardProc(int code, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK MouseProc(int code, WPARAM wparam, LPARAM lparam);

  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Start();
  void Stop(const char* status);
  void SetStatus(const char* status);
  void OnKey(const KBDLLHOOKSTRUCT& key);
  void UpdateForeground(HWND foreground);
  void OnMatched(int snippet_id, int delete_count);
  std::string Replace(int delete_count, const std::string& text);

  HWND window_;
  kusunga::OwnClipboardChanges* own_;
  UINT format_own_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  kusunga::TypedShortcutMatcher matcher_;
  std::set<std::string> ignored_;
  bool enabled_ = false;
  std::string status_ = "off";
  HHOOK keyboard_hook_ = nullptr;
  HHOOK mouse_hook_ = nullptr;

  HWND foreground_ = nullptr;
  bool foreground_ignored_ = false;
  bool foreground_self_ = false;
  bool foreground_elevated_ = false;

  HWND match_window_ = nullptr;
  bool has_match_ = false;
  int keys_since_match_ = 0;

  std::unique_ptr<WinReplacePlatform> replace_platform_;
  std::unique_ptr<kusunga::ReplaceFlow> replace_flow_;
};

#endif  // RUNNER_TYPED_SHORTCUT_BRIDGE_H_
