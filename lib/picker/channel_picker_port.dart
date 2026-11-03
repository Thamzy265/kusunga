import 'dart:async';

import 'package:flutter/services.dart';

import 'picker_port.dart';
import 'shortcut.dart';

/// Talks to the native picker code (Swift on Mac, C++ on Windows).
///
/// Method channel `com.wnasoni.kusunga/picker`.
/// Dart to native:
///  - `registerShortcut {key, modifiers}` answers `ok`, `taken` or `invalid`;
///    `key` is `a`..`z`, `0`..`9`, `f1`..`f12` or `space`; `modifiers` are
///    `ctrl`, `alt`, `shift`, `meta`;
///  - `unregisterShortcut`, `openPicker`, `closePicker`, `showToast`,
///    `hideToast`;
///  - `paste {text, post}` answers `pasted`, `noPermission`, `focusTimeout`,
///    `targetGone`, `targetElevated`, `copyOnly` or `failed`;
///  - `canPost` and `requestPostAccess` answer a bool.
/// Native to Dart: `shortcutPressed` (native shows the picker
/// when Dart has answered) and `dismissed`.
class ChannelPickerPort implements PickerPort {
  ChannelPickerPort({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.wnasoni.kusunga/picker') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _events = StreamController<PickerNativeEvent>.broadcast(sync: true);

  @override
  Stream<PickerNativeEvent> get events => _events.stream;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'shortcutPressed':
        _events.add(const ShortcutPressed());
      case 'dismissed':
        _events.add(const PickerDismissed());
    }
    return null;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<ShortcutRegistration> registerShortcut(PickerShortcut shortcut) async {
    final reply = await _invoke<Object?>('registerShortcut', {
      'key': shortcut.key,
      'modifiers': [
        for (final m in ShortcutModifier.values)
          if (shortcut.modifiers.contains(m)) m.name,
      ],
    });
    return switch (reply) {
      'ok' => ShortcutRegistration.registered,
      'taken' => ShortcutRegistration.taken,
      _ => ShortcutRegistration.failed,
    };
  }

  @override
  Future<void> unregisterShortcut() => _invoke<void>('unregisterShortcut');

  @override
  Future<void> openPicker() => _invoke<void>('openPicker');

  @override
  Future<void> closePicker() => _invoke<void>('closePicker');

  @override
  Future<PasteOutcome> paste(String text, {required bool post}) async {
    final reply = await _invoke<Object?>('paste', {'text': text, 'post': post});
    return switch (reply) {
      'pasted' => PasteOutcome.pasted,
      'noPermission' => PasteOutcome.noPermission,
      'focusTimeout' => PasteOutcome.focusTimeout,
      'targetGone' => PasteOutcome.targetGone,
      'targetElevated' => PasteOutcome.targetElevated,
      'copyOnly' => PasteOutcome.copyOnly,
      _ => PasteOutcome.failed,
    };
  }

  @override
  Future<void> showToast() => _invoke<void>('showToast');

  @override
  Future<void> hideToast() => _invoke<void>('hideToast');

  @override
  Future<bool> canPost() async => await _invoke<Object?>('canPost') == true;

  @override
  Future<bool> requestPostAccess() async =>
      await _invoke<Object?>('requestPostAccess') == true;
}
