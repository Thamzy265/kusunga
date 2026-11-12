import 'dart:async';
import 'dart:io';

import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/data/your_data_service.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';

class FakeKeyStore implements KeyStore {
  FakeKeyStore({this.stored});

  String? stored;
  Object? readError;

  /// If true, read never answers (a keychain prompt nobody has answered).
  bool hang = false;

  /// If true, write never answers.
  bool hangWrite = false;

  /// If true, a read after a write never answers.
  bool hangReadBack = false;
  Object? writeError;

  /// If set, a read after a write returns this instead of what was written.
  String? readBackOverride;
  var _written = false;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (hang || (_written && hangReadBack)) {
      return Completer<String?>().future;
    }
    if (readError != null) throw readError!;
    if (_written && readBackOverride != null) return readBackOverride;
    return stored;
  }

  @override
  Future<void> write(String keyHex) async {
    if (hangWrite) return Completer<void>().future;
    if (writeError != null) throw writeError!;
    stored = keyHex;
    _written = true;
    writes++;
  }

  Object? deleteError;
  int deletes = 0;
  Completer<void>? _deleteGate;

  /// The next delete waits until the returned completer completes.
  Completer<void> holdDelete() => _deleteGate = Completer<void>();

  /// Called at the start of [delete] (to record the order of steps).
  void Function()? onDelete;

  @override
  Future<void> delete() async {
    onDelete?.call();
    final gate = _deleteGate;
    if (gate != null) {
      _deleteGate = null;
      await gate.future;
    }
    if (deleteError != null) throw deleteError!;
    stored = null;
    deletes++;
  }
}

class FakeLog implements ErrorLog {
  final codes = <LogCode>[];
  final details = <int?>[];

  @override
  void log(LogCode code, [int? detail]) {
    codes.add(code);
    details.add(detail);
  }
}

class FakeClipboardSource implements ClipboardSource {
  FakeClipboardSource() {
    controller.onListen = () => calls.add('listen');
  }

  final controller = StreamController<ClipboardEvent>.broadcast(sync: true);
  PasteAccess access = PasteAccess.notApplicable;
  int accessChecks = 0;

  /// The capture calls (M1.6) and the start of listening, in order.
  final calls = <String>[];

  /// The last values sent with setCapturePause and setCaptureIgnored.
  int? sentPause;
  List<String>? sentIgnored;

  /// What setCapturePause answers (false: the native call failed).
  bool pauseAnswer = true;

  @override
  Future<bool> setCapturePause(int until) async {
    calls.add('setCapturePause');
    if (!pauseAnswer) return false;
    sentPause = until;
    return true;
  }

  /// What the next setCaptureIgnored calls answer, in order; then true.
  final ignoredAnswers = <bool>[];

  @override
  Future<bool> setCaptureIgnored(List<String> appIds) async {
    calls.add('setCaptureIgnored');
    if (ignoredAnswers.isNotEmpty && !ignoredAnswers.removeAt(0)) return false;
    sentIgnored = List.of(appIds);
    return true;
  }

  @override
  Stream<ClipboardEvent> get events => controller.stream;

  @override
  Future<PasteAccess> pasteAccess() async {
    accessChecks++;
    return access;
  }

  void copy(String text) => controller.add(ClipboardText(text));

  /// Texts written with [writeOwn] (the watcher skips these changes).
  final ownWrites = <String>[];
  bool writeOwnAnswer = true;

  @override
  Future<bool> writeOwn(String text) async {
    ownWrites.add(text);
    return writeOwnAnswer;
  }
}

/// A store whose writes can be made to fail, like a full disk.
class FlakyStore implements HistoryStore {
  FlakyStore(this.inner);
  final HistoryStore inner;
  bool failWrites = false;
  bool failClear = false;

  /// The history lists can't be read (a locked or damaged file).
  bool failReads = false;
  int closes = 0;

  void _maybeFail() {
    if (failWrites) throw const FileSystemException('disk full');
  }

  @override
  int get limit => inner.limit;
  @override
  int get count => inner.count;
  @override
  List<ClipItem> list() {
    if (failReads) throw const FileSystemException('locked');
    return inner.list();
  }

