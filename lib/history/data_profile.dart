import 'dart:io';

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
  const RejectedDataProfile();
}

const _flag = '-KusungaDataProfile';
final _safeName = RegExp(r'^[a-z0-9-]{1,32}$');

/// The profile from the launch arguments. [debug] is only for tests: a
/// Release or Profile build ignores the switch.
DataProfile dataProfileFrom(List<String> args, {bool debug = kDebugMode}) {
  if (!debug) return const NoDataProfile();
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
    case RejectedDataProfile():
      log.log(LogCode.dataProfileRejected);
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
/// creates nothing) if `profiles` or `profiles/<name>` is a link, or the
/// folder resolves anywhere else. A link there could point at the default
/// folder, and Trim or Clear history would then delete real data (BUG-P1).
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
