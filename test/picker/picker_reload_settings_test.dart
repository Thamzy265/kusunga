// M1.8: after an import with "Also use the settings in this file", the
// picker uses the imported paste mode at once.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';

import '../support/fakes.dart';
import 'fake_picker_port.dart';

void main() {
  testWidgets('reloadSettings reads the saved paste mode again', (
    tester,
  ) async {
    final history = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
    )..start();
    addTearDown(history.dispose);
    final c = PickerController(
      port: FakePickerPort(),
      log: FakeLog(),
      isMac: true,
    );
    await c.attach(history);
    expect(c.pasteMode, PasteMode.auto);
    history.saveSetting('paste_mode', 'copy_only');
    var told = 0;
    c.addListener(() => told++);
    c.reloadSettings();
    expect(c.pasteMode, PasteMode.copyOnly);
    expect(told, greaterThan(0));
    c.dispose();
  });
}
