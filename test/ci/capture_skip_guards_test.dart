// Guards for M1.6 sensitive-content protection (ADR 0005, design note
// "Observability" and "Privacy"):
//  - the clipboard event gains NO field: the source app never crosses the
//    channel, on either system;
//  - the clipboard channel API is exactly the listed calls;
//  - nothing in the capture skip code can log or print the source app;
//  - the log codes are the design's list.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';

String _read(String path) => File(path).readAsStringSync();

/// Source without line comments, so a comment can't satisfy or break a check.
String _code(String path) => _read(
  path,
).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

const _dartSource = 'lib/clipboard/channel_clipboard_source.dart';
const _swiftWatcher = 'macos/Runner/ClipboardWatcher.swift';
const _swiftGate = 'macos/Runner/CaptureSkipCore.swift';
const _swiftBridge = 'macos/Runner/ClipboardBridge.swift';
const _cppBridge = 'windows/runner/clipboard_bridge.cpp';
const _cppGate = 'windows/runner/capture_gate.h';

/// Every key a clipboard event may carry, as before M1.6.
const _eventKeys = {'type', 'text', 'own', 'code'};

/// Every event type. M1.6 adds ignoredApp and sourceUnknown: types, not
/// fields, and they carry nothing else.
const _eventTypes = {
  'text',
  'concealed',
  'tooLarge',
  'error',
  'ignoredApp',
  'sourceUnknown',
};

const _methods = {
  'accessBehavior',
  'writeOwn',
  'setCapturePause',
  'setCaptureIgnored',
};

const _designCodes = {
  'captureSkippedIgnoredApp',
  'capturePaused',
  'captureResumed',
  'captureSourceUnknown',
  // Fix round O2: the list could not reach the watcher after one retry.
  'captureIgnoredSendFailed',
};

