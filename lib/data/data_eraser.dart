import 'dart:async';
import 'dart:io';

import 'package:win32/win32.dart' show WindowsException;

import '../history/history_opener.dart' show keychainStatus;
import '../history/history_service.dart';
import '../history/key_store.dart';
import '../history/windows_key_store.dart' show win32ErrorNumber;
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

/// The key could not be deleted.
class EraseFailed extends EraseResult {
  const EraseFailed({this.stuck = false});

  /// False: the keychain refused, nothing was deleted, and recording goes
  /// on. True: the keychain never answered, so the key delete may still
  /// complete; recording stays stopped for good and Kusunga quits (T5).
  final bool stuck;
}

/// Everything is deleted; [filesLeft] files could not be removed.
class Erased extends EraseResult {
  const Erased(this.filesLeft, {this.leftUnreadable = false});
  final int filesLeft;

  /// True only when every file left is an encrypted database file and the
  /// key is gone, so none of them can be read and the message may say so.
  /// False when anything left is something else (a log, the WAL index, a
  /// link, a folder that couldn't be listed or is a link), or when the key
  /// may still be there (lead ruling R7a, 2026-11-13).
  final bool leftUnreadable;
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

/// Kusunga's encrypted database files: with the key gone, nothing in them
/// can be read. Not the logs, and not `-shm`, which is only the WAL's index
/// and isn't encrypted (R7a).
bool _isEncryptedDbFile(String name) =>
    name == 'kusunga.db' ||
    name == 'kusunga.db-wal' ||
    name == 'kusunga.db-journal' ||
    name == 'kusunga.db.bak' ||
    name.startsWith('kusunga.db.unreadable-');

/// Delete everything, in this order (design note, as changed by the lead's
/// ruling of 2026-11-12):
///  1. stop capture and the timers;
///  2. delete the key; if the keychain refuses, start them again and stop:
///     nothing was deleted. If it doesn't answer in time, see [_deleteKey]
///     (T5). A memory-only session, whose keychain can't be used, only logs
///     a failure and goes on;
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

  /// How long each keychain step is waited for: the delete, the read
  /// after it and, if the key is still there, the delete once more.
  final Duration keyTimeout;

  static void _deleteOne(FileSystemEntity e) => e.deleteSync();

  Future<EraseResult> run(HistoryService history) async {
    history.stopCapture();
    final target = this.target;
    var keyGone = false;
    if (target is DefaultEraseTarget) {
      // A memory-only session never opened the file with this key, so a
      // late answer can't hurt it: it is tried once and the rest goes on.
      final memoryOnly = history.keychainUnusable;
      final key = await _deleteKey(target.keys, waitForLate: !memoryOnly);
      keyGone = key == _Key.gone;
      if (!memoryOnly) {
        switch (key) {
          case _Key.gone:
            break;
          case _Key.kept:
            history.resumeCapture();
            return const EraseFailed();
          case _Key.unknown:
            // Recording is never started again in this run of Kusunga.
            return const EraseFailed(stuck: true);
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
      ProfileEraseTarget(:final folder) => (
        count: await _deleteFolder(folder),
        encrypted: false, // the profile's key is never deleted
      ),
      NoDataEraseTarget() => (count: 0, encrypted: false),
    };
    if (target is DefaultEraseTarget) {
      try {
        await _turnOffLogin?.call();
      } catch (_) {
        // Quitting must go on; the login item service logs its own failure.
      }
    }
    return Erased(left.count, leftUnreadable: keyGone && left.encrypted);
  }

  /// Deletes the key and says whether it is gone. A call that runs out of
  /// time is given up on but can't be cancelled, so it may still remove the
  /// key later (T5, lead ruling 2026-11-12). The key is then read again:
  ///  - gone: the deletion carries on;
  ///  - still there, or the read fails: the call is waited for once more.
  ///    If it answers, its answer counts. If not, the result is unknown and
  ///    recording must not start again while the call is still out there.
  /// [deleteEverythingFailed] is logged once, for a key that is not gone.
  Future<_Key> _deleteKey(KeyStore keys, {required bool waitForLate}) async {
    final call = Future.sync(keys.delete);
    try {
      await call.timeout(keyTimeout);
      return _Key.gone;
    } on TimeoutException {
      if (!waitForLate) return _failed(_Key.unknown);
    } catch (error) {
      return _failed(_Key.kept, error);
    }
    try {
      if (await keys.read().timeout(keyTimeout) == null) return _Key.gone;
    } catch (_) {
      // Can't tell: as if the key were still there.
    }
    try {
      await call.timeout(keyTimeout);
      return _Key.gone;
    } on TimeoutException {
      return _failed(_Key.unknown);
    } catch (error) {
      return _failed(_Key.kept, error);
    }
  }

  _Key _failed(_Key key, [Object? error]) {
    _log.log(
      LogCode.deleteEverythingFailed,
      error == null ? null : _errorNumber(error),
    );
    return key;
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

  /// A data or profile folder that is itself a link is never followed, so
  /// nothing in the folder it points to is deleted (T8). The link stays,
  /// and counts as one thing that could not be removed.
  bool _refuseLink(Directory dir) {
    if (FileSystemEntity.typeSync(dir.path, followLinks: false) !=
        FileSystemEntityType.link) {
      return false;
    }
    _log.log(LogCode.deleteFileFailed);
    return true;
  }

  /// A folder that can't be found or listed counts as one thing not
  /// removed: its files may still be there (T6).
  int _unlisted(Object error) {
    _log.log(LogCode.deleteFileFailed, _errorNumber(error));
    return 1;
  }

  /// The files left, and whether they are all encrypted database files.
  Future<({int count, bool encrypted})> _deleteFiles(
    Future<Directory> Function() folder,
  ) async {
    final List<FileSystemEntity> entries;
    try {
      final dir = await folder();
      if (_refuseLink(dir)) return (count: 1, encrypted: false);
      if (!dir.existsSync()) return (count: 0, encrypted: true);
      entries = dir.listSync(followLinks: false);
    } catch (error) {
      return (count: _unlisted(error), encrypted: false);
    }
    var left = 0;
    var encrypted = true;
    for (final e in entries) {
      if (e is Directory) continue;
      final name = e.uri.pathSegments.last;
      if (!_isKusungaFile(name)) continue;
      if (!_tryDelete(e)) {
        left++;
        if (e is! File || !_isEncryptedDbFile(name)) encrypted = false;
      }
    }
    return (count: left, encrypted: encrypted);
  }

  /// The whole profile folder, files first, then folders from the deepest
  /// up. Links inside it are removed, never followed; the folder itself is
  /// never followed either.
  Future<int> _deleteFolder(Future<Directory> Function() folder) async {
    final Directory dir;
    final List<FileSystemEntity> entries;
    try {
      dir = await folder();
      if (_refuseLink(dir)) return 1;
      if (!dir.existsSync()) return 0;
      entries = dir.listSync(recursive: true, followLinks: false);
    } catch (error) {
      return _unlisted(error);
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

/// Where the key stands after a delete: [kept] means the keychain answered
/// with a refusal; [unknown] means it never answered.
enum _Key { gone, kept, unknown }

int? _errorNumber(Object error) => switch (error) {
  FileSystemException(:final osError) => osError?.errorCode,
  // Never its message: that is looked up through Win32 calls.
  WindowsException(:final hr) => win32ErrorNumber(hr),
  _ => keychainStatus(error),
};
