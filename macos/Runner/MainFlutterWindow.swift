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
    LoginItemBridge.shared.register(messenger: flutterViewController.engine.binaryMessenger)

    // M1.7 (D5 A): the window is not visible at launch (MainMenu.xib); it
    // opens once the app has launched, unless macOS started Kusunga as a
    // login item, which then starts in the menu bar only. The launch's
    // "open application" Apple event is the current event while this
    // notification is posted. If macOS doesn't mark it, the window opens
    // as before.
    launchObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: nil
    ) { [weak self] _ in
      guard let self = self else { return }
      if let observer = self.launchObserver {
        NotificationCenter.default.removeObserver(observer)
        self.launchObserver = nil
      }
      let event = NSAppleEventManager.shared().currentAppleEvent
      let kind = event?.paramDescriptor(forKeyword: AEKeyword(LoginLaunch.propData))?
        .enumCodeValue
      if LoginLaunch.showsWindowAtLaunch(eventID: event?.eventID, propData: kind) {
        self.makeKeyAndOrderFront(nil)
      }
    }

    super.awakeFromNib()
  }

  private var launchObserver: NSObjectProtocol?

  // The picker and the toast are borderless, and a borderless window cannot
  // become the key window (take keystrokes) unless it says so.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
