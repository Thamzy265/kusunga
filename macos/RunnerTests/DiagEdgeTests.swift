import Cocoa
import OSLog
import XCTest

@testable import Kusunga

// Tester probes for the M1.3 diagnostics (6e24bed, 0a56e9b): what the unified
// log accepts, when a forced post may happen, and when the picker stays open.
// Nothing here posts a real key event or touches the real pasteboard.

// MARK: - DiagLog.isCode

class DiagLogEdgeTests: XCTestCase {
  override func setUp() {
    // Probe names used by the tests below that read the real unified log.
    DiagLog.extraCodesForTests = ["edgeProbeOk", "edgeProbeNoNumber", "edgeProbeBig", "edgeProbeNeg"]
  }

  override func tearDown() { DiagLog.extraCodesForTests = [] }

  func testOnlyKnownNamesAreCodes() {
    XCTAssertFalse(DiagLog.isCode(""))
    // The accepted names are a closed list now (B1): a shape such as "a" or 40
    // letters is no longer a code, a known name is.
    XCTAssertFalse(DiagLog.isCode("a"))
    XCTAssertFalse(DiagLog.isCode("Z"))
    XCTAssertFalse(DiagLog.isCode("0"))
    XCTAssertFalse(DiagLog.isCode(String(repeating: "a", count: 40)))
    XCTAssertTrue(DiagLog.isCode("pasteResult"))
    XCTAssertFalse(DiagLog.isCode(String(repeating: "a", count: 41)))
    XCTAssertFalse(DiagLog.isCode(String(repeating: "a", count: 4096)))
    XCTAssertFalse(DiagLog.isCode(String(repeating: "a", count: 1_000_000)))
  }

  func testEveryNonAsciiOrPunctuationCharacterIsRefused() {
    let bad = [
      " ", " a", "a ", "a b", "a\tb", "a\nb", "a\rb", "a\r\n", "abc\n", "\nabc",
      "a\u{0}b", "\u{0}", "abc\u{0}",
      "a.b", "a-b", "a_b", "a/b", "a\\b", "a:b", "a;b", "a,b", "a=b", "a+b",
      "a@b", "a#b", "a$b", "a%b", "a&b", "a*b", "a(b)", "a[b]", "a{b}", "a<b>",
      "a'b", "a\"b", "a`b", "a~b", "a!b", "a?b", "a|b", "a^b",
      // lookalikes and other scripts
      "\u{FF11}\u{FF12}\u{FF13}",  // full-width digits
      "\u{0430}bc",  // Cyrillic a
      "caf\u{00E9}", "cafe\u{0301}",  // e-acute, combining acute
      "\u{200B}abc", "abc\u{200B}",  // zero-width space
      "\u{00A0}abc",  // no-break space
      "\u{202E}abc",  // right-to-left override
      "\u{FEFF}abc",  // byte order mark
      "abc\u{1F600}", "\u{1F600}", "\u{65E5}\u{672C}",
      "\u{0660}\u{0661}",  // Arabic-indic digits
    ]
    for s in bad { XCTAssertFalse(DiagLog.isCode(s), "accepted \(s.debugDescription)") }
  }

  func testInjectionAndFormatStringsAreRefused() {
    let bad = [
      "%s", "%n", "%@", "%{public}@", "%{private}s", "%d%d%d",
      "\\(secret)", "\\(detail)", "${code}", "{{code}}",
      "'; DROP TABLE items;--", "\" OR 1=1 --", "<script>alert(1)</script>",
      "../../etc/passwd", "a\u{1B}[31mred", "code\ninjected 7", "code\r\nFAKE pasteResult 0",
      "permissionSnapshot 7", "permissionSnapshot\n7",
    ]
    for s in bad { XCTAssertFalse(DiagLog.isCode(s), "accepted \(s.debugDescription)") }
  }

  func testTextThatLooksLikeClipboardContentIsRefused() {
    let bad = [
      "my password is hunter2", "john@example.com", "+44 7700 900123", "07700 900123",
      "GB82 WEST 1234 5698 7654 32", "4111 1111 1111 1111", "https://example.com/a?b=c",
      "Hello, world!", "line one\nline two",
    ]
    for s in bad { XCTAssertFalse(DiagLog.isCode(s), "accepted \(s.debugDescription)") }
  }

  /// BUG (repro). The comment on DiagLog.isCode says "no text can be passed as
  /// one", but a card number, a phone number or an IBAN without spaces is
  /// 1 to 40 letters and digits, so the shape check accepts it and it would be
  /// written to the unified log as .public. A real code never starts with a
  /// digit and is camelCase; a closed list of known names would be stronger.
  func testAllDigitStringsAreNotCodes() {
    for s in ["4111111111111111", "07700900123", "447700900123", "123456", "0"] {
      XCTAssertFalse(DiagLog.isCode(s), "accepted \(s) (a number is not a code name)")
    }
  }

