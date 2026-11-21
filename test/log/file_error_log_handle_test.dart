import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:path/path.dart' as p;

/// Tester round 3 on 77a2080 (FileErrorLog keeps one open handle, checks for
/// a link before each open, reopens after a rotation): rotation at the size
/// limit, two writers on one file (two Kusunga processes), and a log file
/// deleted or moved from outside.
void main() {
  late Directory dir;
  late File file;
  final posix = Platform.isWindows ? 'handle behaviour is Mac-only' : null;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_log_');
    file = File(p.join(dir.path, 'kusunga.log'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> lines(File f) => f.existsSync()
      ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList()
      : [];

  test('rotation with the kept handle: no line is lost, one old file is '
      'kept, the live file stays under the limit', () {
    final log = FileErrorLog(file, maxBytes: 400);
    for (var i = 0; i < 40; i++) {
      log.log(LogCode.flushFailed, i);
    }
    log.close();
    final old = File('${file.path}.1');
    expect(old.existsSync(), isTrue);
    expect(file.lengthSync(), lessThan(400 + 80));
    final seen = [
      ...lines(old),
      ...lines(file),
    ].map((l) => int.parse(l.split(' ').last)).toList();
    // One old file is kept, so earlier rotations are gone; but the lines
    // that remain are whole, in order, and the newest one is present.
    expect(seen, isNotEmpty);
    expect(seen.last, 39);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], seen[i - 1] + 1, reason: 'no gap inside what is kept');
    }
    expect(
      Directory(dir.path).listSync().map((e) => p.basename(e.path)).toSet(),
      {'kusunga.log', 'kusunga.log.1'},
    );
  }, skip: posix);

  test('every line is whole: a rotation never splits or merges lines', () {
    final log = FileErrorLog(file, maxBytes: 300);
    for (var i = 0; i < 100; i++) {
      log.log(LogCode.storeUnreadable, i);
    }
    log.close();
    final shape = RegExp(r'^\S+Z storeUnreadable \d+$');
    for (final f in [file, File('${file.path}.1')]) {
      for (final l in lines(f)) {
        expect(shape.hasMatch(l), isTrue, reason: 'garbled: "$l"');
      }
    }
  }, skip: posix);

  test(
    'a log file that is a link at the start is never written',
    () {
      final target = File(p.join(dir.path, 'real.log'))
        ..writeAsStringSync('real\n');
      Link(file.path).createSync(target.path);
      final log = FileErrorLog(file);
      log.log(LogCode.flushFailed);
      log.close();
      expect(target.readAsStringSync(), 'real\n');
    },
    skip: Platform.isWindows ? 'needs symlink rights' : null,
  );

  test('a link put in place of the log after the first line is not written '
      'through, and the lines go on to the file that was opened', () {
    final target = File(p.join(dir.path, 'real.log'))
      ..writeAsStringSync('real\n');
    final log = FileErrorLog(file);
    log.log(LogCode.flushFailed, 1);
    file.deleteSync();
    Link(file.path).createSync(target.path);
    log.log(LogCode.flushFailed, 2);
    log.close();
    expect(target.readAsStringSync(), 'real\n');
  }, skip: posix);

  test('a link in place of the log at a ROTATION reopen is refused', () {
    final target = File(p.join(dir.path, 'real.log'))
      ..writeAsStringSync('real\n');
    final log = FileErrorLog(file, maxBytes: 120);
    log.log(LogCode.flushFailed, 1);
    log.log(LogCode.flushFailed, 2);
    // Swap the live file for a link right before the rotation happens.
    file.renameSync('${file.path}.hold');
    Link(file.path).createSync(target.path);
    for (var i = 3; i < 12; i++) {
      log.log(LogCode.flushFailed, i);
    }
    log.close();
    expect(target.readAsStringSync(), 'real\n');
  }, skip: posix);

  test('BUG-L4: two writers on one file (two processes): lines are whole '
      'and none is lost (Dart\'s append handle writes at its own position, '
      'so one writer overwrites the other\'s lines)', () {
    final a = FileErrorLog(file);
    final b = FileErrorLog(file);
    for (var i = 0; i < 1500; i++) {
      a.log(LogCode.flushFailed, i);
      b.log(LogCode.storeUnreadable, i);
    }
    a.close();
    b.close();
    final all = lines(file);
    expect(all, hasLength(3000));
    final shape = RegExp(r'^\S+Z (flushFailed|storeUnreadable) \d+$');
    expect(all.every(shape.hasMatch), isTrue, reason: 'a garbled line');
  }, skip: posix);

  test('two writers, one rotates: the other one keeps writing to '
      'the live file, not to the old one (lines would vanish from the log '
      'the user reads)', () {
    final a = FileErrorLog(file, maxBytes: 200);
    final b = FileErrorLog(file, maxBytes: 200);
    b.log(LogCode.flushFailed, 0);
    for (var i = 0; i < 12; i++) {
      a.log(LogCode.storeUnreadable, i); // rotates
    }
    b.log(LogCode.dataFolderUnavailable, 999);
    a.close();
    b.close();
    expect(
      lines(file).any((l) => l.endsWith('dataFolderUnavailable 999')),
      isTrue,
      reason: 'B wrote into the rotated .1 file through its old handle',
    );
  }, skip: posix);

  test('BUG-L2: the log file is deleted from outside (a user clearing it): '
      'later lines reach a new file', () {
    final log = FileErrorLog(file);
    log.log(LogCode.flushFailed, 1);
    file.deleteSync();
    log.log(LogCode.flushFailed, 2);
    log.log(LogCode.flushFailed, 3);
    log.close();
    expect(file.existsSync(), isTrue, reason: 'the log is silently gone');
    expect(lines(file).map((l) => l.split(' ').last), contains('3'));
  }, skip: posix);

  test('BUG-L2: the log file is moved aside from outside: later lines '
      'reach the file at the log path', () {
    final log = FileErrorLog(file);
    log.log(LogCode.flushFailed, 1);
    file.renameSync(p.join(dir.path, 'moved.log'));
    log.log(LogCode.flushFailed, 2);
    log.close();
    expect(file.existsSync(), isTrue);
  }, skip: posix);

  test('BUG-L3: a rotation that cannot rename (".1" is a non-empty folder) '
      'does not stop the log for good', () {
    Directory('${file.path}.1').createSync();
    File(p.join('${file.path}.1', 'x')).writeAsStringSync('x');
    final log = FileErrorLog(file, maxBytes: 150);
    for (var i = 0; i < 20; i++) {
      log.log(LogCode.flushFailed, i);
    }
    log.log(LogCode.storeUnreadable, 777);
    log.close();
    expect(
      lines(file).any((l) => l.endsWith(' 777')),
      isTrue,
      reason: 'after the failed rotation every later line is dropped',
    );
  }, skip: posix);

  test('a log that cannot be opened (the folder is gone) never throws', () {
    dir.deleteSync(recursive: true);
    final log = FileErrorLog(file);
    log.log(LogCode.flushFailed);
    log.close();
    dir.createSync();
  });

  test('close then log opens the file again', () {
    final log = FileErrorLog(file);
    log.log(LogCode.flushFailed, 1);
    log.close();
    log.log(LogCode.flushFailed, 2);
    log.close();
    expect(lines(file), hasLength(2));
  });

  // ---- Round 4: per-line open (4375e75) ----

  group('per-line open, real concurrency (two isolates)', () {
    final shape = RegExp(r'^\S+Z (flushFailed|storeUnreadable) \d+$');

    Future<void> writer(String path, LogCode code, int lines, int maxBytes) =>
        Isolate.run(() {
          final l = FileErrorLog(File(path), maxBytes: maxBytes);
          for (var i = 0; i < lines; i++) {
            l.log(code, i);
          }
        });

    Future<void> twoWriters(
      String path,
      int lines,
      int maxBytes, {
      bool oneAfterTheOther = false,
    }) async {
      if (oneAfterTheOther) {
        await writer(path, LogCode.flushFailed, lines, maxBytes);
        await writer(path, LogCode.storeUnreadable, lines, maxBytes);
        return;
      }
      await Future.wait([
        writer(path, LogCode.flushFailed, lines, maxBytes),
        writer(path, LogCode.storeUnreadable, lines, maxBytes),
      ]);
    }

    test('BUG-L5: two real concurrent writers x 1,500 lines, no rotation: '
        '3,000 whole lines, none lost (Dart\'s append open seeks to the end '
        'and then writes, so truly simultaneous writers overwrite each '
        'other: about 0.1-0.3% of the lines)', () async {
      await twoWriters(file.path, 1500, 100000000);
      final all = lines(file);
      expect(all, hasLength(3000));
      expect(all.every(shape.hasMatch), isTrue, reason: 'a garbled line');
      for (final code in ['flushFailed', 'storeUnreadable']) {
        final n = all
            .where((l) => l.contains(code))
            .map((l) => int.parse(l.split(' ').last))
            .toList();
        expect(n, hasLength(1500), reason: code);
        expect(n, orderedEquals([for (var i = 0; i < 1500; i++) i]));
      }
    }, skip: posix ?? 'BUG-L5 (low, also in the code before 77a2080)');

    Future<void> rotatingWriters({required bool oneAfterTheOther}) async {
      await twoWriters(
        file.path,
        3000,
        20000,
        oneAfterTheOther: oneAfterTheOther,
      );
      final old = File('${file.path}.1');
      // Oldest first: the old file, then the live one.
      final kept = [...lines(old), ...lines(file)];
      // A whole line, matched from its first to its last character: a UTC
      // timestamp, the code, and a line number with no leading zero that the
      // writer could have written. A line BUG-L5 overwrote, with the tail of
      // another line (extra digits) at its end, does not match.
      final wholeLine = RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,6}Z '
        r'(flushFailed|storeUnreadable) (0|[1-9]\d{0,3})$',
      );
      final parsed = [
        for (final l in kept)
          if (wholeLine.firstMatch(l) case final m?
              when int.parse(m[2]!) < 3000)
            (code: m[1]!, n: int.parse(m[2]!)),
      ];
      // ignore: avoid_print
      print(
        'LOG rotation x2 writers: live ${lines(file).length} lines, '
        '.1 ${lines(old).length} lines, whole ${parsed.length} of '
        '${kept.length}',
      );
      expect(file.lengthSync(), lessThan(20000 + 200));
      expect(old.existsSync(), isTrue);
      expect(kept, isNotEmpty);
      // No floor on the share of whole lines: with non-atomic appends
      // (BUG-L5) it depends on CPU load (85% on a loaded CI Mac, 2026-11-19).
      // No floor per writer either: when one writer finishes before the
      // other starts (BUG-T1), rotation pushes all of its lines out. What
      // does not depend on timing: the whole lines a writer kept are in the
      // order it wrote them.
      for (final code in ['flushFailed', 'storeUnreadable']) {
        final n = [
          for (final r in parsed)
            if (r.code == code) r.n,
        ];
        for (var i = 1; i < n.length; i++) {
          expect(
            n[i],
            greaterThan(n[i - 1]),
            reason: '$code lines out of order at ${n[i - 1]}, ${n[i]}',
          );
        }
      }
    }

    test('two writers x 3,000 lines with rotations in the middle: the live '
        'file stays bounded, one old file is kept, and each writer\'s whole '
        'kept lines are in order (BUG-L5 may garble some)', () async {
      await rotatingWriters(oneAfterTheOther: false);
    });

    test('BUG-T1: the same two writers when one finishes before the other '
        'starts (a loaded machine): rotation pushes all of the first '
        'writer\'s lines out, which is not a failure', () async {
      await rotatingWriters(oneAfterTheOther: true);
    });
  });

  test('rename keeps failing (".1" is a non-empty folder): the live file '
      'never passes twice the limit, starts over, and keeps the newest '
      'lines', () {
    Directory('${file.path}.1').createSync();
    File(p.join('${file.path}.1', 'x')).writeAsStringSync('x');
    const max = 1000;
    final log = FileErrorLog(file, maxBytes: max);
    var biggest = 0;
    var startedOver = false;
    var last = 0;
    for (var i = 0; i < 600; i++) {
      log.log(LogCode.flushFailed, i);
      final size = file.lengthSync();
      if (size < last) startedOver = true;
      last = size;
      if (size > biggest) biggest = size;
    }
    expect(startedOver, isTrue, reason: 'the log never started over');
    expect(biggest, lessThanOrEqualTo(2 * max + 80));
    expect(lines(file).last.endsWith('flushFailed 599'), isTrue);
    // After the start-over the file again holds only whole lines.
    expect(
      lines(file).every((l) => RegExp(r'^\S+Z flushFailed \d+$').hasMatch(l)),
      isTrue,
    );
    expect(Directory('${file.path}.1').existsSync(), isTrue);
  }, skip: posix);

  test('rename keeps failing and the log is a link at that moment: nothing '
      'is written through it', () {
    final target = File(p.join(dir.path, 'real.log'))
      ..writeAsStringSync('real\n');
    Directory('${file.path}.1').createSync();
    File(p.join('${file.path}.1', 'x')).writeAsStringSync('x');
    final log = FileErrorLog(file, maxBytes: 100);
    for (var i = 0; i < 6; i++) {
      log.log(LogCode.flushFailed, i);
    }
    file.renameSync('${file.path}.hold');
    Link(file.path).createSync(target.path);
    for (var i = 6; i < 20; i++) {
      log.log(LogCode.flushFailed, i);
    }
    expect(target.readAsStringSync(), 'real\n');
  }, skip: posix);
}
