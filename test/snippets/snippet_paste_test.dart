import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/channel_picker_port.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

void main() {
  late FakePickerPort port;
  late FakeLog log;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController c;

  setUp(() {
    port = FakePickerPort();
    log = FakeLog();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      snippetStore: MemorySnippetStore(),
    )..start();
    addTearDown(history.dispose);
  });

  Future<void> open() async {
    c = PickerController(port: port, log: log, isMac: true);
    addTearDown(c.dispose);
    await c.start();
    await c.attach(history);
    port.press();
  }

  testWidgets('a snippet pastes its whole text, skipping history, and logs '
      'pasteSource 1 only', (tester) async {
    final long = 'y' * 3000;
    final id = history.snippets
        .save(name: 'Long one', content: long, type: SnippetType.other)
        .id!;
    await open();
    log.codes.clear();
    log.details.clear();
    await c.pasteSnippet(id);
    expect(port.pastes.single.text, long);
    expect(port.pastes.single.post, isTrue);
    expect(port.pastes.single.skipHistory, isTrue);
    expect(log.codes, [LogCode.pasteSource]);
    expect(log.details, [1]);
    expect(c.mode, WindowMode.manage);
  });

  testWidgets('a history item is pasted as before and logs pasteSource 0', (
    tester,
  ) async {
    source.copy('from history');
    final id = history.items.single.id;
    await open();
    log.codes.clear();
    log.details.clear();
    await c.pasteItem(id);
    expect(port.pastes.single.skipHistory, isFalse);
    expect(log.codes, [LogCode.pasteSource]);
    expect(log.details, [0]);
  });

  testWidgets('a snippet paste that only copies gets the usual toast', (
    tester,
  ) async {
    final id = history.snippets
        .save(name: 'A', content: 'a', type: SnippetType.other)
        .id!;
    await open();
    port.pasteAnswer = PasteOutcome.focusTimeout;
    await c.pasteSnippet(id);
    expect(c.toast, ToastKind.copied);
    expect(
      log.codes,
      containsAllInOrder([LogCode.pasteSource, LogCode.pasteFocusTimeout]),
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a snippet that is gone pastes nothing', (tester) async {
    await open();
    await c.pasteSnippet(4242);
    expect(port.pastes, isEmpty);
  });

  testWidgets('snippets paste in memory-only mode too', (tester) async {
    final store = MemorySnippetStore()
      ..insert(name: 'A', content: 'loaded', type: SnippetType.other, nowMs: 1);
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      notices: const {},
      snippetStore: store,
    );
    addTearDown(history.dispose);
    await open();
    await c.pasteSnippet(store.list().single.id);
    expect(port.pastes.single.text, 'loaded');
  });

  group('ChannelPickerPort sends skipHistory', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.wnasoni.kusunga/picker');
    tearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    test('true for a snippet, false for history', () async {
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return 'pasted';
      });
      final p = ChannelPickerPort();
      await p.paste('s', post: true, skipHistory: true);
      await p.paste('h', post: false);
      expect(calls[0].arguments, {
        'text': 's',
        'post': true,
        'skipHistory': true,
      });
      expect(calls[1].arguments, {
        'text': 'h',
        'post': false,
        'skipHistory': false,
      });
    });
  });
}
