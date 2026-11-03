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
    await TrayService(
      port: TrayManagerPort(),
      iconPath: defaultTargetPlatform == TargetPlatform.windows
          ? 'assets/tray/tray_icon.ico'
          : 'assets/tray/tray_icon.png',
      onQuit: () => exit(0),
    ).start();
  }

  runApp(const KusungaApp());
}
