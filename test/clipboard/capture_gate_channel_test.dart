// M1.6 (ADR 0005): the two capture calls and the two new events. The events
// carry nothing but their type: the source app never crosses the channel.
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

  test(
    'ignoredApp is a skip and sourceUnknown a notice, with no text',
    () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            sink.success({'type': 'ignoredApp'});
            sink.success({'type': 'sourceUnknown'});
            sink.endOfStream();
          },
        ),
      );
      final got = await ChannelClipboardSource().events.toList();
      expect(
        got[0],
        isA<ClipboardSkipped>().having(
          (e) => e.reason,
          'reason',
          SkipReason.ignoredApp,
        ),
      );
      expect(got[1], isA<ClipboardSourceUnknown>());
    },
  );

  test(
    'setCapturePause and setCaptureIgnored send exactly their argument',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return true;
      });
      final source = ChannelClipboardSource();
      expect(await source.setCapturePause(-1), isTrue);
      expect(await source.setCapturePause(1762790400000), isTrue);
      expect(await source.setCaptureIgnored(['keepass.exe', 'a.b']), isTrue);
      expect(
        [for (final c in calls) c.method],
        ['setCapturePause', 'setCapturePause', 'setCaptureIgnored'],
      );
      expect(calls[0].arguments, {'until': -1});
      expect(calls[1].arguments, {'until': 1762790400000});
      expect(calls[2].arguments, {
        'appIds': ['keepass.exe', 'a.b'],
      });
    },
  );

  test(
    'a missing or failing native side answers false, never throws',
    () async {
      final source = ChannelClipboardSource();
      expect(await source.setCapturePause(0), isFalse); // no handler
      expect(await source.setCaptureIgnored(const []), isFalse);
      messenger.setMockMethodCallHandler(methods, (call) async {
        throw PlatformException(code: 'x');
      });
      expect(await source.setCapturePause(0), isFalse);
      expect(await source.setCaptureIgnored(const []), isFalse);
      messenger.setMockMethodCallHandler(methods, (call) async => false);
      expect(await source.setCapturePause(0), isFalse);
    },
  );
}
