import 'package:sqlite3/sqlite3.dart';

/// An app where typed shortcuts never fire (M1.5; M1.6 reuses the list for
/// history). [appId] is the Mac bundle id, or the Windows executable name in
/// lower case. Kept in the encrypted file only; never logged.
class IgnoredApp {
  const IgnoredApp(this.appId, this.displayName, {this.preset = false});

  final String appId;
  final String displayName;

  /// One of the password managers Kusunga lists from the start.
  final bool preset;
}

/// The password managers on the list from the start (M1.5 PM decision D4 A;
/// M1.6 decision D2 A). Rows for both systems are kept; each system shows
/// and uses only its own (see [appIdIsForWindows]). Schema version 4 seeds
/// [presetIgnoredAppsV4] and version 5 adds [presetIgnoredAppsV5], in this
/// order (tests check both).
const presetIgnoredApps = <IgnoredApp>[
  ...presetIgnoredAppsV4,
  ...presetIgnoredAppsV5,
];

/// The M1.5 presets (schema version 4). How each id was checked is in the
/// M1.5 hand-off.
const presetIgnoredAppsV4 = <IgnoredApp>[
  IgnoredApp('com.1password.1password', '1Password', preset: true),
  IgnoredApp('com.agilebits.onepassword7', '1Password 7', preset: true),
  IgnoredApp('com.bitwarden.desktop', 'Bitwarden', preset: true),
  IgnoredApp('org.keepassxc.keepassxc', 'KeePassXC', preset: true),
  IgnoredApp('com.apple.Passwords', 'Passwords', preset: true),
  IgnoredApp('1password.exe', '1Password', preset: true),
  IgnoredApp('bitwarden.exe', 'Bitwarden', preset: true),
  IgnoredApp('keepassxc.exe', 'KeePassXC', preset: true),
  IgnoredApp('keepass.exe', 'KeePass', preset: true),
];

/// The M1.6 presets (schema version 5). Each id was read from a public
/// listing on 2026-11-10: Mac bundle ids from the Homebrew cask data
/// (formulae.brew.sh/api/cask) or Apple's App Store lookup; Windows exe
/// names from public file listings of the installed apps. The sources and
/// the ids left out are in the M1.6 hand-off.
const presetIgnoredAppsV5 = <IgnoredApp>[
  IgnoredApp('com.lastpass.lastpassmacdesktop', 'LastPass', preset: true),
  IgnoredApp('in.sinew.Enpass-Desktop', 'Enpass', preset: true),
  IgnoredApp('com.nordsec.nordpass', 'NordPass', preset: true),
  IgnoredApp('me.proton.pass.electron', 'Proton Pass', preset: true),
  IgnoredApp('com.dashlane.dashlanephonefinal', 'Dashlane', preset: true),
  IgnoredApp('com.keepersecurity.passwordmanager', 'Keeper', preset: true),
  IgnoredApp('com.callpod.keepermac.lite', 'Keeper (App Store)', preset: true),
  IgnoredApp('lastpass.exe', 'LastPass', preset: true),
  IgnoredApp('enpass.exe', 'Enpass', preset: true),
  IgnoredApp('nordpass.exe', 'NordPass', preset: true),
  IgnoredApp('protonpass.exe', 'Proton Pass', preset: true),
  IgnoredApp('keeperpasswordmanager.exe', 'Keeper', preset: true),
];

/// A Windows id is an executable name; a Mac bundle id never ends in ".exe".
bool appIdIsForWindows(String appId) => appId.toLowerCase().endsWith('.exe');

const maxAppIdLength = 255;
const maxAppNameLength = 100;

/// What the stores accept (the same limits as the table's CHECKs); anything
/// else is an [ArgumentError] that carries no text.
void checkIgnoredApp(IgnoredApp app) {
  final idLength = app.appId.runes.length;
  final nameLength = app.displayName.runes.length;
  if (idLength < 1 || idLength > maxAppIdLength) {
    throw ArgumentError.value(idLength, 'appId.length');
  }
  if (nameLength < 1 || nameLength > maxAppNameLength) {
    throw ArgumentError.value(nameLength, 'displayName.length');
  }
}

/// Where the ignore list is kept: the `ignored_apps` table (schema version 4)
/// on the history's encrypted connection, or memory only.
abstract interface class IgnoredAppStore {
  /// In the order they were added.
  List<IgnoredApp> list();

  /// Adds [app] at the end. False if that app id is already on the list.
  bool add(IgnoredApp app);

  /// Removes an app and returns it so Undo can add it back, or null.
  IgnoredApp? remove(String appId);

  /// Puts back every preset app that is missing ("Restore preset list").
  void restorePresets();
}

class MemoryIgnoredAppStore implements IgnoredAppStore {
  final _apps = <IgnoredApp>[...presetIgnoredApps];

  @override
  List<IgnoredApp> list() => List.unmodifiable(_apps);

  @override
  bool add(IgnoredApp app) {
    checkIgnoredApp(app);
    if (_apps.any((a) => a.appId == app.appId)) return false;
    _apps.add(app);
    return true;
  }

  @override
  IgnoredApp? remove(String appId) {
    final i = _apps.indexWhere((a) => a.appId == appId);
    return i < 0 ? null : _apps.removeAt(i);
  }

  @override
  void restorePresets() {
    for (final p in presetIgnoredApps) {
      if (!_apps.any((a) => a.appId == p.appId)) _apps.add(p);
    }
  }
}

/// The `ignored_apps` table. The connection belongs to the history store.
class SqliteIgnoredAppStore implements IgnoredAppStore {
  SqliteIgnoredAppStore(this._db);

  final Database _db;

  @override
  List<IgnoredApp> list() => [
    for (final r in _db.select(
      'SELECT app_id, display_name, preset FROM ignored_apps ORDER BY id',
    ))
      IgnoredApp(
        r['app_id'] as String,
        r['display_name'] as String,
        preset: r['preset'] == 1,
      ),
  ];

  @override
  bool add(IgnoredApp app) {
    checkIgnoredApp(app);
    _db.execute(
      'INSERT INTO ignored_apps (app_id, display_name, preset) '
      'VALUES (?, ?, ?) ON CONFLICT (app_id) DO NOTHING',
      [app.appId, app.displayName, app.preset ? 1 : 0],
    );
    return _db.updatedRows > 0;
  }

  @override
  IgnoredApp? remove(String appId) {
    final rows = _db.select(
      'DELETE FROM ignored_apps WHERE app_id = ? '
      'RETURNING app_id, display_name, preset',
      [appId],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return IgnoredApp(
      r['app_id'] as String,
      r['display_name'] as String,
      preset: r['preset'] == 1,
    );
  }

  @override
  void restorePresets() {
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final p in presetIgnoredApps) {
        _db.execute(
          'INSERT INTO ignored_apps (app_id, display_name, preset) '
          'VALUES (?, ?, 1) ON CONFLICT (app_id) DO NOTHING',
          [p.appId, p.displayName],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      if (!_db.autocommit) {
        try {
          _db.execute('ROLLBACK');
        } catch (_) {}
      }
      rethrow;
    }
  }
}
