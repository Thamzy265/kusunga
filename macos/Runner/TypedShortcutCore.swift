import Foundation

// M1.5 typed shortcuts: the buffer, the matcher and the skip rules
// (docs/design/typed-shortcuts.md, "The buffer", "Matching and skip rules";
// ADR 0004). Foundation only, so it is tested without the app
// (tool/test_mac_shortcuts.sh) and the C++ copy in
// windows/runner/typed_shortcut_policy.h follows the same rules.
//
// Privacy: typed keys exist only in `TypedBuffer`, in memory, at most 32
// characters, cleared after 5 s without a key and on every reset event. No
// type here logs, prints or describes what was typed; only a snippet id and a
// delete count leave this file.

/// What one key press means for the buffer.
enum TypedKey: Equatable {
  /// A key that typed these characters.
  case text(String)
  case backspace
  /// The cursor may have moved, or the key was a command: empty the buffer.
  case reset
  /// A key that types nothing and moves nothing (a function key, Shift).
  case ignore
}

/// Where and how the key arrived (skip rules 1 to 4 on the Mac).
struct TypedKeyContext: Equatable {
  /// macOS secure input is on (a password field). The tap gets no keys then.
  var secureInput = false
  /// The front app is Kusunga itself.
  var frontIsSelf = false
  /// The front app is on the ignore list.
  var frontIgnored = false
  /// The key was sent by other software, not the keyboard (PM decision D5).
  var injected = false
}

/// What the matcher decided. `skipped` carries a log code only.
enum TypedOutcome: Equatable {
  case none
  case matched(snippetId: Int, deleteCount: Int)
  case skipped(String)
}

/// The last characters typed, at most 32 (the longest allowed shortcut).
/// Never logged or described: `description` shows only the count.
final class TypedBuffer: CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  static let maxLength = 32
  static let idleMs = 5000

  private var scalars: [Unicode.Scalar] = []
  /// Per character: sent by other software (D5), not typed on the keyboard.
  private var fromSoftware: [Bool] = []
  private var lastKeyMs: Int?

  var count: Int { scalars.count }

  /// For the matcher and the tests only.
  var contents: [Unicode.Scalar] { scalars }
  var text: String { String(String.UnicodeScalarView(scalars)) }

  func add(_ text: String, nowMs: Int, injected: Bool = false) {
    for s in text.unicodeScalars {
      scalars.append(s)
      fromSoftware.append(injected)
    }
    if scalars.count > TypedBuffer.maxLength {
      let extra = scalars.count - TypedBuffer.maxLength
      scalars.removeFirst(extra)
      fromSoftware.removeFirst(extra)
    }
    lastKeyMs = nowMs
  }

  /// True if any of the last [length] characters came from other software.
  func lastHasInjected(_ length: Int) -> Bool {
    fromSoftware.suffix(length).contains(true)
  }

  func backspace(nowMs: Int) {
    if !scalars.isEmpty {
      scalars.removeLast()
      fromSoftware.removeLast()
    }
    lastKeyMs = nowMs
  }

  func clear() {
    // Overwrite before letting go, so the old characters are not left in the
    // array's storage.
    for i in scalars.indices { scalars[i] = " " }
    scalars.removeAll(keepingCapacity: false)
    fromSoftware.removeAll(keepingCapacity: false)
    lastKeyMs = nil
  }

  /// Empties the buffer if 5 s passed without a key. True if it did.
  @discardableResult
  func expireIfIdle(nowMs: Int) -> Bool {
    guard let last = lastKeyMs, nowMs - last >= TypedBuffer.idleMs else { return false }
    clear()
    return true
  }

  var description: String { "TypedBuffer(\(scalars.count))" }
  var debugDescription: String { description }
  var customMirror: Mirror { Mirror(self, children: ["count": scalars.count]) }
}

/// Shortcut → snippet id, from Dart (`setTable`). Only shortcuts that follow
/// the rules are kept, whatever Dart or the database sent.
struct ShortcutTable {
  private var byText: [String: Int] = [:]
  private(set) var longest = 0

  init(entries: [(Int, String)] = []) {
    for (id, shortcut) in entries where ShortcutTable.isValid(shortcut) {
      byText[shortcut] = id
      longest = max(longest, shortcut.unicodeScalars.count)
    }
  }

