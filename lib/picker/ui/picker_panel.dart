import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../history/clip_item.dart';
import '../../history/history_service.dart';
import '../../history/ui/history_row.dart';
import '../../history/ui/text_display.dart';
import '../../theme/tokens.dart';
import '../picker_controller.dart';
import '../picker_search.dart';

/// The picker (picker mode of the one window): search, a list of previews,
/// keyboard and mouse paste. Spec: `docs/ui/history-picker.md`.
///
/// Keys are handled on the search field's own focus node, so they work while
/// typing, and every other key (caret, Cmd+A, Cmd+Z, Backspace) still reaches
/// the text field. Nothing is bound screen-wide (M1.2 lesson 2).
class PickerPanel extends StatefulWidget {
  const PickerPanel({super.key, required this.controller, this.now});

  final PickerController controller;

  /// Unix milliseconds; replaced in tests.
  final int Function()? now;

  @override
  State<PickerPanel> createState() => _PickerPanelState();
}

class _PickerPanelState extends State<PickerPanel>
    with SingleTickerProviderStateMixin {
  static const rowHeight = 40.0;
  static const _countEvery = Duration(milliseconds: 500);

  final _search = PickerSearch();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _node = FocusNode(onKeyEvent: _onKey);
  AnimationController? _fade;
  HistoryService? _bound;
  var _query = '';
  int? _selectedId;
  var _filtered = const <ClipItem>[];
  var _total = 0;

  late String _spokenCount = _countText();
  Timer? _countTimer;
  Timer? _warmTimer;
  var _countHold = false;
  var _countDirty = false;

  PickerController get _controller => widget.controller;
  int get _nowMs => widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    _bind();
    _recompute();
    _spokenCount = _countText();
    _holdCount();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fade == null && !MediaQuery.of(context).disableAnimations) {
      // 100 ms fade; no animation at all with reduce motion.
      _fade = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
      )..forward();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _bound?.removeListener(_onItems);
    _countTimer?.cancel();
    _warmTimer?.cancel();
    _fade?.dispose();
    _node.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Builds the search index in small steps, so typing never waits for it.
  void _scheduleWarm() {
    if (_warmTimer != null || _bound == null) return;
    _warmTimer = Timer(const Duration(milliseconds: 1), () {
      _warmTimer = null;
      if (!mounted) return;
      if (_search.warm(_bound?.items ?? const [])) _scheduleWarm();
    });
  }

  void _bind() {
    final history = _controller.history;
    if (identical(history, _bound)) return;
    _bound?.removeListener(_onItems);
    _bound = history;
    history?.addListener(_onItems);
  }

  void _onController() {
    _bind();
    _onItems();
  }

  void _onItems() {
    if (!mounted) return;
    setState(_recompute);
    _updateCount();
  }

  void _recompute() {
    final all = _bound?.items ?? const <ClipItem>[];
    _total = all.length;
    _filtered = _search.filter(all, _query);
    _scheduleWarm();
    final id = _selectedId;
    if (_filtered.isEmpty) {
      _selectedId = null;
    } else if (id == null || !_filtered.any((i) => i.id == id)) {
      _selectedId = _filtered.first.id;
    }
  }

  int get _selectedIndex {
    final id = _selectedId;
    if (id == null) return -1;
    return _filtered.indexWhere((i) => i.id == id);
  }

  String _countText() {
    if (_bound == null) return '';
    final n = _filtered.length;
    if (_query.trim().isEmpty) return n == 1 ? '1 item' : '$n items';
    return n == 1 ? '1 match' : '$n matches';
  }

  // The visible count is always current; the spoken one (a polite live region)
  // changes at most once every 500 ms.
  void _updateCount() {
    if (_countHold) {
      _countDirty = true;
    } else {
      setState(() => _spokenCount = _countText());
      _holdCount();
    }
  }

  void _holdCount() {
    _countHold = true;
    _countTimer?.cancel();
    _countTimer = Timer(_countEvery, () {
      _countHold = false;
      if (_countDirty && mounted) {
        _countDirty = false;
        setState(() => _spokenCount = _countText());
        _holdCount();
      }
    });
  }

  void _onQuery(String value) {
    setState(() {
      _query = value;
      _selectedId = null; // back to the first row
      _recompute();
    });
    _updateCount();
    _scrollTo(0);
  }

  void _select(int index) {
    if (_filtered.isEmpty) return;
    final i = index.clamp(0, _filtered.length - 1);
    setState(() => _selectedId = _filtered[i].id);
    _scrollTo(i);
  }

  void _scrollTo(int index) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final top = index * rowHeight;
    final bottom = top + rowHeight;
    if (top < pos.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo(min(bottom - pos.viewportDimension, pos.maxScrollExtent));
    }
  }

  int get _pageSize {
    if (!_scroll.hasClients) return 5;
    return max(1, (_scroll.position.viewportDimension / rowHeight).floor() - 1);
  }

  void _pasteAt(int index) {
    if (index < 0 || index >= _filtered.length) return;
    unawaited(_controller.pasteItem(_filtered[index].id));
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    // While an input method is composing text, its keys are not ours.
    final composing = _text.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.tab) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.escape) {
      if (!repeat) unawaited(_controller.closePicker());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _select(_selectedIndex + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _select(_selectedIndex - 1);
    } else if (key == LogicalKeyboardKey.home) {
      _select(0);
    } else if (key == LogicalKeyboardKey.end) {
      _select(_filtered.length - 1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _select(_selectedIndex + _pageSize);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _select(_selectedIndex - _pageSize);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!repeat) _pasteAt(_selectedIndex);
    } else {
      final n = _digits.indexOf(key);
      final hw = HardwareKeyboard.instance;
      final quick = _controller.isMac ? hw.isMetaPressed : hw.isControlPressed;
      if (n < 0 || !quick) return KeyEventResult.ignored;
      if (!repeat) _pasteAt(n);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final loading = _bound == null;

    Widget body;
    if (loading) {
      body = const _Message(title: 'Opening your history…', live: true);
    } else if (_total == 0) {
      body = const _Message(
        title: 'Nothing here yet',
        detail: 'Copy some text in any app and it will appear here.',
      );
    } else if (_filtered.isEmpty) {
      final shown = _query.length > 40 ? '${cutUnits(_query, 40)}…' : _query;
      body = _Message(
        title: 'No matches for "$shown"',
        detail: 'Try fewer letters.',
      );
    } else {
      body = _list(t);
    }

    final selected = _selectedIndex;
    final announcement = selected < 0
        ? ''
        : _rowName(selected, _filtered[selected]);

    Widget panel = LayoutBuilder(
      builder: (context, box) {
        // Too little room for the hints (200% text in the smallest panel):
        // keep the search, the list and the count.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final compact = box.maxHeight < 200 * scale;
        return _frame(t, body, announcement, loading, compact);
      },
    );
    final fade = _fade;
    if (fade != null) {
      panel = FadeTransition(
        key: const ValueKey('picker-fade'),
        opacity: fade,
        child: panel,
      );
    }
    return panel;
  }

  Widget _frame(
    KusungaTokens t,
    Widget body,
    String announcement,
    bool loading,
    bool compact,
  ) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Kusunga picker',
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KusungaTokens.radius2 + 4),
          side: BorderSide(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchField(controller: _text, node: _node, onChanged: _onQuery),
            Divider(height: 1, thickness: 1, color: t.border),
            Expanded(child: body),
            Semantics(
              key: const ValueKey('picker-selection-announcement'),
              liveRegion: true,
              label: announcement,
              child: const SizedBox.shrink(),
            ),
            Divider(height: 1, thickness: 1, color: t.border),
            _Footer(
              compact: compact,
              isMac: _controller.isMac,
              count: loading ? '' : _countText(),
              spokenCount: loading ? '' : _spokenCount,
            ),
          ],
        ),
      ),
    );
  }

  String _rowName(int index, ClipItem item) {
    final base = HistoryRow.semanticName(item, _nowMs);
    return index < 9 ? '${index + 1}, $base' : base;
  }

  Widget _list(KusungaTokens t) {
    final now = _nowMs;
    final selected = _selectedIndex;
    return ListView.builder(
      controller: _scroll,
      itemExtent: rowHeight,
      itemCount: _filtered.length,
      itemBuilder: (context, i) {
        final item = _filtered[i];
        return _PickerRow(
          key: ValueKey(item.id),
          item: item,
          number: i < 9 ? i + 1 : null,
          selected: i == selected,
          query: _query,
          nowMs: now,
          semanticName: _rowName(i, item),
          onPaste: () => _pasteAt(i),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.node,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode node;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    // 1 px border, darker on hover, and a 2 px focus ring (UI spec).
    final border = WidgetStateInputBorder.resolveWith((states) {
      final focused = states.contains(WidgetState.focused);
      final hovered = states.contains(WidgetState.hovered);
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        borderSide: BorderSide(
          color: focused ? t.focus : (hovered ? t.borderHover : t.border),
          width: focused ? 2 : 1,
        ),
      );
    });
    return Padding(
      padding: EdgeInsets.all(KusungaTokens.space3),
      child: Semantics(
        identifier: 'picker-search',
        label: 'Search history',
        textField: true,
        excludeSemantics: true,
        child: TextField(
          controller: controller,
          focusNode: node,
          autofocus: true,
          maxLines: 1,
          onChanged: onChanged,
          style: KusungaTokens.body.copyWith(color: t.text),
          cursorColor: t.focus,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search history…',
            hintStyle: KusungaTokens.body.copyWith(color: t.textMuted),
            prefixIcon: ExcludeSemantics(
              child: Icon(Icons.search, color: t.textMuted),
            ),
            border: border,
            hoverColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatefulWidget {
  const _PickerRow({
    super.key,
    required this.item,
    required this.number,
    required this.selected,
    required this.query,
    required this.nowMs,
    required this.semanticName,
    required this.onPaste,
  });

  final ClipItem item;
  final int? number;
  final bool selected;
  final String query;
  final int nowMs;
  final String semanticName;
  final VoidCallback onPaste;

  @override
  State<_PickerRow> createState() => _PickerRowState();
}

class _PickerRowState extends State<_PickerRow> {
  var _hovered = false;

  List<InlineSpan> _spans(String display, TextStyle base) {
    final ranges = PickerSearch.ranges(display, widget.query);
    if (ranges.isEmpty) return [TextSpan(text: display)];
    final marked = base.copyWith(
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
    );
    final out = <InlineSpan>[];
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) out.add(TextSpan(text: display.substring(at, start)));
      out.add(TextSpan(text: display.substring(start, end), style: marked));
      at = end;
    }
    if (at < display.length) out.add(TextSpan(text: display.substring(at)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final item = widget.item;
    final selected = widget.selected;
    final background = selected
        ? t.selection
        : (_hovered ? t.surfaceHover : Colors.transparent);
    final base = KusungaTokens.body.copyWith(
      color: t.text,
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    );
    final display = PickerSearch.display(item.preview);

    return Semantics(
      identifier: 'picker-row-${item.id}',
      label: widget.semanticName,
      button: true,
      selected: selected,
      onTap: widget.onPaste,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPaste,
          child: Container(
            key: const ValueKey('picker-row-box'),
            color: background,
            padding: EdgeInsets.symmetric(horizontal: KusungaTokens.space3),
            child: Row(
              children: [
                // The marker and the bold text show the selection; the colour
                // alone never does.
                SizedBox(
                  width: 16,
                  child: selected
                      ? Text(
                          '▶',
                          key: const ValueKey('picker-selected-marker'),
                          style: KusungaTokens.caption.copyWith(color: t.text),
                        )
                      : null,
                ),
                SizedBox(
                  width: 20,
                  child: widget.number == null
                      ? null
                      : Text(
                          '${widget.number}',
                          style: KusungaTokens.caption.copyWith(
                            color: selected ? t.text : t.textMuted,
                          ),
                        ),
                ),
                Icon(
                  item.kind == ClipKind.link ? Icons.link : Icons.notes,
                  size: 18,
                  color: selected ? t.text : t.textMuted,
                ),
                SizedBox(width: KusungaTokens.space2),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: _spans(display, base), style: base),
                    key: const ValueKey('picker-row-text'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: KusungaTokens.space2),
                Text(
                  relativeTimeShort(widget.nowMs, item.lastCopiedAt),
                  style: KusungaTokens.caption.copyWith(
                    color: selected ? t.text : t.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.detail, this.live = false});

  final String title;
  final String? detail;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(KusungaTokens.space4),
        child: Semantics(
          liveRegion: live,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: KusungaTokens.body.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail != null) ...[
                SizedBox(height: KusungaTokens.space1),
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: KusungaTokens.caption.copyWith(color: t.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.compact,
    required this.isMac,
    required this.count,
    required this.spokenCount,
  });

  final bool compact;
  final bool isMac;
  final String count;
  final String spokenCount;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final style = KusungaTokens.caption.copyWith(color: t.textMuted);
    Widget hint(String text) => Text(text, style: style);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: KusungaTokens.space3,
        vertical: KusungaTokens.space2,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: KusungaTokens.space3,
        runSpacing: KusungaTokens.space1,
        children: [
          if (!compact)
            Wrap(
              spacing: KusungaTokens.space3,
              runSpacing: KusungaTokens.space1,
              children: [
                hint('↵ Paste'),
                hint(isMac ? '⌘1–9 Quick paste' : 'Ctrl+1–9 Quick paste'),
                hint('esc Close'),
              ],
            ),
          Semantics(
            liveRegion: true,
            label: spokenCount,
            excludeSemantics: true,
            child: Text(count, style: style),
          ),
        ],
      ),
    );
  }
}
