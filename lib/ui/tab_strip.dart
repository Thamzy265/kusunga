import 'dart:ui' show SemanticsRole;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// The History / Snippets tabs (UI spec `docs/ui/saved-snippets.md`, "Main
/// window tabs" and "Picker tabs"): a tablist, the selected tab bold and
/// underlined (never colour alone), a hover background and a 2 px focus ring.
///
/// With [focusNodes] the tabs take focus and Left/Right move between them
/// (the main window). Without, they never take focus (the picker, where the
/// focus stays in the search field) and only a click switches.
class TabStrip extends StatelessWidget {
  const TabStrip({
    super.key,
    required this.labels,
    required this.identifiers,
    required this.selected,
    required this.onSelect,
    this.focusNodes,
  });

  final List<String> labels;

  /// `Semantics` identifiers (test hooks), one per tab.
  final List<String> identifiers;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<FocusNode>? focusNodes;

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final step = key == LogicalKeyboardKey.arrowRight
        ? 1
        : key == LogicalKeyboardKey.arrowLeft
        ? -1
        : 0;
    if (step != 0) {
      final next = (index + step) % labels.length;
      onSelect(next);
      focusNodes?[next].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpadEnter) {
      onSelect(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticsRole.tabBar,
      container: true,
      explicitChildNodes: true,
      // The tabs wrap onto two rows at 200% text in the smallest window (UI
      // spec, "320 px"); the picker keeps them on one row itself.
      child: Wrap(
        children: [
          for (var i = 0; i < labels.length; i++)
            _Tab(
              label: labels[i],
              identifier: identifiers[i],
              selected: i == selected,
              focusNode: focusNodes?[i],
              onTap: () {
                onSelect(i);
                focusNodes?[i].requestFocus();
              },
              onKey: (event) => _onKey(i, event),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.identifier,
    required this.selected,
    required this.focusNode,
    required this.onTap,
    required this.onKey,
  });

  final String label;
  final String identifier;
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final KeyEventResult Function(KeyEvent event) onKey;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final selected = widget.selected;
    final box = Container(
      constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
      padding: EdgeInsets.symmetric(horizontal: KusungaTokens.space3),
      decoration: BoxDecoration(
        color: _hovered ? t.surfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        border: Border.all(
          color: _focused ? t.focus : Colors.transparent,
          width: 2,
        ),
      ),
      // Only as wide and tall as the label (at least 44 x 36), centred in
      // that box. A Container alignment would stretch the tab to the whole
      // row and push each tab onto its own line (QA-M14-1).
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: KusungaTokens.space1),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? t.focus : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: KusungaTokens.body.copyWith(
              color: t.text,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      identifier: widget.identifier,
      role: SemanticsRole.tab,
      selected: selected,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: widget.focusNode != null,
        skipTraversal: widget.focusNode == null,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) => widget.onKey(event),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: box,
          ),
        ),
      ),
    );
  }
}
