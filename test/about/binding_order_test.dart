// M1.9a (R1): the real binding must register Kusunga's notices BEFORE
// Flutter's own NOTICES collector. Flutter's licence page pins only the first
// package of the first collector at the top and sorts the rest, so with the
// order reversed "abseil-cpp" is pinned and Kusunga lands in the middle of
// the list. Uses the real binding (this file never starts the test binding).
import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/kusunga_binding.dart';

void main() {
  test('the first notice the real binding offers is Kusunga', () async {
    KusungaBinding.ensureInitialized();
    final first = await LicenseRegistry.licenses.first;
    expect(first.packages, ['Kusunga']);
    expect(first.paragraphs.map((p) => p.text).join(' '), contains('GNU'));
  });

  test('starting the binding twice gives the same binding', () {
    expect(
      identical(
        KusungaBinding.ensureInitialized(),
        KusungaBinding.ensureInitialized(),
      ),
      isTrue,
    );
  });

  test('main() starts the app with it, and registers nothing else first', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('KusungaBinding.ensureInitialized();'));
    expect(main, isNot(contains('WidgetsFlutterBinding.ensureInitialized')));
    expect(main, isNot(contains('registerLicences(')));
  });
}
