import 'dart:async';

import 'package:flutter/foundation.dart';

import '../history/history_service.dart';
import '../log/app_log.dart';
import 'picker_port.dart';
import 'picker_search.dart';
import 'shortcut.dart';

/// What the one window is showing: the history screen, the picker, or the
/// small "Copied" toast.
enum WindowMode { manage, picker, toast }

enum ShortcutProblem {
  /// Another app owns the combination (or it could not be registered).
  taken,
}

/// The answer to "change the shortcut".
enum ShortcutChange {
  saved,

  /// Another app owns it. The old shortcut still works.
  taken,

  /// No Cmd, Ctrl or Alt in it.
  needModifier,

  /// Cmd/Ctrl with V, C, X, A or Z alone: needed for copy and paste.
  reserved,

  /// It works now but could not be saved, so it is gone after a quit.
  notSaved,
}

/// The `paste_mode` setting: send Cmd+V / Ctrl+V ([auto]) or only copy.
enum PasteMode {
  auto('auto'),
  copyOnly('copy_only');

  const PasteMode(this.stored);
  final String stored;

  static PasteMode parse(String? text) =>
      text == copyOnly.stored ? copyOnly : auto;
}

enum ToastKind { copied, copiedNoPermission, copiedElevated, copyFailed }

/// Where a pasted text came from: the number logged with `pasteSource`.
enum _PasteSource {
  history(0),
  snippet(1);

  const _PasteSource(this.logNumber);
  final int logNumber;
}

/// Everything the picker, the toast and the settings in the main window need
/// to know, and the paste flow (design note, "How paste works"): the Dart half
/// of what native code does. All words the user sees come from the UI spec
/// (`docs/ui/history-picker.md`).
class PickerController extends ChangeNotifier {
  PickerController({
    required this.port,
    required this._log,
    required this.isMac,
    this.toastDuration = const Duration(seconds: 4),
  }) : _shortcut = PickerShortcut.defaultFor(isMac: isMac);

  final PickerPort port;
  final ErrorLog _log;
  final bool isMac;
  final Duration toastDuration;

  /// The search index. It lives as long as the controller, not the picker, so
  /// opening the picker never rebuilds it; it is filled in small steps in the
  /// background whenever the history changes.
  final search = PickerSearch();

  /// The same for the Snippets tab (name and content).
  final snippetSearch = PickerSearch();
  Timer? _warmTimer;

  StreamSubscription<PickerNativeEvent>? _events;
  Future<void>? _starting;
  Timer? _toastTimer;
  WindowMode _mode = WindowMode.manage;
  PickerShortcut _shortcut;

  /// The shortcut registered with the system right now, if any. It differs
  /// from [_shortcut] when the shortcut the user wants is taken.
  PickerShortcut? _active;
  var _suspended = false;
  ShortcutProblem? _problem;
  HistoryService? _history;
  PasteMode _pasteMode = PasteMode.auto;
  ToastKind? _toast;
  var _card = false;
  var _help = false;
  var _pasting = false;
  var _unsavedShortcut = false;
  var _shortcutSaveFailed = false;
  var _disposed = false;

  WindowMode get mode => _mode;

  /// The shortcut the user wants (the one shown in the setting).
  PickerShortcut get shortcut => _shortcut;
  ShortcutProblem? get shortcutProblem => _problem;

  /// The shortcut in use could not be kept (memory-only history or a failed
  /// save), so it is gone after a quit.
  bool get shortcutSaveFailed => _shortcutSaveFailed;
  HistoryService? get history => _history;
  PasteMode get pasteMode => _pasteMode;
  ToastKind? get toast => _toast;

  /// The permission card ("Let Kusunga paste for you") is showing.
  bool get permissionCardVisible => _card;

  /// "Allow pasting" was pressed but macOS has not allowed it yet.
  bool get permissionHelpVisible => _help;

  String? get shortcutBannerText => _problem == null
      ? null
      : "Kusunga's shortcut ${_shortcut.display(isMac: isMac)} is used by "
            'another app. Choose another.';

  String? get toastText => switch (_toast) {
    null => null,
    ToastKind.copied => 'Copied — press ${isMac ? '⌘V' : 'Ctrl+V'} to paste.',
    ToastKind.copiedNoPermission =>
      'Copied — press ⌘V to paste. Allow pasting in Kusunga to do this for you.',
    ToastKind.copiedElevated =>
      "Copied — press Ctrl+V to paste. Kusunga can't paste into apps run as administrator.",
    ToastKind.copyFailed => "Couldn't copy. Try again.",
  };

