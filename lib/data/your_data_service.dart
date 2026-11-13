import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../history/history_service.dart';
import '../log/app_log.dart';
import 'export_format.dart';

/// The OS save and open dialogs (M1.8). A seam, so tests need no dialog.
abstract interface class FilePort {
  /// The path the user chose to save to, or null if they cancelled.
  Future<String?> pickSavePath(String suggestedName);

  /// The `.json` file the user chose to open, or null if they cancelled.
  Future<String?> pickOpenPath();
}

/// `file_selector`: NSSavePanel / NSOpenPanel on the Mac (the sandbox then
/// lets Kusunga read or write only that file), IFileDialog on Windows.
class FileSelectorPort implements FilePort {
  static const _json = XTypeGroup(
    label: 'JSON',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  @override
  Future<String?> pickSavePath(String suggestedName) async =>
      (await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [_json],
      ))?.path;

  @override
  Future<String?> pickOpenPath() async =>
      (await openFile(acceptedTypeGroups: const [_json]))?.path;
}

typedef ExportWriter = void Function(String path, List<int> bytes);

/// The temporary file for an export to [path]: next to it, with 128 random
/// bits in its name, so nobody can put a file or a link there first (T7).
String exportTempPath(String path, [Random? random]) {
  final r = random ?? Random.secure();
  final hex = [
    for (var i = 0; i < 16; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  return '$path.kusunga-tmp-$hex';
}

/// Writes the export so a failure never leaves half a file: to a temporary
/// file next to [path], then renamed over it. The temporary file has a name
/// nobody can guess, is made only if nothing is there yet, and is never
/// written through a link. Where it can't be made (the Mac sandbox allows
/// only the file the user picked), the file is written directly, never
/// through a link, and removed again if the write fails. Nothing is ever
/// written to any other path.
void writeExportFile(String path, List<int> bytes, {Random? random}) {
  _removeLeftovers(path);
  final temp = File(exportTempPath(path, random));
  try {
    // O_CREAT | O_EXCL: fails if anything is there, a link included.
    temp.createSync(exclusive: true);
  } on FileSystemException {
    _writeDirect(File(path), bytes);
    return;
  }
  try {
    _writeInto(temp, bytes);
    temp.renameSync(path);
  } catch (_) {
    _removeQuietly(temp);
    rethrow;
  }
}

/// Writes into [file], which was just made empty. It is opened without
/// truncating, and written only once it is known to still be a plain file:
/// a link put in its place is never written through.
void _writeInto(File file, List<int> bytes) {
  final out = file.openSync(mode: FileMode.writeOnlyAppend);
  try {
    _refuseLink(file);
    out.writeFromSync(bytes);
    out.flushSync();
  } finally {
    out.closeSync();
  }
}

/// Writes [target] in place. Only once Kusunga has opened it for writing
/// (which empties it) is there half a file to remove on a failure: a file
/// it couldn't open, such as a read-only one, is left as it was (R3).
void _writeDirect(File target, List<int> bytes) {
  _refuseLink(target);
  final out = target.openSync(mode: FileMode.writeOnly);
  try {
    out.writeFromSync(bytes);
    out.flushSync();
    out.closeSync();
  } catch (_) {
    try {
      out.closeSync();
    } catch (_) {}
    _removeQuietly(target);
    rethrow;
  }
}

void _refuseLink(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw FileSystemException('a link, not a file', file.path);
  }
}

/// Temporary files that an earlier export to the same [path] left behind
/// (a crash while writing): only Kusunga's own names, only plain files.
/// Links are never followed or removed. `<name>.kusunga-tmp` is the name
/// builds before T7 used.
void _removeLeftovers(String path) {
  final name = RegExp.escape(p.basename(path));
  final leftover = RegExp('^$name\\.kusunga-tmp(-[0-9a-f]{32})?\$');
  try {
    for (final e in File(path).parent.listSync(followLinks: false)) {
      if (e is File && leftover.hasMatch(p.basename(e.path))) {
        _removeQuietly(e);
      }
    }
  } catch (_) {
    // The folder can't be listed (the Mac sandbox): nothing to tidy.
  }
}

void _removeQuietly(File file) {
  try {
    if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      file.deleteSync();
    }
  } catch (_) {}
}

sealed class ExportResult {
  const ExportResult();
}

/// The save dialog was cancelled: nothing happens, no message.
class ExportCancelled extends ExportResult {
  const ExportCancelled();
}

class ExportSaved extends ExportResult {
  const ExportSaved({required this.snippets, this.history});
  final int snippets;

  /// Null when history was not included.
  final int? history;
}

/// "Couldn't save the export. Try again." No file was left.
class ExportFailed extends ExportResult {
  const ExportFailed();
}

sealed class ImportCheck {
  const ImportCheck();
}

class ImportCancelled extends ImportCheck {
  const ImportCancelled();
}

/// "This file can't be imported. It isn't a Kusunga export, or it is
/// damaged."
class ImportRefused extends ImportCheck {
  const ImportRefused();
}

/// A checked file, ready for the confirm dialog.
class ImportReady extends ImportCheck {
  const ImportReady({
    required this.bundle,
    required this.fileName,
    required this.snippets,
    required this.history,
    int? historyWithSettings,
  }) : historyWithSettings = historyWithSettings ?? history;

  final ExportBundle bundle;

  /// Only the name, shown in the confirm title; never logged.
  final String fileName;

  /// Snippets in the file.
  final int snippets;

