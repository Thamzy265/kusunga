import 'package:material_ui/material_ui.dart';

/// The width of the `focus` ring drawn outside a focused button, in px.
const focusRingWidth = 2.0;

/// Semantic design tokens (UI spec, "Tokens used"). Widgets read these and
/// never hard-code a colour or size. Light and dark values are defined here
/// once; `test/theme/tokens_test.dart` checks their contrast.
@immutable
class KusungaTokens extends ThemeExtension<KusungaTokens> {
  const KusungaTokens({
    required this.surface,
    required this.surfaceHover,
    required this.selection,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.borderHover,
    required this.focus,
    required this.danger,
    required this.bannerWarnBg,
    required this.bannerWarnText,
  });

  final Color surface;
  final Color surfaceHover;

  /// The selected row of the picker (M1.3): 3:1 on the surface, with `text`
  /// at 4.5:1 on it.
  final Color selection;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color borderHover;
  final Color focus;
  final Color danger;
  final Color bannerWarnBg;
  final Color bannerWarnText;

  /// space.1 to space.6, in logical pixels (4 px steps).
  static const space = <double>[4, 8, 12, 16, 20, 24];
  static double get space1 => space[0];
  static double get space2 => space[1];
  static double get space3 => space[2];
  static double get space4 => space[3];
  static double get space5 => space[4];
  static double get space6 => space[5];

  static const radius2 = 8.0;

  /// type.body, type.caption, type.title (colour comes from the theme).
  static const body = TextStyle(fontSize: 14, height: 1.4);
  static const caption = TextStyle(fontSize: 12, height: 1.3);

  /// type.mono: [caption] in a monospace face, for typed shortcuts such as
  /// `;email` (M1.5 UI spec, "Tokens used").
  static const mono = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Consolas', 'Courier New', 'monospace'],
  );
  static const title = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  static const light = KusungaTokens(
    surface: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFEEF3F2),
    selection: Color(0xFF5B91CC),
    text: Color(0xFF1B1F1E),
    textMuted: Color(0xFF4A5553),
    border: Color(0xFF6F7977),
    borderHover: Color(0xFF3C4644),
    focus: Color(0xFF0B5FB0),
    danger: Color(0xFFB3261E),
    bannerWarnBg: Color(0xFFFFF1CC),
    bannerWarnText: Color(0xFF4F3A00),
  );

  static const dark = KusungaTokens(
    surface: Color(0xFF1A1D1C),
    surfaceHover: Color(0xFF272C2B),
    selection: Color(0xFF4A6C96),
    text: Color(0xFFECEFEE),
    textMuted: Color(0xFFAAB4B1),
    border: Color(0xFF8A9693),
    borderHover: Color(0xFFC3CCCA),
    focus: Color(0xFF7DB7FF),
    danger: Color(0xFFFF8A80),
    bannerWarnBg: Color(0xFF3D3210),
    bannerWarnText: Color(0xFFFFE3A3),
  );

  static KusungaTokens of(BuildContext context) =>
      Theme.of(context).extension<KusungaTokens>()!;

  /// The app theme for one brightness, with these tokens attached.
  static ThemeData themeData(Brightness brightness) {
    final tokens = brightness == Brightness.dark ? dark : light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ).copyWith(
          surface: tokens.surface,
          onSurface: tokens.text,
          error: tokens.danger,
          outline: tokens.border,
        );
    // Keyboard focus on a button: the 2 px `focus` ring of the rows and tabs,
    // drawn outside the button so it sits on the background (3:1 there), not
    // on the button's own fill. Material's default is only a faint tint
    // (QA-M14-4). A null side keeps each button's own outline otherwise.
    final ring = ButtonStyle(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(
                color: tokens.focus,
                width: focusRingWidth,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
    );
    bool focused(Set<WidgetState> s) => s.contains(WidgetState.focused);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.surface,
      useMaterial3: true,
      textButtonTheme: TextButtonThemeData(style: ring),
      filledButtonTheme: FilledButtonThemeData(style: ring),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ring),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ring),
      iconButtonTheme: IconButtonThemeData(style: ring),
      // Menu items (the row "More" menu, the Type menu) show focus as a
      // `selection` fill, as the picker's selected row: 3:1 on the menu,
      // text 4.5:1 on it.
      focusColor: tokens.selection,
      popupMenuTheme: PopupMenuThemeData(color: tokens.surface),
      // The toast's Undo sits on the dark toast, where the ring colour would
      // be lost: when focused it is filled with the toast's text colour.
      snackBarTheme: SnackBarThemeData(
        actionTextColor: WidgetStateColor.resolveWith(
          (s) => focused(s) ? scheme.inverseSurface : scheme.inversePrimary,
        ),
        actionBackgroundColor: WidgetStateColor.resolveWith(
          (s) => focused(s) ? scheme.onInverseSurface : Colors.transparent,
        ),
      ),
      extensions: [tokens],
    );
  }

  @override
  KusungaTokens copyWith({
    Color? surface,
    Color? surfaceHover,
    Color? selection,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? borderHover,
    Color? focus,
    Color? danger,
    Color? bannerWarnBg,
    Color? bannerWarnText,
  }) => KusungaTokens(
    surface: surface ?? this.surface,
    surfaceHover: surfaceHover ?? this.surfaceHover,
    selection: selection ?? this.selection,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    border: border ?? this.border,
    borderHover: borderHover ?? this.borderHover,
    focus: focus ?? this.focus,
    danger: danger ?? this.danger,
    bannerWarnBg: bannerWarnBg ?? this.bannerWarnBg,
    bannerWarnText: bannerWarnText ?? this.bannerWarnText,
  );

  @override
  KusungaTokens lerp(KusungaTokens? other, double t) {
    if (other == null) return this;
    return KusungaTokens(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderHover: Color.lerp(borderHover, other.borderHover, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      bannerWarnBg: Color.lerp(bannerWarnBg, other.bannerWarnBg, t)!,
      bannerWarnText: Color.lerp(bannerWarnText, other.bannerWarnText, t)!,
    );
  }
}
