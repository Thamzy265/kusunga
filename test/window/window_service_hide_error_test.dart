// M1.10c developer: a close request hides the window from inside the close
// listener, where nothing awaits the hide. A native hide that throws must be
// logged, not left as an uncaught async error. The real WindowManagerPort
// runs on a fake backend, so no test calls the real plugin.
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';
import 'package:kusunga/window/window_service.dart';

class _Window implements WindowHandle {
  final calls = <String>[];
  bool hideFails = false;
  void Function()? onClose;

  @override
  void setMinimumSize(Size size) {}

  @override
  void setSize(Size size) {}

  @override
  void preventClose(void Function() onCloseRequested) =>
      onClose = onCloseRequested;

  @override
  void show() => calls.add('show');

  @override
  void focus() => calls.add('focus');

  @override
  void hide() {
    calls.add('hide');
    if (hideFails) throw StateError('native hide failed');
  }

  @override
  void dispose() {}
}

class _Backend implements WindowBackend {
  final window = _Window();

  @override
  WindowHandle? findWindow() => window;
}

void main() {
  test('a hide that throws on a close request is logged once with only the '
      'error type, is not an uncaught error, and the next close request '
      'still hides the window', () async {
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = old);
    final backend = _Backend();
    final service = WindowService(port: WindowManagerPort(backend: backend));
    addTearDown(service.dispose);
    await service.start();
    backend.window.hideFails = true;

    backend.window.onClose!();
    await pumpEventQueue();

    expect(logs, ['Kusunga: window hide failed (StateError)']);

    backend.window.hideFails = false;
    backend.window.onClose!();
    await pumpEventQueue();

    expect(backend.window.calls, ['hide', 'hide']);
    expect(logs, hasLength(1));
  });
}
