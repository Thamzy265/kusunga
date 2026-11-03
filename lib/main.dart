import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'clipboard/channel_clipboard_source.dart';
import 'history/history_opener.dart';
import 'history/history_service.dart';
import 'history/windows_key_store.dart';
import 'history/memory_history_store.dart';
import 'lifecycle/app_lifecycle.dart';
import 'lifecycle/quit_flow.dart';
import 'log/app_log.dart';
import 'tray/tray_manager_port.dart';
import 'tray/tray_service.dart';
import 'window/window_manager_port.dart';
import 'window/window_service.dart';

/// Opens the encrypted history and starts listening for copies. It never
/// throws: if anything is wrong the history runs in memory only, with a
/// banner, and nothing is written to disk.
Future<HistoryService> _openHistory() async {
  ErrorLog log = const NullErrorLog();
  OpenedHistory opened;
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    log = FileErrorLog(File('${dir.path}${Platform.pathSeparator}kusunga.log'));
    opened = await openHistory(
      keys: keyStoreFor(isWindows: Platform.isWindows),
      directory: dir.path,
      log: log,
    );
  } catch (_) {
    log.log(LogCode.dataFolderUnavailable);
    opened = OpenedHistory(MemoryHistoryStore(), {HistoryNotice.memoryOnly});
  }
  return HistoryService(
    store: opened.store,
    notices: opened.notices,
    source: ChannelClipboardSource(),
    log: log,
  )..start();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final history = _openHistory();
  runApp(KusungaApp(history: history));

  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
  if (!isDesktop) return;

  // Both services log and swallow their own failures, so the window always
  // opens. The tray starts after runApp so it can never delay the window.
  final window = WindowService(port: WindowManagerPort());
  late final TrayService tray;
  final quit = QuitFlow(
    lifecycle: AppLifecycle(),
    closeHistory: () async => (await history).close(),
    stopTray: () => tray.dispose(),
    stopWindow: () => window.dispose(),
  )..listenForNativeFlush();
  tray = TrayService(
    port: TrayManagerPort(),
    iconPath: defaultTargetPlatform == TargetPlatform.windows
        ? 'assets/tray/tray_icon.ico'
        : 'assets/tray/tray_icon.png',
    onOpen: () => unawaited(window.show()),
    // Tray Quit closes the history first, then asks native to end the app.
    onQuit: () => unawaited(quit.quitFromTray().catchError((Object _) {})),
  );
  unawaited(window.start());
  unawaited(tray.start());
}
