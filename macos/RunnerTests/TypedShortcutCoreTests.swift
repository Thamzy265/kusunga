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

// MARK: - Replacement (design note, "Replacing"; PM decision D2 A)

final class FakeReplacePlatform: ReplacePlatform {
  var log: [String] = []
  var front: Int32? = 100
  var keysAfterMatch = 0
  var canPost = true
  var previous: SavedClipboard? = SavedClipboard(text: "what I copied", markerTypes: [])
  var writeOk = true
  var pasteKeyFound = true
  var count = 10
  var scheduled: [(Int, () -> Void)] = []
  var restored: [SavedClipboard] = []

  func frontmostPid() -> Int32? { front }
  func keysSinceMatch() -> Int { keysAfterMatch }
  func canPostEvents() -> Bool { canPost }
  func previousText() -> SavedClipboard? {
    log.append("readPrevious")
    return previous
  }
  func postBackspaces(_ n: Int) { log.append("backspace×\(n)") }
  func writeSnippet(_ text: String) -> Int? {
    log.append("write")
    guard writeOk else { return nil }
    count += 1
    return count
  }
  func postPaste() -> Bool {
    log.append("paste")
    return pasteKeyFound
  }
  func schedule(afterMs: Int, _ work: @escaping () -> Void) { scheduled.append((afterMs, work)) }
  func changeCount() -> Int { count }
  func restore(_ saved: SavedClipboard) {
    log.append("restore")
    restored.append(saved)
    count += 1
  }
}

final class ReplaceFlowTests: XCTestCase {
  private func run(_ p: FakeReplacePlatform, matchPid: Int32 = 100) -> ReplaceResult {
    ReplaceFlow(platform: p).run(deleteCount: 6, text: "will@example.com", matchPid: matchPid)
  }

  func testWritesTheSnippetThenDeletesTheCodeAndPastesInThatOrder() {
    // C3: the code is deleted only once the snippet is on the clipboard.
    let p = FakeReplacePlatform()
    XCTAssertEqual(run(p), .replaced)
    XCTAssertEqual(p.log, ["readPrevious", "write", "backspace×6", "paste"])
  }

  func testPutsThePreviousTextBackAfterHalfASecond() {
    let p = FakeReplacePlatform()
    _ = run(p)
    XCTAssertEqual(p.scheduled.count, 1)
    XCTAssertEqual(p.scheduled[0].0, 500)
    p.scheduled[0].1()
    XCTAssertEqual(p.restored, [SavedClipboard(text: "what I copied", markerTypes: [])])
  }

  func testKeepsThePreviousPrivacyMarkers() {
    let p = FakeReplacePlatform()
    p.previous = SavedClipboard(text: "pw", markerTypes: ["org.nspasteboard.ConcealedType"])
    _ = run(p)
    p.scheduled[0].1()
    XCTAssertEqual(p.restored.first?.markerTypes, ["org.nspasteboard.ConcealedType"])
  }

  func testNothingIsPutBackIfTheUserCopiedSomethingMeanwhile() {
    let p = FakeReplacePlatform()
    _ = run(p)
    p.count += 1  // another copy
    p.scheduled[0].1()
    XCTAssertTrue(p.restored.isEmpty)
  }

  func testAPreviousClipboardThatWasNotTextLeavesTheSnippet() {
    let p = FakeReplacePlatform()
    p.previous = nil
    XCTAssertEqual(run(p), .replaced)
    XCTAssertTrue(p.scheduled.isEmpty)
  }

  func testAnotherAppInFrontCancelsAndSendsNothing() {
    let p = FakeReplacePlatform()
    p.front = 200
    XCTAssertEqual(run(p), .cancelled)
    XCTAssertEqual(p.log, [])
  }

  func testKeysTypedAfterTheMatchCancel() {
    let p = FakeReplacePlatform()
    p.keysAfterMatch = 1
    XCTAssertEqual(run(p), .cancelled)
    XCTAssertEqual(p.log, [])
  }

  func testWithoutPostPermissionOnlyCopies() {
    let p = FakeReplacePlatform()
    p.canPost = false
    XCTAssertEqual(run(p), .copied)
    XCTAssertEqual(p.log, ["write"])
    XCTAssertTrue(p.scheduled.isEmpty, "the snippet stays for the user to paste")
  }

  func testNoKeyForVLeavesTheSnippetOnTheClipboard() {
    let p = FakeReplacePlatform()
    p.pasteKeyFound = false
    XCTAssertEqual(run(p), .copied)
    XCTAssertTrue(p.scheduled.isEmpty)
  }

  func testAFailedWriteIsReported() {
    let p = FakeReplacePlatform()
    p.writeOk = false
    XCTAssertEqual(run(p), .failed)
    XCTAssertFalse(p.log.contains("paste"))
  }

  func testAFailedWriteLeavesTheCodeAndForgetsThePreviousText() {
    // C3: nothing is deleted when the snippet could not be written, and the
    // text read for a restore is not kept.
    let p = FakeReplacePlatform()
    p.writeOk = false
    let flow = ReplaceFlow(platform: p)
    XCTAssertEqual(
      flow.run(deleteCount: 6, text: "will@example.com", matchPid: 100), .failed)
    XCTAssertFalse(p.log.contains { $0.hasPrefix("backspace") })
    XCTAssertFalse(flow.hasPendingRestore)
    XCTAssertTrue(p.scheduled.isEmpty)
  }

  func testThePreviousTextIsForgottenOnEveryExitWithoutARestore() {
    let p = FakeReplacePlatform()
    p.pasteKeyFound = false
    let flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 6, text: "x", matchPid: 100), .copied)
    XCTAssertFalse(flow.hasPendingRestore)

    let q = FakeReplacePlatform()
    let replaced = ReplaceFlow(platform: q)
    XCTAssertEqual(replaced.run(deleteCount: 6, text: "x", matchPid: 100), .replaced)
    XCTAssertTrue(replaced.hasPendingRestore, "kept for the restore in 0.5 s")
    q.scheduled[0].1()
    XCTAssertFalse(replaced.hasPendingRestore, "forgotten once put back")

    let r = FakeReplacePlatform()
    let moved = ReplaceFlow(platform: r)
    _ = moved.run(deleteCount: 6, text: "x", matchPid: 100)
    r.count += 1  // the user copied something else
    r.scheduled[0].1()
    XCTAssertFalse(moved.hasPendingRestore, "forgotten when not put back")
    XCTAssertTrue(r.restored.isEmpty)
  }

  func testTwoShortcutsWithinHalfASecondPutBackTheFirstClipboardNotASnippet() {
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 6, text: "first", matchPid: 100), .replaced)
    // The clipboard now holds the first snippet; a second shortcut follows.
    p.previous = SavedClipboard(text: "first", markerTypes: ["org.nspasteboard.ConcealedType"])
    XCTAssertEqual(flow.run(deleteCount: 4, text: "second", matchPid: 100), .replaced)
    p.scheduled[0].1()  // the first restore: the clipboard moved on, nothing
    XCTAssertTrue(p.restored.isEmpty)
    p.scheduled[1].1()
    XCTAssertEqual(p.restored, [SavedClipboard(text: "what I copied", markerTypes: [])])
  }

  func testSavedClipboardNeverDescribesItsText() {
    let saved = SavedClipboard(text: "secret", markerTypes: [])
    XCTAssertFalse(String(describing: saved).contains("secret"))
    XCTAssertFalse(String(reflecting: saved).contains("secret"))
  }
}