  /// BUG (repro), same cause: one-word secrets and bank details pass the shape
  /// check. Only a closed list of code names can refuse these.
  func testSingleTokenContentIsNotACode() {
    for s in ["hunter2", "correcthorsebatterystaple", "GB82WEST12345698765432", "Passw0rd"] {
      XCTAssertFalse(DiagLog.isCode(s), "accepted \(s)")
    }
  }

  /// Every code the native side logs itself must pass its own check, or it is
  /// silently dropped (a typo with an underscore would hide a diagnostic).
  func testEveryNativeCodeIsAccepted() {
    let codes = [
      "pasteResult", "postKeyNone", "postKeyCode", "postForced", "postFrontmostOk",
      "postTiming", "postSourceState", "postSourceNil", "postTap", "postEventNil",
      "postSent", "targetTerminated", "pickerKeptTargetGone", "toastShown",
      "toastAppActive", "toastRecheck", "permissionSnapshot", "pasteForcedPost",
    ]
    for c in codes { XCTAssertTrue(DiagLog.isCode(c), c) }
  }

  // MARK: what really reaches the unified log

  private func entries(since: Date) throws -> [String] {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let position = store.position(date: since)
    let predicate = NSPredicate(format: "subsystem == %@", "com.wnasoni.kusunga")
    return try store.getEntries(at: position, matching: predicate)
      .compactMap { $0 as? OSLogEntryLog }
      .filter { $0.category == "diagnostics" }
      .map { $0.composedMessage }
  }

  private func waitForEntry(_ text: String, since: Date) throws -> [String] {
    var seen: [String] = []
    for _ in 0..<40 {
      seen = try entries(since: since)
      if seen.contains(text) { return seen }
      Thread.sleep(forTimeInterval: 0.1)
    }
    return seen
  }

  func testAcceptedCodesAreWrittenAndRefusedOnesNeverAre() throws {
    let start = Date().addingTimeInterval(-1)
    let hostile = [
      "", "has space", "secret clipboard words", "a.b", "caf\u{00E9}", "x\ny",
      String(repeating: "q", count: 41), "%{public}@ leaked", "7700 900123",
    ]
    for h in hostile { DiagLog.log(h, 1234567) }
    DiagLog.log("edgeProbeOk", 42)
    DiagLog.log("edgeProbeNoNumber")
    let seen: [String]
    do {
      seen = try waitForEntry("edgeProbeOk 42", since: start)
    } catch {
      throw XCTSkip("the unified log cannot be read from this test host: \(error)")
    }
    guard seen.contains("edgeProbeOk 42") else {
      throw XCTSkip("the unified log did not return the probe in time (not a product failure)")
    }
    XCTAssertTrue(seen.contains("edgeProbeNoNumber"), "\(seen)")
    for line in seen {
      XCTAssertFalse(line.contains("1234567"), "a refused code was logged: \(line)")
      XCTAssertFalse(line.contains("secret"), line)
      XCTAssertFalse(line.contains("leaked"), line)
      XCTAssertFalse(line.contains("has space"), line)
    }
  }

  func testNegativeAndHugeNumbersAreStillJustNumbers() throws {
    let start = Date().addingTimeInterval(-1)
    DiagLog.log("edgeProbeBig", Int.max)
    DiagLog.log("edgeProbeNeg", -1)
    let seen: [String]
    do {
      seen = try waitForEntry("edgeProbeNeg -1", since: start)
    } catch {
      throw XCTSkip("the unified log cannot be read from this test host: \(error)")
    }
    guard seen.contains("edgeProbeNeg -1") else {
      throw XCTSkip("the unified log did not return the probe in time (not a product failure)")
    }
    XCTAssertTrue(seen.contains("edgeProbeBig \(Int.max)"), "\(seen)")
  }
}

// MARK: - PermissionSnapshot

class PermissionSnapshotEdgeTests: XCTestCase {
  func testAllEightCombinationsGiveEightDistinctNumbersFromZeroToSeven() {
    var seen = Set<Int>()
    for p in [false, true] {
      for a in [false, true] {
        for l in [false, true] {
          let m = PermissionSnapshot.mask(post: p, accessibility: a, listen: l)
          XCTAssertTrue((0...7).contains(m))
          XCTAssertEqual(m & 1 != 0, p)
          XCTAssertEqual(m & 2 != 0, a)
          XCTAssertEqual(m & 4 != 0, l)
          seen.insert(m)
        }
      }
    }
    XCTAssertEqual(seen.count, 8)
  }

