import 'package:flutter/services.dart';

import 'clipboard_source.dart';

/// Talks to the native watcher in the Runner (Swift on Mac, C++ on Windows).
///
/// Event channel `com.wnasoni.kusunga/clipboard/events` sends maps:
/// `{type: text, text, own?}` (own: true when the copy carries Kusunga's own
/// marker, `com.wnasoni.kusunga.self`), `{type: concealed}`, `{type: tooLarge}`,
/// `{type: error, code}`. Listening starts the watcher; cancelling stops it.
/// Method channel `com.wnasoni.kusunga/clipboard`:
/// `accessBehavior` returns `allow`, `ask`, `deny` or `unsupported`.
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
      case 'error':
        final code = raw['code'];
        return ClipboardReadError(code is String ? code : 'unknown');
    }
    return null;
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
