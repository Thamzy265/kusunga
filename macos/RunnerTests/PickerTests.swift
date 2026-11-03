import Cocoa
import XCTest

@testable import Kusunga

// MARK: - Paste flow

/// A pretend Mac: time only moves when the flow sleeps, so the 500 ms and
/// 300 ms limits are tested without waiting.
final class FakePastePlatform: PastePlatform {
  var log: [String] = []
  var now = 0

  var front: pid_t? = 100
  var running: Set<pid_t> = [200]
  var activateResult = true
  /// The target becomes the frontmost app this many ms after activate (nil:
  /// never).
  var frontAfterMs: Int? = 20
  var activatedAt: Int?
  /// Another app grabs the front at this time (nil: never).
  var stealAtMs: Int?
  var stealer: pid_t = 300
  /// Modifier keys are down until this time (nil: not held; Int.max: held).
  var modifiersHeldUntilMs: Int?
  var canPost = true
  /// The key that types "v" in the pretend layout (nil: none does).
  var keyCode: UInt16? = 9

  private func advance() {
    if let a = activatedAt, let d = frontAfterMs, now >= a + d, front != 300 {
      front = 200
    }
    if let s = stealAtMs, now >= s { front = stealer }
  }

  func hidePicker() { log.append("hide") }

  func frontmostPid() -> pid_t? {
    advance()
    return front
  }

  func isRunning(_ pid: pid_t) -> Bool { running.contains(pid) }

  func activate(_ pid: pid_t) -> Bool {
    log.append("activate")
    if activateResult { activatedAt = now }
    return activateResult
  }

  func modifiersDown() -> Bool {
    guard let until = modifiersHeldUntilMs else { return false }
    return now < until
  }

  func canPostEvents() -> Bool { canPost }
  func pasteKeyCode() -> UInt16? { keyCode }

  func postPaste() { log.append("post@\(now)") }

  func sleep(ms: Int) { now += ms }
  func nowMs() -> Int { now }
}

final class FakePasteboardWriter: PasteboardWriting {
  var written: [String] = []
  var succeeds = true
  var onWrite: (() -> Void)?
  func writeText(_ text: String) -> Bool {
    written.append(text)
    onWrite?()
    return succeeds
  }
}

class PasteFlowTests: XCTestCase {
  var platform: FakePastePlatform!
  var writer: FakePasteboardWriter!
  var flow: PasteFlow!

  override func setUp() {
    platform = FakePastePlatform()
    writer = FakePasteboardWriter()
    flow = PasteFlow(platform: platform, writer: writer, ownPid: 1)
  }

  func testWritesHidesActivatesThenPostsInThatOrder() {
    writer.onWrite = { [unowned self] in self.platform.log.append("write") }
    let result = flow.run(text: "hello", target: 200, post: true)
    XCTAssertEqual(result, .pasted)
    XCTAssertEqual(platform.log.first, "write")
    XCTAssertEqual(Array(platform.log.prefix(3)), ["write", "hide", "activate"])
    XCTAssertTrue(platform.log.last!.hasPrefix("post@"))
    XCTAssertEqual(platform.log.filter { $0.hasPrefix("post") }.count, 1)
    XCTAssertEqual(writer.written, ["hello"])
  }

  func testPostsOnlyAfterTheTargetIsFrontmost() {
    platform.frontAfterMs = 120
    let result = flow.run(text: "x", target: 200, post: true)
    XCTAssertEqual(result, .pasted)
    let postedAt = Int(platform.log.last!.dropFirst(5))!
    XCTAssertGreaterThanOrEqual(postedAt, 120)
  }

  func testFocusNotBackWithinHalfASecondNeverPosts() {
    platform.frontAfterMs = nil
    let result = flow.run(text: "x", target: 200, post: true)
    XCTAssertEqual(result, .focusTimeout)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
    XCTAssertGreaterThanOrEqual(platform.now, 500)
    XCTAssertLessThanOrEqual(platform.now, 520, "gives up at 500 ms")
    XCTAssertEqual(writer.written, ["x"], "the text is on the clipboard anyway")
  }

