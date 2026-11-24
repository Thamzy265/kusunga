// M1.10c developer: the tray's "Open Kusunga" (WindowService.openFromTray).
// main.dart starts it with unawaited, so nothing awaits it: a show that
// throws on the new port (a lookup or a native show) must be logged with the
// error type only, not left as an uncaught async error with native text. The
// real WindowManagerPort runs on a fake backend, so no test calls the real
// plugin.
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';
import 'package:kusunga/window/window_service.dart';

/// Records every call into [calls], then throws if that step is in
/// [failing].
class _Window implements WindowHandle {
  _Window(this.calls);

  final List<String> calls;
  final failing = <String>{};

  void _call(String step) {
    calls.add(step);
    if (failing.contains(step)) throw StateError('SECRET native text');
  }

  @override
  void setMinimumSize(Size size) {}

  @override
  void setSize(Size size) {}

  @override
  void preventClose(void Function() onCloseRequested) {}

  @override
  void show() => _call('show');

  @override
  void focus() => _call('focus');

  @override
  void hide() => _call('hide');

  @override
  void dispose() {}
}

/// While [throwing] is above 0, a lookup throws.
class _Backend implements WindowBackend {
  _Backend(List<String> calls) : window = _Window(calls);

  int throwing = 0;
  final _Window window;

  @override
  WindowHandle? findWindow() {
    if (throwing > 0) {
      throwing--;
      throw StateError('SECRET native text');
    }
    return window;
  }
}

const _showFailed = 'Kusunga: window show failed (StateError)';

void main() {
  late List<String> calls;
  late List<String> logs;
  late _Backend backend;
  late WindowService service;

  Future<void> prepare() async => calls.add('prepare');

  setUp(() {
    calls = [];
    logs = [];
    final old = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = old);
    backend = _Backend(calls);
    service = WindowService(port: WindowManagerPort(backend: backend));
    addTearDown(service.dispose);
  });

  test('the picker or the toast is put away first, then the window is shown '
      'and focused', () async {
    await service.openFromTray(prepare);

    expect(calls, ['prepare', 'show', 'focus']);
    expect(logs, isEmpty);
  });

  test('a window lookup that throws is logged once with the error type '
      'only, and is not an error for the caller', () async {
    backend.throwing = 1;

    await service.openFromTray(prepare);

    expect(logs, [_showFailed]);
  });

  test('a native show that throws is logged once with the error type only, '
      'and the next Open Kusunga still shows the window', () async {
    backend.window.failing.add('show');
    await service.openFromTray(prepare);
    backend.window.failing.clear();

    await service.openFromTray(prepare);

    expect(logs, [_showFailed]);
    expect(calls, ['prepare', 'show', 'prepare', 'show', 'focus']);
  });

  test('a prepare that throws: the window is not shown (as before), and the '
      'failure is logged once with the error type only', () async {
    await service.openFromTray(
      () async => throw StateError('SECRET native text'),
    );

    expect(calls, isEmpty);
    expect(logs, [_showFailed]);
  });
}
