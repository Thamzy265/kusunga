import '../history/clip_item.dart';
import '../history/ui/text_display.dart';

/// Filters the history as you type: case-insensitive, matches anywhere, over
/// the in-memory previews (the first 2,000 characters of each item). Runs of
/// white space and line breaks count as one space.
///
/// The lower-case text of each item is kept between keystrokes, and a query
/// that only adds letters searches the previous result, so 5,000 items stay
/// well under 50 ms a keystroke.
class PickerSearch {
  static final _white = RegExp(r'\s+');

  Map<int, _Entry> _index = {};
  List<ClipItem>? _indexedFor;

  List<ClipItem>? _resultFor;
  String _lastQuery = '';
  List<ClipItem> _lastResult = const [];

  /// What a row shows: one line, control and invisible characters made
  /// visible (see `visibleText`).
  static String display(String preview) =>
      visibleText(preview).replaceAll(_white, ' ').trim();

  static String normaliseQuery(String query) =>
      query.replaceAll(_white, ' ').toLowerCase();

  /// The items that contain [query], in the same order. An empty query (or
  /// one of only white space) returns [items] as they are, with no work per
  /// item.
  List<ClipItem> filter(List<ClipItem> items, String query) {
    final q = normaliseQuery(query);
    if (q.trim().isEmpty) {
      _remember(items, '', items);
      return items;
    }
    _sync(items);
    final canNarrow =
        identical(_resultFor, items) &&
        _lastQuery.isNotEmpty &&
        q.startsWith(_lastQuery);
    final source = canNarrow ? _lastResult : items;
    final result = [
      for (final i in source)
        if (_index[i.id]!.lower.contains(q)) i,
    ];
    _remember(items, q, result);
    return result;
  }

  void _remember(List<ClipItem> items, String q, List<ClipItem> result) {
    _resultFor = items;
    _lastQuery = q;
    _lastResult = result;
  }

  /// Builds the lower-case text of up to [maxItems] items that are not indexed
  /// yet. The picker calls it in small steps after it opens, so the first
  /// keystroke finds the index ready. Returns true if more is left to do.
  bool warm(List<ClipItem> items, {int maxItems = 200}) {
    var built = 0;
    var left = false;
    for (final i in items) {
      final old = _index[i.id];
      if (old != null && old.preview == i.preview) continue;
      if (built >= maxItems) {
        left = true;
        break;
      }
      _index[i.id] = _Entry(i.preview, display(i.preview).toLowerCase());
      built++;
    }
    return left;
  }

  // Only items that are new (or changed) are indexed; the rest of the index is
  // reused, and entries of deleted items are dropped.
  void _sync(List<ClipItem> items) {
    if (identical(_indexedFor, items)) return;
    final next = <int, _Entry>{};
    for (final i in items) {
      final old = _index[i.id];
      next[i.id] = old != null && old.preview == i.preview
          ? old
          : _Entry(i.preview, display(i.preview).toLowerCase());
    }
    _index = next;
    _indexedFor = items;
    // A different list: the last result can no longer be reused.
    _resultFor = null;
  }

  /// The places in [displayText] where [query] matches, as (start, end), for
  /// highlighting. None if the lower-case text has a different length (a few
  /// letters change length when lower-cased): the row is then not highlighted.
  static List<(int, int)> ranges(String displayText, String query) {
    final q = normaliseQuery(query);
    if (q.trim().isEmpty) return const [];
    final lower = displayText.toLowerCase();
    if (lower.length != displayText.length) return const [];
    final out = <(int, int)>[];
    var from = 0;
    while (true) {
      final at = lower.indexOf(q, from);
      if (at < 0) break;
      final end = at + q.length;
      from = end;
      // Never start or end inside a surrogate pair (a half emoji as a query).
      if (_isLow(lower, at) || (end < lower.length && _isLow(lower, end))) {
        continue;
      }
      if (_isHigh(lower, end - 1) && end < lower.length) continue;
      out.add((at, end));
    }
    return out;
  }
}

bool _isLow(String s, int i) {
  final u = s.codeUnitAt(i);
  return u >= 0xDC00 && u <= 0xDFFF;
}

bool _isHigh(String s, int i) {
  final u = s.codeUnitAt(i);
  return u >= 0xD800 && u <= 0xDBFF;
}

class _Entry {
  _Entry(this.preview, this.lower);
  final String preview;
  final String lower;
}
