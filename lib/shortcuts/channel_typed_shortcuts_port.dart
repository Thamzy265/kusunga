import 'dart:async';
import 'package:flutter/services.dart';

import 'typed_shortcuts_port.dart';

/// Talks to the native typed-shortcut watcher.
///
/// Method channel `com.wnasoni.kusunga/shortcuts`.
/// Dart to native:
///  - `setTable {entries: [{id, shortcut}]}`;
///  - `setIgnored {appIds: [..]}`;
///  - `setEnabled {on}` and `status` answer a status name;
///  - `replace {deleteCount, text}` answers `replaced`, `cancelled`,
///    `copied` or `failed` (`text` is the snippet Kusunga pastes);
///  - `runningApps` answers `[{appId, name, icon}]` (icon: PNG bytes or
///    null);
///  - `requestListenAccess` answers a bool; `openInputMonitoringSettings`.
/// Native to Dart: `matched {snippetId, deleteCount}` and
/// `statusChanged {status}`.
/// Nothing carries a typed character (ADR 0004; a source guard test checks
/// these names).
class ChannelTypedShortcutsPort implements TypedShortcutsPort {
  ChannelTypedShortcutsPort({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.wnasoni.kusunga/shortcuts') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _events = StreamController<TypedShortcutEvent>.broadcast(sync: true);

  @override
  Stream<TypedShortcutEvent> get events => _events.stream;

  Future<Object?> _onCall(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'matched':
        if (args is Map) {
          final id = args['snippetId'];
          final count = args['deleteCount'];
          if (id is int && count is int && count >= 1 && count <= 32) {
            _events.add(ShortcutMatched(id, count));
          }
        }
      case 'statusChanged':
        if (args is Map) {
          final status = _status(args['status']);
          if (status != null) _events.add(ShortcutStatusChanged(status));
        }
    }
    return null;
  }

  static TypedShortcutStatus? _status(Object? name) {
    for (final s in TypedShortcutStatus.values) {
      if (s.name == name) return s;
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
  Future<void> setTable(List<({int id, String shortcut})> entries) =>
      _invoke<void>('setTable', {
        'entries': [
          for (final e in entries) {'id': e.id, 'shortcut': e.shortcut},
        ],
      });

  @override
  Future<void> setIgnored(List<String> appIds) =>
      _invoke<void>('setIgnored', {'appIds': appIds});

  @override
  Future<TypedShortcutStatus> setEnabled(bool on) async =>
      _status(await _invoke<Object?>('setEnabled', {'on': on})) ??
      (on ? TypedShortcutStatus.failed : TypedShortcutStatus.off);

  @override
  Future<TypedShortcutStatus> status() async =>
      _status(await _invoke<Object?>('status')) ?? TypedShortcutStatus.off;

  @override
  Future<ReplaceOutcome> replace(int deleteCount, String text) async {
    final reply = await _invoke<Object?>('replace', {
      'deleteCount': deleteCount,
      'text': text,
    });
    return switch (reply) {
      'replaced' => ReplaceOutcome.replaced,
      'cancelled' => ReplaceOutcome.cancelled,
      'copied' => ReplaceOutcome.copied,
      _ => ReplaceOutcome.failed,
    };
  }

  @override
  Future<List<RunningApp>> runningApps() async {
    final reply = await _invoke<Object?>('runningApps');
    if (reply is! List) return const [];
    return [
      for (final a in reply)
        if (a is Map &&
            a['appId'] is String &&
            a['name'] is String &&
            (a['appId'] as String).isNotEmpty &&
            (a['name'] as String).isNotEmpty)
          RunningApp(
            appId: a['appId'] as String,
            name: a['name'] as String,
            icon: a['icon'] is Uint8List ? a['icon'] as Uint8List : null,
          ),
    ];
  }

  @override
  Future<bool> requestListenAccess() async =>
      await _invoke<Object?>('requestListenAccess') == true;

  @override
  Future<void> openInputMonitoringSettings() =>
      _invoke<void>('openInputMonitoringSettings');
}
