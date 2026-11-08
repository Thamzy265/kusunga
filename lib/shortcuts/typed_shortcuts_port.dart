import 'dart:async';
import 'dart:typed_data';

/// What the native watcher is doing (UI spec, "Status line").
enum TypedShortcutStatus {
  /// The switch is off; nothing watches keys.
  off,

  /// Watching keys.
  on,

  /// Mac: Input Monitoring is not allowed yet.
  needsPermission,

  /// Mac: another app turned on secure input (a password field, Terminal's
  /// Secure Keyboard Entry). Nothing is lost.
  paused,

  /// Mac: macOS turned the tap off and turning it on again failed.
  stopped,

  /// The tap or the Windows hook could not be started.
  failed,
}

/// How a replacement ended.
enum ReplaceOutcome {
  /// The code was deleted and the snippet pasted.
  replaced,

  /// The front app changed, or more keys came, between the match and the
  /// replacement: nothing was sent.
  cancelled,

  /// Keys could not be sent (no permission, or no key types "v"): the
  /// snippet is on the clipboard and the user pastes it (M1.3 toast).
  copied,

  /// The clipboard could not be written.
  failed,
}

/// One app the user can add to the ignore list ("Add app…"). Never logged.
class RunningApp {
  const RunningApp({required this.appId, required this.name, this.icon});

  /// Mac bundle id, or the Windows executable name in lower case.
  final String appId;
  final String name;

  /// PNG bytes, or null (Windows shows names only for now, lead Q4).
  final Uint8List? icon;
}

/// Things the native side tells Dart. Neither carries anything typed (ADR
/// 0004): a match is a snippet id and how many characters to delete.
sealed class TypedShortcutEvent {
  const TypedShortcutEvent();
}

class ShortcutMatched extends TypedShortcutEvent {
  const ShortcutMatched(this.snippetId, this.deleteCount);
  final int snippetId;
  final int deleteCount;
}

class ShortcutStatusChanged extends TypedShortcutEvent {
  const ShortcutStatusChanged(this.status);
  final TypedShortcutStatus status;
}

/// The native typed-shortcut watcher (Swift on Mac, C++ on Windows). These
/// are all the calls there are (design note, "Dart side"); none carries a
/// typed character.
abstract interface class TypedShortcutsPort {
  Stream<TypedShortcutEvent> get events;

  /// Every shortcut and its snippet id, sent again after every change. No
  /// snippet text and no names.
  Future<void> setTable(List<({int id, String shortcut})> entries);

  /// The app ids where shortcuts never fire (this system's only).
  Future<void> setIgnored(List<String> appIds);

  /// Starts or stops watching. Never asks for a permission; answers the
  /// status after the change.
  Future<TypedShortcutStatus> setEnabled(bool on);

  Future<TypedShortcutStatus> status();

  /// Deletes [deleteCount] characters and pastes [text] (the snippet), then
  /// puts the previous clipboard text back after 0.5 s (PM decision D2).
  Future<ReplaceOutcome> replace(int deleteCount, String text);

  /// The apps running now, for "Add app…".
  Future<List<RunningApp>> runningApps();

  /// Mac: shows macOS's Input Monitoring prompt (only from the explanation
  /// card's Continue). Answers whether it is allowed now.
  Future<bool> requestListenAccess();

  /// Mac: opens Privacy & Security > Input Monitoring.
  Future<void> openInputMonitoringSettings();
}
