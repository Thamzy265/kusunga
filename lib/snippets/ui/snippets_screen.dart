import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../history/clip_item.dart';
import '../../history/ui/text_display.dart';
import '../../theme/tokens.dart';
import '../snippet.dart';
import '../snippet_service.dart';
import 'snippet_editor.dart';
import 'snippet_icons.dart';

/// The Snippets tab of the main window: the user's snippets in their order,
/// with Copy, Edit, Move up, Move down and Delete (with Undo). Spec:
/// `docs/ui/saved-snippets.md`.
class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key, required this.service, this.now});

  final SnippetService service;

  /// Unix milliseconds; replaced in tests.
  final int Function()? now;

  @override
  State<SnippetsScreen> createState() => SnippetsScreenState();
}

/// Public so the main window's "New snippet" button can open the editor here
/// (the toast and the selected row belong to this screen).
class SnippetsScreenState extends State<SnippetsScreen> {
  static const _footerEvery = Duration(seconds: 2);

  final _nodes = <int, FocusNode>{};
  final _screenFocus = FocusNode(
    debugLabel: 'snippets screen',
    skipTraversal: true,
  );
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _scroll = ScrollController();
  SnippetRecord? _pendingUndo;
  Timer? _clock;
  Timer? _footerTimer;
  var _footerHold = false;
  var _footerDirty = false;
  late String _footer;
  String _moveAnnouncement = '';

  /// The last move, for the 150 ms slide: the row, where it came from (+1
  /// below, -1 above) and a counter so each move animates once.
  ({int id, int from, int tick})? _lastMove;
  var _moveTick = 0;

  SnippetService get _service => widget.service;
  int get _nowMs => widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// New snippet is allowed (not memory-only, not at 1,000).
  bool get canCreate => _service.canCreate;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
    _footer = _footerText();
    _holdFooter();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    _clock?.cancel();
    _footerTimer?.cancel();
    _scroll.dispose();
    _screenFocus.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  String _footerText() {
    final n = _service.items.length;
    return n == 1 ? '1 snippet' : '$n snippets';
  }

  void _onChange() {
    // The count is a polite status: at most one change every 2 s.
    if (_footerHold) {
      _footerDirty = true;
    } else {
      _footer = _footerText();
      _holdFooter();
    }
    if (mounted) setState(() {});
  }

  void _holdFooter() {
    _footerHold = true;
    _footerTimer?.cancel();
    _footerTimer = Timer(_footerEvery, () {
      _footerHold = false;
      if (_footerDirty) {
        _footerDirty = false;
        if (mounted) {
          setState(() => _footer = _footerText());
          _holdFooter();
        }
      }
    });
  }

  FocusNode _nodeFor(int id) => _nodes.putIfAbsent(id, FocusNode.new);