  func testFocusArrivingJustInTimeStillPastes() {
    platform.frontAfterMs = 490
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .pasted)
  }

  func testFocusArrivingTooLateDoesNotPaste() {
    platform.frontAfterMs = 530
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
  }

  func testNeverPostsIntoKusungaItself() {
    for target in [nil, 1] as [pid_t?] {
      setUp()
      platform.front = 1
      let result = flow.run(text: "x", target: target, post: true)
      XCTAssertEqual(result, .targetGone, "target \(String(describing: target))")
      XCTAssertFalse(platform.log.contains("activate"))
      XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
      XCTAssertEqual(writer.written, ["x"])
    }
  }

  func testTargetThatQuitIsReportedAndNothingIsPosted() {
    platform.running = []
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .targetGone)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
  }

  func testActivationThatIsRefusedIsTargetGone() {
    platform.activateResult = false
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .targetGone)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
  }

  func testCopyOnlyModeActivatesButDoesNotPost() {
    XCTAssertEqual(flow.run(text: "x", target: 200, post: false), .copyOnly)
    XCTAssertTrue(platform.log.contains("activate"))
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
  }

  func testMissingPermissionCopiesOnly() {
    platform.canPost = false
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .noPermission)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
    XCTAssertTrue(platform.log.contains("activate"), "focus still goes back")
  }

  func testWaitsForTheModifierKeysToBeReleased() {
    platform.modifiersHeldUntilMs = 150
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .pasted)
    let postedAt = Int(platform.log.last!.dropFirst(5))!
    XCTAssertGreaterThanOrEqual(postedAt, 150)
  }

  func testKeysHeldForeverAreWaitedForAtMost300ms() {
    platform.modifiersHeldUntilMs = Int.max
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .pasted)
    let postedAt = Int(platform.log.last!.dropFirst(5))!
    // Focus came back at ~20 ms; the wait then adds up to 300 ms.
    XCTAssertLessThanOrEqual(postedAt, 20 + 300 + 30)
    XCTAssertGreaterThanOrEqual(postedAt, 300)
  }

  func testFocusStolenWhileWaitingForTheKeysNeverPosts() {
    platform.modifiersHeldUntilMs = 200
    platform.stealAtMs = 100
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
  }

  func testAnotherAppInFrontAtTheStartIsNotPostedInto() {
    platform.frontAfterMs = nil
    platform.front = 300
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
  }

  func testAClipboardThatCannotBeWrittenIsReportedAndNothingElseHappensToTheTarget() {
    writer.succeeds = false
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .failed)
    XCTAssertFalse(platform.log.contains("activate"))
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
    XCTAssertTrue(platform.log.contains("hide"), "the picker still goes away")
  }

  func testTheFullTextIsWrittenNotAPreview() {
    let long = String(repeating: "ab", count: 50_000)
    _ = flow.run(text: long, target: 200, post: true)
    XCTAssertEqual(writer.written, [long])
  }

  func testPollingIsEveryTenMilliseconds() {
    platform.frontAfterMs = nil
    _ = flow.run(text: "x", target: 200, post: true)
    XCTAssertEqual(platform.now % 10, 0)
  }
}

// MARK: - The pasteboard marker (on a private pasteboard, never the real one)

class PasteboardMarkerTests: XCTestCase {
  var pasteboard: NSPasteboard!

  override func setUp() {
    pasteboard = NSPasteboard(
      name: NSPasteboard.Name("com.wnasoni.kusunga.test.\(UUID().uuidString)"))
  }

  override func tearDown() {
    pasteboard.releaseGlobally()
  }

  func testWritesTheTextAndOurMarker() {
    let writer = NSPasteboardWriter(pasteboard: pasteboard)
    XCTAssertTrue(writer.writeText("hello\nworld 🙂"))
    XCTAssertEqual(pasteboard.string(forType: .string), "hello\nworld 🙂")
    XCTAssertTrue(pasteboard.types?.map { $0.rawValue }.contains("com.wnasoni.kusunga.self") ?? false)
  }

