// Tester round 3 (M1.5 fixes C2, C7, S1/C4 parity): the match id on the
// channel and through the service, "Starting…" always clearing, and source
// guards that the restore marks cover every marker the clipboard watchers
// treat as secret.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/channel_typed_shortcuts_port.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';

import '../support/fakes.dart';
import 'fake_typed_shortcuts_port.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('matchId on the channel', () {
    const channel = MethodChannel('com.wnasoni.kusunga/shortcuts');
    const codec = StandardMethodCodec();
    final messenger = binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'replaced';
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> fromNative(String method, Object? args) =>
        messenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

    test('matched needs a positive integer matchId; everything else is '
        'dropped', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      final events = <ShortcutMatched>[];
      p.events.listen((e) => events.add(e as ShortcutMatched));
      for (final bad in <Object?>[
        null,
        0,
        -1,
        1.0,
        '1',
        true,
        [1],
      ]) {
        await fromNative('matched', {
          'snippetId': 7,
          'deleteCount': 6,
          'matchId': bad,
        });
      }
      await fromNative('matched', {'snippetId': 7, 'deleteCount': 6});
      expect(events, isEmpty);
      for (final good in [1, 2, 0x7FFFFF]) {
        await fromNative('matched', {
          'snippetId': 7,
          'deleteCount': 6,
          'matchId': good,
        });
      }
      expect(events.map((e) => e.matchId), [1, 2, 0x7FFFFF]);
    });

    test('replace sends exactly matchId, deleteCount and text, with the id '
        'as given', () async {
      final p = ChannelTypedShortcutsPort(channel: channel);
      await p.replace(0x7FFFFF, 32, 'will@example.com');
      final args = calls.single.arguments as Map;
      expect(args.keys.toSet(), {'matchId', 'deleteCount', 'text'});
      expect(args['matchId'], 0x7FFFFF);
      expect(args['deleteCount'], 32);
    });
  });

  group('the service passes the match id through', () {
    late _HoldingPort port;
    late SnippetService snippets;
    late Map<String, String> settings;
    late FakeLog log;

    setUp(() {
      port = _HoldingPort();
      snippets = SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      );
      settings = {'typed_shortcuts_on': '1'};
      log = FakeLog();
    });

    ShortcutService make() {
      final s = ShortcutService(
        port: port,
        snippets: snippets,
        ignoredApps: MemoryIgnoredAppStore(),
        readSetting: (k) => settings[k],
        writeSetting: (k, v) {
          settings[k] = v;
          return true;
        },
        log: log,
        isWindows: false,
        available: true,
      );
      addTearDown(s.dispose);
      return s;
    }

    int add(String code) => snippets
        .save(
          name: 'n$code',
          content: 'text $code',
          type: SnippetType.other,
          shortcut: code,
        )
        .id!;

    test('each replace carries the id of its own match, in order', () async {
      final a = add(';aa');
      final b = add(';bb');
      final s = make();
      await s.start();
      port.match(a, 3, matchId: 41);
      await pumpEventQueue();
      port.match(b, 3, matchId: 42);
      await pumpEventQueue();
      expect(port.replacedMatchIds, [41, 42]);
      expect(port.replaced.map((r) => r.$2), ['text ;aa', 'text ;bb']);
    });

    test('the same match twice is sent twice (native answers the second as '
        'cancelled); a "cancelled" answer shows nothing to the user', () async {
      final a = add(';aa');
      final s = make();
      await s.start();
      port.replaceAnswer = ReplaceOutcome.cancelled;
      port.match(a, 3, matchId: 7);
      await pumpEventQueue();
      port.match(a, 3, matchId: 7);
      await pumpEventQueue();
      expect(port.replacedMatchIds, [7, 7]);
    });

    test('a match that arrives while a replace is running is dropped, never '
        'sent with the older id', () async {
      final a = add(';aa');
      final b = add(';bb');
      final s = make();
      await s.start();
      final hold = Completer<void>();
      port.holdReplace = hold;
      port.match(a, 3, matchId: 1);
      port.match(b, 3, matchId: 2);
      hold.complete();
      await pumpEventQueue();
      expect(port.replacedMatchIds, [1]);
    });

    test('"Starting…" clears and listeners hear it even when the status '
        'does not change', () async {
      final s = make();
      await s.start();
      expect(s.status, TypedShortcutStatus.on);
      var heard = 0;
      s.addListener(() => heard++);
      port.holdEnable = Completer<void>();
      final turning = s.setEnabled(true);
      await pumpEventQueue();
      expect(s.busy, isTrue);
      port.holdEnable!.complete();
      await turning;
      expect(s.busy, isFalse);
      expect(s.status, TypedShortcutStatus.on);
      expect(heard, greaterThanOrEqualTo(2), reason: 'busy on, then busy off');
    });

    test(
      '"Starting…" also clears when the switch moved again meanwhile',
      () async {
        settings['typed_shortcuts_on'] = '0';
        final s = make();
        await s.start();
        port.holdEnable = Completer<void>();
        final on = s.setEnabled(true);
        await pumpEventQueue();
        final off = s.setEnabled(false);
        port.holdEnable!.complete();
        await Future.wait([on, off]);
        expect(s.busy, isFalse);
        expect(s.enabled, isFalse);
      },
    );
  });

  group('restore marks cover every secret marker', () {
    String read(String p) => File(p).readAsStringSync();

    test('Mac: the markers kept on put-back text are exactly the ones the '
        'clipboard watcher treats as secret', () {
      final watcher = read('macos/Runner/ClipboardWatcher.swift');
      final core = read('macos/Runner/TypedShortcutCore.swift');
      Set<String> quoted(String src, String after) {
        final start = src.indexOf(after);
        expect(start, greaterThanOrEqualTo(0), reason: after);
        final end = src.indexOf(RegExp(r'[\]]'), start);
        return {
          for (final m in RegExp(
            r'"(org\.nspasteboard\.\w+)"',
          ).allMatches(src.substring(start, end + 1)))
            m.group(1)!,
        };
      }

      final secret = quoted(watcher, 'static let secretTypes');
      final kept = quoted(core, 'static let privacyMarkers');
      expect(secret, isNotEmpty);
      expect(kept, secret);
      // The snippet itself is transient and concealed, both inside the set.
      expect(
        secret,
        containsAll([
          'org.nspasteboard.TransientType',
          'org.nspasteboard.ConcealedType',
        ]),
      );
    });

    test('Windows: every "don\'t keep" format the watcher reads is a marker '
        'the restore decision tolerates, and the restore sets all three '
        'marks', () {
      final bridge = read('windows/runner/clipboard_bridge.cpp');
      final policy = read('windows/runner/typed_shortcut_policy.h');
      final watched = {
        for (final m in RegExp(
          r'RegisterClipboardFormatW\(L"([^"]+)"\)',
        ).allMatches(bridge))
          m.group(1)!,
      }..remove('com.wnasoni.kusunga.self');
      expect(watched, isNotEmpty);
      final markers = RegExp(
        r'kMarkers\[\] = \{([^}]*)\}',
      ).firstMatch(policy)!.group(1)!;
      for (final name in watched) {
        expect(markers, contains('"$name"'), reason: name);
      }
      final marks = RegExp(
        r'RestoreMarks\(\) \{ return \{([^}]*)\}',
      ).firstMatch(policy)!.group(1)!;
      expect(marks.replaceAll(' ', ''), 'true,true,true');
      // The bridge puts text back with those marks and writes the snippet
      // with the snippet marks, never with none.
      final typed = read('windows/runner/typed_shortcut_bridge.cpp');
      expect(typed, contains('kusunga::RestoreMarks()'));
      expect(typed, contains('kusunga::SnippetMarks()'));
    });

    test('Mac: the snippet and the put-back text are each one pasteboard '
        'item written in one call', () {
      final bridge = read('macos/Runner/TypedShortcutBridge.swift');
      expect(bridge, contains('writeObjects([item])'));
      expect(RegExp(r'writeObjects\(').allMatches(bridge).length, 1);
      // No separate marker write after the text (the old two-step write).
      expect(bridge, isNot(contains('pasteboard.setData(Data(), forType')));
    });
  });
}

/// The fake native side, with a replace that can be held open.
class _HoldingPort extends FakeTypedShortcutsPort {
  Completer<void>? holdReplace;

  @override
  Future<ReplaceOutcome> replace(
    int matchId,
    int deleteCount,
    String text,
  ) async {
    final result = await super.replace(matchId, deleteCount, text);
    await holdReplace?.future;
    return result;
  }
}
