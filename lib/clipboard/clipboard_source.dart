import 'dart:async';

enum SkipReason { concealed, tooLarge }

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
}