// MARK: - Tester edge cases (M1.5): every reset key, skip-rule order, the
// buffer bound, idle edges, characters and delete counts, replace races.

final class TypedShortcutEdgeTests: XCTestCase {
  private func matcher(_ entries: [(Int, String)] = [(7, ";email")]) -> TypedShortcutMatcher {
    let m = TypedShortcutMatcher()
    m.setTable(entries)
    return m
  }

  @discardableResult
  private func type(
    _ m: TypedShortcutMatcher, _ text: String, context: TypedKeyContext = plain, at: Int = 0
  ) -> TypedOutcome {
    var last = TypedOutcome.none
    for ch in text { last = m.handle(.text(String(ch)), context: context, nowMs: at) }
    return last
  }

  // Reset events -------------------------------------------------------

  /// Each key that moves the cursor or is a command must break a half-typed
  /// shortcut: ";em", the key, "ail" never fires (design note, "The buffer").
  func testEveryResetKeyCodeBreaksAHalfTypedShortcut() {
    // Return, Tab, Escape, forward Delete, keypad Enter, 4 arrows, Home, End,
    // Page Up, Page Down.
    let codes: [Int64] = [36, 48, 53, 117, 76, 123, 124, 125, 126, 115, 119, 116, 121]
    XCTAssertEqual(Set(codes), MacKeyClassifier.resetKeys)
    for code in codes {
      let m = matcher()
      type(m, ";em")
      let key = MacKeyClassifier.classify(keyCode: code, command: false, control: false, chars: "\r")
      XCTAssertEqual(key, .reset, "key code \(code)")
      _ = m.handle(key, context: plain, nowMs: 1)
      XCTAssertEqual(m.bufferCount, 0, "key code \(code)")
      XCTAssertEqual(type(m, "ail"), .none, "key code \(code)")
    }
  }

  func testCommandOrControlResetEvenOnAKeyThatTypesNothing() {
    for (cmd, ctl) in [(true, false), (false, true), (true, true)] {
      XCTAssertEqual(
        MacKeyClassifier.classify(keyCode: 0, command: cmd, control: ctl, chars: nil), .reset)
      XCTAssertEqual(
        MacKeyClassifier.classify(keyCode: 51, command: cmd, control: ctl, chars: nil), .reset,
        "Cmd+Delete deletes a line: not a plain Backspace")
    }
  }

  func testOptionAndShiftStillType() {
    // Option makes characters (Option+2 is the euro sign); it is not a reset.
    XCTAssertEqual(
      MacKeyClassifier.classify(keyCode: 19, command: false, control: false, chars: "€"),
      .text("€"))
    XCTAssertEqual(
      MacKeyClassifier.classify(keyCode: 0, command: false, control: false, chars: "A"), .text("A"))
  }

  func testFunctionAndArrowPrivateUseCharactersNeverEnterTheBuffer() {
    for v in [0xF700, 0xF704, 0xF72C, 0xF8FF] {
      let s = String(UnicodeScalar(v)!)
      XCTAssertEqual(
        MacKeyClassifier.classify(keyCode: 122, command: false, control: false, chars: s), .ignore)
    }
    // Just outside the private-use band is an ordinary character.
    XCTAssertEqual(
      MacKeyClassifier.classify(keyCode: 0, command: false, control: false, chars: "\u{F6FF}"),
      .text("\u{F6FF}"))
    XCTAssertEqual(
      MacKeyClassifier.classify(keyCode: 0, command: false, control: false, chars: "\u{F900}"),
      .text("\u{F900}"))
  }

  func testDeleteWithAnEmptyBufferStaysEmptyAndANewKeyStillWorks() {
    let m = matcher()
    for _ in 0..<5 { _ = m.handle(.backspace, context: plain, nowMs: 0) }
    XCTAssertEqual(m.bufferCount, 0)
    XCTAssertEqual(type(m, ";email"), .matched(snippetId: 7, deleteCount: 6))
  }

  func testResetThenFullShortcutFiresAgain() {
    let m = matcher()
    type(m, ";ema")
    _ = m.handle(.reset, context: plain, nowMs: 1)
    XCTAssertEqual(type(m, ";email", at: 2), .matched(snippetId: 7, deleteCount: 6))
  }

  // Idle edges ----------------------------------------------------------

  func testBackspaceCountsAsAKeyForTheIdleClock() {
    let m = matcher()
    type(m, ";emx", at: 0)
    _ = m.handle(.backspace, context: plain, nowMs: 4000)
    // 4.9 s after the Backspace, 8.9 s after the first key: still alive.
    XCTAssertEqual(type(m, "ail", at: 8900), .matched(snippetId: 7, deleteCount: 6))
  }

  func testAKeyThatTypesNothingDoesNotRefreshTheIdleClock() {
    let m = matcher()
    type(m, ";ema", at: 0)
    _ = m.handle(.ignore, context: plain, nowMs: 4900)
    XCTAssertEqual(type(m, "il", at: 5000), .none)
  }

  func testEachKeyRestartsTheFiveSecondClock() {
    let m = matcher()
    type(m, ";ema", at: 0)
    _ = m.handle(.text("i"), context: plain, nowMs: 4999)
    XCTAssertEqual(m.bufferCount, 5)
    XCTAssertEqual(
      m.handle(.text("l"), context: plain, nowMs: 4999 + 4999), .matched(snippetId: 7, deleteCount: 6))
    let n = matcher()
    type(n, ";emai", at: 0)
    XCTAssertEqual(n.handle(.text("l"), context: plain, nowMs: 5000), TypedOutcome.none)
  }

  // Skip rules -----------------------------------------------------------

