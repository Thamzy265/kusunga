// M1.10c: the window port on an injected backend (ADR 0009), so no test calls
// the real window_manager / nativeapi plugin. Covers the hidden Windows start,
// where the platform may not name the app's window yet (design note API-A).
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';

class _FakeWindow implements WindowHandle {
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

/// Answers [findWindow] with null [hiddenFor] times, then with [window].
class _FakeBackend implements WindowBackend {
  _FakeBackend({this.hiddenFor = 0});

  int hiddenFor;
  final window = _FakeWindow();
  var lookups = 0;

  @override
  WindowHandle? findWindow() {
    lookups++;
    if (hiddenFor > 0) {
      hiddenFor--;
      return null;
    }
    return window;
  }
}

const _tick = Duration(milliseconds: 1);

Future<void> _waitTicks(int n) =>
    Future<void>.delayed(Duration(milliseconds: n * 5));

void main() {
  test('init sets the minimum size, the size and close-to-hide', () async {
    final backend = _FakeBackend();
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    addTearDown(port.dispose);

    await port.init();

    final w = backend.window;
    expect(w.calls, ['minimumSize', 'size', 'preventClose']);
    expect(w.minimumSize, const Size(360, 400));
    expect(w.size, const Size(800, 632));
  });

  test('a close request is reported on closeRequests', () async {
    final backend = _FakeBackend();
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    addTearDown(port.dispose);
    await port.init();
    var closes = 0;
    final sub = port.closeRequests.listen((_) => closes++);

    backend.window.onClose!();
    await pumpEventQueue();

    expect(closes, 1);
    await sub.cancel();
  });

  test('show shows and focuses; hide hides', () async {
    final backend = _FakeBackend();
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    addTearDown(port.dispose);
    await port.init();
    backend.window.calls.clear();

    await port.show();
    await port.hide();

    expect(backend.window.calls, ['show', 'focus', 'hide']);
  });

  test('API-A: a window not found at init is found by a retry', () async {
    final backend = _FakeBackend(hiddenFor: 3);
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    addTearDown(port.dispose);

    await port.init();
    expect(backend.window.calls, isEmpty);

    await _waitTicks(20);

    expect(backend.window.calls, ['minimumSize', 'size', 'preventClose']);
    expect(backend.lookups, 4);
  });

  test('API-A: a show while the window is not found yet is done once it '
      'is found', () async {
    final backend = _FakeBackend(hiddenFor: 1000);
    final port = WindowManagerPort(
      backend: backend,
      retryEvery: const Duration(hours: 1),
    );
    addTearDown(port.dispose);
    await port.init();

    backend.hiddenFor = 1;
    await port.show();
    expect(backend.window.calls, isEmpty);

    // The tray's "Open Kusunga" again: this lookup finds the window.
    await port.show();

    expect(backend.window.calls, [
      'minimumSize',
      'size',
      'preventClose',
      'show',
      'focus',
    ]);
  });

  test('API-A: a pending show is carried out by the retry that finds the '
      'window', () async {
    final backend = _FakeBackend(hiddenFor: 2);
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    addTearDown(port.dispose);
    await port.init();
    await port.show();

    await _waitTicks(20);

    expect(backend.window.calls, [
      'minimumSize',
      'size',
      'preventClose',
      'show',
      'focus',
    ]);
  });

  test('API-A: a hide after a pending show cancels it', () async {
    final backend = _FakeBackend(hiddenFor: 3);
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    addTearDown(port.dispose);
    await port.init();
    await port.show();
    await port.hide();

    await _waitTicks(20);

    expect(backend.window.calls, ['minimumSize', 'size', 'preventClose']);
  });

  test('API-A: the retries stop after a bounded number of tries', () async {
    final backend = _FakeBackend(hiddenFor: 1 << 30);
    final port = WindowManagerPort(
      backend: backend,
      retryEvery: _tick,
      maxRetries: 5,
    );
    addTearDown(port.dispose);
    await port.init();

    await _waitTicks(40);

    expect(backend.lookups, 6);
  });

  test('the window is looked up once, then kept', () async {
    final backend = _FakeBackend();
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    addTearDown(port.dispose);
    await port.init();

    await port.show();
    await port.hide();
    await port.show();

    expect(backend.lookups, 1);
  });

  test('dispose stops the retries and releases the window', () async {
    final backend = _FakeBackend(hiddenFor: 1 << 30);
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    await port.init();
    await port.dispose();
    final after = backend.lookups;

    await _waitTicks(20);

    expect(backend.lookups, after);
  });

  test('dispose removes the close listener of a found window', () async {
    final backend = _FakeBackend();
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    await port.init();

    await port.dispose();

    expect(backend.window.calls.last, 'dispose');
  });

  test('a close request after dispose is dropped without an error', () async {
    final backend = _FakeBackend();
    final port = WindowManagerPort(backend: backend, retryEvery: _tick);
    await port.init();
    final onClose = backend.window.onClose!;
    await port.dispose();

    onClose();
  });
}
