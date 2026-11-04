import Carbon.HIToolbox
import Cocoa

enum HotKeyRegistration: Equatable {
  case ok(Int)
  /// Another app owns the combination.
  case taken
  case failed(String)
}

/// The part of the system the registry uses, so its rules are testable.
protocol HotKeyBackend: AnyObject {
  func register(keyCode: UInt32, modifiers: UInt32) -> HotKeyRegistration
  func unregister(_ handle: Int)
}

/// Turns the key and modifier names of the Dart side (lib/picker/shortcut.dart)
/// into Carbon codes.
enum HotKeyMap {
  // US-layout key codes (kVK_ANSI_*): the Mac registers a key position.
  private static let codes: [String: UInt32] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "space": 49,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
  ]

  static func keyCode(for name: String) -> UInt32? { codes[name] }

  static let cmd: UInt32 = 0x0100
  static let shift: UInt32 = 0x0200
  static let option: UInt32 = 0x0800
  static let control: UInt32 = 0x1000

  /// nil if any name is unknown.
  static func carbonModifiers(_ names: [String]) -> UInt32? {
    var flags: UInt32 = 0
    for name in names {
      switch name {
      case "meta": flags |= cmd
      case "shift": flags |= shift
      case "alt": flags |= option
      case "ctrl": flags |= control
      default: return nil
      }
    }
    return flags
  }
}

/// Holds the one global shortcut. A new shortcut is registered before the old
/// one is released, so a refused one never leaves the user without a shortcut.
final class HotKeyRegistry {
  private let backend: HotKeyBackend
  private var current: (handle: Int, key: UInt32, modifiers: UInt32)?

  /// Called when the shortcut is pressed.
  var onPress: (() -> Void)?

  init(backend: HotKeyBackend) {
    self.backend = backend
  }

  /// Answers "ok", "taken" or "invalid" (the answers Dart expects).
  func set(key: String, modifiers: [String]) -> String {
    guard let code = HotKeyMap.keyCode(for: key),
      let mask = HotKeyMap.carbonModifiers(modifiers),
      mask & (HotKeyMap.cmd | HotKeyMap.control | HotKeyMap.option) != 0
    else { return "invalid" }

    if let c = current, c.key == code, c.modifiers == mask { return "ok" }

    switch backend.register(keyCode: code, modifiers: mask) {
    case .ok(let handle):
      if let old = current { backend.unregister(old.handle) }
      current = (handle, code, mask)
      return "ok"
    case .taken:
      return "taken"
    case .failed:
      return "invalid"
    }
  }

  func clear() {
    if let old = current { backend.unregister(old.handle) }
    current = nil
  }

  func handlePress(handle: Int) {
    guard let c = current, c.handle == handle else { return }
    onPress?()
  }
}

/// Carbon `RegisterEventHotKey`: needs no permission and works in the App
/// Sandbox (ADR 0003).
final class CarbonHotKeyBackend: HotKeyBackend {
  /// Called with the handle of the shortcut that was pressed.
  var onPress: ((Int) -> Void)?

  private var refs: [Int: EventHotKeyRef] = [:]
  private var nextId: UInt32 = 1
  private var handler: EventHandlerRef?

  func register(keyCode: UInt32, modifiers: UInt32) -> HotKeyRegistration {
    installHandlerIfNeeded()
    let id = EventHotKeyID(signature: OSType(0x4B53_4E47), id: nextId)  // 'KSNG'
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    if status == OSStatus(eventHotKeyExistsErr) { return .taken }
    guard status == noErr, let ref = ref else { return .failed("\(status)") }
    let handle = Int(nextId)
    nextId += 1
    refs[handle] = ref
    return .ok(handle)
  }

  func unregister(_ handle: Int) {
    if let ref = refs.removeValue(forKey: handle) { UnregisterEventHotKey(ref) }
  }

  private func installHandlerIfNeeded() {
    if handler != nil { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event = event, let userData = userData else { return noErr }
        var hotKeyId = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
        if status == noErr {
          let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(userData).takeUnretainedValue()
          backend.onPress?(Int(hotKeyId.id))
        }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }
}
