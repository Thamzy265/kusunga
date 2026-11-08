import 'dart:async';

import 'package:flutter/foundation.dart';

import '../log/app_log.dart';
import '../snippets/snippet_service.dart';
import 'ignored_apps.dart';
import 'typed_shortcuts_port.dart';

/// The setting that holds the switch: "1" on, "0" off (PM decision D3 A: off
/// until the user turns it on).
const typedShortcutsSetting = 'typed_shortcuts_on';

/// Kusunga itself is never offered in "Add app…": shortcuts never fire in it
/// anyway (skip rule 2).
const _ownAppIds = {'com.wnasoni.kusunga', 'kusunga.exe'};

/// A running app for the "Choose an app" list.
typedef RunningAppChoice = ({RunningApp app, bool added});

/// Typed shortcuts on the Dart side (design note, "Dart side"): keeps the
/// native table in step with the snippets, holds the switch, shows the
/// status, keeps the ignore list, and on a match reads the snippet and asks
/// native code to replace. It never sees a typed key (ADR 0004). Logs codes
/// only: never a shortcut, snippet text or app name.
class ShortcutService extends ChangeNotifier {
  ShortcutService({
    required this.port,
    required this._snippets,
    required IgnoredAppStore ignoredApps,
    required this._readSetting,
    required this._writeSetting,
    required this._log,
    required this.isWindows,
    required this.available,
    this._onCopied,
  }) : _ignored = ignoredApps;

  final TypedShortcutsPort port;
  final SnippetService _snippets;
  final IgnoredAppStore _ignored;
  final String? Function(String key) _readSetting;
  final bool Function(String key, String value) _writeSetting;
  final ErrorLog _log;
  final void Function()? _onCopied;
  final bool isWindows;

  /// False when snippets can't be opened (memory-only or incompatible
  /// database): the switch is disabled and nothing is watched.
  final bool available;

  StreamSubscription<TypedShortcutEvent>? _events;
  var _enabled = false;
  var _status = TypedShortcutStatus.off;
  var _busy = false;
  var _replacing = false;
  var _disposed = false;
  var _lastIgnoredFailed = false;
  List<({int id, String shortcut})>? _sentTable;
  List<IgnoredApp> _apps = const [];

  /// The switch as the user set it.
  bool get enabled => _enabled;
  TypedShortcutStatus get status => _status;

  /// A switch change is waiting for native code ("Starting…" after 300 ms).
  bool get busy => _busy;

  /// This system's ignored apps, in the order they were added.
  List<IgnoredApp> get ignoredApps => _apps;

  /// A preset app of this system is missing ("Restore preset list" shows).
  bool get canRestorePresets => presetIgnoredApps
      .where((p) => appIdIsForWindows(p.appId) == isWindows)
      .any((p) => !_apps.any((a) => a.appId == p.appId));

  /// The last change to the ignore list could not be saved.
  bool get lastIgnoredFailed => _lastIgnoredFailed;

  Future<void> start() async {
    _events = port.events.listen(_onEvent);
    _snippets.addListener(_syncTable);
    _loadIgnored();
    await port.setIgnored([for (final a in _apps) a.appId]);
    _syncTable();
    if (!available) return;
    _enabled = _readSetting(typedShortcutsSetting) == '1';
    if (_enabled) await _apply(true);
    _notify();
  }

  void _loadIgnored() {
    try {
      _apps = [
        for (final a in _ignored.list())
          if (appIdIsForWindows(a.appId) == isWindows) a,
      ];
    } catch (_) {
      _log.log(LogCode.readFailed);
    }
  }

  void _syncTable() {
    if (_disposed) return;
    final table = available
        ? _snippets.shortcutTable
        : const <({int id, String shortcut})>[];
    if (_sentTable != null && listEquals(_sentTable, table)) return;
    _sentTable = table;
    unawaited(port.setTable(table));
    _log.log(LogCode.shortcutTableSize, table.length);
  }

  /// Turns typed shortcuts on or off and saves the choice. Answers the
  /// status, or null if the switch can't be used. Never asks for a
  /// permission: on a Mac without one the answer is needsPermission and the
  /// UI shows the explanation card.
  Future<TypedShortcutStatus?> setEnabled(bool on) async {
    if (!available || _disposed) return null;
    _enabled = on;
    _writeSetting(typedShortcutsSetting, on ? '1' : '0');
    _notify();
    await _apply(on);
    return _status;
  }

  Future<void> _apply(bool on) async {
    _busy = true;
    _notify();
    TypedShortcutStatus status;
    try {
      status = await port.setEnabled(on);
    } catch (_) {
      status = on ? TypedShortcutStatus.failed : TypedShortcutStatus.off;
    }
    _busy = false;
    if (_disposed) return;
    // The switch moved again while native code was busy: that call wins.
    if (on == _enabled) _setStatus(status);
    // Always, so "Starting…" goes away even when the status is unchanged.
    _notify();
  }

