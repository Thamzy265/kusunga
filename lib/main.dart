import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'tray/tray_manager_port.dart';
import 'tray/tray_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
  if (isDesktop) {
    // A tray problem must never stop the window from opening.
    try {
      await TrayService(
        port: TrayManagerPort(),
        iconPath: defaultTargetPlatform == TargetPlatform.windows
            ? 'assets/tray/tray_icon.ico'
            : 'assets/tray/tray_icon.png',
        // TODO(M1.2): quit gracefully (flush and close the data store)
        // before exiting, once the store exists.
        onQuit: () => exit(0),
      ).start();
    } catch (error) {
      debugPrint('Kusunga: tray unavailable: $error');
    }
  }

  runApp(const KusungaApp());
}
