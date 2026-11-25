// M1.10c tester: ways to break the window port's hidden-start retry (design
// note API-A) on an injected backend, so no test calls the real plugin.
//
// These run in testWidgets on purpose: the clock is fake, so a retry every
// 250 ms for 120 tries takes no time, and the binding fails a test that ends
// with a Timer still pending, which is how "no timer left" is checked.
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';

class _Window implements WindowHandle {
  final calls = <String>[];
  Size? minimumSize;
  Size? size;
  void Function()? onClose;

  @override
  void setMinimumSize(Size value) {
    calls.add('minimumSize');
    minimumSize = value;
  }

  @override
  void setSize(Size value) {
    calls.add('size');
    size = value;
  }

  @override
  void preventClose(void Function() onCloseRequested) {
    calls.add('preventClose');
    onClose = onCloseRequested;
  }

  @override
  void show() => calls.add('show');

  @override
  void focus() => calls.add('focus');

  @override
  void hide() => calls.add('hide');

  @override
  void dispose() => calls.add('dispose');
}

/// The first [missing] lookups answer null; [throwing] lookups throw.
class _Backend implements WindowBackend {
  _Backend({this.missing = 0});

  int missing;
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
const _setUp = ['minimumSize', 'size', 'preventClose'];

/// Collects what the port prints. Installed inside each test, after the test
/// binding has set its own debugPrint, and put back by a tear-down.
List<String> _captureLogs() {
  final logs = <String>[];
  final old = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  addTearDown(() => debugPrint = old);
  return logs;
}

void main() {
  testWidgets('never found: exactly 120 retries at 250 ms, one log line, '
      'and no timer left', (tester) async {
    final logs = _captureLogs();
    final backend = _Backend(missing: 1 << 30);
    final port = WindowManagerPort(backend: backend);
    await port.init();
    expect(backend.lookups, 1);

    await tester.pump(_every * 119);
    expect(backend.lookups, 120);
    expect(logs, isEmpty, reason: 'logged before the last retry');

    await tester.pump(_every);
    expect(backend.lookups, 121);
    expect(logs, ['Kusunga: window not found; retried 120 times']);

    await tester.pump(_every * 50);
    expect(backend.lookups, 121, reason: 'the retry kept running');
    expect(logs, hasLength(1));
    await port.dispose();
  });

  testWidgets('found on the very last retry: no log line, no timer left, '
      'set up once', (tester) async {
    final logs = _captureLogs();
    // The init lookup and 119 retries miss; the 120th retry finds it.
    final backend = _Backend(missing: 120);
    final port = WindowManagerPort(backend: backend);
    await port.init();

    await tester.pump(_every * 120);

    expect(backend.lookups, 121);
    expect(backend.window.calls, _setUp);
    expect(logs, isEmpty);
    await tester.pump(_every * 10);
    expect(backend.lookups, 121);
    await port.dispose();
  });

  testWidgets('found on the first retry: the timer stops at once', (
    tester,
  ) async {
    final backend = _Backend(missing: 1);
    final port = WindowManagerPort(backend: backend);
    await port.init();

    await tester.pump(_every);
    await tester.pump(_every * 5);

    expect(backend.lookups, 2);
    expect(backend.window.calls, _setUp);
    await port.dispose();
  });

  testWidgets('retries are short-lived but a show after they gave up still '
      'finds a window that appeared late, and sets it up', (tester) async {
    final logs = _captureLogs();
    final backend = _Backend(missing: 1 << 30);
    final port = WindowManagerPort(backend: backend, maxRetries: 3);
    await port.init();
    await tester.pump(_every * 3);
    expect(logs, hasLength(1));

    backend.missing = 0;
    await port.show();

    expect(backend.window.calls, [..._setUp, 'show', 'focus']);
    await port.dispose();
  });

  testWidgets('init called twice while the window is missing starts one '
      'timer, not two', (tester) async {
    final logs = _captureLogs();
    final backend = _Backend(missing: 1 << 30);
    final port = WindowManagerPort(backend: backend, maxRetries: 4);
    await port.init();
    await port.init();
    final afterInits = backend.lookups;

    await tester.pump(_every);

    expect(backend.lookups, afterInits + 1);
    await tester.pump(_every * 10);
    expect(logs, hasLength(1));
    await port.dispose();
  });

  testWidgets('show, hide, show while missing: the last word wins, and the '
      'window is shown once when found', (tester) async {
    final backend = _Backend(missing: 3);
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.show();
    await port.hide();
    await port.show();

    await tester.pump(_every * 10);

    expect(backend.window.calls, [..._setUp, 'show', 'focus']);
    await port.dispose();
  });

  testWidgets('show asked twice while missing is carried out once', (
    tester,
  ) async {
    final backend = _Backend(missing: 3);
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.show();
    await port.show();

    await tester.pump(_every * 10);

    expect(backend.window.calls.where((c) => c == 'show'), hasLength(1));
    await port.dispose();
  });

  testWidgets('hide while missing and then found: the window is set up and '
      'not shown', (tester) async {
    final backend = _Backend(missing: 2);
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.hide();

    await tester.pump(_every * 10);

    expect(backend.window.calls, _setUp);
    await port.dispose();
  });

  testWidgets('a show before init, with the window missing, is done when it '
      'is found, and init later sets it up once', (tester) async {
    final backend = _Backend(missing: 1);
    final port = WindowManagerPort(backend: backend);
    await port.show(); // missing: pending, and no retry timer without init
    await port.show(); // found now

    expect(backend.window.calls, ['show', 'focus']);
    await port.init();

    expect(backend.window.calls, ['show', 'focus', ..._setUp]);
    await port.dispose();
  });

  testWidgets('dispose in the middle of the retries: no more lookups, no '
      'log line, no timer, and a pending show never fires', (tester) async {
    final logs = _captureLogs();
    final backend = _Backend(missing: 1 << 30);
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.show();
    await tester.pump(_every * 10);
    final before = backend.lookups;

    await port.dispose();
    backend.missing = 0;
    await tester.pump(_every * 200);

    expect(backend.lookups, before);
    expect(logs, isEmpty);
    expect(backend.window.calls, isEmpty);
  });

  testWidgets('dispose twice, and show, hide and init after dispose, do not '
      'throw and do not touch the window', (tester) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.dispose();
    backend.window.calls.clear();

    await port.dispose();
    await port.show();
    await port.hide();

    expect(backend.window.calls, isEmpty);
  });

