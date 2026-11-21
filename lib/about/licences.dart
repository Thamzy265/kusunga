import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'build_info.dart';

/// The notices bundled with the app (M1.9a, GPLv3 section 5(d) and the
/// third-party notices Flutter's own collection misses; `docs/licences.md`).
/// The texts are assets, never fetched. `LICENSE` is the GPL text itself.
const kusungaLicenceAsset = 'LICENSE';
const sqlite3mcNoticesAsset = 'assets/licences/sqlite3mc.txt';
const sqliteNoticeAsset = 'assets/licences/sqlite.txt';

const licenceLegalese =
    'Copyright (C) 2026 William Nasoni. Licensed under the GNU GPL, version 3 '
    'only. This program comes with ABSOLUTELY NO WARRANTY. This is free '
    'software, and you are welcome to redistribute it under certain '
    'conditions; see the GNU GPL for details.';

/// Adds Kusunga, SQLite3 Multiple Ciphers and SQLite to Flutter's licence
/// registry, so they are listed at the top of the licence page. Call once at
/// start-up. Each text is read from [bundle] only when the page is opened.
void registerLicences({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final b = bundle ?? rootBundle;
    // Each notice stands alone: one that fails to load is left out and the
    // others still show.
    for (final (name, asset) in [
      ('Kusunga', kusungaLicenceAsset),
      ('SQLite3 Multiple Ciphers', sqlite3mcNoticesAsset),
      ('SQLite', sqliteNoticeAsset),
    ]) {
      String? text;
      try {
        text = await b.loadString(asset);
      } catch (_) {}
      if (text != null) yield LicenseEntryWithLineBreaks([name], text);
    }
  });
}

/// Opens Flutter's licence page for this build, with Esc to go back (what
/// `showLicensePage` does, plus the key the spec asks for). Closing it returns
/// the focus to the button that opened it.
Future<void> showLicences(BuildContext context, BuildInfo info) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: Focus(
            autofocus: true,
            child: LicensePage(
              applicationName: 'Kusunga',
              applicationVersion: info.licenceVersion,
              applicationLegalese: licenceLegalese,
            ),
          ),
        ),
      ),
    );
