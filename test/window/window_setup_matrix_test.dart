// M1.10c tester (second re-check): the window set-up path with each step
// failing alone and together, reached by init, a retry, a show and a hide.
// Whatever fails, the other steps run, the show or hide that follows is
// done, nothing throws out of a retry, and every log line carries the error
// type or a count, never native text.
//
// A test that waits for the 1 ms retry runs in testWidgets: the retry timer
// then runs on the fake clock and ticks exactly as often as the time pumped
// says, whatever the machine's load or timer step (reviewer F1: a real 1 ms
// timer ticks far less often under load and on Windows). A WindowService
// disposed inside such a test is disposed in tester.runAsync: its dispose
// awaits a subscription cancel that resumes outside the fake clock. Tests
// that need no timer stay plain tests.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/window/window_manager_port.dart';
import 'package:kusunga/window/window_service.dart';

const _secret = 'SECRET native text /Users/someone';

class _Window implements WindowHandle {
  _Window(this.failing);

  final Set<String> failing;
  final calls = <String>[];
  void Function()? onClose;

  void _do(String step) {
    calls.add(step);
    if (failing.contains(step)) throw StateError(_secret);
  }

  @override
  void setMinimumSize(Size size) => _do('minimumSize');

  @override
  void setSize(Size size) => _do('size');

  @override
  void preventClose(void Function() onCloseRequested) {
    onClose = onCloseRequested;
    _do('preventClose');
  }

  @override
  void show() => _do('show');

  @override
  void focus() => _do('focus');

  @override
  void hide() => _do('hide');

  @override
  void dispose() {}
}

class _Backend implements WindowBackend {
  _Backend(Set<String> failing) : window = _Window(failing);

  final _Window window;
  int missing = 0;
  int throwing = 0;
  int lookups = 0;

  @override
  WindowHandle? findWindow() {
    lookups++;
    if (throwing > 0) {
      throwing--;
      throw StateError(_secret);
    }
    if (missing > 0) {
      missing--;
      return null;
    }
    return window;
  }
}

const _steps = ['minimumSize', 'size', 'preventClose'];

Iterable<Set<String>> _subsets() sync* {
  for (var mask = 0; mask < 8; mask++) {
    yield {
      for (var i = 0; i < 3; i++)
        if (mask & (1 << i) != 0) _steps[i],
    };
  }
}

/// 40 ms on the fake clock: 40 ticks of the 1 ms retry, exactly.
Future<void> _wait(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 40));

