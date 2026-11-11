// Guards for M1.7 launch at login (docs/design/settings-and-expiry.md,
// "Launch at login", "Trust boundaries"):
//  - the channel has exactly three calls and carries no path or user data;
//  - the Mac app is a login item through SMAppService.mainApp only, guarded
//    for macOS 13, and the main window opens after launch unless it was a
//    login launch (D5 A);
//  - Windows writes only its own quoted exe path with --login to the HKCU
//    Run key, never writes StartupApproved, and starts hidden with --login;
//  - the new native files are built (Xcode project, CMake) and tested.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Source without line comments, so a comment can't satisfy or break a check.
String _code(String path) => _read(
  path,
).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

const _dart = 'lib/settings/login_item.dart';
const _swiftCore = 'macos/Runner/LoginItemCore.swift';
const _swiftBridge = 'macos/Runner/LoginItemBridge.swift';
const _swiftWindow = 'macos/Runner/MainFlutterWindow.swift';
const _xib = 'macos/Runner/Base.lproj/MainMenu.xib';
const _pbx = 'macos/Runner.xcodeproj/project.pbxproj';
const _cppPolicy = 'windows/runner/login_item_policy.h';
const _cppBridge = 'windows/runner/login_item_bridge.cpp';
const _cppMain = 'windows/runner/main.cpp';
const _cmake = 'windows/runner/CMakeLists.txt';

const _methods = {'loginItemStatus', 'setLoginItem', 'openLoginItemsSettings'};

Set<String> _quoted(String src, RegExp around) => {
  for (final m in around.allMatches(src)) m.group(1)!,
};

void main() {
  test('Dart calls exactly the three methods on its own channel', () {
    final src = _code(_dart);
    expect(src, contains("'com.wnasoni.kusunga/login_item'"));
    expect(
      _quoted(
        src,
        RegExp(r"invokeMethod<[^>]*>\(\s*'([A-Za-z]+)'"),
      ).union(_quoted(src, RegExp(r"_call\('([A-Za-z]+)'"))),
      _methods,
    );
  });

  test(
    'Mac: the bridge answers the three methods, with a bool argument only',
    () {
      final src = _code(_swiftBridge);
      expect(src, contains('"com.wnasoni.kusunga/login_item"'));
      expect(_quoted(src, RegExp(r'case "([A-Za-z]+)"')), _methods);
      expect(src, contains('call.arguments as? Bool'));
    },
  );

  test('Mac: SMAppService.mainApp only, guarded for macOS 13', () {
    final src = _code(_swiftBridge);
    expect(src, contains('@available(macOS 13.0, *)'));
    expect(src, contains('if #available(macOS 13.0, *)'));
    expect(
      RegExp(
        r'SMAppService\.(?!mainApp|openSystemSettingsLoginItems)\w+',
      ).hasMatch(src),
      isFalse,
      reason: 'no helper app, agent or daemon',
    );
    expect(src, isNot(contains('SMLoginItemSetEnabled')));
  });

  test('Mac: the reply is a state and an optional number, nothing else', () {
    final src = _code(_swiftCore);
    final keys = _quoted(src, RegExp(r'r?\["([a-z]+)"\]'))
      ..addAll(_quoted(src, RegExp(r'\["([a-z]+)": ')));
    expect(keys, {'state', 'error'});
  });

  test('Mac: the window does not open by itself; it opens after launch '
      'unless macOS says it was a login launch (D5 A)', () {
    final window = _read(_xib)
        .split('\n')
        .firstWhere((l) => l.contains('customClass="MainFlutterWindow"'));
    expect(window, contains('visibleAtLaunch="NO"'));
    final src = _code(_swiftWindow);
    expect(src, contains('NSApplication.didFinishLaunchingNotification'));
    expect(src, contains('currentAppleEvent'));
    expect(src, contains('LoginLaunch.showsWindowAtLaunch'));
    expect(src, contains('makeKeyAndOrderFront'));
    expect(src, contains('LoginItemBridge.shared.register'));
  });

  test('Mac: both new files are in the Runner target, the tests in '
      'RunnerTests, and the standalone script runs them', () {
    final pbx = _read(_pbx);
    for (final f in [
      'LoginItemCore.swift in Sources',
      'LoginItemBridge.swift in Sources',
      'LoginItemCoreTests.swift in Sources',
    ]) {
      expect(RegExp(RegExp.escape(f)).allMatches(pbx).length, 2, reason: f);
    }
    final script = _read('tool/test_mac_login_item.sh');
    expect(script, contains('macos/Runner/LoginItemCore.swift'));
    expect(script, contains('macos/RunnerTests/LoginItemCoreTests.swift'));
    expect(script, isNot(contains('LoginItemBridge')));
  });

  test('Windows: HKCU Run value "Kusunga" with the quoted exe path and '
      '--login; StartupApproved is only read', () {
    final policy = _code(_cppPolicy);
    expect(
      policy,
      contains(r'Software\\Microsoft\\Windows\\CurrentVersion\\Run'),
    );
    expect(policy, contains('L"Kusunga"'));
    expect(policy, contains('--login'));
    final bridge = _code(_cppBridge);
    expect(bridge, contains('HKEY_CURRENT_USER'));
    expect(bridge, isNot(contains('HKEY_LOCAL_MACHINE')));
    // Writes go through one function that only takes the Run key.
    final writes = RegExp(
      r'RegSetValueExW|RegSetKeyValueW|RegDeleteValueW|'
      r'RegDeleteKeyValueW',
    ).allMatches(bridge).length;
    expect(writes, 2, reason: 'one write and one delete, both of Run');
    final approvedUses = RegExp('StartupApproved').allMatches(policy + bridge);
    expect(approvedUses, isNotEmpty);
    expect(
      RegExp(r'RegSetValueExW\([^;]*kStartupApproved').hasMatch(bridge),
      isFalse,
    );
  });

  test('Windows: a --login start shows no window; the bridge is built and '
      'its policy tested', () {
    expect(_code(_cppMain), contains('IsLoginLaunch'));
    expect(_read(_cmake), contains('"login_item_bridge.cpp"'));
    expect(
      _read('tool/test_windows_policy.sh'),
      contains('login_item_policy_test'),
    );
  });
}
