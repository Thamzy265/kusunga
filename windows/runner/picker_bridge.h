#ifndef RUNNER_PICKER_BRIDGE_H_
#define RUNNER_PICKER_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "picker_policy.h"

// Connects the picker to Dart: the global shortcut (RegisterHotKey), the
// window shapes and the paste flow. The rules (keys, placement, focus and
// administrator checks) are in picker_policy.h and tested without Windows.
//
// Method channel "com.wnasoni.kusunga/picker" (see
// lib/picker/channel_picker_port.dart):
//  - Dart calls "registerShortcut" {key, modifiers} (answers "ok", "taken" or
//    "invalid"), "unregisterShortcut", "openPicker", "closePicker",
//    "paste" {text, post} (answers a PasteResult name), "showToast",
//    "hideToast", "canPost" and "requestPostAccess" (both always true here);
//  - native calls "shortcutPressed" (and shows the picker once Dart has
//    answered, or after 300 ms) and "dismissed".
// The window that had focus is remembered by handle only, in memory, from the
// moment the shortcut is pressed until the picker is gone. It is never stored
// or logged.
class PickerBridge {
 public:
  PickerBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~PickerBridge();

  PickerBridge(const PickerBridge&) = delete;
  PickerBridge& operator=(const PickerBridge&) = delete;

  // Handles WM_HOTKEY, WM_TIMER (the 300 ms fallback), WM_ACTIVATE (the
  // picker lost focus) and WM_GETMINMAXINFO (no minimum size while the picker
  // or the toast shows). It runs before Flutter's own handling. Returns the result if the message was handled.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

  // Called by the paste flow to hide the picker.
  void HidePickerForPaste();

 private:
  enum class Mode { kNormal, kPicker, kToast };

  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  const char* RegisterShortcut(const std::string& key,
                               const std::vector<std::string>& modifiers);
  void UnregisterShortcut();

  void BeginOpen();
  void ShowPendingPicker();
  void EnterPicker();
  void LeavePicker(bool show_manage, bool activate);
  void ClosePicker();
  void WindowDeactivated();
  void ShowToast();
  void HideToast();

  void SaveWindow();
  void RestoreWindow();
  void ApplySmallShape(kusunga::Rect frame, bool no_activate);
  kusunga::Rect WorkAreaAtPointer(double* scale) const;

  std::string RunPasteFlow(const std::string& text, bool post);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  Mode mode_ = Mode::kNormal;
  bool manage_was_visible_ = false;
  bool pasting_ = false;
  bool open_pending_ = false;
  HWND target_ = nullptr;

  bool saved_ = false;
  LONG_PTR saved_style_ = 0;
  LONG_PTR saved_ex_style_ = 0;
  WINDOWPLACEMENT saved_placement_{};

  int hotkey_id_ = 0;  // 0: none; otherwise 1 or 2 (the new one is registered
                       // under the other number before the old is released)
  uint32_t hotkey_vk_ = 0;
  uint32_t hotkey_mods_ = 0;
  UINT format_own_ = 0;
};

#endif  // RUNNER_PICKER_BRIDGE_H_
