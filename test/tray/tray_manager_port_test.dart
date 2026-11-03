import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/tray/tray_manager_port.dart';

const _channel = MethodChannel('tray_manager');

Future<void> _platformSends(String method) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> invoked;

  setUp(() {
    invoked = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          invoked.add(call.method);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('C1: left click on the icon pops up the menu', () async {
    final port = TrayManagerPort();
    addTearDown(port.dispose);

    await _platformSends('onTrayIconMouseDown');

    expect(invoked, ['popUpContextMenu']);
  });

  test('C1: right click on the icon pops up the menu', () async {
    final port = TrayManagerPort();
    addTearDown(port.dispose);

    await _platformSends('onTrayIconRightMouseDown');

    expect(invoked, ['popUpContextMenu']);
  });

  test('C3: setToolTip is sent on every platform', () async {
    final port = TrayManagerPort();
    addTearDown(port.dispose);

    await port.setToolTip('Kusunga');

    expect(invoked, ['setToolTip']);
  });

  test('destroy asks the plugin to remove the icon', () async {
    final port = TrayManagerPort();
    addTearDown(port.dispose);

    await port.destroy();

    expect(invoked, ['destroy']);
  });

  test('F2: after dispose the port no longer reacts to the icon', () async {
    final port = TrayManagerPort();
    await port.dispose();

    await _platformSends('onTrayIconMouseDown');

    expect(invoked, isEmpty);
  });
}
