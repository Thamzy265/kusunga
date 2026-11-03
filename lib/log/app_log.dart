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
