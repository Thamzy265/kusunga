// M1.8 D6 A: Delete everything turns launch at login off through the same
// port, whatever the switch is doing; checked through the fake port only
// (the real check is a PM step, lead ruling G3).
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';

import '../support/fakes.dart';

void main() {
  late FakeLoginItemPort port;
  late FakeLog log;
  late LoginItemService service;

  setUp(() {
    port = FakeLoginItemPort()..next = const LoginItemAnswer(LoginItemState.on);
    log = FakeLog();
    service = LoginItemService(port: port, log: log);
    addTearDown(service.dispose);
  });

  test('asks the OS to turn it off and logs it', () async {
    await service.refresh();
    expect(service.isOn, isTrue);
    port.next = const LoginItemAnswer(LoginItemState.off);
    await service.turnOff();
    expect(port.setCalls, [false]);
    expect(log.codes, contains(LogCode.loginItemOff));
    expect(service.isOn, isFalse);
  });

  test('also while another change is still running', () async {
    final held = port.hold();
    final pending = service.set(true);
    port.next = const LoginItemAnswer(LoginItemState.off);
    await service.turnOff();
    expect(port.setCalls, [true, false]);
    held.complete(const LoginItemAnswer(LoginItemState.on));
    await pending;
  });

  test('a failure is logged with its number and never thrown', () async {
    port.next = const LoginItemAnswer(LoginItemState.failed, error: 5);
    await service.turnOff();
    expect(log.codes, contains(LogCode.loginItemFailed));
  });
}
