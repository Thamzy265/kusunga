import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/data_eraser.dart';
import '../../data/export_format.dart';
import '../../data/your_data_service.dart';
import '../../history/history_service.dart';
import '../../history/ui/history_screen.dart' show showClearHistoryDialog;
import '../../log/app_log.dart';
import '../../theme/tokens.dart';
import '../../ui/section_heading.dart';

// Copy from the UI spec (`docs/ui/your-data.md`, "Copy"), and the lead's
// rulings G2 and G5 (2026-11-12).
const _kHeading = 'Your data';
const _kExport = 'Export…';
const _kImport = 'Import…';
const _kChecking = 'Checking the file…';
const _kDeleteHistory = 'Delete all history…';
const _kDeleteEverything = 'Delete everything…';
const _kExportHelp =
    'Export saves your snippets, and history if you choose, to a file. '
    "The file isn't encrypted.";
const _kMemoryOnlyHelp = "History isn't saved right now.";
const _kImportOff =
    "Import isn't available right now, because history isn't being saved.";
const _deleteHelp =
    'Delete everything removes all Kusunga data from this computer, '
    'including its key.';
const _kExportTitle = 'Export your data';
const _kExportText = 'Your snippets and settings will be saved to a file.';
const _kExportWarning =
    "The file isn't encrypted. Anyone who opens it can read it.";
const _kSave = 'Save…';
const _kSaving = 'Saving…';
const _kExportFailed = "Couldn't save the export. Try again.";
const _kRefused =
    "This file can't be imported. It isn't a Kusunga export, or it is "
    'damaged.';
const _kUseSettings = 'Also use the settings in this file';
const _kImporting = 'Importing…';
const _kNothing = 'This file has nothing to import.';
// Lead ruling R4 (2026-11-13).
const _kSettingsOnly =
    'This file has settings and ignored apps, but no snippets or history.';
const _kImportFailed = "Couldn't import. Nothing was changed.";
const _kDeleteTitle = 'Delete everything?';
const _kDeleteIntro = 'This removes from this computer:';
const _kDeleteOutro =
    "Launch at login is turned off, and Kusunga quits. This can't be "
    'undone. Export first if you want a copy.';
const _kDeleting = 'Deleting…';
const _kDeleted = 'Everything is deleted. Kusunga will now quit.';
const _kDeleteFailed =
    "Couldn't delete everything. Nothing was deleted. Try again.";
// The keychain never answered (T5; lead's wording, 2026-11-12).
const _kDeleteStuck =
    "Kusunga couldn't confirm whether its key was deleted, so it has "
    'stopped recording and will now quit. Open Kusunga again. If your '
    'snippets and history are still there, try Delete everything again.';

String _items(int n) => n == 1 ? '1 history item' : '$n history items';
String _snippets(int n) => n == 1 ? '1 snippet' : '$n snippets';

/// "Exported 12 snippets" / "Exported 12 snippets and 200 history items".
String exportedMessage(int snippets, int? history) => history == null
    ? 'Exported ${_snippets(snippets)}'
    : 'Exported ${_snippets(snippets)} and ${_items(history)}';

