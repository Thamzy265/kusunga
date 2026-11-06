import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../clip_item.dart';
import 'text_display.dart';

/// One item in the history list: kind icon, up to 2 lines of text, time, and
/// Copy, Save as snippet (M1.4) and Delete buttons that show on hover or
/// focus.
class HistoryRow extends StatefulWidget {
  const HistoryRow({
    super.key,
    required this.item,
    required this.focusNode,
    required this.nowMs,
    required this.animateIn,
    required this.autofocus,
    required this.onCopy,
    required this.onDelete,
    required this.onMove,
    required this.onSaveAsSnippet,
    required this.canSaveAsSnippet,
    this.onDisposedWithFocus,
    this.keepAlive = false,
  });

  final ClipItem item;
  final FocusNode focusNode;
  final int nowMs;

  /// Slide in (a new copy). Read once, when the row is first built.
  final bool animateIn;
  final bool autofocus;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  /// "Save as snippet" (button, or S on the focused row).
  final VoidCallback onSaveAsSnippet;

  /// False in memory-only mode and at 1,000 snippets: the button is off. S
  /// still calls [onSaveAsSnippet], which explains the cap.
  final bool canSaveAsSnippet;

  /// Moves focus: -1 previous, 1 next, and the two ends.
  final void Function(RowMove move) onMove;

  /// The row goes away (scrolled out of the built range) while it has focus.
  final VoidCallback? onDisposedWithFocus;

  /// Kept built off screen. Only while a text-size change re-lays out the
  /// list, so the focused control in this row survives until the row is
  /// back in view; never otherwise (a hidden row must not keep the focus).
  final bool keepAlive;

  /// The accessible name: "Link: https://example.com…, copied 2 minutes ago".
  static String semanticName(ClipItem item, int nowMs) {
    final kind = item.kind == ClipKind.link ? 'Link' : 'Text';
    final text = visibleText(item.preview);
    final cut = text.length > 500;
    final shown = cutUnits(text, 500);
    final ellipsis = cut || item.isTruncated ? '…' : '';
    return '$kind: $shown$ellipsis, copied ${relativeTimeLong(nowMs, item.lastCopiedAt)}';
  }

  @override
  State<HistoryRow> createState() => _HistoryRowState();
}

enum RowMove { previous, next, first, last }

