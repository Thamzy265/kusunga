import XCTest

@testable import Kusunga

// M1.5 typed shortcuts: the native buffer, the matcher and the skip rules
// (docs/design/typed-shortcuts.md, "The buffer", "Matching and skip rules";
// ADR 0004). Foundation only, so this file also runs as a standalone bundle
// without launching Kusunga (tool/test_mac_shortcuts.sh).

private let plain = TypedKeyContext()

final class TypedBufferTests: XCTestCase {
  func testHoldsAtMost32CharactersAndDropsTheOldest() {
    let buffer = TypedBuffer()
    buffer.add("a", nowMs: 0)
    buffer.add(String(repeating: "b", count: 40), nowMs: 1)
    XCTAssertEqual(buffer.count, 32)
    XCTAssertEqual(buffer.text, String(repeating: "b", count: 32))
    XCTAssertEqual(TypedBuffer.maxLength, 32)
  }

  func testClearsAfterFiveSecondsWithoutAKey() {
    let buffer = TypedBuffer()
    buffer.add(";em", nowMs: 1000)
    XCTAssertFalse(buffer.expireIfIdle(nowMs: 5999))
    XCTAssertEqual(buffer.count, 3)
    XCTAssertTrue(buffer.expireIfIdle(nowMs: 6000))
    XCTAssertEqual(buffer.count, 0)
    XCTAssertEqual(TypedBuffer.idleMs, 5000)
  }

  func testBackspaceRemovesTheLastCharacter() {
    let buffer = TypedBuffer()
    buffer.add(";emx", nowMs: 0)
    buffer.backspace(nowMs: 1)
    XCTAssertEqual(buffer.text, ";em")
    buffer.clear()
    buffer.backspace(nowMs: 2)
    XCTAssertEqual(buffer.count, 0)
  }

  func testDescriptionNeverShowsTheText() {
    let buffer = TypedBuffer()
    buffer.add("secret", nowMs: 0)
    XCTAssertFalse(String(describing: buffer).contains("secret"))
    XCTAssertFalse(String(reflecting: buffer).contains("secret"))
  }
}

final class ShortcutTableTests: XCTestCase {
  func testRefusesShortcutsOutsideTheRules() {
    let table = ShortcutTable(entries: [
      (1, ";email"), (2, "e"), (3, String(repeating: ";", count: 33)), (4, "; x"),
      (5, ";a\tb"), (6, ";a\nb"), (7, ";ok"),
    ])
    XCTAssertEqual(table.count, 2)
  }

  func testLongestShortcutEndingTheBufferWins() {
    let table = ShortcutTable(entries: [(1, "il"), (2, ";email")])
    let m = table.match(Array(";email".unicodeScalars))
    XCTAssertEqual(m?.snippetId, 2)
    XCTAssertEqual(m?.deleteCount, 6)
  }

  func testCaseSensitive() {
    let table = ShortcutTable(entries: [(1, ";email")])
    XCTAssertNil(table.match(Array(";Email".unicodeScalars)))
  }

  func testDeleteCountIsInCharactersTheUserSees() {
    let table = ShortcutTable(entries: [(1, ";é😀")])
    XCTAssertEqual(table.match(Array(";é😀".unicodeScalars))?.deleteCount, 3)
  }
}

final class TypedShortcutMatcherTests: XCTestCase {
  private func matcher(_ entries: [(Int, String)] = [(7, ";email")]) -> TypedShortcutMatcher {
    let m = TypedShortcutMatcher()
    m.setTable(entries)
    return m
  }

  private func type(
    _ m: TypedShortcutMatcher, _ text: String, context: TypedKeyContext = plain, at: Int = 0
  ) -> [TypedOutcome] {
    text.map { m.handle(.text(String($0)), context: context, nowMs: at) }
  }

  func testFiresOnTheLastCharacter() {
    let m = matcher()
    let out = type(m, ";email")
    XCTAssertEqual(out.last, .matched(snippetId: 7, deleteCount: 6))
    XCTAssertEqual(Array(out.dropLast()), Array(repeating: .none, count: 5))
  }

  func testAMatchClearsTheBuffer() {
    let m = matcher()
    _ = type(m, ";email")
    XCTAssertEqual(m.bufferCount, 0)
  }

  func testEachResetEventEmptiesTheBuffer() {
    let m = matcher()
    _ = type(m, ";em")
    _ = m.handle(.reset, context: plain, nowMs: 0)
    XCTAssertEqual(m.bufferCount, 0)
    // The design's example: ;em, a click elsewhere, then ail never fires.
    XCTAssertEqual(type(m, "ail").last, TypedOutcome.none)
  }

  func testResetCallsFromThePlatformEmptyTheBuffer() {
    let m = matcher()
    _ = type(m, ";em")
    m.reset()
    XCTAssertEqual(m.bufferCount, 0)
  }

  func testIdleForFiveSecondsClearsBeforeTheNextKey() {
    let m = matcher()
    _ = type(m, ";ema", at: 0)
    XCTAssertEqual(m.handle(.text("il"), context: plain, nowMs: 5000), TypedOutcome.none)
  }

