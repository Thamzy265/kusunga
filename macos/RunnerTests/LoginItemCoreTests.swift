import CoreServices
import XCTest

@testable import Kusunga

// M1.7 launch at login (docs/design/settings-and-expiry.md, "Launch at
// login"): the controller behind the `loginItemStatus` and `setLoginItem`
// calls, against a fake SMAppService, and the login-launch check (D5 A).
// Foundation only, so this file also runs as a standalone bundle without
// launching Kusunga or registering a real login item
// (tool/test_mac_login_item.sh).

private struct FakeError: Error, CustomNSError {
  let code: Int
  var errorCode: Int { code }
  static var errorDomain: String { "fake" }
}

private final class FakeService: LoginItemService {
  var status: LoginItemStatus = .notRegistered
  var registerError: Error?
  var unregisterError: Error?
  /// The status after a register or unregister call (what macOS reports).
  var statusAfterRegister: LoginItemStatus = .enabled
  var statusAfterUnregister: LoginItemStatus = .notRegistered
  /// The status macOS has after a call that threw; nil keeps it.
  var statusOnThrow: LoginItemStatus?
  var calls: [String] = []

  func register() throws {
    calls.append("register")
    if let e = registerError {
      if let s = statusOnThrow { status = s }
      throw e
    }
    status = statusAfterRegister
  }

  func unregister() throws {
    calls.append("unregister")
    if let e = unregisterError {
      if let s = statusOnThrow { status = s }
      throw e
    }
    status = statusAfterUnregister
  }

  func openSystemSettingsLoginItems() { calls.append("open") }
}

final class LoginItemControllerTests: XCTestCase {
  func testStatusIsWhatTheOSSays() {
    let service = FakeService()
    let c = LoginItemController(service: service)
    for s: LoginItemStatus in [.enabled, .notRegistered, .requiresApproval, .notFound] {
      service.status = s
      XCTAssertEqual(c.status(), LoginItemAnswer(state: s, error: nil))
    }
    XCTAssertEqual(service.calls, [], "reading never registers anything")
  }

  func testMacOS12IsUnsupportedAndNeverCallsTheService() {
    let c = LoginItemController(service: nil)
    XCTAssertEqual(c.status().state, .unsupported)
    XCTAssertEqual(c.set(true).state, .unsupported)
    XCTAssertEqual(c.set(false).state, .unsupported)
    c.openSettings()  // nothing to open, no crash
  }

