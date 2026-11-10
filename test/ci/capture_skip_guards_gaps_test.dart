// M1.6 tester: guards that close gaps in test/ci/capture_skip_guards_test.dart
// (ADR 0005: the source app never leaves native memory, is never logged and
// never stored). Source scans, like the existing guards.
//
// Gaps closed here:
//  - the existing guard only matches the literal form `emit([...])`; a new
//    `emit(someMap)` with a variable would carry fields it never sees;
//  - the logging bans miss fputs, FileHandle, dump, Swift.print, wprintf,
//    std::clog, fwrite, MessageBox and trace APIs;
//  - ClipboardBridge.swift (which receives the list) is not scanned at all;
//  - nothing ties the Swift DiagLog code list to Dart's capture codes;
//  - nothing checks that Dart's pause and history code logs only the
//    allowed details;
//  - nothing checks the source closure can't be stored (`@escaping`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';

String _read(String path) => File(path).readAsStringSync();

String _code(String path) => _read(
  path,
).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

const _swiftFiles = [
  'macos/Runner/CaptureSkipCore.swift',
  'macos/Runner/ClipboardWatcher.swift',
  'macos/Runner/ClipboardBridge.swift',
];
const _cppFiles = [
  'windows/runner/capture_gate.h',
  'windows/runner/app_id.h',
  'windows/runner/clipboard_bridge.cpp',
];

void main() {
  roundThreeGuards();
  group('every event is a literal map or a known builder', () {
    test('Mac: every emit( call site is emit([...]) with a literal map', () {
      final src = _code('macos/Runner/ClipboardWatcher.swift');
      final calls = RegExp(r'(?<![\w.])emit\(').allMatches(src).length;
      final literal = RegExp(r'(?<![\w.])emit\(\[').allMatches(src).length;
      expect(calls, literal, reason: 'a non-literal emit hides its fields');
      expect(calls, 5);
    });

    test('Mac: the ClipboardBridge only forwards events, never builds one', () {
      final src = _code('macos/Runner/ClipboardBridge.swift');
      expect(src, isNot(contains('"ignoredApp"')));
      expect(src, isNot(contains('"type"')));
    });

    test('Windows: every Emit( call site is Event("..."), the error lambda or '
        'a locally built event', () {
      final src = _code('windows/runner/clipboard_bridge.cpp');
      final starts = RegExp(r'(?<![\w:])Emit\(').allMatches(src);
      final forms = [
        for (final m in starts)
          src
              .substring(m.end, (m.end + 24).clamp(0, src.length))
              .replaceAll(RegExp(r'\s+'), ' '),
      ];
      expect(forms, isNotEmpty);
      for (final f in forms) {
        expect(
          f.startsWith('Event("') ||
              f.startsWith('[] {') ||
              f.startsWith('std::move(e)') ||
              f.startsWith('EncodableMap event'),
          isTrue,
          reason: 'unexpected Emit($f',
        );
      }
    });
  });

  group('no other way to write out the source app', () {
    test('Swift: no stderr, file, dump or os logging in the capture files', () {
      for (final f in _swiftFiles) {
        final src = _code(f);
        for (final banned in [
          RegExp(r'\bfputs\('),
          RegExp(r'\bfputc\('),
          RegExp(r'\bdump\('),
          RegExp(r'Swift\.print'),
          RegExp(r'FileHandle\.standard'),
          RegExp(r'\bFileHandle\b'),
          RegExp(r'\bOSLog\b|os\.log|import os\b|\bOSLogger\b'),
          RegExp(r'\bNSLog\('),
          RegExp(r'\bprint\('),
          RegExp(r'\bDiagLog\b'),
          RegExp(r'\.write\(to:'),
          RegExp(r'UserDefaults'),
          RegExp(r'\bURLSession\b'),
        ]) {
          expect(banned.hasMatch(src), isFalse, reason: '$f: $banned');
        }
      }
    });

    test('C++: no stdio, stream, trace, dialog or network call in the '
        'capture files', () {
      for (final f in _cppFiles) {
        final src = _code(f);
        for (final banned in [
          RegExp(r'\b(f|w|v|_c)?printf\('),
          RegExp(r'\b(fwrite|fputs|fputws|puts|perror)\('),
          RegExp(r'std::(cout|cerr|clog|wcout|wcerr|ofstream|fstream)'),
          RegExp(r'OutputDebugString'),
          RegExp(r'MessageBox'),
          RegExp(r'TraceLogging|EventWrite|ETW'),
          RegExp(r'\bWinHttp|\bInternet(Open|Connect)|\bsend\(|\bWSA'),
          RegExp(r'RegSetValue|WritePrivateProfile'),
        ]) {
          expect(banned.hasMatch(src), isFalse, reason: '$f: $banned');
        }
      }
    });

    test('the source closure is non-escaping, so it cannot be stored', () {
      final swift = _code('macos/Runner/CaptureSkipCore.swift');
      final escaping = RegExp(r'@escaping[^,)]*').allMatches(swift).toList();
      // Only the clock in init(now:).
      expect(escaping, hasLength(1));
      expect(swift, contains('func check(source: () -> String?)'));
      final watcher = _code('macos/Runner/ClipboardWatcher.swift');
      // The poller stores frontApp (a function that returns it), never a
      // value read from it.
      expect(RegExp(r'frontApp\(\)').allMatches(watcher), isEmpty);
    });

    test('the Mac watcher keeps no variable that could hold the app id', () {
      final src = _code('macos/Runner/ClipboardWatcher.swift');
      final vars = {
        for (final m in RegExp(r'\n\s*(?:private )?var (\w+)').allMatches(src))
          m.group(1)!,
      };
      expect(
        vars.where(
          (v) => RegExp(
            r'source|app|bundle|owner',
            caseSensitive: false,
          ).hasMatch(v),
        ),
        isEmpty,
        reason: '$vars',
      );
    });
  });

  group('Dart never prints or logs an app id', () {
    test('no print or debugPrint in lib mentions an app, source or list', () {
      final hits = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final lines = e.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (!RegExp(r'\b(debugPrint|print)\(').hasMatch(l)) continue;
          if (RegExp(
            r'appId|ignored|bundle|\bexe\b|source|displayName',
            caseSensitive: false,
          ).hasMatch(l)) {
            hits.add('${e.path}:${i + 1}');
          }
        }
      }
      expect(hits, isEmpty);
    });

    test('no log call in lib passes an app id, name or text as its detail', () {
      final hits = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        for (final m in RegExp(
          r'\blog\(\s*LogCode\.\w+\s*,\s*([^)]*)\)',
        ).allMatches(src)) {
          if (RegExp(
            r'appId|displayName|text|content|name|preview',
            caseSensitive: false,
          ).hasMatch(m.group(1)!)) {
            hits.add('${e.path}: ${m.group(0)}');
          }
        }
      }
      expect(hits, isEmpty);
    });

    test('pause_service logs only capturePaused (minutes or -1) and '
        'captureResumed (0 or 1)', () {
      final src = _code('lib/history/pause_service.dart');
      final calls = [
        for (final m in RegExp(r'_log\.log\(([^;]*)\);').allMatches(src))
          m.group(1)!.replaceAll(RegExp(r'\s+'), ' '),
      ];
      expect(calls, [
        'LogCode.captureResumed, 1',
        'LogCode.capturePaused, minutes ?? -1',
        'LogCode.captureResumed, 0',
      ]);
    });

    test('history_service logs the capture codes with no detail', () {
      final src = _code('lib/history/history_service.dart');
      for (final c in ['captureSkippedIgnoredApp', 'captureSourceUnknown']) {
        final calls = RegExp(
          '_log\\.log\\(\\s*LogCode\\.$c([^)]*)\\)',
        ).allMatches(src).toList();
        expect(calls, isNotEmpty, reason: c);
        for (final m in calls) {
          expect(m.group(1)!.trim(), isEmpty, reason: c);
        }
      }
    });
  });

  group('the native log list follows Dart', () {
    test('DiagLog.swift lists exactly the capture codes Dart has', () {
      final swift = _read('macos/Runner/DiagLog.swift');
      final listed = {
        for (final m in RegExp(r'"(capture\w+)"').allMatches(swift))
          m.group(1)!,
      };
      final dart = {
        for (final c in LogCode.values)
          if (c.name.startsWith('capture')) c.name,
      };
      expect(listed, dart);
    });
  });

  group('the clipboard events and the setting hold no app', () {
    test('the stored setting is a number only', () {
      final src = _code('lib/history/pause_service.dart');
      expect(
        RegExp(r"_write\(historyPausedSetting, '\$_until'\)").hasMatch(src),
        isTrue,
      );
      expect(RegExp(r'_write\(').allMatches(src), hasLength(1));
    });
  });
}

