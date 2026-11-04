import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

/// Connects the picker to Dart: the global shortcut, the window shapes and the
/// paste flow.
///
/// Method channel `com.wnasoni.kusunga/picker` (see
/// lib/picker/channel_picker_port.dart):
///  - Dart calls `registerShortcut {key, modifiers}` (answers "ok", "taken" or
///    "invalid"), `unregisterShortcut`, `openPicker`, `closePicker`,
///    `paste {text, post}` (answers a PasteResult name), `showToast`,
///    `hideToast`, `canPost`, `permissionSnapshot` (a number for the log) and
///    `requestPostAccess`;
///  - native calls `shortcutPressed` (and shows the picker once Dart has
///    answered, or after 300 ms) and `dismissed`.
/// The app that has focus is remembered by process id only, in memory, from the
/// moment the shortcut is pressed until the picker is gone. It is never stored
/// or logged.
final class PickerBridge {
  static let shared = PickerBridge()

  private var channel: FlutterMethodChannel?
  private var windows: PickerWindowController?
  private let backend = CarbonHotKeyBackend()
  private lazy var registry = HotKeyRegistry(backend: backend)
  private var target: pid_t?
  private let dismissal = DismissCoordinator()
  private var pasting = false
  private var openPending = false
  private var resignObserver: NSObjectProtocol?

  func register(
    messenger: FlutterBinaryMessenger, window: NSWindow, viewController: FlutterViewController
  ) {
    let windows = PickerWindowController(window: window, viewController: viewController)
    self.windows = windows
    backend.onPress = { [weak self] handle in self?.registry.handlePress(handle: handle) }
    registry.onPress = { [weak self] in self?.beginOpen() }

    // Dart mirrors its log codes here (codes and numbers only).
    FlutterMethodChannel(name: "com.wnasoni.kusunga/diag", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method == "log", let args = call.arguments as? [String: Any],
          let code = args["code"] as? String
        {
          DiagLog.log(code, args["detail"] as? Int)
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

    // The app the picker came from quit: it is gone, so a paste only copies.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let self = self, let t = self.target,
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.processIdentifier == t
      else { return }
      DiagLog.log("targetTerminated", nil)
      // The pid stays (a paste then finds it gone and only copies); the flag
      // tells a lost focus that the quit was the reason.
      self.dismissal.noteTargetQuit()
      if self.windows?.mode == .picker { self.windows?.retakeKeyboard() }
    }

    let channel = FlutterMethodChannel(
      name: "com.wnasoni.kusunga/picker", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel

    // Clicking outside or switching app takes the focus from the picker: it
    // closes, and the history window comes back if it was open.
    resignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: window, queue: .main
    ) { [weak self] _ in self?.windowLostFocus() }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "registerShortcut":
      guard let key = args?["key"] as? String, let mods = args?["modifiers"] as? [String] else {
        return result("invalid")
      }
      result(registry.set(key: key, modifiers: mods))
    case "unregisterShortcut":
      registry.clear()
      result(nil)
    case "openPicker":
      beginOpen()
      result(nil)
    case "closePicker":
      closePicker()
      result(nil)
    case "paste":
      guard let text = args?["text"] as? String else { return result(PasteResult.failed.rawValue) }
      result(runPaste(text: text, post: (args?["post"] as? Bool) ?? true).rawValue)
    case "showToast":
      windows?.showToast()
      result(nil)
    case "hideToast":
      windows?.hideToast()
      result(nil)
    case "permissionSnapshot":
      result(PermissionSnapshot.current())
    case "canPost":
      result(CGPreflightPostEventAccess())
    case "requestPostAccess":
      // Only the "Allow pasting" button gets here (design note: never on our
      // own).
      result(CGRequestPostEventAccess())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The shortcut or the tray item: remember the app that has focus, ask Dart
  /// to switch to the picker, then show the window.
  private func beginOpen() {
    guard let windows = windows, let channel = channel else { return }
    if pasting || openPending || windows.mode == .picker { return }
    let me = ProcessInfo.processInfo.processIdentifier
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    target = (front != nil && front != me) ? front : nil
    dismissal.reset()
    openPending = true
    var shown = false
    let show = { [weak self] in
      if shown { return }
      shown = true
      self?.openPending = false
      self?.windows?.enterPicker(target: self?.target)
    }
    channel.invokeMethod("shortcutPressed", arguments: nil) { _ in show() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { show() }
  }

  /// Esc.
  private func closePicker() {
    guard let windows = windows, windows.mode == .picker else { return }
    // A target that quit is as good as none: Kusunga was the app in front.
    let plan = ClosePlan.make(
      manageWasVisible: windows.manageWasVisible, target: dismissal.targetQuit ? nil : target)
    windows.leavePicker(showManage: plan.showManage, activate: plan.activateKusunga)
    if let t = plan.reactivate { _ = MacPastePlatform.activateApp(t) }
    target = nil
  }

  private func windowLostFocus() {
    guard let windows = windows, windows.mode == .picker, !pasting else { return }
    dismissal.focusLost(
      target: target, alive: { [weak self] in self?.targetAlive() ?? false },
      schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
      decide: { [weak self] dismiss in
        guard let self = self, let windows = self.windows, windows.mode == .picker, !self.pasting
        else { return }
        if dismiss {
          self.dismissPicker()
        } else {
          // The app the picker came from quit: stay open, Enter copies and
          // shows the toast.
          DiagLog.log("pickerKeptTargetGone", nil)
          windows.retakeKeyboard()
        }
      })
  }

  private func targetAlive() -> Bool {
    target.map { MacPastePlatform.isAlive($0) } ?? false
  }

  private func dismissPicker() {
    guard let windows = windows else { return }
    windows.leavePicker(showManage: windows.manageWasVisible, activate: false)
    target = nil
    channel?.invokeMethod("dismissed", arguments: nil)
  }

  private func runPaste(text: String, post: Bool) -> PasteResult {
    pasting = true
    defer {
      pasting = false
      target = nil
    }
    let platform = MacPastePlatform(
      hide: { [weak self] in self?.windows?.leavePicker(showManage: false, activate: false) },
      diag: DiagLog.log)
    let flow = PasteFlow(
      platform: platform, writer: NSPasteboardWriter(),
      ownPid: ProcessInfo.processInfo.processIdentifier, diag: DiagLog.log)
    return flow.run(text: text, target: target, post: post)
  }
}
