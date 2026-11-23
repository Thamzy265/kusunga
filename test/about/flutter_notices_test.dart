// M1.9a round 5 (PM decision 2026-11-22): Flutter's own collection of the app's
// LICENSE, a second GPL row named "kusunga" next to the pinned "Kusunga", is
// hidden. Everything else Flutter collects stays.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/flutter_notices.dart';
import 'package:kusunga/about/licences.dart';

/// NOTICES.Z as `flutter build` writes it: gzip of "packages\n\ntext" blocks
/// split by a line of 80 dashes.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.notices, this.licence);
  final String notices;
  final String licence;

  @override
  Future<ByteData> load(String key) async {
    final bytes = switch (key) {
      'NOTICES.Z' => gzip.encode(utf8.encode(notices)),
      kusungaLicenceAsset => utf8.encode(licence),
      _ => throw FlutterError('no $key'),
    };
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

String notices(List<String> blocks) => blocks.join('\n${'-' * 80}\n');

void main() {
  final gpl = File('LICENSE').readAsStringSync();

  Future<List<List<String>>> packages(List<String> blocks) async => [
    for (final e in await flutterNotices(
      bundle: _Bundle(notices(blocks), gpl),
    ).toList())
      [...e.packages],
  ];

  test(
    "the app's own LICENSE is left out, the rest is kept in order",
    () async {
      expect(
        await packages([
          'abseil-cpp\n\nApache text',
          'kusunga\n\n$gpl',
          'archive\nzlib\n\nzlib text',
        ]),
        [
          ['abseil-cpp'],
          ['archive', 'zlib'],
        ],
      );
    },
  );

  test('the text of what is kept is the text Flutter collected', () async {
    final entries = await flutterNotices(
      bundle: _Bundle(notices(['path\n\nBSD text, line one\nline two']), gpl),
    ).toList();
    expect(entries.single.paragraphs.map((p) => p.text), [
      'BSD text, line one line two',
    ]);
  });

  test('a "kusunga" notice with another text is not hidden', () async {
    expect(await packages(['kusunga\n\nsome other notice', 'path\n\nx']), [
      ['kusunga'],
      ['path'],
    ]);
  });

  test('a package that merely shares the name is kept', () async {
    expect(await packages(['kusunga\nother\n\n$gpl']), [
      ['kusunga', 'other'],
    ]);
  });

  test('white space does not decide whether it is the same text', () async {
    final rewrapped = gpl.replaceAll('\n', '\r\n');
    expect(await packages(['kusunga\n\n$rewrapped', 'path\n\nx']), [
      ['path'],
    ]);
  });

  // BUG-T1 (M1.9a round 6): this used to expect the error on the stream, as
  // Flutter's own collector does. On the licence page that error replaces the
  // whole list, Kusunga's GPL and SQLite notices too, so now nothing is given.
  test('without NOTICES.Z it gives no notices and no error, so the page still '
      'lists Kusunga\'s own', () async {
    expect(await flutterNotices(bundle: _Missing()).toList(), isEmpty);
  });

  test('the binding registers it, after ours, in place of Flutter\'s own', () {
    final binding = File('lib/about/kusunga_binding.dart').readAsStringSync();
    final ours = binding.indexOf('registerLicences();');
    final flutters = binding.indexOf('LicenseRegistry.addLicense(');
    expect(ours, isNonNegative);
    expect(flutters, greaterThan(ours));
    expect(binding, contains('flutterNotices'));
    // Flutter's collector, which would bring the duplicate back.
    expect(
      binding,
      isNot(matches(RegExp(r'^\s*super\.initLicenses', multiLine: true))),
    );
  });
}

class _Missing extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Unable to load asset: "$key".');
}
