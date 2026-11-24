// M1.7 reviewer F12: the one live-count dialog behind Clear history and
// Auto-delete. It follows the count, and at 0 closes as Cancel would (PM
// decision 2026-11-08); a count it could not read never closes it.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/ui/close_at_zero.dart';

void main() {
  late ValueNotifier<int?> count;
  late Future<bool?> result;

  setUp(() => count = ValueNotifier<int?>(3));
  tearDown(() => count.dispose());

  Future<BuildContext> open(WidgetTester tester) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    result = showDialog<bool>(
      context: host,
      builder: (context) => CloseAtZero(
        listenable: count,
        count: () => count.value,
        builder: (context, n) =>
            AlertDialog(content: Text(n == null ? 'unknown' : '$n items')),
      ),
    );
    await tester.pumpAndSettle();
    return host;
  }

  testWidgets('follows the count; at 0 closes as Cancel, keeping the last '
      'count while it goes', (tester) async {
    await open(tester);
    expect(find.text('3 items'), findsOneWidget);
    count.value = 2;
    await tester.pump();
    expect(find.text('2 items'), findsOneWidget);
    count.value = 0;
    await tester.pump();
    expect(find.text('0 items'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await result, isFalse);
  });

  testWidgets('a count that cannot be read never closes it', (tester) async {
    await open(tester);
    count.value = null;
    await tester.pumpAndSettle();
    expect(find.text('unknown'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('with another route on top it is removed, as Cancel', (
    tester,
  ) async {
    final host = await open(tester);
    _pushOnTop(host);
    await tester.pumpAndSettle();
    count.value = 0;
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(find.text('on top'), findsOneWidget);
  });
}

void _pushOnTop(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const Text('on top')));
}
