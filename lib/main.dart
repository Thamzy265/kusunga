import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'clipboard/channel_clipboard_source.dart';
import 'history/history_handle.dart';
import 'history/open_app_history.dart';
import 'history/windows_key_store.dart';
import 'lifecycle/app_lifecycle.dart';
import 'lifecycle/quit_flow.dart';
import 'log/app_log.dart';
import 'log/unified_log.dart';
import 'picker/channel_picker_port.dart';
import 'picker/picker_controller.dart';
import 'tray/tray_manager_port.dart';
import 'tray/tray_service.dart';
import 'window/window_manager_port.dart';
import 'window/window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The unified log mirror is a macOS thing (the Windows side has none).
  final deferredLog = DeferredErrorLog(
    mirror: defaultTargetPlatform == TargetPlatform.macOS
        ? ChannelUnifiedLog()
        : null,
  );
  final history = openAppHistory(
    deferred: deferredLog,
    supportDirectory: getApplicationSupportDirectory,
    keys: keyStoreFor(isWindows: Platform.isWindows),
    source: ChannelClipboardSource(),
  );
  final handle = HistoryHandle(history);

  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
  // The picker shortcut is registered at once with the default; the saved
  // one is read when the history has opened (it never waits for the keychain).
  final picker = isDesktop
      ? PickerController(
          port: ChannelPickerPort(),
          log: deferredLog,
          isMac: defaultTargetPlatform == TargetPlatform.macOS,
        )
      : null;
  runApp(KusungaApp(history: history, picker: picker));
  if (!isDesktop) return;
  unawaited(picker!.start());
  history.then<void>(picker.attach, onError: (Object _) {});

  // Both services log and swallow their own failures, so the window always
  // opens. The tray starts after runApp so it can never delay the window.
  final window = WindowService(port: WindowManagerPort());
  late final TrayService tray;
  final quit = QuitFlow(
    lifecycle: AppLifecycle(),
    closeHistory: handle.close,
    stopTray: () => tray.dispose(),
    stopWindow: () => window.dispose(),
  )..listenForNativeFlush();
  tray = TrayService(
    port: TrayManagerPort(),
    iconPath: defaultTargetPlatform == TargetPlatform.windows
        ? 'assets/tray/tray_icon.ico'
        : 'assets/tray/tray_icon.png',
    onOpenPicker: picker.openFromTray,
    onOpen: () =>
        unawaited(picker.prepareManageWindow().then((_) => window.show())),
    // Tray Quit closes the history first, then asks native to end the app.
    onQuit: () => unawaited(quit.quitFromTray().catchError((Object _) {})),
  );
  unawaited(window.start());
  unawaited(tray.start());
}
