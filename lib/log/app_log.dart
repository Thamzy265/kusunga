import 'dart:io';

/// Everything Kusunga may write to its log. The log takes a code from this
/// list and an optional number, never text, so clipboard content, hashes and
/// app names cannot end up in it.
enum LogCode {
  keychainReadFailed,
  keychainWriteFailed,
  keychainMismatch,
  keychainTimeout,
  encryptionUnavailable,
  dataFolderUnavailable,
  storeUnreadable,
  storeIncompatible,
  storeOpenFailed,
  writeFailed,
  readFailed,
  clipboardLocked,
  clipboardTooLarge,
  clipboardChannelError,
  accessCheckFailed,
  flushFailed,
  // M1.3 picker (design note, "Observability"): codes only, never content,
  // app names or window titles.
  hotkeyRegisterFailed,
  pasteFocusTimeout,
  pastePermissionMissing,
  // Copy-only for another reason: paste mode, a key still held, an unreadable
  // integrity level, or no key that types "v".
  pasteCopyOnly,
  // Permission state (detail: 1 post, 2 accessibility trusted, 4 listen) at
  // start-up and before each paste, and a debug-build forced post.
  permissionSnapshot,
  pasteForcedPost,
  pasteTargetElevated,
  pasteTargetGone,
  // M1.4 snippets (design note, "Observability"): codes only, never a name,
  // content or type.
  snippetSaveFailed,
  snippetDeleteFailed,
  snippetMoveFailed,
  snippetCapReached,
  // Memory-only or incompatible database: snippets can't be saved.
  snippetsUnavailable,
  // Every paste from the picker: detail 0 history, 1 snippet.
  pasteSource,
  // The copy kept before a migration could not be written: the file is left
  // as it is and this session is memory only (TB-1).
  migrationBackupFailed,
  // The whole text of a snippet could not be read for Edit (TB-2).
  snippetOpenFailed,
  // Debug builds only: a test data profile is in use (never its name or
  // path), it was refused (memory only; detail none = a bad name, 2 = a
  // link in its folder, 3 = a misspelled switch), or there was no key for
  // it to reuse (memory only; a profile never writes a key).
  dataProfileActive,
  dataProfileRejected,
  dataProfileNoKey,
  // M1.5 typed shortcuts (design note, "Observability"): codes only, never a
  // typed key, a shortcut, snippet text or an app name. shortcutTableSize
  // carries the number of shortcuts; shortcutHookFailed a Windows error
  // number.
  shortcutFired,
  shortcutCancelled,
  shortcutSkippedIgnoredApp,
  shortcutSkippedPassword,
  shortcutSkippedUnknownField,
  shortcutSkippedInjected,
  shortcutSkippedAdmin,
  shortcutTapReenabled,
  shortcutTapFailed,
  shortcutHookFailed,
  shortcutPermissionMissing,
  shortcutTableSize,

  // Debug builds only (Mac): QA's switch that lets software-sent keys fire
  // typed shortcuts is on (PM decision 2026-11-09). Logged by native code.
  shortcutSyntheticKeysAllowed,

  // M1.6 sensitive-content protection (design note, "Observability"): codes
  // only, never an app name or text. A copy from an ignored app was skipped
  // before it was read; history was paused (detail: 15 or 60 minutes, or -1
  // until resumed) or resumed (detail: 0 the user, 1 the timer); on Windows
  // the source app of a copy could not be found, so it was captured as today.
  captureSkippedIgnoredApp,
  capturePaused,
  captureResumed,
  captureSourceUnknown,
}

abstract interface class ErrorLog {
  /// [detail] is an optional error number (for example a SQLite result code).
  void log(LogCode code, [int? detail]);
}

/// Appends `time code detail` lines to a file and keeps it under 1 MB by
/// moving the old file to `<name>.1` (one old file is kept). A logging failure
/// is swallowed: the log must never crash the app.
///
/// The file is opened for each line, in append mode, so two writers (two
/// Kusunga processes) never overwrite each other's lines (BUG-L4), and a log
/// deleted or moved from outside starts again at its path (BUG-L2). Right
/// before every open, also after a rotation, the path is checked: a link put
/// in place of the log is never written through (BUG-P2 late link).
///
/// If the rotation cannot rename (`.1` is a folder, or locked), lines keep
/// going to the live file (BUG-L3); at twice the limit it starts over, so it
/// never grows past 2 MB.
class FileErrorLog implements ErrorLog {
  FileErrorLog(this.file, {DateTime Function()? now, this.maxBytes = 1000000})
    : _now = now ?? DateTime.now;

  final File file;
  final int maxBytes;
  final DateTime Function() _now;

  @override
  void log(LogCode code, [int? detail]) {
    try {
      final line =
          '${_now().toUtc().toIso8601String()} ${code.name}'
          '${detail == null ? '' : ' $detail'}\n';
      if (FileSystemEntity.isLinkSync(file.path)) return;
      var mode = FileMode.append;
      if (file.existsSync()) {
        final size = file.lengthSync();
        if (size >= maxBytes) {
          try {
            file.renameSync('${file.path}.1');
          } catch (_) {
            if (size >= 2 * maxBytes) mode = FileMode.write;
          }
          if (FileSystemEntity.isLinkSync(file.path)) return;
        }
      }
      file.writeAsStringSync(line, mode: mode);
    } catch (_) {
      // Nothing sensible to do: never throw from the log.
    }
  }

  /// Nothing is kept open; kept so callers can say they are done.
  void close() {}
}

class NullErrorLog implements ErrorLog {
  const NullErrorLog();
  @override
  void log(LogCode code, [int? detail]) {}
}

/// A log that can be used before the log file is known (the data folder is
/// found asynchronously). Codes sent early wait, at most 20 of them, and are
/// written in order when the real log is attached. Used once only: a second
/// [attach] is ignored.
class DeferredErrorLog implements ErrorLog {
  /// [mirror] (the unified log) gets every code at once; the file log, once it
  /// is known, gets the ones that waited.
  DeferredErrorLog({this.mirror});

  static const maxWaiting = 20;
  final ErrorLog? mirror;

  ErrorLog? _real;
  final _waiting = <(LogCode, int?)>[];

  void attach(ErrorLog real) {
    if (_real != null) return;
    _real = real;
    for (final (code, detail) in _waiting) {
      real.log(code, detail);
    }
    _waiting.clear();
  }

  @override
  void log(LogCode code, [int? detail]) {
    mirror?.log(code, detail);
    final real = _real;
    if (real != null) {
      real.log(code, detail);
      return;
    }
    _waiting.add((code, detail));
    if (_waiting.length > maxWaiting) _waiting.removeAt(0);
  }
}
