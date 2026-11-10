import Cocoa
import XCTest

@testable import Kusunga

// M1.6 sensitive-content protection: the capture skips decided in native
// code before any text is read (docs/design/sensitive-content.md, option A;
// ADR 0005). The order is secret markers, then the pause, then the source app
// against the ignore list. This file also runs as a standalone bundle without
// launching Kusunga (tool/test_mac_capture.sh).

/// A pasteboard we control. It records every read of the text and of the
/// source marker, so a test can prove a skipped copy was never read.
final class GatePasteboard: PasteboardReading {
  var changeCount = 0
  var typeIdentifiers: [String] = []
  var text: String? = nil
  var marker: String? = nil
  private(set) var textReads = 0
  private(set) var markerReads = 0

  func plainString() -> String? {
    textReads += 1
    return text
  }

  func sourceMarker() -> String? {
    markerReads += 1
    return marker
  }

  func copy(
    _ text: String?, types: [String] = ["public.utf8-plain-text"], marker: String? = nil
  ) {
    changeCount += 1
    self.text = text
    self.marker = marker
    typeIdentifiers = marker == nil ? types : types + [CaptureGate.sourceMarkerType]
  }
}

final class CaptureGateTests: XCTestCase {
  private var nowMs: Int64 = 1_000_000

  private func gate() -> CaptureGate { CaptureGate(now: { [unowned self] in self.nowMs }) }

  func testIsPausedReadsTheThreeKindsOfValue() {
    XCTAssertFalse(CaptureGate.isPaused(until: 0, nowMs: 5))
    XCTAssertTrue(CaptureGate.isPaused(until: -1, nowMs: 5))
    XCTAssertTrue(CaptureGate.isPaused(until: 6, nowMs: 5))
    // At the end time the pause is over.
    XCTAssertFalse(CaptureGate.isPaused(until: 5, nowMs: 5))
    XCTAssertFalse(CaptureGate.isPaused(until: 4, nowMs: 5))
  }

  func testAnyOtherNegativeValueMeansNotPaused() {
    let g = gate()
    g.setPause(-7)
    XCTAssertEqual(g.pausedUntil, 0)
    g.setPause(-1)
    XCTAssertEqual(g.pausedUntil, -1)
  }

  func testPausedSkipsWithoutAskingForTheSource() {
    let g = gate()
    g.setIgnored(["com.example.vault"])
    g.setPause(nowMs + 60_000)
    var asked = 0
    XCTAssertEqual(g.check(source: { asked += 1; return "com.example.vault" }), .paused)
    XCTAssertEqual(asked, 0)
  }

  func testUntilResumedStaysPausedWhateverTheClock() {
    let g = gate()
    g.setPause(-1)
    nowMs = Int64.max - 1
    XCTAssertEqual(g.check(source: { nil }), .paused)
  }

  func testATimedPauseEndsOnTheWallClock() {
    let g = gate()
    g.setPause(nowMs + 1_000)
    XCTAssertEqual(g.check(source: { nil }), .paused)
    nowMs += 1_000
    XCTAssertNil(g.check(source: { nil }))
  }

  func testAnIgnoredSourceIsSkipped() {
    let g = gate()
    g.setIgnored(["com.example.vault", "org.other"])
    XCTAssertEqual(g.check(source: { "com.example.vault" }), .ignoredApp)
    XCTAssertNil(g.check(source: { "com.apple.TextEdit" }))
    // Bundle ids are matched exactly, as typed shortcuts do.
    XCTAssertNil(g.check(source: { "COM.EXAMPLE.VAULT" }))
  }

  func testAnUnknownSourceIsCapturedAsToday() {
    let g = gate()
    g.setIgnored(["com.example.vault"])
    XCTAssertNil(g.check(source: { nil }))
  }

  func testAnEmptyListNeverAsksForTheSource() {
    let g = gate()
    var asked = 0
    XCTAssertNil(g.check(source: { asked += 1; return "x" }))
    XCTAssertEqual(asked, 0)
  }

  func testTheListIsReplacedNotAddedTo() {
    let g = gate()
    g.setIgnored(["a.b"])
    g.setIgnored(["c.d"])
    XCTAssertNil(g.check(source: { "a.b" }))
    XCTAssertEqual(g.check(source: { "c.d" }), .ignoredApp)
  }