void main() {
  late List<String> logs;
  late DebugPrintCallback realDebugPrint;

  setUp(() {
    logs = [];
    realDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = realDebugPrint);
  });

  /// testWidgets (the fake clock), with the log capture undone before
  /// testWidgets checks that the test left debugPrint as it found it: the
  /// setUp's tear-down runs only after that check.
  void testOnFakeClock(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      addTearDown(() => debugPrint = realDebugPrint);
      await body(tester);
    });
  }

  WindowManagerPort portFor(_Backend b) {
    final port = WindowManagerPort(
      backend: b,
      retryEvery: const Duration(milliseconds: 1),
    );
    addTearDown(port.dispose);
    return port;
  }

  void expectClean(Set<String> failing) {
    expect(logs.join('\n'), isNot(contains('SECRET')));
    expect(logs.join('\n'), isNot(contains('/Users')));
    expect(
      logs.where((l) => l.contains('set-up failed')),
      hasLength(failing.length),
      reason: 'one log line per failing step',
    );
  }

  for (final failing in _subsets()) {
    final name = failing.isEmpty
        ? 'no step fails'
        : '${failing.join(' + ')} fail';

    test(
      'init, window known: $name: all three steps tried, none throws',
      () async {
        final b = _Backend(failing);
        await portFor(b).init();

        expect(b.window.calls, _steps);
        expectClean(failing);
      },
    );

    testOnFakeClock('retry finds it: $name: all steps tried, then the pending '
        'show is done', (tester) async {
      final b = _Backend(failing)..missing = 2;
      final port = portFor(b);
      await port.init();
      await port.show();

      await _wait(tester);

      expect(b.window.calls, [..._steps, 'show', 'focus']);
      expectClean(failing);
    });

    test('a show that finds the window: $name: set up, then shown', () async {
      final b = _Backend(failing)..missing = 1;
      final port = WindowManagerPort(
        backend: b,
        retryEvery: const Duration(hours: 1),
      );
      addTearDown(port.dispose);
      await port.init();

      await port.show();

      expect(b.window.calls, [..._steps, 'show', 'focus']);
      expectClean(failing);
    });

    test('a hide that finds the window: $name: set up, then hidden', () async {
      final b = _Backend(failing)..missing = 1;
      final port = WindowManagerPort(
        backend: b,
        retryEvery: const Duration(hours: 1),
      );
      addTearDown(port.dispose);
      await port.init();

      await port.hide();

      expect(b.window.calls, [..._steps, 'hide']);
      expectClean(failing);
    });
  }

  testOnFakeClock(
    'a failed set-up is not retried by the retry timer: the window '
    'is adopted once',
    (tester) async {
      final b = _Backend({'size'})..missing = 1;
      final port = portFor(b);
      await port.init();
      await _wait(tester);
      final lookups = b.lookups;

      await _wait(tester);

      expect(b.lookups, lookups);
      expect(b.window.calls.where((c) => c == 'preventClose'), hasLength(1));
    },
  );

  testOnFakeClock('init whose lookup throws reaches the caller, starts the '
      'retry, and the window is set up when a retry finds it', (tester) async {
    final b = _Backend(const {})..throwing = 1;
    final port = portFor(b);

    await expectLater(port.init(), throwsStateError);
    await _wait(tester);

    expect(b.window.calls, _steps);
    expect(logs.join(), isNot(contains('SECRET')));
  });

  testOnFakeClock('init whose lookup throws, then retry lookups throw too: '
      'bounded, one final log with counts only', (tester) async {
    final b = _Backend(const {})..throwing = 1 << 30;
    final port = WindowManagerPort(
      backend: b,
      retryEvery: const Duration(milliseconds: 1),
      maxRetries: 5,
    );
    addTearDown(port.dispose);

    await expectLater(port.init(), throwsStateError);
    await _wait(tester);

    expect(b.lookups, 6);
    expect(logs, hasLength(1));
    expect(logs.single, contains('5 failed'));
    expect(logs.single, isNot(contains('SECRET')));
  });

  testOnFakeClock(
    'init twice with a throwing lookup does not start two timers',
    (tester) async {
      final b = _Backend(const {})..throwing = 1 << 30;
      final port = WindowManagerPort(
        backend: b,
        retryEvery: const Duration(milliseconds: 1),
        maxRetries: 5,
      );
      addTearDown(port.dispose);
      await expectLater(port.init(), throwsStateError);
      await expectLater(port.init(), throwsStateError);
      await _wait(tester);

      expect(b.lookups, 2 + 5);
    },
  );

  testOnFakeClock(
    'a pending show that throws when the window is found at init: the '
    'error reaches the caller, no retry runs, and the next show works',
    (tester) async {
      final b = _Backend({'show'});
      final port = portFor(b);
      b.missing = 1;
      await port.show(); // pending
      b.missing = 0;

      await expectLater(port.init(), throwsStateError);
      final lookups = b.lookups;
      await _wait(tester);
      expect(b.lookups, lookups, reason: 'a retry ran for a known window');

      b.window.failing.clear();
      await port.show();
      expect(b.window.calls.last, 'focus');
    },
  );

  group('WindowService after a failed init (real port, fake backend)', () {
    testOnFakeClock(
      'close requests hide the window once a retry has set it up, '
      'and the start log has the error type only',
      (tester) async {
        final b = _Backend(const {})..throwing = 1;
        final port = portFor(b);
        final service = WindowService(port: port);
        addTearDown(service.dispose);

        await service.start();
        await _wait(tester);
        b.window.calls.clear();

        b.window.onClose!();
        await tester.pump();

        expect(b.window.calls, ['hide']);
        expect(logs.where((l) => l.contains('setup failed')), hasLength(1));
        expect(logs.join(), isNot(contains('SECRET')));
      },
    );

    testOnFakeClock('dispose right after a failed start leaves no listener and '
        'no timer behind', (tester) async {
      final b = _Backend(const {})..throwing = 1 << 30;
      final port = portFor(b);
      final service = WindowService(port: port);

      await service.start();
      await tester.runAsync(service.dispose);
      final lookups = b.lookups;
      await _wait(tester);

      expect(b.lookups, lookups);
      // And testWidgets fails a test that ends with a timer still pending.
    });
  });

  group('WindowService.openFromTray', () {
    late _Backend b;
    late WindowService service;

    setUp(() {
      b = _Backend(<String>{});
      service = WindowService(port: portFor(b));
      addTearDown(service.dispose);
    });

    test('prepare then show, in that order', () async {
      await service.openFromTray(() async {
        b.window.calls.add('prepared');
      });

      expect(b.window.calls, ['prepared', 'show', 'focus']);
    });

    test('a prepare that throws: no show, a log with the type only, and '
        'the next open works', () async {
      await service.openFromTray(() => throw StateError(_secret));
      expect(b.window.calls, isEmpty);
      expect(logs, hasLength(1));
      expect(logs.single, contains('StateError'));
      expect(logs.single, isNot(contains('SECRET')));

      await service.openFromTray(() async {});
      expect(b.window.calls, ['show', 'focus']);
    });

    test(
      'a prepare that fails asynchronously is logged the same way',
      () async {
        await service.openFromTray(() async {
          await Future<void>.delayed(Duration.zero);
          throw StateError(_secret);
        });

        expect(logs.single, isNot(contains('SECRET')));
        expect(b.window.calls, isEmpty);
      },
    );

    test('a show that throws: logged with the type only, and the next open '
        'works', () async {
      b.window.failing.add('show');
      await service.openFromTray(() async {});
      expect(logs, hasLength(1));
      expect(logs.single, isNot(contains('SECRET')));

      b.window.failing.clear();
      b.window.calls.clear();
      await service.openFromTray(() async {});
      expect(b.window.calls, ['show', 'focus']);
    });

    test('two opens at once show twice, without an error', () async {
      await Future.wait([
        service.openFromTray(() async {}),
        service.openFromTray(() async {}),
      ]);

      expect(b.window.calls.where((c) => c == 'show'), hasLength(2));
      expect(logs, isEmpty);
    });

    test('an open after dispose does not throw', () async {
      await service.dispose();

      await service.openFromTray(() async {});
    });
  });

  test('no debugPrint in the window and tray port files interpolates a '
      'caught error without runtimeType (native text stays out of logs)', () {
    final offenders = <String>[];
    for (final path in [
      'lib/window/window_manager_port.dart',
      'lib/window/window_service.dart',
      'lib/tray/tray_manager_port.dart',
    ]) {
      final text = File(path).readAsStringSync();
      for (final m in RegExp(r'debugPrint\(([\s\S]*?)\);').allMatches(text)) {
        final call = m.group(1)!;
        final bare = call.replaceAll(r'${error.runtimeType}', '');
        if (RegExp(r'\$\{?(error|e|exception)\b').hasMatch(bare)) {
          offenders.add('$path: ${call.trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
