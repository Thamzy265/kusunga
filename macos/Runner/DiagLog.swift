import Foundation
import os

/// Diagnostics for the macOS unified log. Read with:
///   log show --predicate 'subsystem == "com.wnasoni.kusunga"' --info --last 10m
/// Codes and small numbers only, marked public: never clipboard content, app
/// names or window titles. (The app's own log file sits in a protected
/// container that cannot be read from outside.)
enum DiagLog {
  private static let logger = Logger(subsystem: "com.wnasoni.kusunga", category: "diagnostics")

  /// A code is 1 to 40 letters and digits, so no text can be passed as one.
  static func isCode(_ text: String) -> Bool {
    guard (1...40).contains(text.utf8.count) else { return false }
    return text.utf8.allSatisfy {
      ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
    }
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
