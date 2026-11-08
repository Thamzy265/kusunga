import 'dart:async';

import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';

/// A pretend native watcher: records every call, answers what the test says.
class FakeTypedShortcutsPort implements TypedShortcutsPort {
  final controller = StreamController<TypedShortcutEvent>.broadcast(sync: true);
  final calls = <String>[];
  final tables = <List<({int id, String shortcut})>>[];
  final ignoredSent = <List<String>>[];
  final replaced = <(int, String)>[];

  /// What setEnabled(true) answers.
  TypedShortcutStatus onStatus = TypedShortcutStatus.on;
  ReplaceOutcome replaceAnswer = ReplaceOutcome.replaced;
  bool listenAnswer = false;
  List<RunningApp> apps = const [];

  /// When set, setEnabled waits for it (to test "Starting…").
  Completer<void>? holdEnable;

  @override
  Stream<TypedShortcutEvent> get events => controller.stream;

  void match(int id, int count) => controller.add(ShortcutMatched(id, count));
  void statusChanged(TypedShortcutStatus s) =>
      controller.add(ShortcutStatusChanged(s));

  @override
  Future<void> setTable(List<({int id, String shortcut})> entries) async {
    calls.add('setTable');
    tables.add(entries);
  }

  @override
  Future<void> setIgnored(List<String> appIds) async {
    calls.add('setIgnored');
    ignoredSent.add(appIds);
  }

  @override
  Future<TypedShortcutStatus> setEnabled(bool on) async {
    calls.add('setEnabled($on)');
    await holdEnable?.future;
    return on ? onStatus : TypedShortcutStatus.off;
  }

  @override
  Future<TypedShortcutStatus> status() async => TypedShortcutStatus.off;

  @override
  Future<ReplaceOutcome> replace(int deleteCount, String text) async {
    calls.add('replace');
    replaced.add((deleteCount, text));
    return replaceAnswer;
  }

  @override
  Future<List<RunningApp>> runningApps() async {
    calls.add('runningApps');
    return apps;
  }

  @override
  Future<bool> requestListenAccess() async {
    calls.add('requestListenAccess');
    return listenAnswer;
  }

  @override
  Future<void> openInputMonitoringSettings() async {
    calls.add('openInputMonitoringSettings');
  }
}
