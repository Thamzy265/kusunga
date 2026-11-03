import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_service.dart';

import 'fake_tray_port.dart';

void main() {
  test(
    'start sets icon, tooltip and a menu with Open Kusunga then Quit',
    () async {
      final port = FakeTrayPort();
      final service = TrayService(
        port: port,
        iconPath: 'icon.png',
        onOpen: () {},
        onQuit: () {},
      );

      await service.start();

      expect(port.iconPath, 'icon.png');
      expect(port.toolTip, 'Kusunga');
      expect(port.menu!.map((e) => (e.key, e.label)), [
        ('open', 'Open Kusunga'),
        ('quit', 'Quit'),
      ]);
    },
  );

  test('choosing Quit calls onQuit once and Open calls onOpen once', () async {
    final port = FakeTrayPort();
    var quits = 0;
    var opens = 0;
    final service = TrayService(
      port: port,
      iconPath: 'icon.png',
      onOpen: () => opens++,
      onQuit: () => quits++,
    );
    await service.start();

    port.clicks.add(TrayService.quitKey);
    await Future<void>.delayed(Duration.zero);
    expect((quits, opens), (1, 0));

    port.clicks.add(TrayService.openKey);
    await Future<void>.delayed(Duration.zero);
    expect((quits, opens), (1, 1));
  });

  test('other menu keys do nothing', () async {
    final port = FakeTrayPort();
    var calls = 0;
    final service = TrayService(
      port: port,
      iconPath: 'icon.png',
      onOpen: () => calls++,
      onQuit: () => calls++,
    );
    await service.start();

    port.clicks.add('something-else');
    await Future<void>.delayed(Duration.zero);

    expect(calls, 0);
  });
}
