import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../log/app_log.dart';
import 'key_store.dart';

/// A test data profile, for Debug builds only (PM decision 2026-11-05, "Add
/// a test profile"): launched with `-KusungaDataProfile <name>`, Kusunga
/// keeps its database, backups, moved-aside files, settings and log in
/// `<support>/profiles/<name>/` and never touches the default folder. QA uses
/// it to test the history limit without the PM's own history.
sealed class DataProfile {
  const DataProfile();
}

/// No switch (and always in Release): the default folder.
class NoDataProfile extends DataProfile {
  const NoDataProfile();
}

class ActiveDataProfile extends DataProfile {
  const ActiveDataProfile(this.name);

  /// `[a-z0-9-]{1,32}`: no separators, no dots, so never a path.
  final String name;
}

/// The switch was given with a name that is not allowed (or twice, or with
/// no name). Nothing is read or written anywhere: the session is memory
/// only. Falling back to the default folder could cost the PM real data.
class RejectedDataProfile extends DataProfile {
  const RejectedDataProfile([this.detail]);

  /// The `detail` logged with `dataProfileRejected`, or null for a bad name.
  final int? detail;
}

/// The `detail` of `dataProfileRejected` for a misspelled switch (reviewer
/// P1, BUG-Q1): `-KusungaDataProfil`, `-KusungaDataProfle`, a lost or
/// typographic dash, spaces or quotes around it, the switch split in two.
const dataProfileMisspeltDetail = 3;

const _flag = '-KusungaDataProfile';
final _safeName = RegExp(r'^[a-z0-9-]{1,32}$');

/// What a switch can start with: `-`, `/`, and every dash or minus that
/// autocorrect, a doc or a keyboard can put there (BUG-Q1d).
const _dashes = '-/\u2010\u2011\u2012\u2013\u2014\u2015\u2212\uFE63\uFF0D';

/// Whitespace (a no-break space too) and straight or curly quotes before the
/// switch, from a pasted doc or shell line (BUG-Q1e).
final _leadingSpaceOrQuotes = RegExp('^[\\s"\'\u201C\u201D\u2018\u2019]+');

/// Dropped by [_fold]: whitespace, quotes, `_` and every dash of [_dashes].
final _separators = RegExp(
  '[\\s"\'\u201C\u201D\u2018\u2019_/\\-\u2010-\u2015\u2212\uFE63\uFF0D]',
);

/// The switch folded by [_fold].
const _switchFolded = 'kusungadataprofile';

/// Edits (a letter dropped, added or changed, or two neighbours swapped)
/// that still count as the switch (BUG-Q1a). An argument needs at least 15
/// letters, nearly all of them the switch's in its order, to come this
/// close, so a short or unrelated argument never does.
const _maxEdits = 3;

/// Only this many folded letters can matter: a longer start of an argument
/// is more than [_maxEdits] edits from the switch.
const _foldedReach = _switchFolded.length + _maxEdits;

/// [arg] in lower case without whitespace, quotes, `_` or dashes, cut to
/// [_foldedReach] letters: ` "–Kusunga-Data_Profile` becomes
/// `kusungadataprofile`.
String _fold(String arg) {
  final folded = arg.toLowerCase().replaceAll(_separators, '');
  return folded.length > _foldedReach
      ? folded.substring(0, _foldedReach)
      : folded;
}

/// Whether [folded] starts with the switch give or take [_maxEdits] edits,
/// so `kusungadataprofle`, `kusunagdataprofile` and `kusungadataprofile=qa`
/// count. The edit count is the optimal string alignment distance
/// (Damerau-Levenshtein, where swapping two neighbouring letters is one
/// edit) between the switch and the closest start of [folded].
bool _startsNearTheSwitch(String folded) {
  const s = _switchFolded;
  final t = folded.length > _foldedReach
      ? folded.substring(0, _foldedReach)
      : folded;
  // d[i][j]: the edits between the first i letters of s and the first j of t.
  final d = [
    for (var i = 0; i <= s.length; i++)
      List<int>.generate(t.length + 1, (j) => i == 0 ? j : (j == 0 ? i : 0)),
  ];
  for (var i = 1; i <= s.length; i++) {
    for (var j = 1; j <= t.length; j++) {
      var best = min(
        min(d[i - 1][j], d[i][j - 1]) + 1,
        d[i - 1][j - 1] + (s[i - 1] == t[j - 1] ? 0 : 1),
      );
      if (i > 1 && j > 1 && s[i - 1] == t[j - 2] && s[i - 2] == t[j - 1]) {
        best = min(best, d[i - 2][j - 2] + 1);
      }
      d[i][j] = best;
    }
  }
  return d[s.length].reduce(min) <= _maxEdits;
}

/// An argument that looks like an attempt at the switch:
/// - it starts like a switch (after any whitespace or quotes, a dash of
///   [_dashes] or `/`) and holds both "kusunga" and "profil" in any case,
///   order or spelling around them (reviewer P1); or
/// - [folded] (the argument through [_fold]) starts within [_maxEdits]
///   edits of the switch, with or without a dash (BUG-Q1a, Q1c, Q1d, Q1e).
bool _looksLikeTheSwitch(String arg, String folded) {
  final start = arg.replaceFirst(_leadingSpaceOrQuotes, '');
  if (start.isNotEmpty && _dashes.contains(start[0])) {
    final lower = start.toLowerCase();
    if (lower.contains('kusunga') && lower.contains('profil')) return true;
  }
  return _startsNearTheSwitch(folded);
}

