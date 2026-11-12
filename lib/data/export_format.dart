import 'dart:convert';

import '../history/clip_item.dart';
import '../history/history_store.dart';
import '../shortcuts/ignored_apps.dart';
import '../snippets/snippet.dart';
import '../snippets/snippet_shortcut.dart';
import '../snippets/snippet_store.dart';

/// The export file (M1.8, `docs/design/your-data.md`, "Export file"): plain
/// UTF-8 JSON (PM decision D1 A). Nothing in it is ever run, opened or
/// followed as a path.
const exportFormatName = 'kusunga-export';
const exportFormatVersion = 1;

/// A bigger file is refused before it is read as JSON.
const maxImportBytes = 20 * 1024 * 1024;

/// Our own file is 3 levels deep (file, list, item). Deeper JSON is refused
/// before the parser, which recurses, ever sees it.
const maxImportDepth = 8;

/// The settings that travel (lead ruling G1, 2026-11-12). The picker
/// shortcut (one per machine) and the pause (a state, not a setting) never
/// do; launch at login is held by the OS.
const exportedSettingKeys = [
  'history_limit',
  historyExpirySetting,
  'typed_shortcuts_on',
  'paste_mode',
];

const _pasteModes = {'auto', 'copy_only'};

/// `kusunga-export-YYYY-MM-DD.json`, in local time.
String exportFileName(DateTime day) =>
    'kusunga-export-${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}.json';

class ExportSnippet {
  const ExportSnippet({
    required this.name,
    required this.content,
    required this.type,
    required this.position,
    this.shortcut,
  });

  final String name;
  final String content;
  final SnippetType type;
  final int position;
  final String? shortcut;
}

class ExportHistoryItem {
  const ExportHistoryItem({
    required this.content,
    required this.kind,
    required this.createdAt,
    required this.lastCopiedAt,
  });

  final String content;
  final ClipKind kind;

  /// Unix milliseconds.
  final int createdAt;
  final int lastCopiedAt;
}

/// The settings in a file; null where the file has none.
class ExportSettings {
  const ExportSettings({
    this.historyLimit,
    this.historyExpiryDays,
    this.typedShortcutsOn,
    this.pasteMode,
  });

  final int? historyLimit;
  final int? historyExpiryDays;
  final bool? typedShortcutsOn;

  /// `auto` or `copy_only` (the stored `paste_mode` values).
  final String? pasteMode;

  bool get isEmpty =>
      historyLimit == null &&
      historyExpiryDays == null &&
      typedShortcutsOn == null &&
      pasteMode == null;
}

class ExportBundle {
  const ExportBundle({
    required this.snippets,
    this.history,
    this.settings,
    this.ignoredApps,
  });

  final List<ExportSnippet> snippets;

  /// Null when the user did not tick "Include history" (D2 A).
  final List<ExportHistoryItem>? history;
  final ExportSettings? settings;
  final List<IgnoredApp>? ignoredApps;

  /// Whether "Also use the settings in this file" has anything to apply
  /// (D5 A: the settings and the ignored apps).
  bool get hasSettings =>
      (settings != null && !settings!.isEmpty) ||
      (ignoredApps != null && ignoredApps!.isNotEmpty);
}

