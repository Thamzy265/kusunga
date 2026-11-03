import 'dart:async';

import 'history_service.dart';

/// The history while it may still be opening. On quit, a history that has
/// not finished opening has nothing on disk to flush, so closing does not
/// wait for it (waiting could leave an invisible process for up to the
/// keychain timeout).
class HistoryHandle {
  HistoryHandle(Future<HistoryService> opening) {
    opening.then<void>((s) => _opened = s, onError: (Object _) {});
  }

  HistoryService? _opened;

  Future<void> close() async => _opened?.close();
}
