import 'dart:async';

enum SkipReason {
  concealed,
  tooLarge,

  /// From an app on the ignore list (M1.6). Native code decided before
  /// reading; the app is never named.
  ignoredApp,
}

/// What the native watcher reports. Native code checks the secret-marker
/// formats and the size before it reads any text, and Dart checks again.
sealed class ClipboardEvent {
  const ClipboardEvent();
}

class ClipboardText extends ClipboardEvent {
  const ClipboardText(this.text, {this.ownMarker = false});
  final String text;

  /// The copy carries Kusunga's own pasteboard marker (the picker wrote it).
  /// Any app can add that marker, so it only means "move to top if already
  /// saved"; it never skips a check.
  final bool ownMarker;
}

/// A copy that must not be saved. There is never any text with it.
class ClipboardSkipped extends ClipboardEvent {
  const ClipboardSkipped(this.reason);
  final SkipReason reason;
}

/// Windows: the ignore list is not empty but the app a copy came from could
/// not be found, so the copy is captured as today (M1.6, fail open). Carries
/// nothing; it only counts for the log.
class ClipboardSourceUnknown extends ClipboardEvent {
  const ClipboardSourceUnknown();
}

/// The clipboard could not be read (for example another app held it).
class ClipboardReadError extends ClipboardEvent {
  const ClipboardReadError(this.code);
  final String code;
}

/// Mac "Paste from Other Apps" state.
enum PasteAccess {
  allowed,

  /// Ask or deny: Kusunga cannot read copies without the user's say-so.
  needsSetup,

  /// Windows, or a macOS without the setting.
  notApplicable,
}

abstract interface class ClipboardSource {
  Stream<ClipboardEvent> get events;
  Future<PasteAccess> pasteAccess();

  /// Puts [text] on the clipboard as Kusunga's own change: native code
  /// remembers the change number it made (Mac changeCount, Windows
  /// GetClipboardSequenceNumber) and the watcher skips that one change, so a
  /// copied snippet is not added to history (PM decision D1). Returns false if
  /// it could not be written.
  Future<bool> writeOwn(String text);

  /// Sends the pause to the native watcher (M1.6, ADR 0005): 0 not paused,
  /// -1 until resumed, otherwise the end time in ms since 1970. The watcher
  /// compares it with the wall clock before reading each copy. False if
  /// native code could not be told.
  Future<bool> setCapturePause(int until);

  /// Sends the ignore list to the native watcher: copies from these apps are
  /// skipped before they are read. The same ids typed shortcuts get. False
  /// if native code could not be told.
  Future<bool> setCaptureIgnored(List<String> appIds);
}
