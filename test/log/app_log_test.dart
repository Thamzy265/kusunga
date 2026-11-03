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
}
