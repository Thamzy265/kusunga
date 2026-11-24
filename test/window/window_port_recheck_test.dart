// M1.10c tester (re-check): the window port's new error paths, and a failing
// hide followed by a show.
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';

class _Window implements WindowHandle {
  final calls = <String>[];
  bool sizeFails = false;
  bool hideFails = false;
  bool disposeFails = false;

  @override
  void setMinimumSize(Size size) => calls.add('minimumSize');

  @override
  void setSize(Size size) {
    calls.add('size');
    if (sizeFails) throw StateError('SECRET native text');
  }

  @override
  void preventClose(void Function() onCloseRequested) =>
      calls.add('preventClose');

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
  void dispose() {
    calls.add('dispose');
    if (disposeFails) throw StateError('native dispose failed');
  }
}

class _Backend implements WindowBackend {
  int missing = 0;
  int throwing = 0;
  final window = _Window();

  @override
  WindowHandle? findWindow() {
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

List<String> _captureLogs() {
  final logs = <String>[];
  final old = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  addTearDown(() => debugPrint = old);
  return logs;
}

void main() {
  testWidgets('a hide whose lookup throws, then a show: the show works and '
      'nothing is stuck pending', (tester) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    backend.throwing = 1;

    await expectLater(port.hide(), throwsStateError);
    await port.show();

    expect(backend.window.calls, ['show', 'focus']);
    await port.dispose();
  });

  testWidgets('a hide that throws natively, then a show, then a hide: each '
      'call goes through and the show is not swallowed', (tester) async {
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    await port.init();
    backend.window.calls.clear();
    backend.window.hideFails = true;

    await expectLater(port.hide(), throwsStateError);
    backend.window.hideFails = false;
    await port.show();
    await port.hide();

    expect(backend.window.calls, ['hide', 'show', 'focus', 'hide']);
    await port.dispose();
  });

  testWidgets('a show pending while lookups keep throwing is carried out '
      'when a lookup works, and the logs carry no native error text', (
    tester,
  ) async {
    final logs = _captureLogs();
    final backend = _Backend();
    final port = WindowManagerPort(backend: backend);
    backend.missing = 1;
    await port.init();
    await port.show();
    backend.throwing = 3;

    await tester.pump(_every * 10);

    expect(backend.window.calls, [
      'minimumSize',
      'size',
      'preventClose',
      'show',
      'focus',
    ]);
    expect(logs.join(), isNot(contains('SECRET')));
    await port.dispose();
  });

  testWidgets('W3: a pending show is still carried out when the window found '
      'by a retry fails its set-up (the user asked to open it)', (
    tester,
  ) async {
    final logs = _captureLogs();
    final backend = _Backend()..missing = 1;
    backend.window.sizeFails = true;
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await port.show();

    await tester.pump(_every * 3);

    expect(logs.join(), isNot(contains('SECRET')));
    expect(backend.window.calls, containsAll(['show', 'focus']));
    await port.dispose();
  });

  testWidgets('a window set-up that throws leaves the close button still '
      'redirected to hide (preventClose is attempted)', (tester) async {
    _captureLogs();
    final backend = _Backend()..missing = 1;
    backend.window.sizeFails = true;
    final port = WindowManagerPort(backend: backend);
    await port.init();

    await tester.pump(_every * 3);

    expect(backend.window.calls, contains('preventClose'));
    await port.dispose();
  });

  testWidgets('a window whose release throws on dispose: the error reaches '
      'the caller once, the close stream is closed, and a second dispose '
      'is quiet', (tester) async {
    final backend = _Backend();
    backend.window.disposeFails = true;
    final port = WindowManagerPort(backend: backend);
    await port.init();
    var done = false;
    port.closeRequests.listen((_) {}, onDone: () => done = true);

    await expectLater(port.dispose(), throwsStateError);
    await tester.pump();
    await port.dispose();

    expect(done, isTrue);
    expect(backend.window.calls.where((c) => c == 'dispose'), hasLength(1));
  });

  testWidgets('dispose during the retries of a window whose set-up would '
      'throw leaves nothing pending', (tester) async {
    _captureLogs();
    final backend = _Backend()..missing = 5;
    backend.window.sizeFails = true;
    final port = WindowManagerPort(backend: backend);
    await port.init();
    await tester.pump(_every * 2);

    await port.dispose();
    await tester.pump(_every * 20);

    expect(backend.window.calls, isEmpty);
  });
}
