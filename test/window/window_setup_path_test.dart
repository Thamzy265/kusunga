// M1.10c developer: the window set-up path when a native step throws (tester
// findings W3 and W4, and the same kind of bug on the other ways in: init
// finding the window at once, a show or hide finding it, and a retry). A step
// that fails must never stop what comes after it. The backend is a fake, so
// no test calls the real plugin. testWidgets on purpose: the clock is fake,
// and the binding fails a test that ends with a Timer pending.
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';

/// Records every call, then throws if that step is in [failing].
class _Window implements WindowHandle {
  final calls = <String>[];
  final failing = <String>{};
  void Function()? onClose;

  void _call(String step) {
    calls.add(step);
    if (failing.contains(step)) throw StateError('SECRET native text');
  }

  @override
  void setMinimumSize(Size size) => _call('minimumSize');

  @override
  void setSize(Size size) => _call('size');

  @override
  void preventClose(void Function() onCloseRequested) {
    _call('preventClose');
    onClose = onCloseRequested;
  }

  @override
  void show() => _call('show');

  @override
  void focus() => _call('focus');

  @override
  void hide() => _call('hide');

  @override
  void dispose() => _call('dispose');
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
      throw StateError('SECRET native text');
    }
    if (missing > 0) {
      missing--;
      return null;
    }
    return window;
  }
}

const _every = Duration(milliseconds: 250);
const _setUpFailed = 'Kusunga: window set-up failed (StateError)';

List<String> _captureLogs() {
  final logs = <String>[];
  final old = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  addTearDown(() => debugPrint = old);
  return logs;
}

void main() {
  group('W3: a set-up that throws never stops the show or hide after it', () {
    testWidgets('a show pending while the window is missing is carried out '
        'when a retry finds the window and its set-up throws', (tester) async {
      final logs = _captureLogs();
      final backend = _Backend()..missing = 2;
      backend.window.failing.add('size');
      final port = WindowManagerPort(backend: backend);
      await port.init(); // missing: the retry starts
      await port.show(); // still missing: the show waits

      await tester.pump(_every); // the first retry finds the window

      expect(tester.takeException(), isNull);
      expect(backend.window.calls, containsAllInOrder(['show', 'focus']));
      expect(backend.window.calls.where((c) => c == 'show'), hasLength(1));
      expect(logs, [_setUpFailed]);
      await tester.pump(_every * 5);
      expect(backend.lookups, 3, reason: 'the retry kept running');
      await port.dispose();
    });

    testWidgets('init that finds the window at once, with a show asked for '
        'before init, carries out the show when the set-up throws, and '
        'does not throw', (tester) async {
      final logs = _captureLogs();
      final backend = _Backend()..missing = 1;
      backend.window.failing.add('size');
      final port = WindowManagerPort(backend: backend);
      await port.show(); // missing: the show waits (no retry before init)

      await port.init(); // found at once

      expect(backend.window.calls, containsAllInOrder(['show', 'focus']));
      expect(logs, [_setUpFailed]);
      await port.dispose();
    });

    testWidgets('init that finds the window at once and whose set-up throws '
        'does not throw, logs the error type once, and a show then works', (
      tester,
    ) async {
      final logs = _captureLogs();
      final backend = _Backend();
      backend.window.failing.add('size');
      final port = WindowManagerPort(backend: backend);

      await port.init();
      backend.window.calls.clear();
      await port.show();

      expect(backend.window.calls, ['show', 'focus']);
      expect(logs, [_setUpFailed]);
      await port.dispose();
    });

    testWidgets('a hide that finds the window itself and whose set-up throws '
        'still hides it and does not throw', (tester) async {
      final logs = _captureLogs();
      final backend = _Backend()..missing = 1;
      backend.window.failing.add('size');
      final port = WindowManagerPort(backend: backend);
      await port.init(); // missing: the retry starts

      await port.hide(); // this lookup finds the window

      expect(backend.window.calls.last, 'hide');
      expect(logs, [_setUpFailed]);
      await port.dispose();
    });

    testWidgets('a pending show whose native show throws, when a retry finds '
        'the window, is logged as a failed show with the error type only, '
        'not as a failed set-up', (tester) async {
      final logs = _captureLogs();
      final backend = _Backend()..missing = 2;
      backend.window.failing.add('show');
      final port = WindowManagerPort(backend: backend);
      await port.init();
      await port.show();

      await tester.pump(_every);

      expect(tester.takeException(), isNull);
      expect(logs, ['Kusunga: window show failed (StateError)']);
      await port.dispose();
    });
  });
}
