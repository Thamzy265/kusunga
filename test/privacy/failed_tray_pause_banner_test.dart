// M1.6 UI spec, states matrix "Tray menu / Error" (PM decision 2026-11-10,
// docs commit bb51d44): when a pause started from the tray fails, the History
// tab shows "Couldn't apply the pause. Try again." in the warning banner
// above the list, until the next pause or resume.
//
// Repro: this fails until the developer builds that banner.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  Future<void> show(WidgetTester tester) async {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await tester.pump();
  }

  const text = "Couldn't apply the pause. Try again.";

  testWidgets('a failed pause from the tray shows the banner in the History '
      'tab', (tester) async {
    await show(tester);
    source.pauseAnswer = false;
    // The tray calls the service directly, with no Privacy tab involved.
    await service.pause.pause(PauseLength.hour);
    await tester.pump();
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('the banner stays until the next pause or resume, then goes', (
    tester,
  ) async {
    await show(tester);
    source.pauseAnswer = false;
    await service.pause.pause(PauseLength.hour);
    await tester.pump();
    await service.pause.tick(); // a tick (and its one retry) does not clear it
    await tester.pump();
    expect(find.text(text), findsOneWidget);
    source.pauseAnswer = true;
    await service.pause.pause(PauseLength.hour);
    await tester.pump();
    expect(find.text(text), findsNothing);
  });
}
