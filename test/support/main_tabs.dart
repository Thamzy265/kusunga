import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/ui/limit_field.dart';

/// A main-window tab by its `Semantics` identifier (`main-tab-history`,
/// `main-tab-snippets`, `main-tab-privacy`, `main-tab-settings`).
Finder mainTab(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

/// Shows the Settings tab, where the Keep field is since M1.7 (D1 A),
/// unless it already shows.
Future<void> showKeepField(WidgetTester tester) async {
  if (find.byType(LimitField).evaluate().isNotEmpty) return;
  await tester.tap(mainTab('main-tab-settings'));
  await tester.pumpAndSettle();
}

/// Shows the History tab (its list, header and ⋯ menu), unless it already
/// shows.
Future<void> showHistoryTab(WidgetTester tester) async {
  if (find.byTooltip('More options').evaluate().isNotEmpty) return;
  await tester.tap(mainTab('main-tab-history'));
  await tester.pumpAndSettle();
}
