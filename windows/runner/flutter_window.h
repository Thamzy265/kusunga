#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "clipboard_bridge.h"
#include "picker_bridge.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
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

  // Kusunga's own clipboard changes (a snippet), shared by the paste flow and
  // the watcher so a snippet is not added to history. Declared before the
  // bridges, so it outlives them.
  kusunga::OwnClipboardChanges own_changes_;

  // Clipboard watcher and quit flow (see clipboard_bridge.h).
  std::unique_ptr<ClipboardBridge> clipboard_bridge_;

  // The global shortcut, the picker window and paste (see picker_bridge.h).
  std::unique_ptr<PickerBridge> picker_bridge_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
