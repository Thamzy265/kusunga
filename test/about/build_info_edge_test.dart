// M1.9a tester: odd --dart-define values and the source-link tag rule
// (docs/ui/about-and-licences.md: "Source link", "States matrix").
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/build_info.dart';

const _repo = 'https://github.com/Thamzy265/kusunga';

BuildInfo info(String version, String build, {bool dev = false}) =>
    BuildInfo(version: version, build: build, development: dev);

void main() {
  group('source-link tag rule', () {
    for (final (dev, version, expected) in [
      (false, '0.9.0', '$_repo/tree/v0.9.0'),
      (false, '1.0.0-beta.2', '$_repo/tree/v1.0.0-beta.2'),
      (true, '0.9.0', _repo),
      (true, '', _repo),
      (false, '', _repo),
    ]) {
      test('development=$dev version="$version" links $expected', () {
        expect(info(version, '1', dev: dev).sourceUrl, expected);
      });
    }

    test('a development build never links a tag, whatever the version', () {
      for (final v in ['0.9.0', '9.9.9', '0.0.0-dev']) {
        expect(info(v, '1', dev: true).sourceUrl, isNot(contains('/tree/')));
      }
    });

    test('the caption appears for a development build only', () {
      expect(info('0.9.0', '1', dev: true).caption, 'Development build');
      expect(info('0.9.0', '1').caption, isNull);
      expect(info('', '', dev: true).caption, 'Development build');
      expect(info('', '').caption, isNull);
    });
  });

  group('version and build combinations', () {
    test('only a build number set: the version is unknown, build ignored', () {
      final i = info('', '7');
      expect(i.versionLine, 'Kusunga (version unknown)');
      expect(i.copyText, 'Kusunga (version unknown)');
      expect(i.sourceUrl, _repo);
      expect(i.licenceVersion, isNull);
      expect(i.copyVersionLabel, 'Copy version');
    });

    test('version set, build empty: "Kusunga 0.9.0" in every surface', () {
      final i = info('0.9.0', '');
      expect(i.versionLine, 'Kusunga 0.9.0');
      expect(i.copyText, 'Kusunga 0.9.0');
      expect(i.licenceVersion, '0.9.0');
      expect(i.copyVersionLabel, 'Copy version 0.9.0');
      expect(i.sourceUrl, '$_repo/tree/v0.9.0');
    });

    test('version set, build empty, development build', () {
      final i = info('0.9.0', '', dev: true);
      expect(i.versionLine, 'Kusunga 0.9.0 — development build');
      expect(i.copyText, i.versionLine);
    });

    test('unknown version in a development build', () {
      final i = info('', '', dev: true);
      expect(i.versionLine, 'Kusunga (version unknown) — development build');
      expect(i.copyText, i.versionLine);
    });

    test('a very long version keeps every character, no truncation', () {
      final v = '1.' * 400;
      final i = info(v, '99999999999999');
      expect(i.versionLine, contains(v));
      expect(i.sourceUrl, '$_repo/tree/v$v');
      expect(i.copyText, i.versionLine);
    });

    test('non-ASCII and "-" prerelease text pass through unchanged', () {
      final i = info('0.9.0-β.1', '1');
      expect(i.versionLine, 'Kusunga 0.9.0-β.1 (build 1)');
    });
  });

  // BUGS: a mistyped --dart-define is shown as it is, and builds a broken
  // link. The release script sets these, so the risk is a typo in that
  // script, but the About screen is what a tester reads and copies.
  group('odd defines', () {
    test('a whitespace-only version is "unknown", not a known version', () {
      final i = info('   ', '1');
      expect(i.versionLine, 'Kusunga (version unknown)');
      expect(i.sourceUrl, _repo);
    });

    test('a version with spaces around it gives a link without spaces', () {
      final i = info(' 0.9.0 ', '1');
      expect(i.sourceUrl, '$_repo/tree/v0.9.0');
      expect(i.versionLine, 'Kusunga 0.9.0 (build 1)');
    });

    test('a whitespace-only build leaves the build out', () {
      expect(info('0.9.0', '  ').versionLine, 'Kusunga 0.9.0');
    });

    test('the source link never contains whitespace', () {
      expect(info('0.9.0 beta\n', '1').sourceUrl, isNot(matches(r'\s')));
    });

    test('a version already starting with "v" does not become "vv0.9.0"', () {
      expect(
        info('v0.9.0', '1').sourceUrl,
        isNot(contains('/tree/vv')),
        reason: 'the tag is v<version>; --dart-define=KUSUNGA_VERSION=v0.9.0',
      );
    });
  });
}
