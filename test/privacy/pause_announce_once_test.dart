// O6: the announcer speaks only on a user pause or resume, or when a timed
// pause ends; a clock-back cut of the end time on a tick says nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/privacy/ui/privacy_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('a clock-back cut on a tick is not announced', (tester) async {
    final handle = tester.ensureSemantics();
    var now = DateTime(2026, 11, 10, 14, 0).millisecondsSinceEpoch;
    final pause = PauseService(
      setNativePause: (_) async => true,
      readSetting: (_) => null,
      writeSetting: (_, _) => true,
      log: FakeLog(),
      persists: true,
      clock: () => now,
    )..load();
    addTearDown(pause.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Scaffold(body: PauseAnnouncer(pause: pause)),
      ),
    );
    await pause.pause(PauseLength.hour);
    await tester.pump();
    expect(find.bySemanticsLabel('History paused until 15:00'), findsOneWidget);
    now -= 3 * 60 * 60 * 1000; // clock back 3 h: the end is cut to 12:00
    await pause.tick();
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp('History paused until 12:00')),
      findsNothing,
    );
    expect(find.bySemanticsLabel('History paused until 15:00'), findsOneWidget);
    handle.dispose();
  });
}
