import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';

import '../support/fakes.dart';
import 'fake_picker_port.dart';

/// Edge cases for the permission snapshot taken before a paste (6e24bed) and
/// for the forced-post outcome.
class _SnapshotPort extends FakePickerPort {
  Completer<int?>? gate;
  Object? throwOnSnapshot;

  @override
  Future<int?> permissionSnapshot() async {
    calls.add('snapshot');
    if (throwOnSnapshot != null) throw throwOnSnapshot!;
    final g = gate;
    if (g != null) return g.future;
    return snapshotAnswer;
  }
}

void main() {
  late _SnapshotPort port;
  late FakeLog log;
  late FakeClipboardSource source;
  late HistoryService history;
  PickerController? built;

  void ctest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      built = null;
      await body(tester);
      built?.dispose();
    });
  }

  PickerController build() => built = PickerController(
    port: port,
    log: log,
    isMac: true,
    toastDuration: const Duration(seconds: 4),
  );

  setUp(() {
    port = _SnapshotPort();
    log = FakeLog();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
    )..start();
    addTearDown(history.dispose);
  });

  int saveText(String t) {
    source.copy(t);
    return history.items.first.id;
  }

  Future<PickerController> open() async {
    final c = build();
    await c.start();
    await c.attach(history);
    port.press();
    return c;
  }

  ctest('a second Enter while the paste is in flight pastes only once', (
    tester,
  ) async {
    final id = saveText('a');
    final c = await open();
    port.pasteGate = Completer<void>();
    final first = c.pasteItem(id);
    final second = c.pasteItem(id);
    port.pasteGate!.complete();
    await first;
    await second;
    expect(port.pastes.length, 1);
  });

  ctest('a paste asks native for nothing first: the paste-time permission '
      'state is logged natively (F6), so there is no extra round trip', (
    tester,
  ) async {
    final id = saveText('top secret words');
    port.snapshotAnswer = 7;
    final c = await open();
    port.calls.clear();
    log.codes.clear();
    await c.pasteItem(id);
    expect(port.calls.first, 'paste');
    expect(port.calls, isNot(contains('snapshot')));
    expect(log.codes, [LogCode.pasteSource]);
  });

  // REPRO (low severity): the real port swallows PlatformException and
  // MissingPluginException, but any other error from permissionSnapshot escapes
  // pasteItem after _pasting was set to true and before it is cleared, so the
  // paste never happens and Esc and Enter are ignored from then on.
  ctest('a snapshot that fails must not stop the paste or leave the picker '
      'stuck (a diagnostic can never break the feature)', (tester) async {
    final id = saveText('a');
    final c = await open();
    port.throwOnSnapshot = StateError('native went away');
    Object? escaped;
    try {
      await c.pasteItem(id);
    } catch (e) {
      escaped = e;
    }
    expect(escaped, isNull, reason: 'the log must not throw into the paste');
    expect(port.pastes.length, 1, reason: 'the paste still happens');
    // The paste finished, so the picker is closed; opening it again and
    // pressing Esc must work (nothing is stuck in the "pasting" state).
    port.press();
    port.calls.clear();
    await c.closePicker();
    expect(port.calls, contains('close'), reason: 'Esc still works afterwards');
  });

  ctest('start still finishes when the first snapshot fails', (tester) async {
    port.throwOnSnapshot = StateError('native went away');
    final c = build();
    Object? escaped;
    try {
      await c.start();
    } catch (e) {
      escaped = e;
    }
    expect(escaped, isNull, reason: 'a log error must not break start-up');
  });

  ctest('a forced post counts as a paste: no toast, no card, back to the '
      'history window, one log code', (tester) async {
    final id = saveText('a');
    final c = await open();
    port.pasteAnswer = PasteOutcome.pastedForced;
    log.codes.clear();
    await c.pasteItem(id);
    expect(c.toast, isNull);
    expect(c.mode, WindowMode.manage);
    expect(log.codes.map((x) => x.name), ['pasteSource', 'pasteForcedPost']);
    expect(port.calls.where((x) => x == 'showToast'), isEmpty);
  });

  ctest('a plain paste logs no forced-post code', (tester) async {
    final id = saveText('a');
    final c = await open();
    port.pasteAnswer = PasteOutcome.pasted;
    log.codes.clear();
    await c.pasteItem(id);
    expect(log.codes, [LogCode.pasteSource]);
  });
}
