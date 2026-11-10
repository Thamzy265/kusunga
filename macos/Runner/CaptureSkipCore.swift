import Foundation

/// Why a copy was not read (M1.6, ADR 0005). Secret markers are checked
/// before this, in the watcher, as in M1.2.
enum CaptureSkip: Equatable {
  /// The user paused history.
  case paused
  /// The copy came from an app on the ignore list.
  case ignoredApp
}

/// The pause and the ignore list, as Dart last sent them, and the rule that
/// uses them. Foundation only, so it is tested without launching Kusunga
/// (tool/test_mac_capture.sh).
///
/// The source app id lives only inside [check], for one copy: it is never
/// stored, logged or sent to Dart.
final class CaptureGate {
  static let shared = CaptureGate()

  /// The nspasteboard.org convention: the bundle id of the app that wrote
  /// the copy.
  static let sourceMarkerType = "org.nspasteboard.source"

  /// 0 not paused, -1 paused until resumed, otherwise the end time in ms
  /// since 1970 (UTC).
  private(set) var pausedUntil: Int64 = 0
  private var ignored: Set<String> = []
  private let now: () -> Int64

  init(now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
    self.now = now
  }

  /// Any value other than 0, -1 or an end time counts as "not paused".
  func setPause(_ until: Int64) {
    pausedUntil = until < -1 ? 0 : until
  }

  func setIgnored(_ appIds: [String]) {
    ignored = Set(appIds)
  }

  static func isPaused(until: Int64, nowMs: Int64) -> Bool {
    until == -1 || until > nowMs
  }

  /// The pause first, against the wall clock now, then the source app.
  /// [source] is asked only when the list is not empty and history is not
  /// paused. An unknown source is captured as today.
  func check(source: () -> String?) -> CaptureSkip? {
    if CaptureGate.isPaused(until: pausedUntil, nowMs: now()) { return .paused }
    if ignored.isEmpty { return nil }
    guard let app = source() else { return nil }
    return ignored.contains(app) ? .ignoredApp : nil
  }

  /// The app a copy came from: the pasteboard's source marker when it has
  /// one (decision D5 A), otherwise the front app. The marker is read only
  /// when its type is there; it is never the copy's text.
  static func sourceApp(
    types: [String], marker: () -> String?, front: () -> String?
  ) -> String? {
    if types.contains(sourceMarkerType), let id = marker()?.trimmingCharacters(
      in: .whitespacesAndNewlines), !id.isEmpty
    {
      return id
    }
    return front()
  }
}
