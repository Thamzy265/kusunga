import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_log_');
    file = File('${dir.path}/kusunga.log');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes the time, the code and the number, nothing else', () {
    final log = FileErrorLog(file, now: () => DateTime.utc(2026, 11, 3, 9));
    log.log(LogCode.writeFailed, 13);
    log.log(LogCode.clipboardLocked);
    expect(file.readAsLinesSync(), [
      '2026-11-03T09:00:00.000Z writeFailed 13',
      '2026-11-03T09:00:00.000Z clipboardLocked',
    ]);
  });

  test('keeps the file under the size limit with one old file', () {
    final log = FileErrorLog(file, maxBytes: 200);
    for (var i = 0; i < 30; i++) {
      log.log(LogCode.writeFailed, i);
    }
    expect(file.lengthSync(), lessThan(400));
    expect(File('${file.path}.1').existsSync(), isTrue);
  });

  test('never throws, even if the folder is gone', () {
    final log = FileErrorLog(File('${dir.path}/nope/kusunga.log'));
    expect(() => log.log(LogCode.writeFailed), returnsNormally);
  });

  test('the picker codes exist, with exactly the names in the design note', () {
    expect(
      LogCode.values.map((c) => c.name),
      containsAll([
        'hotkeyRegisterFailed',
        'pasteFocusTimeout',
        'pastePermissionMissing',
        'pasteCopyOnly',
        'permissionSnapshot',
        'pasteForcedPost',
        'pasteTargetElevated',
        'pasteTargetGone',
      ]),
    );
  });

  group('DeferredErrorLog', () {
    test(
      'holds codes until the real log is ready, then writes them in order',
      () {
        final late = DeferredErrorLog();
        late.log(LogCode.hotkeyRegisterFailed);
        late.log(LogCode.writeFailed, 5);
        final real = _Recording();
        late.attach(real);
        late.log(LogCode.pasteTargetGone);
        expect(real.lines, [
          'hotkeyRegisterFailed',
          'writeFailed 5',
          'pasteTargetGone',
        ]);
      },
    );

    test('keeps at most 20 waiting codes, newest last', () {
      final late = DeferredErrorLog();
      for (var i = 0; i < 30; i++) {
        late.log(LogCode.writeFailed, i);
      }
      final real = _Recording();
      late.attach(real);
      expect(real.lines.length, 20);
      expect(real.lines.first, 'writeFailed 10');
      expect(real.lines.last, 'writeFailed 29');
    });

    test('attaching twice keeps the first log and writes nothing twice', () {
      final late = DeferredErrorLog();
      late.log(LogCode.readFailed);
      final a = _Recording();
      final b = _Recording();
      late.attach(a);
      late.attach(b);
      late.log(LogCode.flushFailed);
      expect(a.lines, ['readFailed', 'flushFailed']);
      expect(b.lines, isEmpty);
    });
  });
}

class _Recording implements ErrorLog {
  final lines = <String>[];
  @override
  void log(LogCode code, [int? detail]) =>
      lines.add(detail == null ? code.name : '${code.name} $detail');
}
