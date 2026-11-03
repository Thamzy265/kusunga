import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../clip_item.dart';
import 'text_display.dart';

/// One item in the history list: kind icon, up to 2 lines of text, time, and
/// Copy and Delete buttons that show on hover or focus.
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
  });

  final ClipItem item;
  final FocusNode focusNode;
  final int nowMs;

  /// Slide in (a new copy). Read once, when the row is first built.
  final bool animateIn;
  final bool autofocus;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  /// Moves focus: -1 previous, 1 next, and the two ends.
  final void Function(RowMove move) onMove;

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

class _HistoryRowState extends State<HistoryRow> {
  var _hovered = false;
  var _within = false;
  late final bool _animateIn = widget.animateIn;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(HistoryRow old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_rebuild);
      widget.focusNode.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onMove(RowMove.next);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.onMove(RowMove.previous);
    } else if (key == LogicalKeyboardKey.home) {
      widget.onMove(RowMove.first);
    } else if (key == LogicalKeyboardKey.end) {
      widget.onMove(RowMove.last);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onCopy();
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      widget.onDelete();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
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
        label: 'Copy',
        description: description,
        onPressed: widget.onCopy,
      ),
    );
    final deleteButton = hideUnlessActive(
      _RowButton(
        identifier: 'history-delete-${item.id}',
        label: 'Delete',
        description: description,
        onPressed: widget.onDelete,
        danger: true,
      ),
    );

    final row = LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 600;
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
                        children: [time, copyButton, deleteButton],
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
    required this.label,
    required this.description,
    required this.onPressed,
    this.danger = false,
  });

  final String identifier;
  final String label;
  final String description;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Semantics(
      identifier: identifier,
      button: true,
      label: label,
      hint: description,
      excludeSemantics: true,
      onTap: onPressed,
      child: TextButton(
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
