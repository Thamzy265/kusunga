import Cocoa
import XCTest

@testable import Kusunga

// Tester probes for M1.3 on the Mac: the 500 ms and 300 ms limits to the
// millisecond, a thief or a quitting app at each step, hostile and huge texts
// on a private pasteboard (never the real one), and the shortcut registry.

class PasteFlowEdgeTests: XCTestCase {
  var platform: FakePastePlatform!
  var writer: FakePasteboardWriter!
  var flow: PasteFlow!

  override func setUp() {
    platform = FakePastePlatform()
    writer = FakePasteboardWriter()
    flow = PasteFlow(platform: platform, writer: writer, ownPid: 1)
  }

  private func posts() -> Int { platform.log.filter { $0.hasPrefix("post") }.count }

  func testFocusAt0_1_499_500MsStillPastes() {
    for d in [0, 1, 499, 500] {
      setUp()
      platform.frontAfterMs = d
      XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .pasted, "focus after \(d) ms")
      XCTAssertEqual(posts(), 1, "\(d)")
    }
  }

  func testFocusAt501MsOrLaterNeverPosts() {
    for d in [501, 502, 510, 1000] {
      setUp()
      platform.frontAfterMs = d
      XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout, "focus after \(d) ms")
      XCTAssertEqual(posts(), 0, "\(d)")
      XCTAssertEqual(writer.written, ["x"], "text stays on the clipboard")
    }
  }

  func testModifierKeysReleasedAroundTheLimitPostOnceAtOrBeforeTheLimit() {
    for until in [0, 1, 299, 300] {
      setUp()
      platform.frontAfterMs = 0
      platform.modifiersHeldUntilMs = until
      XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .pasted)
      let at = Int(platform.log.last!.dropFirst(5))!
      XCTAssertGreaterThanOrEqual(at, until, "not before the keys are up (\(until))")
      XCTAssertLessThanOrEqual(at, 300 + 10)
      XCTAssertEqual(posts(), 1)
    }
  }

  func testAThiefAtAnyMomentBeforeThePostNeverGetsTheKeystroke() {
    // Focus is confirmed at 20 ms and the keys are held until 200 ms. A thief
    // that arrives at any time from the confirmation to the release wins the
    // focus; Cmd+V must then not be posted.
    for steal in stride(from: 20, through: 200, by: 10) {
      setUp()
      platform.modifiersHeldUntilMs = 200
      platform.stealAtMs = steal
      let result = flow.run(text: "x", target: 200, post: true)
      XCTAssertEqual(result, .focusTimeout, "thief at \(steal) ms")
      XCTAssertEqual(posts(), 0, "thief at \(steal) ms")
    }
  }

  func testTheAppQuittingAfterItWasActivatedIsNotPostedInto() {
    // Activation worked, then the app quit: nothing is in front that is ours
    // to paste into.
    platform.frontAfterMs = nil
    platform.front = 300
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout)
    XCTAssertEqual(posts(), 0)
  }

  func testNoTargetAtAllIsTargetGoneAndTheTextIsStillCopied() {
    XCTAssertEqual(flow.run(text: "x", target: nil, post: true), .targetGone)
    XCTAssertEqual(writer.written, ["x"])
    XCTAssertFalse(platform.log.contains("activate"))
  }

  func testMissingPermissionIsCheckedAfterTheFocusNotBefore() {
    // The toast for "no permission" must only be claimed when the app really
    // came to the front; otherwise the user is told the wrong thing.
    platform.canPost = false
    platform.frontAfterMs = nil
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout)
  }

  func testCopyOnlyModeNeverAsksAboutThePermissionOrPosts() {
    platform.canPost = false
    XCTAssertEqual(flow.run(text: "x", target: 200, post: false), .copyOnly)
    XCTAssertEqual(posts(), 0)
  }

  func testTextsAreHandedOverWhole() {
    let nul = "a\u{0}b"
    let bidi = "pay\u{202E}1234"
    let huge = String(repeating: "𝄞", count: 262_144)  // 1 MiB of UTF-8
    for text in [nul, bidi, huge, "  keep  \n", "\r\n"] {
      setUp()
      _ = flow.run(text: text, target: 200, post: true)
      XCTAssertEqual(writer.written, [text])
    }
  }

  func testTwoRunsInARowEachPostOnce() {
    XCTAssertEqual(flow.run(text: "one", target: 200, post: true), .pasted)
    platform.log.removeAll()
    platform.activatedAt = nil
    platform.front = 100
    XCTAssertEqual(flow.run(text: "two", target: 200, post: true), .pasted)
    XCTAssertEqual(posts(), 1)
    XCTAssertEqual(writer.written, ["one", "two"])
  }
}

class PasteboardWriterEdgeTests: XCTestCase {
  var pasteboard: NSPasteboard!

  override func setUp() {
    pasteboard = NSPasteboard(
      name: NSPasteboard.Name("com.wnasoni.kusunga.test.edge.\(UUID().uuidString)"))
  }

  override func tearDown() { pasteboard.releaseGlobally() }

  func testAMegabyteOfTextRoundTrips() {
    let huge = String(repeating: "x", count: 1_048_576)
    XCTAssertTrue(NSPasteboardWriter(pasteboard: pasteboard).writeText(huge))
    XCTAssertEqual(pasteboard.string(forType: .string)?.utf8.count, 1_048_576)
  }