  func testSkipPrecedenceIsInjectedThenPasswordThenSelfThenIgnored() {
    func outcome(_ c: TypedKeyContext) -> TypedOutcome {
      let m = matcher()
      return type(m, ";email", context: c)
    }
    var c = TypedKeyContext(secureInput: true, frontIsSelf: true, frontIgnored: true, injected: true)
    XCTAssertEqual(outcome(c), .skipped("shortcutSkippedInjected"))
    c.injected = false
    XCTAssertEqual(outcome(c), .skipped("shortcutSkippedPassword"))
    c.secureInput = false
    XCTAssertEqual(outcome(c), .none, "typing in Kusunga itself is silent, not logged")
    c.frontIsSelf = false
    XCTAssertEqual(outcome(c), .skipped("shortcutSkippedIgnoredApp"))
    c.frontIgnored = false
    XCTAssertEqual(outcome(c), .matched(snippetId: 7, deleteCount: 6))
  }

  func testASkipKeepsTheBufferSoCorrectingAndRetypingFiresOnceTheSkipEnds() {
    let m = matcher()
    var c = TypedKeyContext()
    c.frontIgnored = true
    XCTAssertEqual(type(m, ";email", context: c), .skipped("shortcutSkippedIgnoredApp"))
    XCTAssertEqual(m.bufferCount, 6)
    _ = m.handle(.backspace, context: plain, nowMs: 1)
    XCTAssertEqual(type(m, "l", at: 1), .matched(snippetId: 7, deleteCount: 6))
  }

  func testOneSoftwareKeyInsideTheShortcutBlocksIt() {
    for badIndex in 0..<6 {
      let m = matcher()
      var out = TypedOutcome.none
      for (i, ch) in ";email".enumerated() {
        var c = TypedKeyContext()
        c.injected = i == badIndex
        out = m.handle(.text(String(ch)), context: c, nowMs: 0)
      }
      XCTAssertEqual(out, .skipped("shortcutSkippedInjected"), "software key at \(badIndex)")
    }
  }

  func testSoftwareKeysBeforeTheShortcutDoNotBlockIt() {
    let m = matcher()
    var soft = TypedKeyContext()
    soft.injected = true
    type(m, "hello ", context: soft)
    XCTAssertEqual(type(m, ";email"), .matched(snippetId: 7, deleteCount: 6))
  }

  func testSoftwareKeysAreForgottenWhenBackspaced() {
    let m = matcher()
    var soft = TypedKeyContext()
    soft.injected = true
    type(m, ";emai", context: plain)
    type(m, "x", context: soft)
    _ = m.handle(.backspace, context: plain, nowMs: 0)
    XCTAssertEqual(type(m, "l"), .matched(snippetId: 7, deleteCount: 6))
  }

  func testNoCharacterOfTheMatchIsKeptAfterAMatchEvenIfItWasSkippedBefore() {
    let m = matcher()
    var c = TypedKeyContext()
    c.secureInput = true
    XCTAssertEqual(type(m, ";email", context: c), .skipped("shortcutSkippedPassword"))
    // Secure input ends; the platform resets on that event.
    m.reset()
    XCTAssertEqual(m.bufferCount, 0)
    XCTAssertEqual(type(m, "l"), .none)
  }

  // Buffer bound ------------------------------------------------------------

  func testAThirtyTwoCharacterShortcutFiresAfterLongJunk() {
    let code = ";" + String(repeating: "a", count: 31)
    let m = matcher([(9, code)])
    type(m, String(repeating: "z", count: 100))
    XCTAssertEqual(m.bufferCount, 32)
    XCTAssertEqual(type(m, code), .matched(snippetId: 9, deleteCount: 32))
  }

  func testAThirtyThreeCharacterShortcutIsRefusedNotTruncated() {
    let code = ";" + String(repeating: "a", count: 32)
    let m = matcher([(9, code)])
    XCTAssertEqual(m.tableSize, 0)
    XCTAssertEqual(type(m, code), .none)
  }

  func testTheBufferNeverExceeds32EvenForOneHugeKeyEvent() {
    let m = matcher()
    _ = m.handle(.text(String(repeating: "q", count: 500)), context: plain, nowMs: 0)
    XCTAssertEqual(m.bufferCount, 32)
  }

  func testAMultiCharacterKeyEventEndingInTheShortcutFires() {
    let m = matcher()
    XCTAssertEqual(
      m.handle(.text("xx;email"), context: plain, nowMs: 0), .matched(snippetId: 7, deleteCount: 6))
  }

  // Table rules -------------------------------------------------------------

  func testTheRulesAtTheEdges() {
    let ok = [
      String(repeating: "a", count: 32), "ab", "😀😀", ";é", "日本",
      String(repeating: "😀", count: 32),
    ]
    let bad = [
      "", "a", String(repeating: "a", count: 33), String(repeating: "😀", count: 33),
      "a b", "a\u{00A0}b", "a\u{0085}b", "a\u{2028}b", "a\u{3000}b", "a\u{1680}b", "a\u{202F}b",
      "a\u{0000}b", "a\u{007F}b", "a\r\nb", "a\u{000B}b", "a\u{000C}b", "\u{2009}ab",
    ]
    for s in ok { XCTAssertEqual(ShortcutTable(entries: [(1, s)]).count, 1, "ok: \(s.debugDescription)") }
    for s in bad { XCTAssertEqual(ShortcutTable(entries: [(1, s)]).count, 0, "bad: \(s.debugDescription)") }
  }

  /// The set of refused characters must be the same one the Dart editor
  /// refuses (lib/snippets/snippet_shortcut.dart) and the C++ copy refuses.
  func testRefusedCharacterSetMatchesTheDartRule() {
    func dartRefuses(_ r: UInt32) -> Bool {
      r < 0x20 || r == 0x20 || r == 0x7F || (r >= 0x80 && r <= 0xA0) || r == 0x1680
        || (r >= 0x2000 && r <= 0x200A) || r == 0x2028 || r == 0x2029 || r == 0x202F
        || r == 0x205F || r == 0x3000
    }
    for r in UInt32(0)...UInt32(0x10FFFF) {
      guard let s = UnicodeScalar(r) else { continue }
      let accepted = ShortcutTable(entries: [(1, "a" + String(s))]).count == 1
      XCTAssertEqual(accepted, !dartRefuses(r), "U+\(String(r, radix: 16))")
    }
  }

  func testTwoShortcutsWithTheSameTextKeepTheLastId() {
    let table = ShortcutTable(entries: [(1, ";x1"), (2, ";x1")])
    XCTAssertEqual(table.count, 1)
    XCTAssertEqual(table.match(Array(";x1".unicodeScalars))?.snippetId, 2)
  }

