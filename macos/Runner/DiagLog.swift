import Foundation
import os

/// Diagnostics for the macOS unified log. Read with:
///   log show --predicate 'subsystem == "com.wnasoni.kusunga"' --info --last 10m
/// Codes from a closed list and small numbers only, marked public: never
/// clipboard content, app names or window titles. (The app's own log file sits in a protected
/// container that cannot be read from outside.)
enum DiagLog {
  private static let logger = Logger(subsystem: "com.wnasoni.kusunga", category: "diagnostics")

  /// The only names that are ever written: every Dart `LogCode` plus the codes
  /// the native side logs itself. A closed list, because any shape check would
  /// also let a card number, a phone number or a one-word secret through as
  /// "public" text. A test checks it against the Dart list and the sources.
  static let knownCodes: Set<String> = [
    // Dart LogCode (lib/log/app_log.dart)
    "keychainReadFailed", "keychainWriteFailed", "keychainMismatch", "keychainTimeout",
    "encryptionUnavailable", "dataFolderUnavailable", "storeUnreadable", "storeIncompatible",
    "storeOpenFailed", "writeFailed", "readFailed", "clipboardLocked", "clipboardTooLarge",
    "clipboardChannelError", "accessCheckFailed", "flushFailed", "hotkeyRegisterFailed",
    "pasteFocusTimeout", "pastePermissionMissing", "pasteCopyOnly", "permissionSnapshot",
    "pasteForcedPost", "pasteTargetElevated", "pasteTargetGone", "snippetSaveFailed",
    "snippetDeleteFailed", "snippetMoveFailed", "snippetCapReached", "snippetsUnavailable",
    "pasteSource", "migrationBackupFailed", "snippetOpenFailed", "dataProfileActive",
    "dataProfileRejected", "dataProfileNoKey", "shortcutFired", "shortcutCancelled",
    "shortcutSkippedIgnoredApp", "shortcutSkippedPassword", "shortcutSkippedUnknownField",
    "shortcutSkippedInjected", "shortcutSkippedAdmin", "shortcutTapReenabled",
    "shortcutTapFailed", "shortcutHookFailed", "shortcutPermissionMissing", "shortcutTableSize",
    // Native
    "pasteResult", "postKeyNone", "postKeyCode", "postForced", "postFrontmostOk", "postTiming",
    "postSourceState", "postSourceNil", "postTap", "postEventNil", "postSent",
    "targetTerminated", "pickerKeptTargetGone", "toastShown", "toastAppActive", "toastRecheck",
    "diagSelfTest",
  ]

  #if DEBUG
    /// Test probes only (compiled out of Release).
    static var extraCodesForTests: Set<String> = []
  #endif

  static func isCode(_ text: String) -> Bool {
    if knownCodes.contains(text) { return true }
    #if DEBUG
      return extraCodesForTests.contains(text)
    #else
      return false
    #endif
  }

  static func log(_ code: String, _ detail: Int? = nil) {
    guard isCode(code) else { return }
    if let detail = detail {
      logger.info("\(code, privacy: .public) \(detail, privacy: .public)")
    } else {
      logger.info("\(code, privacy: .public)")
    }
  }
}

/// When the picker loses focus because the app it came from quit, the picker
/// stays: Enter then copies and shows the "Copied" toast (the target is gone).
/// Any other loss of focus closes it.
enum DismissRule {
  static func shouldDismiss(target: pid_t?, targetQuit: Bool = false, targetAlive: Bool) -> Bool {
    !(target != nil && (targetQuit || !targetAlive))
  }
}

/// Decides what a lost focus means. The decision is taken a short moment later,
/// because macOS can report the quit before or after the focus change. The quit
/// only explains a focus loss that happens close to it (within [window]
/// seconds): when Kusunga stays the active app the quit changes no focus, and a
/// click 2 seconds later is the user's own and must close the picker.
final class DismissCoordinator {
  /// How close (in seconds) a lost focus must be to the quit to be caused by it.
  static let window: TimeInterval = 1.0

  private let now: () -> TimeInterval
  private var quitAt: TimeInterval?

  init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.now = now
  }

  var targetQuit: Bool { quitAt != nil }

  func noteTargetQuit() { quitAt = now() }

  /// A new opening, a closing or a paste: forget an earlier quit.
  func reset() { quitAt = nil }

  /// Only the quit notice explains a lost focus, not a pid that merely looks
  /// dead: the notice arrives at the moment of the quit, and a dead pid would
  /// keep the picker for every later click as well.
  func focusLost(
    target: pid_t?,
    schedule: (TimeInterval, @escaping () -> Void) -> Void,
    decide: @escaping (Bool) -> Void
  ) {
    let lostAt = now()
    schedule(0.12) { [weak self] in
      guard let self = self else { return }
      let explained = self.quitAt.map { abs($0 - lostAt) <= DismissCoordinator.window } ?? false
      let dismiss = DismissRule.shouldDismiss(
        target: target, targetQuit: explained, targetAlive: true)
      // One keep uses up the reason: the user can click away afterwards.
      if !dismiss { self.reset() }
      decide(dismiss)
    }
  }
}
