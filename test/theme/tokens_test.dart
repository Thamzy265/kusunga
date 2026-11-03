import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/theme/tokens.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  for (final (name, t) in [
    ('light', KusungaTokens.light),
    ('dark', KusungaTokens.dark),
  ]) {
    group('$name tokens', () {
      test('text meets 4.5:1 on the surface and on hover', () {
        expect(contrast(t.text, t.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(t.text, t.surfaceHover), greaterThanOrEqualTo(4.5));
        expect(contrast(t.textMuted, t.surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(t.textMuted, t.surfaceHover),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(t.danger, t.surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(t.bannerWarnText, t.bannerWarnBg),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('borders, icons and the focus ring meet 3:1', () {
        expect(contrast(t.border, t.surface), greaterThanOrEqualTo(3));
        expect(contrast(t.borderHover, t.surface), greaterThanOrEqualTo(3));
        expect(contrast(t.focus, t.surface), greaterThanOrEqualTo(3));
        expect(contrast(t.focus, t.surfaceHover), greaterThanOrEqualTo(3));
      });
    });
  }

  test('spacing runs in 4 px steps and radius is defined', () {
    expect(KusungaTokens.space, [4, 8, 12, 16, 20, 24]);
    expect(KusungaTokens.radius2, greaterThan(0));
  });

  test('the theme extension is found from a built theme', () {
    final theme = KusungaTokens.themeData(Brightness.dark);
    expect(theme.extension<KusungaTokens>(), same(KusungaTokens.dark));
  });
}
