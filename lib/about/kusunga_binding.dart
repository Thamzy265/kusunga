import 'package:flutter/widgets.dart';

import 'licences.dart';

/// The app's binding. It differs from [WidgetsFlutterBinding] in one thing:
/// Kusunga's notices are registered before Flutter's own NOTICES collector, so
/// "Kusunga" is the package Flutter's licence page pins at the top (see
/// [registerLicences]). `main()` starts the app with
/// [KusungaBinding.ensureInitialized].
class KusungaBinding extends WidgetsFlutterBinding {
  KusungaBinding() {
    _instance = this;
  }

  static KusungaBinding? _instance;

  static WidgetsBinding ensureInitialized() => _instance ?? KusungaBinding();

  @override
  void initLicenses() {
    // Ours first: the licence page pins the first package of the first
    // collector. The binding's own NOTICES collector is added by super.
    registerLicences();
    super.initLicenses();
  }
}
