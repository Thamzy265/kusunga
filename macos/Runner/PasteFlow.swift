import Cocoa

/// What the paste flow needs from the Mac. A protocol so the logic (focus
/// confirmation, modifier wait, never posting into the wrong app) is tested
/// with a pretend Mac whose clock only moves when the flow sleeps.
protocol PastePlatform: AnyObject {
  /// Hides the picker window.
  func hidePicker()
  func frontmostPid() -> pid_t?
  func isRunning(_ pid: pid_t) -> Bool
  /// Asks the app to come to the front. False if it cannot be asked.
  func activate(_ pid: pid_t) -> Bool
  /// Cmd, Shift, Ctrl or Option is held down right now.
  func modifiersDown() -> Bool
  /// `CGPreflightPostEventAccess()`: does not prompt.
  func canPostEvents() -> Bool
  /// Sends Cmd+V to the session.
  func postPaste()
  func sleep(ms: Int)
  func nowMs() -> Int
}

protocol PasteboardWriting {
  /// Replaces the pasteboard with [text] and our own marker type.
  func writeText(_ text: String) -> Bool
}

/// How a paste ended. The raw values are the answers to Dart (see
/// lib/picker/channel_picker_port.dart).
enum PasteResult: String {
  case pasted
  case noPermission
  case focusTimeout
  case targetGone
  case copyOnly
  case failed
}

/// Design note, "How paste works" (Mac): write the text and our marker, hide
/// the picker, bring the remembered app back, confirm it is in front (up to
/// 500 ms), wait for the picker's modifier keys to be released (up to 300 ms),
/// and only then, if the permission is there, post Cmd+V. Anything else leaves
/// the text on the clipboard and reports why. Never posts into Kusunga itself
/// or into an app that is not in front.
final class PasteFlow {
  static let focusTimeoutMs = 500
  static let modifierTimeoutMs = 300
  static let pollMs = 10

  private let platform: PastePlatform
  private let writer: PasteboardWriting
  private let ownPid: pid_t

  init(platform: PastePlatform, writer: PasteboardWriting, ownPid: pid_t) {
    self.platform = platform
    self.writer = writer
    self.ownPid = ownPid
  }

  func run(text: String, target: pid_t?, post: Bool) -> PasteResult {
    let written = writer.writeText(text)
    platform.hidePicker()
    guard written else { return .failed }

    guard let target = target, target != ownPid, platform.isRunning(target) else {
      return .targetGone
    }
    guard platform.activate(target) else { return .targetGone }
    guard waitUntil(PasteFlow.focusTimeoutMs, { platform.frontmostPid() == target }) else {
      return .focusTimeout
    }
    if !post { return .copyOnly }
    if !platform.canPostEvents() { return .noPermission }

    // Let go of Cmd+Shift first, so the app does not see Cmd+Shift+V. Waiting
    // too long is not an error: the key event below carries only Cmd.
    _ = waitUntil(PasteFlow.modifierTimeoutMs, { !platform.modifiersDown() })

    // Focus can be taken while we waited: check again, right before posting.
    guard platform.frontmostPid() == target else { return .focusTimeout }
    platform.postPaste()
    return .pasted
  }

  private func waitUntil(_ limitMs: Int, _ condition: () -> Bool) -> Bool {
    let start = platform.nowMs()
    while true {
      if condition() { return true }
      if platform.nowMs() - start >= limitMs { return false }
      platform.sleep(ms: PasteFlow.pollMs)
    }
  }
}

/// Writes to a real NSPasteboard (the general one in the app, a private one in
/// tests).
final class NSPasteboardWriter: PasteboardWriting {
  private let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func writeText(_ text: String) -> Bool {
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else { return false }
    // Our own marker: the watcher then only moves the item to the top, and
    // only if it is already saved (a copy with the marker is never trusted).
    _ = pasteboard.setString(
      "1", forType: NSPasteboard.PasteboardType(ClipboardPolicy.ownMarkerType))
    return true
  }
}

/// The real Mac. [hide] hides the picker window.
final class MacPastePlatform: PastePlatform {
  private let hide: () -> Void

  init(hide: @escaping () -> Void) {
    self.hide = hide
  }

  func hidePicker() { hide() }

  func frontmostPid() -> pid_t? {
    NSWorkspace.shared.frontmostApplication?.processIdentifier
  }

  func isRunning(_ pid: pid_t) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
    return !app.isTerminated
  }

  func activate(_ pid: pid_t) -> Bool {
    MacPastePlatform.activateApp(pid)
  }

  static func activateApp(_ pid: pid_t) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
      return false
    }
    if #available(macOS 14.0, *) {
      // Kusunga is the active app, so it may hand the focus to another one.
      return app.activate(from: NSRunningApplication.current, options: [])
    }
    return app.activate(options: [.activateIgnoringOtherApps])
  }

  func modifiersDown() -> Bool {
    !NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty
  }

  func canPostEvents() -> Bool { CGPreflightPostEventAccess() }

  func postPaste() {
    // Key code 9 is "V" on the US layout. Posted to the session, with only the
    // Command flag.
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
      else { continue }
      event.flags = .maskCommand
      event.post(tap: .cgSessionEventTap)
    }
  }

  /// Waits while still handling events: the system tells us which app is in
  /// front through the main run loop.
  func sleep(ms: Int) {
    let deadline = Date().addingTimeInterval(Double(ms) / 1000)
    if !RunLoop.current.run(mode: .default, before: deadline) {
      Thread.sleep(until: deadline)
    }
  }

  func nowMs() -> Int {
    Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
  }
}
