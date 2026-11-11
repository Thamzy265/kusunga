// M1.7 tester (R1: nothing expired shows in History or the picker, even
// before the clean-up runs). The only place that reads the whole history from
// the store is HistoryService._refresh, and only for Never; the picker gets
// its list from the HistoryService, never from the store.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only HistoryService reads the clip list from the store, and it '
      'filters whenever auto-delete is on', () {
    final readers = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('lib/snippets') ||
          f.path.contains('sqlite_history_store') ||
          f.path.contains('memory_history_store') ||
          f.path.endsWith('history_store.dart')) {
        continue;
      }
      final src = f.readAsStringSync();
      if (RegExp(r'_store\.list\(\)|store\.list\(\)').hasMatch(src)) {
        readers.add(f.path);
      }
    }
    expect(readers, ['lib/history/history_service.dart']);
    final service = File('lib/history/history_service.dart').readAsStringSync();
    expect(
      service,
      contains('cutoff == null ? _store.list() : _store.listSince(cutoff)'),
    );
  });

  test('the picker and the shortcut code never touch the history store', () {
    for (final dir in ['lib/picker', 'lib/shortcuts']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        expect(src, isNot(contains('history_store.dart')), reason: f.path);
        expect(src, isNot(contains('sqlite_history_store')), reason: f.path);
      }
    }
  });

  test('both clean-up deletes use a strict "<" and the read filter ">="', () {
    final sqlite = File(
      'lib/history/sqlite_history_store.dart',
    ).readAsStringSync();
    expect(sqlite, contains('DELETE FROM clip_items WHERE last_copied_at < ?'));
    expect(sqlite, contains("'WHERE last_copied_at >= ? '"));
    expect(sqlite, isNot(contains('last_copied_at <= ?')));
    expect(sqlite, isNot(contains('last_copied_at > ?')));
  });
}
