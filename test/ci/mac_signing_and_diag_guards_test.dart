import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';

/// Guards for 0888574 and d94a892 on the Mac: the optional local signing file,
/// the deployment target, the debug-only force-post switch and the diagnostics
/// channel. These read the sources and the Xcode settings; nothing is built or
/// signed.
String read(String path) => File(path).readAsStringSync();

String stripComments(String swift) =>
    swift.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  group('optional Local.xcconfig (d94a892)', () {
    test('AppInfo.xcconfig includes it with the optional form only', () {
      final lines = read('macos/Runner/Configs/AppInfo.xcconfig').split('\n');
      final includes = lines.where((l) => l.trimLeft().startsWith('#include'));
      expect(includes.where((l) => l.contains('Local.xcconfig')), [
        '#include? "Local.xcconfig"',
      ]);
    });

    test('no other xcconfig or project file pulls in Local.xcconfig', () {
      final others = [
        'macos/Runner/Configs/Debug.xcconfig',
        'macos/Runner/Configs/Release.xcconfig',
        'macos/Runner/Configs/Warnings.xcconfig',
        'macos/Flutter/Flutter-Debug.xcconfig',
        'macos/Flutter/Flutter-Release.xcconfig',
        'macos/Runner.xcodeproj/project.pbxproj',
      ];
      for (final f in others) {
        expect(read(f), isNot(contains('Local.xcconfig')), reason: f);
      }
    });

    test('the real file is git-ignored and never tracked', () {
      final ignored = Process.runSync('git', [
        'check-ignore',
        '-q',
        'macos/Runner/Configs/Local.xcconfig',
      ]);
      expect(ignored.exitCode, 0, reason: 'Local.xcconfig must be ignored');
      final tracked = Process.runSync('git', [
        'ls-files',
        '--',
        'macos/Runner/Configs/Local.xcconfig',
      ]);
      expect((tracked.stdout as String).trim(), isEmpty);
    });

    test(
      'the example is tracked, not ignored, and holds a placeholder only',
      () {
        final ignored = Process.runSync('git', [
          'check-ignore',
          '-q',
          'macos/Runner/Configs/Local.xcconfig.example',
        ]);
        expect(ignored.exitCode, 1, reason: 'the example must be committed');
        final example = read('macos/Runner/Configs/Local.xcconfig.example');
        expect(example, contains('DEVELOPMENT_TEAM = YOURTEAMID'));
        // Only these three keys are set.
        final keys = [
          for (final l in example.split('\n'))
            if (l.contains('=') && !l.trimLeft().startsWith('//'))
              l.split('=').first.trim(),
        ];
        expect(keys, [
          'DEVELOPMENT_TEAM',
          'CODE_SIGN_STYLE',
          'CODE_SIGN_IDENTITY',
        ]);
      },
    );

    test('no tracked file carries a real team id or signing identity', () {
      final tracked =
          (Process.runSync('git', [
                    'ls-files',
                    'macos',
                    'ios',
                    'tool',
                    '.github',
                  ]).stdout
                  as String)
              .split('\n')
              .where((f) => f.isNotEmpty && File(f).existsSync());
      final teamId = RegExp(r'DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10})\b');
      for (final f in tracked) {
        if (f.endsWith('.png') || f.endsWith('.icns')) continue;
        final text = File(f).readAsStringSync();
        for (final m in teamId.allMatches(text)) {
          expect(m.group(1), 'YOURTEAMID', reason: 'a real team id in $f');
        }
      }
      // If a developer has a local file, its team id is nowhere in the repo.
      final local = File('macos/Runner/Configs/Local.xcconfig');
      if (local.existsSync()) {
        final m = RegExp(
          r'DEVELOPMENT_TEAM\s*=\s*(\S+)',
        ).firstMatch(local.readAsStringSync());
        final id = m?.group(1);
        if (id != null && id != 'YOURTEAMID') {
          for (final f in tracked) {
            if (f.endsWith('.png') || f.endsWith('.icns')) continue;
            expect(
              File(f).readAsStringSync().contains(id),
              isFalse,
              reason: 'the local team id leaked into $f',
            );
          }
        }
      }
    });

    test('the project itself stays ad-hoc: identity "-", no team', () {
      final pbx = read('macos/Runner.xcodeproj/project.pbxproj');
      expect(pbx, isNot(contains('DEVELOPMENT_TEAM')));
      expect(
        RegExp(r'PROVISIONING_PROFILE\w* = "[^"]+"').hasMatch(pbx),
        isFalse,
        reason: 'a pinned profile would break ad-hoc builds',
      );
      expect(pbx, contains('CODE_SIGN_IDENTITY = "-";'));
      expect(pbx, isNot(contains('Apple Development')));
      expect(pbx, isNot(contains('Developer ID')));
    });

    test('the deployment target is 12.0 everywhere and follows the plist', () {
      final pbx = read('macos/Runner.xcodeproj/project.pbxproj');
      final targets = RegExp(
        r'MACOSX_DEPLOYMENT_TARGET = ([\d.]+);',
      ).allMatches(pbx).map((m) => m.group(1)).toSet();
      expect(targets, {'12.0'});
      expect(
        read('macos/Runner/Info.plist'),
        contains(r'$(MACOSX_DEPLOYMENT_TARGET)'),
      );
      // The unified log API used by DiagLog (Logger) needs macOS 11 or later.
      expect(read('macos/Runner/DiagLog.swift'), contains('Logger('));
    });

    final xcodebuild = Platform.isMacOS
        ? Process.runSync('which', ['xcodebuild']).exitCode == 0
        : false;

    Map<String, String> settings(Directory macos, String config) {
      final r = Process.runSync('xcodebuild', [
        '-project',
        '${macos.path}/Runner.xcodeproj',
        '-scheme',
        'Runner',
        '-configuration',
        config,
        '-showBuildSettings',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return {
        for (final l in (r.stdout as String).split('\n'))
          if (RegExp(r'^\s+[A-Z_]+ = ').hasMatch(l))
            l.split(' = ').first.trim(): l
                .split(' = ')
                .skip(1)
                .join(' = ')
                .trim(),
      };
    }

    // A copy in a temp folder, so the real Local.xcconfig (and any build that
    // is running) is never touched. -showBuildSettings builds and signs nothing.
    Directory copyMacos() {
      final tmp = Directory.systemTemp.createTempSync('kusunga-xcconfig');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final r = Process.runSync('cp', ['-R', 'macos', '${tmp.path}/macos']);
      expect(r.exitCode, 0);
      final copy = Directory('${tmp.path}/macos');
      File('${copy.path}/Runner/Configs/Local.xcconfig').createSync();
      File('${copy.path}/Runner/Configs/Local.xcconfig').deleteSync();
      return copy;
    }

    test(
      'a build without Local.xcconfig is ad-hoc signed with no team',
      () {
        final macos = copyMacos();
        for (final config in ['Debug', 'Release', 'Profile']) {
          final s = settings(macos, config);
          expect(s['CODE_SIGN_IDENTITY'], '-', reason: config);
          expect(s['DEVELOPMENT_TEAM'], isNull, reason: config);
          expect(s['MACOSX_DEPLOYMENT_TARGET'], '12.0', reason: config);
        }
      },
      skip: xcodebuild ? false : 'needs xcodebuild on a Mac',
    );

    test(
      'with a Local.xcconfig the team and identity are picked up',
      () {
        final macos = copyMacos();
        File('${macos.path}/Runner/Configs/Local.xcconfig').writeAsStringSync(
          'DEVELOPMENT_TEAM = TESTTEAM00\n'
          'CODE_SIGN_STYLE = Automatic\n'
          'CODE_SIGN_IDENTITY = Apple Development\n',
        );
        final s = settings(macos, 'Debug');
        expect(s['DEVELOPMENT_TEAM'], 'TESTTEAM00');
        expect(s['CODE_SIGN_IDENTITY'], 'Apple Development');
      },
      skip: xcodebuild ? false : 'needs xcodebuild on a Mac',
    );
  });

  group('debug-only force-post switch (6e24bed)', () {
    final swift = stripComments(read('macos/Runner/PasteFlow.swift'));

    String realPlatformSwitch() {
      final start = swift.indexOf('func forcePostEnabled() -> Bool {\n    #if');
      expect(start, isNonNegative, reason: 'the real switch is in #if DEBUG');
      return swift.substring(start, swift.indexOf('func pasteKeyCode', start));
    }

    test('the real answer is read only inside #if DEBUG, false in Release', () {
      final body = realPlatformSwitch();
      final ifDebug = body.indexOf('#if DEBUG');
      final elseAt = body.indexOf('#else');
      final endAt = body.indexOf('#endif');
      expect(ifDebug, lessThan(elseAt));
      expect(elseAt, lessThan(endAt));
      expect(
        body.substring(ifDebug, elseAt),
        contains('UserDefaults.standard.bool(forKey: "KusungaForcePost")'),
      );
      expect(
        body.substring(elseAt, endAt).replaceAll(RegExp(r'\s+'), ' ').trim(),
        '#else return false',
      );
    });

    test('the key name appears nowhere else in the app sources', () {
      final files = [
        for (final e in Directory('macos/Runner').listSync(recursive: true))
          if (e is File && e.path.endsWith('.swift')) e.path,
        for (final e in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart')) e.path,
        for (final e in Directory('windows/runner').listSync(recursive: true))
          if (e is File && (e.path.endsWith('.cpp') || e.path.endsWith('.h')))
            e.path,
      ];
      for (final f in files) {
        final text = stripComments(File(f).readAsStringSync());
        if (f.endsWith('PasteFlow.swift')) {
          expect('KusungaForcePost'.allMatches(text).length, 1, reason: f);
        } else {
          expect(text, isNot(contains('KusungaForcePost')), reason: f);
        }
      }
    });

    test('nothing enables it from the project, plist, entitlements or CI', () {
      for (final f in [
        'macos/Runner/Info.plist',
        'macos/Runner/Release.entitlements',
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner.xcodeproj/project.pbxproj',
        '.github/workflows/check.yml',
        'tool/check.sh',
        'tool/check.ps1',
      ]) {
        if (File(f).existsSync()) {
          expect(read(f), isNot(contains('KusungaForcePost')), reason: f);
        }
      }
      final shared = Directory(
        'macos/Runner.xcodeproj/xcshareddata',
      ).existsSync();
      if (shared) {
        for (final e in Directory(
          'macos/Runner.xcodeproj/xcshareddata',
        ).listSync(recursive: true).whereType<File>()) {
          expect(
            e.readAsStringSync(),
            isNot(contains('KusungaForcePost')),
            reason: e.path,
          );
        }
      }
    });

    test('the default for any other platform is off', () {
      expect(
        swift,
        contains(
          'extension PastePlatform {\n  func forcePostEnabled() -> Bool { false }',
        ),
      );
    });

    test('the flow forces only after the permission check says no, never '
        'before the target and focus checks', () {
      final from = swift.indexOf('private func steps');
      final run = swift.substring(
        from,
        swift.indexOf('private func waitUntil'),
      );
      final target = run.indexOf('platform.isRunning(target)');
      final focus = run.indexOf('platform.frontmostPid() == target }');
      final force = run.indexOf('platform.forcePostEnabled()');
      final recheck = run.indexOf('let frontOk');
      final post = run.indexOf('platform.postPaste()');
      expect(target, lessThan(focus));
      expect(focus, lessThan(force));
      expect(force, lessThan(recheck));
      expect(recheck, lessThan(post));
      expect('forcePostEnabled'.allMatches(run).length, 1);
      expect('postPaste()'.allMatches(run).length, 1);
    });

    test('Dart never asks for a forced post', () {
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          final t = f.readAsStringSync();
          expect(t.contains('force:'), isFalse, reason: f.path);
          expect(t.contains("'force'"), isFalse, reason: f.path);
        }
      }
    });
  });

  group('the diagnostics channel (0888574)', () {
    final bridge = stripComments(read('macos/Runner/PickerBridge.swift'));
    final diag = read('macos/Runner/DiagLog.swift');

    test('Dart and Mac use the same channel and method names', () {
      expect(
        read('lib/log/unified_log.dart'),
        contains("'com.wnasoni.kusunga/diag'"),
      );
      expect(bridge, contains('name: "com.wnasoni.kusunga/diag"'));
      expect(read('lib/log/unified_log.dart'), contains("'log'"));
      expect(bridge, contains('call.method == "log"'));
    });

    test('the Mac handler passes only a string code and an int to DiagLog', () {
      final start = bridge.indexOf('com.wnasoni.kusunga/diag');
      final end = bridge.indexOf('didTerminateApplicationNotification');
      final handler = bridge.substring(start, end);
      expect(handler, contains('args["code"] as? String'));
      expect(handler, contains('args["detail"] as? Int'));
      expect(handler, contains('DiagLog.log(code, args["detail"] as? Int)'));
      // Anything else is refused, not logged.
      expect(handler, contains('FlutterMethodNotImplemented'));
      expect('DiagLog.log('.allMatches(handler).length, 1);
      expect(handler, isNot(contains('Logger')));
      expect(handler, isNot(contains('NSLog')));
      expect(handler, isNot(contains('print(')));
    });

    test('the only writer to the unified log checks the code first', () {
      for (final e in Directory('macos/Runner').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.swift')) continue;
        final t = stripComments(e.readAsStringSync());
        if (e.path.endsWith('DiagLog.swift')) continue;
        expect(t, isNot(contains('os_log')), reason: e.path);
        expect(t, isNot(contains('Logger(')), reason: e.path);
        expect(t, isNot(contains('NSLog')), reason: e.path);
        expect(t, isNot(contains('print(')), reason: e.path);
      }
      expect(
        diag.indexOf('guard isCode(code)'),
        lessThan(diag.indexOf('logger.info')),
      );
      expect('logger.info'.allMatches(diag).length, 2);
      expect(
        RegExp(r'privacy: \.(\w+)').allMatches(diag).map((m) => m.group(1)),
        everyElement('public'),
        reason: 'only a code and a number are logged, both public by design',
      );
      expect(diag, isNot(contains('privacy: .private')));
    });

    test('every string passed to DiagLog or diag(...) in Swift is a code', () {
      final code = RegExp(r'^[A-Za-z0-9]{1,40}$');
      final call = RegExp(r'(?:DiagLog\.log|diag)\(\s*"([^"]*)"');
      var seen = 0;
      for (final e in Directory('macos/Runner').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.swift')) continue;
        for (final m in call.allMatches(stripComments(e.readAsStringSync()))) {
          seen++;
          expect(
            code.hasMatch(m.group(1)!),
            isTrue,
            reason: '${e.path}: ${m.group(1)}',
          );
        }
      }
      expect(seen, greaterThan(15));
    });

    test('every Dart log code name passes the native check, or it would be '
        'dropped silently', () {
      final code = RegExp(r'^[A-Za-z0-9]{1,40}$');
      for (final c in LogCode.values) {
        expect(code.hasMatch(c.name), isTrue, reason: c.name);
      }
      expect(
        LogCode.values.map((c) => c.name).toSet().length,
        LogCode.values.length,
      );
    });

    test('Windows has no diag handler, so Dart must ignore its absence', () {
      expect(
        File('windows/runner/picker_bridge.cpp').readAsStringSync(),
        isNot(contains('kusunga/diag')),
      );
    });
  });

  group('the picker stays open only for a gone target (0888574)', () {
    final bridge = stripComments(read('macos/Runner/PickerBridge.swift'));

    test('Mac: both checks go through the rule and never keep it for a live '
        'target or without a target', () {
      expect('shouldDismissNow()'.allMatches(bridge).length, 3);
      final rule = bridge.substring(
        bridge.indexOf('private func shouldDismissNow'),
      );
      expect(
        rule,
        contains(r'target.map { MacPastePlatform.isAlive($0) } ?? false'),
      );
      expect(
        rule,
        contains(
          'DismissRule.shouldDismiss(target: target, targetAlive: alive)',
        ),
      );
    });

    test('Mac: a paste in progress, or a picker that is not shown, is never '
        'kept open by the new code', () {
      final lost = bridge.substring(
        bridge.indexOf('private func windowLostFocus'),
      );
      expect(
        lost.substring(0, lost.indexOf('if !shouldDismissNow()')),
        contains('windows.mode == .picker, !pasting'),
      );
      final later = lost.substring(lost.indexOf('asyncAfter'));
      expect(later, contains('windows.mode == .picker, !self.pasting'));
      // The live-target path still closes it and tells Dart.
      expect(lost, contains('self.dismissPicker()'));
      final dismiss = bridge.substring(
        bridge.indexOf('private func dismissPicker'),
      );
      expect(dismiss, contains('leavePicker'));
      expect(dismiss, contains('invokeMethod("dismissed"'));
    });

    test('Mac: keeping it open forgets the target, so a paste only copies', () {
      expect(
        RegExp(
          r'pickerKeptTargetGone[\s\S]{0,80}target = nil',
        ).allMatches(bridge).length,
        2,
      );
    });

    test('Windows: the same rule, through the tested policy function', () {
      final cpp = read('windows/runner/picker_bridge.cpp');
      expect(
        cpp,
        contains(
          'ShouldDismissOnDeactivate(target_ != nullptr,\n'
          '                                          target_ != nullptr && ::IsWindow(target_))',
        ),
      );
      final h = read('windows/runner/picker_policy.h');
      expect(
        h,
        contains(
          'inline bool ShouldDismissOnDeactivate(bool has_target, bool target_alive) {\n'
          '  return !(has_target && !target_alive);',
        ),
      );
      final i = cpp.indexOf('void PickerBridge::WindowDeactivated()');
      final fn = cpp.substring(i, cpp.indexOf('\n}\n', i));
      expect(
        fn.indexOf('pasting_'),
        lessThan(fn.indexOf('ShouldDismissOnDeactivate')),
      );
      expect(
        fn.indexOf('ShouldDismissOnDeactivate'),
        lessThan(fn.indexOf('LeavePicker')),
      );
    });
  });
}
