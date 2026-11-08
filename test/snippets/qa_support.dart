import 'snippet_service_test.dart' show FlakySnippetStore;

/// A memory store whose full-text read can be made to fail, like a database
/// that cannot be read for a moment (the list, which holds only previews,
/// still works). Writes can be made to fail as well (see [FlakySnippetStore]).
class ContentReadFailsStore extends FlakySnippetStore {
  bool failContentReads = false;

  @override
  String? contentOf(int id) {
    if (failContentReads) throw StateError('read failed');
    return super.contentOf(id);
  }
}