  func testTickClearsAnIdleBufferWithoutAKey() {
    let m = matcher()
    _ = type(m, ";ema", at: 0)
    m.tick(nowMs: 4999)
    XCTAssertEqual(m.bufferCount, 4)
    m.tick(nowMs: 5000)
    XCTAssertEqual(m.bufferCount, 0)
  }

  func testBackspaceCorrectsATypo() {
    let m = matcher()
    _ = type(m, ";emx")
    _ = m.handle(.backspace, context: plain, nowMs: 0)
    XCTAssertEqual(type(m, "ail").last, .matched(snippetId: 7, deleteCount: 6))
  }

  func testIgnoredKeysChangeNothing() {
    let m = matcher()
    _ = type(m, ";ema")
    XCTAssertEqual(m.handle(.ignore, context: plain, nowMs: 0), TypedOutcome.none)
    XCTAssertEqual(type(m, "il").last, .matched(snippetId: 7, deleteCount: 6))
  }

  func testSecureInputSkipsWithoutClearing() {
    let m = matcher()
    var ctx = plain
    ctx.secureInput = true
    XCTAssertEqual(type(m, ";email", context: ctx).last, .skipped("shortcutSkippedPassword"))
    XCTAssertEqual(m.bufferCount, 6)
  }

  func testKusungaItselfNeverFires() {
    let m = matcher()
    var ctx = plain
    ctx.frontIsSelf = true
    XCTAssertEqual(type(m, ";email", context: ctx).last, TypedOutcome.none)
  }

  func testIgnoredAppSkips() {
    let m = matcher()
    var ctx = plain
    ctx.frontIgnored = true
    XCTAssertEqual(type(m, ";email", context: ctx).last, .skipped("shortcutSkippedIgnoredApp"))
  }

  func testKeysSentBySoftwareNeverFire() {
    let m = matcher()
    var injected = plain
    injected.injected = true
    XCTAssertEqual(type(m, ";email", context: injected).last, .skipped("shortcutSkippedInjected"))
    m.reset()
    // Software types most of it, the user the last key: still no match.
    _ = type(m, ";emai", context: injected)
    XCTAssertEqual(type(m, "l").last, .skipped("shortcutSkippedInjected"))
    m.reset()
    // The user types it all after software typed something else: it fires.
    _ = type(m, "xyz", context: injected)
    XCTAssertEqual(type(m, ";email").last, .matched(snippetId: 7, deleteCount: 6))
  }

  func testANewTableReplacesTheOldAndClearsTheBuffer() {
    let m = matcher()
    _ = type(m, ";ema")
    m.setTable([(9, ";mob")])
    XCTAssertEqual(m.bufferCount, 0)
    XCTAssertEqual(type(m, ";email").last, TypedOutcome.none)
    XCTAssertEqual(type(m, ";mob").last, .matched(snippetId: 9, deleteCount: 4))
  }

  func testAnEmptyTableNeverMatches() {
    let m = matcher([])
    XCTAssertEqual(type(m, ";email").last, TypedOutcome.none)
  }

  func testMatchingIsFastEnough() {
    // 1,000 shortcuts of up to 32 characters; the design budget is 1 ms per
    // key (p99), so 1,000 keys must take well under a second.
    let entries = (0..<1000).map { (i: Int) -> (Int, String) in (i, ";s\(i)x") }
    let m = matcher(entries)
    let start = Date()
    for i in 0..<1000 { _ = m.handle(.text(i % 2 == 0 ? "a" : "b"), context: plain, nowMs: i) }
    XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
  }
}

final class MacKeyClassifierTests: XCTestCase {
  func testPrintableCharactersAreText() {
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 0, command: false, control: false, chars: "a"), .text("a"))
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 41, command: false, control: false, chars: ";"), .text(";"))
  }

  func testDeleteIsBackspace() {
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 51, command: false, control: false, chars: "\u{7F}"), .backspace)
  }

  func testNavigationAndEditingKeysReset() {
    // Return, Tab, Escape, forward Delete, keypad Enter, arrows, Home, End,
    // Page Up, Page Down.
    for code: Int64 in [36, 48, 53, 117, 76, 123, 124, 125, 126, 115, 119, 116, 121] {
      XCTAssertEqual(
        MacKeyClassifier.classify(keyCode: code, command: false, control: false, chars: nil), .reset,
        "key \(code)")
    }
  }

  func testCommandOrControlReset() {
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 9, command: true, control: false, chars: "v"), .reset)
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 0, command: false, control: true, chars: "a"), .reset)
  }

  func testNoCharacterOrAControlCharacterIsIgnored() {
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 122, command: false, control: false, chars: nil), .ignore)
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 122, command: false, control: false, chars: ""), .ignore)
    XCTAssertEqual(
      MacKeyClassifier.classify(keyCode: 122, command: false, control: false, chars: "\u{F704}"), .ignore)
    XCTAssertEqual(MacKeyClassifier.classify(keyCode: 1, command: false, control: false, chars: "\u{1}"), .ignore)
  }
}
