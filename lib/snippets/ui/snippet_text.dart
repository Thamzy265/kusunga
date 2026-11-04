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

/// "My mobile — 07700 900123": the picker row, and what picker search
/// matches against, so every match is visible and highlighted (F8).
String snippetLine(SnippetItem s) =>
    '${OneLine.of(s.name)} — ${OneLine.of(s.preview)}';

/// One line of the content for screen readers, at most 500 characters.
String _spokenContent(SnippetItem s) {
  final text = OneLine.of(s.preview);
  final more = text.length > 500 || s.isTruncated ? '…' : '';
  return '${cutUnits(text, 500)}$more';
}

/// The main-window row: "My mobile, Phone, 07700 900123" (UI spec).
String snippetRowName(SnippetItem s) =>
    '${OneLine.of(s.name)}, ${s.type.label}, ${_spokenContent(s)}';

/// The picker row: "Phone, My mobile, 07700 900123" (the number is added
/// in front by the picker).
String snippetPickerName(SnippetItem s) =>
    '${s.type.label}, ${OneLine.of(s.name)}, ${_spokenContent(s)}';
