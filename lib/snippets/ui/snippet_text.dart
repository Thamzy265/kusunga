import '../../history/clip_item.dart';
import '../../history/ui/text_display.dart';
import '../snippet.dart';

/// The one shared way a snippet is written out on one line, in the main
/// window and the picker (C1): control and invisible characters shown, runs
/// of white space as one space.
abstract final class OneLine {
  static final _white = RegExp(r'\s+');

  static String of(String text) =>
      visibleText(text).replaceAll(_white, ' ').trim();
}

/// "My mobile — 07700 900123", or "Work email ;email — will@example.com"
/// with a typed shortcut (M1.5): the picker row, and what picker search
/// matches against, so every match is visible and highlighted (F8). Under
/// 400 px the picker leaves the shortcut out ([withShortcut] false) before
/// the name is cut.
String snippetLine(SnippetItem s, {bool withShortcut = true}) {
  final shortcut = withShortcut && s.shortcut != null ? ' ${s.shortcut}' : '';
  return '${OneLine.of(s.name)}$shortcut — ${OneLine.of(s.preview)}';
}

/// ", shortcut ;email" for the spoken names, or nothing.
String _spokenShortcut(SnippetItem s) =>
    s.shortcut == null ? '' : ', shortcut ${s.shortcut}';

/// One line of the content for screen readers, at most 500 characters.
String _spokenContent(SnippetItem s) {
  final text = OneLine.of(s.preview);
  final more = text.length > 500 || s.isTruncated ? '…' : '';
  return '${cutUnits(text, 500)}$more';
}

/// The main-window row: "My mobile, Phone, 07700 900123", or "Work email,
/// Email, shortcut ;email, will@example.com" (UI specs M1.4 and M1.5).
String snippetRowName(SnippetItem s) =>
    '${OneLine.of(s.name)}, ${s.type.label}${_spokenShortcut(s)}, '
    '${_spokenContent(s)}';

/// The picker row: "Email, Work email, shortcut ;email, will@example.com"
/// (the number is added in front by the picker).
String snippetPickerName(SnippetItem s) =>
    '${s.type.label}, ${OneLine.of(s.name)}${_spokenShortcut(s)}, '
    '${_spokenContent(s)}';
