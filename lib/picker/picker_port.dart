import 'dart:async';

import 'shortcut.dart';

/// What happened when native code tried to register the shortcut.
enum ShortcutRegistration {
  registered,

  /// Another app already owns this combination. The previous shortcut stays.
  taken,

  /// Any other failure, or no native side. The previous shortcut stays.
  failed,
}

/// How a paste ended. Everything except [pasted] means the text is on the
/// clipboard and the user has to press Cmd+V / Ctrl+V themselves.
enum PasteOutcome {
  pasted,

  /// Debug builds only: the debug switch posted the keystroke although macOS
  /// said it is not allowed (to test whether the event arrives). Treated as
  /// [pasted].
  pastedForced,

  /// Mac: Kusunga is not allowed to post key events.
  noPermission,

  /// The app that had focus did not come to the front within 500 ms.
  focusTimeout,

  /// The app that had focus quit, or there was none (Kusunga itself).
  targetGone,

  /// Windows: the app that had focus runs as administrator.
  targetElevated,

  /// Paste mode is "copy only", so no key was sent.
  copyOnly,

  /// The text could not be put on the clipboard.
  failed,
}

/// Things native code tells Dart.
sealed class PickerNativeEvent {
  const PickerNativeEvent();
}

/// The shortcut (or the tray item) was used. Native code remembered which app
/// had focus. It shows the picker window as soon as Dart has answered.
class ShortcutPressed extends PickerNativeEvent {
  const ShortcutPressed();
}

/// The picker lost focus (a click outside, another app came forward). Native
/// code has already put the window back.
class PickerDismissed extends PickerNativeEvent {
  const PickerDismissed();
}

/// The part of the Mac / Windows code that the picker uses. Kept small so
/// tests can replace it with a fake; `ChannelPickerPort` is the real one and
/// is tested against a mocked channel.
abstract interface class PickerPort {
  Stream<PickerNativeEvent> get events;

  /// Registers [shortcut] as the global shortcut. The new one is registered
  /// before the old one is released, so a failure keeps the old shortcut.
  Future<ShortcutRegistration> registerShortcut(PickerShortcut shortcut);
  Future<void> unregisterShortcut();

  /// The tray item "Open picker": same as pressing the shortcut.
  Future<void> openPicker();

  /// Esc: hides the picker, brings back the main window if it was open, and
  /// otherwise returns focus to the app that had it.
  Future<void> closePicker();

  /// Puts [text] on the clipboard (with Kusunga's own marker), hides the
  /// picker, gives focus back and, if [post] is true and it is safe, sends
  /// Cmd+V / Ctrl+V. Never throws. With [skipHistory] (a snippet, PM decision
  /// D1) native code remembers the change number it made, and the watcher
  /// skips that one change.
  Future<PasteOutcome> paste(
    String text, {
    required bool post,
    bool skipHistory = false,
  });

  /// Shows the small "Copied" toast near the pointer without taking focus.
  Future<void> showToast();
  Future<void> hideToast();

  /// A small number for the log, never content: 1 if posting events is
  /// allowed, 2 if the Accessibility status is trusted (read only), 4 if
  /// listening is allowed. Null if native code gave no answer.
  Future<int?> permissionSnapshot();

  /// Mac: may Kusunga post key events? Does not prompt. Windows: true.
  Future<bool> canPost();

  /// Mac: asks macOS for the permission (its own dialog). Only called from the
  /// "Allow pasting" button. Returns whether it is allowed now.
  Future<bool> requestPostAccess();
}
