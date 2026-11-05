import 'package:flutter/material.dart';

import 'history/history_service.dart';
import 'history/ui/history_host.dart';
import 'picker/picker_controller.dart';
import 'picker/ui/window_root.dart';
import 'theme/tokens.dart';

class KusungaApp extends StatelessWidget {
  const KusungaApp({
    super.key,
    required this.history,
    this.picker,
    this.dataProfile,
  });

  /// The history, once it has opened (see `openHistory`).
  final Future<HistoryService> history;

  /// The picker (M1.3). Without it the window is only the history screen.
  final PickerController? picker;

  /// The test data profile in use (Debug builds only), shown in the window.
  final String? dataProfile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kusunga',
      theme: KusungaTokens.themeData(Brightness.light),
      darkTheme: KusungaTokens.themeData(Brightness.dark),
      themeMode: ThemeMode.system,
      home: picker == null
          ? HistoryHost(history: history, dataProfile: dataProfile)
          : WindowRoot(
              history: history,
              picker: picker!,
              dataProfile: dataProfile,
            ),
    );
  }
}