  /// A shortcut that sits inside another one (not at its start) fires first.
  /// Locks today's behaviour; see the finding in the hand-off.
  func testAShortcutInsideAnotherOneFiresBeforeTheLongerOneIsFinished() {
    let m = matcher([(1, "ma"), (2, ";email")])
    let outcomes = ";email".map { m.handle(.text(String($0)), context: plain, nowMs: 0) }
    XCTAssertEqual(outcomes[3], .matched(snippetId: 1, deleteCount: 2), "fires at the 'a'")
    XCTAssertFalse(outcomes.contains(.matched(snippetId: 2, deleteCount: 6)))
  }

  func testLongestWinsWhenTwoShortcutsEndTheSameWay() {
    let m = matcher([(1, "ab"), (2, "xab")])
    XCTAssertEqual(type(m, "xab"), .matched(snippetId: 2, deleteCount: 3))
    XCTAssertEqual(type(m, "yab"), .matched(snippetId: 1, deleteCount: 2))
  }

  func testCaseAndUnicodeAreExact() {
    let m = matcher([(1, ";Email"), (2, ";é")])
    XCTAssertEqual(type(m, ";email"), .none)
    // Swift compares strings by canonical equivalence, so "e" + combining
    // acute matches the precomposed shortcut here; the C++ copy compares
    // code points and does not (see the hand-off, cross-platform note).
    XCTAssertEqual(type(m, ";e\u{301}"), .matched(snippetId: 2, deleteCount: 2))
    XCTAssertEqual(type(m, ";é"), .matched(snippetId: 2, deleteCount: 2))
    XCTAssertEqual(type(m, ";Email"), .matched(snippetId: 1, deleteCount: 6))
  }

  // Delete counts (Mac: what the user sees; one Backspace removes one) -------

  func testDeleteCountsAreUserVisibleCharacters() {
    let cases: [(String, Int)] = [
      (";👍🏽", 2),  // skin tone: 3 scalars, 1 character
      (";🇬🇧", 2),  // flag: 2 scalars
      (";👨‍👩‍👧", 2),  // family with joiners: 5 scalars
      (";e\u{301}", 2),  // e + combining acute
      (";é", 2),
      (";日本", 3),
      (String(repeating: "😀", count: 32), 32),
    ]
    for (code, visible) in cases {
      let table = ShortcutTable(entries: [(1, code)])
      let m = table.match(Array(code.unicodeScalars))
      XCTAssertEqual(m?.deleteCount, visible, code)
      XCTAssertEqual(m?.length, code.unicodeScalars.count, code)
      XCTAssertGreaterThanOrEqual(m?.deleteCount ?? 0, 1)
      XCTAssertLessThanOrEqual(m?.deleteCount ?? 99, TypedBuffer.maxLength)
    }
  }

  func testBufferKeepsScalarsSoAZwjShortcutStillMatchesAfterTheBufferIsFull() {
    let code = ";👨‍👩‍👧"
    let m = matcher([(3, code)])
    type(m, String(repeating: "z", count: 40))
    XCTAssertEqual(m.handle(.text(code), context: plain, nowMs: 0), .matched(snippetId: 3, deleteCount: 2))
  }

  func testNothingTypedIsDescribedByTheMatcherTypes() {
    let b = TypedBuffer()
    b.add("hunter2", nowMs: 0)
    for text in [String(describing: b), String(reflecting: b), "\(Mirror(reflecting: b).children.map { "\($0.value)" })"] {
      XCTAssertFalse(text.contains("hunter"))
    }
    var dumped = ""
    dump(b, to: &dumped)
    XCTAssertFalse(dumped.contains("hunter"))
  }

  func testClearForgetsEveryCharacter() {
    let b = TypedBuffer()
    b.add("secret", nowMs: 0, injected: true)
    b.clear()
    XCTAssertEqual(b.count, 0)
    XCTAssertFalse(b.lastHasInjected(32))
    XCTAssertEqual(b.text, "")
  }
}

final class ReplaceFlowEdgeTests: XCTestCase {
  func testCancelledRunLeavesAPendingRestoreAlone() {
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 6, text: "first", matchPid: 100), .replaced)
    p.front = 200  // the user switched app before the second one
    XCTAssertEqual(flow.run(deleteCount: 4, text: "second", matchPid: 100), .cancelled)
    p.scheduled[0].1()
    XCTAssertEqual(p.restored.count, 1, "the user's text still comes back")
  }

  func testThreeShortcutsInARowRestoreTheUsersOwnTextOnce() {
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    for i in 0..<3 {
      XCTAssertEqual(flow.run(deleteCount: 3, text: "s\(i)", matchPid: 100), .replaced)
    }
    XCTAssertEqual(p.log.filter { $0 == "readPrevious" }.count, 1)
    for work in p.scheduled { work.1() }
    XCTAssertEqual(p.restored, [SavedClipboard(text: "what I copied", markerTypes: [])])
  }

  func testTheUserCopiesBetweenTwoShortcutsSoTheNewCopyIsKept() {
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    _ = flow.run(deleteCount: 3, text: "first", matchPid: 100)
    p.count += 1  // the user pressed Cmd+C
    p.previous = SavedClipboard(text: "new copy", markerTypes: [])
    _ = flow.run(deleteCount: 3, text: "second", matchPid: 100)
    for work in p.scheduled { work.1() }
    XCTAssertEqual(p.restored, [SavedClipboard(text: "new copy", markerTypes: [])])
  }

  func testAnEmptyOrNonTextPreviousClipboardSchedulesNoRestore() {
    let p = FakeReplacePlatform()
    p.previous = nil
    XCTAssertEqual(
      ReplaceFlow(platform: p).run(deleteCount: 3, text: "x", matchPid: 100), .replaced)
    XCTAssertTrue(p.scheduled.isEmpty)
    XCTAssertTrue(p.restored.isEmpty)
  }

  func testAnEmptyStringPreviousIsStillRestored() {
    let p = FakeReplacePlatform()
    p.previous = SavedClipboard(text: "", markerTypes: [])
    _ = ReplaceFlow(platform: p).run(deleteCount: 3, text: "x", matchPid: 100)
    p.scheduled[0].1()
    XCTAssertEqual(p.restored.count, 1)
  }

  func testNoFrontAppCancels() {
    let p = FakeReplacePlatform()
    p.front = nil
    XCTAssertEqual(
      ReplaceFlow(platform: p).run(deleteCount: 3, text: "x", matchPid: 100), .cancelled)
    XCTAssertTrue(p.log.isEmpty)
  }

  func testCancelledAndCopiedNeverTouchTheClipboardPreviousText() {
    let p = FakeReplacePlatform()
    p.canPost = false
    XCTAssertEqual(
      ReplaceFlow(platform: p).run(deleteCount: 3, text: "x", matchPid: 100), .copied)
    XCTAssertEqual(p.log, ["write"], "no Backspace, no paste, no read of the clipboard")
    XCTAssertTrue(p.scheduled.isEmpty)
  }

  func testPasteKeyMissingStillDeletedTheCodeAndKeepsTheSnippet() {
    let p = FakeReplacePlatform()
    p.pasteKeyFound = false
    XCTAssertEqual(
      ReplaceFlow(platform: p).run(deleteCount: 3, text: "x", matchPid: 100), .copied)
    XCTAssertTrue(p.scheduled.isEmpty, "the snippet stays so the user can paste it")
  }

  func testFailedWriteAfterAPendingRestoreNeverRestoresStaleText() {
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    _ = flow.run(deleteCount: 3, text: "first", matchPid: 100)
    p.writeOk = false
    XCTAssertEqual(flow.run(deleteCount: 3, text: "second", matchPid: 100), .failed)
    p.scheduled[0].1()
    // The first restore may put the user's text back only if the clipboard is
    // still the first snippet.
    XCTAssertLessThanOrEqual(p.restored.count, 1)
  }

  func testRestoreDelayIsExactlyHalfASecond() {
    XCTAssertEqual(ReplaceFlow.restoreDelayMs, 500)
  }
}

