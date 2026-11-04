import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/open_app_history.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

/// F5/C2: a data folder that cannot be found is still logged (to the unified
/// log mirror), because the log goes through the deferred log from the start.
void main() {
  test('a failing data-folder provider: memory only, and the code is still '
      'logged to the mirror', () async {
    final mirror = FakeLog();
    final deferred = DeferredErrorLog(mirror: mirror);
    final service = await openAppHistory(
      deferred: deferred,
      supportDirectory: () async =>
          throw const FileSystemException('no folder'),
      keys: FakeKeyStore(),
      source: FakeClipboardSource(),
    );
    addTearDown(service.dispose);
    expect(service.banners, contains(HistoryBanner.memoryOnly));
    expect(mirror.codes, contains(LogCode.dataFolderUnavailable));
  });

  test(
    'a good folder: the file log gets the codes and the history opens',
    () async {
      final dir = Directory.systemTemp.createTempSync('kusunga_app_history_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final mirror = FakeLog();
      final deferred = DeferredErrorLog(mirror: mirror);
      deferred.log(LogCode.hotkeyRegisterFailed); // before the folder is known
      final service = await openAppHistory(
        deferred: deferred,
        supportDirectory: () async => dir,
        keys: FakeKeyStore(),
        source: FakeClipboardSource(),
      );
      addTearDown(service.dispose);
      expect(service.banners, isEmpty);
      expect(mirror.codes, [LogCode.hotkeyRegisterFailed]);
      final text = File('${dir.path}/kusunga.log').readAsStringSync();
      expect(text, contains('hotkeyRegisterFailed'));
    },
  );

  test(
    'codes the history writes after opening reach the mirror once',
    () async {
      final dir = Directory.systemTemp.createTempSync('kusunga_app_history_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final mirror = FakeLog();
      final deferred = DeferredErrorLog(mirror: mirror);
      await openAppHistory(
        deferred: deferred,
        supportDirectory: () async => dir,
        keys: FakeKeyStore()..readError = StateError('locked'),
        source: FakeClipboardSource(),
      ).then((s) => addTearDown(s.dispose));
      expect(
        mirror.codes.where((c) => c == LogCode.keychainReadFailed).length,
        1,
      );
    },
  );
}
