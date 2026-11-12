#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "clipboard_bridge.h"
#include "login_item_bridge.h"
#include "picker_bridge.h"
#include "typed_shortcut_bridge.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // With [start_hidden] (a login start, M1.7 D5 A) the window is not shown
  // after the first frame: Kusunga starts in the tray only.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // A login start: no window until the user opens it from the tray.
  bool start_hidden_;

  // Kusunga's own clipboard changes (a snippet), shared by the paste flow and
  // the watcher so a snippet is not added to history. Declared before the
  // bridges, so it outlives them.
  kusunga::OwnClipboardChanges own_changes_;

  // Clipboard watcher and quit flow (see clipboard_bridge.h).
  std::unique_ptr<ClipboardBridge> clipboard_bridge_;

  // The global shortcut, the picker window and paste (see picker_bridge.h).
  std::unique_ptr<PickerBridge> picker_bridge_;

  // Typed shortcuts: the keyboard hook and replacement (see
  // typed_shortcut_bridge.h).
  std::unique_ptr<TypedShortcutBridge> typed_shortcut_bridge_;

  // Launch at login: the HKCU Run value (see login_item_bridge.h).
  std::unique_ptr<LoginItemBridge> login_item_bridge_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