  func testTheSourceMarkerCountsFirstThenTheFrontApp() {
    var frontReads = 0
    let front = { () -> String? in frontReads += 1; return "com.front" }
    XCTAssertEqual(
      CaptureGate.sourceApp(
        types: ["public.utf8-plain-text", CaptureGate.sourceMarkerType],
        marker: { "com.marked" }, front: front),
      "com.marked")
    XCTAssertEqual(frontReads, 0)
    XCTAssertEqual(
      CaptureGate.sourceApp(
        types: ["public.utf8-plain-text", CaptureGate.sourceMarkerType],
        marker: { nil }, front: front),
      "com.front")
    XCTAssertEqual(
      CaptureGate.sourceApp(
        types: ["public.utf8-plain-text", CaptureGate.sourceMarkerType],
        marker: { "  " }, front: front),
      "com.front")
  }

  func testTheMarkerIsNotReadWhenItsTypeIsMissing() {
    var markerReads = 0
    XCTAssertEqual(
      CaptureGate.sourceApp(
        types: ["public.utf8-plain-text"], marker: { markerReads += 1; return "x" },
        front: { "com.front" }),
      "com.front")
    XCTAssertEqual(markerReads, 0)
  }

  func testTheSourceMarkerTypeName() {
    XCTAssertEqual(CaptureGate.sourceMarkerType, "org.nspasteboard.source")
  }
}

final class CapturePollerOrderTests: XCTestCase {
  private var nowMs: Int64 = 1_000_000
  private var events: [[String: Any]] = []
  private var front: String? = "com.apple.TextEdit"
  private var frontReads = 0

  private func make(_ pb: GatePasteboard, _ gate: CaptureGate) -> ClipboardPoller {
    ClipboardPoller(
      pasteboard: pb, gate: gate,
      frontApp: { [unowned self] in self.frontReads += 1; return self.front }
    ) { [unowned self] in self.events.append($0) }
  }

  private func gate() -> CaptureGate { CaptureGate(now: { [unowned self] in self.nowMs }) }

  private var types: [String] { events.map { $0["type"] as? String ?? "?" } }

  func testASecretCopyIsSkippedAsSecretEvenWhilePausedOrIgnored() {
    let pb = GatePasteboard()
    let g = gate()
    g.setPause(-1)
    g.setIgnored(["com.apple.TextEdit"])
    let poller = make(pb, g)
    pb.copy("hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
    poller.tick()
    XCTAssertEqual(types, ["concealed"])
    XCTAssertEqual(pb.textReads, 0)
    XCTAssertEqual(frontReads, 0)
  }

  func testWhilePausedACopyIsNeverReadAndNothingIsSent() {
    let pb = GatePasteboard()
    let g = gate()
    g.setPause(nowMs + 15 * 60_000)
    let poller = make(pb, g)
    pb.copy("my bank details")
    for _ in 0..<10 { poller.tick() }
    XCTAssertEqual(events.count, 0)
    XCTAssertEqual(pb.textReads, 0)
    XCTAssertEqual(pb.markerReads, 0)
    XCTAssertEqual(frontReads, 0)
  }

  func testWhenThePauseEndsTheNextCopyIsCaptured() {
    let pb = GatePasteboard()
    let g = gate()
    g.setPause(nowMs + 1_000)
    let poller = make(pb, g)
    pb.copy("during")
    poller.tick()
    nowMs += 1_000
    pb.copy("after")
    poller.tick()
    XCTAssertEqual(types, ["text"])
    XCTAssertEqual(events.first?["text"] as? String, "after")
  }

  func testACopyFromAnIgnoredFrontAppIsNeverRead() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    front = "com.example.vault"
    let poller = make(pb, g)
    pb.copy("secret")
    for _ in 0..<10 { poller.tick() }
    XCTAssertEqual(types, ["ignoredApp"])
    XCTAssertEqual(pb.textReads, 0)
    // The event carries nothing but its type: no app, no text.
    XCTAssertEqual(Set(events[0].keys), ["type"])
  }

