import 'dart:io';

import '../clipboard/clipboard_source.dart';
import '../log/app_log.dart';
import 'history_opener.dart';
import 'history_service.dart';
import 'key_store.dart';
import 'memory_history_store.dart';

/// Opens the encrypted history and starts listening for copies. It never
/// throws: if anything is wrong the history runs in memory only, with a
/// banner, and nothing is written to disk.
///
/// Everything is logged through [deferred] from the start, so even a data
/// folder that cannot be found reaches the unified log (its mirror); the file
/// log is attached as soon as the folder is known.
Future<HistoryService> openAppHistory({
  required DeferredErrorLog deferred,
  required Future<Directory> Function() supportDirectory,
  required KeyStore keys,
  required ClipboardSource source,
}) async {
  OpenedHistory opened;
  try {
    final dir = await supportDirectory();
    await dir.create(recursive: true);
    deferred.attach(
      FileErrorLog(File('${dir.path}${Platform.pathSeparator}kusunga.log')),
    );
    opened = await openHistory(keys: keys, directory: dir.path, log: deferred);
  } catch (_) {
    deferred.log(LogCode.dataFolderUnavailable);
    opened = OpenedHistory(MemoryHistoryStore(), {HistoryNotice.memoryOnly});
  }
  return HistoryService(
    store: opened.store,
    notices: opened.notices,
    snippetStore: opened.snippets,
    source: source,
    log: deferred,
  )..start();
}
