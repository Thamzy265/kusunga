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
  if (object == null || !object.attached) return;
  // The ring is drawn outside the control (`KusungaTokens.themeData`, 2 px):
  // reveal that too, or a control scrolled up to the edge of its view has the
  // ring cut off there (WCAG 2.4.7, M1.9a B2).
  object.showOnScreen(
    rect: object is RenderBox
        ? (Offset.zero & object.size).inflate(focusRingReach)
        : null,
  );
}

/// How far a focus ring reaches outside the control it marks, in px.
const focusRingReach = 2.0;

/// Reading order, with [revealOnTraversal].
FocusTraversalPolicy revealingReadingOrder() =>
    ReadingOrderTraversalPolicy(requestFocusCallback: revealOnTraversal);

/// Whether widgets under [context] may take the focus now: false while a
/// dialog or a menu is on top of their route. Flutter grants an autofocus
/// whenever the widget's own route scope has no focused child (none after
/// Enter in a text field, which unfocuses itself), whichever route holds the
/// focus, and a plain request always. So a row, a card or a scroll-and-focus
/// step behind a modal pulled the focus out of it: Escape and Enter then did
/// nothing there, and Tab walked the page behind it (BUG-D1, BUG-D3,
/// BUG-D4). True where there is no route.
bool canTakeFocus(BuildContext context) =>
    ModalRoute.isCurrentOf(context) ?? true;

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
    // Entering: only controls whose whole row is in view (no scroll needed,
    // whichever policy moves the focus: Shift+Tab around from the first tab
    // goes through the app's own), else rows partly in view, else all. The
    // row decides, not the control: a row cut off at the top can have its
    // buttons fully in view (BUG-T1).
    final members = descendants.toSet();
    FocusNode rowOf(FocusNode node) {
      var row = node;
      for (final a in node.ancestors) {
        if (members.contains(a)) row = a;
      }
      return row;
    }

    for (final whole in [true, false]) {
      final inView = [
        for (final n in sorted)
          if (_inView(rowOf(n), whole: whole)) n,
      ];
      if (inView.isNotEmpty) return inView;
    }
    return sorted;
  }

  /// Laid out inside its list's view: [whole] or at least partly. A row
  /// kept alive off screen (a focused button keeps its row) is not.
  static bool _inView(FocusNode node, {required bool whole}) {
    final object = node.context?.findRenderObject();
    if (object == null || !object.attached) return false;
    if (object is RenderBox && !object.hasSize) return false;
    RenderObject? child = object;
    while (child != null &&
        child.parentData is! SliverMultiBoxAdaptorParentData) {
      child = child.parent;
    }
    final data = child?.parentData;
    if (data is SliverMultiBoxAdaptorParentData && data.keptAlive) {
      return false;
    }
    final Object? viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport is! RenderBox || !viewport.hasSize) return true;
    final area = viewport.localToGlobal(Offset.zero) & viewport.size;
    final rect = node.rect;
    if (!rect.isFinite) return false;
    return whole
        ? rect.top >= area.top - 0.5 && rect.bottom <= area.bottom + 0.5
        : rect.bottom > area.top && rect.top < area.bottom;
  }
}