/// The import summary, with the sentences for what was skipped when they
/// apply (spec "Copy"; lead ruling G5).
String importedMessage(ImportCounts c) {
  final onlySettings =
      c.settingsApplied && c.snippetsAdded == 0 && c.historyAdded == 0;
  final parts = [
    // Lead copy, R8 (2026-11-13): nothing added, but the settings were.
    if (onlySettings) 'Imported the settings and ignored apps in this file.',
    if (!onlySettings)
      'Imported ${_snippets(c.snippetsAdded)} and ${_items(c.historyAdded)}.',
    if (c.snippetsAlreadyHere == 1) '1 snippet was already here.',
    if (c.snippetsAlreadyHere > 1)
      '${c.snippetsAlreadyHere} snippets were already here.',
    // Lead copy, R9 (2026-11-13).
    if (c.historyAlreadyHere == 1) '1 history item was already here.',
    if (c.historyAlreadyHere > 1)
      '${c.historyAlreadyHere} history items were already here.',
    if (c.shortcutsDropped == 1)
      '1 shortcut was already used, so that snippet has none.',
    if (c.shortcutsDropped > 1)
      '${c.shortcutsDropped} shortcuts were already used, so those snippets '
          'have none.',
    if (c.historyTooOld == 1)
      "1 history item was older than your auto-delete time and wasn't "
          'added.',
    if (c.historyTooOld > 1)
      '${c.historyTooOld} history items were older than your auto-delete '
          "time and weren't added.",
    // An import never deletes history (R1; lead copy, 2026-11-13).
    if (c.historyNoRoom == 1)
      "1 history item didn't fit under your history limit and wasn't added.",
    if (c.historyNoRoom > 1)
      "${c.historyNoRoom} history items didn't fit under your history limit "
          "and weren't added.",
    if (c.limitKept && c.expiryKept)
      "Your history limit and auto-delete weren't changed, because that "
          'would delete items. Change them in Settings.',
    if (c.limitKept && !c.expiryKept)
      "Your history limit wasn't changed, because that would delete items. "
          'Change it in Settings.',
    if (c.expiryKept && !c.limitKept)
      "Your auto-delete time wasn't changed, because that would delete "
          'items. Change it in Settings.',
  ];
  return parts.join(' ');
}

/// "Everything is deleted. 1 file couldn't be removed, but it can't be
/// read any more."
String partialMessage(int files) => files == 1
    ? "Everything is deleted. 1 file couldn't be removed, but it can't be "
          'read any more.'
    : "Everything is deleted. $files files couldn't be removed, but they "
          "can't be read any more.";

/// "Everything is deleted. 1 file couldn't be removed." when something
/// left may still be read: a log, or anything that isn't an encrypted
/// database file whose key is gone (lead ruling R7a, 2026-11-13).
String plainPartialMessage(int files) => files == 1
    ? "Everything is deleted. 1 file couldn't be removed."
    : "Everything is deleted. $files files couldn't be removed.";

/// The partial message in a debug data profile (T10; lead's wording,
/// 2026-11-12). The profile shares the key, which is never deleted there,
/// so a file left behind can still be read.
String profilePartialMessage(int files) => files == 1
    ? "Everything is deleted. 1 file in this test profile couldn't be "
          'removed.'
    : "Everything is deleted. $files files in this test profile couldn't be "
          'removed.';

/// What the Your data section needs from the app (M1.8).
class YourDataSetup {
  const YourDataSetup({
    required this.files,
    required this.log,
    required this.eraser,
    required this.quit,
    this.afterImport,
  });

  final FilePort files;
  final ErrorLog log;

  /// Delete everything for this session's data (default folder, profile,
  /// or nothing on disk).
  final DataEraser Function() eraser;

  /// Quits Kusunga after Delete everything (D6 A).
  final Future<void> Function() quit;

  /// An import applied the file's settings: typed shortcuts and the picker
  /// read theirs again.
  final Future<void> Function()? afterImport;
}

/// Settings › Your data (M1.8, spec `docs/ui/your-data.md`): Export…,
/// Import…, Delete all history… and Delete everything….
class YourDataSection extends StatefulWidget {
  const YourDataSection({
    super.key,
    required this.service,
    required this.setup,
    required this.toast,
  });

  final HistoryService service;
  final YourDataSetup setup;

  /// Shows a toast in the Settings tab; [long] for a summary of several
  /// sentences.
  final void Function(String message, {bool long}) toast;

  @override
  State<YourDataSection> createState() => _YourDataSectionState();
}

class _YourDataSectionState extends State<YourDataSection> {
  late YourDataService _data = _build();
  var _checking = false;
  var _checkingSlow = false;
  Timer? _slowTimer;

  YourDataService _build() => YourDataService(
    history: widget.service,
    log: widget.setup.log,
    files: widget.setup.files,
  );