  void _prune(List<SnippetItem> items) {
    final ids = items.map((i) => i.id).toSet();
    final gone = _nodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in gone) {
      final node = _nodes.remove(id)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
    }
  }

  void _toast(String message, {SnackBarAction? action, Duration? duration}) {
    final m = _messenger.currentState;
    if (m == null) return;
    // An Undo toast keeps its 5 seconds: a later message waits in the queue
    // behind it instead of replacing it (TB-4).
    if (_pendingUndo == null) m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: duration ?? const Duration(seconds: 2),
        persist: false,
        behavior: SnackBarBehavior.floating,
        width: 320,
      ),
    );
  }

  void _focusRow(int id, {bool scrollToEnd = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _nodes[id];
      if (node != null && (node.context?.mounted ?? false)) {
        node.requestFocus();
        return;
      }
      // Rows are built lazily: scroll the row into being, then focus it.
      if (_scroll.hasClients) {
        final index = _service.items.indexWhere((s) => s.id == id);
        _scroll.jumpTo(
          index <= 0 && !scrollToEnd ? 0 : _scroll.position.maxScrollExtent,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nodes[id]?.requestFocus();
      });
      setState(() {});
    });
  }

  Future<void> openNew() async {
    if (!_service.canEdit) return;
    if (_service.atCap) {
      _toast(snippetCapMessage, duration: const Duration(seconds: 5));
      return;
    }
    final id = await showSnippetEditor(
      context,
      service: _service,
      start: const SnippetEditorStart.create(),
    );
    if (id == null || !mounted) return;
    _toast('Snippet saved');
    _focusRow(id, scrollToEnd: true);
  }

  Future<void> _edit(SnippetItem item) async {
    if (!_service.canEdit) return;
    final id = await showSnippetEditor(
      context,
      service: _service,
      start: SnippetEditorStart.edit(item),
    );
    if (id == null || !mounted) return;
    _toast('Snippet saved');
    _focusRow(id);
  }

  Future<void> _copy(int id) async {
    final ok = await _service.copy(id);
    if (!mounted) return;
    _toast(ok ? 'Copied' : "Couldn't copy. Try again.");
  }

  void _move(SnippetItem item, int by) {
    if (!_service.canEdit) return;
    final items = _service.items;
    final from = items.indexWhere((s) => s.id == item.id);
    final to = from + by;
    if (from < 0 || to < 0 || to >= items.length) return;
    if (!_service.move(item.id, to)) {
      _toast("Couldn't move the snippet. Try again.");
      return;
    }
    final message =
        '${OneLine.of(item.name)}, moved to position ${to + 1} of '
        '${items.length}';
    setState(() {
      _moveAnnouncement = message;
      _lastMove = (id: item.id, from: by > 0 ? -1 : 1, tick: ++_moveTick);
    });
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        ),
      );
    }
    // The focus stays on the moved row.
    _focusRow(item.id);
  }

  void _moveFocus(int id, int by) {
    final items = _service.items;
    final i = items.indexWhere((s) => s.id == id);
    final target = i + by;
    if (i < 0 || target < 0 || target >= items.length) return;
    _focusRow(items[target].id);
  }

  void _delete(SnippetItem item) {
    if (!_service.canEdit) return;
    final items = _service.items;
    final index = items.indexWhere((s) => s.id == item.id);
    if (index < 0) return;
    // Focus goes to the next row, or the previous one at the end.
    final neighbour = index + 1 < items.length
        ? items[index + 1].id
        : (index > 0 ? items[index - 1].id : null);
    final result = _service.delete(item.id);
    if (result.failed) {
      _toast("Couldn't delete the snippet. Try again.");
      return;
    }
    final record = result.record;
    if (record == null) return;
    _pendingUndo = record;
    final m = _messenger.currentState;
    m?.hideCurrentSnackBar();
    final controller = m?.showSnackBar(
      SnackBar(
        content: const Text('Snippet deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: _undo),
        duration: const Duration(seconds: 5),
        persist: false,
        behavior: SnackBarBehavior.floating,
        width: 320,
      ),
    );
    controller?.closed.then((_) {
      // Undo keeps the snippet in memory for 5 s only.
      if (identical(_pendingUndo, record)) _pendingUndo = null;
    });
    if (neighbour != null) {
      _focusRow(neighbour);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _screenFocus.requestFocus();
      });
    }
  }

  void _undo() {
    final record = _pendingUndo;
    if (record == null) return;
    _pendingUndo = null;
    _messenger.currentState?.hideCurrentSnackBar();
    if (!_service.undo(record)) {
      _toast(
        _service.atCap
            ? snippetCapMessage
            : "Couldn't save the snippet. "
                  'Try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final items = _service.items;
    _prune(items);
    return ScaffoldMessenger(
      key: _messenger,
      child: Focus(
        focusNode: _screenFocus,
        child: Scaffold(
          backgroundColor: t.surface,
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(KusungaTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final b in _service.banners)
                                _Banner(banner: b, onRetry: _service.reload),
                            ],
                          ),
                        ),
                        if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(
                              onNew: canCreate ? openNew : null,
                            ),
                          )
                        else
                          _list(items),
                      ],
                    ),
                  ),
                  Semantics(
                    key: const ValueKey('snippet-move-announcement'),
                    liveRegion: defaultTargetPlatform != TargetPlatform.macOS,
                    label: _moveAnnouncement,
                    child: const SizedBox.shrink(),
                  ),
                  SizedBox(height: KusungaTokens.space2),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _footer,
                      style: KusungaTokens.caption.copyWith(color: t.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<SnippetItem> items) {
    final now = _nowMs;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final move = _lastMove;
    return SliverSemantics(
      label: 'Snippets, ${items.length} items',
      explicitChildNodes: true,
      sliver: SliverPadding(
        padding: EdgeInsets.only(bottom: KusungaTokens.space6 * 2),
        sliver: SliverList.separated(
          itemCount: items.length,
          // Rows keep their element (and focus) when they move.
          findItemIndexCallback: (key) {
            if (key is! ValueKey<int>) return null;
            final i = items.indexWhere((s) => s.id == key.value);
            return i < 0 ? null : i;
          },
          separatorBuilder: (_, _) => SizedBox(height: KusungaTokens.space1),
          itemBuilder: (context, i) {
            final item = items[i];
            final slide = !reduceMotion && move != null && move.id == item.id
                ? move
                : null;
            return SnippetRow(
              key: ValueKey(item.id),
              item: item,
              isFirst: i == 0,
              isLast: i == items.length - 1,
              editable: _service.canEdit,
              focusNode: _nodeFor(item.id),
              nowMs: now,
              slideFrom: slide?.from ?? 0,
              slideTick: slide?.tick ?? 0,
              onCopy: () => _copy(item.id),
              onEdit: () => _edit(item),
              onMoveUp: () => _move(item, -1),
              onMoveDown: () => _move(item, 1),
              onDelete: () => _delete(item),
              onFocusMove: (by) => _moveFocus(item.id, by),
            );
          },
        ),
      ),
    );
  }
}

