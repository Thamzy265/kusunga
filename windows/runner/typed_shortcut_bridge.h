#ifndef RUNNER_TYPED_SHORTCUT_BRIDGE_H_
#define RUNNER_TYPED_SHORTCUT_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <functional>
#include <memory>
#include <optional>
#include <set>
#include <string>

#include "clipboard_policy.h"
#include "typed_shortcut_policy.h"

class WinReplacePlatform;
class HookThread;
class FieldCheckWorker;

// M1.5 typed shortcuts on Windows: WH_KEYBOARD_LL and WH_MOUSE_LL hooks on
// their own thread with its own message loop (reviewer R1: never on the
// runner's platform thread, which also runs Dart and the picker's paste),
// UI Automation's password check on a persistent worker thread, the
// matcher in typed_shortcut_policy.h, and the replacement. No permission
// is needed. The rules are tested without Windows
// (typed_shortcut_policy_test.cpp); this file only supplies the Windows
// calls.
//
// Threads: the hook thread owns the matcher, the front-window state and
// the ignore set. The UI thread hands it settings through `inbox_` and
// shares only `pending_` (the match Dart may answer) with it. A match goes
// hook thread -> field check worker -> UI thread (kMsgMatched) -> Dart.
//
// Method channel "com.wnasoni.kusunga/shortcuts" (see
// lib/shortcuts/channel_typed_shortcuts_port.dart):
//  - Dart calls "setTable" {entries: [{id, shortcut}]}, "setIgnored"
//    {appIds}, "setEnabled" {on} and "status" (both answer a status name),
//    "replace" {matchId, deleteCount, text}, "runningApps" (names only for
//    now; see
//    RunningAppIcon), "requestListenAccess" (true: Windows asks for no
//    permission) and "openInputMonitoringSettings" (nothing on Windows);
//  - native calls "matched" {snippetId, deleteCount, matchId} and
//    "statusChanged" {status} ("stopped" when Windows removed the hooks and
//    they could not be put back). matchId is an opaque counter (C2): a
//    "replace" answers only the newest match, never an older one.
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

  // Handles the bridge's own WM_APP messages (a checked match, the hooks
  // lost or put back), WM_TIMER for the replacement's timers (the 0.5 s
  // restore, the modifier poll), and looks at WM_ACTIVATE (put the hooks
  // back) without handling it.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  friend class WinReplacePlatform;

  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Start();
  void Stop(const char* status);
  void SetStatus(const char* status);
  void OnMatched(int snippet_id, int delete_count, uint32_t match_id);
  // Answers through [answer], at once or after waiting for held modifiers
  // to be released (C1, never sleeping).
  void Replace(uint32_t match_id, int delete_count, const std::string& text,
               std::function<void(const char*)> answer);

  HWND window_;
  kusunga::OwnClipboardChanges* own_;
  UINT format_own_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool enabled_ = false;
  std::string status_ = "off";

  // Shared with the hook thread (each has its own lock).
  kusunga::HookInbox inbox_;
  kusunga::PendingMatch pending_;
  uint32_t replacing_id_ = 0;  // the match being replaced now (UI thread)

  std::unique_ptr<FieldCheckWorker> field_worker_;
  std::unique_ptr<HookThread> hook_thread_;

  std::unique_ptr<WinReplacePlatform> replace_platform_;
  std::unique_ptr<kusunga::ReplaceFlow> replace_flow_;
};

#endif  // RUNNER_TYPED_SHORTCUT_BRIDGE_H_