  func testReplacesWhatWasThere() {
    pasteboard.clearContents()
    pasteboard.setString("old", forType: .string)
    pasteboard.setString("x", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    XCTAssertTrue(NSPasteboardWriter(pasteboard: pasteboard).writeText("new"))
    XCTAssertEqual(pasteboard.string(forType: .string), "new")
    XCTAssertFalse(
      pasteboard.types?.map { $0.rawValue }.contains("org.nspasteboard.ConcealedType") ?? true,
      "an old secret marker must not stay on a new item")
  }

  func testTheWatcherSeesOurWriteAsOurOwn() {
    var events: [[String: Any]] = []
    let watched = ClipboardPoller(pasteboard: pasteboard) { events.append($0) }
    watched.prime()
    XCTAssertTrue(NSPasteboardWriter(pasteboard: pasteboard).writeText("from picker"))
    watched.tick()
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0]["type"] as? String, "text")
    XCTAssertEqual(events[0]["text"] as? String, "from picker")
    XCTAssertEqual(events[0]["own"] as? Bool, true)
  }

  func testAnOrdinaryCopyHasNoOwnFlag() {
    var events: [[String: Any]] = []
    let watched = ClipboardPoller(pasteboard: pasteboard) { events.append($0) }
    watched.prime()
    pasteboard.clearContents()
    pasteboard.setString("plain", forType: .string)
    watched.tick()
    XCTAssertEqual(events.count, 1)
    XCTAssertNil(events[0]["own"])
  }
}

class ClipboardPollerOwnMarkerTests: XCTestCase {
  var pasteboard: FakePasteboard!
  var events: [[String: Any]]!
  var poller: ClipboardPoller!

  override func setUp() {
    pasteboard = FakePasteboard()
    events = []
    poller = ClipboardPoller(pasteboard: pasteboard) { [unowned self] in self.events.append($0) }
    poller.prime()
  }

  let own = "com.wnasoni.kusunga.self"

  func testMarkerIsReportedAsOwn() {
    pasteboard.copy("a", types: ["public.utf8-plain-text", own])
    poller.tick()
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0]["own"] as? Bool, true)
  }

  func testTheMarkerNeverSkipsTheSecretCheck() {
    // Any app can add our marker. A secret marker still wins, and the text is
    // never read.
    for secret in [
      "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
      "org.nspasteboard.AutoGeneratedType",
    ] {
      setUp()
      pasteboard.copy("secret", types: ["public.utf8-plain-text", own, secret])
      poller.tick()
      XCTAssertEqual(events.count, 1, secret)
      XCTAssertEqual(events[0]["type"] as? String, "concealed", secret)
      XCTAssertNil(events[0]["own"], secret)
      XCTAssertNil(events[0]["text"], secret)
      XCTAssertEqual(pasteboard.textReads, 0, "never read: \(secret)")
    }
  }

  func testMarkerWithoutTextIsIgnored() {
    pasteboard.copy(nil, types: [own])
    poller.tick()
    XCTAssertTrue(events.isEmpty)
  }

  func testOwnFlagComesWithTheTextOfARetriedRead() {
    pasteboard.copy(nil, types: ["public.utf8-plain-text", own])
    poller.tick()
    XCTAssertTrue(events.isEmpty)
    pasteboard.text = "late"
    poller.tick()  // read, held
    poller.tick()  // confirmed
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0]["text"] as? String, "late")
    XCTAssertEqual(events[0]["own"] as? Bool, true)
  }

  func testTooLargeOwnTextIsStillTooLarge() {
    pasteboard.copy(
      String(repeating: "x", count: ClipboardPolicy.maxBytes + 1),
      types: ["public.utf8-plain-text", own])
    poller.tick()
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0]["type"] as? String, "tooLarge")
  }

  func testMarkerConstantMatchesTheDesign() {
    XCTAssertEqual(ClipboardPolicy.ownMarkerType, "com.wnasoni.kusunga.self")
  }
}

// MARK: - Shortcut keys

class HotKeyMapTests: XCTestCase {
  func testEveryKeyTheAppAllowsHasAUniqueCode() {
    var names = (97...122).map { String(UnicodeScalar($0)!) }
    names += (0...9).map { String($0) }
    names += (1...12).map { "f\($0)" }
    names.append("space")
    var seen = Set<UInt32>()
    for n in names {
      guard let code = HotKeyMap.keyCode(for: n) else {
        return XCTFail("no code for \(n)")
      }
      XCTAssertTrue(seen.insert(code).inserted, "duplicate code for \(n)")
    }
    XCTAssertEqual(names.count, 26 + 10 + 12 + 1)
  }

