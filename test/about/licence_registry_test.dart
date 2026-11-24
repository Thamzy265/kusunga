// M1.9a (AC1, AC7): every notice listed in docs/licences.md is reachable in
// the licence registry, from texts bundled as assets.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/licences.dart';

Future<Map<String, String>> registered() async {
  LicenseRegistry.reset();
  registerLicences();
  final byPackage = <String, StringBuffer>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final name in entry.packages) {
      final buffer = byPackage.putIfAbsent(name, StringBuffer.new);
      for (final p in entry.paragraphs) {
        buffer.writeln(p.text);
      }
    }
  }
  return {for (final e in byPackage.entries) e.key: e.value.toString()};
}

/// The first cell of each row of the "what it bundles" table in
/// docs/licences.md, cut at its first " (" or ":" (the part that names it).
List<String> bundledComponents() {
  final doc = File('docs/licences.md').readAsStringSync();
  final section = doc
      .split('## SQLite3 Multiple Ciphers 2.7.1: what it bundles')
      .last
      .split('\n## Flags')
      .first;
  final rows = section
      .split('\n')
      .where((l) => l.startsWith('| ') && !l.startsWith('| Component'))
      .where((l) => !l.startsWith('|---'));
  return [
    for (final row in rows)
      row.split('|')[1].trim().split(RegExp(r' \(|:')).first.trim(),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> licences;
  setUpAll(() async => licences = await registered());
  tearDownAll(LicenseRegistry.reset);

  test('Kusunga, SQLite3 Multiple Ciphers and SQLite are registered', () {
    expect(
      licences.keys,
      containsAll(['Kusunga', 'SQLite3 Multiple Ciphers', 'SQLite']),
    );
  });

  test('Kusunga: the full GPL-3.0 text from LICENSE', () {
    final gpl = File('LICENSE').readAsStringSync();
    // The registry splits the text into paragraphs; compare without
    // whitespace so line breaks do not matter.
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), '');
    // The Kusunga package also lists the two SQLite notices after the GPL
    // (so the top row of the licence page reaches every notice).
    expect(flat(licences['Kusunga']!), startsWith(flat(gpl)));
    expect(licences['Kusunga'], contains('Version 3, 29 June 2007'));
  });

  test('SQLite: the public-domain blessing', () {
    final text = licences['SQLite']!;
    expect(text, contains('The author disclaims copyright'));
    expect(text, contains('May you do good and not evil.'));
    expect(text, contains('May you share freely'));
  });

  test('every bundled part listed in docs/licences.md is in the notice', () {
    final components = bundledComponents();
    expect(components, hasLength(19), reason: 'parts table changed');
    final text = licences['SQLite3 Multiple Ciphers']!;
    for (final name in components) {
      expect(text, contains(name), reason: 'missing: $name');
    }
  });

  test('the parts the spec names are there by name', () {
    final text = licences['SQLite3 Multiple Ciphers']!;
    for (final name in [
      'AEGIS',
      'Ascon',
      'ChaCha20',
      'Poly1305',
      'SHA-1',
      'SHA-2',
      'MD5',
      'fastpbkdf2',
      'Argon2',
      'AES',
      'miniz',
    ]) {
      expect(text, contains(name), reason: name);
    }
  });

  // AC7: the MIT notice of the project, with its copyright line, as in
  // LICENSE of SQLite3 Multiple Ciphers v2.7.1 (every part: licence_texts_test).
  test('SQLite3 Multiple Ciphers: the MIT notice, with its copyright line', () {
    final text = licences['SQLite3 Multiple Ciphers']!;
    expect(text, contains('MIT License'));
    expect(text, contains('Copyright (c) 2019-2026 Ulrich Telle'));
    expect(text, contains('Permission is hereby granted, free of charge'));
    expect(text, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
  });

  test('the notice names the dependency version, like docs/licences.md', () {
    expect(licences['SQLite3 Multiple Ciphers'], contains('2.7.1'));
    expect(licences['SQLite'], contains('3.54.1'));
  });

  test('the app registers the notices at start-up, before Flutter\'s own', () {
    final binding = File('lib/about/kusunga_binding.dart').readAsStringSync();
    final ours = binding.indexOf('registerLicences();');
    final flutters = binding.indexOf(
      'LicenseRegistry.addLicense(flutterNotices)',
    );
    expect(ours, isNonNegative);
    expect(flutters, greaterThan(ours));
  });

  test('the texts are bundled assets, never fetched', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- LICENSE'));
    expect(pubspec, contains('- assets/licences/'));
    final source = File('lib/about/licences.dart').readAsStringSync();
    expect(source, isNot(contains('http.')));
    expect(source, isNot(contains('HttpClient')));
  });
}
