import 'snippet.dart';

/// Where saved snippets are kept: the `snippets` table in the same encrypted
/// database as history (design note, option A), or memory only. Calls are
/// synchronous, and every change is one transaction.
///
/// Snippets are never touched by the history limit or by Clear history.
abstract interface class SnippetStore {
  /// The most snippets kept (design note, "Cap").
  static const maxCount = 1000;

  int get count;

  /// In the user's order (by position).
  List<SnippetItem> list();

  /// The whole text of a snippet, or null if it is gone.
  String? contentOf(int id);

  /// Adds a snippet at the end and returns its id. [name] must already be
  /// normalised (see `normaliseName`). Throws [ArgumentError] for a bad name
  /// or content, and [SnippetCapReached] at 1,000 snippets.
  int insert({
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
  });

  /// Changes a snippet and keeps its place. Returns false if it is gone.
  bool update(
    int id, {
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
  });

  /// Moves a snippet to [toIndex] (clamped to the list) and renumbers every
  /// position 0..n-1 in one transaction. Returns false if it is gone.
  bool move(int id, int toIndex);

  /// Removes a snippet and returns it so Undo can put it back, or null.
  SnippetRecord? delete(int id);

  /// Puts a deleted snippet back at its old position (Undo). Throws
  /// [SnippetCapReached] if the list is full again.
  void restore(SnippetRecord record);

  void close();
}

/// The new order of [ids] after moving [id] to [toIndex], or null if [id] is
/// not there.
List<int>? reorder(List<int> ids, int id, int toIndex) {
  final from = ids.indexOf(id);
  if (from < 0) return null;
  final next = List.of(ids)..removeAt(from);
  next.insert(toIndex.clamp(0, next.length), id);
  return next;
}
