#ifndef RUNNER_CLIPBOARD_BRIDGE_H_
#define RUNNER_CLIPBOARD_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>

#include "capture_gate.h"
#include "clipboard_policy.h"

// Connects the Windows clipboard watcher and the quit flow to Dart.
//
// Channels (names match lib/clipboard/channel_clipboard_source.dart and
// lib/lifecycle/app_lifecycle.dart):
//  - event "com.wnasoni.kusunga/clipboard/events": copies. A text event has
//    "own": true when the copy carries Kusunga's own marker format
//    ("com.wnasoni.kusunga.self", written by the picker).
//    Listening starts the watcher (AddClipboardFormatListener); cancelling
//    stops it.
//  - method "com.wnasoni.kusunga/clipboard": "accessBehavior"
//    always answers "unsupported" (a Mac-only setting); "writeOwn" {text}
//    writes a copied snippet with its sequence number recorded, so the
//    watcher skips it (PM decision D1), and answers a bool;
//    "setCaptureIgnored" {appIds} and "setCapturePause" {until} (M1.6: the
//    ignore list, and 0, -1 or an end time in ms) set what the watcher checks
//    before reading a copy (ADR 0005), and answer true. A copy from an
//    ignored app sends {type: "ignoredApp"}; when the list is not empty and
//    the source can't be found, {type: "sourceUnknown"} comes before the
//    copy's own event. Neither names the app.
//  - method "com.wnasoni.kusunga/lifecycle": Dart calls "quit";
//    native calls "flush" and waits for the answer when Windows ends the
//    session (WM_ENDSESSION).
// Puts [text] (UTF-8) on the clipboard with Kusunga's marker format. With
// [own] (a snippet), the change is recorded so the watcher skips it. [marks]
// (typed shortcuts, M1.5 D2 and S1) add the "don't keep this" formats:
// ExcludeClipboardContentFromMonitorProcessing, CanIncludeInClipboardHistory
// = 0 and CanUploadToCloudClipboard = 0, so other clipboard managers,
// Windows clipboard history and the cloud clipboard leave it alone. Used by
// the paste flow, "writeOwn" and typed shortcuts.
bool WriteClipboardText(HWND window, UINT format_own, const std::string& text,
                        kusunga::OwnClipboardChanges* own,
                        const kusunga::ClipboardMarks& marks = {});

class ClipboardBridge {
 public:
  // [own] is shared with the picker's paste flow and outlives both bridges.
  ClipboardBridge(flutter::BinaryMessenger* messenger, HWND window,
                  kusunga::OwnClipboardChanges* own);
  ~ClipboardBridge();

  ClipboardBridge(const ClipboardBridge&) = delete;
  ClipboardBridge& operator=(const ClipboardBridge&) = delete;

  // Handles WM_CLIPBOARDUPDATE, WM_QUERYENDSESSION and WM_ENDSESSION. Returns
  // the result if the message was handled.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  void Start(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
  void Stop();
  void OnClipboardUpdate();
  void Emit(flutter::EncodableMap event);
  void FlushDartBlocking();

  HWND window_;
  kusunga::OwnClipboardChanges* own_;
  bool listening_ = false;
  uint32_t last_sequence_ = 0;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> clipboard_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> lifecycle_;
  UINT format_exclude_ = 0;
  UINT format_can_include_ = 0;
  UINT format_viewer_ignore_ = 0;
  UINT format_own_ = 0;
  kusunga::CaptureGate gate_;
};

#endif  // RUNNER_CLIPBOARD_BRIDGE_H_
