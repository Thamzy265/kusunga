import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';

void main() {
  testWidgets('home screen shows the app name', (tester) async {
    await tester.pumpWidget(const KusungaApp());

    expect(find.text('Kusunga'), findsOneWidget);
  });
}
