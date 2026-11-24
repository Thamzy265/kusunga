// M1.10c developer: errors on the window port's error paths (tester findings
// W1 and W2, and the same kind of bug elsewhere in the port). The backend is
// a fake, so no test calls the real plugin. testWidgets on purpose: the clock
// is fake, and the binding fails a test that ends with a Timer pending.
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';

class _Window implements WindowHandle {
  final calls = <String>[];
  bool setUpFails = false;
  bool disposeFails = false;

  @override
  void setMinimumSize(Size value) {
    if (setUpFails) throw StateError('native set-up failed');
    calls.add('minimumSize');
  }

  @override
  void setSize(Size value) => calls.add('size');

  @override
  void preventClose(void Function() onCloseRequested) =>
      calls.add('preventClose');

  @override
  void show() => calls.add('show');

  @override
  void focus() => calls.add('focus');

  @override
  void hide() => calls.add('hide');

  @override
  void dispose() {
    calls.add('dispose');
    if (disposeFails) throw StateError('native dispose failed');
  }
}

/// The first [missing] lookups answer null; while [throwing] is above 0, a
/// lookup throws.
class _Backend implements WindowBackend {
  int missing = 0;
  int throwing = 0;
  final window = _Window();
  var lookups = 0;

  @override
  WindowHandle? findWindow() {
    lookups++;
    if (throwing > 0) {
      throwing--;
      throw StateError('native lookup failed');
    }
    if (missing > 0) {
      missing--;
      return null;
    }
    return window;
  }
}

const _every = Duration(milliseconds: 250);

List<String> _captureLogs() {
  final logs = <String>[];
  final old = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  addTearDown(() => debugPrint = old);
  return logs;
}

void main() {
  testWidgets('W1: lookups that throw on every retry are counted as misses: '
      'the retries reach their bound, one log line says how many failed, and '
      'no timer is left', (tester) async {
    final logs = _captureLogs();
    final backend = _Backend()..missing = 1;
    final port = WindowManagerPort(backend: backend, maxRetries: 3);
    await port.init();
    backend.throwing = 1 << 30;

    await tester.pump(_every * 10);

    expect(tester.takeException(), isNull);
    expect(backend.lookups, 4);
    expect(logs, ['Kusunga: window not found; retried 3 times; 3 failed']);
    await port.dispose();
  });

  testWidgets('a window found on a retry whose set-up throws is not an '
      'uncaught error: it is logged once, no timer is left, and a later init '
      'sets it up', (tester) async {
    final logs = _captureLogs();
    final backend = _Backend()..missing = 1;
    final port = WindowManagerPort(backend: backend);
    await port.init();
    backend.window.setUpFails = true;

    await tester.pump(_every * 5);

    expect(
      tester.takeException(),
      isNull,
      reason: 'a throwing set-up escaped the retry timer',
    );
    expect(backend.lookups, 2, reason: 'the retry stopped once found');
    expect(logs, ['Kusunga: window set-up failed (StateError)']);

    backend.window.setUpFails = false;
    await port.init();
    expect(backend.window.calls, ['minimumSize', 'size', 'preventClose']);
    await port.dispose();
  });
}