  func testKnownCodes() {
    XCTAssertEqual(HotKeyMap.keyCode(for: "v"), 9)
    XCTAssertEqual(HotKeyMap.keyCode(for: "a"), 0)
    XCTAssertEqual(HotKeyMap.keyCode(for: "z"), 6)
    XCTAssertEqual(HotKeyMap.keyCode(for: "1"), 18)
    XCTAssertEqual(HotKeyMap.keyCode(for: "0"), 29)
    XCTAssertEqual(HotKeyMap.keyCode(for: "space"), 49)
    XCTAssertEqual(HotKeyMap.keyCode(for: "f1"), 122)
    XCTAssertEqual(HotKeyMap.keyCode(for: "f12"), 111)
  }

  func testOtherNamesAreRejected() {
    for n in ["", "V", "enter", "f13", "ab", "é", "esc", "tab"] {
      XCTAssertNil(HotKeyMap.keyCode(for: n), n)
    }
  }

  func testModifiersBecomeCarbonFlags() {
    XCTAssertEqual(HotKeyMap.carbonModifiers(["meta"]), 0x0100)
    XCTAssertEqual(HotKeyMap.carbonModifiers(["shift"]), 0x0200)
    XCTAssertEqual(HotKeyMap.carbonModifiers(["alt"]), 0x0800)
    XCTAssertEqual(HotKeyMap.carbonModifiers(["ctrl"]), 0x1000)
    XCTAssertEqual(HotKeyMap.carbonModifiers(["shift", "meta"]), 0x0300)
    XCTAssertEqual(HotKeyMap.carbonModifiers([]), 0)
  }

  func testUnknownModifiersAreRejected() {
    XCTAssertNil(HotKeyMap.carbonModifiers(["meta", "hyper"]))
    XCTAssertNil(HotKeyMap.carbonModifiers(["Meta"]))
  }
}

final class FakeHotKeyBackend: HotKeyBackend {
  var taken: Set<String> = []
  var failWith: String?
  var log: [String] = []
  var live: [Int: String] = [:]
  private var next = 1

  func register(keyCode: UInt32, modifiers: UInt32) -> HotKeyRegistration {
    let id = "\(keyCode)/\(modifiers)"
    log.append("register \(id)")
    if let f = failWith { return .failed(f) }
    if taken.contains(id) || live.values.contains(id) { return .taken }
    let handle = next
    next += 1
    live[handle] = id
    return .ok(handle)
  }

  func unregister(_ handle: Int) {
    log.append("unregister \(live[handle] ?? "?")")
    live[handle] = nil
  }
}

class HotKeyRegistryTests: XCTestCase {
  var backend: FakeHotKeyBackend!
  var registry: HotKeyRegistry!

  override func setUp() {
    backend = FakeHotKeyBackend()
    registry = HotKeyRegistry(backend: backend)
  }

  func testRegistersAValidShortcut() {
    XCTAssertEqual(registry.set(key: "v", modifiers: ["shift", "meta"]), "ok")
    XCTAssertEqual(backend.live.values.sorted(), ["9/768"])
  }

  func testAnInvalidKeyOrModifierNeverReachesTheSystem() {
    XCTAssertEqual(registry.set(key: "enter", modifiers: ["meta"]), "invalid")
    XCTAssertEqual(registry.set(key: "v", modifiers: ["hyper"]), "invalid")
    XCTAssertEqual(registry.set(key: "v", modifiers: []), "invalid", "needs a modifier")
    XCTAssertTrue(backend.log.isEmpty)
  }

  func testShiftAloneIsNotEnough() {
    XCTAssertEqual(registry.set(key: "v", modifiers: ["shift"]), "invalid")
    XCTAssertTrue(backend.log.isEmpty)
  }

  func testTheNewShortcutIsRegisteredBeforeTheOldOneIsReleased() {
    _ = registry.set(key: "v", modifiers: ["shift", "meta"])
    backend.log.removeAll()
    XCTAssertEqual(registry.set(key: "k", modifiers: ["alt"]), "ok")
    XCTAssertEqual(backend.log, ["register 40/2048", "unregister 9/768"])
    XCTAssertEqual(backend.live.values.sorted(), ["40/2048"])
  }

