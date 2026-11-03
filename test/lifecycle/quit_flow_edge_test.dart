// Tester (M1.2): quit-flow ordering, double quit and failure cases, and the
// flush when the store is memory only. The developer's tests are in
// quit_flow_test.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/lifecycle/app_lifecycle.dart';
import 'package:kusunga/lifecycle/quit_flow.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/lifecycle');

  late List<String> steps;
  late Object? quitError;
  late Completer<void>? closeGate;

  QuitFlow makeFlow({
    Future<void> Function()? stopTray,
    Future<void> Function()? stopWindow,
    Future<void> Function()? closeHistory,
  }) => QuitFlow(
    lifecycle: AppLifecycle(exitFallback: (code) => steps.add('exit $code')),
    closeHistory:
        closeHistory ??
        () async {
          steps.add('close start');
          await closeGate?.future;
          steps.add('close end');
        },
    stopTray: stopTray ?? () async => steps.add('stop tray'),
    stopWindow: stopWindow ?? () async => steps.add('stop window'),
  );

  setUp(() {
    steps = [];
    quitError = null;
    closeGate = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      steps.add('native ${call.method}');
      if (call.method == 'quit' && quitError != null) throw quitError!;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> nativeFlush() => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(const MethodCall('flush')),
    (_) {},
  );

  /// Native waits for the answer to `flush`; this resolves when it comes.
  Future<ByteData?> nativeFlushAnswer() {
    final done = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('flush')),
      done.complete,
    );
    return done.future;
  }

  group('ordering', () {
    test('the app is not told to quit until the history has closed', () async {
      closeGate = Completer<void>();
      final flow = makeFlow()..listenForNativeFlush();
      final quitting = flow.quitFromTray();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(steps, ['stop tray', 'stop window', 'close start']);
      expect(steps, isNot(contains('native quit')));

      closeGate!.complete();
      await quitting;
      expect(steps.last, 'native quit');
      expect(
        steps.indexOf('close end'),
        lessThan(steps.indexOf('native quit')),
      );
    });

    test('native flush arriving while tray Quit is closing waits for the '
        'same close, which runs once', () async {
      closeGate = Completer<void>();
      final flow = makeFlow()..listenForNativeFlush();
      final quitting = flow.quitFromTray();
      await Future<void>.delayed(Duration.zero);
      var answered = false;
      final answer = nativeFlushAnswer().then((_) => answered = true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        answered,
        isFalse,
        reason: 'native must not quit before the close has finished',
      );

      closeGate!.complete();
      await Future.wait([quitting, answer]);
      expect(steps.where((s) => s == 'close start'), hasLength(1));
    });

    test('Cmd+Q while a native flush is already closing: one close, both '
        'answered after it ends', () async {
      closeGate = Completer<void>();
      makeFlow().listenForNativeFlush();
      var a = false;
      var b = false;
      final first = nativeFlushAnswer().then((_) => a = true);
      final second = nativeFlushAnswer().then((_) => b = true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect([a, b], [false, false]);
      closeGate!.complete();
      await Future.wait([first, second]);
      expect(steps.where((s) => s == 'close start'), hasLength(1));
      expect(steps.indexOf('close end'), greaterThan(-1));
    });

    test('a native flush after the tray Quit finished answers at once and '
        'closes nothing again', () async {
      final flow = makeFlow()..listenForNativeFlush();
      await flow.quitFromTray();
      steps.clear();
      await nativeFlush();
      expect(steps, isEmpty);
    });

    test('three tray Quits at once ask native to quit once', () async {
      final flow = makeFlow();
      await Future.wait([
        flow.quitFromTray(),
        flow.quitFromTray(),
        flow.quitFromTray(),
      ]);
      expect(steps.where((s) => s == 'native quit'), hasLength(1));
      expect(steps.where((s) => s == 'stop tray'), hasLength(1));
      expect(steps.where((s) => s == 'close start'), hasLength(1));
    });

    test('a native flush that fails still answers native', () async {
      final flow = makeFlow(closeHistory: () async => throw StateError('x'))
        ..listenForNativeFlush();
      final answer = await nativeFlushAnswer();
      expect(answer, isNotNull);
      expect(
        const StandardMethodCodec().decodeEnvelope(answer!),
        isNull,
        reason: 'success envelope: native is not left waiting for 3 seconds',
      );
      await flow.flush();
    });
  });

  group('failures never stop the quit', () {
    test('a tray that throws on stop: the history is still closed and the '
        'app still quits', () async {
      // Bug repro (BUG-17): stopTray is awaited with no try/catch, so an
      // error there skips the close and the quit; the app stays open with
      // no tray and an open database.
      final flow = makeFlow(stopTray: () async => throw StateError('tray'));
      await flow.quitFromTray().catchError((Object _) {});
      expect(steps, contains('close start'));
      expect(steps, contains('native quit'));
    });

    test('a window that throws on stop: the history is still closed and the '
        'app still quits', () async {
      final flow = makeFlow(stopWindow: () async => throw StateError('win'));
      await flow.quitFromTray().catchError((Object _) {});
      expect(steps, contains('close start'));
      expect(steps, contains('native quit'));
    });

    test('a close that throws: the app still quits', () async {
      final flow = makeFlow(closeHistory: () async => throw StateError('db'));
      await flow.quitFromTray();
      expect(steps, contains('native quit'));
    });

    test('if native cannot quit the first time, choosing Quit again tries '
        'again', () async {
      // Bug repro (BUG-18): the failed attempt is kept, so every later Quit
      // click returns the same failed result and does nothing.
      quitError = PlatformException(code: 'nope');
      final flow = makeFlow();
      await flow.quitFromTray().catchError((Object _) {});
      quitError = null;
      steps.clear();
      await flow.quitFromTray().catchError((Object _) {});
      expect(steps, contains('native quit'));
    });

    test(
      'without a native side Quit falls back to exit(0) after closing',
      () async {
        messenger.setMockMethodCallHandler(channel, null);
        final flow = makeFlow();
        await flow.quitFromTray();
        expect(steps, [
          'stop tray',
          'stop window',
          'close start',
          'close end',
          'exit 0',
        ]);
      },
    );
  });

  group('closing the history on the way out', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_quit_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('memory-only history: quitting writes nothing to disk and the '
        'items are gone with it', () async {
      final store = MemoryHistoryStore();
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        notices: {},
        source: source,
        log: const NullErrorLog(),
      )..start();
      source.copy('only in memory');
      final flow = makeFlow(closeHistory: service.close);
      await flow.quitFromTray();
      expect(dir.listSync(), isEmpty);
      expect(service.items, isEmpty);
      source.copy('after quit');
      expect(service.items, isEmpty, reason: 'the watcher is stopped');
      service.dispose();
    });

    test('a real history is closed: the file can be opened again at once '
        'and holds everything copied before the quit', () async {
      final path = '${dir.path}/k.db';
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        source: source,
        log: const NullErrorLog(),
        clock: () => 1,
      )..start();
      for (var i = 0; i < 25; i++) {
        source.copy('copy $i');
      }
      final flow = makeFlow(closeHistory: service.close)
        ..listenForNativeFlush();
      await nativeFlushAnswer();

      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(again.count, 25);
      expect(again.list().first.preview, 'copy 24');
      again.close();
      await flow.quitFromTray();
      service.dispose();
    });

    test('a copy that arrives during the close is not half written', () async {
      final path = '${dir.path}/k.db';
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        source: source,
        log: FakeLog(),
        clock: () => 1,
      )..start();
      source.copy('before');
      final closing = service.close();
      source.copy('during');
      await closing;
      source.copy('after');
      service.dispose();

      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      final saved = again.list().map((i) => i.preview).toList();
      expect(saved, contains('before'));
      expect(saved, isNot(contains('after')));
      expect(again.count, lessThanOrEqualTo(2));
      again.close();
    });

    test('closing twice, and from every path, closes the file once', () async {
      final store = FlakyStore(MemoryHistoryStore());
      final service = HistoryService(
        store: store,
        source: FakeClipboardSource(),
        log: const NullErrorLog(),
      )..start();
      final flow = makeFlow(closeHistory: service.close)
        ..listenForNativeFlush();
      await Future.wait([
        nativeFlushAnswer(),
        flow.quitFromTray(),
        flow.flush(),
      ]);
      await service.close();
      expect(store.closes, 1);
      service.dispose();
    });

    test('clear and delete just before quit are on disk', () async {
      final path = '${dir.path}/k.db';
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final source = FakeClipboardSource();
      var t = 0;
      final service = HistoryService(
        store: store,
        source: source,
        log: const NullErrorLog(),
        clock: () => t += 10,
      )..start();
      source.copy('a');
      source.copy('b');
      source.copy('c');
      service.delete(service.items.first.id); // c
      await makeFlow(closeHistory: service.close).quitFromTray();
      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(again.list().map((i) => i.preview), ['b', 'a']);
      again.close();
      service.dispose();
    });
  });

  test('ClipItem limits match the design: 1 MB and a 2,000 character list', () {
    expect(ClipItem.maxContentLength, 1048576);
    expect(ClipItem.previewLength, 2000);
  });
}
