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

/// Schema version 1: the first version of the store.
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
];