  /// Listens to the native side and registers the default shortcut. Never
  /// throws. A second call does nothing.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _events = port.events.listen(_onEvent);
    final result = await port.registerShortcut(_shortcut);
    if (_disposed) return;
    _applyRegistration(_shortcut, result);
    _notify();
    await _logPermissions();
  }

  /// The permission state as one code and a number (design: codes only).
  Future<void> _logPermissions() async {
    // A diagnostic must never stop start-up or a paste: any error is dropped.
    try {
      final mask = await port.permissionSnapshot();
      if (mask != null && !_disposed) {
        _log.log(LogCode.permissionSnapshot, mask);
      }
    } catch (_) {}
  }

  void _applyRegistration(PickerShortcut tried, ShortcutRegistration result) {
    if (result == ShortcutRegistration.registered) {
      _active = tried;
      _problem = null;
    } else {
      _problem = ShortcutProblem.taken;
      _log.log(LogCode.hotkeyRegisterFailed);
    }
  }

  /// The history has opened: read the saved shortcut and paste mode. A saved
  /// shortcut that differs from the one in use is registered now; if it is
  /// taken, the working one stays and the banner says so.
  Future<void> attach(HistoryService history) async {
    await start();
    if (_disposed) return;
    _history?.removeListener(_scheduleWarm);
    _history = history;
    history.addListener(_scheduleWarm);
    _scheduleWarm();
    _pasteMode = PasteMode.parse(history.setting('paste_mode'));
    if (_unsavedShortcut) {
      // The user chose a shortcut while the history was still opening.
      final kept =
          history.saveSetting('picker_shortcut', _shortcut.serialized) &&
          history.persistsSettings;
      _shortcutSaveFailed = !kept;
      _unsavedShortcut = false;
    } else {
      final saved = PickerShortcut.parse(history.setting('picker_shortcut'));
      if (saved != null &&
          saved != _shortcut &&
          !saved.isReserved(isMac: isMac)) {
        _shortcut = saved;
        final result = await port.registerShortcut(saved);
        if (_disposed) return;
        _applyRegistration(saved, result);
      }
    }
    _notify();
  }

  // A few items (a new copy) are indexed at once; a long list is continued in
  // small steps, so nothing waits for the index.
  void _scheduleWarm() {
    if (_warmTimer != null || _disposed) return;
    final items = _history?.items;
    if (items == null || !search.warm(items)) return;
    _warmTimer = Timer(const Duration(milliseconds: 1), () {
      _warmTimer = null;
      _scheduleWarm();
    });
  }

  void _onEvent(PickerNativeEvent event) {
    if (_disposed) return;
    switch (event) {
      case ShortcutPressed():
        if (_pasting || _mode == WindowMode.picker) return;
        _cancelToast();
        _mode = WindowMode.picker;
        _notify();
      case PickerDismissed():
        if (_pasting || _mode != WindowMode.picker) return;
        _mode = WindowMode.manage;
        _notify();
    }
  }

  /// The tray item "Open picker".
  void openFromTray() => unawaited(port.openPicker());

  /// Esc: native hides the picker (and restores the main window if it was
  /// open), then the window goes back to the history screen.
  Future<void> closePicker() async {
    if (_mode != WindowMode.picker || _pasting) return;
    await port.closePicker();
    if (_disposed || _mode != WindowMode.picker) return;
    _mode = WindowMode.manage;
    _notify();
  }

  /// The tray item "Open Kusunga": the picker or the toast must be put away
  /// first, because they use the same window.
  Future<void> prepareManageWindow() async {
    switch (_mode) {
      case WindowMode.manage:
        return;
      case WindowMode.picker:
        await closePicker();
      case WindowMode.toast:
        _cancelToast();
        await port.hideToast();
        if (_disposed) return;
        _mode = WindowMode.manage;
        _notify();
    }
  }

  /// Pastes history item [id] into the app that had focus (see
  /// [PasteOutcome]).
  Future<void> pasteItem(int id) =>
      _paste(_history?.textOf(id), _PasteSource.history);

  /// Pastes snippet [id]. Its change is skipped by the watcher, so it is not
  /// added to history (PM decision D1).
  Future<void> pasteSnippet(int id) =>
      _paste(_history?.snippets.textOf(id), _PasteSource.snippet);

  Future<void> _paste(String? text, _PasteSource source) async {
    if (_mode != WindowMode.picker || _pasting) return;
    if (text == null) return;
    _pasting = true;
    _log.log(LogCode.pasteSource, source.logNumber);
    PasteOutcome outcome;
    try {
      outcome = await port.paste(
        text,
        post: _pasteMode == PasteMode.auto,
        skipHistory: source == _PasteSource.snippet,
      );
    } catch (_) {
      outcome = PasteOutcome.failed;
    }
    _pasting = false;
    if (_disposed) return;
    _finishPaste(outcome);
  }

  void _finishPaste(PasteOutcome outcome) {
    ToastKind? toast;
    switch (outcome) {
      case PasteOutcome.pasted:
        break;
      case PasteOutcome.pastedForced:
        _log.log(LogCode.pasteForcedPost);
      case PasteOutcome.noPermission:
        _log.log(LogCode.pastePermissionMissing);
        if (isMac) {
          _card = true;
          _help = false;
        }
        toast = isMac ? ToastKind.copiedNoPermission : ToastKind.copied;
      case PasteOutcome.focusTimeout:
        _log.log(LogCode.pasteFocusTimeout);
        toast = ToastKind.copied;
      case PasteOutcome.targetGone:
        _log.log(LogCode.pasteTargetGone);
        toast = ToastKind.copied;
      case PasteOutcome.targetElevated:
        _log.log(LogCode.pasteTargetElevated);
        toast = isMac ? ToastKind.copied : ToastKind.copiedElevated;
      case PasteOutcome.copyOnly:
        _log.log(LogCode.pasteCopyOnly);
        toast = ToastKind.copied;
      case PasteOutcome.failed:
        toast = ToastKind.copyFailed;
    }
    if (toast == null) {
      _mode = WindowMode.manage;
      _notify();
      return;
    }
    _toast = toast;
    _mode = WindowMode.toast;
    _notify();
    unawaited(port.showToast());
    _toastTimer?.cancel();
    _toastTimer = Timer(toastDuration, _hideToast);
  }

  Future<void> _hideToast() async {
    _toastTimer = null;
    if (_disposed || _mode != WindowMode.toast) return;
    await port.hideToast();
    if (_disposed || _mode != WindowMode.toast) return;
    _toast = null;
    _mode = WindowMode.manage;
    _notify();
  }

  void _cancelToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    _toast = null;
  }

  /// Registers [next] and saves it. The old shortcut is kept if [next] is
  /// refused.
  Future<ShortcutChange> changeShortcut(PickerShortcut next) async {
    if (!next.isValid) return ShortcutChange.needModifier;
    if (next.isReserved(isMac: isMac)) return ShortcutChange.reserved;
    if (next == _shortcut && _problem == null) {
      if (_suspended) await _restore();
      return ShortcutChange.saved;
    }
    final result = await port.registerShortcut(next);
    if (_disposed) return ShortcutChange.saved;
    if (result != ShortcutRegistration.registered) {
      _log.log(LogCode.hotkeyRegisterFailed);
      if (_suspended) await _restore();
      return ShortcutChange.taken;
    }
    _shortcut = next;
    _active = next;
    _suspended = false;
    _problem = null;
    final history = _history;
    var change = ShortcutChange.saved;
    if (history == null) {
      _unsavedShortcut = true;
    } else if (!history.saveSetting('picker_shortcut', next.serialized) ||
        !history.persistsSettings) {
      // In memory-only mode the shortcut works until quit but is not kept.
      change = ShortcutChange.notSaved;
    }
    _shortcutSaveFailed = change == ShortcutChange.notSaved;
    _notify();
    return change;
  }

  /// While the user presses keys to record a new shortcut, the current one is
  /// released: otherwise pressing it would open the picker instead.
  Future<void> beginRecording() async {
    if (_suspended || _disposed) return;
    _suspended = true;
    await port.unregisterShortcut();
  }

  /// Recording was cancelled: the shortcut that worked before is put back.
  Future<void> endRecording() async {
    if (_suspended && !_disposed) await _restore();
  }

  Future<void> _restore() async {
    _suspended = false;
    final active = _active;
    if (active != null) await port.registerShortcut(active);
  }

  /// The "Allow pasting" button: the only place that asks macOS.
  Future<void> allowPasting() async {
    if (!isMac) return;
    final allowed = await port.requestPostAccess();
    if (_disposed) return;
    if (allowed) {
      _card = false;
      _help = false;
      _pasteMode = PasteMode.auto;
      _history?.saveSetting('paste_mode', PasteMode.auto.stored);
    } else {
      _help = true;
    }
    _notify();
  }

  /// "Not now": the card comes back only after a paste needs it again.
  void dismissPermissionCard() {
    _card = false;
    _help = false;
    _notify();
  }

  /// The permission may have been granted in System Settings meanwhile.
  Future<void> recheckPostAccess() async {
    if (!isMac || !_card) return;
    final allowed = await port.canPost();
    if (_disposed || !allowed) return;
    _card = false;
    _help = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _toastTimer?.cancel();
    _warmTimer?.cancel();
    _history?.removeListener(_scheduleWarm);
    unawaited(_events?.cancel());
    super.dispose();
  }
}
