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
    "pasteForcedPost", "pasteTargetElevated", "pasteTargetGone",
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
  static func shouldDismiss(target: pid_t?, targetAlive: Bool) -> Bool {
    !(target != nil && !targetAlive)
  }
}