/// The one-line form of a name or a content preview, for display and screen
/// readers: control and invisible characters shown, white space as one space.
abstract final class OneLine {
  static final _white = RegExp(r'\s+');
  static String of(String text) =>
      visibleText(text).replaceAll(_white, ' ').trim();
}

/// One snippet: type icon, name, one line of content, and the row actions
/// (shown on hover or focus; in a "More" menu under 600 px).
class SnippetRow extends StatefulWidget {
  const SnippetRow({
    super.key,
    required this.item,
    required this.isFirst,
    required this.isLast,
    required this.editable,
    required this.focusNode,
    required this.nowMs,
    required this.onCopy,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onFocusMove,
    this.slideFrom = 0,
    this.slideTick = 0,
  });

  final SnippetItem item;
  final bool isFirst;
  final bool isLast;

  /// False in memory-only mode: Edit, Move and Delete are off, Copy works.
  final bool editable;
  final FocusNode focusNode;
  final int nowMs;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final void Function(int by) onFocusMove;

  /// After a move: +1 slides in from below, -1 from above (150 ms).
  final int slideFrom;
  final int slideTick;

  /// "My mobile, Phone, 07700 900123".
  static String semanticName(SnippetItem item) {
    final text = OneLine.of(item.preview);
    final cut = text.length > 500 || item.isTruncated ? '…' : '';
    return '${OneLine.of(item.name)}, ${item.type.label}, '
        '${cutUnits(text, 500)}$cut';
  }

  @override
  State<SnippetRow> createState() => _SnippetRowState();
}

