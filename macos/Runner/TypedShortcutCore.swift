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

  /// How long until the idle clear is due: 5 s after the last key, never
  /// negative. Nil when there is nothing to clear (C9).
  func msUntilIdleClear(nowMs: Int) -> Int? {
    guard !scalars.isEmpty, let last = lastKeyMs else { return nil }
    return max(0, last + TypedBuffer.idleMs - nowMs)
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

  /// When the platform's one-shot timer should call `tick` next: exactly
  /// 5 s after the last key, or nil for no timer (C9).
  func msUntilIdleClear(nowMs: Int) -> Int? { buffer.msUntilIdleClear(nowMs: nowMs) }

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

/// The match Dart may still answer with `replace` (C2): its id, the app it
/// happened in and how much the user did since (any of it cancels). Only
/// the newest match is valid: a newer one makes older ids worthless, so a
/// late `replace` for an older match never deletes text. The id is an
/// opaque counter, never anything typed. Main thread only.
final class PendingMatch {
  /// Ids stay in 23 bits, the same range as on Windows.
  static let maxId = 0x7F_FFFF

  private var lastId: Int
  private var current: (id: Int, target: Int32)?
  private var inputs = 0

  init(lastId: Int = 0) { self.lastId = lastId }

  /// A new match in the app [target]; answers its id.
  @discardableResult
  func begin(target: Int32) -> Int {
    lastId = lastId >= PendingMatch.maxId ? 1 : lastId + 1
    current = (lastId, target)
    inputs = 0
    return lastId
  }

  /// A key or a mouse press by the user after the match.
  func noteInput() {
    if current != nil { inputs += 1 }
  }

  /// The app and the input count, if [id] is the newest match.
  func peek(_ id: Int) -> (target: Int32, inputs: Int)? {
    guard let c = current, c.id == id else { return nil }
    return (c.target, inputs)
  }

  /// [id] was answered: nothing is pending unless a newer match came.
  func end(_ id: Int) {
    if current?.id == id { clear() }
  }

  func clear() {
    current = nil
    inputs = 0
  }
}

/// What the platform's input events mean beyond the buffer.
enum TypedShortcutInput {
  /// Any mouse button press (C5): the cursor may have moved, so the buffer
  /// empties, and a match still waiting for its replacement counts it as
  /// input, which cancels the replacement.
  static func mouseDown(matcher: TypedShortcutMatcher, pending: PendingMatch) {
    matcher.reset()
    pending.noteInput()
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

// MARK: - Replacing (design note, "Replacing"; PM decision D2 A)

/// The clipboard text from before a replacement, kept in memory for 0.5 s
/// so it can be put back. [markerTypes] are the nspasteboard.org privacy
/// markers it had (a password manager's copy stays concealed). Never
/// described or logged.
struct SavedClipboard: Equatable, CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  let text: String
  let markerTypes: [String]

  var description: String { "SavedClipboard" }
  var debugDescription: String { description }
  var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One clipboard write: the text and its marker types. The platform writes
/// them as one pasteboard item in one call, so no app can read the text
/// before its markers are there (C6). Never described or logged.
struct ClipboardContent: Equatable, CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  let text: String
  let markerTypes: [String]

  /// The snippet a shortcut pastes: transient and concealed, so other
  /// clipboard managers do not keep it.
  static func snippet(_ text: String) -> ClipboardContent {
    ClipboardContent(
      text: text,
      markerTypes: ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType"])
  }

  /// The previous text put back, with the privacy markers it had.
  static func restore(_ saved: SavedClipboard) -> ClipboardContent {
    ClipboardContent(text: saved.text, markerTypes: saved.markerTypes)
  }

  var description: String { "ClipboardContent" }
  var debugDescription: String { description }
  var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Whether the clipboard from before a replacement may be put back (design
/// note, "Replacing" step 4): only when every type on it was plain text or a
/// marker. Anything else (rich text, HTML, an image, files) leaves the
/// snippet on the clipboard, because Kusunga only puts back text (C4).
enum RestorableClipboard {
  static let textTypes: Set<String> = [
    "public.utf8-plain-text", "NSStringPboardType", "public.utf16-plain-text",
    "public.utf16-external-plain-text", "public.plain-text",
  ]

  /// nspasteboard.org privacy markers: kept on the text that is put back,
  /// so a password manager's copy stays concealed. The same list as
  /// ClipboardPolicy.secretTypes (ClipboardWatcher.swift).
  static let privacyMarkers = [
    "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
    "org.nspasteboard.AutoGeneratedType",
  ]

  /// Markers that say nothing about the content: the privacy markers, the
  /// copying app (nspasteboard.org) and Kusunga's own marker.
  static let markerTypes: Set<String> = Set(privacyMarkers).union([
    "org.nspasteboard.source", "com.wnasoni.kusunga.self",
  ])

  /// Decided from the types alone, before any text is read.
  static func canRestore(types: [String]) -> Bool {
    types.contains { textTypes.contains($0) }
      && types.allSatisfy { textTypes.contains($0) || markerTypes.contains($0) }
  }

  static func saved(text: String?, types: [String]) -> SavedClipboard? {
    guard canRestore(types: types), let text = text else { return nil }
    return SavedClipboard(text: text, markerTypes: privacyMarkers.filter { types.contains($0) })
  }
}

/// What a replacement needs from the Mac, so the order and the safety
/// checks are tested without one.
protocol ReplacePlatform: AnyObject {
  func frontmostPid() -> Int32?
  /// Keys the user typed since the match (any of them cancels).
  func keysSinceMatch() -> Int
  /// `CGPreflightPostEventAccess()`: never prompts.
  func canPostEvents() -> Bool
  /// The clipboard text now, or nil if the clipboard holds no text or
  /// anything besides text and markers (`RestorableClipboard`).
  func previousText() -> SavedClipboard?
  /// Posts [n] Delete keys carrying Kusunga's marker.
  func postBackspaces(_ n: Int)
  /// Writes the snippet marked transient and concealed, and records the
  /// change as Kusunga's own (not added to history). Answers the change
  /// count, or nil if it could not be written.
  func writeSnippet(_ text: String) -> Int?
  /// Posts Cmd+V carrying Kusunga's marker. False if no key types "v".
  func postPaste() -> Bool
  func schedule(afterMs: Int, _ work: @escaping () -> Void)
  func changeCount() -> Int
  /// Writes [saved] back, as Kusunga's own change.
  func restore(_ saved: SavedClipboard)
}

/// The answers to Dart (lib/shortcuts/channel_typed_shortcuts_port.dart).
enum ReplaceResult: String {
  case replaced
  case cancelled
  case copied
  case failed
}

/// Check that nothing moved since the match, write the snippet, delete the
/// code, paste, then put the previous clipboard text back after 0.5 s if
/// nobody copied anything else meanwhile.
final class ReplaceFlow {
  static let restoreDelayMs = 500

  private let platform: ReplacePlatform
  /// A restore still waiting: what it will put back, and the change count of
  /// the snippet it follows. A second shortcut within 0.5 s takes it over,
  /// so the user's own text comes back, not the first snippet. Only this
  /// holds the previous text; it is let go on every path that puts nothing
  /// back (C3).
  private var pending: (saved: SavedClipboard, mine: Int)?

  init(platform: ReplacePlatform) { self.platform = platform }

  /// True while the previous text is kept for a restore (tests).
  var hasPendingRestore: Bool { pending != nil }

  func run(deleteCount: Int, text: String, matchPid: Int32) -> ReplaceResult {
    // Another app in front, or more keys typed: deleting now could remove
    // text that is not the shortcut.
    guard platform.frontmostPid() == matchPid, platform.keysSinceMatch() == 0 else {
      return .cancelled
    }
    guard platform.canPostEvents() else {
      // No keys can be sent: the code stays, and the user pastes (M1.3).
      return platform.writeSnippet(text) == nil ? .failed : .copied
    }
    let earlier = pending
    pending = nil
    // The user's own text from a restore still waiting, or the clipboard now.
    let reused = earlier.map { platform.changeCount() == $0.mine } ?? false
    var previous = reused ? earlier?.saved : platform.previousText()
    var handedOver = false
    defer {
      // Every exit that schedules no restore lets go of the previous text.
      if !handedOver { previous = nil }
    }
    // The snippet first: if it can't be written, nothing is deleted and the
    // code stays where the user typed it (C3).
    guard let mine = platform.writeSnippet(text) else {
      // An earlier restore still waiting keeps the user's text.
      if reused { pending = earlier }
      return .failed
    }
    platform.postBackspaces(deleteCount)
    guard platform.postPaste() else { return .copied }
    if let saved = previous {
      pending = (saved, mine)
      handedOver = true
      platform.schedule(afterMs: ReplaceFlow.restoreDelayMs) { [self, platform] in
        // A newer shortcut took the restore over.
        guard let waiting = self.pending, waiting.mine == mine else { return }
        self.pending = nil
        // The user copied something else in the meantime: keep that.
        guard platform.changeCount() == mine else { return }
        platform.restore(waiting.saved)
      }
    }
    return .replaced
  }
}

extension ReplaceFlow {
  /// Replaces for [matchId] only if it is still the newest match (C2): an
  /// answer for an older match is cancelled and sends nothing. The match
  /// ends either way.
  func run(matchId: Int, deleteCount: Int, text: String, pending: PendingMatch)
    -> ReplaceResult
  {
    guard let match = pending.peek(matchId) else { return .cancelled }
    defer { pending.end(matchId) }
    return run(deleteCount: deleteCount, text: text, matchPid: match.target)
  }
}
