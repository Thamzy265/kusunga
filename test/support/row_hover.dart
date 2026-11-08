import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';

/// Clicks a snippet row button the way a person with a mouse does: the
/// pointer is over the row first, so its buttons show, then it clicks.
/// Hidden row buttons take no room and no clicks (QA-M14-3), so a plain tap
/// at the button's place would miss it.
Future<void> clickRowAction(WidgetTester tester, Finder button) async {
  final row = find.ancestor(of: button, matching: find.byType(SnippetRow));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getTopLeft(row) + const Offset(8, 8));
  await tester.pump();
  await tester.tap(button, kind: PointerDeviceKind.mouse);
  await mouse.removePointer();
}