  func testATakenShortcutKeepsTheOldOne() {
    _ = registry.set(key: "v", modifiers: ["shift", "meta"])
    backend.taken = ["40/2048"]
    XCTAssertEqual(registry.set(key: "k", modifiers: ["alt"]), "taken")
    XCTAssertEqual(backend.live.values.sorted(), ["9/768"], "old one still works")
    XCTAssertEqual(registry.set(key: "j", modifiers: ["alt"]), "ok", "and the next try works")
  }

  func testAnotherFailureIsInvalidAndKeepsTheOldOne() {
    _ = registry.set(key: "v", modifiers: ["shift", "meta"])
    backend.failWith = "oops"
    XCTAssertEqual(registry.set(key: "k", modifiers: ["alt"]), "invalid")
    XCTAssertEqual(backend.live.count, 1)
  }

  func testTheSameShortcutAgainIsAQuietSuccess() {
    _ = registry.set(key: "v", modifiers: ["shift", "meta"])
    backend.log.removeAll()
    XCTAssertEqual(registry.set(key: "v", modifiers: ["meta", "shift"]), "ok")
    XCTAssertTrue(backend.log.isEmpty, "our own registration must not look taken")
  }

  func testClearReleasesTheShortcutAndAllowsRegisteringItAgain() {
    _ = registry.set(key: "v", modifiers: ["shift", "meta"])
    registry.clear()
    XCTAssertTrue(backend.live.isEmpty)
    registry.clear()
    XCTAssertEqual(backend.log.filter { $0.hasPrefix("unregister") }.count, 1)
    XCTAssertEqual(registry.set(key: "v", modifiers: ["shift", "meta"]), "ok")
  }

  func testAPressCallsTheHandlerOnlyForOurShortcut() {
    var presses = 0
    registry.onPress = { presses += 1 }
    _ = registry.set(key: "v", modifiers: ["shift", "meta"])
    registry.handlePress(handle: backend.live.keys.first!)
    registry.handlePress(handle: 999)
    XCTAssertEqual(presses, 1)
  }
}

// MARK: - Window placement

class PickerGeometryTests: XCTestCase {
  let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)

  func testPickerIsCentredAcrossAndInTheUpperPartOfTheScreen() {
    let f = PickerGeometry.pickerFrame(in: screen)
    XCTAssertEqual(f.size, NSSize(width: 560, height: 420))
    XCTAssertEqual(f.midX, screen.midX, accuracy: 0.5)
    XCTAssertEqual(f.maxY, screen.maxY - screen.height / 6, accuracy: 0.5)
    XCTAssertTrue(screen.contains(f))
  }

  func testOnASecondScreenItIsCentredThere() {
    let second = NSRect(x: 1440, y: -200, width: 1920, height: 1080)
    let f = PickerGeometry.pickerFrame(in: second)
    XCTAssertEqual(f.midX, second.midX, accuracy: 0.5)
    XCTAssertTrue(second.contains(f))
  }

  func testASmallScreenGets90PercentWidthButNotLessThan360() {
    let small = NSRect(x: 0, y: 0, width: 700, height: 500)
    let f = PickerGeometry.pickerFrame(in: small)
    XCTAssertEqual(f.width, 630, accuracy: 0.5)
    XCTAssertTrue(small.contains(f))
    let narrow = NSRect(x: 0, y: 0, width: 380, height: 600)
    XCTAssertEqual(PickerGeometry.pickerFrame(in: narrow).width, 360, accuracy: 0.5)
  }

  func testNeverTallerThanTheScreenOrShorterThanTheMinimum() {
    let short = NSRect(x: 0, y: 0, width: 1000, height: 400)
    let f = PickerGeometry.pickerFrame(in: short)
    XCTAssertLessThanOrEqual(f.height, 400)
    XCTAssertGreaterThanOrEqual(f.height, 240)
    XCTAssertTrue(short.contains(f))
  }

  func testToastSitsJustBelowAndRightOfThePointer() {
    let f = PickerGeometry.toastFrame(pointer: NSPoint(x: 500, y: 500), in: screen)
    XCTAssertEqual(f.size, NSSize(width: 360, height: 96))
    XCTAssertEqual(f.minX, 512, accuracy: 0.5)
    XCTAssertEqual(f.maxY, 488, accuracy: 0.5)
  }

  func testToastStaysOnTheScreenAtTheEdges() {
    for p in [
      NSPoint(x: 1439, y: 874), NSPoint(x: 1, y: 1), NSPoint(x: 1439, y: 1), NSPoint(x: 1, y: 874),
    ] {
      let f = PickerGeometry.toastFrame(pointer: p, in: screen)
      XCTAssertTrue(screen.contains(f), "\(p) -> \(f)")
    }
  }

  func testTheScreenWithThePointerIsChosen() {
    let a = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let b = NSRect(x: 1000, y: 0, width: 1000, height: 800)
    XCTAssertEqual(PickerGeometry.screenFrame(containing: NSPoint(x: 1500, y: 100), among: [a, b]), b)
    XCTAssertEqual(PickerGeometry.screenFrame(containing: NSPoint(x: 10, y: 10), among: [a, b]), a)
    // On a seam or outside every screen: the first one.
    XCTAssertEqual(PickerGeometry.screenFrame(containing: NSPoint(x: 5000, y: 5000), among: [a, b]), a)
    XCTAssertNil(PickerGeometry.screenFrame(containing: .zero, among: []))
  }
}