class _SnippetRowState extends State<SnippetRow> {
  var _hovered = false;
  var _within = false;
  final _menu = GlobalKey<PopupMenuButtonState<_RowAction>>();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(SnippetRow old) {
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
    final hw = HardwareKeyboard.instance;
    final alt = hw.isAltPressed && !hw.isMetaPressed && !hw.isControlPressed;
    if (key == LogicalKeyboardKey.arrowUp) {
      alt
          ? _ifEditable(widget.onMoveUp, !widget.isFirst)
          : widget.onFocusMove(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      alt
          ? _ifEditable(widget.onMoveDown, !widget.isLast)
          : widget.onFocusMove(1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onCopy();
    } else if ((key == LogicalKeyboardKey.keyE &&
            !hw.isMetaPressed &&
            !hw.isControlPressed &&
            !hw.isAltPressed) ||
        key == LogicalKeyboardKey.f2) {
      _ifEditable(widget.onEdit, true);
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _ifEditable(widget.onDelete, true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _ifEditable(VoidCallback action, bool allowed) {
    if (widget.editable && allowed) action();
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final item = widget.item;
    final name = OneLine.of(item.name);
    final active = _hovered || _within || widget.focusNode.hasFocus;
    final editable = widget.editable;

    Widget hide(Widget button) => Opacity(
      opacity: active ? 1 : 0,
      alwaysIncludeSemantics: true,
      child: button,
    );
    final actions = <Widget>[
      hide(
        _ActionButton(
          identifier: 'snippet-copy-${item.id}',
          text: 'Copy',
          label: 'Copy $name',
          onPressed: widget.onCopy,
        ),
      ),
      hide(
        _ActionButton(
          identifier: 'snippet-edit-${item.id}',
          text: 'Edit',
          label: 'Edit $name',
          onPressed: editable ? widget.onEdit : null,
        ),
      ),
      if (!widget.isFirst)
        hide(
          _ActionButton(
            identifier: 'snippet-up-${item.id}',
            text: 'Move up',
            label: 'Move $name up',
            onPressed: editable ? widget.onMoveUp : null,
          ),
        ),
      if (!widget.isLast)
        hide(
          _ActionButton(
            identifier: 'snippet-down-${item.id}',
            text: 'Move down',
            label: 'Move $name down',
            onPressed: editable ? widget.onMoveDown : null,
          ),
        ),
      hide(
        _ActionButton(
          identifier: 'snippet-delete-${item.id}',
          text: 'Delete',
          label: 'Delete $name',
          onPressed: editable ? widget.onDelete : null,
          danger: true,
        ),
      ),
    ];

    Widget more() => Semantics(
      identifier: 'snippet-more-${item.id}',
      button: true,
      label: 'More actions for $name',
      onTap: () => _menu.currentState?.showButtonMenu(),
      excludeSemantics: true,
      child: PopupMenuButton<_RowAction>(
        key: _menu,
        tooltip: 'More',
        icon: Icon(Icons.more_horiz, color: t.text),
        onSelected: (a) => switch (a) {
          _RowAction.copy => widget.onCopy(),
          _RowAction.edit => widget.onEdit(),
          _RowAction.up => widget.onMoveUp(),
          _RowAction.down => widget.onMoveDown(),
          _RowAction.delete => widget.onDelete(),
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: _RowAction.copy, child: Text('Copy')),
          PopupMenuItem(
            value: _RowAction.edit,
            enabled: editable,
            child: const Text('Edit'),
          ),
          if (!widget.isFirst)
            PopupMenuItem(
              value: _RowAction.up,
              enabled: editable,
              child: const Text('Move up'),
            ),
          if (!widget.isLast)
            PopupMenuItem(
              value: _RowAction.down,
              enabled: editable,
              child: const Text('Move down'),
            ),
          PopupMenuItem(
            value: _RowAction.delete,
            enabled: editable,
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    final row = LayoutBuilder(
      builder: (context, box) {
        // Below a 600 px window (at 100% text; the spec's breakpoint is the
        // window width, not the row's) the actions go into the More menu.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final narrow = MediaQuery.sizeOf(context).width < 600 * scale;
        final texts = ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: KusungaTokens.body.copyWith(
                        color: t.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // The edited time, on wide windows only.
                  if (!narrow) ...[
                    SizedBox(width: KusungaTokens.space2),
                    Flexible(
                      child: Text(
                        'edited '
                        '${relativeTimeLong(widget.nowMs, item.updatedAt)}',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: KusungaTokens.caption.copyWith(
                          color: t.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                OneLine.of(item.preview),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: KusungaTokens.body.copyWith(color: t.text),
              ),
            ],
          ),
        );
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: KusungaTokens.space3,
            vertical: KusungaTokens.space2,
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  snippetIcon(item.type),
                  size: 20,
                  color: t.textMuted,
                ),
              ),
              SizedBox(width: KusungaTokens.space3),
              Expanded(child: texts),
              SizedBox(width: KusungaTokens.space2),
              if (narrow) more() else ...actions,
            ],
          ),
        );
      },
    );

    Widget body = Container(
      key: ValueKey('snippet-row-box-${item.id}'),
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

    if (widget.slideFrom != 0) {
      body = TweenAnimationBuilder<double>(
        key: ValueKey('slide-${item.id}-${widget.slideTick}'),
        tween: Tween(begin: widget.slideFrom.toDouble(), end: 0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        builder: (context, v, child) =>
            FractionalTranslation(translation: Offset(0, v), child: child),
        child: body,
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (mounted) setState(() => _within = f);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          identifier: 'snippet-row-${item.id}',
          label: SnippetRow.semanticName(item),
          onTap: widget.focusNode.requestFocus,
          child: Focus(
            focusNode: widget.focusNode,
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
}

enum _RowAction { copy, edit, up, down, delete }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.identifier,
    required this.text,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String identifier;
  final String text;
  final String label;
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
      onTap: onPressed,
      excludeSemantics: true,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: danger ? t.danger : t.text,
          minimumSize: const Size(44, 28),
          padding: EdgeInsets.symmetric(horizontal: KusungaTokens.space2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(text),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.banner, required this.onRetry});

  final SnippetBanner banner;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final text = switch (banner) {
      SnippetBanner.unavailable =>
        "Snippets can't be saved right now, because Kusunga can't reach your "
            'keychain. Your saved snippets still paste.',
      SnippetBanner.readError =>
        "Kusunga couldn't read your snippets. Try again.",
    };
    return Padding(
      padding: EdgeInsets.only(bottom: KusungaTokens.space2),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: KusungaTokens.space3,
          vertical: KusungaTokens.space2,
        ),
        decoration: BoxDecoration(
          color: t.bannerWarnBg,
          borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: KusungaTokens.space2,
          children: [
            Semantics(
              liveRegion: true,
              focusable: true,
              child: Focus(
                child: Text(
                  text,
                  style: KusungaTokens.body.copyWith(color: t.bannerWarnText),
                ),
              ),
            ),
            if (banner == SnippetBanner.readError)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: t.bannerWarnText),
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNew});

  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.bookmark_border, size: 40, color: t.textMuted),
            ),
            SizedBox(height: KusungaTokens.space3),
            Text(
              'No snippets yet',
              style: KusungaTokens.title.copyWith(color: t.text),
            ),
            SizedBox(height: KusungaTokens.space1),
            Text(
              'Save things you paste often, like your phone number or email.',
              textAlign: TextAlign.center,
              style: KusungaTokens.body.copyWith(color: t.textMuted),
            ),
            SizedBox(height: KusungaTokens.space3),
            Semantics(
              identifier: 'snippet-new-empty',
              child: FilledButton(
                onPressed: onNew,
                child: const Text('New snippet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
