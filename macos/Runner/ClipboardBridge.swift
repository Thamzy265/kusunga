import Cocoa
import FlutterMacOS

/// Connects the clipboard watcher and the quit flow to Dart.
///
/// Channels (names match lib/clipboard/channel_clipboard_source.dart and
/// lib/lifecycle/app_lifecycle.dart):
///  - event `uk.org.cgatechnologies.kusunga/clipboard/events`: copies. Listening
///    starts polling every 250 ms; cancelling stops it.
///  - method `uk.org.cgatechnologies.kusunga/clipboard`: `accessBehavior`.
///  - method `uk.org.cgatechnologies.kusunga/lifecycle`: Dart calls `quit`;
///    native calls `flush` and waits for the answer before quitting.
final class ClipboardBridge: NSObject, FlutterStreamHandler {
  static let shared = ClipboardBridge()

  private var timer: Timer?
  private var poller: ClipboardPoller?
  private(set) var lifecycleChannel: FlutterMethodChannel?

  func register(messenger: FlutterBinaryMessenger) {
    FlutterEventChannel(
      name: "uk.org.cgatechnologies.kusunga/clipboard/events", binaryMessenger: messenger
    ).setStreamHandler(self)

    FlutterMethodChannel(
      name: "uk.org.cgatechnologies.kusunga/clipboard", binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      if call.method == "accessBehavior" {
        result(ClipboardBridge.accessBehavior())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let lifecycle = FlutterMethodChannel(
      name: "uk.org.cgatechnologies.kusunga/lifecycle", binaryMessenger: messenger)
    lifecycle.setMethodCallHandler { call, result in
      if call.method == "quit" {
        result(nil)
        DispatchQueue.main.async { NSApp.terminate(nil) }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    lifecycleChannel = lifecycle
  }

  /// "allow", "ask", "deny", or "unsupported" before macOS 15.4.
  static func accessBehavior() -> String {
    if #available(macOS 15.4, *) {
      switch NSPasteboard.general.accessBehavior {
      case .alwaysAllow: return "allow"
      case .alwaysDeny: return "deny"
      default: return "ask"
      }
    }
    return "unsupported"
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    let poller = ClipboardPoller(pasteboard: NSPasteboard.general) { events($0) }
    poller.prime()
    self.poller = poller
    let timer = Timer(timeInterval: 0.25, repeats: true) { _ in poller.tick() }
    timer.tolerance = 0.05  // lets the system batch wake-ups: low idle CPU
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    timer?.invalidate()
    timer = nil
    poller = nil
    return nil
  }
}
