import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/lifecycle/app_lifecycle.dart';
import 'package:kusunga/lifecycle/quit_flow.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('uk.org.cgatechnologies.kusunga/lifecycle');

  late List<String> steps;
  late QuitFlow flow;
  Object? flushError;

  setUp(() {
    steps = [];
    flushError = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      steps.add('native ${call.method}');
      return null;
    });
    flow = QuitFlow(
      lifecycle: AppLifecycle(),
      closeHistory: () async {
        steps.add('close history');
        if (flushError != null) throw flushError!;
      },
      stopTray: () async => steps.add('stop tray'),
      stopWindow: () async => steps.add('stop window'),
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> nativeFlush() => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(const MethodCall('flush')),
    (_) {},
  );

  test(
    'tray Quit: stops the tray and window, closes history, then quits',
    () async {
      await flow.quitFromTray();
      expect(steps, [
        'stop tray',
        'stop window',
        'close history',
        'native quit',
      ]);
    },
  );

  test('tray Quit still quits when closing the history fails', () async {
    flushError = StateError('disk');
    await flow.quitFromTray();
    expect(steps.last, 'native quit');
  });

  test(
    'Cmd+Q / log off: native asks for a flush and history is closed',
    () async {
      flow.listenForNativeFlush();
      await nativeFlush();
      expect(steps, ['close history']);
    },
  );

  test('history is closed once even if several exit paths run', () async {
    flow.listenForNativeFlush();
    await nativeFlush();
    await flow.quitFromTray();
    await nativeFlush();
    expect(steps.where((s) => s == 'close history').length, 1);
  });

  test('pressing Quit twice quits once', () async {
    await Future.wait([flow.quitFromTray(), flow.quitFromTray()]);
    expect(steps.where((s) => s == 'native quit').length, 1);
  });
}
