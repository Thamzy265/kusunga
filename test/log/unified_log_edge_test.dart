import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/log/unified_log.dart';

/// Edge cases for the unified-log mirror (0888574): what Dart can send, and
/// that a missing or failing native side is never an error.
class _Recording implements ErrorLog {
  final lines = <String>[];
  @override
  void log(LogCode code, [int? detail]) =>
      lines.add(detail == null ? code.name : '${code.name} $detail');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.wnasoni.kusunga/diag');

  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('with no native side at all (Windows) nothing is thrown, not even '
      'later', () async {
    // No handler: invokeMethod throws MissingPluginException asynchronously.
    final log = ChannelUnifiedLog();
    for (final c in LogCode.values) {
      log.log(c, 1);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // An unhandled async error would fail this test by itself.
  });

  test('a native side that throws something that is not a PlatformException '
      'is still swallowed', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw StateError('boom');
    });
    ChannelUnifiedLog().log(LogCode.readFailed, 9);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('every code goes out as its own name, a short alphanumeric word and a '
      'number or nothing', () async {
    final seen = <Map<Object?, Object?>>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      expect(c.method, 'log');
      seen.add(c.arguments as Map<Object?, Object?>);
      return null;
    });
    final log = ChannelUnifiedLog();
    for (final c in LogCode.values) {
      log.log(c);
    }
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, LogCode.values.length);
    for (final a in seen) {
      expect(a.keys.toSet(), {'code', 'detail'}, reason: 'no other field');
      expect(a['code'], matches(RegExp(r'^[A-Za-z0-9]{1,40}$')));
      expect(a['detail'], isNull);
    }
  });

  test('numbers pass through unchanged, including negative and very large '
      'ones', () async {
    final seen = <Object?>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      seen.add((c.arguments as Map)['detail']);
      return null;
    });
    final log = ChannelUnifiedLog();
    for (final n in [0, -1, 7, 1 << 40, 9007199254740991]) {
      log.log(LogCode.permissionSnapshot, n);
    }
    await Future<void>.delayed(Duration.zero);
    expect(seen, [0, -1, 7, 1 << 40, 9007199254740991]);
  });

  test('a custom channel is used when given (tests never reach the real '
      'one)', () async {
    const other = MethodChannel('test/other');
    final seen = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(other, (c) async {
      seen.add(c.method);
      return null;
    });
    addTearDown(
      () =>
          binding.defaultBinaryMessenger.setMockMethodCallHandler(other, null),
    );
    ChannelUnifiedLog(channel: other).log(LogCode.writeFailed);
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['log']);
  });

  test('the deferred log mirrors every code at once, even the ones beyond '
      'the 20 the file log can hold', () {
    final mirror = _Recording();
    final deferred = DeferredErrorLog(mirror: mirror);
    for (var i = 0; i < DeferredErrorLog.maxWaiting + 5; i++) {
      deferred.log(LogCode.hotkeyRegisterFailed, i);
    }
    expect(mirror.lines.length, DeferredErrorLog.maxWaiting + 5);
    final file = _Recording();
    deferred.attach(file);
    expect(
      file.lines.length,
      DeferredErrorLog.maxWaiting,
      reason: 'oldest dropped',
    );
    expect(
      mirror.lines.length,
      DeferredErrorLog.maxWaiting + 5,
      reason: 'attach never replays to the mirror',
    );
  });

  test('a second attach is ignored and never replays to the mirror', () {
    final mirror = _Recording();
    final deferred = DeferredErrorLog(mirror: mirror);
    deferred.log(LogCode.writeFailed);
    final first = _Recording();
    final second = _Recording();
    deferred.attach(first);
    deferred.attach(second);
    deferred.log(LogCode.readFailed);
    expect(mirror.lines, ['writeFailed', 'readFailed']);
    expect(first.lines, ['writeFailed', 'readFailed']);
    expect(second.lines, isEmpty);
  });

  test('without a mirror the deferred log behaves as before', () {
    final deferred = DeferredErrorLog();
    deferred.log(LogCode.writeFailed, 2);
    final file = _Recording();
    deferred.attach(file);
    expect(file.lines, ['writeFailed 2']);
  });
}
