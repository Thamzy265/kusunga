/// Shows control, bidi and invisible characters as visible symbols so that
/// copied text cannot pretend to be something else (design note, abuse cases).
String visibleText(String text) {
  final out = StringBuffer();
  final runes = text.replaceAll('\r\n', '\n').runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    // A zero width joiner between two emoji is part of one emoji (a family, a
    // rainbow flag): it stays. Anywhere else it is shown as a code.
    if (r == 0x200D &&
        i > 0 &&
        i + 1 < runes.length &&
        _joinsEmoji(runes[i - 1], runes[i + 1])) {
      out.writeCharCode(r);
    } else if (r == 0x0A || r == 0x09) {
      out.writeCharCode(r);
    } else if (r < 0x20) {
      out.writeCharCode(0x2400 + r); // Control Pictures block
    } else if (r == 0x7F) {
      out.writeCharCode(0x2421);
    } else if (_isInvisible(r)) {
      out.write('[U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}]');
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

bool _isInvisible(int r) =>
    (r >= 0x80 && r <= 0x9F) || // C1 controls
    r == 0x2028 || // line separator
    r == 0x2029 || // paragraph separator
    (r >= 0xE0000 && r <= 0xE007F) || // tag characters (invisible text)
    r == 0x061C || // Arabic letter mark
    (r >= 0x200B && r <= 0x200F) || // zero width, LRM, RLM
    (r >= 0x202A && r <= 0x202E) || // bidi embeddings and overrides
    (r >= 0x2060 && r <= 0x2064) || // word joiner and invisible operators
    (r >= 0x2066 && r <= 0x206F) || // bidi isolates and deprecated formats
    r == 0xFEFF; // byte order mark

/// "now", "2 min", "1 h", "3 d" (row).
String relativeTimeShort(int nowMs, int thenMs) {
  final minutes = _minutes(nowMs, thenMs);
  if (minutes < 1) return 'now';
  if (minutes < 60) return '$minutes min';
  if (minutes < 1440) return '${minutes ~/ 60} h';
  return '${minutes ~/ 1440} d';
}

/// "just now", "2 minutes ago", "1 hour ago" (screen readers).
String relativeTimeLong(int nowMs, int thenMs) {
  final minutes = _minutes(nowMs, thenMs);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return _plural(minutes, 'minute');
  if (minutes < 1440) return _plural(minutes ~/ 60, 'hour');
  return _plural(minutes ~/ 1440, 'day');
}

int _minutes(int nowMs, int thenMs) {
  final diff = nowMs - thenMs;
  return diff <= 0 ? 0 : diff ~/ 60000;
}

String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';

bool _isEmoji(int r) =>
    (r >= 0x1F000 && r <= 0x1FAFF) || // pictographs, skin tones, symbols
    (r >= 0x2600 && r <= 0x27BF) || // misc symbols, dingbats (hearts, ...)
    (r >= 0x2B00 && r <= 0x2BFF) ||
    r == 0x2764;

bool _joinsEmoji(int before, int after) =>
    (_isEmoji(before) || before == 0xFE0F) && _isEmoji(after);
