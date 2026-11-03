import 'dart:async';
import 'dart:io';

import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/log/app_log.dart';

class FakeKeyStore implements KeyStore {
  FakeKeyStore({this.stored});

  String? stored;
  Object? readError;
  Object? writeError;

  /// If set, a read after a write returns this instead of what was written.
  String? readBackOverride;
  var _written = false;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (readError != null) throw readError!;
    if (_written && readBackOverride != null) return readBackOverride;
    return stored;
  }

  @override
  Future<void> write(String keyHex) async {
    if (writeError != null) throw writeError!;
    stored = keyHex;
    _written = true;
    writes++;
  }
}

class FakeLog implements ErrorLog {
  final codes = <LogCode>[];

  @override
  void log(LogCode code, [int? detail]) => codes.add(code);
}

class FakeClipboardSource implements ClipboardSource {
  final controller = StreamController<ClipboardEvent>.broadcast(sync: true);
  PasteAccess access = PasteAccess.notApplicable;
  int accessChecks = 0;

  @override
  Stream<ClipboardEvent> get events => controller.stream;

  @override
  Future<PasteAccess> pasteAccess() async {
    accessChecks++;
    return access;
  }

  void copy(String text) => controller.add(ClipboardText(text));
}

/// A store whose writes can be made to fail, like a full disk.
class FlakyStore implements HistoryStore {
  FlakyStore(this.inner);
  final HistoryStore inner;
  bool failWrites = false;
  bool failClear = false;
  int closes = 0;

  void _maybeFail() {
    if (failWrites) throw const FileSystemException('disk full');
  }

  @override
  int get limit => inner.limit;
  @override
  int get count => inner.count;
  @override
  List<ClipItem> list() => inner.list();
  @override
  String? contentOf(int id) => inner.contentOf(id);
  @override
  int insertOrBump(String content, ClipKind kind, int nowMs) {
    _maybeFail();
    return inner.insertOrBump(content, kind, nowMs);
  }

  @override
  ClipRecord? delete(int id) => inner.delete(id);
  @override
  void restore(ClipRecord record) => inner.restore(record);
  @override
  int clear() {
    if (failClear) throw const FileSystemException('locked');
    return inner.clear();
  }

  @override
  int countRemovedBy(int newLimit) => inner.countRemovedBy(newLimit);
  @override
  void setLimit(int newLimit) => inner.setLimit(newLimit);
  @override
  void close() {
    closes++;
    inner.close();
  }
}
