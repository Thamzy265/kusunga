import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

/// M1.5 typed shortcuts on the Mac: a listen-only event tap (ListenEvent /
/// Input Monitoring, ADR 0003; never the Accessibility API), the matcher in
/// TypedShortcutCore.swift, and the replacement.
///
/// Method channel `com.wnasoni.kusunga/shortcuts` (see
/// lib/shortcuts/channel_typed_shortcuts_port.dart):
///  - Dart calls `setTable {entries: [{id, shortcut}]}`, `setIgnored
///    {appIds}`, `setEnabled {on}` and `status` (both answer a status name),
///    `replace {deleteCount, text}`, `runningApps`, `requestListenAccess` and
///    `openInputMonitoringSettings`;
///  - native calls `matched {snippetId, deleteCount}` and `statusChanged
///    {status}`.
/// Typed keys never leave the matcher's buffer (ADR 0004): no channel
/// message, log line or file carries one. The front app is known by pid and
/// bundle id, in memory only, and never logged.
final class TypedShortcutBridge {
  static let shared = TypedShortcutBridge()

  /// On every key Kusunga posts (`eventSourceUserData`), so the tap never
  /// feeds Kusunga's own Delete and Cmd+V back into the buffer.
  static let ownEventMarker: Int64 = 0x4B53_4E47_5459  // "KSNGTY"

  /// Asked once by Continue; after that macOS stops asking, so Continue
  /// opens System Settings instead (UI spec, explanation card).
  static let askedKey = "KusungaAskedInputMonitoring"

  private var channel: FlutterMethodChannel?
  private let matcher = TypedShortcutMatcher()
  private var ignored: Set<String> = []
  private var enabled = false
  private var status = "off"
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var timer: Timer?
  private var frontPid: pid_t?
  private var frontBundle: String?
  private var matchPid: pid_t?
  private var keysSinceMatch = 0
  private var observers: [NSObjectProtocol] = []
  private let ownPid = ProcessInfo.processInfo.processIdentifier

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.wnasoni.kusunga/shortcuts", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel

