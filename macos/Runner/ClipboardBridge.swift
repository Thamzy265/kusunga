import Cocoa
import FlutterMacOS

/// Connects the clipboard watcher and the quit flow to Dart.
///
/// Channels (names match lib/clipboard/channel_clipboard_source.dart and
/// lib/lifecycle/app_lifecycle.dart):
///  - event `com.wnasoni.kusunga/clipboard/events`: copies. Listening
///    starts polling every 250 ms; cancelling stops it.
///  - method `com.wnasoni.kusunga/clipboard`: `accessBehavior`, and
///    `writeOwn {text}` (a copied snippet: written with its change count
///    recorded, so the watcher skips it; answers a bool),
///    `setCaptureIgnored {appIds}` and `setCapturePause {until}` (M1.6: the
///    ignore list, and 0, -1 or an end time in ms; the watcher checks both
///    before reading a copy, ADR 0005; each answers true).
///  - method `com.wnasoni.kusunga/lifecycle`: Dart calls `quit`;
///    native calls `flush` and waits for the answer before quitting.
final class ClipboardBridge: NSObject, FlutterStreamHandler {
  static let shared = ClipboardBridge()

  private var timer: Timer?
  private var poller: ClipboardPoller?
  private(set) var lifecycleChannel: FlutterMethodChannel?

  func register(messenger: FlutterBinaryMessenger) {
    FlutterEventChannel(
      name: "com.wnasoni.kusunga/clipboard/events", binaryMessenger: messenger
    ).setStreamHandler(self)

    FlutterMethodChannel(
      name: "com.wnasoni.kusunga/clipboard", binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      if call.method == "accessBehavior" {
        result(ClipboardBridge.accessBehavior())
      } else if call.method == "writeOwn" {
        guard let args = call.arguments as? [String: Any], let text = args["text"] as? String
        else { return result(false) }
        result(NSPasteboardWriter(ownChanges: OwnClipboardChanges.shared).writeText(text))
      } else if call.method == "setCaptureIgnored" {
        let args = call.arguments as? [String: Any]
        CaptureGate.shared.setIgnored((args?["appIds"] as? [String]) ?? [])
        result(true)
      } else if call.method == "setCapturePause" {
        let args = call.arguments as? [String: Any]
        guard let until = (args?["until"] as? NSNumber)?.int64Value else { return result(false) }
        CaptureGate.shared.setPause(until)
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let lifecycle = FlutterMethodChannel(
      name: "com.wnasoni.kusunga/lifecycle", binaryMessenger: messenger)
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
    let poller = ClipboardPoller(
      pasteboard: NSPasteboard.general,
      mayRetry: { ClipboardPoller.readsAreSilent(ClipboardBridge.accessBehavior()) },
      mayReadMarker: { ClipboardPoller.readsAreSilent(ClipboardBridge.accessBehavior()) },
      ownChanges: OwnClipboardChanges.shared,
      gate: CaptureGate.shared,
      frontApp: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) { events($0) }
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