// MARK: - C4: the previous clipboard is put back only when it was all text
// (design note, "Replacing" step 4: anything else leaves the snippet).

final class RestorableClipboardTests: XCTestCase {
  func testPlainTextIsRestoredWithItsPrivacyMarkers() {
    XCTAssertEqual(
      RestorableClipboard.saved(
        text: "what I copied", types: ["public.utf8-plain-text", "NSStringPboardType"]),
      SavedClipboard(text: "what I copied", markerTypes: []))
    XCTAssertEqual(
      RestorableClipboard.saved(
        text: "pw",
        types: [
          "public.utf8-plain-text", "org.nspasteboard.ConcealedType",
          "org.nspasteboard.TransientType", "org.nspasteboard.source",
        ]),
      SavedClipboard(
        text: "pw",
        markerTypes: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]))
  }

  func testAnyOtherTypeLeavesTheSnippet() {
    for other in ["public.rtf", "public.html", "public.png", "public.file-url", "com.adobe.pdf"] {
      XCTAssertNil(
        RestorableClipboard.saved(text: "x", types: ["public.utf8-plain-text", other]), other)
    }
  }

  func testNoTextOrNoTypesIsNothingToRestore() {
    XCTAssertNil(RestorableClipboard.saved(text: nil, types: ["public.utf8-plain-text"]))
    XCTAssertNil(RestorableClipboard.saved(text: "x", types: []))
    XCTAssertNil(
      RestorableClipboard.saved(text: "x", types: ["org.nspasteboard.ConcealedType"]),
      "markers alone are not text")
  }

  func testOnlyTheTypesAreLookedAtBeforeTheText() {
    XCTAssertTrue(RestorableClipboard.canRestore(types: ["public.utf8-plain-text"]))
    XCTAssertFalse(RestorableClipboard.canRestore(types: ["public.utf8-plain-text", "public.rtf"]))
    XCTAssertEqual(
      RestorableClipboard.privacyMarkers,
      [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
      ])
  }
}

// MARK: - C6: one write holds the text and its markers together.

final class ClipboardContentTests: XCTestCase {
  func testTheSnippetIsTransientAndConcealed() {
    let c = ClipboardContent.snippet("will@example.com")
    XCTAssertEqual(c.text, "will@example.com")
    XCTAssertEqual(
      c.markerTypes, ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType"])
  }

  func testThePutBackTextKeepsItsOwnMarkersOnly() {
    let saved = SavedClipboard(text: "pw", markerTypes: ["org.nspasteboard.ConcealedType"])
    XCTAssertEqual(
      ClipboardContent.restore(saved),
      ClipboardContent(text: "pw", markerTypes: ["org.nspasteboard.ConcealedType"]))
    XCTAssertEqual(
      ClipboardContent.restore(SavedClipboard(text: "x", markerTypes: [])).markerTypes, [])
  }

  func testNeverDescribesItsText() {
    let c = ClipboardContent.snippet("secret")
    XCTAssertFalse(String(describing: c).contains("secret"))
    XCTAssertFalse(String(reflecting: c).contains("secret"))
  }
}

// MARK: - C2: a replacement says which match it answers; a newer match
// makes older ones invalid.

final class PendingMatchTests: XCTestCase {
  func testEachMatchGetsANewOpaqueId() {
    let p = PendingMatch()
    let a = p.begin(target: 100)
    let b = p.begin(target: 100)
    XCTAssertGreaterThan(a, 0)
    XCTAssertNotEqual(a, b)
    XCTAssertNil(p.peek(a), "a newer match makes the older one invalid")
    XCTAssertEqual(p.peek(b)?.target, 100)
    XCTAssertNil(p.peek(0))
    XCTAssertNil(p.peek(b + 1))
  }

  func testEndingAnOlderMatchLeavesTheNewerOne() {
    let p = PendingMatch()
    let a = p.begin(target: 100)
    let b = p.begin(target: 200)
    p.end(a)
    XCTAssertEqual(p.peek(b)?.target, 200)
    p.end(b)
    XCTAssertNil(p.peek(b))
  }

  func testInputsAreCountedFromTheMatch() {
    let p = PendingMatch()
    p.noteInput()  // nothing pending: not counted
    let a = p.begin(target: 1)
    XCTAssertEqual(p.peek(a)?.inputs, 0)
    p.noteInput()
    XCTAssertEqual(p.peek(a)?.inputs, 1)
    let b = p.begin(target: 1)
    XCTAssertEqual(p.peek(b)?.inputs, 0, "a new match starts from 0")
  }

  func testIdsStayPositiveAndSmallWhenTheCounterWraps() {
    let p = PendingMatch(lastId: PendingMatch.maxId - 1)
    XCTAssertEqual(p.begin(target: 1), PendingMatch.maxId)
    XCTAssertEqual(p.begin(target: 1), 1)
    XCTAssertEqual(PendingMatch.maxId, 0x7F_FFFF)
  }

