import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var termination: TerminationCoordinator?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Closing the window hides it; Quit in the menu bar is the only exit.
    return false
  }

  // Every way of quitting passes through here. Dart flushes and closes the
  // history database first; we wait for it (at most 3 seconds).
  override func applicationShouldTerminate(_ sender: NSApplication)
    -> NSApplication.TerminateReply
  {
    if termination == nil {
      let channel = ClipboardBridge.shared.lifecycleChannel
      termination = TerminationCoordinator(
        flush: channel.map { channel in
          { done in channel.invokeMethod("flush", arguments: nil) { _ in done() } }
        },
        reply: { NSApp.reply(toApplicationShouldTerminate: true) },
        timeout: 3)
    }
    return termination!.begin()
  }

  // A Dock click with no visible window shows the main window again.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      sender.windows.first(where: { $0 is MainFlutterWindow })?
        .makeKeyAndOrderFront(self)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