  HistoryService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
  }

  @override
  void didUpdateWidget(YourDataSection old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service || old.setup != widget.setup) {
      old.service.removeListener(_changed);
      widget.service.addListener(_changed);
      _data = _build();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _slowTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    final result = await showDialog<ExportSaved>(
      context: context,
      builder: (context) =>
          _ExportDialog(data: _data, historyCount: _service.items.length),
    );
    if (result != null && mounted) {
      widget.toast(exportedMessage(result.snippets, result.history));
    }
  }

  Future<void> _import() async {
    setState(() {
      _checking = true;
      _checkingSlow = false;
    });
    // Announced only when the check takes more than 1 second (spec).
    _slowTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _checking) setState(() => _checkingSlow = true);
    });
    final check = await _data.checkImport();
    _slowTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkingSlow = false;
    });
    switch (check) {
      case ImportCancelled():
        return;
      case ImportRefused():
        widget.toast(_kRefused);
      case ImportReady():
        final done = await showDialog<_ImportClosed>(
          context: context,
          builder: (context) => _ImportDialog(data: _data, ready: check),
        );
        if (done == null || !mounted) return;
        widget.toast(importedMessage(done.counts), long: true);
        if (done.appliedSettings) await widget.setup.afterImport?.call();
    }
  }

  Future<void> _deleteAllHistory() async {
    if (await showClearHistoryDialog(context, _service)) {
      _service.deleteAllHistory();
    }
  }

  Future<void> _deleteEverything() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _DeleteEverythingDialog(service: _service, setup: widget.setup),
    );
    if (quit == true) await widget.setup.quit();
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final canImport = _service.canImport;
    Widget button(String id, String label, VoidCallback? onPressed) =>
        Semantics(
          identifier: id,
          child: OutlinedButton(
            style: ButtonStyle(
              overlayColor: WidgetStatePropertyAll(t.surfaceHover),
              minimumSize: const WidgetStatePropertyAll(Size(24, 40)),
            ),
            onPressed: onPressed,
            child: Text(label),
          ),
        );
    Widget pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, box) {
        // 320 px (360 px at 200% text): one button per row, full width.
        if (box.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              a,
              SizedBox(height: KusungaTokens.space2),
              b,
            ],
          );
        }
        return Wrap(
          spacing: KusungaTokens.space2,
          runSpacing: KusungaTokens.space2,
          children: [a, b],
        );
      },
    );
    Widget caption(String text) => Padding(
      padding: EdgeInsets.only(top: KusungaTokens.space1),
      child: Text(
        text,
        style: KusungaTokens.caption.copyWith(color: t.textMuted),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(_kHeading),
        SizedBox(height: KusungaTokens.space2),
        pair(
          button('your-data-export', _kExport, _exportPressed),
          button(
            'your-data-import',
            _checking ? _kChecking : _kImport,
            canImport && !_checking ? _importPressed : null,
          ),
        ),
        caption(_kExportHelp),
        if (_service.keychainUnusable) caption(_kMemoryOnlyHelp),
        if (!canImport) caption(_kImportOff),
        if (_checkingSlow)
          Semantics(
            liveRegion: true,
            label: _kChecking,
            child: const SizedBox(width: 1, height: 1),
          ),
        SizedBox(height: KusungaTokens.space3),
        pair(
          button(
            'your-data-delete-history',
            _kDeleteHistory,
            _service.items.isEmpty ? null : _deleteHistoryPressed,
          ),
          button(
            'your-data-delete-everything',
            _kDeleteEverything,
            _deleteEverythingPressed,
          ),
        ),
        caption(_deleteHelp),
      ],
    );
  }

  void _exportPressed() => unawaited(_export());
  void _importPressed() => unawaited(_import());
  void _deleteHistoryPressed() => unawaited(_deleteAllHistory());
  void _deleteEverythingPressed() => unawaited(_deleteEverything());
}

/// An error in a dialog: announced when it appears.
Widget _error(KusungaTokens t, String text) => Padding(
  padding: EdgeInsets.only(top: KusungaTokens.space2),
  child: Semantics(
    container: true,
    liveRegion: true,
    child: Text(text, style: KusungaTokens.body.copyWith(color: t.danger)),
  ),
);