  func testAReplaceForAnOlderMatchIsCancelledAndSendsNothing() {
    // Two quick matches: the first answer must not delete text.
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    let pending = PendingMatch()
    let first = pending.begin(target: 100)
    let second = pending.begin(target: 100)
    XCTAssertEqual(
      flow.run(matchId: first, deleteCount: 6, text: "will@example.com", pending: pending),
      .cancelled)
    XCTAssertEqual(p.log, [])
    XCTAssertEqual(
      flow.run(matchId: second, deleteCount: 4, text: "07700", pending: pending), .replaced)
    XCTAssertNil(pending.peek(second), "answered once")
    XCTAssertEqual(
      flow.run(matchId: second, deleteCount: 4, text: "07700", pending: pending), .cancelled)
  }

  func testTheMatchTargetIsTheAppItHappenedIn() {
    let p = FakeReplacePlatform()
    let pending = PendingMatch()
    let id = pending.begin(target: 200)
    XCTAssertEqual(
      ReplaceFlow(platform: p).run(matchId: id, deleteCount: 6, text: "x", pending: pending),
      .cancelled, "app 100 is in front now")
  }
}

// MARK: - C5: a mouse press after a match cancels its replacement.

final class MouseDownTests: XCTestCase {
  func testAClickBetweenTheMatchAndTheReplacementCancelsIt() {
    let matcher = TypedShortcutMatcher()
    matcher.setTable([(7, ";email")])
    let pending = PendingMatch()
    var id = 0
    for ch in ";email" {
      if case .matched = matcher.handle(.text(String(ch)), context: plain, nowMs: 0) {
        id = pending.begin(target: 100)
      }
    }
    XCTAssertGreaterThan(id, 0)
    TypedShortcutInput.mouseDown(matcher: matcher, pending: pending)
    XCTAssertEqual(pending.peek(id)?.inputs, 1)
    let p = FakeReplacePlatform()
    p.keysAfterMatch = pending.peek(id)?.inputs ?? 1
    XCTAssertEqual(
      ReplaceFlow(platform: p).run(matchId: id, deleteCount: 6, text: "x", pending: pending),
      .cancelled)
    XCTAssertEqual(p.log, [], "nothing deleted, nothing pasted")
  }

  func testAClickEmptiesTheBuffer() {
    let matcher = TypedShortcutMatcher()
    matcher.setTable([(7, ";email")])
    for ch in ";em" { _ = matcher.handle(.text(String(ch)), context: plain, nowMs: 0) }
    TypedShortcutInput.mouseDown(matcher: matcher, pending: PendingMatch())
    XCTAssertEqual(matcher.bufferCount, 0)
  }
}

// MARK: - C9: the buffer is cleared exactly 5 s after the last key, by a
// timer the platform sets from this deadline.

final class IdleDeadlineTests: XCTestCase {
  private func matcher() -> TypedShortcutMatcher {
    let m = TypedShortcutMatcher()
    m.setTable([(7, ";email")])
    return m
  }

  func testTheTimerIsDueFiveSecondsAfterTheLastKey() {
    let m = matcher()
    XCTAssertNil(m.msUntilIdleClear(nowMs: 0), "nothing typed: no timer")
    _ = m.handle(.text(";"), context: plain, nowMs: 1000)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 1000), 5000)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 3000), 3000)
    _ = m.handle(.text("e"), context: plain, nowMs: 3000)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 3000), 5000, "each key moves it")
    m.tick(nowMs: 7999)
    XCTAssertEqual(m.bufferCount, 2)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 7999), 1, "fired early: set again")
    m.tick(nowMs: 8000)
    XCTAssertEqual(m.bufferCount, 0)
    XCTAssertNil(m.msUntilIdleClear(nowMs: 8000), "cleared: no timer")
  }

  func testNeverNegativeAndGoneAfterAnyClear() {
    let m = matcher()
    _ = m.handle(.text(";"), context: plain, nowMs: 0)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 9000), 0)
    _ = m.handle(.reset, context: plain, nowMs: 100)
    XCTAssertNil(m.msUntilIdleClear(nowMs: 100))
    _ = m.handle(.text(";"), context: plain, nowMs: 200)
    _ = m.handle(.backspace, context: plain, nowMs: 300)
    XCTAssertNil(m.msUntilIdleClear(nowMs: 300), "empty again: nothing to clear")
    for ch in ";email" { _ = m.handle(.text(String(ch)), context: plain, nowMs: 400) }
    XCTAssertNil(m.msUntilIdleClear(nowMs: 400), "a match empties it")
  }

  func testAKeyThatTypesNothingDoesNotMoveTheDeadline() {
    let m = matcher()
    _ = m.handle(.text(";"), context: plain, nowMs: 0)
    _ = m.handle(.ignore, context: plain, nowMs: 4000)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 4000), 1000)
  }
}

// MARK: - Tester round 3: PendingMatch, restorable types, the idle deadline
// and every exit of a replacement (C2, C3, C4, C5, C9).

final class Round3EdgeTests: XCTestCase {
  // C2 ---------------------------------------------------------------------

  func testIdsWrapFromMaxToOneAndNeverZero() {
    let p = PendingMatch(lastId: PendingMatch.maxId - 2)
    XCTAssertEqual(p.begin(target: 1), PendingMatch.maxId - 1)
    XCTAssertEqual(p.begin(target: 1), PendingMatch.maxId)
    XCTAssertNil(p.peek(PendingMatch.maxId - 1))
    XCTAssertEqual(p.begin(target: 1), 1)
    XCTAssertNil(p.peek(PendingMatch.maxId), "the id from before the wrap is dead")
    XCTAssertNotNil(p.peek(1))
    XCTAssertEqual(PendingMatch(lastId: Int.max).begin(target: 1), 1)
    XCTAssertEqual(PendingMatch(lastId: PendingMatch.maxId + 1).begin(target: 1), 1)
    XCTAssertEqual(PendingMatch.maxId, 0x7F_FFFF)
  }

  func testIdsThatWereNeverGivenOutAreRefused() {
    let p = PendingMatch()
    let id = p.begin(target: 5)
    for bad in [0, -1, id + 1, id | 0x80_0000, Int.max, Int.min] {
      XCTAssertNil(p.peek(bad), "\(bad)")
    }
  }

