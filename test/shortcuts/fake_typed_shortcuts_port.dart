import 'dart:async';

import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';

/// A pretend native watcher: records every call, answers what the test says.
class FakeTypedShortcutsPort implements TypedShortcutsPort {
  final controller = StreamController<TypedShortcutEvent>.broadcast(sync: true);
  final calls = <String>[];
  final tables = <List<({int id, String shortcut})>>[];
  final ignoredSent = <List<String>>[];
  final replaced = <(int, String)>[];

  /// The match id each replace answered (C2).
  final replacedMatchIds = <int>[];
  var _nextMatchId = 0;

  /// What setEnabled(true) answers.
  TypedShortcutStatus onStatus = TypedShortcutStatus.on;
  ReplaceOutcome replaceAnswer = ReplaceOutcome.replaced;
  bool listenAnswer = false;
  List<RunningApp> apps = const [];

  /// When set, setEnabled waits for it (to test "Starting…").
  Completer<void>? holdEnable;

  @override
  Stream<TypedShortcutEvent> get events => controller.stream;

  /// A match from native. Each gets a new match id unless one is given.
  void match(int id, int count, {int? matchId}) =>
      controller.add(ShortcutMatched(id, count, matchId ?? ++_nextMatchId));
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
  Future<ReplaceOutcome> replace(
    int matchId,
    int deleteCount,
    String text,
  ) async {
    calls.add('replace');
    replacedMatchIds.add(matchId);
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
