// M1.6: tray_manager 0.5.3 supports submenus on Mac and Windows (type
// "submenu" with a nested "submenu" map). The port sends "Pause history ▸"
// that way, and a click on a submenu item reports that item's key.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_manager_port.dart';
import 'package:kusunga/tray/tray_service.dart';

const _channel = MethodChannel('tray_manager');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> invoked;

  setUp(() {
    invoked = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      invoked.add(call);
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('an entry with children is sent as a submenu', () async {
    final port = TrayManagerPort();
    addTearDown(port.dispose);
    await port.setMenu(const [
      TrayMenuEntry(key: 'open', label: 'Open Kusunga'),
      TrayMenuEntry(
        key: 'pause',
        label: 'Pause history',
        children: [
          TrayMenuEntry(key: 'pause15', label: 'For 15 minutes'),
          TrayMenuEntry(key: 'pauseUntil', label: 'Until I resume'),
        ],
      ),
    ]);
    final call = invoked.singleWhere((c) => c.method == 'setContextMenu');
    final items = ((call.arguments as Map)['menu'] as Map)['items'] as List;
    expect((items[0] as Map)['type'], 'normal');
    final pause = items[1] as Map;
    expect(pause['type'], 'submenu');
    expect(pause['label'], 'Pause history');
    final sub = (pause['submenu'] as Map)['items'] as List;
    expect(
      [for (final i in sub) (i as Map)['label']],
      ['For 15 minutes', 'Until I resume'],
    );
  });

  test('a click on a submenu item reports its key', () async {
    final port = TrayManagerPort();
    addTearDown(port.dispose);
    await port.setMenu(const [
      TrayMenuEntry(
        key: 'pause',
        label: 'Pause history',
        children: [TrayMenuEntry(key: 'pause60', label: 'For 1 hour')],
      ),
    ]);
    final call = invoked.singleWhere((c) => c.method == 'setContextMenu');
    final items = ((call.arguments as Map)['menu'] as Map)['items'] as List;
    final id =
        (((items[0] as Map)['submenu'] as Map)['items'] as List)[0]['id'];
    final keys = <String>[];
    final sub = port.menuItemClicks.listen(keys.add);
    await messenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onTrayMenuItemClick', {'id': id}),
      ),
      (_) {},
    );
    await pumpEventQueue();
    expect(keys, ['pause60']);
    await sub.cancel();
  });
}