  @override
  List<ClipItem> listSince(int sinceMs) {
    if (failReads) throw const FileSystemException('locked');
    return inner.listSince(sinceMs);
  }

  @override
  int countOlderThan(int cutoffMs, {int? notBefore}) =>
      inner.countOlderThan(cutoffMs, notBefore: notBefore);
  @override
  int deleteOlderThan(int cutoffMs) {
    _maybeFail();
    return inner.deleteOlderThan(cutoffMs);
  }

  @override
  int setExpiryDays(int days, {int? deleteBefore}) {
    _maybeFail();
    return inner.setExpiryDays(days, deleteBefore: deleteBefore);
  }

  @override
  String? contentOf(int id, {int? notBefore}) =>
      inner.contentOf(id, notBefore: notBefore);
  @override
  int insertOrBump(String content, ClipKind kind, int nowMs) {
    _maybeFail();
    return inner.insertOrBump(content, kind, nowMs);
  }

  @override
  bool bumpIfPresent(String content, int nowMs) {
    _maybeFail();
    return inner.bumpIfPresent(content, nowMs);
  }

  @override
  String? readSetting(String key) => inner.readSetting(key);
  @override
  void writeSetting(String key, String value) {
    _maybeFail();
    inner.writeSetting(key, value);
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
  List<ClipRecord> records({int? notBefore}) {
    if (failReads) throw const FileSystemException('locked');
    return inner.records(notBefore: notBefore);
  }

  @override
  void compact() {
    _maybeFail();
    inner.compact();
  }

  @override
  ImportCounts importBundle(
    ExportBundle bundle, {
    required bool applySettings,
    int? notBefore,
    required int nowMs,
  }) {
    _maybeFail();
    return inner.importBundle(
      bundle,
      applySettings: applySettings,
      notBefore: notBefore,
      nowMs: nowMs,
    );
  }

  @override
  ImportCounts previewImport(
    ExportBundle bundle, {
    required bool applySettings,
    int? notBefore,
    required int nowMs,
  }) {
    _maybeFail();
    return inner.previewImport(
      bundle,
      applySettings: applySettings,
      notBefore: notBefore,
      nowMs: nowMs,
    );
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

/// A login-item port (M1.7) that answers [next], or waits on [hold].
class FakeLoginItemPort implements LoginItemPort {
  LoginItemAnswer next = const LoginItemAnswer(LoginItemState.off);

  /// When set, reads answer this instead of [next]: what the OS still has
  /// after a change that failed.
  LoginItemAnswer? reads;
  int statusCalls = 0;
  final setCalls = <bool>[];
  int openCalls = 0;
  Completer<LoginItemAnswer>? _held;

  /// The next call waits until the returned completer completes.
  Completer<LoginItemAnswer> hold() => _held = Completer<LoginItemAnswer>();

  Future<LoginItemAnswer> _answer([LoginItemAnswer? answer]) {
    final held = _held;
    _held = null;
    return held?.future ?? Future.value(answer ?? next);
  }

  @override
  Future<LoginItemAnswer> status() {
    statusCalls++;
    return _answer(reads);
  }

  @override
  Future<LoginItemAnswer> set(bool on) {
    setCalls.add(on);
    return _answer();
  }

  @override
  Future<void> openSettings() async => openCalls++;
}

/// The save and open dialogs (M1.8): answers the paths set here.
class FakeFilePort implements FilePort {
  String? savePath;
  String? openPath;
  String? suggested;
  int saves = 0;
  int opens = 0;
  Completer<String?>? _openGate;

  /// The next open dialog answers only when the completer completes.
  Completer<String?> holdOpen() => _openGate = Completer<String?>();

  @override
  Future<String?> pickSavePath(String suggestedName) async {
    saves++;
    suggested = suggestedName;
    return savePath;
  }

  @override
  Future<String?> pickOpenPath() async {
    opens++;
    final gate = _openGate;
    if (gate != null) {
      _openGate = null;
      return gate.future;
    }
    return openPath;
  }
}
