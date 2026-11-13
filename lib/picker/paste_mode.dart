/// The `paste_mode` setting: send Cmd+V / Ctrl+V ([auto]) or only copy.
/// The one place its stored values are defined: the picker, the export and
/// the import all read them from here.
enum PasteMode {
  auto('auto'),
  copyOnly('copy_only');

  const PasteMode(this.stored);
  final String stored;

  /// The mode stored as [text], or null for anything else.
  static PasteMode? fromStored(String? text) {
    for (final m in values) {
      if (m.stored == text) return m;
    }
    return null;
  }

  /// What the picker uses: anything but `copy_only` is [auto].
  static PasteMode parse(String? text) =>
      text == copyOnly.stored ? copyOnly : auto;
}
