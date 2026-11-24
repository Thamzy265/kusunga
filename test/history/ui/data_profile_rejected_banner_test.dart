import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../picker/fake_picker_port.dart';
import '../../support/fakes.dart';

/// QA-M14-6 (QA session 4, Debug builds only): a test-profile switch that
/// was not recognised runs memory only, and the banner blamed the keychain.
/// It names the switch instead; every other memory-only case keeps the
/// keychain text.
void main() {
  const keychainText =
      "History won't be kept after you quit, because Kusunga can't reach "
      'your keychain.';
  const switchText =
      "History won't be kept after you quit, because the test profile switch "
      "wasn't recognised.";

  late HistoryService service;

  setUp(() {
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
      notices: {HistoryNotice.memoryOnly},
      snippetStore: MemorySnippetStore(),
    )..start();
  });
  tearDown(() => service.dispose());

  Future<void> show(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump();
  }

  Widget host({required bool rejected}) => MaterialApp(
    theme: KusungaTokens.themeData(Brightness.light),
    home: HistoryHost(
      history: Future.value(service),
      dataProfileRejected: rejected,
    ),
  );

  testWidgets('a rejected switch: the banner names the switch, not the '
      'keychain', (tester) async {
    await show(tester, host(rejected: true));
    expect(find.text(switchText), findsOneWidget);
    expect(find.text(keychainText), findsNothing);
  });

  testWidgets('no rejected switch (and every Release build): the keychain '
      'text, unchanged', (tester) async {
    await show(tester, host(rejected: false));
    expect(find.text(keychainText), findsOneWidget);
    expect(find.text(switchText), findsNothing);
  });

  group('the Snippets tab', () {
    const snippetsKeychainText =
        "Snippets can't be opened right now, because Kusunga can't reach "
        'your keychain.';
    const snippetsSwitchText =
        "Snippets can't be opened right now, because the test profile switch "
        "wasn't recognised.";

    Future<void> openSnippets(WidgetTester tester) async {
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.identifier == 'main-tab-snippets',
        ),
      );
      await tester.pump();
    }

    testWidgets('a rejected switch: the banner names the switch, not the '
        'keychain', (tester) async {
      await show(tester, host(rejected: true));
      await openSnippets(tester);
      expect(find.text(snippetsSwitchText), findsOneWidget);
      expect(find.text(snippetsKeychainText), findsNothing);
    });

    testWidgets('no rejected switch (and every Release build): the keychain '
        'text, unchanged', (tester) async {
      await show(tester, host(rejected: false));
      await openSnippets(tester);
      expect(find.text(snippetsKeychainText), findsOneWidget);
      expect(find.text(snippetsSwitchText), findsNothing);
    });

    testWidgets('the app passes it to the Snippets tab', (tester) async {
      await show(
        tester,
        KusungaApp(history: Future.value(service), dataProfileRejected: true),
      );
      await openSnippets(tester);
      expect(find.text(snippetsSwitchText), findsOneWidget);
    });
  });

  testWidgets('the app passes it to the main window', (tester) async {
    await show(
      tester,
      KusungaApp(history: Future.value(service), dataProfileRejected: true),
    );
    expect(find.text(switchText), findsOneWidget);
    expect(find.text(keychainText), findsNothing);
  });

  testWidgets('with the picker (Mac and Windows), the app passes it to the '
      'main window too', (tester) async {
    final controller = PickerController(
      port: FakePickerPort(),
      log: FakeLog(),
      isMac: true,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.attach(service);
    await show(
      tester,
      KusungaApp(
        history: Future.value(service),
        picker: controller,
        dataProfileRejected: true,
      ),
    );
    expect(find.text(switchText), findsOneWidget);
    expect(find.text(keychainText), findsNothing);
  });
}
