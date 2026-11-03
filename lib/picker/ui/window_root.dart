import 'package:flutter/material.dart';

import '../../history/history_service.dart';
import '../../history/ui/history_host.dart';
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
  const WindowRoot({super.key, required this.history, required this.picker});

  final Future<HistoryService> history;
  final PickerController picker;

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

  @override
  Widget build(BuildContext context) {
    final picker = widget.picker;
    return ListenableBuilder(
      listenable: picker,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          Visibility(
            visible: picker.mode == WindowMode.manage,
            maintainState: true,
            child: HistoryHost(
              history: widget.history,
              initial: picker.history,
              topSlot: PickerSettingsSection(controller: picker),
            ),
          ),
          if (picker.mode == WindowMode.picker) PickerPanel(controller: picker),
          if (picker.mode == WindowMode.toast)
            PickerToastView(controller: picker),
        ],
      ),
    );
  }
}
