// M1.7 tester (docs/design/settings-and-expiry.md, "Observability"): the new
// log codes carry numbers only. Run the real clean-up, the failures and the
// login item through the real file log with recognisable secrets around, then
// read the file back: every line is "<time> <code>[ <number>]".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';
import 'package:kusunga/snippets/snippet.dart';

import '../support/fakes.dart';

const day = Duration.millisecondsPerDay;
const secret = 'SECRET-IBAN-GB82WEST12345698765432';

class _Port implements LoginItemPort {
  LoginItemAnswer answer = const LoginItemAnswer(LoginItemState.on);
  @override
  Future<LoginItemAnswer> status() async => answer;
  @override
  Future<LoginItemAnswer> set(bool on) async => answer;
  @override
  Future<void> openSettings() async {}
}

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_log_edge_');
    file = File('${dir.path}/kusunga.log');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('historyExpired, historyExpiryFailed, settingSaveFailed and the login '
      'codes: a code and a number, nothing else', () async {
    final store = FlakyStore(MemoryHistoryStore());
    var now = 100 * day;
    store.inner.writeSetting(historyExpirySetting, '1');
    store.inner.insertOrBump(secret, ClipKind.text, now - 5 * day);
    store.inner.insertOrBump('$secret 2', ClipKind.text, now - 4 * day);
    final service = HistoryService(
      store: store,
      source: FakeClipboardSource(),
      log: FileErrorLog(file),
      clock: () => now,
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
    service.snippets.save(
      name: secret,
      content: secret,
      type: SnippetType.other,
    );
    store.inner.insertOrBump(secret, ClipKind.text, now - 3 * day);
    now += 10 * day;
    service.expiry.cleanUp(); // historyExpired 1
    store.failWrites = true;
    service.expiry.cleanUp();
    service.expiry.cleanUp();
    service.expiry.cleanUp(); // historyExpiryFailed x3
    service.expiry.setDays(7); // settingSaveFailed
    store.failWrites = false;

    final port = _Port();
    final item = LoginItemService(port: port, log: FileErrorLog(file));
    await item.set(true);
    port.answer = const LoginItemAnswer(LoginItemState.off);
    await item.set(false);
    port.answer = const LoginItemAnswer(LoginItemState.needsApproval);
    await item.set(true);
    port.answer = const LoginItemAnswer(LoginItemState.failed, error: 13);
    await item.set(true);
    item.dispose();

    final lines = file.readAsLinesSync();
    expect(lines, isNotEmpty);
    final names = LogCode.values.map((c) => c.name).join('|');
    final shape = RegExp('^\\S+Z ($names)( -?\\d+)?\$');
    for (final line in lines) {
      expect(shape.hasMatch(line), isTrue, reason: line);
      expect(line, isNot(contains('SECRET')));
    }
    final codes = [for (final l in lines) l.split(' ')[1]];
    expect(
      codes,
      containsAll([
        'historyExpired',
        'historyExpiryFailed',
        'settingSaveFailed',
        'loginItemOn',
        'loginItemOff',
        'loginItemNeedsApproval',
        'loginItemFailed',
      ]),
    );
    expect(
      lines.any((l) => l.contains(' historyExpired ') && l.endsWith(' 2')),
      isTrue,
      reason: 'the launch clean-up removed 2',
    );
    expect(
      lines.any((l) => l.contains(' historyExpired ') && l.endsWith(' 1')),
      isTrue,
      reason: 'the later one removed 1',
    );
    expect(
      lines.where((l) => l.contains(' loginItemFailed')).single,
      endsWith(' 13'),
    );
  });

  test('no new code is logged with a string: every call site passes a '
      'number or nothing', () {
    final sources = [
      File('lib/history/expiry_service.dart').readAsStringSync(),
      File('lib/settings/login_item.dart').readAsStringSync(),
    ];
    for (final src in sources) {
      for (final m in RegExp(r'_log\.log\(([^;]*)\)').allMatches(src)) {
        final args = m.group(1)!;
        expect(args, isNot(contains("'")), reason: args);
        expect(args, isNot(contains('"')), reason: args);
        expect(args, isNot(contains(r'$')), reason: args);
      }
    }
  });
}
