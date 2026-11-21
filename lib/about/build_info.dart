import 'package:flutter/foundation.dart';

const _repo = 'https://github.com/Thamzy265/kusunga';

/// Which build is running, for the About section (M1.9a, requirements R1 and
/// R2). The version and build number are put in at build time:
///
///   flutter build macos --release \
///     --dart-define=KUSUNGA_VERSION=0.9.0 --dart-define=KUSUNGA_BUILD=1
///
/// (the release script does this; the pubspec version is not read). Without
/// them the app says the version is unknown.
class BuildInfo {
  const BuildInfo({
    required this.version,
    required this.build,
    required this.development,
  });

  /// This build's values: `--dart-define`, and debug or profile means a
  /// development build.
  static const current = BuildInfo(
    version: String.fromEnvironment('KUSUNGA_VERSION'),
    build: String.fromEnvironment('KUSUNGA_BUILD'),
    development: !kReleaseMode,
  );

  final String version;
  final String build;

  /// A debug or profile build.
  final bool development;

  bool get _known => version.isNotEmpty;

  String get _name => !_known
      ? 'Kusunga (version unknown)'
      : build.isEmpty
      ? 'Kusunga $version'
      : 'Kusunga $version (build $build)';

  /// "Kusunga 0.9.0 (build 1)", plus " — development build" when it is one.
  String get versionLine => development ? '$_name — development build' : _name;

  /// What Copy version puts on the clipboard: the whole line, so a report
  /// from a development build says so.
  String get copyText => versionLine;

  /// The source link: the tag of this build, or the plain repository for a
  /// development build or an unknown version.
  String get sourceUrl =>
      (development || !_known) ? _repo : '$_repo/tree/v$version';

  /// Shown under the source link for a development build.
  String? get caption => development ? 'Development build' : null;

  /// The version on the licence page: "0.9.0 (build 1)", or null if unknown.
  String? get licenceVersion => !_known
      ? null
      : build.isEmpty
      ? version
      : '$version (build $build)';

  /// The accessible name of Copy version.
  String get copyVersionLabel => !_known
      ? 'Copy version'
      : build.isEmpty
      ? 'Copy version $version'
      : 'Copy version $version build $build';
}
