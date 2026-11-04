import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    ClipboardBridge.shared.register(messenger: flutterViewController.engine.binaryMessenger)
    PickerBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger, window: self,
      viewController: flutterViewController)

    super.awakeFromNib()
  }

  // The picker and the toast are borderless, and a borderless window cannot
  // become the key window (take keystrokes) unless it says so.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
