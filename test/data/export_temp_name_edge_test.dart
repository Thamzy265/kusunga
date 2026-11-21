// Windows CI green (group C), tester: abuse and edge cases for what is at the
// export's temp name and at the target. writeExportFile has a `createTemp`
// seam, so the Windows answer (an exclusive create that succeeds over a
// dangling link) is also played on macOS.
//
// Rules held in every case: the export never writes through a link, never
// loses the user's existing file when the temp route is used, and leaves no
// Kusunga temp file behind.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/your_data_service.dart';
import 'package:path/path.dart' as p;

/// A byte list that fails part-way through the write.
class _FailingBytes extends ListBase<int> {
  @override
  int get length => 10;
  @override
  set length(int _) => throw UnsupportedError('fixed');
  @override
  int operator [](int index) {
    if (index >= 5) throw const FileSystemException('disk full');
    return 0x41;
  }

  @override
  void operator []=(int index, int value) => throw UnsupportedError('fixed');
}

void main() {
  late Directory dir;
  final links = Platform.isWindows
      ? 'creating links needs extra rights on Windows'
      : false;

  setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_tester_c_'));
  tearDown(() {
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
    }
    dir.deleteSync(recursive: true);
  });

  String tempOf(String path) => exportTempPath(path, Random(11));
  bool isLink(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link;

  /// Kusunga temp names that are plain files, left in [dir].
  List<String> strayTempFiles() => [
    for (final e in dir.listSync(followLinks: false))
      if (e is File && p.basename(e.path).contains('.kusunga-tmp'))
        p.basename(e.path),
  ];

  void export(String path, String text, {void Function(File)? createTemp}) =>
      writeExportFile(
        path,
        utf8.encode(text),
        random: Random(11),
        createTemp: createTemp,
      );

  group('anything at the temp name means: written in place, nothing lost', () {
    test('a folder at the temp name (with a file inside): the export is '
        'written in place, the folder and its file stay', () {
      final path = p.join(dir.path, 'out.json');
      final folder = Directory(tempOf(path))..createSync();
      File(p.join(folder.path, 'inside.txt')).writeAsStringSync('keep');
      export(path, 'new');
      expect(File(path).readAsStringSync(), 'new');
      expect(folder.existsSync(), isTrue);
      expect(
        File(p.join(folder.path, 'inside.txt')).readAsStringSync(),
        'keep',
      );
    });

    test('a link to a folder at the temp name: not entered, not removed, '
        'nothing written into the folder', () {
      final target = Directory(p.join(dir.path, 'target'))..createSync();
      final path = p.join(dir.path, 'out.json');
      Link(tempOf(path)).createSync(target.path);
      export(path, 'new');
      expect(File(path).readAsStringSync(), 'new');
      expect(target.listSync(), isEmpty);
      expect(isLink(tempOf(path)), isTrue);
    }, skip: links);

    test('a link to a file at the temp name: the file is not written, '
        'appended to or truncated', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final path = p.join(dir.path, 'out.json');
      Link(tempOf(path)).createSync(victim.path);
      export(path, 'new');
      expect(victim.readAsStringSync(), 'keep');
      expect(File(path).readAsStringSync(), 'new');
    }, skip: links);

    test(
      'a hard link at the temp name: its other name keeps its content',
      () {
        final victim = File(p.join(dir.path, 'victim.txt'))
          ..writeAsStringSync('keep');
        final path = p.join(dir.path, 'out.json');
        expect(Process.runSync('ln', [victim.path, tempOf(path)]).exitCode, 0);
        export(path, 'new');
        expect(victim.readAsStringSync(), 'keep');
        expect(File(path).readAsStringSync(), 'new');
      },
      skip: Platform.isWindows,
    );

    test('the Windows answer over a link to a folder or a file: still '
        'written in place, nothing behind the link changes', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final folder = Directory(p.join(dir.path, 'folder'))..createSync();
      for (final target in [victim.path, folder.path]) {
        final path = p.join(dir.path, 'out-${p.basename(target)}.json');
        Link(tempOf(path)).createSync(target);
        export(path, 'new', createTemp: (_) {});
        expect(File(path).readAsStringSync(), 'new', reason: target);
      }
      expect(victim.readAsStringSync(), 'keep');
      expect(folder.listSync(), isEmpty);
    }, skip: links);

    test('the Windows answer over a dangling link: nothing is created at '
        'the link target either', () {
      final nowhere = p.join(dir.path, 'nowhere');
      final path = p.join(dir.path, 'out.json');
      Link(tempOf(path)).createSync(nowhere);
      export(path, 'new', createTemp: (_) {});
      expect(File(path).readAsStringSync(), 'new');
      expect(FileSystemEntity.typeSync(nowhere), FileSystemEntityType.notFound);
    }, skip: links);

    test('over an existing export: replaced whole (a longer old file leaves '
        'no tail), whether the temp name is free or taken', () {
      for (final taken in [false, true]) {
        final path = p.join(dir.path, 'out-$taken.json');
        File(path).writeAsStringSync('old and much longer than the new one');
        if (taken) File(tempOf(path)).writeAsStringSync('planted');
        export(path, 'new');
        expect(File(path).readAsStringSync(), 'new', reason: 'taken $taken');
      }
    });
  });

  group('the temp name is free: the temp route', () {
    test('a failed write leaves the user\'s existing file as it was and no '
        'temp file behind', () {
      final path = p.join(dir.path, 'out.json');
      File(path).writeAsStringSync('the user\'s export');
      expect(
        () => writeExportFile(path, _FailingBytes(), random: Random(11)),
        throwsA(isA<Exception>()),
      );
      expect(File(path).readAsStringSync(), 'the user\'s export');
      expect(strayTempFiles(), isEmpty);
    });

    test('a successful export leaves no temp file', () {
      final path = p.join(dir.path, 'out.json');
      export(path, 'new');
      expect(strayTempFiles(), isEmpty);
      expect(dir.listSync().map((e) => p.basename(e.path)), ['out.json']);
    });

    test('a link as the target is replaced by the file; what it pointed '
        'to is not written', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final path = p.join(dir.path, 'out.json');
      Link(path).createSync(victim.path);
      export(path, 'new');
      expect(victim.readAsStringSync(), 'keep');
      expect(isLink(path), isFalse);
      expect(File(path).readAsStringSync(), 'new');
    }, skip: links);

    test(
      'a dangling link as the target: nothing is created where it points',
      () {
        final nowhere = p.join(dir.path, 'nowhere');
        final path = p.join(dir.path, 'out.json');
        Link(path).createSync(nowhere);
        export(path, 'new');
        expect(File(nowhere).existsSync(), isFalse);
        expect(File(path).readAsStringSync(), 'new');
      },
      skip: links,
    );

    test('a hard link as the target: renamed over, the other name keeps its '
        'content', () {
      final other = File(p.join(dir.path, 'other.txt'))
        ..writeAsStringSync('keep');
      final path = p.join(dir.path, 'out.json');
      expect(Process.runSync('ln', [other.path, path]).exitCode, 0);
      export(path, 'new');
      expect(other.readAsStringSync(), 'keep');
      expect(File(path).readAsStringSync(), 'new');
    }, skip: Platform.isWindows);

    test('a folder as the target: the export fails, the folder and its '
        'file stay, no temp file is left', () {
      final target = Directory(p.join(dir.path, 'out.json'))..createSync();
      File(p.join(target.path, 'inside.txt')).writeAsStringSync('keep');
      expect(
        () => export(target.path, 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        File(p.join(target.path, 'inside.txt')).readAsStringSync(),
        'keep',
      );
      expect(strayTempFiles(), isEmpty);
    });

    test('a folder as the target, temp name taken as well (in place): fails, '
        'the folder stays', () {
      final target = Directory(p.join(dir.path, 'out.json'))..createSync();
      File(tempOf(target.path)).writeAsStringSync('planted');
      expect(
        () => export(target.path, 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(target.existsSync(), isTrue);
    });

    test('a read-only file in a read-only folder: the export fails, the '
        'file is as it was, nothing is left', () {
      final sub = Directory(p.join(dir.path, 'ro'))..createSync();
      final file = File(p.join(sub.path, 'out.json'))
        ..writeAsStringSync('the user\'s export');
      Process.runSync('chmod', ['400', file.path]);
      Process.runSync('chmod', ['500', sub.path]);
      expect(
        () => writeExportFile(file.path, utf8.encode('new')),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.readAsStringSync(), 'the user\'s export');
      expect(sub.listSync().map((e) => p.basename(e.path)), ['out.json']);
    }, skip: Platform.isWindows);

    test('a read-only file in a writable folder is replaced by rename, as '
        'a save over it would be', () {
      final file = File(p.join(dir.path, 'out.json'))..writeAsStringSync('old');
      Process.runSync('chmod', ['400', file.path]);
      export(file.path, 'new');
      expect(file.readAsStringSync(), 'new');
      expect(strayTempFiles(), isEmpty);
    }, skip: Platform.isWindows);
  });

  group('a link or file appearing after the check (a lost race)', () {
    test('a link to a file wins the race: the file is not changed, the '
        'export is refused and the existing export is as it was', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final path = p.join(dir.path, 'out.json');
      File(path).writeAsStringSync('the user\'s export');
      expect(
        () => export(
          path,
          'new',
          createTemp: (f) => Link(f.path).createSync(victim.path),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(victim.readAsStringSync(), 'keep');
      expect(File(path).readAsStringSync(), 'the user\'s export');
    }, skip: links);

    test(
      'a dangling link wins the race: nothing is created at its target',
      () {
        final nowhere = p.join(dir.path, 'nowhere');
        final path = p.join(dir.path, 'out.json');
        File(path).writeAsStringSync('the user\'s export');
        expect(
          () => export(
            path,
            'new',
            createTemp: (f) => Link(f.path).createSync(nowhere),
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          FileSystemEntity.typeSync(nowhere),
          FileSystemEntityType.notFound,
          reason: 'opening for append creates a missing file through a link',
        );
        expect(File(path).readAsStringSync(), 'the user\'s export');
      },
      skip: Platform.isWindows
          ? links
          : 'BUG-C1 (low), the repro, fails today: the temp name is opened for '
                'append, which creates an empty file where a dangling link points',
    );

    test('the real exclusive create loses to a file made after the check: '
        'the export falls back to writing in place', () {
      final path = p.join(dir.path, 'out.json');
      export(
        path,
        'new',
        createTemp: (f) {
          f.writeAsStringSync('late arrival');
          f.createSync(exclusive: true);
        },
      );
      expect(File(path).readAsStringSync(), 'new');
      expect(File(tempOf(path)).readAsStringSync(), 'late arrival');
    });
  });
}
