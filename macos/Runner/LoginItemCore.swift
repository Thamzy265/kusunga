import Foundation

/// Launch at login (M1.7, docs/design/settings-and-expiry.md, "Launch at
/// login"). Foundation only, so it is unit tested without the app
/// (tool/test_mac_login_item.sh); `LoginItemBridge.swift` connects it to
/// `SMAppService.mainApp` (macOS 13 and later) and to Dart.
///
/// The OS is the source of truth: nothing is stored by Kusunga.

/// What the channel answers. The raw values are the Dart contract
/// (lib/settings/login_item.dart).
enum LoginItemStatus: String {
  case enabled, notRegistered, requiresApproval, notFound, error, unsupported
}

/// The part of `SMAppService` Kusunga uses, so tests use a fake and never
/// register a real login item.
protocol LoginItemService: AnyObject {
  /// `.enabled`, `.notRegistered`, `.requiresApproval` or `.notFound`.
  var status: LoginItemStatus { get }
  func register() throws
  func unregister() throws
  func openSystemSettingsLoginItems()
}

/// A state and, for a failure, the OS error number. Nothing else crosses
/// the channel: no path and no user data.
struct LoginItemAnswer: Equatable {
  let state: LoginItemStatus
  let error: Int?

  var reply: [String: Any] {
    var r: [String: Any] = ["state": state.rawValue]
    if let error = error { r["error"] = error }
    return r
  }
}

final class LoginItemController {
  /// Nil before macOS 13, where `SMAppService` does not exist (PM decision
  /// D4 B: the switch is shown off and disabled).
  private let service: LoginItemService?

  init(service: LoginItemService?) {
    self.service = service
  }

  func status() -> LoginItemAnswer {
    guard let service = service else { return LoginItemAnswer(state: .unsupported, error: nil) }
    return LoginItemAnswer(state: service.status, error: nil)
  }

  /// Registers or unregisters the app as a login item and answers the
  /// status afterwards. A call that throws while macOS still ends in the
  /// state asked for (already registered, needs approval) is not an error.
  func set(_ on: Bool) -> LoginItemAnswer {
    guard let service = service else { return LoginItemAnswer(state: .unsupported, error: nil) }
    let done: (LoginItemStatus) -> Bool =
      on
      ? { $0 == .enabled || $0 == .requiresApproval }
      : { $0 == .notRegistered }
    if done(service.status) { return LoginItemAnswer(state: service.status, error: nil) }
    do {
      if on { try service.register() } else { try service.unregister() }
    } catch {
      let after = service.status
      if done(after) { return LoginItemAnswer(state: after, error: nil) }
      return LoginItemAnswer(state: .error, error: (error as NSError).code)
    }
    return LoginItemAnswer(state: service.status, error: nil)
  }

  func openSettings() {
    service?.openSystemSettingsLoginItems()
  }
}

/// Whether this launch was macOS starting Kusunga at login (D5 A: then no
/// window opens, only the menu bar icon). The launch's "open application"
/// Apple event carries `keyAELaunchedAsLogInItem` in its `keyAEPropData`
/// parameter. When macOS doesn't say so, the window opens as before.
enum LoginLaunch {
  /// `kAEOpenApplication` ('oapp').
  static let openApplication: UInt32 = 0x6F61_7070
  /// `keyAEPropData` ('prdt').
  static let propData: UInt32 = 0x7072_6474
  /// `keyAELaunchedAsLogInItem` ('lgit').
  static let launchedAsLogInItem: UInt32 = 0x6C67_6974

  static func isLoginLaunch(eventID: UInt32?, propData: UInt32?) -> Bool {
    eventID == openApplication && propData == launchedAsLogInItem
  }

  static func showsWindowAtLaunch(eventID: UInt32?, propData: UInt32?) -> Bool {
    !isLoginLaunch(eventID: eventID, propData: propData)
  }
}
