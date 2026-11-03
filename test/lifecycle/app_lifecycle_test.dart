import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/lifecycle/app_lifecycle.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/lifecycle');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Plays the native side: asks Dart to flush and waits for the answer.
  Future<void> nativeAsksToFlush() async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('flush')),
      (_) {},
    );
  }

  test('native flush runs the registered handler and waits for it', () async {
    final lifecycle = AppLifecycle();
    var finished = false;
    lifecycle.onFlush(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      finished = true;
    });

    await nativeAsksToFlush();
    expect(finished, isTrue);
  });

  test('a failing flush handler still answers native', () async {
    final lifecycle = AppLifecycle();
    lifecycle.onFlush(() async => throw StateError('boom'));
    await nativeAsksToFlush(); // must complete, not hang or throw
  });

  test('quit asks native to quit', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await AppLifecycle().quit();
    expect(calls, ['quit']);
  });

  test('with no native side, quit falls back to exiting', () async {
    var exitCode = -1;
    await AppLifecycle(exitFallback: (c) => exitCode = c).quit();
    expect(exitCode, 0);
  });
}
