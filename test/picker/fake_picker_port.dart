import 'dart:async';

import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/shortcut.dart';

/// A picker port for tests: records every call and answers as told.
class FakePickerPort implements PickerPort {
  final controller = StreamController<PickerNativeEvent>.broadcast(sync: true);
  final calls = <String>[];
  final registered = <PickerShortcut>[];
  final pastes = <({String text, bool post})>[];

  /// What registerShortcut answers; a function so a test can vary it.
  ShortcutRegistration Function(PickerShortcut s) registerAnswer = (_) =>
      ShortcutRegistration.registered;
  PasteOutcome pasteAnswer = PasteOutcome.pasted;

  /// If set, paste waits for it (to test what happens in the meantime).
  Completer<void>? pasteGate;
  Object? pasteThrows;
  bool canPostAnswer = false;
  bool requestAnswer = false;

  @override
  Stream<PickerNativeEvent> get events => controller.stream;

  void press() => controller.add(const ShortcutPressed());
  void dismiss() => controller.add(const PickerDismissed());

  @override
  Future<ShortcutRegistration> registerShortcut(PickerShortcut shortcut) async {
    calls.add('register ${shortcut.serialized}');
    final r = registerAnswer(shortcut);
    if (r == ShortcutRegistration.registered) registered.add(shortcut);
    return r;
  }

  @override
  Future<void> unregisterShortcut() async => calls.add('unregister');

  @override
  Future<void> openPicker() async => calls.add('open');

  @override
  Future<void> closePicker() async => calls.add('close');

  @override
  Future<PasteOutcome> paste(String text, {required bool post}) async {
    calls.add('paste');
    pastes.add((text: text, post: post));
    if (pasteGate != null) await pasteGate!.future;
    if (pasteThrows != null) throw pasteThrows!;
    return pasteAnswer;
  }

  @override
  Future<void> showToast() async => calls.add('showToast');

  @override
  Future<void> hideToast() async => calls.add('hideToast');

  @override
  Future<bool> canPost() async {
    calls.add('canPost');
    return canPostAnswer;
  }

  @override
  Future<bool> requestPostAccess() async {
    calls.add('requestPostAccess');
    return requestAnswer;
  }
}
