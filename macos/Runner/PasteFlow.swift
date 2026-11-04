import Carbon.HIToolbox
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
  /// Debug builds only: post even if macOS says posting is not allowed, to test
  /// whether the event arrives. Always false in a Release build.
  func forcePostEnabled() -> Bool
  /// The key code of the key that types "v" in the current keyboard layout,
  /// or nil if no key does (then nothing is sent).
  func pasteKeyCode() -> UInt16?
  /// Sends Cmd+V to the session, with the key found by `pasteKeyCode()`.
  func postPaste()
  func sleep(ms: Int)
  func nowMs() -> Int
}

protocol PasteboardWriting {
  /// Replaces the pasteboard with [text] and our own marker type.
  func writeText(_ text: String) -> Bool
}

/// How a paste ended. The raw values are the answers to Dart (see
/// lib/picker/channel_picker_port.dart); `logNumber` is the number written to
/// the log after `pasteResult`. The numbers are pinned: a new case gets a new
/// number and never shifts the others.
///   0 pasted, 1 pastedForced, 2 noPermission, 3 focusTimeout, 4 targetGone,
///   5 copyOnly, 6 failed.
///
/// The raw values are the answers to Dart (see
/// lib/picker/channel_picker_port.dart).
extension PastePlatform {
  func forcePostEnabled() -> Bool { false }
  /// The US layout key for V. The real Mac looks it up in the layout.
  func pasteKeyCode() -> UInt16? { 9 }
}

/// Finds the key that types "v". Key code 9 is the V key on a US layout, but
/// on Dvorak it types "." and Cmd+. would interrupt a running Terminal command.
enum PasteKey {
  /// [translate] gives the letter a key code types in the current layout with
  /// Command held (so on "Dvorak - QWERTY ⌘", where the Command table is
  /// QWERTY, key 9 is chosen), or nil. The standard key is tried first.
  static func code(forV translate: (UInt16, Bool) -> String?) -> UInt16? {
    if translate(9, true) == "v" { return 9 }
    for code in UInt16(0)..<UInt16(128) where translate(code, true) == "v" {
      return code
    }
    return nil
  }

  /// The real layout: the current keyboard layout, or the last ASCII-capable
  /// one if the current layout cannot type letters (as macOS does for Cmd
  /// shortcuts).
  static func translateInCurrentLayout(_ code: UInt16, command: Bool) -> String? {
    guard
      let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
    guard let bytes = CFDataGetBytePtr(data) else { return nil }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    var dead: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    let status = UCKeyTranslate(
      layout, code, UInt16(kUCKeyActionDown),
      command ? UInt32((cmdKey >> 8) & 0xFF) : 0, UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: length)
  }
}

/// The permission state as one small number for the log: 1 post allowed,
/// 2 accessibility trusted (read only: never asks), 4 listen allowed.
enum PermissionSnapshot {
  static func mask(post: Bool, accessibility: Bool, listen: Bool) -> Int {
    (post ? 1 : 0) | (accessibility ? 2 : 0) | (listen ? 4 : 0)
  }

  static func current() -> Int {
    mask(
      post: CGPreflightPostEventAccess(), accessibility: AXIsProcessTrusted(),
      listen: CGPreflightListenEventAccess())
  }
}

/// What Esc does (E1): the history window comes back without being activated,
/// and the app the user was in gets the focus back. Kusunga itself is
/// activated only if it was the app in front.
struct ClosePlan: Equatable {
  let showManage: Bool
  let activateKusunga: Bool
  let reactivate: pid_t?

  static func make(manageWasVisible: Bool, target: pid_t?) -> ClosePlan {
    ClosePlan(
      showManage: manageWasVisible,
      activateKusunga: manageWasVisible && target == nil,
      reactivate: target)
  }
}

enum PasteResult: String, CaseIterable {
  case pasted
  case pastedForced
  case noPermission
  case focusTimeout
  case targetGone
  case copyOnly
  case failed

  var logNumber: Int {
    switch self {
    case .pasted: return 0
    case .pastedForced: return 1
    case .noPermission: return 2
    case .focusTimeout: return 3
    case .targetGone: return 4
    case .copyOnly: return 5
    case .failed: return 6
    }
  }
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
  private let diag: (String, Int?) -> Void
  private let permissionMask: () -> Int

  /// [diag] gets a code and a number for every step (never any content).
  /// [permissionMask] is the permission state (see `PermissionSnapshot`), logged
  /// once before the result of every paste.
  init(
    platform: PastePlatform, writer: PasteboardWriting, ownPid: pid_t,
    diag: @escaping (String, Int?) -> Void = { _, _ in },
    permissionMask: @escaping () -> Int = PermissionSnapshot.current
  ) {
    self.permissionMask = permissionMask
    self.platform = platform
    self.writer = writer
    self.ownPid = ownPid
    self.diag = diag
  }

