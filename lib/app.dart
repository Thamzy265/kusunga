import 'package:flutter/material.dart';

import 'history/history_service.dart';
import 'history/ui/history_host.dart';
import 'theme/tokens.dart';

class KusungaApp extends StatelessWidget {
  const KusungaApp({super.key, required this.history});

  /// The history, once it has opened (see `openHistory`).
  final Future<HistoryService> history;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kusunga',
      theme: KusungaTokens.themeData(Brightness.light),
      darkTheme: KusungaTokens.themeData(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HistoryHost(history: history),
    );
  }
}
