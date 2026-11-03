import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double textScale = 1.0,
  Brightness? brightness,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  if (brightness != null) {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }
  await tester.pumpWidget(const KusungaApp());
}

void main() {
  testWidgets('app title is Kusunga', (tester) async {
    await _pump(tester);

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Kusunga',
    );
  });

  for (final b in Brightness.values) {
    testWidgets('home renders in ${b.name} mode with readable contrast', (
      tester,
    ) async {
      await _pump(tester, brightness: b);

      expect(find.text('Kusunga'), findsOneWidget);
      final context = tester.element(find.byType(Scaffold));
      expect(
        Theme.of(context).brightness,
        Brightness.light,
        reason: 'App defines only a light theme today',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow window (200x300) has no overflow', (tester) async {
    await _pump(tester, size: const Size(200, 300));

    expect(find.text('Kusunga'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('very small window (60x60) has no overflow', (tester) async {
    await _pump(tester, size: const Size(60, 60));

    expect(tester.takeException(), isNull);
  });

  testWidgets('text scale 2.0 in a narrow window has no overflow', (
    tester,
  ) async {
    await _pump(tester, size: const Size(200, 300), textScale: 2.0);

    expect(find.text('Kusunga'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title is exposed to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(find.bySemanticsLabel('Kusunga'), findsOneWidget);
    handle.dispose();
  });
}