class _HistoryRowState extends State<HistoryRow>
    with AutomaticKeepAliveClientMixin<HistoryRow> {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  var _hovered = false;
  var _within = false;
  late final bool _animateIn = widget.animateIn;

  @override
  void initState() {
    super.initState();
    // A row rebuilt at another place (a copy arrived above it) can start
    // with the focus already on its node: no focus change will say so
    // (BUG-H7).
    _hadFocus = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(HistoryRow old) {
    super.didUpdateWidget(old);
    if (old.keepAlive != widget.keepAlive) updateKeepAlive();
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_rebuild);
      widget.focusNode.addListener(_rebuild);
      _hadFocus = widget.focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_rebuild);
    // Scrolled out of the built range (or replaced) while it had the focus:
    // the screen decides where the focus goes, so it never falls to whatever
    // row had it before (BUG-H3).
    if (_hadFocus) widget.onDisposedWithFocus?.call();
    _copyFocus.dispose();
    _saveFocus.dispose();
    _deleteFocus.dispose();
    super.dispose();
  }

  // The buttons' nodes live as long as the row: at a breakpoint (200% text,
  // for one) the buttons are rebuilt in another layout, and the screen can
  // then give the focus back to the same button (lead rule after BUG-T2).
  final _copyFocus = FocusNode(debugLabel: 'history row Copy');
  final _saveFocus = FocusNode(debugLabel: 'history row Save as snippet');
  final _deleteFocus = FocusNode(debugLabel: 'history row Delete');

  /// Whether the row had the focus at the last focus change. Read in
  /// [dispose]: by then the Focus below has already let go of the node.
  var _hadFocus = false;

  void _rebuild() {
    _hadFocus = widget.focusNode.hasFocus;
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // On a Mac, Cmd+Up and Cmd+Down are first and last (and fn+Left/Right
    // arrive as Home and End).
    final cmd = HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onMove(cmd ? RowMove.last : RowMove.next);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.onMove(cmd ? RowMove.first : RowMove.previous);
    } else if (key == LogicalKeyboardKey.home) {
      widget.onMove(RowMove.first);
    } else if (key == LogicalKeyboardKey.end) {
      widget.onMove(RowMove.last);
    } else if (!node.hasPrimaryFocus) {
      // On a row button (Copy, Save as snippet, Delete), Enter and Space
      // activate that button: the row's own keys are for the row (BUG-K1).
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onCopy();
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      widget.onDelete();
    } else if (key == LogicalKeyboardKey.keyS &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      widget.onSaveAsSnippet();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = KusungaTokens.of(context);
    final item = widget.item;
    final active = _hovered || _within || widget.focusNode.hasFocus;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final animate = _animateIn && !reduceMotion;
    final description = _description(item);

    final text = ExcludeSemantics(
      child: Tooltip(
        message: visibleText(item.preview),
        waitDuration: const Duration(milliseconds: 600),
        child: Text(
          visibleText(item.preview),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: KusungaTokens.body.copyWith(color: t.text),
        ),
      ),
    );
    final time = ExcludeSemantics(
      child: Text(
        relativeTimeShort(widget.nowMs, item.lastCopiedAt),
        style: KusungaTokens.caption.copyWith(color: t.textMuted),
      ),
    );

    Widget hideUnlessActive(Widget button) => Opacity(
      opacity: active ? 1 : 0,
      alwaysIncludeSemantics: true,
      child: button,
    );
    final copyButton = hideUnlessActive(
      _RowButton(
        identifier: 'history-copy-${item.id}',
        focusNode: _copyFocus,
        label: 'Copy',
        description: description,
        onPressed: widget.onCopy,
      ),
    );
    final saveButton = hideUnlessActive(
      _RowButton(
        identifier: 'history-save-snippet-${item.id}',
        focusNode: _saveFocus,
        label: 'Save as snippet',
        description: description,
        onPressed: widget.canSaveAsSnippet ? widget.onSaveAsSnippet : null,
      ),
    );
    final deleteButton = hideUnlessActive(
      _RowButton(
        identifier: 'history-delete-${item.id}',
        focusNode: _deleteFocus,
        label: 'Delete',
        description: description,
        onPressed: widget.onDelete,
        danger: true,
      ),
    );

    final row = LayoutBuilder(
      builder: (context, box) {
        // Narrow below a 600 px window (the spec's breakpoint is the window
        // width, not the row's; F9), at 100% text: at 200% text the time and
        // the three buttons need twice the room.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final narrow = MediaQuery.sizeOf(context).width < 600 * scale;
        final icon = ExcludeSemantics(
          child: Icon(
            item.kind == ClipKind.link ? Icons.link : Icons.notes,
            size: 20,
            color: t.textMuted,
          ),
        );
        final gap = SizedBox(width: KusungaTokens.space3);
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: KusungaTokens.space3,
            vertical: KusungaTokens.space2,
          ),
          child: narrow
              // Narrow: the text gets the full width; the time and the
              // buttons wrap onto lines below it, so nothing overflows at
              // 200% text.
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        gap,
                        Expanded(child: text),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 20 + KusungaTokens.space3),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: KusungaTokens.space2,
                        children: [time, copyButton, saveButton, deleteButton],
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    icon,
                    gap,
                    Expanded(child: text),
                    gap,
                    time,
                    SizedBox(width: KusungaTokens.space2),
                    copyButton,
                    saveButton,
                    deleteButton,
                  ],
                ),
        );
      },
    );

    Widget body = Container(
      key: ValueKey('row-${item.id}'),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: active ? t.surfaceHover : t.surface,
        border: Border.all(
          color: widget.focusNode.hasFocus ? t.focus : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(KusungaTokens.radius2),
      ),
      child: row,
    );

    body = TweenAnimationBuilder<double>(
      key: ValueKey('enter-${item.id}'),
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * -12),
          child: child,
        ),
      ),
      child: body,
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (mounted) setState(() => _within = f);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // The row's own node carries the label, focus and tap together
        // (screen readers need the tappable node to have a name).
        child: Semantics(
          label: HistoryRow.semanticName(item, widget.nowMs),
          onTap: widget.focusNode.requestFocus,
          child: Focus(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: widget.focusNode.requestFocus,
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  static String _description(ClipItem item) {
    final text = visibleText(item.preview).replaceAll('\n', ' ');
    return text.length > 100 ? '${text.substring(0, 100)}…' : text;
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.identifier,
    required this.focusNode,
    required this.label,
    required this.description,
    required this.onPressed,
    this.danger = false,
  });

  final String identifier;
  final FocusNode focusNode;
  final String label;
  final String description;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Semantics(
      identifier: identifier,
      button: true,
      enabled: onPressed != null,
      label: label,
      hint: description,
      excludeSemantics: true,
      onTap: onPressed,
      child: TextButton(
        focusNode: focusNode,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: danger ? t.danger : t.text,
          minimumSize: const Size(44, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label),
      ),
    );
  }
}