  /// History rows the import will add without the file's settings: not
  /// lines older than the auto-delete time (lead ruling G5), that repeat
  /// another line or an item already here, or that the limit would trim
  /// (T4).
  final int history;

  /// The same with the file's settings applied: its limit and auto-delete
  /// time decide instead.
  final int historyWithSettings;

  /// The history count for the confirm text, as the tick box stands.
  int historyFor({required bool applySettings}) =>
      applySettings && hasSettings ? historyWithSettings : history;

  bool get hasSettings => bundle.hasSettings;

  /// No snippet and no history item to add, with or without its settings.
  bool get _noItems =>
      snippets == 0 && history == 0 && historyFor(applySettings: true) == 0;

  /// "This file has nothing to import": no items, and no settings or
  /// ignored apps either.
  bool get isEmpty => _noItems && !hasSettings;

  /// Only settings or ignored apps (lead ruling R4, 2026-11-13): "This file
  /// has settings and ignored apps, but no snippets or history." It can be
  /// imported, but only with "Also use the settings in this file" ticked.
  bool get settingsOnly => _noItems && hasSettings;
}

sealed class ImportResult {
  const ImportResult();
}

class ImportDone extends ImportResult {
  const ImportDone(this.counts);
  final ImportCounts counts;
}

/// "Couldn't import. Nothing was changed."
class ImportFailedResult extends ImportResult {
  const ImportFailedResult();
}

/// Export and import for the Your data section (M1.8,
/// `docs/design/your-data.md`). Logs codes and numbers only: never a file
/// name, a path or anything from a file.
class YourDataService {
  YourDataService({
    required this.history,
    required this._log,
    required this._files,
    DateTime Function()? now,
    ExportWriter? writer,
  }) : _now = now ?? DateTime.now,
       _write = writer ?? writeExportFile;

  final HistoryService history;
  final ErrorLog _log;
  final FilePort _files;
  final DateTime Function() _now;
  final ExportWriter _write;

  /// Asks where to save, then writes what the user chose (R1). The save
  /// dialog opens only after the warning was shown in Kusunga's own dialog.
  Future<ExportResult> export({required bool includeHistory}) async {
    final String? path;
    try {
      path = await _files.pickSavePath(exportFileName(_now()));
    } catch (_) {
      _log.log(LogCode.exportFailed);
      return const ExportFailed();
    }
    if (path == null) return const ExportCancelled();
    try {
      final bundle = history.exportBundle(includeHistory: includeHistory);
      _write(path, utf8.encode(encodeExport(bundle, exportedAt: _now())));
      _log.log(LogCode.dataExported, bundle.snippets.length);
      final n = bundle.history?.length;
      if (n != null) _log.log(LogCode.dataExportedHistory, n);
      return ExportSaved(snippets: bundle.snippets.length, history: n);
    } catch (error) {
      _log.log(
        LogCode.exportFailed,
        error is FileSystemException ? error.osError?.errorCode : null,
      );
      return const ExportFailed();
    }
  }

  /// Asks for a file, then reads and checks it. Nothing is changed yet.
  Future<ImportCheck> checkImport() async {
    final String? path;
    try {
      path = await _files.pickOpenPath();
    } catch (_) {
      _log.log(LogCode.importRejected);
      return const ImportRefused();
    }
    if (path == null) return const ImportCancelled();
    try {
      final bundle = checkImportTimes(
        decodeImport(_read(path)),
        nowMs: _now().millisecondsSinceEpoch,
      );
      // Rows, not lines (T4); the old estimate only if that can't be
      // worked out, and then the import fails anyway.
      int rows({required bool applySettings}) =>
          history.historyToAdd(bundle, applySettings: applySettings) ??
          history.importableHistory(bundle);
      return ImportReady(
        bundle: bundle,
        fileName: File(path).uri.pathSegments.last,
        snippets: bundle.snippets.length,
        history: rows(applySettings: false),
        historyWithSettings: bundle.hasSettings
            ? rows(applySettings: true)
            : null,
      );
    } on ImportRejected catch (e) {
      _log.log(LogCode.importRejected, e.reason.number);
      return const ImportRefused();
    } catch (_) {
      // Unreadable (gone, no rights): refused like a damaged file.
      _log.log(LogCode.importRejected);
      return const ImportRefused();
    }
  }

  /// At most [maxImportBytes] + 1 bytes are read, so a huge file (or one
  /// that grows while it is read) is refused without loading it. Read in
  /// one go, like the export is written: 20 MB at most.
  static List<int> _read(String path) {
    final file = File(path).openSync();
    try {
      if (file.lengthSync() > maxImportBytes) {
        throw const ImportRejected(ImportRejectReason.tooLarge);
      }
      return file.readSync(maxImportBytes + 1);
    } finally {
      file.closeSync();
    }
  }

  /// Adds the checked file in one transaction (R2, R3).
  ImportResult runImport(ImportReady ready, {required bool applySettings}) {
    try {
      final c = history.importBundle(
        ready.bundle,
        applySettings: applySettings && ready.hasSettings,
      );
      _log.log(LogCode.dataImported, c.snippetsAdded);
      _log.log(LogCode.dataImportedHistory, c.historyAdded);
      _log.log(
        LogCode.dataImportSkipped,
        c.snippetsAlreadyHere +
            c.historyAlreadyHere +
            c.historyTooOld +
            c.historyNoRoom,
      );
      return ImportDone(c);
    } catch (_) {
      _log.log(LogCode.importFailed);
      return const ImportFailedResult();
    }
  }
}
