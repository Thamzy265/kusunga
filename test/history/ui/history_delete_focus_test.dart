import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

/// M2 (found in M1.3 review, an M1.2 bug): deleting the only row left no focus
/// inside the screen, so Cmd/Ctrl+Z did nothing.
void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    final meta = platform == TargetPlatform.macOS;
    testWidgets(
      '${meta ? 'Cmd' : 'Ctrl'}+Z restores the only row after deleting it',
      (t) async {
        final source = FakeClipboardSource();
        final service = HistoryService(
          store: MemoryHistoryStore(),
          source: source,
          log: const NullErrorLog(),
        )..start();
        addTearDown(service.dispose);
        source.copy('only row');
        await t.pumpWidget(
          MaterialApp(
            theme: KusungaTokens.themeData(Brightness.light),
            home: HistoryScreen(service: service),
          ),
        );
        await t.pump();
        await t.tap(find.widgetWithText(TextButton, 'Delete').first);
        await t.pump();
        expect(service.items, isEmpty);

        final mod = meta
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await t.sendKeyDownEvent(mod);
        await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await t.sendKeyUpEvent(mod);
        await t.pump();
        expect([for (final i in service.items) i.preview], ['only row']);
        await t.pump(const Duration(seconds: 6));
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
