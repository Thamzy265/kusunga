import Cocoa
import FlutterMacOS
import ServiceManagement

/// `SMAppService.mainApp`: the app itself as a login item, inside the App
/// Sandbox, with no helper app and no new entitlement (macOS 13 and later).
@available(macOS 13.0, *)
final class MainAppLoginItem: LoginItemService {
  var status: LoginItemStatus {
    switch SMAppService.mainApp.status {
    case .enabled: return .enabled
    case .notRegistered: return .notRegistered
    case .requiresApproval: return .requiresApproval
    case .notFound: return .notFound
    @unknown default: return .error
    }
  }

  func register() throws { try SMAppService.mainApp.register() }
  func unregister() throws { try SMAppService.mainApp.unregister() }
  func openSystemSettingsLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

/// Connects launch at login to Dart (M1.7).
///
/// Method channel `com.wnasoni.kusunga/login_item` (see
/// lib/settings/login_item.dart): `loginItemStatus` (no arguments) and
/// `setLoginItem` (a bool) answer `{state, error?}`; `openLoginItemsSettings`
/// (no arguments) opens System Settings › General › Login Items. No path and
/// no user data cross the channel. Dart logs the codes.
final class LoginItemBridge {
  static let shared = LoginItemBridge()

  private var channel: FlutterMethodChannel?
  private let controller: LoginItemController = {
    if #available(macOS 13.0, *) {
      return LoginItemController(service: MainAppLoginItem())
    }
    return LoginItemController(service: nil)
  }()

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.wnasoni.kusunga/login_item", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "loginItemStatus":
        result(self.controller.status().reply)
      case "setLoginItem":
        guard let on = call.arguments as? Bool else {
          result(FlutterError(code: "badArgs", message: nil, details: nil))
          return
        }
        result(self.controller.set(on).reply)
      case "openLoginItemsSettings":
        self.controller.openSettings()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }
}
