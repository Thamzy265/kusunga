import Cocoa
import XCTest

@testable import Kusunga

// M1.6 tester: edge cases of the capture skips in the Mac watcher
// (docs/design/sensitive-content.md "Abuse cases", ADR 0005). Uses the
// GatePasteboard fake from CaptureGateTests.swift, which records every read
// of the text and of the source marker. Runs without launching Kusunga:
// tool/test_mac_capture.sh.

final class CaptureGateEdgeTests: XCTestCase {
  private var nowMs: Int64 = 1_000_000
  private var events: [[String: Any]] = []
  private var front: String? = "com.apple.TextEdit"
  private var frontReads = 0

  private func gate() -> CaptureGate { CaptureGate(now: { [unowned self] in self.nowMs }) }

  private func make(_ pb: GatePasteboard, _ gate: CaptureGate) -> ClipboardPoller {
    ClipboardPoller(
      pasteboard: pb, gate: gate,
      frontApp: { [unowned self] in self.frontReads += 1; return self.front }
    ) { [unowned self] in self.events.append($0) }
  }

  private var types: [String] { events.map { $0["type"] as? String ?? "?" } }

  // MARK: gate values

  func testSetPauseExtremes() {
    let g = gate()
    g.setPause(Int64.max)
    XCTAssertEqual(g.check(source: { nil }), .paused)
    g.setPause(Int64.min)
    XCTAssertEqual(g.pausedUntil, 0)
    XCTAssertNil(g.check(source: { nil }))
    g.setPause(0)
    XCTAssertNil(g.check(source: { nil }))
  }

  func testThePauseEndsExactlyAtTheEndTimeAndIsPausedOneMsBefore() {
    let g = gate()
    g.setPause(nowMs + 1)
    XCTAssertEqual(g.check(source: { nil }), .paused)
    nowMs += 1
    XCTAssertNil(g.check(source: { nil }))
  }

  func testClockMovedBackwardsKeepsATimedPauseOnUntilItsEndTime() {
    // Native code compares with the wall clock only; Dart cuts a pause that
    // would now run too long (PauseService), so native must not shorten it.
    let g = gate()
    g.setPause(nowMs + 10_000)
    nowMs -= 3_600_000
    XCTAssertEqual(g.check(source: { nil }), .paused)
  }

  func testAVeryLongAndADuplicatedListStillMatchExactly() {
    let g = gate()
    let long = String(repeating: "a", count: 10_000)
    g.setIgnored([long, long, "com.example.vault", "com.example.vault"])
    XCTAssertEqual(g.check(source: { long }), .ignoredApp)
    XCTAssertNil(g.check(source: { long + "b" }))
    XCTAssertNil(g.check(source: { String(long.dropLast()) }))
    XCTAssertEqual(g.check(source: { "com.example.vault" }), .ignoredApp)
  }

  func testAnEmptyListAfterAFullOneStopsSkipping() {
    let g = gate()
    g.setIgnored(["x.y"])
    XCTAssertEqual(g.check(source: { "x.y" }), .ignoredApp)
    g.setIgnored([])
    var asked = 0
    XCTAssertNil(g.check(source: { asked += 1; return "x.y" }))
    XCTAssertEqual(asked, 0)
  }

  func testTheMarkerIsTrimmedOfNewlinesAndTabsToo() {
    XCTAssertEqual(
      CaptureGate.sourceApp(
        types: [CaptureGate.sourceMarkerType], marker: { "\n\tcom.example.vault \r\n" },
        front: { "front" }),
      "com.example.vault")
    XCTAssertEqual(
      CaptureGate.sourceApp(
        types: [CaptureGate.sourceMarkerType], marker: { "" }, front: { "front" }),
      "front")
  }

  func testNoFrontAppAndNoMarkerIsUnknown() {
    XCTAssertNil(
      CaptureGate.sourceApp(
        types: ["public.utf8-plain-text"], marker: { "x" }, front: { nil }))
  }

  // MARK: the watcher

