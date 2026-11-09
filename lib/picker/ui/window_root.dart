import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../history/history_service.dart';
import '../../history/ui/history_host.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../shortcuts/ui/typed_shortcuts_section.dart';
import '../picker_controller.dart';
import 'picker_panel.dart';
import 'picker_settings_section.dart';
import 'picker_toast.dart';

/// The one window, in the mode the controller says: the history screen (with
/// the picker settings), the picker, or the small toast.
///
/// The history screen stays built while the picker or the toast shows (hidden,
/// not rebuilt), so a pending Undo, the scroll position and an unfinished edit
/// are still there when the window comes back. The focus goes back to what had it,
/// so Cmd/Ctrl+Z still works.
class WindowRoot extends StatefulWidget {
  const WindowRoot({
    super.key,
    required this.history,
    required this.picker,
    this.dataProfile,
    this.dataProfileRejected = false,
    this.shortcuts,
  });

  final Future<HistoryService> history;
  final PickerController picker;

  /// Typed shortcuts (M1.5), once the history has opened. Without it the
  /// Snippets tab has no "Typed shortcuts" section.
  final Future<ShortcutService>? shortcuts;

  /// The test data profile in use, if any (see `HistoryHost.dataProfile`).
  final String? dataProfile;

  /// See `HistoryHost.dataProfileRejected`.
  final bool dataProfileRejected;

  @override
  State<WindowRoot> createState() => _WindowRootState();
}

class _WindowRootState extends State<WindowRoot> {
  late WindowMode _mode;
  FocusNode? _focusBefore;

  @override
  void initState() {
    super.initState();
    _mode = widget.picker.mode;
    widget.picker.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.picker.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final mode = widget.picker.mode;
    if (mode == _mode) return;
    final was = _mode;
    _mode = mode;
    if (was == WindowMode.manage) {
      // Remember what had focus (a row, a field) before the picker takes it.
      _focusBefore = FocusManager.instance.primaryFocus;
    } else if (mode == WindowMode.manage) {
      final node = _focusBefore;
      _focusBefore = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node != null && node.context != null) {
          node.requestFocus();
        }
      });
    }
  }

  // The size the history screen had when it was last shown. While it is
  // hidden it keeps that size, so the small picker and toast windows never
  // make it lay out (and overflow) at 360 x 96.
  Size _manageSize = const Size(800, 632);

  Widget _history() {
    final picker = widget.picker;
    final shown = picker.mode == WindowMode.manage;
    return LayoutBuilder(
      builder: (context, box) {
        if (shown) _manageSize = box.biggest;
        final screen = HistoryHost(
          history: widget.history,
          initial: picker.history,
          topSlot: PickerSettingsSection(controller: picker),
          snippetsTopSlot: _shortcutsSection(),
          dataProfile: widget.dataProfile,
          dataProfileRejected: widget.dataProfileRejected,
        );
        return Visibility(
          visible: shown,
          maintainState: true,
          // The same widgets in both cases, so the screen is never rebuilt.
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: shown ? null : _manageSize.width,
            maxWidth: shown ? null : _manageSize.width,
            minHeight: shown ? null : _manageSize.height,
            maxHeight: shown ? null : _manageSize.height,
            child: screen,
          ),
        );
      },
    );
  }

  Widget? _shortcutsSection() {
    final shortcuts = widget.shortcuts;
    if (shortcuts == null) return null;
    return FutureBuilder<ShortcutService>(
      future: shortcuts,
      builder: (context, snap) => snap.data == null
          ? const SizedBox.shrink()
          : TypedShortcutsSection(
              service: snap.data!,
              isMac: defaultTargetPlatform == TargetPlatform.macOS,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picker = widget.picker;
    return ListenableBuilder(
      listenable: picker,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          _history(),
          if (picker.mode == WindowMode.picker) PickerPanel(controller: picker),
          if (picker.mode == WindowMode.toast)
            PickerToastView(controller: picker),
        ],
      ),
    );
  }
}
