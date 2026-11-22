import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';

/// Closes [service] (which closes its store and the database file), then
/// disposes it.
///
/// `dispose()` alone leaves the file open (it only marks the service closed),
/// and Windows refuses to delete an open file, so a later tear-down that
/// deletes the temp folder fails with errno 32. macOS allows it, which is why
/// only the Windows run showed it. Safe after the service was already closed.
Future<void> closeAndDispose(HistoryService service) async {
  await service.close();
  service.dispose();
}

/// Registers [closeAndDispose] as a tear-down.
///
/// Tear-downs run last-registered-first, so call this after the tear-down that
/// deletes the folder is registered (for example in the test body, after a
/// group `tearDown`): the database is then closed before the folder goes.
void addCloseTearDown(HistoryService service) =>
    addTearDown(() => closeAndDispose(service));
