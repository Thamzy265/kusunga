import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../log/app_log.dart';
import 'history_store.dart';
import 'key_store.dart';
import 'memory_history_store.dart';
import 'migrations.dart';
import 'sqlite_history_store.dart';

/// Things the user is told about once the history is open.
enum HistoryNotice {
  /// History will not be kept after quit (keychain or disk not usable).
  memoryOnly,

  /// The old history could not be read, so a new one was started.
  readError,
}

class OpenedHistory {
  const OpenedHistory(this.store, this.notices);
  final HistoryStore store;
  final Set<HistoryNotice> notices;
}

String generateKeyHex(Random random) => [
  for (var i = 0; i < 32; i++)
    random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

/// Opens the encrypted history in [directory], following the failure plan in
/// `docs/design/clipboard-history.md`:
///  - keychain or disk not usable: memory only, nothing written to disk;
///  - file unreadable with the key: moved aside, a new empty history started.
Future<OpenedHistory> openHistory({
  required KeyStore keys,
  required String directory,
  required ErrorLog log,
  Random? random,
  DateTime Function()? today,
  bool Function(Database db)? cipherActive,
  List<Migration> migrations = kMigrations,
  Duration keyTimeout = const Duration(seconds: 15),
}) async {
  OpenedHistory memoryOnly() =>
      OpenedHistory(MemoryHistoryStore(), {HistoryNotice.memoryOnly});

  String keyHex;
  try {
    // A keychain prompt nobody answers would leave the window on the spinner
    // for ever: give up and run in memory.
    var key = await keys.read().timeout(keyTimeout);
    if (key == null) {
      key = generateKeyHex(random ?? Random.secure());
      await keys.write(key).timeout(keyTimeout);
      if (await keys.read().timeout(keyTimeout) != key) {
        log.log(LogCode.keychainMismatch);
        return memoryOnly();
      }
    }
    keyHex = key;
  } catch (error) {
    log.log(LogCode.keychainReadFailed, _keychainStatus(error));
    return memoryOnly();
  }

  final path = '$directory${Platform.pathSeparator}kusunga.db';
  try {
    Directory(directory).createSync(recursive: true);
  } catch (_) {
    log.log(LogCode.dataFolderUnavailable);
    return memoryOnly();
  }

  SqliteHistoryStore tryOpen() => SqliteHistoryStore.open(
    path: path,
    keyHex: keyHex,
    cipherActive: cipherActive,
    migrations: migrations,
  );

  try {
    return OpenedHistory(tryOpen(), {});
  } on EncryptionUnavailable {
    log.log(LogCode.encryptionUnavailable);
    return memoryOnly();
  } on Object catch (error) {
    log.log(
      LogCode.storeUnreadable,
      error is SqliteException ? error.extendedResultCode : null,
    );
  }

  // The file cannot be read with this key (wrong key, corrupt, or written by a
  // newer app). Keep it, and start a new history.
  try {
    _moveAside(path, (today ?? DateTime.now)());
    return OpenedHistory(tryOpen(), {HistoryNotice.readError});
  } on Object {
    log.log(LogCode.storeOpenFailed);
    return memoryOnly();
  }
}

void _moveAside(String path, DateTime day) {
  final stamp =
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  var target = '$path.unreadable-$stamp';
  for (var n = 2; File(target).existsSync(); n++) {
    target = '$path.unreadable-$stamp-$n';
  }
  File(path).renameSync(target);
}

/// The OSStatus number in a keychain error such as "Code: -34018, ...", or
/// null. Only the number is kept: the rest of the text is never logged.
int? _keychainStatus(Object error) {
  if (error is! PlatformException) return null;
  final match = RegExp(r'Code:\s*(-?\d{1,6})').firstMatch(error.message ?? '');
  return match == null ? null : int.parse(match.group(1)!);
}
