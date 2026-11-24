import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:kusunga/ui/focus_order.dart';

void main() {
  test('the reveal reach is the width of the button focus ring (R14)', () {
    expect(focusRingReach, focusRingWidth);
  });

  test('a focused button draws the ring at focusRingWidth', () {
    final side = KusungaTokens.themeData(
      Brightness.light,
    ).outlinedButtonTheme.style?.side?.resolve({WidgetState.focused});
    expect(side?.width, focusRingWidth);
  });
}