  func testTurningOnRegistersAndAnswersTheNewStatus() {
    let service = FakeService()
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(true), LoginItemAnswer(state: .enabled, error: nil))
    XCTAssertEqual(service.calls, ["register"])
  }

  func testTurningOnMayNeedApproval() {
    let service = FakeService()
    service.statusAfterRegister = .requiresApproval
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(true).state, .requiresApproval)
  }

  func testAlreadyOnDoesNotRegisterAgain() {
    let service = FakeService()
    service.status = .enabled
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(true).state, .enabled)
    XCTAssertEqual(service.calls, [])
  }

  func testAFailedRegisterIsAnErrorWithItsNumber() {
    let service = FakeService()
    service.registerError = FakeError(code: 22)
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(true), LoginItemAnswer(state: .error, error: 22))
  }

  func testAThrowingRegisterThatStillLeftItRegisteredIsNotAnError() {
    // macOS throws "already registered" or "needs approval" while the item
    // is in fact there: the status decides.
    let service = FakeService()
    service.registerError = FakeError(code: 1)
    service.status = .requiresApproval
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(true), LoginItemAnswer(state: .requiresApproval, error: nil))
  }

  func testNotFoundAfterRegisterIsReportedAsNotFound() {
    let service = FakeService()
    service.statusAfterRegister = .notFound
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(true).state, .notFound)
  }

  func testTurningOffUnregisters() {
    let service = FakeService()
    service.status = .enabled
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(false), LoginItemAnswer(state: .notRegistered, error: nil))
    XCTAssertEqual(service.calls, ["unregister"])
  }

  func testTurningOffWhenAlreadyOffDoesNothing() {
    let service = FakeService()
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(false).state, .notRegistered)
    XCTAssertEqual(service.calls, [])
  }

  func testAFailedUnregisterIsAnErrorWithItsNumber() {
    let service = FakeService()
    service.status = .enabled
    service.unregisterError = FakeError(code: 5)
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(false), LoginItemAnswer(state: .error, error: 5))
  }

  func testAThrowingUnregisterThatStillRemovedItIsNotAnError() {
    let service = FakeService()
    service.status = .enabled
    service.unregisterError = FakeError(code: 6)
    service.statusOnThrow = .notRegistered
    let c = LoginItemController(service: service)
    XCTAssertEqual(c.set(false), LoginItemAnswer(state: .notRegistered, error: nil))
  }

  func testOpenSettingsOpensTheLoginItemsPane() {
    let service = FakeService()
    LoginItemController(service: service).openSettings()
    XCTAssertEqual(service.calls, ["open"])
  }

  func testTheReplyHasOnlyAStateAndAnOptionalNumber() {
    XCTAssertEqual(
      LoginItemAnswer(state: .enabled, error: nil).reply as NSDictionary,
      ["state": "enabled"] as NSDictionary)
    XCTAssertEqual(
      LoginItemAnswer(state: .error, error: 3).reply as NSDictionary,
      ["state": "error", "error": 3] as NSDictionary)
    XCTAssertEqual(
      LoginItemAnswer(state: .unsupported, error: nil).reply as NSDictionary,
      ["state": "unsupported"] as NSDictionary)
  }

  func testStateNamesMatchTheDartChannelContract() {
    // lib/settings/login_item.dart, ChannelLoginItemPort._states.
    XCTAssertEqual(
      [LoginItemStatus.enabled, .notRegistered, .requiresApproval, .notFound, .error, .unsupported]
        .map(\.rawValue),
      ["enabled", "notRegistered", "requiresApproval", "notFound", "error", "unsupported"])
  }
}

final class LoginLaunchTests: XCTestCase {
  func testTheFourCharCodesAreTheSDKOnes() {
    XCTAssertEqual(LoginLaunch.openApplication, UInt32(kAEOpenApplication))
    XCTAssertEqual(LoginLaunch.propData, UInt32(keyAEPropData))
    XCTAssertEqual(LoginLaunch.launchedAsLogInItem, UInt32(keyAELaunchedAsLogInItem))
  }

  func testOnlyAnOpenApplicationEventMarkedAsLoginItemIsALoginLaunch() {
    XCTAssertTrue(
      LoginLaunch.isLoginLaunch(
        eventID: LoginLaunch.openApplication, propData: LoginLaunch.launchedAsLogInItem))
    XCTAssertFalse(
      LoginLaunch.isLoginLaunch(eventID: LoginLaunch.openApplication, propData: nil))
    XCTAssertFalse(
      LoginLaunch.isLoginLaunch(
        eventID: LoginLaunch.openApplication, propData: UInt32(keyAELaunchedAsServiceItem)))
    XCTAssertFalse(
      LoginLaunch.isLoginLaunch(
        eventID: UInt32(kAEReopenApplication), propData: LoginLaunch.launchedAsLogInItem))
    XCTAssertFalse(LoginLaunch.isLoginLaunch(eventID: nil, propData: nil))
  }

  func testTheWindowShowsUnlessItIsALoginLaunch() {
    // D5 A: a login start opens no window; anything else (or no event at
    // all, when macOS can't tell) opens it as today.
    XCTAssertFalse(
      LoginLaunch.showsWindowAtLaunch(
        eventID: LoginLaunch.openApplication, propData: LoginLaunch.launchedAsLogInItem))
    XCTAssertTrue(LoginLaunch.showsWindowAtLaunch(eventID: nil, propData: nil))
    XCTAssertTrue(
      LoginLaunch.showsWindowAtLaunch(eventID: LoginLaunch.openApplication, propData: nil))
  }
}
