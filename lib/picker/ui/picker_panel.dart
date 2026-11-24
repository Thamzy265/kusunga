import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../history/clip_item.dart';
import '../../history/history_service.dart';
import '../../history/ui/history_row.dart';
import '../../history/ui/text_display.dart';
import '../../snippets/snippet.dart';
import '../../snippets/snippet_service.dart';
import '../../snippets/ui/snippet_icons.dart';
import '../../snippets/ui/snippet_text.dart';
import '../../theme/tokens.dart';
import '../../ui/tab_strip.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const rowHeight = 40.0;
  static const _countEvery = Duration(milliseconds: 500);

  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _node = FocusNode(onKeyEvent: _onKey);
  AnimationController? _fade;
  HistoryService? _bound;
  SnippetService? _boundSnippets;

  /// The Snippets tab is showing. The picker always opens on History (PM
  /// decision D3): this state is new each time the picker opens.
  var _snippetsTab = false;
  String _tabAnnouncement = '';
  var _query = '';
  int? _selectedId;
  var _filtered = const <ClipItem>[];
  var _total = 0;

  late String _spokenCount = _countText();
  Timer? _countTimer;
  var _countHold = false;
  var _countDirty = false;
  String? _lastSpokenCount;

  PickerController get _controller => widget.controller;
  int get _nowMs => widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // autofocus alone is not enough: the window is shown and made key after
    // this frame, and the focus may sit on the hidden history screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeFocus());
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

  void _takeFocus() {
    if (mounted && !_node.hasPrimaryFocus) _node.requestFocus();
  }

  // The window became the front app (it is made key after it is shown).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _takeFocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onController);
    _bound?.removeListener(_onItems);
    _boundSnippets?.removeListener(_onItems);
    _countTimer?.cancel();
    _fade?.dispose();
    _node.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _bind() {
    final history = _controller.history;
    if (identical(history, _bound)) return;
    _bound?.removeListener(_onItems);
    _bound = history;
    history?.addListener(_onItems);
    _boundSnippets?.removeListener(_onItems);
    _boundSnippets = history?.snippets;
    _boundSnippets?.addListener(_onItems);
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
    final all = _snippetsTab
        ? _controller.snippetEntries
        : _bound?.items ?? const <ClipItem>[];
    _total = all.length;
    _filtered = (_snippetsTab ? _controller.snippetSearch : _controller.search)
        .filter(all, _query);
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
    if (_query.trim().isNotEmpty) return n == 1 ? '1 match' : '$n matches';
    if (_snippetsTab) return n == 1 ? '1 snippet' : '$n snippets';
    return n == 1 ? '1 item' : '$n items';
  }

  /// ⌃Tab / ⌃⇧Tab (Ctrl+Tab on Windows), or a click on a tab. The query is
  /// kept, the new tab is filtered, its first row selected, and the switch
  /// announced ("Snippets, 4 items").
  void _selectTab(bool snippets) {
    if (snippets != _snippetsTab) {
      setState(() {
        _snippetsTab = snippets;
        _selectedId = null;
        _recompute();
        final n = _filtered.length;
        _tabAnnouncement =
            '${snippets ? 'Snippets' : 'History'}, '
            '${n == 1 ? '1 item' : '$n items'}';
      });
      _speak(_tabAnnouncement);
      _updateCount();
      _scrollTo(0);
    }
    // A click outside the text field takes its focus on desktop: give it back.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeFocus());
  }

  // The visible count is always current; the spoken one (a polite live region)
  // changes at most once every 500 ms.
  void _updateCount() {
    if (_countHold) {
      _countDirty = true;
    } else {
      setState(() => _spokenCount = _countText());
      _speakCount();
      _holdCount();
    }
  }

  // Flutter's live regions are not always spoken by VoiceOver on macOS, so the
  // count and the selected row are also sent as explicit announcements.
  void _speak(String message, {bool assertive = false}) {
    // Explicit announcements are the Mac channel; Windows uses live regions.
    if (!mounted || message.isEmpty || !_controller.isMac) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
        assertiveness: assertive
            ? Assertiveness.assertive
            : Assertiveness.polite,
      ),
    );
  }

  // The count, once per change (not again for the same words).
  void _speakCount() {
    if (_bound == null || _spokenCount == _lastSpokenCount) return;
    _lastSpokenCount = _spokenCount;
    _speak(_spokenCount);
  }

  void _holdCount() {
    _countHold = true;
    _countTimer?.cancel();
    _countTimer = Timer(_countEvery, () {
      _countHold = false;
      // "12 items" when the picker opens: spoken once the first hold ends, so
      // it follows the panel and field names.
      if (_countDirty && mounted) {
        // A change during the hold: say the current count, once.
        _countDirty = false;
        setState(() => _spokenCount = _countText());
        _speakCount();
        _holdCount();
      } else if (_lastSpokenCount == null) {
        _speakCount();
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
    final changed = _filtered[i].id != _selectedId;
    setState(() => _selectedId = _filtered[i].id);
    _scrollTo(i);
    // The caret never moves (the keys are consumed), so VoiceOver and Narrator
    // have nothing to say on their own: say the row.
    if (changed) _speak(_rowName(i, _filtered[i]), assertive: true);
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
    final id = _filtered[index].id;
    unawaited(
      _snippetsTab ? _controller.pasteSnippet(id) : _controller.pasteItem(id),
    );
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

    if (key == LogicalKeyboardKey.tab) {
      // ⌃Tab and ⌃⇧Tab switch tabs (with two tabs, both go to the other one);
      // a plain Tab does nothing, so the focus stays in the search field.
      final hw = HardwareKeyboard.instance;
      if (hw.isControlPressed && !hw.isMetaPressed && !hw.isAltPressed) {
        _selectTab(!_snippetsTab);
      }
      return KeyEventResult.handled;
    }
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
      // Only the one modifier: AltGr is Ctrl+Alt on Windows and types { [ ] }
      // on many layouts, so Alt, Shift or the other main key mean "typing".
      final quick = _controller.isMac
          ? hw.isMetaPressed &&
                !hw.isControlPressed &&
                !hw.isAltPressed &&
                !hw.isShiftPressed
          : hw.isControlPressed &&
                !hw.isMetaPressed &&
                !hw.isAltPressed &&
                !hw.isShiftPressed;
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
    } else if (_total == 0 && _snippetsTab) {
      body = const _Message(
        title: 'No snippets yet',
        detail: "Save one from Kusunga's main window.",
      );
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
            Padding(
              padding: EdgeInsets.only(
                left: KusungaTokens.space3,
                right: KusungaTokens.space3,
                top: KusungaTokens.space2,
              ),
              // The tabs stay on one row (UI spec, "Breakpoints"): at 200%
              // text in the smallest panel they shrink rather than wrap.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: TabStrip(
                  labels: const ['History', 'Snippets'],
                  identifiers: const [
                    'picker-tab-history',
                    'picker-tab-snippets',
                  ],
                  selected: _snippetsTab ? 1 : 0,
                  onSelect: (i) => _selectTab(i == 1),
                ),
              ),
            ),
            _SearchField(
              controller: _text,
              node: _node,
              onChanged: _onQuery,
              snippets: _snippetsTab,
            ),
            Divider(height: 1, thickness: 1, color: t.border),
            Expanded(child: body),
            Semantics(
              key: const ValueKey('picker-selection-announcement'),
              // One channel per platform: on Windows (Narrator) the live
              // region, on a Mac (VoiceOver) the explicit announcement.
              liveRegion: !_controller.isMac,
              label: announcement,
              child: const SizedBox.shrink(),
            ),
            Semantics(
              key: const ValueKey('picker-tab-announcement'),
              liveRegion: !_controller.isMac,
              label: _tabAnnouncement,
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
    final snippet = _snippetsTab ? _controller.snippetById(item.id) : null;
    final base = snippet != null
        ? snippetPickerName(snippet)
        : HistoryRow.semanticName(item, _nowMs);
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
          snippet: _snippetsTab ? _controller.snippetById(item.id) : null,
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
    required this.snippets,
  });

  final TextEditingController controller;
  final FocusNode node;
  final ValueChanged<String> onChanged;
  final bool snippets;

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
        label: snippets ? 'Search snippets' : 'Search history',
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
            hintText: snippets ? 'Search snippets…' : 'Search history…',
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
    this.snippet,
    required this.number,
    required this.selected,
    required this.query,
    required this.nowMs,
    required this.semanticName,
    required this.onPaste,
  });

  final ClipItem item;

  /// Set on the Snippets tab: the row shows "Name — content" and its icon.
  final SnippetItem? snippet;
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
    final snippet = widget.snippet;
    // A snippet row shows exactly the text search matched (F8).
    // Under 400 px the shortcut goes before the name is cut (M1.5 UI spec).
    final display = snippet == null
        ? PickerSearch.display(item.preview)
        : snippetLine(
            snippet,
            withShortcut: MediaQuery.sizeOf(context).width >= 400,
          );

    return Semantics(
      identifier: snippet == null
          ? 'picker-row-${item.id}'
          : 'picker-snippet-row-${item.id}',
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
                  snippet != null
                      ? snippetIcon(snippet.type)
                      : item.kind == ClipKind.link
                      ? Icons.link
                      : Icons.notes,
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
                if (snippet == null) ...[
                  SizedBox(width: KusungaTokens.space2),
                  Text(
                    relativeTimeShort(widget.nowMs, item.lastCopiedAt),
                    style: KusungaTokens.caption.copyWith(
                      color: selected ? t.text : t.textMuted,
                    ),
                  ),
                ],
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
                hint(isMac ? '⌃Tab Switch' : 'Ctrl+Tab Switch'),
                hint('esc Close'),
              ],
            ),
          Semantics(
            liveRegion: !isMac,
            label: spokenCount,
            excludeSemantics: true,
            child: Text(count, style: style),
          ),
        ],
      ),
    );
  }
}