String _time(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// The file's text. Pretty-printed so a person can read what is in it.
String encodeExport(ExportBundle b, {required DateTime exportedAt}) {
  final settings = b.settings;
  return const JsonEncoder.withIndent('  ').convert({
    'format': exportFormatName,
    'version': exportFormatVersion,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'snippets': [
      for (final s in b.snippets)
        {
          'name': s.name,
          'content': s.content,
          'type': s.type.name,
          'shortcut': s.shortcut,
          'position': s.position,
        },
    ],
    if (b.history != null)
      'history': [
        for (final h in b.history!)
          {
            'content': h.content,
            'kind': h.kind.name,
            'created_at': _time(h.createdAt),
            'last_copied_at': _time(h.lastCopiedAt),
          },
      ],
    if (settings != null)
      'settings': {
        'history_limit': ?settings.historyLimit,
        historyExpirySetting: ?settings.historyExpiryDays,
        if (settings.typedShortcutsOn != null)
          'typed_shortcuts_on': settings.typedShortcutsOn! ? 1 : 0,
        'paste_mode': ?settings.pasteMode,
      },
    if (b.ignoredApps != null)
      'ignored_apps': [
        for (final a in b.ignoredApps!)
          {'app_id': a.appId, 'display_name': a.displayName},
      ],
  });
}

/// Why a file was refused. [number] is what `importRejected` logs.
enum ImportRejectReason {
  tooLarge(1),
  notUtf8(2),
  notJson(3),
  tooDeep(4),
  wrongFormat(5),
  newerVersion(6),
  badItem(7);

  const ImportRejectReason(this.number);
  final int number;
}

/// The whole file is refused; nothing was changed.
class ImportRejected implements Exception {
  const ImportRejected(this.reason);
  final ImportRejectReason reason;

  // Never any text from the file.
  @override
  String toString() => 'ImportRejected(${reason.name})';
}

Never _bad() => throw const ImportRejected(ImportRejectReason.badItem);

/// Reads and checks a file the user picked. Throws [ImportRejected] for
/// anything that is not a valid Kusunga export: the whole file, never a part.
ExportBundle decodeImport(List<int> bytes) {
  if (bytes.length > maxImportBytes) {
    throw const ImportRejected(ImportRejectReason.tooLarge);
  }
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const ImportRejected(ImportRejectReason.notUtf8);
  }
  if (text.startsWith('﻿')) text = text.substring(1);
  if (_tooDeep(text)) throw const ImportRejected(ImportRejectReason.tooDeep);
  Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const ImportRejected(ImportRejectReason.notJson);
  }
  if (root is! Map<String, Object?>) {
    throw const ImportRejected(ImportRejectReason.notJson);
  }
  if (root['format'] != exportFormatName) {
    throw const ImportRejected(ImportRejectReason.wrongFormat);
  }
  final version = root['version'];
  if (version is! int || version < 1) {
    throw const ImportRejected(ImportRejectReason.wrongFormat);
  }
  if (version > exportFormatVersion) {
    throw const ImportRejected(ImportRejectReason.newerVersion);
  }
  final at = root['exported_at'];
  if (at != null) _ms(at);

  final snippets = root['snippets'];
  if (snippets is! List || snippets.length > SnippetStore.maxCount) _bad();
  final history = root['history'];
  if (history != null &&
      (history is! List || history.length > HistoryStore.maxLimit)) {
    _bad();
  }
  final settings = root['settings'];
  if (settings != null && settings is! Map<String, Object?>) _bad();
  final apps = root['ignored_apps'];
  if (apps != null && apps is! List) _bad();

  return ExportBundle(
    snippets: [for (final s in snippets) _snippet(s)],
    history: history == null
        ? null
        : [for (final h in history as List) _historyItem(h)],
    settings: settings == null
        ? null
        : _settings(settings as Map<String, Object?>),
    ignoredApps: apps == null ? null : [for (final a in apps as List) _app(a)],
  );
}

/// Whether [text] nests lists and objects deeper than [maxImportDepth].
/// Brackets inside strings do not count.
bool _tooDeep(String text) {
  var depth = 0;
  var inString = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (c == 0x5C) {
        i++; // the escaped character
      } else if (c == 0x22) {
        inString = false;
      }
    } else if (c == 0x22) {
      inString = true;
    } else if (c == 0x5B || c == 0x7B) {
      if (++depth > maxImportDepth) return true;
    } else if (c == 0x5D || c == 0x7D) {
      depth--;
    }
  }
  return false;
}

T _as<T>(Object? value) => value is T ? value : _bad();

/// Text from the file. Half a character (a lone UTF-16 surrogate) can't be
/// stored as UTF-8: SQLite would keep U+FFFD instead, so what is saved would
/// differ from the file. Such a file is refused (T2), as shortcuts already
/// are.
String _text(Object? value) {
  final text = _as<String>(value);
  for (final r in text.runes) {
    if (r >= 0xD800 && r <= 0xDFFF) _bad();
  }
  return text;
}

ExportSnippet _snippet(Object? raw) {
  final s = _as<Map<String, Object?>>(raw);
  final name = _text(s['name']);
  final content = _text(s['content']);
  // The editor's own rules (M1.4): a name that is one visible line of 1 to
  // 100 characters, content that is not blank and within 1 MiB.
  if (normaliseName(name) != name || checkSnippet(name, content).isNotEmpty) {
    _bad();
  }
  final typeName = _as<String>(s['type']);
  final type = SnippetType.values.where((t) => t.name == typeName);
  if (type.isEmpty) _bad();
  final shortcut = s['shortcut'];
  if (shortcut != null &&
      (shortcut is! String || checkShortcutText(shortcut) != null)) {
    _bad();
  }
  final position = s['position'] ?? 0;
  if (position is! int || position < 0) _bad();
  return ExportSnippet(
    name: name,
    content: content,
    type: type.single,
    position: position,
    shortcut: shortcut as String?,
  );
}

/// The one form Kusunga writes: UTC, `2026-11-12T09:30:00.000Z`, with or
/// without the fraction of a second.
final _utcTime = RegExp(
  r'^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(\.\d{1,6})?Z$',
);

