import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let project = FlutterDartProject()
    #if DEBUG
      // Debug builds only: `-KusungaDataProfile <name>` (a test data folder,
      // PM decision 2026-11-05) is passed on to Dart, which checks the name.
      // Only the launch arguments count, never a saved preference. A value
      // that is not text is passed on as "" so Dart rejects it (memory only)
      // rather than using the real data.
      let launchArgs = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
      if let value = launchArgs["KusungaDataProfile"] {
        project.dartEntrypointArguments = ["-KusungaDataProfile", value as? String ?? ""]
      }
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

    super.awakeFromNib()
  }

  // The picker and the toast are borderless, and a borderless window cannot
  // become the key window (take keystrokes) unless it says so.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
