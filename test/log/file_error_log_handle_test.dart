import 'dart:io';

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
}