/// Whether any argument other than the exact switch looks like an attempt
/// at it, alone or read together with its neighbour (a space typed inside
/// it: `-Kusunga DataProfile qa`, BUG-Q1f). The exact switch is never read
/// with a neighbour: `YES` before it is only three letters away.
bool _hasMisspeltSwitch(List<String> args) {
  final folded = [for (final a in args) a == _flag ? null : _fold(a)];
  for (var i = 0; i < args.length; i++) {
    final here = folded[i];
    if (here == null) continue;
    if (_looksLikeTheSwitch(args[i], here)) return true;
    final next = i + 1 < args.length ? folded[i + 1] : null;
    if (next != null && _startsNearTheSwitch(here + next)) return true;
  }
  return false;
}

/// The profile from the launch arguments. [debug] is only for tests: a
/// Release or Profile build ignores the switch.
DataProfile dataProfileFrom(List<String> args, {bool debug = kDebugMode}) {
  if (!debug) return const NoDataProfile();
  // A mistyped or misspelled switch (`-KusungaDataProfile=qa`,
  // `-KusungaDataProfle`, `KusungaDataProfile`, `−KusungaDataProfile`,
  // ` "-KusungaDataProfile"`, `-Kusunga DataProfile`, any case) is rejected
  // too: it must never mean the real folder (reviewer P1, BUG-Q1).
  if (_hasMisspeltSwitch(args)) {
    return const RejectedDataProfile(dataProfileMisspeltDetail);
  }
  final at = args.indexOf(_flag);
  if (at < 0) return const NoDataProfile();
  if (at + 1 >= args.length || args.lastIndexOf(_flag) != at) {
    return const RejectedDataProfile();
  }
  final name = args[at + 1];
  return _safeName.hasMatch(name)
      ? ActiveDataProfile(name)
      : const RejectedDataProfile();
}

/// The data folder and key store to open the history with. Logs closed codes
/// only (`dataProfileActive`, `dataProfileRejected`), never the name or the
/// path.
///
/// The profile reuses the database key already in the keychain, so there is
/// no new keychain item and no new prompt. It never writes a key: with none
/// yet, a new one would replace the real one and make the real history
/// unreadable, so the profile is memory only instead.
({Future<Directory> Function() supportDirectory, KeyStore keys})
dataProfileSetup(
  DataProfile profile, {
  required Future<Directory> Function() supportDirectory,
  required KeyStore keys,
  required ErrorLog log,
}) {
  switch (profile) {
    case NoDataProfile():
      return (supportDirectory: supportDirectory, keys: keys);
    case RejectedDataProfile(:final detail):
      log.log(LogCode.dataProfileRejected, detail);
      return (
        supportDirectory: () async =>
            throw const FileSystemException('data profile rejected'),
        keys: keys,
      );
    case ActiveDataProfile(:final name):
      log.log(LogCode.dataProfileActive);
      return (
        supportDirectory: () async {
          final base = await supportDirectory();
          return _profileFolder(base, name, log);
        },
        keys: _ReadOnlyKeyStore(keys, log),
      );
  }
}

/// The `detail` of `dataProfileRejected` when a link was found on the way to
/// the profile folder.
const dataProfileLinkDetail = 2;

/// `<base>/profiles/<name>`, or a throw (so the session is memory only and
/// creates nothing) if `profiles` or `profiles/<name>` is a link, the
/// folder resolves anywhere else, or anything in it is a link (or a hard
/// link to a file of the default folder). A link there
/// could point at the default folder, and Trim or Clear history would then
/// delete real data (BUG-P1, BUG-P2).
Directory _profileFolder(Directory base, String name, ErrorLog log) {
  final sep = Platform.pathSeparator;
  final profiles = '${base.path}${sep}profiles';
  final folder = '$profiles$sep$name';
  Never refuse() {
    log.log(LogCode.dataProfileRejected, dataProfileLinkDetail);
    throw const FileSystemException('data profile path has a link');
  }

  for (final path in [profiles, folder]) {
    if (FileSystemEntity.isLinkSync(path)) refuse();
  }
  if (Directory(folder).existsSync()) {
    final real = Directory(folder).resolveSymbolicLinksSync();
    final expected =
        '${base.resolveSymbolicLinksSync()}${sep}profiles$sep$name';
    if (real != expected) refuse();
    // A linked file inside (the database and its -wal/-shm, the log, the
    // .bak, a moved-aside file) would be read, appended to or overwritten
    // through the link: refuse before anything is opened (BUG-P2).
    final entries = Directory(folder).listSync(followLinks: false);
    if (entries.any((e) => e is Link)) refuse();
    // A hard link is not a Link: it is a second name for the same file, and
    // dart:io has no link count. identicalSync compares the device and inode
    // (Mac) or the volume and file id (Windows), so a profile file that is
    // the default folder's database, log, backup or moved-aside file under
    // another name is refused too (BUG-P3).
    final defaultFiles = base
        .listSync(followLinks: false)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
    for (final file in entries.whereType<File>()) {
      for (final path in defaultFiles) {
        if (FileSystemEntity.identicalSync(file.path, path)) refuse();
      }
    }
  }
  return Directory(folder);
}

class _ReadOnlyKeyStore implements KeyStore {
  _ReadOnlyKeyStore(this._inner, this._log);

  final KeyStore _inner;
  final ErrorLog _log;

  @override
  Future<String?> read() => _inner.read();

  @override
  Future<void> write(String keyHex) async {
    _log.log(LogCode.dataProfileNoKey);
    throw StateError('a data profile never writes a key');
  }
}
