// M1.10c reviewer F2: on Windows the runner, not nativeapi, sets the window's
// minimum size. nativeapi answers WM_GETMINMAXINFO itself, before the
// runner's window procedure sees it, so a minimum set through it would keep
// the picker and the toast from getting smaller than the history window (the
// runner lifts the minimum while they show). The port therefore leaves the
// minimum out on Windows and still sets it on the Mac. The backend is a fake,
// so no test calls the real plugin.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';

class _Window implements WindowHandle {
  final calls = <String>[];
  Size? minimumSize;

  @override
  void setMinimumSize(Size size) {
    calls.add('minimumSize');
    minimumSize = size;
  }

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

class _Backend implements WindowBackend {
  final window = _Window();
  var missing = 0;

  @override
  WindowHandle? findWindow() {
    if (missing > 0) {
      missing--;
      return null;
    }
    return window;
  }
}

void main() {
  void runOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  WindowManagerPort portFor(_Backend backend) {
    final port = WindowManagerPort(
      backend: backend,
      retryEvery: const Duration(hours: 1),
    );
    addTearDown(port.dispose);
    return port;
  }

  test('on Windows, init leaves the minimum size to the runner and still '
      'sets the size and close-to-hide', () async {
    runOn(TargetPlatform.windows);
    final backend = _Backend();

    await portFor(backend).init();

    expect(backend.window.calls, ['size', 'preventClose']);
    expect(backend.window.minimumSize, isNull);
  });

  test('on Windows, a window that a show finds is set up without the '
      'minimum size too', () async {
    runOn(TargetPlatform.windows);
    final backend = _Backend()..missing = 1;
    final port = portFor(backend);
    await port.init(); // missing

    await port.show();

    expect(backend.window.calls, ['size', 'preventClose', 'show', 'focus']);
  });

  test(
    'on the Mac, init still sets the 360 x 400 minimum size first',
    () async {
      runOn(TargetPlatform.macOS);
      final backend = _Backend();

      await portFor(backend).init();

      expect(backend.window.calls, ['minimumSize', 'size', 'preventClose']);
      expect(backend.window.minimumSize, const Size(360, 400));
    },
  );

  test('the runner sets the same 360 x 400 minimum on Windows, in its own '
      'WM_GETMINMAXINFO handling', () {
    final policy = File('windows/runner/picker_policy.h').readAsStringSync();
    expect(policy, contains('constexpr double kHistoryMinWidth = 360;'));
    expect(policy, contains('constexpr double kHistoryMinHeight = 400;'));
    final bridge = File('windows/runner/picker_bridge.cpp').readAsStringSync();
    final start = bridge.indexOf('case WM_GETMINMAXINFO:');
    expect(start, isNot(-1));
    final handling = bridge.substring(
      start,
      bridge.indexOf('case ', start + 5),
    );
    expect(handling, contains('MinTrackSize('));
    expect(handling, contains('ptMinTrackSize'));
  });
}