    let workspace = NSWorkspace.shared.notificationCenter
    observers.append(
      workspace.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        self?.frontChanged(app)
      })
    // Back in Kusunga: Input Monitoring may have been allowed in System
    // Settings meanwhile.
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self = self, self.enabled, self.status == "needsPermission" else { return }
        self.start()
      })
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "setTable":
      let rows = (args?["entries"] as? [[String: Any]]) ?? []
      let entries: [(Int, String)] = rows.compactMap { row in
        guard let id = row["id"] as? Int, let s = row["shortcut"] as? String else { return nil }
        return (id, s)
      }
      matcher.setTable(entries)
      result(nil)
    case "setIgnored":
      ignored = Set((args?["appIds"] as? [String]) ?? [])
      matcher.reset()
      result(nil)
    case "setEnabled":
      let on = (args?["on"] as? Bool) ?? false
      enabled = on
      if on { start() } else { stop(status: "off") }
      result(status)
    case "status":
      result(status)
    case "replace":
      guard let count = args?["deleteCount"] as? Int, count >= 1, count <= TypedBuffer.maxLength,
        let text = args?["text"] as? String
      else { return result(ReplaceResult.failed.rawValue) }
      result(replace(deleteCount: count, text: text).rawValue)
    case "runningApps":
      result(TypedShortcutBridge.runningApps())
    case "requestListenAccess":
      // Only the explanation card's Continue gets here (never on our own).
      let defaults = UserDefaults.standard
      if defaults.bool(forKey: TypedShortcutBridge.askedKey) {
        TypedShortcutBridge.openSettings()
        result(CGPreflightListenEventAccess())
      } else {
        defaults.set(true, forKey: TypedShortcutBridge.askedKey)
        result(CGRequestListenEventAccess())
      }
    case "openInputMonitoringSettings":
      TypedShortcutBridge.openSettings()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Watching

  private func setStatus(_ next: String) {
    if next == status { return }
    status = next
    channel?.invokeMethod("statusChanged", arguments: ["status": next])
  }

  /// Creates the tap only while the switch is on and Input Monitoring is
  /// allowed. Never asks: without the permission the status says so.
  private func start() {
    guard enabled else { return }
    if tap != nil { return setStatus(currentWatchingStatus()) }
    guard CGPreflightListenEventAccess() else { return setStatus("needsPermission") }

    let mask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
      | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: CGEventMask(mask),
        callback: { _, type, event, info in
          if let info = info {
            Unmanaged<TypedShortcutBridge>.fromOpaque(info).takeUnretainedValue()
              .onEvent(type: type, event: event)
          }
          return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      DiagLog.log("shortcutTapFailed", 0)
      return setStatus("failed")
    }
    self.tap = tap
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    self.source = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    frontChanged(NSWorkspace.shared.frontmostApplication)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.tick()
    }
    setStatus(currentWatchingStatus())
  }

  private func stop(status next: String) {
    timer?.invalidate()
    timer = nil
    if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
    matcher.reset()
    matchPid = nil
    setStatus(next)
  }

  private func currentWatchingStatus() -> String {
    IsSecureEventInputEnabled() ? "paused" : "on"
  }

  /// Every second: the 5 s idle clear, and secure input turning on or off.
  private func tick() {
    matcher.tick(nowMs: TypedShortcutBridge.nowMs())
    let next = currentWatchingStatus()
    if next == "paused" { matcher.reset() }
    if status == "on" || status == "paused" { setStatus(next) }
  }

  private func frontChanged(_ app: NSRunningApplication?) {
    frontPid = app?.processIdentifier
    frontBundle = app?.bundleIdentifier
    matcher.reset()
  }

  private func onEvent(type: CGEventType, event: CGEvent) {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // macOS turned the tap off: turn it on once more.
      matcher.reset()
      guard let tap = tap else { return }
      CGEvent.tapEnable(tap: tap, enable: true)
      if CGEvent.tapIsEnabled(tap: tap) {
        DiagLog.log("shortcutTapReenabled", nil)
      } else {
        DiagLog.log("shortcutTapFailed", 1)
        stop(status: "stopped")
      }
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      matcher.reset()
    case .keyDown:
      onKey(event)
    default:
      break
    }
  }

  private func onKey(_ event: CGEvent) {
    // Kusunga's own Delete and Cmd+V.
    if event.getIntegerValueField(.eventSourceUserData) == TypedShortcutBridge.ownEventMarker {
      return
    }
    if matchPid != nil { keysSinceMatch += 1 }
    let flags = event.flags
    var length = 0
    var units = [UniChar](repeating: 0, count: 8)
    event.keyboardGetUnicodeString(
      maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
    let chars = length > 0 ? String(utf16CodeUnits: units, count: length) : nil
    // The characters live only until the matcher has them.
    for i in units.indices { units[i] = 0 }
    let key = MacKeyClassifier.classify(
      keyCode: event.getIntegerValueField(.keyboardEventKeycode),
      command: flags.contains(.maskCommand), control: flags.contains(.maskControl), chars: chars)
    var context = TypedKeyContext()
    context.secureInput = IsSecureEventInputEnabled()
    context.frontIsSelf = frontPid == ownPid
    context.frontIgnored = frontBundle.map { ignored.contains($0) } ?? false
    // Keyboard events come from no process; anything else was sent by
    // software (PM decision D5).
    context.injected = event.getIntegerValueField(.eventSourceUnixProcessID) != 0
    switch matcher.handle(key, context: context, nowMs: TypedShortcutBridge.nowMs()) {
    case .none:
      break
    case .skipped(let code):
      DiagLog.log(code, nil)
    case .matched(let snippetId, let deleteCount):
      matchPid = frontPid
      keysSinceMatch = 0
      channel?.invokeMethod(
        "matched", arguments: ["snippetId": snippetId, "deleteCount": deleteCount])
    }
  }

  // MARK: Replacing

  private func replace(deleteCount: Int, text: String) -> ReplaceResult {
    defer {
      matchPid = nil
      keysSinceMatch = 0
      matcher.reset()
    }
    guard enabled, let pid = matchPid else { return .cancelled }
    let platform = MacReplacePlatform(keysSinceMatch: { [weak self] in self?.keysSinceMatch ?? 1 })
    return ReplaceFlow(platform: platform).run(deleteCount: deleteCount, text: text, matchPid: pid)
  }

  // MARK: Helpers

  static func nowMs() -> Int { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) }

  static func openSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    {
      NSWorkspace.shared.open(url)
    }
  }

  /// Regular apps that are running (they have a Dock icon), with a 32 pt
  /// icon as PNG. Kusunga itself is left out by Dart.
  static func runningApps() -> [[String: Any]] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
        let name = app.localizedName, !name.isEmpty
      else { return nil }
      var row: [String: Any] = ["appId": id, "name": name]
      if let icon = app.icon, let png = pngIcon(icon) {
        row["icon"] = FlutterStandardTypedData(bytes: png)
      } else {
        row["icon"] = NSNull()
      }
      return row
    }
  }

  private static func pngIcon(_ image: NSImage) -> Data? {
    let size = NSSize(width: 32, height: 32)
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
  }
}