void main() {
  group('the clipboard event gains no field (ADR 0005)', () {
    test('Mac: every emitted map uses only type, text and own', () {
      final src = _code(_swiftWatcher) + _code(_swiftGate);
      final maps = RegExp(r'emit\(\[([^\]]*)\]\)').allMatches(src).toList();
      expect(maps, isNotEmpty);
      final keys = <String>{};
      final types = <String>{};
      for (final m in maps) {
        for (final k in RegExp(r'"(\w+)":').allMatches(m.group(1)!)) {
          keys.add(k.group(1)!);
        }
        final t = RegExp(r'"type":\s*"(\w+)"').firstMatch(m.group(1)!);
        if (t != null) types.add(t.group(1)!);
      }
      expect(keys, {'type', 'text', 'own'});
      expect(types, {'text', 'concealed', 'tooLarge', 'ignoredApp'});
    });

    test('the ignoredApp event is the type alone', () {
      final src = _code(_swiftWatcher);
      expect(src, contains('emit(["type": "ignoredApp"])'));
      expect(_code(_cppBridge), contains('Emit(Event("ignoredApp"));'));
      expect(_code(_cppBridge), contains('Emit(Event("sourceUnknown"));'));
    });

    test('Windows: event keys are only type, text, own and code', () {
      final src = _code(_cppBridge);
      final keys = {
        for (final m in RegExp(
          r'e\[EncodableValue\("(\w+)"\)\]',
        ).allMatches(src))
          m.group(1)!,
        'type', // set inside Event()
      };
      expect(_eventKeys.containsAll(keys), isTrue, reason: '$keys');
      final types = {
        for (final m in RegExp(r'Event\("(\w+)"\)').allMatches(src))
          m.group(1)!,
      };
      expect(types, _eventTypes);
    });

    test('Dart reads only the known keys and types', () {
      final src = _code(_dartSource);
      final start = src.indexOf('static ClipboardEvent? _decode');
      final body = src.substring(start, src.indexOf('\n  }\n', start));
      final keys = {
        for (final m in RegExp(r"raw\['(\w+)'\]").allMatches(body)) m.group(1)!,
      };
      expect(_eventKeys.containsAll(keys), isTrue, reason: '$keys');
      final types = {
        for (final m in RegExp(r"case '(\w+)':").allMatches(body)) m.group(1)!,
      };
      expect(types, _eventTypes);
    });

    test('no event key or type names an app, a source, a bundle or an exe', () {
      for (final k in {..._eventKeys, ..._eventTypes}) {
        expect(
          RegExp(
                r'source|bundle|exe|owner|front|appid|name',
                caseSensitive: false,
              ).hasMatch(k) &&
              k != 'sourceUnknown',
          isFalse,
          reason: k,
        );
      }
    });
  });

  group('the clipboard channel API', () {
    test('Dart, Swift and C++ use exactly the same methods', () {
      final dart = _code(_dartSource);
      final dartCalls = {
        for (final m in RegExp(
          r"(?:invokeMethod<[^>]+>|_call)\(\s*'(\w+)'",
        ).allMatches(dart))
          m.group(1)!,
      };
      expect(dartCalls, _methods);
      // The clipboard channel's handler only: the lifecycle channel
      // (quit) comes after it.
      String clipboardPart(String src, String lifecycle) =>
          src.substring(0, src.indexOf(lifecycle));
      final swift = {
        for (final m in RegExp(r'call\.method == "(\w+)"').allMatches(
          clipboardPart(
            _code(_swiftBridge),
            'name: "com.wnasoni.kusunga/lifecycle"',
          ),
        ))
          m.group(1)!,
      };
      expect(swift, _methods);
      final cpp = {
        for (final m in RegExp(r'call\.method_name\(\) == "(\w+)"').allMatches(
          clipboardPart(_code(_cppBridge), 'lifecycle_ = std::make_unique'),
        ))
          m.group(1)!,
      };
      expect(cpp, _methods);
    });

    test('the capture calls carry only appIds and until', () {
      final dart = _code(_dartSource);
      expect(dart, contains("_call('setCapturePause', {'until': until})"));
      expect(dart, contains("_call('setCaptureIgnored', {'appIds': appIds})"));
    });
  });

  group('nothing can log or print the source app', () {
    test(
      'Swift capture code has no print, NSLog, os_log, Logger or DiagLog',
      () {
        for (final f in [_swiftGate, _swiftWatcher]) {
          final src = _code(f);
          expect(
            src,
            isNot(matches(RegExp(r'\b(print|NSLog|os_log|debugPrint)\('))),
            reason: f,
          );
          expect(src, isNot(contains('Logger(')), reason: f);
          expect(src, isNot(contains('DiagLog')), reason: f);
        }
      },
    );

    test('C++ capture code has no printf, OutputDebugString, cout or cerr', () {
      for (final f in [_cppGate, _cppBridge]) {
        expect(
          _code(f),
          isNot(
            matches(
              RegExp(
                r'\b(f?printf|puts)\(|OutputDebugString|std::cout|std::cerr',
              ),
            ),
          ),
          reason: f,
        );
      }
    });

    test('the Windows exe name is looked up only inside the capture check', () {
      final src = _code(_cppBridge);
      final uses = RegExp(r'ExeNameOfWindow\(').allMatches(src).length;
      // The definition and the two lookups (owner, foreground) inside
      // DecideCapture's source lambda.
      expect(uses, 3);
      final start = src.indexOf('kusunga::DecideCapture(');
      final call = src.substring(start, src.indexOf('});', start));
      expect(
        RegExp(r'ExeNameOfWindow\(').allMatches(call).length,
        2,
        reason: 'both lookups happen in the decision',
      );
    });

    test('the gates hold no field for the source app', () {
      final swift = _code(_swiftGate);
      final vars = [
        for (final m in RegExp(
          r'(?:private\(set\) )?(?:private )?var (\w+)',
        ).allMatches(swift))
          m.group(1)!,
      ];
      expect(vars.toSet(), {'pausedUntil', 'ignored'});
      final cpp = _code(_cppGate);
      final fields = {
        for (final m in RegExp(r'\b(\w+_);').allMatches(cpp)) m.group(1)!,
      };
      expect(fields, {'paused_until_', 'ignored_'});
    });
  });

  group('log codes', () {
    test('Dart has exactly the design note\'s capture codes', () {
      final names = {for (final c in LogCode.values) c.name};
      expect(names.where((n) => n.startsWith('capture')).toSet(), _designCodes);
    });

    test('the design note lists them', () {
      final note = _read('docs/design/sensitive-content.md');
      for (final c in _designCodes) {
        expect(note, contains('`$c`'), reason: c);
      }
    });
  });
}