/// Escape and the barrier do nothing while [busy] (input is ignored).
Widget _blockWhile(bool busy, Widget child) =>
    PopScope(canPop: !busy, child: child);

Widget _tick({
  required String id,
  required String label,
  required bool value,
  required ValueChanged<bool>? onChanged,
}) => MergeSemantics(
  child: Semantics(
    identifier: id,
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged(!value),
      canRequestFocus: false,
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
          ),
          Expanded(child: Text(label)),
        ],
      ),
    ),
  ),
);

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.data, required this.historyCount});

  final YourDataService data;
  final int historyCount;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  var _includeHistory = false;
  var _saving = false;
  var _failed = false;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    final result = await widget.data.export(includeHistory: _includeHistory);
    if (!mounted) return;
    switch (result) {
      case ExportSaved():
        Navigator.of(context).pop(result);
      case ExportCancelled():
        setState(() => _saving = false);
      case ExportFailed():
        setState(() {
          _saving = false;
          _failed = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final n = widget.historyCount;
    final label = n == 0
        ? 'Include history (no items)'
        : 'Include history ($n ${n == 1 ? 'item' : 'items'})';
    return _blockWhile(
      _saving,
      AlertDialog(
        title: const Text(_kExportTitle),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(_kExportText),
            SizedBox(height: KusungaTokens.space2),
            _tick(
              id: 'export-include-history',
              label: label,
              value: _includeHistory,
              onChanged: n == 0 || _saving
                  ? null
                  : (v) => setState(() => _includeHistory = v),
            ),
            SizedBox(height: KusungaTokens.space2),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: KusungaTokens.space3,
                vertical: KusungaTokens.space2,
              ),
              decoration: BoxDecoration(
                color: t.bannerWarnBg,
                borderRadius: BorderRadius.circular(KusungaTokens.radius2),
              ),
              child: Text(
                _kExportWarning,
                style: KusungaTokens.body.copyWith(color: t.bannerWarnText),
              ),
            ),
            if (_failed) _error(t, _kExportFailed),
          ],
        ),
        actions: [
          Semantics(
            identifier: 'export-cancel',
            child: TextButton(
              autofocus: true,
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          Semantics(
            identifier: 'export-save',
            child: FilledButton(
              onPressed: _saving ? null : () => unawaited(_save()),
              child: Text(_saving ? _kSaving : _kSave),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the import dialog closes with.
class _ImportClosed {
  const _ImportClosed(this.counts, {required this.appliedSettings});
  final ImportCounts counts;
  final bool appliedSettings;
}

/// "a-long-name…end.json": the middle is cut so the end (the date and the
/// extension) still shows.
String _middle(String name, int max) {
  final runes = name.runes.toList();
  if (runes.length <= max) return name;
  final head = (max - 1) ~/ 2;
  final tail = max - 1 - head;
  return '${String.fromCharCodes(runes.take(head))}…'
      '${String.fromCharCodes(runes.skip(runes.length - tail))}';
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.data, required this.ready});

  final YourDataService data;
  final ImportReady ready;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  var _useSettings = false;
  var _importing = false;
  var _failed = false;

  Future<void> _run() async {
    setState(() {
      _importing = true;
      _failed = false;
    });
    // One frame so "Importing…" shows before the write.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final apply = _useSettings && widget.ready.hasSettings;
    final result = widget.data.runImport(widget.ready, applySettings: apply);
    switch (result) {
      case ImportDone(:final counts):
        Navigator.of(
          context,
        ).pop(_ImportClosed(counts, appliedSettings: apply));
      case ImportFailedResult():
        setState(() {
          _importing = false;
          _failed = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final ready = widget.ready;
    final title = Text(
      'Import from ${_middle(ready.fileName, 40)}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    if (ready.isEmpty) {
      return AlertDialog(
        title: title,
        content: const Text(_kNothing),
        actions: [
          Semantics(
            identifier: 'import-empty-close',
            child: TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      );
    }
    return _blockWhile(
      _importing,
      AlertDialog(
        title: title,
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ready.settingsOnly
                  ? _kSettingsOnly
                  : 'Import ${_snippets(ready.snippets)} and '
                        '${_items(ready.historyFor(applySettings: _useSettings))}? '
                        'Nothing you have now will be changed or removed.',
            ),
            if (ready.hasSettings) ...[
              SizedBox(height: KusungaTokens.space2),
              _tick(
                id: 'import-use-settings',
                label: _kUseSettings,
                value: _useSettings,
                onChanged: _importing
                    ? null
                    : (v) => setState(() => _useSettings = v),
              ),
            ],
            if (_failed) _error(t, _kImportFailed),
          ],
        ),
        actions: [
          Semantics(
            identifier: 'import-cancel',
            child: TextButton(
              autofocus: true,
              onPressed: _importing ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          Semantics(
            identifier: 'import-confirm',
            child: FilledButton(
              // A settings-only file imports nothing unless ticked (R4).
              onPressed: _importing || (ready.settingsOnly && !_useSettings)
                  ? null
                  : () => unawaited(_run()),
              child: Text(_importing ? _kImporting : 'Import'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteEverythingDialog extends StatefulWidget {
  const _DeleteEverythingDialog({required this.service, required this.setup});

  final HistoryService service;
  final YourDataSetup setup;

  @override
  State<_DeleteEverythingDialog> createState() =>
      _DeleteEverythingDialogState();
}

class _DeleteEverythingDialogState extends State<_DeleteEverythingDialog> {
  var _deleting = false;
  var _failed = false;
  String? _done;

  // Read once when the dialog opens: what the list says goes.
  late final int _history = widget.service.items.length;
  late final int _snippetCount = widget.service.snippets.items.length;

  Future<void> _run() async {
    setState(() {
      _deleting = true;
      _failed = false;
    });
    final eraser = widget.setup.eraser();
    final result = await eraser.run(widget.service);
    if (!mounted) return;
    setState(() {
      _deleting = false;
      switch (result) {
        // The key delete may still complete: recording stays stopped, and
        // the only way on is to quit (T5).
        case EraseFailed(stuck: true):
          _done = _kDeleteStuck;
        case EraseFailed():
          _failed = true;
        case Erased(:final filesLeft, :final leftUnreadable):
          _done = filesLeft == 0
              ? _kDeleted
              : eraser.target is ProfileEraseTarget
              ? profilePartialMessage(filesLeft)
              : leftUnreadable
              ? partialMessage(filesLeft)
              : plainPartialMessage(filesLeft);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final done = _done;
    if (done != null) {
      // Done, or the key delete never answered: Kusunga quits after OK;
      // Escape does the same.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(true);
        },
        child: AlertDialog(
          content: Semantics(
            container: true,
            liveRegion: true,
            child: Text(done),
          ),
          actions: [
            Semantics(
              identifier: 'delete-everything-ok',
              child: FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      );
    }
    final history = _history == 1 ? '1 item' : '$_history items';
    return _blockWhile(
      _deleting,
      AlertDialog(
        title: const Text(_kDeleteTitle),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(_kDeleteIntro),
            Text('• all history ($history)'),
            Text('• all snippets ($_snippetCount)'),
            const Text('• your settings and ignored apps'),
            const Text("• Kusunga's key and log"),
            SizedBox(height: KusungaTokens.space2),
            const Text(_kDeleteOutro),
            if (_failed) _error(t, _kDeleteFailed),
          ],
        ),
        actions: [
          Semantics(
            identifier: 'delete-everything-cancel',
            child: TextButton(
              autofocus: true,
              onPressed: _deleting
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ),
          Semantics(
            identifier: 'delete-everything-confirm',
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.danger,
                foregroundColor: t.surface,
              ),
              onPressed: _deleting ? null : () => unawaited(_run()),
              child: Text(_deleting ? _kDeleting : 'Delete everything'),
            ),
          ),
        ],
      ),
    );
  }
}
