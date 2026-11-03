import 'dart:async';

import 'package:flutter/foundation.dart';

import '../history/history_service.dart';
import '../log/app_log.dart';
import 'picker_port.dart';
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

  StreamSubscription<PickerNativeEvent>? _events;
  Future<void>? _starting;
  Timer? _toastTimer;
  WindowMode _mode = WindowMode.manage;
  PickerShortcut _shortcut;
  ShortcutProblem? _problem;
  HistoryService? _history;
  PasteMode _pasteMode = PasteMode.auto;
  ToastKind? _toast;
  var _card = false;
  var _help = false;
  var _pasting = false;
  var _unsavedShortcut = false;
  var _disposed = false;

  WindowMode get mode => _mode;

  /// The shortcut the user wants (the one shown in the setting).
  PickerShortcut get shortcut => _shortcut;
  ShortcutProblem? get shortcutProblem => _problem;
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
    _applyRegistration(result);
    _notify();
  }

  void _applyRegistration(ShortcutRegistration result) {
    if (result == ShortcutRegistration.registered) {
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
    _history = history;
    _pasteMode = PasteMode.parse(history.setting('paste_mode'));
    if (_unsavedShortcut) {
      // The user chose a shortcut while the history was still opening.
      history.saveSetting('picker_shortcut', _shortcut.serialized);
      _unsavedShortcut = false;
    } else {
      final saved = PickerShortcut.parse(history.setting('picker_shortcut'));
      if (saved != null && saved != _shortcut) {
        _shortcut = saved;
        final result = await port.registerShortcut(saved);
        if (_disposed) return;
        _applyRegistration(result);
      }
    }
    _notify();
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

  /// Pastes item [id] into the app that had focus (see [PasteOutcome]).
  Future<void> pasteItem(int id) async {
    if (_mode != WindowMode.picker || _pasting) return;
    final text = _history?.textOf(id);
    if (text == null) return;
    _pasting = true;
    PasteOutcome outcome;
    try {
      outcome = await port.paste(text, post: _pasteMode == PasteMode.auto);
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
    if (next == _shortcut && _problem == null) return ShortcutChange.saved;
    final result = await port.registerShortcut(next);
    if (_disposed) return ShortcutChange.saved;
    if (result != ShortcutRegistration.registered) {
      _log.log(LogCode.hotkeyRegisterFailed);
      return ShortcutChange.taken;
    }
    _shortcut = next;
    _problem = null;
    final history = _history;
    var change = ShortcutChange.saved;
    if (history == null) {
      _unsavedShortcut = true;
    } else if (!history.saveSetting('picker_shortcut', next.serialized)) {
      change = ShortcutChange.notSaved;
    }
    _notify();
    return change;
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
    unawaited(_events?.cancel());
    super.dispose();
  }
}
