import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let project = FlutterDartProject()
    #if DEBUG
      // Debug builds only: the launch arguments go on to Dart, which looks
      // for `-KusungaDataProfile <name>` (a test data folder, PM decision
      // 2026-11-05) and rejects a bad name or a mistyped switch.
      project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    #endif
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    ClipboardBridge.shared.register(messenger: flutterViewController.engine.binaryMessenger)
    PickerBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger, window: self,
      viewController: flutterViewController)
    TypedShortcutBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // The picker and the toast are borderless, and a borderless window cannot
  // become the key window (take keystrokes) unless it says so.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
