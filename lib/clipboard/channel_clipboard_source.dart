import 'package:flutter/services.dart';

import 'clipboard_source.dart';

/// Talks to the native watcher in the Runner (Swift on Mac, C++ on Windows).
///
/// Event channel `com.wnasoni.kusunga/clipboard/events` sends maps:
/// `{type: text, text, own?}` (own: true when the copy carries Kusunga's own
/// marker, `com.wnasoni.kusunga.self`), `{type: concealed}`, `{type: tooLarge}`,
/// `{type: error, code}`, and (M1.6) `{type: ignoredApp}` and, on Windows,
/// `{type: sourceUnknown}`, which carry nothing else: the source app never
/// crosses the channel (ADR 0005). Listening starts the watcher; cancelling
/// stops it.
/// Method channel `com.wnasoni.kusunga/clipboard`:
/// `accessBehavior` returns `allow`, `ask`, `deny` or `unsupported`;
/// `writeOwn {text}` writes the text, remembers the change number it made so
/// the watcher skips that one change, and returns a bool;
/// `setCapturePause {until}` and `setCaptureIgnored {appIds}` (M1.6) set
/// what the watcher checks before reading a copy, and return a bool.
class ChannelClipboardSource implements ClipboardSource {
  ChannelClipboardSource({EventChannel? events, MethodChannel? methods})
    : _events =
          events ?? const EventChannel('com.wnasoni.kusunga/clipboard/events'),
      _methods =
          methods ?? const MethodChannel('com.wnasoni.kusunga/clipboard');

  final EventChannel _events;
  final MethodChannel _methods;

  @override
  Stream<ClipboardEvent> get events => _events
      .receiveBroadcastStream()
      .map(_decode)
      .where((e) => e != null)
      .cast<ClipboardEvent>();

  static ClipboardEvent? _decode(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'text':
        final text = raw['text'];
        return text is String
            ? ClipboardText(text, ownMarker: raw['own'] == true)
            : null;
      case 'concealed':
        return const ClipboardSkipped(SkipReason.concealed);
      case 'tooLarge':
        return const ClipboardSkipped(SkipReason.tooLarge);
      case 'ignoredApp':
        return const ClipboardSkipped(SkipReason.ignoredApp);
      case 'sourceUnknown':
        return const ClipboardSourceUnknown();
      case 'error':
        final code = raw['code'];
        return ClipboardReadError(code is String ? code : 'unknown');
    }
    return null;
  }

  @override
  Future<bool> writeOwn(String text) async {
    try {
      return await _methods.invokeMethod<Object?>('writeOwn', {'text': text}) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> setCapturePause(int until) =>
      _call('setCapturePause', {'until': until});

  @override
  Future<bool> setCaptureIgnored(List<String> appIds) =>
      _call('setCaptureIgnored', {'appIds': appIds});

  Future<bool> _call(String method, Map<String, Object> args) async {
    try {
      return await _methods.invokeMethod<Object?>(method, args) == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<PasteAccess> pasteAccess() async {
    try {
      final state = await _methods.invokeMethod<String>('accessBehavior');
      return switch (state) {
        'allow' => PasteAccess.allowed,
        'ask' || 'deny' => PasteAccess.needsSetup,
        _ => PasteAccess.notApplicable,
      };
    } on MissingPluginException {
      return PasteAccess.notApplicable;
    } on PlatformException {
      return PasteAccess.notApplicable;
    }
  }
}
