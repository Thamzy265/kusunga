import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/widgets.dart';

import 'flutter_notices.dart';
import 'licences.dart';

/// The app's binding. It differs from [WidgetsFlutterBinding] in two things:
/// Kusunga's notices are registered before Flutter's own NOTICES collector, so
/// "Kusunga" is the package Flutter's licence page pins at the top (see
/// [registerLicences]); and the NOTICES collector is [flutterNotices], which
/// leaves out the app's own LICENSE (a second "kusunga" row). `main()` starts
/// the app with [KusungaBinding.ensureInitialized].
class KusungaBinding extends WidgetsFlutterBinding {
  KusungaBinding() {
    _instance = this;
  }

  static KusungaBinding? _instance;

  static WidgetsBinding ensureInitialized() => _instance ?? KusungaBinding();

  // Flutter's own collector (added by `super`) cannot be taken out of the
  // registry again, so `super.initLicenses()` is not called: [flutterNotices]
  // does what it does, minus the app's own LICENSE. Nothing else happens in
  // `ServicesBinding.initLicenses`.
  @override
  // ignore: must_call_super
  void initLicenses() {
    // Ours first: the licence page pins the first package of the first
    // collector.
    registerLicences();
    LicenseRegistry.addLicense(flutterNotices);
  }
}