  func testEmojiBidiAndControlCharactersRoundTrip() {
    let text = "a\u{202E}b\u{200B}c\u{7}d 🙂 e\u{301} \r\n"
    XCTAssertTrue(NSPasteboardWriter(pasteboard: pasteboard).writeText(text))
    XCTAssertEqual(pasteboard.string(forType: .string), text)
  }

  func testATextWithANulIsNotCutAtTheNul() {
    let text = "before\u{0}after"
    XCTAssertTrue(NSPasteboardWriter(pasteboard: pasteboard).writeText(text))
    XCTAssertEqual(pasteboard.string(forType: .string), text)
  }

  func testOurOwnWriteOfBigOrHostileTextIsSeenAsOwnByTheWatcher() {
    var events: [[String: Any]] = []
    let watched = ClipboardPoller(pasteboard: pasteboard) { events.append($0) }
    watched.prime()
    XCTAssertTrue(NSPasteboardWriter(pasteboard: pasteboard).writeText("a\u{202E}b"))
    watched.tick()
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0]["own"] as? Bool, true)
    XCTAssertEqual(events[0]["text"] as? String, "a\u{202E}b")
  }

  func testTwoWritesInARowLeaveOnlyTheSecond() {
    let writer = NSPasteboardWriter(pasteboard: pasteboard)
    XCTAssertTrue(writer.writeText("first"))
    XCTAssertTrue(writer.writeText("second"))
    XCTAssertEqual(pasteboard.string(forType: .string), "second")
    let types = pasteboard.types?.map { $0.rawValue } ?? []
    XCTAssertEqual(types.filter { $0 == "com.wnasoni.kusunga.self" }.count, 1)
  }
}

class HotKeyEdgeTests: XCTestCase {
  var backend: FakeHotKeyBackend!
  var registry: HotKeyRegistry!

  override func setUp() {
    backend = FakeHotKeyBackend()
    registry = HotKeyRegistry(backend: backend)
  }

  func testEveryAllowedKeyWithEveryUsableModifierSetRegisters() {
    let mods = ["ctrl", "alt", "shift", "meta"]
    var tried = 0
    for key in HotKeyMapKeys.all {
      for mask in 1..<16 {
        let chosen = mods.enumerated().filter { mask & (1 << $0.offset) != 0 }.map { $0.element }
        let usable = chosen.contains("ctrl") || chosen.contains("alt") || chosen.contains("meta")
        setUp()
        let answer = registry.set(key: key, modifiers: chosen)
        XCTAssertEqual(answer, usable ? "ok" : "invalid", "\(key) + \(chosen)")
        tried += 1
      }
    }
    XCTAssertEqual(tried, 49 * 15)
  }

  func testDamagedNamesNeverReachTheSystem() {
    for key in ["", "V", "f0", "f13", "vv", "é", "enter", "esc", "\u{0}", "v\u{0}", "10"] {
      XCTAssertEqual(registry.set(key: key, modifiers: ["meta"]), "invalid", key)
    }
    for mod in ["", "Cmd", "command", "win", "CTRL", "ctrl "] {
      XCTAssertEqual(registry.set(key: "v", modifiers: [mod]), "invalid", mod)
    }
    XCTAssertTrue(backend.log.isEmpty)
  }

  func testTakenThenFreeThenSameAgain() {
    backend.taken = ["9/256"]
    XCTAssertEqual(registry.set(key: "v", modifiers: ["meta"]), "taken")
    backend.taken = []
    XCTAssertEqual(registry.set(key: "v", modifiers: ["meta"]), "ok")
    XCTAssertEqual(registry.set(key: "v", modifiers: ["meta"]), "ok")
    XCTAssertEqual(backend.live.count, 1)
  }

  func testRecordingThenCancellingLeavesNoShortcutUntilRestored() {
    XCTAssertEqual(registry.set(key: "v", modifiers: ["shift", "meta"]), "ok")
    registry.clear()  // Dart: beginRecording
    var presses = 0
    registry.onPress = { presses += 1 }
    registry.handlePress(handle: 1)  // the old handle: must be dead
    XCTAssertEqual(presses, 0)
    XCTAssertEqual(registry.set(key: "v", modifiers: ["shift", "meta"]), "ok")  // endRecording
    registry.handlePress(handle: backend.live.keys.first!)
    XCTAssertEqual(presses, 1)
  }

  func testAPressAfterReplacingTheShortcutOnlyCountsForTheNewHandle() {
    XCTAssertEqual(registry.set(key: "v", modifiers: ["shift", "meta"]), "ok")
    let oldHandle = backend.live.keys.first!
    XCTAssertEqual(registry.set(key: "k", modifiers: ["alt"]), "ok")
    var presses = 0
    registry.onPress = { presses += 1 }
    registry.handlePress(handle: oldHandle)
    XCTAssertEqual(presses, 0)
  }
}

/// The key names Dart may send (lib/picker/shortcut.dart): a-z, 0-9, f1-f12,
/// space.
enum HotKeyMapKeys {
  static let all: [String] =
    "abcdefghijklmnopqrstuvwxyz".map { String($0) } + (0...9).map { String($0) }
    + (1...12).map { "f\($0)" } + ["space"]
}
