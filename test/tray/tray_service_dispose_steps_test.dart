// M1.10c tester (re-check): TrayService disposed during EACH await of its
// start and of a pause update. After the destroy, no icon, tooltip or menu
// call may reach the native tray (it would make the icon again), and every
// menu that was built must be freed. The real port runs on the fake backend.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

import '../support/fakes.dart';
import 'fake_tray_backend.dart';

/// The real port with a gate held open after one step.
class _StepGatePort implements TrayPort {
  _StepGatePort(this.inner);

  final TrayManagerPort inner;
  String? gateAfter;
  Completer<void>? gate;
  Completer<void>? reached;

  Future<void> _hold(String step) async {
    if (step != gateAfter) return;
    reached?.complete();
    await gate?.future;
  }

  @override
  Stream<String> get menuItemClicks => inner.menuItemClicks;

  @override
  Future<void> setIcon(String path) async {
    await inner.setIcon(path);
    await _hold('setIcon');
  }

  @override
  Future<void> setToolTip(String text) async {
    await inner.setToolTip(text);
    await _hold('setToolTip');
  }

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async {
    await inner.setMenu(entries);
    await _hold('setMenu');
  }

  @override
  Future<void> destroy() => inner.destroy();

  @override
  Future<void> dispose() => inner.dispose();
}

const _nativeSteps = {'setIcon', 'setTooltip', 'setContextMenu'};

void main() {
  late FakeTrayBackend backend;
  late _StepGatePort port;
  late TrayService tray;
  late PauseService pause;

  setUp(() {
    backend = FakeTrayBackend();
    port = _StepGatePort(TrayManagerPort(backend: backend));
    pause = PauseService(
      setNativePause: (_) async => true,
      readSetting: (_) => null,
      writeSetting: (_, _) => true,
      log: FakeLog(),
      persists: true,
      clock: () => DateTime(2026, 11, 24, 12).millisecondsSinceEpoch,
    )..load();
    addTearDown(pause.dispose);
    tray = TrayService(
      port: port,
      iconPath: 'icon.png',
      pausedIconPath: 'icon_paused.png',
      use24Hour: () => true,
      onOpenPicker: () {},
      onOpen: () {},
      onQuit: () {},
    )..attachPause(pause);
  });

  /// Holds [step], runs [trigger] to reach it, disposes, lets the held step
  /// finish, and checks nothing native happened after the first destroy and
  /// that no menu was left alive.
  Future<void> disposeAt(String step, Future<void> Function() trigger) async {
    port
      ..gateAfter = step
      ..gate = Completer<void>()
      ..reached = Completer<void>();
    final running = trigger();
    await port.reached!.future;
    final disposing = tray.dispose();
    await pumpEventQueue();
    port.gate!.complete();
    await running;
    await disposing;
    await pumpEventQueue();

    final first = backend.calls.indexOf('destroy');
    expect(first, isNonNegative, reason: 'the tray was never destroyed');
    final after = backend.calls.sublist(first + 1);
    expect(
      after.where(_nativeSteps.contains),
      isEmpty,
      reason: 'native work after destroy: $after',
    );
    for (final m in backend.menus) {
      expect(m.disposed, isTrue, reason: 'a menu was never freed');
    }
  }

  for (final step in ['setIcon', 'setToolTip', 'setMenu']) {
    test('dispose while start waits after $step', () async {
      await disposeAt(step, tray.start);
    });
  }

  for (final step in ['setIcon', 'setToolTip', 'setMenu']) {
    test('dispose while a pause update waits after $step', () async {
      await tray.start();
      await pumpEventQueue();
      await disposeAt(step, () => pause.pause(PauseLength.quarterHour));
    });
  }

  test('dispose twice around an update in flight does not throw and '
      'destroys the icon', () async {
    await tray.start();
    await pumpEventQueue();
    port
      ..gateAfter = 'setIcon'
      ..gate = Completer<void>()
      ..reached = Completer<void>();
    final running = pause.pause(PauseLength.quarterHour);
    await port.reached!.future;

    final a = tray.dispose();
    final b = tray.dispose();
    port.gate!.complete();
    await Future.wait([running, a, b]);

    expect(backend.calls, contains('destroy'));
  });
}