/// A time from the file, in Unix milliseconds. It must name a moment that
/// exists: `DateTime.parse` rolls 31 February over to 3 March and month 13
/// into the next year, so the fields it read must be the fields written
/// (T9).
int _ms(Object? raw) {
  final text = _as<String>(raw);
  final m = _utcTime.firstMatch(text);
  final time = m == null ? null : DateTime.tryParse(text);
  if (m == null || time == null) _bad();
  final written = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  final read = [
    time.year,
    time.month,
    time.day,
    time.hour,
    time.minute,
    time.second,
  ];
  for (var i = 0; i < written.length; i++) {
    if (written[i] != read[i]) _bad();
  }
  return time.millisecondsSinceEpoch;
}

ExportHistoryItem _historyItem(Object? raw) {
  final h = _as<Map<String, Object?>>(raw);
  final content = _text(h['content']);
  // Capture's own rule: blank text is never kept (T1).
  if (content.trim().isEmpty || isOverCap(content)) _bad();
  final kindName = _as<String>(h['kind']);
  final kind = ClipKind.values.where((k) => k.name == kindName);
  if (kind.isEmpty) _bad();
  return ExportHistoryItem(
    content: content,
    kind: kind.single,
    createdAt: _ms(h['created_at']),
    lastCopiedAt: _ms(h['last_copied_at']),
  );
}

/// The same allowed values as the Settings tab (M1.7) and the picker.
ExportSettings _settings(Map<String, Object?> s) {
  final limit = s['history_limit'];
  if (limit != null &&
      (limit is! int ||
          limit < HistoryStore.minLimit ||
          limit > HistoryStore.maxLimit)) {
    _bad();
  }
  final days = s[historyExpirySetting];
  if (days != null && (days is! int || !historyExpiryChoices.contains(days))) {
    _bad();
  }
  final typed = s['typed_shortcuts_on'];
  // A whole number, like the other settings: 1.0 == 1 in Dart (T3).
  if (typed != null && (typed is! int || (typed != 0 && typed != 1))) _bad();
  final paste = s['paste_mode'];
  if (paste != null && !_pasteModes.contains(paste)) _bad();
  return ExportSettings(
    historyLimit: limit as int?,
    historyExpiryDays: days as int?,
    typedShortcutsOn: typed == null ? null : typed == 1,
    pasteMode: paste as String?,
  );
}

IgnoredApp _app(Object? raw) {
  final a = _as<Map<String, Object?>>(raw);
  final app = IgnoredApp(_text(a['app_id']), _text(a['display_name']));
  try {
    checkIgnoredApp(app);
  } on ArgumentError {
    _bad();
  }
  return app;
}

/// How far after the import a history time in the file may be: a day, for
/// clocks that differ between computers (lead ruling 2026-11-12).
const maxImportAhead = Duration(hours: 24);

/// The lead's time rules (2026-11-12). They need the import time, which
/// [decodeImport] doesn't have, so the import runs them on its result:
///  - a `created_at` or `last_copied_at` more than [maxImportAhead] after
///    [nowMs] refuses the whole file (it would sort first and never
///    expire);
///  - a `last_copied_at` before its `created_at` is kept with `created_at`
///    set to `last_copied_at`.
ExportBundle checkImportTimes(ExportBundle bundle, {required int nowMs}) {
  final history = bundle.history;
  if (history == null) return bundle;
  final latest = nowMs + maxImportAhead.inMilliseconds;
  return ExportBundle(
    snippets: bundle.snippets,
    history: [
      for (final h in history)
        if (h.createdAt > latest || h.lastCopiedAt > latest)
          _bad()
        else
          ExportHistoryItem(
            content: h.content,
            kind: h.kind,
            createdAt: h.lastCopiedAt < h.createdAt
                ? h.lastCopiedAt
                : h.createdAt,
            lastCopiedAt: h.lastCopiedAt,
          ),
    ],
    settings: bundle.settings,
    ignoredApps: bundle.ignoredApps,
  );
}

/// What an import did, for the summary toast and the log.
class ImportCounts {
  const ImportCounts({
    this.snippetsAdded = 0,
    this.snippetsAlreadyHere = 0,
    this.shortcutsDropped = 0,
    this.historyAdded = 0,
    this.historyTooOld = 0,
  });

  final int snippetsAdded;

  /// Same name and content as a snippet already here: skipped.
  final int snippetsAlreadyHere;

  /// Added without their shortcut, which was already used.
  final int shortcutsDropped;

  /// History items added or merged into one already here.
  final int historyAdded;

  /// Older than the auto-delete time: not added (lead ruling G5).
  final int historyTooOld;
}