  func run(text: String, target: pid_t?, post: Bool) -> PasteResult {
    let start = platform.nowMs()
    diag("permissionSnapshot", permissionMask())
    let result = steps(text: text, target: target, post: post, start: start)
    diag("pasteResult", result.logNumber)
    return result
  }

  private func steps(text: String, target: pid_t?, post: Bool, start: Int) -> PasteResult {
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
    var forced = false
    if !platform.canPostEvents() {
      if platform.forcePostEnabled() { forced = true } else { return .noPermission }
    }
    // No key types "v" in this layout: pressing a different key could do
    // something else, so only the copy is done.
    guard let keyCode = platform.pasteKeyCode() else {
      diag("postKeyNone", nil)
      return .copyOnly
    }
    diag("postKeyCode", Int(keyCode))
    if forced { diag("postForced", 1) }

    // Let go of Cmd+Shift first, so the app does not see Cmd+Shift+V. Waiting
    // too long is not an error: the key event below carries only Cmd.
    _ = waitUntil(PasteFlow.modifierTimeoutMs, { !platform.modifiersDown() })

    // Focus can be taken while we waited: check again, right before posting.
    let frontOk = platform.frontmostPid() == target
    diag("postFrontmostOk", frontOk ? 1 : 0)
    guard frontOk else { return .focusTimeout }
    platform.postPaste()
    diag("postTiming", platform.nowMs() - start)
    return forced ? .pastedForced : .pasted
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
  private let ownChanges: OwnClipboardChanges?

  /// With [ownChanges] (a snippet), the change count this write made is
  /// recorded, so the watcher skips it and it is not added to history.
  init(pasteboard: NSPasteboard = .general, ownChanges: OwnClipboardChanges? = nil) {
    self.pasteboard = pasteboard
    self.ownChanges = ownChanges
  }

  /// How many times the change count moves after `clearContents()` while
  /// the text and the marker are written: none (setString on the item the
  /// clear created does not change ownership; XCTest pins this).
  static let changesAfterClear = 0

  /// The change number recorded by the last write (tests).
  private(set) var lastRecorded: Int?

  func writeText(_ text: String) -> Bool {
    // The number this write makes is the one clearContents() returns. It is
    // taken from there, not read after the writes, so another app's change in
    // between can never be recorded as ours (F5).
    let cleared = pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else { return false }
    // Our own marker: the watcher then only moves the item to the top, and
    // only if it is already saved (a copy with the marker is never trusted).
    _ = pasteboard.setString(
      "1", forType: NSPasteboard.PasteboardType(ClipboardPolicy.ownMarkerType))
    // Recorded at once, on the main thread, before the watcher's next tick.
    if let ownChanges = ownChanges {
      let mine = cleared + NSPasteboardWriter.changesAfterClear
      ownChanges.record(mine)
      lastRecorded = mine
    }
    return true
  }
}

/// The real Mac. [hide] hides the picker window.
final class MacPastePlatform: PastePlatform {
  private let hide: () -> Void
  private let diag: (String, Int?) -> Void

  init(hide: @escaping () -> Void, diag: @escaping (String, Int?) -> Void = { _, _ in }) {
    self.hide = hide
    self.diag = diag
  }

  func hidePicker() { hide() }

  func frontmostPid() -> pid_t? {
    NSWorkspace.shared.frontmostApplication?.processIdentifier
  }

  func isRunning(_ pid: pid_t) -> Bool { MacPastePlatform.isAlive(pid) }

  static func isAlive(_ pid: pid_t) -> Bool {
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

  func forcePostEnabled() -> Bool {
    #if DEBUG
      // Off by default. Launch with `-KusungaForcePost YES` to turn it on.
      return UserDefaults.standard.bool(forKey: "KusungaForcePost")
    #else
      return false
    #endif
  }

  func pasteKeyCode() -> UInt16? {
    PasteKey.code(forV: PasteKey.translateInCurrentLayout)
  }

  func postPaste() {
    // The key that types "v" in the current layout (key code 9 on a US
    // layout), posted to the session with only the Command flag.
    guard let keyCode = pasteKeyCode() else { return }
    let state = CGEventSourceStateID.combinedSessionState
    let tap = CGEventTapLocation.cgSessionEventTap
    let source = CGEventSource(stateID: state)
    diag("postSourceState", Int(state.rawValue))
    if source == nil { diag("postSourceNil", nil) }
    diag("postTap", Int(tap.rawValue))
    var posted = 0
    for down in [true, false] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
      else {
        diag("postEventNil", down ? 1 : 0)
        continue
      }
      event.flags = .maskCommand
      event.post(tap: tap)
      posted += 1
    }
    diag("postSent", posted)
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
