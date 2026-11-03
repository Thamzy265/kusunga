import 'package:flutter/material.dart';

import '../../history/history_service.dart';
import '../../history/ui/history_host.dart';
import '../picker_controller.dart';
import 'picker_panel.dart';
import 'picker_settings_section.dart';
import 'picker_toast.dart';

/// The one window, in the mode the controller says: the history screen (with
/// the picker settings), the picker, or the small toast.
class WindowRoot extends StatelessWidget {
  const WindowRoot({super.key, required this.history, required this.picker});

  final Future<HistoryService> history;
  final PickerController picker;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: picker,
      builder: (context, _) => switch (picker.mode) {
        WindowMode.manage => HistoryHost(
          history: history,
          initial: picker.history,
          topSlot: PickerSettingsSection(controller: picker),
        ),
        WindowMode.picker => PickerPanel(controller: picker),
        WindowMode.toast => PickerToastView(controller: picker),
      },
    );
  }
}
