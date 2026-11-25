// M1.10c reviewer F3: on Windows the app's window is the runner's, picked by
// its window class from this process's top-level windows, hidden ones
// included. The runner shows its window only after the first frame (and,
// after a login start, only on "Open Kusunga"), and while it is hidden
// nativeapi's getCurrent() can return another hidden window of the process,
// such as Windows' "Default IME". The pick is a pure function, so it is
// tested here without Windows; the backend below uses it as the real one
// does, so no test calls the real plugin.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';

// Top-level windows of the process, as EnumWindows lists them.
const _ime = (handle: 0x1001, className: 'IME'); // "Default IME"
const _imeUi = (handle: 0x1002, className: 'MSCTFIME UI');
const _runner = (handle: 0x2001, className: 'FLUTTER_RUNNER_WIN32_WINDOW');

class _Window implements WindowHandle {
  _Window(this.handle);

  final int handle;
  final calls = <String>[];

  @override
  void setMinimumSize(Size size) => calls.add('minimumSize');

  @override
  void setSize(Size size) => calls.add('size');

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
  void dispose() {}
}

/// Like the real Windows backend: picks from [windows] (the z-order now) and
/// wraps the handle it picked.
class _ZOrderBackend implements WindowBackend {
  List<TopLevelWindow> windows = [];
  final wrapped = <int, _Window>{};
  var lookups = 0;

  @override
  WindowHandle? findWindow() {
    lookups++;
    final handle = pickRunnerWindow(windows);
    return handle == null
        ? null
        : wrapped.putIfAbsent(handle, () => _Window(handle));
  }
}

void main() {
  test('"Default IME" first in the z-order is not picked: the runner '
      'window is', () {
    expect(pickRunnerWindow([_ime, _imeUi, _runner]), _runner.handle);
  });

  test('the runner window is picked when it is the only one', () {
    expect(pickRunnerWindow([_runner]), _runner.handle);
  });

  test('without a runner window there is no pick, so the port looks again', () {
    expect(pickRunnerWindow([_ime, _imeUi]), isNull);
    expect(pickRunnerWindow(const []), isNull);
  });

  test('a class that only looks like the runner\'s is not picked', () {
    expect(
      pickRunnerWindow(const [
        (handle: 1, className: 'FLUTTER_RUNNER_WIN32_WINDOW_2'),
        (handle: 2, className: 'FLUTTERVIEW'),
        (handle: 3, className: 'FLUTTER_RUNNER'),
        (handle: 4, className: ''),
      ]),
      isNull,
    );
  });

  test('the class is the one the Windows runner registers its window with', () {
    final runner = File('windows/runner/win32_window.cpp').readAsStringSync();
    expect(runner, contains('kWindowClassName[] = L"$runnerWindowClass";'));
  });

  testWidgets('the port sets up and shows the runner window, never the IME '
      'window, and keeps looking while there is no runner window', (
    tester,
  ) async {
    final backend = _ZOrderBackend()..windows = [_ime, _imeUi];
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.show(); // pending until the window is found

    await tester.pump(const Duration(milliseconds: 250)); // a retry: none yet
    expect(backend.lookups, 3);
    expect(backend.wrapped, isEmpty);

    backend.windows = [_ime, _imeUi, _runner];
    await tester.pump(const Duration(milliseconds: 250)); // found

    expect(backend.wrapped.keys, [_runner.handle]);
    expect(backend.wrapped[_runner.handle]!.calls, [
      'minimumSize',
      'size',
      'preventClose',
      'show',
      'focus',
    ]);
    await port.dispose();
  });
}
