import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

/// Cmd+Z on the Mac, Ctrl+Z on Windows.
Future<void> undoKey(WidgetTester t, TargetPlatform platform) async {
  final mod = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await t.sendKeyDownEvent(mod);
  await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await t.sendKeyUpEvent(mod);
  await t.pump();
}

void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  Future<void> show(WidgetTester t) async {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
    )..start();
    source.copy('row one');
    source.copy('row two');
    await t.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: HistoryScreen(service: service),
      ),
    );
    await t.pump();
  }

  Finder field() => find.byKey(const Key('limit-field'));
  String fieldText(WidgetTester t) =>
      t.widget<TextField>(field()).controller!.text;

  Future<void> typeInField(WidgetTester t) async {
    await t.tap(field());
    await t.pump(const Duration(milliseconds: 600));
    await t.enterText(field(), '300');
    await t.pump(const Duration(milliseconds: 600));
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    final key = platform == TargetPlatform.macOS ? 'Cmd+Z' : 'Ctrl+Z';
    final variant = TargetPlatformVariant.only(platform);

    testWidgets('$key in the Keep field undoes typing', (t) async {
      await show(t);
      await typeInField(t);
      expect(fieldText(t), '300');
      await undoKey(t, platform);
      expect(fieldText(t), '200');
      service.dispose();
    }, variant: variant);

    testWidgets(
      '$key in the Keep field with a delete waiting does not restore the row',
      (t) async {
        await show(t);
        await t.sendKeyEvent(LogicalKeyboardKey.delete); // first row has focus
        await t.pump();
        expect(service.items.length, 1);
        await typeInField(t);
        await undoKey(t, platform);
        expect(service.items.length, 1, reason: 'the row stays deleted');
        expect(fieldText(t), '200', reason: 'the key undid the typing');
        service.dispose();
        await t.pump(const Duration(seconds: 6));
      },
      variant: variant,
    );

    testWidgets('$key in the list still undoes the delete', (t) async {
      await show(t);
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pump();
      expect(service.items.length, 1);
      await undoKey(t, platform);
      await t.pumpAndSettle();
      expect(service.items.length, 2);
      service.dispose();
    }, variant: variant);
  }
}
