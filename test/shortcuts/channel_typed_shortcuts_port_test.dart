import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/channel_typed_shortcuts_port.dart';
import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';

/// Every typed-shortcut platform call against a mocked channel. The names
/// and arguments here are the contract with TypedShortcutBridge.swift and
/// typed_shortcut_bridge.cpp.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/shortcuts');
  const codec = StandardMethodCodec();

  final calls = <MethodCall>[];
  Object? Function(MethodCall call) answer = (_) => null;

  setUp(() {
    calls.clear();
    answer = (_) => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final result = answer(call);
      if (result is Exception) throw result;
      return result;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  ChannelTypedShortcutsPort port() =>
      ChannelTypedShortcutsPort(channel: channel);

  Future<void> fromNative(String method, Object? args) =>
      messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );

  test('setTable sends ids and shortcuts only', () async {
    await port().setTable([
      (id: 1, shortcut: ';email'),
      (id: 2, shortcut: ';mob'),
    ]);
    expect(calls.single.method, 'setTable');
    expect(calls.single.arguments, {
      'entries': [
        {'id': 1, 'shortcut': ';email'},
        {'id': 2, 'shortcut': ';mob'},
      ],
    });
  });

  test('setIgnored sends the app ids', () async {
    await port().setIgnored(['com.1password.1password']);
    expect(calls.single.arguments, {
      'appIds': ['com.1password.1password'],
    });
  });

  test('setEnabled and status answer a status by name', () async {
    answer = (_) => 'needsPermission';
    expect(await port().setEnabled(true), TypedShortcutStatus.needsPermission);
    expect(calls.single.arguments, {'on': true});
    answer = (_) => 'paused';
    expect(await port().status(), TypedShortcutStatus.paused);
  });

  test('no native side: on is "failed", off is "off"', () async {
    answer = (_) => PlatformException(code: 'x');
    expect(await port().setEnabled(true), TypedShortcutStatus.failed);
    expect(await port().setEnabled(false), TypedShortcutStatus.off);
    answer = (_) => 'nonsense';
    expect(await port().status(), TypedShortcutStatus.off);
  });

  test('replace sends the delete count and the snippet text', () async {
    for (final r in ReplaceOutcome.values) {
      answer = (_) => r.name;
      expect(await port().replace(6, 'will@example.com'), r);
    }
    expect(calls.first.arguments, {
      'deleteCount': 6,
      'text': 'will@example.com',
    });
    answer = (_) => PlatformException(code: 'x');
    expect(await port().replace(6, 'x'), ReplaceOutcome.failed);
  });

  test('runningApps reads id, name and icon; bad rows are dropped', () async {
    final png = Uint8List.fromList([1, 2, 3]);
    answer = (_) => [
      {'appId': 'com.example.bank', 'name': 'My Bank', 'icon': png},
      {'appId': 'bank.exe', 'name': 'Bank', 'icon': null},
      {'appId': '', 'name': 'No id'},
      {'appId': 'x', 'name': 5},
      'junk',
    ];
    final apps = await port().runningApps();
    expect(apps.map((a) => a.appId), ['com.example.bank', 'bank.exe']);
    expect(apps.first.icon, png);
    expect(apps.last.icon, isNull);
    answer = (_) => null;
    expect(await port().runningApps(), isEmpty);
  });

  test('requestListenAccess and openInputMonitoringSettings', () async {
    answer = (_) => true;
    expect(await port().requestListenAccess(), isTrue);
    await port().openInputMonitoringSettings();
    expect(calls.map((c) => c.method), [
      'requestListenAccess',
      'openInputMonitoringSettings',
    ]);
  });

  test('matched carries a snippet id and a delete count only', () async {
    final p = port();
    final events = <TypedShortcutEvent>[];
    p.events.listen(events.add);
    await fromNative('matched', {'snippetId': 7, 'deleteCount': 6});
    // Out of range or malformed: dropped.
    await fromNative('matched', {'snippetId': 7, 'deleteCount': 0});
    await fromNative('matched', {'snippetId': 7, 'deleteCount': 33});
    await fromNative('matched', {'snippetId': '7', 'deleteCount': 6});
    await fromNative('matched', null);
    expect(events.length, 1);
    final m = events.single as ShortcutMatched;
    expect((m.snippetId, m.deleteCount), (7, 6));
  });

  test('statusChanged carries a status name', () async {
    final p = port();
    final events = <TypedShortcutEvent>[];
    p.events.listen(events.add);
    await fromNative('statusChanged', {'status': 'stopped'});
    await fromNative('statusChanged', {'status': 'bogus'});
    expect(
      (events.single as ShortcutStatusChanged).status,
      TypedShortcutStatus.stopped,
    );
  });
}
