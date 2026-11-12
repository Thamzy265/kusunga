import 'dart:async';
import 'dart:io';

import '../history/history_opener.dart' show keychainStatus;
import '../history/history_service.dart';
import '../history/key_store.dart';
import '../log/app_log.dart';

/// What Delete everything removes (M1.8).
sealed class EraseTarget {
  const EraseTarget();
}

/// The default data folder and the key in the keychain.
class DefaultEraseTarget extends EraseTarget {
  const DefaultEraseTarget({required this.keys, required this.folder});
  final KeyStore keys;
  final Future<Directory> Function() folder;
}

/// A debug data profile: only its own folder. Its key is the default one,
/// shared with the real history, so it is never deleted, and launch at
/// login (shared with the real app) is left alone (brief; lead ruling G3).
class ProfileEraseTarget extends EraseTarget {
  const ProfileEraseTarget({required this.folder});
  final Future<Directory> Function() folder;
}

/// A rejected profile switch: the session was memory only and nothing was
/// read or written on disk, so nothing on disk is touched.
class NoDataEraseTarget extends EraseTarget {
  const NoDataEraseTarget();
}

sealed class EraseResult {
  const EraseResult();
}

/// The key could not be deleted: nothing was deleted, recording goes on.
class EraseFailed extends EraseResult {
  const EraseFailed();
}

/// Everything is deleted; [filesLeft] files could not be removed, but with
/// the key gone they can't be read.
class Erased extends EraseResult {
  const Erased(this.filesLeft);
  final int filesLeft;
}

/// The names Kusunga writes in its data folder.
bool _isKusungaFile(String name) =>
    name == 'kusunga.db' ||
    name == 'kusunga.db-wal' ||
    name == 'kusunga.db-shm' ||
    name == 'kusunga.db-journal' ||
    name == 'kusunga.db.bak' ||
    name.startsWith('kusunga.db.unreadable-') ||
    name == 'kusunga.log' ||
    name == 'kusunga.log.1';

/// Delete everything, in this order (design note, as changed by the lead's
/// ruling of 2026-11-12):
///  1. stop capture and the timers;
///  2. delete the key; if that fails, start them again and stop: nothing
///     was deleted (a memory-only session, whose keychain can't be used,
///     only logs it and goes on);
///  3. close the database (copies still waiting are dropped);
///  4. log `deleteEverythingDone`, stop the file log, delete the files;
///  5. turn launch at login off (D6 A). The caller then quits.
class DataEraser {
  DataEraser({
    required this.target,
    required this._log,
    required this._stopFileLog,
    this._turnOffLogin,
    void Function(FileSystemEntity entity)? deleteEntity,
    this.keyTimeout = const Duration(seconds: 30),
  }) : _delete = deleteEntity ?? _deleteOne;

  final EraseTarget target;
  final ErrorLog _log;
  final void Function() _stopFileLog;
  final Future<void> Function()? _turnOffLogin;
  final void Function(FileSystemEntity entity) _delete;

  /// A keychain prompt nobody answers counts as a failure.
  final Duration keyTimeout;

  static void _deleteOne(FileSystemEntity e) => e.deleteSync();

  Future<EraseResult> run(HistoryService history) async {
    history.stopCapture();
    final target = this.target;
    if (target is DefaultEraseTarget) {
      try {
        await target.keys.delete().timeout(keyTimeout);
      } catch (error) {
        _log.log(LogCode.deleteEverythingFailed, _errorNumber(error));
        if (!history.keychainUnusable) {
          history.resumeCapture();
          return const EraseFailed();
        }
      }
    }
    if (history.keychainUnusable || target is NoDataEraseTarget) {
      history.clear(); // the memory store is emptied
    }
    await history.close(saveWaiting: false);

    _log.log(LogCode.deleteEverythingDone);
    _stopFileLog();
    final left = switch (target) {
      DefaultEraseTarget(:final folder) => await _deleteFiles(folder),
      ProfileEraseTarget(:final folder) => await _deleteFolder(folder),
      NoDataEraseTarget() => 0,
    };
    if (target is DefaultEraseTarget) {
      try {
        await _turnOffLogin?.call();
      } catch (_) {
        // Quitting must go on; the login item service logs its own failure.
      }
    }
    return Erased(left);
  }

  /// Counts one failure and logs its number.
  bool _tryDelete(FileSystemEntity e) {
    try {
      _delete(e);
      return true;
    } catch (error) {
      _log.log(LogCode.deleteFileFailed, _errorNumber(error));
      return false;
    }
  }

  Future<int> _deleteFiles(Future<Directory> Function() folder) async {
    final List<FileSystemEntity> entries;
    try {
      entries = (await folder()).listSync(followLinks: false);
    } catch (error) {
      _log.log(LogCode.deleteFileFailed, _errorNumber(error));
      return 0;
    }
    var left = 0;
    for (final e in entries) {
      if (e is Directory) continue;
      if (!_isKusungaFile(e.uri.pathSegments.last)) continue;
      if (!_tryDelete(e)) left++;
    }
    return left;
  }

  /// The whole profile folder, files first, then folders from the deepest
  /// up. Links are removed, never followed.
  Future<int> _deleteFolder(Future<Directory> Function() folder) async {
    final Directory dir;
    final List<FileSystemEntity> entries;
    try {
      dir = await folder();
      if (!dir.existsSync()) return 0;
      entries = dir.listSync(recursive: true, followLinks: false);
    } catch (error) {
      _log.log(LogCode.deleteFileFailed, _errorNumber(error));
      return 0;
    }
    var left = 0;
    for (final e in entries.where((e) => e is! Directory)) {
      if (!_tryDelete(e)) left++;
    }
    final dirs = entries.whereType<Directory>().toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final d in [...dirs, dir]) {
      _tryDelete(d);
    }
    return left;
  }
}

int? _errorNumber(Object error) => switch (error) {
  FileSystemException(:final osError) => osError?.errorCode,
  _ => keychainStatus(error),
};
