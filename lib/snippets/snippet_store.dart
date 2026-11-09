import 'snippet.dart';
import 'snippet_shortcut.dart';

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
  /// normalised (see `normaliseName`). Throws [ArgumentError] for a bad name,
  /// content or [shortcut], [SnippetCapReached] at 1,000 snippets, and
  /// [ShortcutTaken] if [shortcut] clashes with another snippet's (checked
  /// in the same transaction as the write, PM decision D1 A).
  int insert({
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
    String? shortcut,
  });

  /// Changes a snippet and keeps its place. Returns false if it is gone.
  /// [shortcut] replaces the old one (null removes it); the same errors as
  /// [insert].
  bool update(
    int id, {
    required String name,
    required String content,
    required SnippetType type,
    required int nowMs,
    String? shortcut,
  });

  /// Every snippet that has a shortcut, in the user's order.
  List<ShortcutOwner> shortcuts();

  /// Moves a snippet to [toIndex] (clamped to the list) and renumbers every
  /// position 0..n-1 in one transaction. Returns false if it is gone.
  bool move(int id, int toIndex);

  /// Removes a snippet and returns it so Undo can put it back, or null.
  SnippetRecord? delete(int id);

  /// Puts a deleted snippet back at its old position (Undo). Throws
  /// [SnippetCapReached] if the list is full again. If its shortcut was given
  /// to another snippet meanwhile, it comes back without one: the snippet
  /// itself is never lost.
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