// MARK: - The key that types "v" (Dvorak and other layouts)

class PasteKeyTests: XCTestCase {
  /// A layout as a table of key code -> typed letter.
  private func layout(_ table: [UInt16: String]) -> (UInt16) -> String? { { table[$0] } }

  func testQwertyUsesKeyCode9() {
    XCTAssertEqual(PasteKey.code(forV: layout([9: "v", 0: "a"])), 9)
  }

  func testDvorakFindsWhereVIs() {
    // On plain Dvorak key code 9 types "." and "v" sits on the key at code 47.
    XCTAssertEqual(PasteKey.code(forV: layout([9: ".", 47: "v", 8: "j"])), 47)
  }

  func testNoKeyTypingVMeansNoPasteKey() {
    XCTAssertNil(PasteKey.code(forV: layout([9: "м", 0: "ф"])))
    XCTAssertNil(PasteKey.code(forV: layout([:])))
  }

  func testOnlyAPlainLowerCaseVCounts() {
    XCTAssertNil(PasteKey.code(forV: layout([9: "V", 10: "vv", 11: " v"])))
  }

  func testTheStandardKeyWinsIfTwoKeysTypeV() {
    XCTAssertEqual(PasteKey.code(forV: layout([3: "v", 9: "v"])), 9)
  }

  func testOnlyRealKeyCodesAreTried() {
    XCTAssertNil(PasteKey.code(forV: layout([200: "v"])))
  }
}

class PasteFlowKeyTests: XCTestCase {
  func testNoKeyForVCopiesOnlyAndNeverPosts() {
    let platform = FakePastePlatform()
    platform.keyCode = nil
    let flow = PasteFlow(platform: platform, writer: FakePasteboardWriter(), ownPid: 1)
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .copyOnly)
    XCTAssertFalse(platform.log.contains { $0.hasPrefix("post") })
    XCTAssertTrue(platform.log.contains("activate"))
  }
}

// MARK: - Esc and click outside (E1)

class ClosePlanTests: XCTestCase {
  func testEscWithATargetGivesTheFocusBackToItAndDoesNotActivateKusunga() {
    let plan = ClosePlan.make(manageWasVisible: true, target: 200)
    XCTAssertTrue(plan.showManage)
    XCTAssertFalse(plan.activateKusunga)
    XCTAssertEqual(plan.reactivate, 200)
  }

  func testEscWithATargetAndNoHistoryWindowJustReturnsToTheTarget() {
    let plan = ClosePlan.make(manageWasVisible: false, target: 200)
    XCTAssertFalse(plan.showManage)
    XCTAssertFalse(plan.activateKusunga)
    XCTAssertEqual(plan.reactivate, 200)
  }

  func testWhenKusungaItselfWasInFrontItComesBack() {
    let plan = ClosePlan.make(manageWasVisible: true, target: nil)
    XCTAssertTrue(plan.showManage)
    XCTAssertTrue(plan.activateKusunga)
    XCTAssertNil(plan.reactivate)
  }

  func testNothingToRestoreActivatesNothing() {
    let plan = ClosePlan.make(manageWasVisible: false, target: nil)
    XCTAssertFalse(plan.showManage)
    XCTAssertFalse(plan.activateKusunga)
    XCTAssertNil(plan.reactivate)
  }
}
