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
}

abstract interface class ErrorLog {
  /// [detail] is an optional error number (for example a SQLite result code).
  void log(LogCode code, [int? detail]);
}

/// Appends `time code detail` lines to a file and keeps it under 1 MB by
/// moving the old file to `<name>.1` (one old file is kept). A logging failure
/// is swallowed: the log must never crash the app.
class FileErrorLog implements ErrorLog {
  FileErrorLog(this.file, {DateTime Function()? now, this.maxBytes = 1000000})
    : _now = now ?? DateTime.now;

  final File file;
  final int maxBytes;
  final DateTime Function() _now;

  @override
  void log(LogCode code, [int? detail]) {
    try {
      if (file.existsSync() && file.lengthSync() >= maxBytes) {
        file.renameSync('${file.path}.1');
      }
      final line =
          '${_now().toUtc().toIso8601String()} ${code.name}'
          '${detail == null ? '' : ' $detail'}\n';
      file.writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {
      // Nothing sensible to do: never throw from the log.
    }
  }
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
  static const maxWaiting = 20;

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
    final real = _real;
    if (real != null) {
      real.log(code, detail);
      return;
    }
    _waiting.add((code, detail));
    if (_waiting.length > maxWaiting) _waiting.removeAt(0);
  }
}