  testWidgets('init after dispose leaves no retry timer behind', (
    tester,
  ) async {
    final backend = _Backend(missing: 1 << 30);
    final port = WindowManagerPort(backend: backend, maxRetries: 1000000);
    await port.dispose();

    await port.init();

    // The binding fails the test at its end if a Timer is still pending.
    expect(backend.lookups, 0);
  });

  testWidgets('the close stream of a disposed port ends without an error', (
    tester,
  ) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.dispose();

    var done = false;
    port.closeRequests.listen(
      (_) => fail('event after dispose'),
      onDone: () => done = true,
    );
    await tester.pump();

    expect(done, isTrue);
  });

  testWidgets('every close request is reported, none is lost, and the '
      'window is never closed by the port', (tester) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    await port.init();
    var closes = 0;
    port.closeRequests.listen((_) => closes++);

    backend.window.onClose!();
    backend.window.onClose!();
    backend.window.onClose!();
    await tester.pump();

    expect(closes, 3);
    expect(backend.window.calls, _setUp);
    await port.dispose();
  });

  testWidgets('the size values are exactly 360x400 minimum and 800x632 '
      'initial, minimum set before the size', (tester) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);

    await port.init();

    expect(backend.window.minimumSize, const Size(360, 400));
    expect(backend.window.size, const Size(800, 632));
    expect(backend.window.calls.indexOf('minimumSize'), lessThan(1));
    await port.dispose();
  });

  testWidgets('focus follows show, once per show, and never follows hide', (
    tester,
  ) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    await port.init();
    backend.window.calls.clear();

    await port.show();
    await port.hide();
    await port.show();

    expect(backend.window.calls, ['show', 'focus', 'hide', 'show', 'focus']);
    await port.dispose();
  });

  testWidgets('a lookup that throws in a retry is not an uncaught error: '
      'the retries go on and the window is found', (tester) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    backend.missing = 1;
    await port.init();
    backend.throwing = 2;

    await tester.pump(_every * 5);

    expect(
      tester.takeException(),
      isNull,
      reason: 'a throwing lookup escaped the retry timer',
    );
    expect(backend.window.calls, _setUp);
    await port.dispose();
  });

  testWidgets('a lookup that throws in init reaches the caller, and a later '
      'show still gets the window once the lookup works', (tester) async {
    final backend = _Backend()..throwing = 1;
    final port = WindowManagerPort(backend: backend);

    await expectLater(port.init(), throwsStateError);
    await port.show();

    expect(backend.window.calls, contains('show'));
    await port.dispose();
  });

  testWidgets('a lookup that throws in show reaches the caller and the '
      'show is not lost', (tester) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    backend.throwing = 1;

    await expectLater(port.show(), throwsStateError);
    await port.show();

    expect(backend.window.calls, ['show', 'focus']);
    await port.dispose();
  });
}
