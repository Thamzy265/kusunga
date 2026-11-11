import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'clipboard/channel_clipboard_source.dart';
import 'history/data_profile.dart';
import 'history/history_handle.dart';
import 'history/open_app_history.dart';
import 'history/windows_key_store.dart';
import 'lifecycle/app_lifecycle.dart';
import 'lifecycle/quit_flow.dart';
import 'log/app_log.dart';
import 'log/unified_log.dart';
import 'picker/channel_picker_port.dart';
import 'picker/picker_controller.dart';
import 'settings/login_item.dart';
import 'shortcuts/channel_typed_shortcuts_port.dart';
import 'shortcuts/shortcut_service.dart';
import 'tray/tray_manager_port.dart';
import 'tray/tray_service.dart';
import 'window/window_manager_port.dart';
import 'window/window_service.dart';

/// [args]: on a Mac only what the Debug-only native code passes on (the
/// test data profile); on Windows the command line.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // The unified log mirror is a macOS thing (the Windows side has none).
  final deferredLog = DeferredErrorLog(
    mirror: defaultTargetPlatform == TargetPlatform.macOS
        ? ChannelUnifiedLog()
        : null,
  );
  // `-KusungaDataProfile <name>`: Debug builds only, a separate data folder
  // for QA (PM decision 2026-11-05). Release ignores it.
  final profile = dataProfileFrom(args);
  final data = dataProfileSetup(
    profile,
    supportDirectory: getApplicationSupportDirectory,
    keys: keyStoreFor(isWindows: Platform.isWindows),
    log: deferredLog,
  );
  final history = openAppHistory(
    deferred: deferredLog,
    supportDirectory: data.supportDirectory,
    keys: data.keys,
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
  // Typed shortcuts (M1.5): off until the user turns them on (D3 A). The
  // table and the ignore list are sent once the history has opened.
  final shortcuts = isDesktop
      ? history.then((h) async {
          final service = ShortcutService(
            port: ChannelTypedShortcutsPort(),
            snippets: h.snippets,
            ignoredApps: h.ignoredApps,
            readSetting: h.setting,
            writeSetting: h.saveSetting,
            log: deferredLog,
            isWindows: Platform.isWindows,
            available: h.snippets.canEdit,
            onCopied: picker!.showCopiedToast,
            // M1.6 D1 A: the same list stops history capture.
            setCaptureIgnored: h.setCaptureIgnored,
          );
          await service.start();
          return service;
        })
      : null;
  // Launch at login (M1.7): the OS holds the state; read again when the
  // Settings tab opens and when Kusunga becomes active.
  final loginItem = isDesktop
      ? (LoginItemService(port: ChannelLoginItemPort(), log: deferredLog)
          ..startListening())
      : null;
  runApp(
    KusungaApp(
      loginItem: loginItem,
      history: history,
      picker: picker,
      shortcuts: shortcuts,
      dataProfile: profile is ActiveDataProfile ? profile.name : null,
      dataProfileRejected: profile is RejectedDataProfile,
    ),
  );
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
    pausedIconPath: defaultTargetPlatform == TargetPlatform.windows
        ? 'assets/tray/tray_icon_paused.ico'
        : 'assets/tray/tray_icon_paused.png',
    onOpenPicker: picker.openFromTray,
    onOpen: () =>
        unawaited(picker.prepareManageWindow().then((_) => window.show())),
    // Tray Quit closes the history first, then asks native to end the app.
    onQuit: () => unawaited(quit.quitFromTray().catchError((Object _) {})),
  );
  unawaited(window.start());
  unawaited(tray.start());
  // M1.6: the pause's 15 s tick (and on becoming active), and the tray's
  // Pause / Resume once the history has opened.
  history.then<void>((h) {
    h.pause.startTicking();
    // M1.7: the auto-delete check (every 15 minutes, after a wake, and on
    // becoming active); the launch clean-up already ran in start().
    h.expiry.startTicking();
    tray.attachPause(h.pause);
  }, onError: (Object _) {});
}