  func testAReplaceForAnAlreadyAnsweredMatchSendsNothing() {
    let fake = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: fake)
    let pending = PendingMatch()
    let id = pending.begin(target: 100)
    XCTAssertEqual(
      flow.run(matchId: id, deleteCount: 6, text: "x", pending: pending), .replaced)
    let log = fake.log
    XCTAssertEqual(
      flow.run(matchId: id, deleteCount: 6, text: "x", pending: pending), .cancelled)
    XCTAssertEqual(fake.log, log, "a duplicate replace touches nothing")
  }

  func testAStaleIdAfterANewMatchIsCancelledAndTheNewOneStillWorks() {
    let fake = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: fake)
    let pending = PendingMatch()
    let old = pending.begin(target: 100)
    let new = pending.begin(target: 100)
    XCTAssertEqual(
      flow.run(matchId: old, deleteCount: 6, text: "old", pending: pending), .cancelled)
    XCTAssertTrue(fake.log.isEmpty)
    XCTAssertNotNil(pending.peek(new), "answering the old one must not end the new one")
    XCTAssertEqual(
      flow.run(matchId: new, deleteCount: 4, text: "new", pending: pending), .replaced)
  }

  func testANewMatchStartsItsInputCountAtZeroAndInputBeforeAnyMatchCountsNothing() {
    let p = PendingMatch()
    p.noteInput()
    let a = p.begin(target: 1)
    XCTAssertEqual(p.peek(a)?.inputs, 0)
    p.noteInput()
    p.noteInput()
    XCTAssertEqual(p.peek(a)?.inputs, 2)
    let b = p.begin(target: 2)
    XCTAssertEqual(p.peek(b)?.inputs, 0)
    XCTAssertEqual(p.peek(b)?.target, 2)
    p.end(a)
    XCTAssertNotNil(p.peek(b))
    p.end(b)
    p.noteInput()
    XCTAssertNil(p.peek(b))
  }

  func testTheMatchEndsEvenWhenTheReplaceIsCancelled() {
    let fake = FakeReplacePlatform()
    fake.front = 200
    let flow = ReplaceFlow(platform: fake)
    let pending = PendingMatch()
    let id = pending.begin(target: 100)
    XCTAssertEqual(
      flow.run(matchId: id, deleteCount: 6, text: "x", pending: pending), .cancelled)
    XCTAssertNil(pending.peek(id))
  }

  // C5 ---------------------------------------------------------------------

  func testAClickBeforeAnyMatchIsHarmlessAndAClickAfterTheAnswerChangesNothing() {
    let m = TypedShortcutMatcher()
    m.setTable([(7, ";email")])
    let pending = PendingMatch()
    TypedShortcutInput.mouseDown(matcher: m, pending: pending)  // no match yet
    let id = pending.begin(target: 100)
    let fake = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: fake)
    XCTAssertEqual(
      flow.run(matchId: id, deleteCount: 6, text: "x", pending: pending), .replaced)
    TypedShortcutInput.mouseDown(matcher: m, pending: pending)
    XCTAssertNil(pending.peek(id))
  }

  func testEveryClickBeforeTheReplaceCountsAndAnyOneCancels() {
    for clicks in 1...3 {
      let m = TypedShortcutMatcher()
      let pending = PendingMatch()
      let id = pending.begin(target: 100)
      for _ in 0..<clicks { TypedShortcutInput.mouseDown(matcher: m, pending: pending) }
      XCTAssertEqual(pending.peek(id)?.inputs, clicks)
    }
  }

  // C9 ---------------------------------------------------------------------

  func testIdleDeadlineAtTheEdges() {
    let m = TypedShortcutMatcher()
    m.setTable([(7, ";email")])
    _ = m.handle(.text(";"), context: plain, nowMs: 10_000)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 10_000), 5000)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 14_999), 1)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 15_000), 0)
    XCTAssertEqual(m.msUntilIdleClear(nowMs: 99_999), 0)
    m.tick(nowMs: 14_999)
    XCTAssertEqual(m.bufferCount, 1)
    m.tick(nowMs: 15_000)
    XCTAssertEqual(m.bufferCount, 0)
    XCTAssertNil(m.msUntilIdleClear(nowMs: 15_000))
  }

  func testTheDeadlineFollowsBackspaceAndSkippedMatchesAndDropsWhenEmpty() {
    let b = TypedShortcutMatcher()
    b.setTable([(7, ";email")])
    type(b, ";e", at: 0)
    _ = b.handle(.backspace, context: plain, nowMs: 3000)
    XCTAssertEqual(b.msUntilIdleClear(nowMs: 3000), 5000)
    _ = b.handle(.backspace, context: plain, nowMs: 3500)
    XCTAssertNil(b.msUntilIdleClear(nowMs: 3500), "empty buffer, no timer")

    let k = TypedShortcutMatcher()
    k.setTable([(7, ";email")])
    var ignored = TypedKeyContext()
    ignored.frontIgnored = true
    type(k, ";email", context: ignored, at: 2000)
    XCTAssertEqual(k.bufferCount, 6)
    XCTAssertEqual(k.msUntilIdleClear(nowMs: 2000), 5000)

    let j = TypedShortcutMatcher()
    j.setTable([(7, ";email")])
    var soft = TypedKeyContext()
    soft.injected = true
    _ = j.handle(.text(";"), context: soft, nowMs: 100)
    XCTAssertEqual(j.msUntilIdleClear(nowMs: 100), 5000)
    j.reset()
    XCTAssertNil(j.msUntilIdleClear(nowMs: 100))
  }

  @discardableResult
  private func type(
    _ m: TypedShortcutMatcher, _ text: String, context: TypedKeyContext = plain, at: Int = 0
  ) -> TypedOutcome {
    var last = TypedOutcome.none
    for ch in text { last = m.handle(.text(String(ch)), context: context, nowMs: at) }
    return last
  }

  // C4 ---------------------------------------------------------------------

  func testRestorableTypesAtTheEdges() {
    let utf8 = "public.utf8-plain-text"
    XCTAssertTrue(RestorableClipboard.canRestore(types: [utf8]))
    XCTAssertTrue(RestorableClipboard.canRestore(types: [utf8, utf8]))
    XCTAssertTrue(RestorableClipboard.canRestore(types: ["NSStringPboardType"]))
    XCTAssertTrue(RestorableClipboard.canRestore(
      types: ["org.nspasteboard.ConcealedType", utf8, "org.nspasteboard.source"]))
    XCTAssertTrue(RestorableClipboard.canRestore(types: [utf8, "com.wnasoni.kusunga.self"]))
    // Markers alone, or nothing, is nothing to put back.
    XCTAssertFalse(RestorableClipboard.canRestore(types: []))
    XCTAssertFalse(RestorableClipboard.canRestore(types: ["org.nspasteboard.ConcealedType"]))
    // Anything else blocks, even beside text and a marker.
    for other in ["public.html", "public.rtf", "public.png", "public.file-url",
      "com.apple.pasteboard.promised-file-url", "dyn.ah62d4rv4gu8y6y4grf0gn5xbrzw1gydcr7u1e3cq",
      "public.url", "public.utf8-plain-textX", "Public.UTF8-Plain-Text",
      "org.nspasteboard.concealedtype", " org.nspasteboard.ConcealedType"]
    {
      XCTAssertFalse(RestorableClipboard.canRestore(types: [utf8, other]), other)
      XCTAssertFalse(
        RestorableClipboard.canRestore(types: [utf8, "org.nspasteboard.ConcealedType", other]), other)
    }
  }

  func testOnlyThePrivacyMarkersAreKeptOnTheRestoredText() {
    let types = [
      "public.utf8-plain-text", "org.nspasteboard.ConcealedType", "org.nspasteboard.source",
      "com.wnasoni.kusunga.self", "org.nspasteboard.AutoGeneratedType",
    ]
    let saved = RestorableClipboard.saved(text: "secret", types: types)
    XCTAssertEqual(
      Set(saved?.markerTypes ?? []),
      ["org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType"])
    XCTAssertNil(RestorableClipboard.saved(text: nil, types: types), "no text read")
    XCTAssertNil(RestorableClipboard.saved(text: "x", types: ["public.png"]))
    XCTAssertEqual(
      RestorableClipboard.saved(text: "", types: ["public.utf8-plain-text"])?.text, "")
    XCTAssertEqual(
      Set(RestorableClipboard.privacyMarkers),
      ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType"])
  }

  func testTheSnippetAndTheRestoreAreEachOneContentWithOnlyTheirOwnMarkers() {
    XCTAssertEqual(
      Set(ClipboardContent.snippet("a").markerTypes),
      ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType"])
    let kept = SavedClipboard(text: "b", markerTypes: ["org.nspasteboard.ConcealedType"])
    XCTAssertEqual(ClipboardContent.restore(kept).markerTypes, ["org.nspasteboard.ConcealedType"])
    XCTAssertEqual(
      ClipboardContent.restore(SavedClipboard(text: "c", markerTypes: [])).markerTypes, [])
    for c in [ClipboardContent.snippet("hunter2"), ClipboardContent.restore(
      SavedClipboard(text: "hunter2", markerTypes: []))]
    {
      XCTAssertFalse(String(describing: c).contains("hunter"))
      XCTAssertFalse(String(reflecting: c).contains("hunter"))
      var dumped = ""
      dump(c, to: &dumped)
      XCTAssertFalse(dumped.contains("hunter"))
    }
  }

  // C3 ---------------------------------------------------------------------

  func testNoPendingRestoreRemainsAfterAnyExitThatPutsNothingBack() {
    // Write fails with a fresh read.
    var p = FakeReplacePlatform()
    p.writeOk = false
    var flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 3, text: "x", matchPid: 100), .failed)
    XCTAssertFalse(flow.hasPendingRestore)
    XCTAssertFalse(p.log.contains { $0.hasPrefix("backspace") }, "the code stays")
    XCTAssertTrue(p.scheduled.isEmpty)
    // No paste key.
    p = FakeReplacePlatform()
    p.pasteKeyFound = false
    flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 3, text: "x", matchPid: 100), .copied)
    XCTAssertFalse(flow.hasPendingRestore)
    // Cannot post keys.
    p = FakeReplacePlatform()
    p.canPost = false
    flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 3, text: "x", matchPid: 100), .copied)
    XCTAssertFalse(flow.hasPendingRestore)
    // Cancelled.
    p = FakeReplacePlatform()
    p.front = 5
    flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 3, text: "x", matchPid: 100), .cancelled)
    XCTAssertFalse(flow.hasPendingRestore)
    XCTAssertTrue(p.log.isEmpty)
    // Non-text before.
    p = FakeReplacePlatform()
    p.previous = nil
    flow = ReplaceFlow(platform: p)
    XCTAssertEqual(flow.run(deleteCount: 3, text: "x", matchPid: 100), .replaced)
    XCTAssertFalse(flow.hasPendingRestore)
  }

  func testThePendingRestoreEndsWhenItFiresOrIsOvertaken() {
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    _ = flow.run(deleteCount: 3, text: "a", matchPid: 100)
    XCTAssertTrue(flow.hasPendingRestore)
    p.scheduled[0].1()
    XCTAssertFalse(flow.hasPendingRestore)
    XCTAssertEqual(p.restored.count, 1)
    p.scheduled[0].1()  // a duplicate timer
    XCTAssertEqual(p.restored.count, 1)

    let q = FakeReplacePlatform()
    let f2 = ReplaceFlow(platform: q)
    _ = f2.run(deleteCount: 3, text: "a", matchPid: 100)
    q.count += 1  // the user copies something else
    q.scheduled[0].1()
    XCTAssertFalse(f2.hasPendingRestore)
    XCTAssertTrue(q.restored.isEmpty)
  }

  func testAWriteFailureKeepsOnlyAnEarlierRestoreThatIsStillValid() {
    // Still valid: the clipboard is still the first snippet.
    var p = FakeReplacePlatform()
    var flow = ReplaceFlow(platform: p)
    _ = flow.run(deleteCount: 3, text: "a", matchPid: 100)
    p.writeOk = false
    XCTAssertEqual(flow.run(deleteCount: 3, text: "b", matchPid: 100), .failed)
    XCTAssertTrue(flow.hasPendingRestore)
    p.scheduled[0].1()
    XCTAssertEqual(p.restored.count, 1)
    // Not valid: the user copied in between, so the old text must not return.
    p = FakeReplacePlatform()
    flow = ReplaceFlow(platform: p)
    _ = flow.run(deleteCount: 3, text: "a", matchPid: 100)
    p.count += 1
    p.writeOk = false
    XCTAssertEqual(flow.run(deleteCount: 3, text: "b", matchPid: 100), .failed)
    XCTAssertFalse(flow.hasPendingRestore)
    p.scheduled[0].1()
    XCTAssertTrue(p.restored.isEmpty)
  }

  func testAPasteFailureAfterAPendingRestoreDropsIt() {
    let p = FakeReplacePlatform()
    let flow = ReplaceFlow(platform: p)
    _ = flow.run(deleteCount: 3, text: "a", matchPid: 100)
    p.pasteKeyFound = false
    XCTAssertEqual(flow.run(deleteCount: 3, text: "b", matchPid: 100), .copied)
    XCTAssertFalse(flow.hasPendingRestore)
    p.scheduled[0].1()
    XCTAssertTrue(p.restored.isEmpty, "the snippet stays; the old text must not overwrite it")
  }
}
