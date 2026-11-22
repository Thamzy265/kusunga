// Guards for M1.5 typed shortcuts (ADR 0004, design note "Observability" and
// "For the reviewer"; ADR 0003):
//  - the channel API is exactly the listed calls, and none carries a typed
//    key: `matched` is a snippet id and a delete count only;
//  - no native log, print or channel call can reach the typed-key buffer;
//  - the log codes are the design's list, and every native skip code is one;
//  - the App Sandbox stays on, and nothing asks for the Accessibility API.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/source_text.dart';
import '../support/swift_conditional.dart';

String _read(String path) => readSource(path);

/// Source without line comments, so a comment can't satisfy or break a check.
String _code(String path) => _read(path)
    .split('\n')
    .where(
      (l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'),
    )
    .join('\n');

const _dartPort = 'lib/shortcuts/channel_typed_shortcuts_port.dart';
const _swiftBridge = 'macos/Runner/TypedShortcutBridge.swift';
const _swiftCore = 'macos/Runner/TypedShortcutCore.swift';
const _cppBridge = 'windows/runner/typed_shortcut_bridge.cpp';
const _cppPolicy = 'windows/runner/typed_shortcut_policy.h';

const _dartToNative = {
  'setTable',
  'setIgnored',
  'setEnabled',
  'status',
  'replace',
  'runningApps',
  'requestListenAccess',
  'openInputMonitoringSettings',
};
const _nativeToDart = {'matched', 'statusChanged'};

/// Every key any typed-shortcut channel message may carry. `text` is only
/// the snippet Kusunga pastes (replace); `shortcut` only the table from
/// Dart; `name` and `icon` only runningApps.
const _allowedKeys = {
  'entries',
  'id',
  'shortcut',
  'appIds',
  'on',
  'deleteCount',
  'text',
  'snippetId',
  // C2: an opaque counter naming the match `replace` answers. Never typed
  // text: it is an integer from a counter on both systems (checked below).
  'matchId',
  'status',
  'appId',
  'name',
  'icon',
};

const _designCodes = {
  'shortcutFired',
  'shortcutCancelled',
  'shortcutSkippedIgnoredApp',
  'shortcutSkippedPassword',
  'shortcutSkippedUnknownField',
  'shortcutSkippedInjected',
  'shortcutSkippedAdmin',
  'shortcutTapReenabled',
  'shortcutTapFailed',
  'shortcutHookFailed',
  'shortcutPermissionMissing',
  'shortcutTableSize',
  // Debug builds only: QA's switch to accept software-sent keys is on (PM
  // decision 2026-11-09).
  'shortcutSyntheticKeysAllowed',
};

void main() {
  group('the channel API (ADR 0004)', () {
    test('Dart calls exactly the listed methods and handles exactly two', () {
      final src = _code(_dartPort);
      final calls = {
        for (final m in RegExp(r"_invoke<[^>]+>\(\s*'(\w+)'").allMatches(src))
          m.group(1)!,
      };
      expect(calls, _dartToNative);
      final handled = {
        for (final m in RegExp(r"case '(\w+)':").allMatches(src)) m.group(1)!,
      };
      expect(handled, _nativeToDart);
    });

    test('Swift and C++ answer the same methods and send only the two '
        'events', () {
      final swift = _code(_swiftBridge);
      final cpp = _code(_cppBridge);
      final swiftCases = {
        for (final m in RegExp(r'case "(\w+)":').allMatches(swift)) m.group(1)!,
      };
      expect(swiftCases, _dartToNative);
      final cppCases = {
        for (final m in RegExp(r'method == "(\w+)"').allMatches(cpp))
          m.group(1)!,
      };
      expect(cppCases, _dartToNative);
      final swiftSent = {
        for (final m in RegExp(r'invokeMethod\(\s*"(\w+)"').allMatches(swift))
          m.group(1)!,
      };
      final cppSent = {
        for (final m in RegExp(r'InvokeMethod\(\s*"(\w+)"').allMatches(cpp))
          m.group(1)!,
      };
      expect(swiftSent, _nativeToDart);
      expect(cppSent, _nativeToDart);
    });

    test('matched carries only snippetId, deleteCount and matchId, on both '
        'systems', () {
      final swift = _code(_swiftBridge);
      final m = RegExp(
        r'"matched",\s*arguments:\s*\[([^\]]*)\]',
      ).firstMatch(swift)!;
      expect(
        {
          for (final k in RegExp(r'"(\w+)":').allMatches(m.group(1)!))
            k.group(1),
        },
        {'snippetId', 'deleteCount', 'matchId'},
      );
      // The match id is the counter's answer, nothing typed.
      final idName = RegExp(
        r'"matchId":\s*(\w+)',
      ).firstMatch(m.group(1)!)!.group(1)!;
      expect(swift, contains('let $idName = pending.begin('));
      final cpp = _code(_cppBridge);
      final start = cpp.indexOf('void TypedShortcutBridge::OnMatched');
      final body = cpp.substring(start, cpp.indexOf('\n}\n', start));
      expect(
        {
          for (final k in RegExp(r'EncodableValue\("(\w+)"\)').allMatches(body))
            k.group(1),
        },
        {'snippetId', 'deleteCount', 'matchId'},
      );
      // An integer token from the pending match's counter.
      expect(
        body,
        contains('void TypedShortcutBridge::OnMatched(int snippet_id'),
      );
      expect(body, contains('EncodableValue(static_cast<int64_t>(match_id))'));
      expect(body, matches(RegExp(r'uint32_t match_id\)')));
      // And the values are the outcome's numbers, never the buffer.
      expect(body, isNot(contains('matcher_')));
      expect(body, isNot(contains('Contents')));
    });

    test('Dart reads matchId only as a positive int and sends back exactly '
        'matchId, deleteCount and text', () {
      final src = _code(_dartPort);
      expect(src, contains("final matchId = args['matchId'];"));
      expect(src, contains('matchId is int'));
      final call = RegExp(
        r"_invoke<Object\?>\('replace', \{([^}]*)\}",
      ).firstMatch(src)!;
      expect(
        {
          for (final k in RegExp(r"'(\w+)':").allMatches(call.group(1)!))
            k.group(1),
        },
        {'matchId', 'deleteCount', 'text'},
      );
    });

    test('no message key names typed text', () {
      final keys = <String>{};
      for (final f in [_dartPort, _swiftBridge]) {
        for (final m in RegExp(
          r'''['"](\w+)['"]\s*[:\]]''',
        ).allMatches(_code(f))) {
          keys.add(m.group(1)!);
        }
      }
      for (final m in RegExp(
        r'(?:EncodableValue|Find\([^,]+,)\s*\(?\s*"(\w+)"',
      ).allMatches(_code(_cppBridge))) {
        keys.add(m.group(1)!);
      }
      final messageKeys = keys.where(
        (k) => !_dartToNative.contains(k) && !_nativeToDart.contains(k),
      );
      // Status names and result names are values, not keys: drop them.
      const values = {
        'on',
        'off',
        'needsPermission',
        'paused',
        'stopped',
        'failed',
        'replaced',
        'cancelled',
        'copied',
        'Undo',
      };
      for (final k in messageKeys.where((k) => !values.contains(k))) {
        expect(_allowedKeys, contains(k), reason: 'unexpected key "$k"');
      }
      for (final k in _allowedKeys) {
        expect(
          RegExp(
            r'typed|key|char|buffer|keystroke',
            caseSensitive: false,
          ).hasMatch(k),
          isFalse,
          reason: k,
        );
      }
    });
  });

  group('nothing can log or send the buffer', () {
    test('Swift: no print, NSLog, os_log or Logger; DiagLog gets literals', () {
      for (final f in [_swiftBridge, _swiftCore]) {
        final src = _code(f);
        expect(
          src,
          isNot(matches(RegExp(r'\b(print|NSLog|os_log|debugPrint)\('))),
          reason: f,
        );
        expect(src, isNot(contains('Logger(')), reason: f);
        for (final m in RegExp(r'DiagLog\.log\(([^,)]+)').allMatches(src)) {
          final arg = m.group(1)!.trim();
          expect(
            arg.startsWith('"') || arg == 'code',
            isTrue,
            reason: '$f logs $arg',
          );
        }
      }
      // `code` only ever comes from a .skipped outcome.
      expect(_code(_swiftBridge), contains('case .skipped(let code):'));
    });

    test('C++: no printf, OutputDebugString, cout or cerr', () {
      for (final f in [_cppBridge, _cppPolicy]) {
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

    test('the buffer types describe themselves without their text', () {
      final core = _code(_swiftCore);
      expect(
        core,
        contains(
          'var description: String { "TypedBuffer(\\(scalars.count))" }',
        ),
      );
      expect(core, contains('var customMirror: Mirror'));
    });
  });

  group('log codes', () {
    test('Dart has every code of the design note', () {
      final names = {for (final c in LogCode.values) c.name};
      expect(names.containsAll(_designCodes), isTrue);
      expect(
        names.where((n) => n.startsWith('shortcut')).toSet(),
        _designCodes,
      );
    });

    test('every skip code the native matchers return is a log code', () {
      final names = {for (final c in LogCode.values) c.name};
      final used = <String>{
        for (final m in RegExp(
          r'\.skipped\("(\w+)"\)',
        ).allMatches(_code(_swiftCore)))
          m.group(1)!,
        for (final m in RegExp(
          r'Skipped\("(\w+)"\)',
        ).allMatches(_code(_cppPolicy)))
          m.group(1)!,
        for (final m in RegExp(
          r'return "(shortcut\w+)"',
        ).allMatches(_code(_cppPolicy)))
          m.group(1)!,
      };
      expect(used, {
        'shortcutSkippedInjected',
        'shortcutSkippedPassword',
        'shortcutSkippedIgnoredApp',
        'shortcutSkippedAdmin',
        'shortcutSkippedUnknownField',
      });
      expect(names.containsAll(used), isTrue);
    });
  });

  group('QA\'s synthetic-keys switch is debug only (PM 2026-11-09)', () {
    test('its symbols and argument appear only inside #if DEBUG in the '
        'Swift sources', () {
      final needles = [
        'SyntheticKeysSwitch',
        'acceptsSyntheticKeys',
        'KusungaAcceptSyntheticKeys',
        'shortcutSyntheticKeysAllowed',
      ];
      var seen = 0;
      for (final f
          in Directory('macos/Runner')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.swift'))) {
        for (final (line, inDebug) in swiftDebugLines(readSource(f.path))) {
          if (line.trimLeft().startsWith('//')) continue;
          for (final n in needles) {
            if (!line.contains(n)) continue;
            seen++;
            // DiagLog's closed list names every code, debug or not.
            final inCodeList = f.path.endsWith('DiagLog.swift');
            expect(
              inDebug || inCodeList,
              isTrue,
              reason: '${f.path}: "$n" outside #if DEBUG: $line',
            );
          }
        }
      }
      expect(seen, greaterThanOrEqualTo(4), reason: 'the switch exists');
    });

    test('the guard itself sees #else and nesting', () {
      final lines = swiftDebugLines(
        '#if DEBUG\na\n#if os(macOS)\nb\n#endif\n#else\nc\n#endif\nd',
      );
      bool at(String s) => lines.firstWhere((l) => l.$1 == s).$2;
      expect(at('a'), isTrue);
      expect(at('b'), isTrue);
      expect(at('c'), isFalse);
      expect(at('d'), isFalse);
    });

    test('not on Windows', () {
      expect(_read(_cppBridge), isNot(contains('Synthetic')));
      expect(_read(_cppPolicy), isNot(contains('Synthetic')));
    });
  });

  group('Mac permissions (ADR 0003)', () {
    test('both entitlements keep the App Sandbox', () {
      for (final f in [
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner/Release.entitlements',
      ]) {
        final plist = _read(f);
        expect(
          plist,
          matches(
            RegExp(r'<key>com\.apple\.security\.app-sandbox</key>\s*<true/>'),
          ),
          reason: f,
        );
      }
    });

    test('typed shortcuts never ask for the Accessibility API', () {
      for (final f in [_swiftBridge, _swiftCore]) {
        final src = _code(f);
        expect(src, isNot(contains('AXIsProcessTrustedWithOptions')));
        expect(src, isNot(contains('AXUIElement')));
        expect(src, isNot(contains('kAXTrustedCheckOptionPrompt')));
      }
    });

    test('the tap is listen-only and made only after a preflight', () {
      final src = _code(_swiftBridge);
      expect(src, contains('options: .listenOnly'));
      expect(
        src.indexOf('CGPreflightListenEventAccess()'),
        lessThan(src.indexOf('CGEvent.tapCreate')),
      );
      // The only prompt is behind the explanation card's Continue.
      expect(
        RegExp(r'CGRequestListenEventAccess\(\)').allMatches(src).length,
        1,
      );
    });
  });
}
