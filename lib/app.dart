import 'package:flutter/material.dart';

import 'history/history_service.dart';
import 'history/ui/history_host.dart';
import 'picker/picker_controller.dart';
import 'picker/ui/window_root.dart';
import 'settings/login_item.dart';
import 'settings/ui/your_data_section.dart';
import 'shortcuts/shortcut_service.dart';
import 'theme/tokens.dart';

class KusungaApp extends StatelessWidget {
  const KusungaApp({
    super.key,
    required this.history,
    this.picker,
    this.dataProfile,
    this.dataProfileRejected = false,
    this.shortcuts,
    this.loginItem,
    this.yourData,
  });

  /// Settings › Your data (M1.8, desktop).
  final YourDataSetup? yourData;

  /// Launch at login (M1.7, desktop).
  final LoginItemService? loginItem;

  /// Typed shortcuts (M1.5), once the history has opened.
  final Future<ShortcutService>? shortcuts;

  /// The history, once it has opened (see `openHistory`).
  final Future<HistoryService> history;

  /// The picker (M1.3). Without it the window is only the history screen.
  final PickerController? picker;

  /// The test data profile in use (Debug builds only), shown in the window.
  final String? dataProfile;

  /// A test profile switch was given but not recognised (Debug builds only),
  /// so this session is memory only: the banner says so (QA-M14-6).
  final bool dataProfileRejected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kusunga',
      theme: KusungaTokens.themeData(Brightness.light),
      darkTheme: KusungaTokens.themeData(Brightness.dark),
      themeMode: ThemeMode.system,
      home: picker == null
          ? HistoryHost(
              history: history,
              dataProfile: dataProfile,
              dataProfileRejected: dataProfileRejected,
            )
          : WindowRoot(
              history: history,
              picker: picker!,
              dataProfile: dataProfile,
              dataProfileRejected: dataProfileRejected,
              shortcuts: shortcuts,
              loginItem: loginItem,
              yourData: yourData,
            ),
    );
  }
}
