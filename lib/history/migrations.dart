/// One forward step of the database schema. Versions count from 1 with no
/// gaps. Never edit a migration that has shipped: add a new one.
class Migration {
  const Migration({
    required this.version,
    required this.statements,
    this.onRun,
  });

  final int version;
  final List<String> statements;

  /// Test hook: called just before the statements run.
  final void Function()? onRun;
}

/// Schema version 1: the first version of the store. Version 2 (M1.3) adds no
/// structure: the picker settings are rows of the `settings` table. The step
/// is recorded so that later migrations stay in order, and a version 1 build
/// leaves a version 2 file untouched. Version 3 (M1.4) adds the snippets
/// table and nothing else (expand only; `docs/design/saved-snippets.md`).
/// Version 4 (M1.5, `docs/design/typed-shortcuts.md`, "Data") adds the
/// nullable `snippets.shortcut` column with its unique index, the
/// `ignored_apps` table seeded with the preset password managers of both
/// systems, and the `typed_shortcuts_on` setting, off (expand only).
const kMigrations = <Migration>[
  Migration(
    version: 1,
    statements: [
      '''
CREATE TABLE clip_items (
  id INTEGER PRIMARY KEY,
  content TEXT NOT NULL CHECK (length(CAST(content AS BLOB)) BETWEEN 1 AND 1048576),
  kind TEXT NOT NULL CHECK (kind IN ('text', 'link')),
  content_hash BLOB NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  last_copied_at INTEGER NOT NULL
)''',
      'CREATE INDEX idx_clip_items_last_copied_at '
          'ON clip_items (last_copied_at DESC)',
      '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value INTEGER NOT NULL,
  CHECK (key != 'history_limit' OR value BETWEEN 10 AND 5000)
)''',
      "INSERT INTO settings (key, value) VALUES ('history_limit', 200)",
    ],
  ),
  Migration(version: 2, statements: []),
  Migration(
    version: 3,
    statements: [
      '''
CREATE TABLE snippets (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  content TEXT NOT NULL CHECK (length(CAST(content AS BLOB)) BETWEEN 1 AND 1048576),
  type TEXT NOT NULL CHECK (type IN ('phone', 'email', 'link', 'address', 'other')),
  position INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
      'CREATE INDEX idx_snippets_position ON snippets (position)',
    ],
  ),
  Migration(
    version: 4,
    statements: [
      '''
ALTER TABLE snippets ADD COLUMN shortcut TEXT
  CHECK (shortcut IS NULL OR (length(shortcut) BETWEEN 2 AND 32
         AND instr(shortcut, ' ') = 0 AND instr(shortcut, char(9)) = 0
         AND instr(shortcut, char(10)) = 0 AND instr(shortcut, char(13)) = 0))''',
      'CREATE UNIQUE INDEX idx_snippets_shortcut ON snippets (shortcut) '
          'WHERE shortcut IS NOT NULL',
      '''
CREATE TABLE ignored_apps (
  id INTEGER PRIMARY KEY,
  app_id TEXT NOT NULL UNIQUE CHECK (length(app_id) BETWEEN 1 AND 255),
  display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 100),
  preset INTEGER NOT NULL CHECK (preset IN (0, 1))
)''',
      // Literals, not built from `presetIgnoredApps`: a shipped migration
      // never changes (a test checks the two lists are the same).
      '''
INSERT INTO ignored_apps (app_id, display_name, preset) VALUES
  ('com.1password.1password', '1Password', 1),
  ('com.agilebits.onepassword7', '1Password 7', 1),
  ('com.bitwarden.desktop', 'Bitwarden', 1),
  ('org.keepassxc.keepassxc', 'KeePassXC', 1),
  ('com.apple.Passwords', 'Passwords', 1),
  ('1password.exe', '1Password', 1),
  ('bitwarden.exe', 'Bitwarden', 1),
  ('keepassxc.exe', 'KeePassXC', 1),
  ('keepass.exe', 'KeePass', 1)''',
      "INSERT INTO settings (key, value) VALUES ('typed_shortcuts_on', 0)",
    ],
  ),
];