/// The real Mac for `ReplaceFlow`.
final class MacReplacePlatform: ReplacePlatform {
  private let keys: () -> Int
  private let pasteboard = NSPasteboard.general

  init(keysSinceMatch: @escaping () -> Int) { keys = keysSinceMatch }

  func frontmostPid() -> Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
  func keysSinceMatch() -> Int { keys() }
  func canPostEvents() -> Bool { CGPreflightPostEventAccess() }

  func previousText() -> SavedClipboard? {
    let types = pasteboard.types?.map { $0.rawValue } ?? []
    guard let text = pasteboard.string(forType: .string) else { return nil }
    return SavedClipboard(
      text: text, markerTypes: types.filter { ClipboardPolicy.secretTypes.contains($0) })
  }

  private func post(keyCode: CGKeyCode, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
      else { continue }
      event.flags = flags
      event.setIntegerValueField(.eventSourceUserData, value: TypedShortcutBridge.ownEventMarker)
      event.post(tap: .cgSessionEventTap)
    }
  }

  func postBackspaces(_ n: Int) {
    for _ in 0..<n { post(keyCode: CGKeyCode(kVK_Delete), flags: []) }
  }

  /// The snippet is marked transient and concealed (nspasteboard.org), so
  /// other clipboard managers do not keep it, and recorded as Kusunga's own
  /// change, so Kusunga's history does not either.
  func writeSnippet(_ text: String) -> Int? {
    let cleared = pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else { return nil }
    for marker in ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType"] {
      _ = pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
    }
    let mine = cleared + NSPasteboardWriter.changesAfterClear
    OwnClipboardChanges.shared.record(mine)
    return mine
  }

  func postPaste() -> Bool {
    guard let v = PasteKey.code(forV: PasteKey.translateInCurrentLayout) else { return false }
    post(keyCode: CGKeyCode(v), flags: .maskCommand)
    return true
  }

  func schedule(afterMs: Int, _ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(afterMs), execute: work)
  }

  func changeCount() -> Int { pasteboard.changeCount }

  func restore(_ saved: SavedClipboard) {
    let cleared = pasteboard.clearContents()
    _ = pasteboard.setString(saved.text, forType: .string)
    for marker in saved.markerTypes {
      _ = pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
    }
    OwnClipboardChanges.shared.record(cleared + NSPasteboardWriter.changesAfterClear)
  }
}
