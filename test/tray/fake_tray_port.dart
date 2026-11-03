import 'dart:async';

import 'package:kusunga/tray/tray_service.dart';

/// One fake [TrayPort] shared by the tray tests. Records every call in
/// [calls]; set [failOn] to 'icon', 'tooltip', 'menu' or 'destroy' to make
/// that call throw. [gateIcon] holds setIcon until completed.
class FakeTrayPort implements TrayPort {
  final clicks = StreamController<String>.broadcast();
  final calls = <String>[];
  String? iconPath;
  String? toolTip;
  List<TrayMenuEntry>? menu;
  Object? failOn;
  Completer<void>? gateIcon;

  @override
  Stream<String> get menuItemClicks => clicks.stream;

  @override
  Future<void> setIcon(String path) async {
    calls.add('icon');
    await gateIcon?.future;
    if (failOn == 'icon') throw StateError('icon failed');
    iconPath = path;
  }

  @override
  Future<void> setToolTip(String text) async {
    calls.add('tooltip');
    if (failOn == 'tooltip') throw StateError('tooltip failed');
    toolTip = text;
  }

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async {
    calls.add('menu');
    if (failOn == 'menu') throw StateError('menu failed');
    menu = entries;
  }

  @override
  Future<void> destroy() async {
    calls.add('destroy');
    if (failOn == 'destroy') throw StateError('destroy failed');
  }

  @override
  Future<void> dispose() async => calls.add('dispose');

  int count(String call) => calls.where((c) => c == call).length;
}