  /// The explanation card's Continue: asks macOS (its own prompt), then
  /// tries again. True if typed shortcuts are on now.
  Future<bool> requestPermission() async {
    if (!available || !_enabled) return false;
    final granted = await port.requestListenAccess();
    if (_disposed) return false;
    if (granted) await _apply(true);
    return _status == TypedShortcutStatus.on;
  }

  Future<void> openSettings() => port.openInputMonitoringSettings();

  void _setStatus(TypedShortcutStatus status) {
    if (status == _status) return;
    _status = status;
    switch (status) {
      case TypedShortcutStatus.needsPermission:
        _log.log(LogCode.shortcutPermissionMissing);
      case TypedShortcutStatus.stopped:
      // Mac: the tap was turned off and could not be turned on again.
      // Windows: Windows removed the hook and it could not be put back (R1).
      case TypedShortcutStatus.failed:
        _log.log(
          isWindows ? LogCode.shortcutHookFailed : LogCode.shortcutTapFailed,
        );
      case TypedShortcutStatus.on:
      case TypedShortcutStatus.off:
      case TypedShortcutStatus.paused:
        break;
    }
    _notify();
  }

  void _onEvent(TypedShortcutEvent event) {
    if (_disposed) return;
    switch (event) {
      case ShortcutStatusChanged(:final status):
        if (_enabled && available) _setStatus(status);
      case ShortcutMatched(:final snippetId, :final deleteCount):
        unawaited(_replace(snippetId, deleteCount));
    }
  }

  Future<void> _replace(int snippetId, int deleteCount) async {
    if (!_enabled || !available || _replacing) return;
    final text = _snippets.textOf(snippetId);
    if (text == null) return;
    _replacing = true;
    ReplaceOutcome outcome;
    try {
      outcome = await port.replace(deleteCount, text);
    } catch (_) {
      outcome = ReplaceOutcome.failed;
    }
    _replacing = false;
    if (_disposed) return;
    switch (outcome) {
      case ReplaceOutcome.replaced:
        _log.log(LogCode.shortcutFired);
      case ReplaceOutcome.cancelled:
        _log.log(LogCode.shortcutCancelled);
      case ReplaceOutcome.copied:
        // The M1.3 fallback: the snippet is on the clipboard.
        _log.log(LogCode.pastePermissionMissing);
        _onCopied?.call();
      case ReplaceOutcome.failed:
        _log.log(LogCode.writeFailed);
    }
  }

  // ---- The ignore list ----

  bool _changeIgnored(void Function() change) {
    try {
      change();
      _lastIgnoredFailed = false;
    } catch (_) {
      _log.log(LogCode.writeFailed);
      _lastIgnoredFailed = true;
      _notify();
      return false;
    }
    _loadIgnored();
    unawaited(port.setIgnored([for (final a in _apps) a.appId]));
    _notify();
    return true;
  }

  /// Removes an app and returns it for Undo, or null if that failed.
  IgnoredApp? removeApp(String appId) {
    IgnoredApp? removed;
    final ok = _changeIgnored(() => removed = _ignored.remove(appId));
    return ok ? removed : null;
  }

  /// Undo: puts a removed app back (at the end of the list).
  bool undoRemove(IgnoredApp app) => _changeIgnored(() => _ignored.add(app));

  /// "Add app…": adds a running app. False if that failed.
  bool addApp(RunningApp app) => _changeIgnored(
    () => _ignored.add(
      IgnoredApp(
        app.appId,
        app.name.length > maxAppNameLength
            ? String.fromCharCodes(app.name.runes.take(maxAppNameLength))
            : app.name,
      ),
    ),
  );

  /// "Restore preset list". False if that failed.
  bool restorePresets() => _changeIgnored(_ignored.restorePresets);

  /// The apps running now, by name, without Kusunga; each marked if it is
  /// already on the list.
  Future<List<RunningAppChoice>> runningApps() async {
    final apps = await port.runningApps();
    final listed = {for (final a in _apps) a.appId};
    final choices = <RunningAppChoice>[
      for (final a in apps)
        if (!_ownAppIds.contains(a.appId.toLowerCase()) &&
            appIdIsForWindows(a.appId) == isWindows)
          (app: a, added: listed.contains(a.appId)),
    ];
    choices.sort(
      (a, b) => a.app.name.toLowerCase().compareTo(b.app.name.toLowerCase()),
    );
    return choices;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _snippets.removeListener(_syncTable);
    unawaited(_events?.cancel());
    super.dispose();
  }
}
