import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/picker/channel_picker_port.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/shortcut.dart';

/// Every platform call of the picker, against a mocked channel (M1.2 lesson 1:
/// fakes alone missed native bugs). The names and arguments here are the
/// contract with `PickerBridge.swift` and `picker_bridge.cpp`.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/picker');

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

  ChannelPickerPort port() => ChannelPickerPort(channel: channel);

  group('registerShortcut', () {
    test('sends the key and the modifiers by name', () async {
      answer = (_) => 'ok';
      final r = await port().registerShortcut(
        PickerShortcut.parse('ctrl+shift+meta+f5')!,
      );
      expect(r, ShortcutRegistration.registered);
      expect(calls.single.method, 'registerShortcut');
      expect(calls.single.arguments, {
        'key': 'f5',
        'modifiers': ['ctrl', 'shift', 'meta'],
      });
    });

    test('"taken" means another app owns the combination', () async {
      answer = (_) => 'taken';
      expect(
        await port().registerShortcut(PickerShortcut.parse('alt+k')!),
        ShortcutRegistration.taken,
      );
    });

    test('anything else, an error, or no native side is a failure', () async {
      for (final reply in <Object?>[
        'invalid',
        'weird',
        null,
        7,
        PlatformException(code: 'x'),
        MissingPluginException(),
      ]) {
        answer = (_) => reply;
        expect(
          await port().registerShortcut(PickerShortcut.parse('alt+k')!),
          ShortcutRegistration.failed,
          reason: '$reply',
        );
      }
    });
  });

  group('paste', () {
    test('sends the whole text and whether to post the keystroke', () async {
      answer = (_) => 'pasted';
      final r = await port().paste('hello\nworld', post: true);
      expect(r, PasteOutcome.pasted);
      expect(calls.single.method, 'paste');
      expect(calls.single.arguments, {'text': 'hello\nworld', 'post': true});

      await port().paste('x', post: false);
      expect(calls.last.arguments, {'text': 'x', 'post': false});
    });

    test('maps every outcome name', () async {
      const names = {
        'pasted': PasteOutcome.pasted,
        'noPermission': PasteOutcome.noPermission,
        'focusTimeout': PasteOutcome.focusTimeout,
        'targetGone': PasteOutcome.targetGone,
        'targetElevated': PasteOutcome.targetElevated,
        'copyOnly': PasteOutcome.copyOnly,
        'pastedForced': PasteOutcome.pastedForced,
        'failed': PasteOutcome.failed,
      };
      for (final e in names.entries) {
        answer = (_) => e.key;
        expect(await port().paste('t', post: true), e.value, reason: e.key);
      }
    });

    test('an unknown answer, an error or no native side is "failed"', () async {
      for (final reply in <Object?>[
        'surprise',
        null,
        3,
        PlatformException(code: 'x'),
        MissingPluginException(),
      ]) {
        answer = (_) => reply;
        expect(
          await port().paste('t', post: true),
          PasteOutcome.failed,
          reason: '$reply',
        );
      }
    });
  });

  group('simple calls', () {
    test('openPicker, closePicker, showToast, hideToast, unregister', () async {
      final p = port();
      await p.openPicker();
      await p.closePicker();
      await p.showToast();
      await p.hideToast();
      await p.unregisterShortcut();
      expect(calls.map((c) => c.method), [
        'openPicker',
        'closePicker',
        'showToast',
        'hideToast',
        'unregisterShortcut',
      ]);
      expect(calls.every((c) => c.arguments == null), isTrue);
    });

    test('they never throw when the native side is missing or fails', () async {
      for (final reply in <Object?>[
        PlatformException(code: 'x'),
        MissingPluginException(),
      ]) {
        answer = (_) => reply;
        final p = port();
        await p.openPicker();
        await p.closePicker();
        await p.showToast();
        await p.hideToast();
        await p.unregisterShortcut();
      }
    });
  });

  group('permission snapshot', () {
    test('asks native and passes the number on', () async {
      answer = (_) => 5;
      expect(await port().permissionSnapshot(), 5);
      expect(calls.single.method, 'permissionSnapshot');
    });

    test('anything but a number, an error or no native side is null', () async {
      for (final reply in <Object?>[
        'x',
        null,
        PlatformException(code: 'x'),
        MissingPluginException(),
      ]) {
        answer = (_) => reply;
        expect(await port().permissionSnapshot(), isNull, reason: '$reply');
      }
    });
  });

  group('post access', () {
    test(
      'canPost asks without prompting; requestPostAccess asks the OS',
      () async {
        answer = (c) => c.method == 'canPost';
        expect(await port().canPost(), isTrue);
        answer = (c) => c.method == 'requestPostAccess';
        expect(await port().requestPostAccess(), isTrue);
        expect(calls.map((c) => c.method), ['canPost', 'requestPostAccess']);
      },
    );

    test('an error or a missing native side means "not allowed"', () async {
      for (final reply in <Object?>[
        PlatformException(code: 'x'),
        MissingPluginException(),
        null,
        'yes',
      ]) {
        answer = (_) => reply;
        expect(await port().canPost(), isFalse, reason: '$reply');
        expect(await port().requestPostAccess(), isFalse, reason: '$reply');
      }
    });
  });

  group('events from native', () {
    Future<void> send(String method, [Object? args]) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

    test('shortcutPressed and dismissed arrive as events', () async {
      final p = port();
      final got = <PickerNativeEvent>[];
      final sub = p.events.listen(got.add);
      await send('shortcutPressed');
      await send('dismissed');
      await sub.cancel();
      expect(got.length, 2);
      expect(got[0], isA<ShortcutPressed>());
      expect(got[1], isA<PickerDismissed>());
    });

    test('unknown methods are ignored', () async {
      final p = port();
      final got = <PickerNativeEvent>[];
      final sub = p.events.listen(got.add);
      await send('somethingElse');
      await sub.cancel();
      expect(got, isEmpty);
    });
  });
}