  func testTheSourceMarkerWinsOverTheFrontApp() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    front = "com.apple.TextEdit"
    let poller = make(pb, g)
    pb.copy("secret", marker: "com.example.vault")
    poller.tick()
    XCTAssertEqual(types, ["ignoredApp"])
    XCTAssertEqual(pb.textReads, 0)
    XCTAssertEqual(frontReads, 0)
    // And a marker naming an app not on the list lets the copy through,
    // even with an ignored app in front.
    front = "com.example.vault"
    pb.copy("hello", marker: "com.apple.TextEdit")
    poller.tick()
    XCTAssertEqual(types, ["ignoredApp", "text"])
  }

  func testAnotherAppsCopyIsCaptured() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    let poller = make(pb, g)
    pb.copy("hello")
    poller.tick()
    XCTAssertEqual(types, ["text"])
    XCTAssertEqual(pb.textReads, 1)
  }

  func testTheSourceIsWorkedOutOncePerCopyAtTheFirstLook() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    let poller = make(pb, g)
    // The text is not ready yet, so the poller retries; the user switched
    // to the vault meanwhile. The copy was made in TextEdit.
    pb.copy(nil)
    poller.tick()
    front = "com.example.vault"
    pb.text = "late text"
    poller.tick()
    poller.tick()
    XCTAssertEqual(frontReads, 1)
    XCTAssertEqual(types, ["text"])
  }

  func testTextHeldForConfirmationIsNotSentOnceAPauseStarts() {
    let pb = GatePasteboard()
    let g = gate()
    let poller = make(pb, g)
    pb.copy(nil)
    poller.tick()  // not ready
    pb.text = "late text"
    poller.tick()  // read on a retry, held for the confirming tick
    g.setPause(nowMs + 60_000)
    poller.tick()  // the confirming tick: paused now, so nothing is sent
    poller.tick()
    XCTAssertEqual(events.count, 0)
  }

  func testWithoutAGateTheWatcherBehavesAsBefore() {
    let pb = GatePasteboard()
    let poller = ClipboardPoller(pasteboard: pb) { [unowned self] in self.events.append($0) }
    pb.copy("hello")
    poller.tick()
    XCTAssertEqual(types, ["text"])
  }
}

// M1.6 fix round 2 (reviewer R5): reading the source marker is a pasteboard
// data read, which can raise its own paste alert when access is "ask" or
// "deny". Then the marker is never read; the front app is the source.
final class CaptureSourceAccessTests: XCTestCase {
  private var events: [[String: Any]] = []
  private var front: String? = "com.apple.TextEdit"

  private func make(_ pb: GatePasteboard, mayReadMarker: Bool) -> ClipboardPoller {
    let g = CaptureGate(now: { 1_000_000 })
    g.setIgnored(["com.example.vault"])
    return ClipboardPoller(
      pasteboard: pb, mayRetry: { mayReadMarker }, mayReadMarker: { mayReadMarker },
      gate: g, frontApp: { [unowned self] in self.front }
    ) { [unowned self] in self.events.append($0) }
  }

  private var types: [String] { events.map { $0["type"] as? String ?? "?" } }

  func testWithoutAlwaysAllowTheMarkerIsNeverReadAndTheFrontAppCounts() {
    let pb = GatePasteboard()
    let poller = make(pb, mayReadMarker: false)
    // The marker names the vault, but it can't be read without an alert:
    // the front app (TextEdit, not ignored) is the source.
    pb.copy("hello", marker: "com.example.vault")
    poller.tick()
    XCTAssertEqual(pb.markerReads, 0)
    XCTAssertEqual(types, ["text"])
    // With the vault in front, its copy is skipped and never read.
    front = "com.example.vault"
    pb.copy("secret", marker: "com.apple.TextEdit")
    poller.tick()
    XCTAssertEqual(pb.markerReads, 0)
    XCTAssertEqual(types, ["text", "ignoredApp"])
    XCTAssertEqual(pb.textReads, 1)
  }

  func testWithAlwaysAllowTheMarkerStillWins() {
    let pb = GatePasteboard()
    let poller = make(pb, mayReadMarker: true)
    pb.copy("secret", marker: "com.example.vault")
    poller.tick()
    XCTAssertEqual(pb.markerReads, 1)
    XCTAssertEqual(types, ["ignoredApp"])
    XCTAssertEqual(pb.textReads, 0)
  }

  func testOnlyAlwaysAllowAndUnsupportedMayReadTheMarker() {
    XCTAssertTrue(ClipboardPoller.readsAreSilent("allow"))
    XCTAssertTrue(ClipboardPoller.readsAreSilent("unsupported"))
    XCTAssertFalse(ClipboardPoller.readsAreSilent("ask"))
    XCTAssertFalse(ClipboardPoller.readsAreSilent("deny"))
  }
}