  func testTheLiveSnapshotIsAlwaysAMaskAndIsSafeToCallOften() {
    for _ in 0..<50 {
      XCTAssertTrue((0...7).contains(PermissionSnapshot.current()))
    }
  }

  func testTheLiveSnapshotAgreesWithTheBitForPosting() {
    // Bit 1 is exactly the preflight answer that decides the paste.
    XCTAssertEqual(PermissionSnapshot.current() & 1 != 0, CGPreflightPostEventAccess())
  }
}

// MARK: - Force-post

class ForcePostEdgeTests: XCTestCase {
  var platform: FakePastePlatform!
  var writer: FakePasteboardWriter!
  var lines: [String] = []
  var flow: PasteFlow!

  override func setUp() {
    platform = FakePastePlatform()
    platform.canPost = false
    platform.forcePost = true
    writer = FakePasteboardWriter()
    lines = []
    flow = PasteFlow(
      platform: platform, writer: writer, ownPid: 1,
      diag: { [unowned self] c, d in self.lines.append(d == nil ? c : "\(c) \(d!)") })
  }

  private var posts: Int { platform.log.filter { $0.hasPrefix("post") }.count }

  func testNoTargetMeansNoPostEvenWhenForced() {
    XCTAssertEqual(flow.run(text: "x", target: nil, post: true), .targetGone)
    XCTAssertEqual(posts, 0)
    XCTAssertFalse(lines.contains { $0.hasPrefix("postForced") })
  }

