// M1.9a (docs/ui/about-and-licences.md, "Copy" and "Layout"): the version line
// and the source link, from the build-time values.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/build_info.dart';

void main() {
  test('a release build names the version, the build and the tag', () {
    const info = BuildInfo(version: '0.9.0', build: '1', development: false);
    expect(info.versionLine, 'Kusunga 0.9.0 (build 1)');
    expect(info.sourceUrl, 'https://github.com/Thamzy265/kusunga/tree/v0.9.0');
    expect(info.caption, isNull);
    expect(info.copyVersionLabel, 'Copy version 0.9.0 build 1');
  });

  test('a debug or profile build says so and links the plain repo', () {
    const info = BuildInfo(version: '0.9.0', build: '1', development: true);
    expect(info.versionLine, 'Kusunga 0.9.0 (build 1) — development build');
    expect(info.sourceUrl, 'https://github.com/Thamzy265/kusunga');
    expect(info.caption, 'Development build');
  });

  test('no version: "Kusunga (version unknown)" and the plain repo link', () {
    const info = BuildInfo(version: '', build: '', development: false);
    expect(info.versionLine, 'Kusunga (version unknown)');
    expect(info.sourceUrl, 'https://github.com/Thamzy265/kusunga');
    // Copy version copies that text.
    expect(info.versionLine, info.copyText);
  });

  test('a version without a build number leaves the build out', () {
    const info = BuildInfo(version: '0.9.0', build: '', development: false);
    expect(info.versionLine, 'Kusunga 0.9.0');
  });

  test('copyText is the version line a tester reports', () {
    const info = BuildInfo(version: '0.9.0', build: '1', development: false);
    expect(info.copyText, 'Kusunga 0.9.0 (build 1)');
  });

  test('a development build copies its development note too', () {
    const info = BuildInfo(version: '0.9.0', build: '1', development: true);
    expect(info.copyText, 'Kusunga 0.9.0 (build 1) — development build');
  });

  test('the values come from --dart-define; tests run unset and in debug', () {
    final info = BuildInfo.current;
    expect(info.version, isEmpty);
    expect(info.development, isTrue);
  });
}
