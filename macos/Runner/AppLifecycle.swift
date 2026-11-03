import Cocoa

/// Lets Dart flush and close the database before the app quits, on every exit
/// path (Cmd+Q, Dock Quit, tray Quit, log out, shut down). Answers once.
final class TerminationCoordinator {
  private let flush: ((@escaping () -> Void) -> Void)?
  private let reply: () -> Void
  private let timeout: TimeInterval
  private var flushing = false
  private var replied = false

  /// [flush] asks Dart to flush and calls its argument when Dart is done; nil
  /// means there is no Dart side to wait for. [reply] tells AppKit it may quit.
  init(
    flush: ((@escaping () -> Void) -> Void)?, reply: @escaping () -> Void,
    timeout: TimeInterval
  ) {
    self.flush = flush
    self.reply = reply
    self.timeout = timeout
  }

  func begin() -> NSApplication.TerminateReply {
    guard let flush = flush else { return .terminateNow }
    if flushing { return .terminateLater }
    flushing = true
    flush { [weak self] in self?.finish() }
    // Never hang the quit if Dart does not answer.
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish() }
    return .terminateLater
  }

  private func finish() {
    if replied { return }
    replied = true
    reply()
  }
}