  var count: Int { byText.count }

  /// 2 to 32 characters, with no spaces, line breaks or control characters.
  static func isValid(_ shortcut: String) -> Bool {
    let scalars = shortcut.unicodeScalars
    guard scalars.count >= 2, scalars.count <= TypedBuffer.maxLength else { return false }
    return !scalars.contains { s in
      s.value <= 0x20 || (s.value >= 0x7F && s.value <= 0xA0)
        || s.properties.isWhitespace
    }
  }

  /// The longest shortcut the buffer ends with, and how many characters (as
  /// the user sees them) a replacement deletes.
  func match(_ buffer: [Unicode.Scalar]) -> (snippetId: Int, deleteCount: Int, length: Int)? {
    if buffer.count < 2 || longest == 0 { return nil }
    var length = min(buffer.count, longest)
    while length >= 2 {
      let tail = String(String.UnicodeScalarView(buffer[(buffer.count - length)...]))
      if let id = byText[tail] { return (id, tail.count, length) }
      length -= 1
    }
    return nil
  }
}

/// The buffer plus the table and the skip rules. One per app, used on the
/// main thread only.
final class TypedShortcutMatcher {
  private let buffer = TypedBuffer()
  private var table = ShortcutTable()

  var bufferCount: Int { buffer.count }
  var tableSize: Int { table.count }

  /// A new table (after any change to the snippets). Starts from an empty
  /// buffer so an old half-typed shortcut cannot finish a new one.
  func setTable(_ entries: [(Int, String)]) {
    table = ShortcutTable(entries: entries)
    buffer.clear()
  }

  /// Any reset event the platform sees (front app changed, secure input on,
  /// the switch turned off, a replacement).
  func reset() { buffer.clear() }

  /// Called on a timer: the buffer never outlives 5 s without a key.
  func tick(nowMs: Int) { buffer.expireIfIdle(nowMs: nowMs) }

  func handle(_ key: TypedKey, context: TypedKeyContext, nowMs: Int) -> TypedOutcome {
    buffer.expireIfIdle(nowMs: nowMs)
    switch key {
    case .ignore:
      return .none
    case .reset:
      buffer.clear()
      return .none
    case .backspace:
      buffer.backspace(nowMs: nowMs)
      return .none
    case .text(let text):
      buffer.add(text, nowMs: nowMs, injected: context.injected)
      guard let m = table.match(buffer.contents) else { return .none }
      // Skips keep the buffer (design note, "Matching and skip rules").
      // Keys from other software never fire a shortcut, not even when the
      // user types only its last key (D5).
      if buffer.lastHasInjected(m.length) { return .skipped("shortcutSkippedInjected") }
      if context.secureInput { return .skipped("shortcutSkippedPassword") }
      if context.frontIsSelf { return .none }
      if context.frontIgnored { return .skipped("shortcutSkippedIgnoredApp") }
      buffer.clear()
      return .matched(snippetId: m.snippetId, deleteCount: m.deleteCount)
    }
  }
}

/// Mac key codes (kVK_*) and what they mean for the buffer.
enum MacKeyClassifier {
  static let deleteKey: Int64 = 51
  /// Return, Tab, Escape, forward Delete, keypad Enter, the arrows, Home,
  /// End, Page Up and Page Down.
  static let resetKeys: Set<Int64> = [36, 48, 53, 117, 76, 123, 124, 125, 126, 115, 119, 116, 121]

  static func classify(keyCode: Int64, command: Bool, control: Bool, chars: String?) -> TypedKey {
    if command || control { return .reset }
    if keyCode == deleteKey { return .backspace }
    if resetKeys.contains(keyCode) { return .reset }
    guard let chars = chars, !chars.isEmpty else { return .ignore }
    for s in chars.unicodeScalars {
      // Control characters, and the private-use codes macOS gives function
      // and arrow keys (NSF1FunctionKey and so on).
      if s.value < 0x20 || s.value == 0x7F || (s.value >= 0xF700 && s.value <= 0xF8FF) {
        return .ignore
      }
    }
    return .text(chars)
  }
}
