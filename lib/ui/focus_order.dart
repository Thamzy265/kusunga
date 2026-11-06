import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Tab and Shift+Tab: focuses [node] and scrolls it fully into view, up or
/// down. Flutter's own callback only scrolls down on Tab and up on
/// Shift+Tab, so Tab to a control built above the view left the focus
/// hidden (QA-M14-5, WCAG 2.4.11).
void revealOnTraversal(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final object = node.context?.findRenderObject();
  if (object != null && object.attached) object.showOnScreen();
}

/// Reading order, with [revealOnTraversal].
FocusTraversalPolicy revealingReadingOrder() =>
    ReadingOrderTraversalPolicy(requestFocusCallback: revealOnTraversal);

/// The Tab order of a scrolled list's rows (QA-M14-5). A list also builds a
/// few rows beyond each edge of its view, and reading order put those first.
/// From outside the list, Tab enters at the first row fully in view and
/// Shift+Tab at the last, so the list does not move. Inside the list, Tab
/// and Shift+Tab go through every built row in order, and each one is
/// scrolled fully into view.
class ListTraversalPolicy extends ReadingOrderTraversalPolicy {
  ListTraversalPolicy() : super(requestFocusCallback: revealOnTraversal);

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final sorted = super.sortDescendants(descendants, currentNode).toList();
    final inside = sorted.any(
      (n) => n == currentNode || currentNode.ancestors.contains(n),
    );
    if (inside) return sorted;
    // Entering: only what is fully in view (no scroll needed, whichever
    // policy moves the focus: Shift+Tab around from the first tab goes
    // through the app's own), else what is partly in view, else all.
    for (final whole in [true, false]) {
      final inView = [
        for (final n in sorted)
          if (_inView(n, whole: whole)) n,
      ];
      if (inView.isNotEmpty) return inView;
    }
    return sorted;
  }

  /// Inside its list's view: [whole] or at least partly.
  static bool _inView(FocusNode node, {required bool whole}) {
    final object = node.context?.findRenderObject();
    if (object == null || !object.attached) return false;
    final Object? viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport is! RenderBox || !viewport.hasSize) return true;
    final area = viewport.localToGlobal(Offset.zero) & viewport.size;
    final rect = node.rect;
    return whole
        ? rect.top >= area.top - 0.5 && rect.bottom <= area.bottom + 0.5
        : rect.bottom > area.top && rect.top < area.bottom;
  }
}