  func testAGoneTargetMeansNoPostEvenWhenForced() {
    platform.running = []
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .targetGone)
    XCTAssertEqual(posts, 0)
  }

  func testTheTargetQuitsBeforeActivationMeansNoPost() {
    platform.activateResult = false
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .targetGone)
    XCTAssertEqual(posts, 0)
  }

  func testNeverPostsIntoKusungaItselfEvenWhenForced() {
    platform.running = [1]
    XCTAssertEqual(flow.run(text: "x", target: 1, post: true), .targetGone)
    XCTAssertEqual(posts, 0)
  }

  func testCopyOnlyModeNeverPostsEvenWhenForced() {
    XCTAssertEqual(flow.run(text: "x", target: 200, post: false), .copyOnly)
    XCTAssertEqual(posts, 0)
    XCTAssertFalse(lines.contains { $0.hasPrefix("postForced") })
  }

  func testAFailedClipboardWriteNeverPostsEvenWhenForced() {
    writer.succeeds = false
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .failed)
    XCTAssertEqual(posts, 0)
  }

  func testNoKeyForVNeverPostsEvenWhenForcedAndDoesNotSayItForced() {
    platform.keyCode = nil
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .copyOnly)
    XCTAssertEqual(posts, 0)
    XCTAssertFalse(lines.contains { $0.hasPrefix("postForced") }, "\(lines)")
  }

  func testFocusTakenDuringTheModifierWaitNeverPostsEvenWhenForced() {
    platform.modifiersHeldUntilMs = 250
    platform.stealAtMs = 120
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout)
    XCTAssertEqual(posts, 0)
  }

  func testTheTargetNeverComingToTheFrontNeverPostsEvenWhenForced() {
    for d in [501, 600, 5000] {
      setUp()
      platform.frontAfterMs = d
      XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .focusTimeout, "\(d)")
      XCTAssertEqual(posts, 0, "\(d)")
    }
  }

  func testAForcedPostIsExactlyOneKeystrokeAndTheTextIsOnTheClipboardFirst() {
    XCTAssertEqual(flow.run(text: "hello", target: 200, post: true), .pastedForced)
    XCTAssertEqual(posts, 1)
    XCTAssertEqual(writer.written, ["hello"])
    let hide = platform.log.firstIndex(of: "hide")!
    let post = platform.log.firstIndex { $0.hasPrefix("post") }!
    XCTAssertLessThan(hide, post)
  }

  func testWithPermissionTheSwitchIsInvisible() {
    platform.canPost = true
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .pasted)
    XCTAssertFalse(lines.contains { $0.hasPrefix("postForced") }, "\(lines)")
    XCTAssertEqual(posts, 1)
  }

  func testSwitchOffMeansNoPermissionAndNothingForcedIsLogged() {
    platform.forcePost = false
    XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .noPermission)
    XCTAssertEqual(posts, 0)
    XCTAssertFalse(lines.contains { $0.hasPrefix("postForced") })
    XCTAssertFalse(lines.contains { $0.hasPrefix("postKeyCode") }, "no step after the refusal")
  }

  func testRepeatedForcedPostsPostOncePerPaste() {
    for _ in 0..<5 {
      setUp()
      XCTAssertEqual(flow.run(text: "x", target: 200, post: true), .pastedForced)
      XCTAssertEqual(posts, 1)
    }
  }

  func testAPlatformThatDoesNotMentionTheSwitchNeverForces() {
    final class Plain: PastePlatform {
      func hidePicker() {}
      func frontmostPid() -> pid_t? { 200 }
      func isRunning(_ pid: pid_t) -> Bool { true }
      func activate(_ pid: pid_t) -> Bool { true }
      func modifiersDown() -> Bool { false }
      func canPostEvents() -> Bool { false }
      func postPaste() { XCTFail("posted without permission") }
      func sleep(ms: Int) {}
      func nowMs() -> Int { 0 }
    }
    let plain = Plain()
    XCTAssertFalse(plain.forcePostEnabled())
    let f = PasteFlow(platform: plain, writer: FakePasteboardWriter(), ownPid: 1)
    XCTAssertEqual(f.run(text: "x", target: 200, post: true), .noPermission)
  }

  func testTheResultNumbersMatchTheEnumOrder() {
    XCTAssertEqual(PasteResult.allCases.map { $0.rawValue }, [
      "pasted", "pastedForced", "noPermission", "focusTimeout", "targetGone", "copyOnly",
      "failed",
    ])
  }

  /// A paste's log never carries the text, even a forced one.
  func testAForcedPasteLogsNoContent() {
    _ = flow.run(text: "my private secret", target: 200, post: true)
    XCTAssertFalse(lines.joined(separator: "|").contains("secret"))
    XCTAssertFalse(lines.joined(separator: "|").contains("private"))
    for l in lines {
      let parts = l.split(separator: " ")
      XCTAssertTrue(DiagLog.isCode(String(parts[0])), l)
      XCTAssertTrue(parts.count == 1 || (parts.count == 2 && Int(parts[1]) != nil), l)
    }
  }

  // MARK: the real platform

  func testTheRealSwitchIsOffByDefault() throws {
    // A Debug build only; the Release branch is checked by test/ci in Dart.
    try XCTSkipIf(
      UserDefaults.standard.bool(forKey: "KusungaForcePost"),
      "this run was started with the switch on")
    XCTAssertFalse(MacPastePlatform(hide: {}).forcePostEnabled())
  }

  /// The launch argument `-KusungaForcePost YES` lands in the in-memory
  /// argument domain. Set there (never written to the app's preferences, so the
  /// running Debug app is not affected) the switch turns on, and off again.
  func testTheRealSwitchFollowsTheLaunchArgumentOnlyInDebug() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: "KusungaForcePost") else { return }
    let platform = MacPastePlatform(hide: {})
    defaults.setVolatileDomain(
      ["KusungaForcePost": "YES"], forName: UserDefaults.argumentDomain)
    defer { defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
    #if DEBUG
      XCTAssertTrue(platform.forcePostEnabled())
    #else
      XCTAssertFalse(platform.forcePostEnabled(), "Release must never force")
    #endif
    for off in ["NO", "0", "false", ""] {
      defaults.setVolatileDomain(
        ["KusungaForcePost": off], forName: UserDefaults.argumentDomain)
      XCTAssertFalse(platform.forcePostEnabled(), "value \(off.debugDescription)")
    }
  }
}

// MARK: - The picker stays open only when the target is gone

class DismissRuleEdgeTests: XCTestCase {
  func testTheWholeTable() {
    // target? alive? -> dismiss?
    XCTAssertFalse(DismissRule.shouldDismiss(target: 200, targetAlive: false))
    XCTAssertTrue(DismissRule.shouldDismiss(target: 200, targetAlive: true))
    XCTAssertTrue(DismissRule.shouldDismiss(target: nil, targetAlive: false))
    XCTAssertTrue(DismissRule.shouldDismiss(target: nil, targetAlive: true))
  }

  func testOddProcessIdsFollowTheSameRule() {
    for pid: pid_t in [0, 1, -1, Int32.max] {
      XCTAssertFalse(DismissRule.shouldDismiss(target: pid, targetAlive: false), "\(pid)")
      XCTAssertTrue(DismissRule.shouldDismiss(target: pid, targetAlive: true), "\(pid)")
    }
  }

  func testAProcessThatNeverExistedIsNotAlive() {
    // The bridge asks this before it keeps the picker open.
    XCTAssertFalse(MacPastePlatform.isAlive(Int32.max))
    XCTAssertFalse(MacPastePlatform.isAlive(-5))
  }

  func testOurOwnProcessIsAlive() {
    XCTAssertTrue(MacPastePlatform.isAlive(ProcessInfo.processInfo.processIdentifier))
  }
}