  func testSecretMarkerArrivingAfterTheGatePassedStillWinsBeforeAnyRead() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    let poller = make(pb, g)
    pb.copy(nil)  // first look: no text yet, gate passed
    poller.tick()
    let readsBefore = pb.textReads  // the one empty read of the first look
    pb.typeIdentifiers = ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
    pb.text = "hunter2"
    poller.tick()
    XCTAssertEqual(types, ["concealed"])
    XCTAssertEqual(pb.textReads, readsBefore, "no read once the marker was seen")
  }

  func testAnIgnoredCopyThenAnAllowedCopyAreBothHandled() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    let poller = make(pb, g)
    front = "com.example.vault"
    pb.copy("password")
    poller.tick()
    front = "com.apple.TextEdit"
    pb.copy("hello")
    poller.tick()
    XCTAssertEqual(types, ["ignoredApp", "text"])
    XCTAssertEqual(pb.textReads, 1, "only the allowed copy was read")
  }

  func testTheMarkerIsReadOnceAtMostAndNotAtAllWithAnEmptyList() {
    let pb = GatePasteboard()
    let g = gate()
    let poller = make(pb, g)
    pb.copy("hello", marker: "com.example.vault")
    poller.tick()
    XCTAssertEqual(pb.markerReads, 0, "empty list: the source is never asked")
    XCTAssertEqual(frontReads, 0)

    g.setIgnored(["other.app"])
    pb.copy(nil, marker: "com.example.vault")
    poller.tick()
    poller.tick()
    poller.tick()
    XCTAssertEqual(pb.markerReads, 1)
  }

  func testEveryEmittedEventOfASkipCarriesOnlyItsType() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    let poller = make(pb, g)
    pb.copy("p", marker: "com.example.vault")
    poller.tick()
    g.setPause(-1)
    pb.copy("q")
    poller.tick()
    for e in events { XCTAssertEqual(Set(e.keys), ["type"]) }
    XCTAssertEqual(types, ["ignoredApp"])
  }

  func testAPausedCopyThenResumeCapturesTheNextOne() {
    let pb = GatePasteboard()
    let g = gate()
    g.setPause(-1)
    let poller = make(pb, g)
    pb.copy("while paused")
    poller.tick()
    g.setPause(0)
    // The paused copy is gone for good: another tick does not bring it back.
    poller.tick()
    poller.tick()
    XCTAssertEqual(events.count, 0)
    XCTAssertEqual(pb.textReads, 0)
    pb.copy("after")
    poller.tick()
    XCTAssertEqual(types, ["text"])
  }

  /// Design note: "While paused, no copy is added to history and no text is
  /// read." A pause that starts while the watcher is still waiting for a
  /// copy's text (the copy was made just before) must stop that read.
  func testAPauseStartedWhileWaitingForTheTextStopsTheRead() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["com.example.vault"])
    let poller = make(pb, g)
    pb.copy(nil)  // not readable yet: the watcher keeps trying
    poller.tick()
    // The first look tried a read and got nothing; that was before the
    // pause. (Developer fix round: the repro counted that read too.)
    let readsBeforePause = pb.textReads
    g.setPause(-1)  // the user pauses from the tray
    pb.text = "text that arrived after the pause"
    poller.tick()
    poller.tick()
    XCTAssertEqual(
      pb.textReads, readsBeforePause, "text was read after the pause started")
    XCTAssertEqual(events.count, 0)
  }

  /// The same for the ignore list: when the list changes while waiting, the
  /// copy is judged against the list that was in force at the first look
  /// (documented behaviour: once per copy).
  func testTheListIsAppliedOncePerCopyEvenIfItChangesWhileWaiting() {
    let pb = GatePasteboard()
    let g = gate()
    g.setIgnored(["other.app"])
    front = "com.example.vault"
    let poller = make(pb, g)
    pb.copy(nil)
    poller.tick()
    g.setIgnored(["com.example.vault"])
    pb.text = "late"
    poller.tick()
    poller.tick()
    XCTAssertEqual(types, ["text"])
  }
}
