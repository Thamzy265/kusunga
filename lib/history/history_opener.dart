import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

import '../log/app_log.dart';
import 'history_store.dart';
import 'key_store.dart';
import 'memory_history_store.dart';
import '../snippets/memory_snippet_store.dart';
import '../snippets/snippet_service.dart' show SnippetsUnavailable;
import '../snippets/snippet_store.dart';
import 'migrations.dart';
import 'sqlite_history_store.dart';

/// Things the user is told about once the history is open.
enum HistoryNotice {
  /// History will not be kept after quit (keychain or disk not usable).
  memoryOnly,

  /// The old history could not be read (wrong key, damaged), so a new one was
  /// started. The old file was moved aside, not deleted.
  readError,

  /// The file was written by a newer or different version of Kusunga, or a
  /// migration failed. It is left exactly as it is; this session is memory
  /// only.
  incompatible,

  /// The safety copy before a migration could not be written. The file is
  /// left exactly as it is; this session is memory only.
  backupFailed,
}

class OpenedHistory {
  OpenedHistory(
    this.store,
    this.notices, [
    SnippetStore? snippets,
    this.snippetsUnavailable,
  ]) : snippets =
           snippets ??
           (store is SqliteHistoryStore
               ? store.snippetStore()
               : MemorySnippetStore());
  final HistoryStore store;
  final Set<HistoryNotice> notices;

  /// The snippets: in the same encrypted file, or in memory when the history
  /// is (memory-only or incompatible).
  final SnippetStore snippets;

  /// Set when the cause is not clear from [notices] (a failed migration is
  /// "incompatible" for history but has its own snippets banner).
  final SnippetsUnavailable? snippetsUnavailable;
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
  Duration keyTimeout = const Duration(seconds: 30),
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
  } on TimeoutException {
    log.log(LogCode.keychainTimeout);
    return memoryOnly();
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
  } on UnsupportedSchemaVersion {
    log.log(LogCode.storeIncompatible);
    return OpenedHistory(MemoryHistoryStore(), {HistoryNotice.incompatible});
  } on MigrationBackupFailed {
    // The file is fine; only the copy could not be made. It is left exactly
    // as it is (never moved aside as unreadable) and this session is memory
    // only, as for a failed migration.
    log.log(LogCode.migrationBackupFailed);
    return OpenedHistory(MemoryHistoryStore(), {HistoryNotice.backupFailed});
  } on MigrationFailed {
    log.log(LogCode.storeIncompatible);
    return OpenedHistory(
      MemoryHistoryStore(),
      {HistoryNotice.incompatible},
      null,
      SnippetsUnavailable.updateFailed,
    );
  } on Object catch (error) {
    log.log(
      LogCode.storeUnreadable,
      error is SqliteException ? error.extendedResultCode : null,
    );
  }

  // The file cannot be read with this key (wrong key, damaged pages). Keep
  // it aside, and start a new history. (A file from a newer version, or one
  // that failed to migrate, is not moved: see above.)
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
