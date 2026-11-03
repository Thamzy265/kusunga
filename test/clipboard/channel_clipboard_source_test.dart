import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/channel_clipboard_source.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const events = EventChannel('com.wnasoni.kusunga/clipboard/events');
  const methods = MethodChannel('com.wnasoni.kusunga/clipboard');

  tearDown(() {
    messenger.setMockStreamHandler(events, null);
    messenger.setMockMethodCallHandler(methods, null);
  });

  Future<List<ClipboardEvent>> receive(List<Object?> sent) async {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sent.forEach(sink.success);
          sink.endOfStream();
        },
      ),
    );
    return ChannelClipboardSource().events.toList();
  }

  test('decodes text, concealed, too-large and read-error events', () async {
    final got = await receive([
      {'type': 'text', 'text': 'hello'},
      {'type': 'concealed'},
      {'type': 'tooLarge'},
      {'type': 'error', 'code': 'locked'},
    ]);

    expect(got[0], isA<ClipboardText>().having((e) => e.text, 'text', 'hello'));
    expect(
      got[1],
      isA<ClipboardSkipped>().having(
        (e) => e.reason,
        'reason',
        SkipReason.concealed,
      ),
    );
    expect(
      got[2],
      isA<ClipboardSkipped>().having(
        (e) => e.reason,
        'reason',
        SkipReason.tooLarge,
      ),
    );
    expect(
      got[3],
      isA<ClipboardReadError>().having((e) => e.code, 'code', 'locked'),
    );
  });

  test('a malformed event is dropped, not thrown', () async {
    final got = await receive([
      42,
      {'type': 'text'},
      {'type': 'text', 'text': 7},
      {'type': 'mystery'},
      {'type': 'text', 'text': 'ok'},
    ]);
    expect(got.length, 1);
    expect((got.single as ClipboardText).text, 'ok');
  });

  test('a concealed event never carries text through', () async {
    final got = await receive([
      {'type': 'concealed', 'text': 'hunter2'},
    ]);
    expect(got.single, isA<ClipboardSkipped>());
  });

  test('asks the native side for the paste-access state', () async {
    for (final (native, expected) in [
      ('allow', PasteAccess.allowed),
      ('ask', PasteAccess.needsSetup),
      ('deny', PasteAccess.needsSetup),
      ('unsupported', PasteAccess.notApplicable),
    ]) {
      messenger.setMockMethodCallHandler(methods, (call) async {
        expect(call.method, 'accessBehavior');
        return native;
      });
      expect(await ChannelClipboardSource().pasteAccess(), expected);
    }
  });

  test(
    'a missing or failing native side means paste access is not applicable',
    () async {
      // No handler: MissingPluginException, as on Windows or in a test.
      expect(
        await ChannelClipboardSource().pasteAccess(),
        PasteAccess.notApplicable,
      );

      messenger.setMockMethodCallHandler(
        methods,
        (_) async => throw PlatformException(code: 'x'),
      );
      expect(
        await ChannelClipboardSource().pasteAccess(),
        PasteAccess.notApplicable,
      );
    },
  );
}
