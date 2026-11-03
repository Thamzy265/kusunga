import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_service.dart';

class FakeTrayPort implements TrayPort {
  final menuClicks = StreamController<String>.broadcast();
  String? iconPath;
  String? toolTip;
  List<TrayMenuEntry>? menu;

  @override
  Stream<String> get menuItemClicks => menuClicks.stream;

  @override
  Future<void> setIcon(String path) async => iconPath = path;

  @override
  Future<void> setToolTip(String text) async => toolTip = text;

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async => menu = entries;
}

void main() {
  test('start sets icon, tooltip and a menu with only Quit', () async {
    final port = FakeTrayPort();
    final service = TrayService(
      port: port,
      iconPath: 'icon.png',
      onQuit: () {},
    );

    await service.start();

    expect(port.iconPath, 'icon.png');
    expect(port.toolTip, 'Kusunga');
    expect(port.menu, hasLength(1));
    expect(port.menu!.single.label, 'Quit');
  });

  test('choosing Quit calls onQuit once', () async {
    final port = FakeTrayPort();
    var quits = 0;
    final service = TrayService(
      port: port,
      iconPath: 'icon.png',
      onQuit: () => quits++,
    );
    await service.start();

    port.menuClicks.add(TrayService.quitKey);
    await Future<void>.delayed(Duration.zero);

    expect(quits, 1);
  });

  test('other menu keys do not quit', () async {
    final port = FakeTrayPort();
    var quits = 0;
    final service = TrayService(
      port: port,
      iconPath: 'icon.png',
      onQuit: () => quits++,
    );
    await service.start();

    port.menuClicks.add('something-else');
    await Future<void>.delayed(Duration.zero);

    expect(quits, 0);
  });
}
