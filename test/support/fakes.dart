import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/log/app_log.dart';

class FakeKeyStore implements KeyStore {
  FakeKeyStore({this.stored});

  String? stored;
  Object? readError;
  Object? writeError;

  /// If set, a read after a write returns this instead of what was written.
  String? readBackOverride;
  var _written = false;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (readError != null) throw readError!;
    if (_written && readBackOverride != null) return readBackOverride;
    return stored;
  }

  @override
  Future<void> write(String keyHex) async {
    if (writeError != null) throw writeError!;
    stored = keyHex;
    _written = true;
    writes++;
  }
}

class FakeLog implements ErrorLog {
  final codes = <LogCode>[];

  @override
  void log(LogCode code, [int? detail]) => codes.add(code);
}
