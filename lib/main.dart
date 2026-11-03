import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'tray/tray_manager_port.dart';
import 'tray/tray_service.dart';
import 'window/window_manager_port.dart';
import 'window/window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const KusungaApp());

  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
  if (!isDesktop) return;

  // Both services log and swallow their own failures, so the window always
  // opens. The tray starts after runApp so it can never delay the window.
  final window = WindowService(port: WindowManagerPort());
  late final TrayService tray;
  tray = TrayService(
    port: TrayManagerPort(),
    iconPath: defaultTargetPlatform == TargetPlatform.windows
        ? 'assets/tray/tray_icon.ico'
        : 'assets/tray/tray_icon.png',
    onOpen: () => unawaited(window.show()),
    onQuit: () async {
      // TODO(M1.2): quit gracefully (flush and close the data store) before
      // exiting, once the store exists.
      await tray.dispose();
      await window.dispose();
      exit(0);
    },
  );
  unawaited(window.start());
  unawaited(tray.start());
}