// Round 3 (R7): app_id.h now holds the exe-name lookup, so it is under the
// same rules as the gate: no state, nothing written out.
void roundThreeGuards() {
  group('app_id.h (R7)', () {
    test('keeps no state: no static or global variable', () {
      final src = _code('windows/runner/app_id.h');
      expect(RegExp(r'\bstatic\s+(?!inline|constexpr)').hasMatch(src), isFalse);
      expect(RegExp(r'\bthread_local\b').hasMatch(src), isFalse);
      expect(
        RegExp(
          r'^\s*(?:std::\w+(?:<[^>]*>)?|int|bool)\s+\w+_?\s*(?:=|;)',
          multiLine: true,
        ).hasMatch(
          src
              .split('\n')
              .where((l) => !l.startsWith('  ') && !l.startsWith('\t'))
              .join('\n'),
        ),
        isFalse,
      );
    });

    test('is included by the two bridges and nothing else', () {
      final users = [
        for (final f in Directory('windows/runner').listSync())
          if (f is File &&
              (f.path.endsWith('.cpp') || f.path.endsWith('.h')) &&
              _read(f.path).contains('#include "app_id.h"'))
            f.path.split('/').last,
      ]..sort();
      expect(users, [
        'app_id_test.cpp',
        'capture_gate_edge_test.cpp',
        'clipboard_bridge.cpp',
        'typed_shortcut_bridge.cpp',
      ]);
    });
  });
}
