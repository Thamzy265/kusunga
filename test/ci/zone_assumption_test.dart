import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';

import '../support/fakes.dart';

/// BUG-F1 (tester round 12, confirmed independently in round 13): the History
/// footer froze in a test, not in the app. A service started in `setUp`
/// listens to the fake clipboard outside the test's fake-async zone, so a
/// Timer armed by the screen's listener runs on real time and
/// `tester.pump(Duration)` never fires it.
///
/// This file pins the two facts that make that a test trap and not an app bug:
/// 1. the trap itself (so nobody "fixes" the app for it again);
/// 2. the app runs in ONE zone: no `runZoned`, no isolates, no `compute`, so
///    a listener never runs in a different zone from the one that armed its
///    timers.
void main() {
  late FakeClipboardSource source;
  late HistoryService fromSetUp;

  setUp(() {
    source = FakeClipboardSource();
    fromSetUp = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
    )..start();
  });
  tearDown(() => fromSetUp.dispose());

  testWidgets('the trap: a Timer armed by a listener of a service started in '
      'setUp does not fire under tester.pump; one started in the test body '
      'does', (tester) async {
    final body = Zone.current;
    var firedFromSetUp = false;
    var zoneFromSetUp = true;
    fromSetUp.addListener(() {
      zoneFromSetUp = Zone.current == body;
      Timer(const Duration(seconds: 2), () => firedFromSetUp = true);
    });
    source.copy('a');
    await tester.pump(const Duration(seconds: 5));
    expect(zoneFromSetUp, isFalse, reason: 'the listener ran in the body zone');
    expect(firedFromSetUp, isFalse);

    final bodySource = FakeClipboardSource();
    final started = HistoryService(
      store: MemoryHistoryStore(),
      source: bodySource,
      log: FakeLog(),
    )..start();
    addTearDown(started.dispose);
    var firedInBody = false;
    var zoneInBody = false;
    started.addListener(() {
      zoneInBody = Zone.current == body;
      Timer(const Duration(seconds: 2), () => firedInBody = true);
    });
    bodySource.copy('b');
    await tester.pump(const Duration(seconds: 5));
    expect(zoneInBody, isTrue);
    expect(firedInBody, isTrue);
  });

  test('the app has one zone: no runZoned, no isolates, no compute, no '
      'Zone.current.fork in lib/', () {
    final patterns = {
      'runZoned': RegExp(r'\brunZoned(Guarded)?\s*\('),
      'Zone fork': RegExp(r'Zone\.current\.fork|\.fork\s*\(\s*specification'),
      'Isolate': RegExp(r'\bIsolate\.(spawn|run)\b'),
      'compute': RegExp(r'\bcompute\s*\('),
    };
    final found = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final text = e
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      patterns.forEach((name, re) {
        if (re.hasMatch(text)) found.add('$name in ${e.path}');
      });
    }
    expect(
      found,
      isEmpty,
      reason:
          'a second zone or isolate means a listener can arm a Timer in '
          'a zone the screen does not run in: re-check the footer throttle '
          '(History and Snippets) and every Timer in lib/',
    );
  });

  test('Timers in lib/ live only in the known screens and controllers: a new '
      'file with a Timer must be checked for the zone that calls it', () {
    final allowed = {
      'lib/history/ui/history_host.dart',
      'lib/history/ui/history_screen.dart',
      'lib/snippets/ui/snippets_screen.dart',
      'lib/picker/picker_controller.dart',
      'lib/picker/ui/picker_panel.dart',
      'lib/picker/ui/picker_settings_section.dart',
    };
    final seen = <String>{};
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final text = e
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (RegExp(r'\bTimer(\.periodic)?\s*\(').hasMatch(text)) {
        seen.add(e.path.replaceAll('\\', '/'));
      }
    }
    expect(
      seen.difference(allowed),
      isEmpty,
      reason: 'a new file creates a Timer: check which zone calls it',
    );
  });
}
