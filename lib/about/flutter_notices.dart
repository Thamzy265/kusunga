import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart';

import 'licences.dart';

/// The notices Flutter's build collects (`NOTICES.Z`), the way
/// `ServicesBinding.initLicenses` offers them, except for one: the app's own
/// `LICENSE`, which the build files under the package name "kusunga". It
/// repeats the GPL text next to the pinned "Kusunga" row, so it is left out
/// (PM decision 2026-11-22). Only an entry for that package alone, with the
/// text of `LICENSE`, is hidden.
///
/// Flutter's licence page lists whatever the registry holds and has no way to
/// hide a row, and the registry has no way to take Flutter's collector out
/// again, so [KusungaBinding] registers this in its place.
///
/// A `NOTICES.Z` that is missing or cannot be read, unpacked or decoded gives
/// no notices and no error (BUG-T1): an error on this stream makes the licence
/// page show only the error text, which would hide Kusunga's own GPL, SQLite
/// and SQLite3 Multiple Ciphers notices.
Stream<LicenseEntry> flutterNotices({AssetBundle? bundle}) async* {
  final b = bundle ?? rootBundle;
  final List<LicenseEntry> entries;
  try {
    final data = await b.load('NOTICES.Z');
    // On the main isolate: the app has one zone and no isolates
    // (`test/ci/zone_assumption_test.dart`). It runs only when the licence
    // page is opened.
    entries = _parse(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } catch (_) {
    return;
  }
  String? own;
  try {
    own = _squash(await b.loadString(kusungaLicenceAsset));
  } catch (_) {}
  for (final entry in entries) {
    if (own != null && _isAppLicence(entry, own)) continue;
    yield entry;
  }
}

/// [packages] holds only "kusunga" and the text is [ownLicence] (squashed).
bool _isAppLicence(LicenseEntry entry, String ownLicence) =>
    entry.packages.length == 1 &&
    entry.packages.single == _appPackage &&
    _squash([for (final p in entry.paragraphs) p.text].join(' ')) == ownLicence;

/// The package name in `pubspec.yaml`, which the build uses for the app.
const _appPackage = 'kusunga';

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Same format and split as Flutter's own parser.
List<LicenseEntry> _parse(Uint8List compressed) {
  final raw = utf8.decode(gzip.decode(compressed));
  final separator = '\n${'-' * 80}\n';
  return [
    for (final license in raw.split(separator))
      if (license.indexOf('\n\n') case final int split when split >= 0)
        LicenseEntryWithLineBreaks(
          license.substring(0, split).split('\n'),
          license.substring(split + 2),
        )
      else
        LicenseEntryWithLineBreaks(const <String>[], license),
  ];
}
