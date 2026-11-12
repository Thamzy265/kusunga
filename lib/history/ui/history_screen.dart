import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../clipboard/clipboard_source.dart';
import '../../privacy/ui/privacy_screen.dart' show pauseEndText;
import '../../snippets/ui/snippet_editor.dart';
import '../../theme/tokens.dart';
import '../../ui/close_at_zero.dart';
import '../../ui/focus_order.dart';
import '../clip_item.dart';
import '../history_service.dart';
import '../pause_service.dart';
import 'history_row.dart';

/// The home view: what Kusunga has saved, with Copy, Delete (with Undo),
/// Clear history and the limit. Spec: `docs/ui/clipboard-history.md`.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.service,
    this.now,
    this.topSlot,
    this.dataProfileRejected = false,
  });

  final HistoryService service;

  /// See `HistoryHost.dataProfileRejected`.
  final bool dataProfileRejected;

  /// Extra content under the header and banners (the picker settings).
  final Widget? topSlot;

  /// Unix milliseconds; replaced in tests.
  final int Function()? now;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _footerEvery = Duration(seconds: 2);

  final _nodes = <int, FocusNode>{};

  /// A node that is always there, inside the Undo shortcut. After the last row
  /// is deleted the focus goes here, so Cmd/Ctrl+Z still works.
  final _screenFocus = FocusNode(
    debugLabel: 'history screen',
    skipTraversal: true,
  );

  /// Above the "More options" button, which keeps its own node to itself:
  /// the menu and the Clear history dialog give the focus back to the button
  /// through it (see [_focusMore]).
  final _moreWrap = FocusNode(
    debugLabel: 'More options',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final _seen = <int>{};
  final _newIds = <int>{};
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _scroll = ScrollController();
  ClipRecord? _pendingUndo;
  Timer? _clock;
  Timer? _footerTimer;
  var _footerHold = false;
  var _footerDirty = false;
  late String _footer;

  HistoryService get _service => widget.service;
  int get _nowMs => widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _seen.addAll(_service.items.map((i) => i.id));
    _shownIds = [for (final item in _service.items) item.id];
    _service.addListener(_onChange);
    _service.snippets.addListener(_onSnippets);
    _footer = _footerText();
    _holdFooter();
    // Relative times ("2 min") move on without any other event.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  TextScaler? _textScaler;

  /// The row kept built while a text-size change re-lays out the list (see
  /// [_keepFocusThroughTextSize]); null otherwise.
  int? _holdId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaler = MediaQuery.textScalerOf(context);
    if (_textScaler != null && scaler != _textScaler) {
      _keepFocusThroughTextSize();
    }
    _textScaler = scaler;
  }

  /// A text-size change makes every row taller or shorter, so the focused
  /// row can move out of view, or out of the built range (and its focused
  /// control with it). It is not a user scroll (H5, PM decision
  /// 2026-11-05): the focused row is scrolled back fully into view and the
  /// same control keeps the focus (lead rule after BUG-T2). Called before
  /// the new layout, so the row is held built through it. Focus waiting on
  /// the screen after a user scroll is left as it is.
  void _keepFocusThroughTextSize() {
    final control = FocusManager.instance.primaryFocus;
    int? rowId;
    for (final MapEntry(key: id, value: node) in _nodes.entries) {
      if (node.hasFocus) rowId = id;
    }
    if (control == null || rowId == null) return;
    final id = rowId;
    _holdId = id;
    final ticket = ++_focusTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ticket == _focusTicket) {
        _showAndFocus(id, control: control);
      }
    });
  }

  /// Ends a hold once a focus request has brought its row back (or gave up).
  void _releaseHold() {
    if (_holdId != null && mounted) setState(() => _holdId = null);
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    _service.snippets.removeListener(_onSnippets);
    _clock?.cancel();
    _footerTimer?.cancel();
    _scroll.dispose();
    _screenFocus.dispose();
    _moreWrap.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  String _footerText() {
    final limit = _service.limit;
    final n = _service.items.length;
    // Copies waiting to be saved can briefly outnumber the limit.
    return '${n > limit ? limit : n} of $limit items';
  }

  void _onChange() {
    for (final item in _service.items) {
      if (_seen.add(item.id)) _newIds.add(item.id);
    }
    // Footer updates are announced politely, so at most once every 2 s.
    if (_footerHold) {
      _footerDirty = true;
    } else {
      _footer = _footerText();
      _holdFooter();
    }
    final items = _service.items;
    final next = _focusPending ? null : _survivorOfFocusedRow(items);
    _shownIds = [for (final item in items) item.id];
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next != null) {
          if (_lostFocusId != null && !_followFocus) {
            // Scrolled away with the mouse: the next arrow key goes on from
            // the item that took the gone one's place.
            _lostFocusId = next;
          } else {
            _showAndFocus(next);
          }
        } else if (_followFocus) {
          _keepFocusedRowInView();
        }
      });
    }
  }

  /// The ids of the rows as last shown, in order.
  List<int> _shownIds = const [];

  /// If the focused row's item is gone (a full history trims its oldest copy
  /// on every new one), the item that takes its place: the nearest older one
  /// still there, else the nearest newer one. The focus never ends on nothing
  /// (BUG-H6).
  int? _survivorOfFocusedRow(List<ClipItem> items) {
    if (items.isEmpty) return null;
    int? focused = _lostFocusId;
    for (final MapEntry(key: id, value: node) in _nodes.entries) {
      if (node.hasFocus) focused = id;
    }
    if (focused == null) return null;
    final ids = {for (final item in items) item.id};
    if (ids.contains(focused)) return null;
    final at = _shownIds.indexOf(focused);
    if (at < 0) return items.last.id;
    for (var i = at + 1; i < _shownIds.length; i++) {
      if (ids.contains(_shownIds[i])) return _shownIds[i];
    }
    for (var i = at - 1; i >= 0; i--) {
      if (ids.contains(_shownIds[i])) return _shownIds[i];
    }
    return items.last.id;
  }

  /// True while the arrow keys move the focus: the focused row is then kept
  /// in view when the list changes. A scroll or a click with the mouse or
  /// the trackpad turns it off, so a new copy never pulls the list back; the
  /// next arrow key turns it on again (BUG-H5, PM decision 2026-11-05).
  var _followFocus = true;

  void _stopFollowing([Object? _]) => _followFocus = false;

  /// The item whose row had the focus when the row went away (scrolled out
  /// with the mouse or the trackpad); null while a row has the focus.
  int? _lostFocusId;

  /// The focused row [id] was disposed. After this frame: if the row is
  /// built again (it only moved), it keeps the focus; else the focus waits on
  /// the screen (never on another row, which a Delete would then hit), and
  /// either the list follows it back into view (arrow keys in use) or the
  /// next arrow key goes on from it.
  void _rowLostFocus(int id) {
    if (_focusPending) return;
    final ticket = _focusTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A focus request since then (an arrow key, End finishing) decides.
      if (!mounted || _focusPending || ticket != _focusTicket) return;
      // A dialog or a menu on top keeps the focus; it gives it back to its
      // opener when it closes.
      if (!canTakeFocus(context)) return;
      final node = _nodes[id];
      if (node != null && (node.context?.mounted ?? false)) {
        if (!node.hasFocus) node.requestFocus();
        return;
      }
      if (!_service.items.any((e) => e.id == id)) return;
      _lostFocusId = id;
      _screenFocus.requestFocus();
      if (_followFocus) _showAndFocus(id);
    });
  }

  /// Arrow keys while the focus waits on the screen (its row was scrolled
  /// away): they go on from that row.
  KeyEventResult _onScreenKey(FocusNode node, KeyEvent event) {
    final id = _lostFocusId;
    if (id == null || !node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final cmd = HardwareKeyboard.instance.isMetaPressed;
    final move = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => cmd ? RowMove.last : RowMove.next,
      LogicalKeyboardKey.arrowUp => cmd ? RowMove.first : RowMove.previous,
      LogicalKeyboardKey.home => RowMove.first,
      LogicalKeyboardKey.end => RowMove.last,
      _ => null,
    };
    if (move == null) return KeyEventResult.ignored;
    _move(id, move);
    return KeyEventResult.handled;
  }

  // "Save as snippet" turns off at the cap.
  void _onSnippets() {
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

  FocusNode _nodeFor(int id) => _nodes.putIfAbsent(id, () {
    final node = FocusNode();
    node.addListener(() {
      if (node.hasFocus) _lostFocusId = null;
    });
    return node;
  });

  void _prune(List<ClipItem> items) {
    final ids = items.map((i) => i.id).toSet();
    final gone = _nodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in gone) {
      final node = _nodes.remove(id)!;
      // Dispose after this frame: the row is still being torn down.
      WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
    }
    _newIds.removeWhere((id) => !ids.contains(id));
    if (_holdId != null && !ids.contains(_holdId)) _holdId = null;
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

  Future<void> _copy(int id) async {
    final ok = await _service.copy(id);
    if (!mounted) return;
    _toast(ok ? 'Copied' : "Couldn't copy. Try again.");
  }

  /// "Save as snippet": the editor, filled in from the whole text. The item
  /// stays in history (PM decision D2).
  Future<void> _saveAsSnippet(int id) async {
    final snippets = _service.snippets;
    if (!snippets.canEdit) return;
    if (snippets.atCap) {
      _toast(snippetCapMessage, duration: const Duration(seconds: 5));
      return;
    }
    final text = _service.textOf(id);
    if (text == null) {
      // Never open the editor without the whole text (F10).
      snippets.noteOpenFailed();
      _toast(snippetOpenFailedMessage);
      return;
    }
    final saved = await showSnippetEditor(
      context,
      service: snippets,
      start: SnippetEditorStart.fromHistory(text),
    );
    if (saved == null || !mounted) return;
    _toast('Snippet saved');
    // The focus goes back to the row it came from.
    final ticket = ++_focusTicket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ticket == _focusTicket) _showAndFocus(id);
    });
  }

  void _delete(int id) {
    final items = _service.items;
    final index = items.indexWhere((i) => i.id == id);
    if (index < 0) return;
    // Focus goes to the next row, or the previous one at the end.
    final neighbour = index + 1 < items.length
        ? items[index + 1].id
        : (index > 0 ? items[index - 1].id : null);
    final hadFocus = _nodes[id]?.hasFocus ?? false;

    final record = _service.delete(id);
    if (record == null) return;
    _pendingUndo = record;
    final m = _messenger.currentState;
    // The new Undo shows at once: any toast queued behind the old Undo is
    // out of date (F4).
    m
      ?..clearSnackBars()
      ..removeCurrentSnackBar();
    final controller = m?.showSnackBar(
      SnackBar(
        content: const Text('Deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => _undo()),
        duration: const Duration(seconds: 5),
        persist: false,
        behavior: SnackBarBehavior.floating,
        width: 320,
      ),
    );
    controller?.closed.then((_) {
      if (identical(_pendingUndo, record)) _pendingUndo = null;
    });
    if (neighbour == null) {
      final ticket = ++_focusTicket;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ticket == _focusTicket) _screenFocus.requestFocus();
      });
    }
    if (hadFocus && neighbour != null) {
      final ticket = ++_focusTicket;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ticket == _focusTicket) _showAndFocus(neighbour);
      });
    }
  }

  void _undo() {
    final record = _pendingUndo;
    if (record == null) return;
    _pendingUndo = null;
    _messenger.currentState?.hideCurrentSnackBar();
    _service.undo(record);
  }

  void _move(int id, RowMove move) {
    _followFocus = true;
    final items = _service.items;
    final i = items.indexWhere((e) => e.id == id);
    if (i < 0 || items.isEmpty) return;
    final target = switch (move) {
      RowMove.previous => (i - 1).clamp(0, items.length - 1),
      RowMove.next => (i + 1).clamp(0, items.length - 1),
      RowMove.first => 0,
      RowMove.last => items.length - 1,
    };
    _showAndFocus(
      items[target].id,
      end: switch (move) {
        RowMove.first => _End.first,
        RowMove.last => _End.last,
        _ => null,
      },
    );
  }

  /// Bumped by every focus request: one still waiting for a frame gives up
  /// when a newer one came after it (End then Home in one frame).
  var _focusTicket = 0;

  /// True while a focus request is still scrolling towards its row.
  var _focusPending = false;

  /// Scrolls the row [id] fully into view and focuses it (WCAG 2.4.11): at
  /// once if the row is laid out, else once it is, after scrolling towards it
  /// frame by frame (rows differ in height, so its place is only estimated
  /// until it is built). [end]: the request is for the first or last row, so
  /// if that row goes meanwhile (a full history trims its oldest copy) the
  /// new first or last row is the target (BUG-H1).
  ///
  /// [control]: a control in that row to give the focus to instead of the
  /// row itself, while it is still there (a text-size change).
  void _showAndFocus(int id, {_End? end, FocusNode? control}) {
    final index = _service.items.indexWhere((e) => e.id == id);
    _focusStep(id, index, end, ++_focusTicket, 200, control);
  }

  void _focusStep(
    int id,
    int index,
    _End? end,
    int ticket,
    int triesLeft,
    FocusNode? control,
  ) {
    if (!mounted || ticket != _focusTicket) return;
    // A dialog or a menu went on top meanwhile (End still stepping when the
    // menu opened): the request is dropped, never resumed, so no row takes
    // the focus from the modal, and the modal gives it back to its opener
    // when it closes (BUG-D3).
    if (!canTakeFocus(context)) {
      _focusPending = false;
      _releaseHold();
      return;
    }
    final items = _service.items;
    if (items.isEmpty) {
      _focusPending = false;
      _releaseHold();
      _screenFocus.requestFocus();
      return;
    }
    var at = items.indexWhere((e) => e.id == id);
    if (at < 0 ||
        (end == _End.last && at != items.length - 1) ||
        (end == _End.first && at != 0)) {
      // The row went while the list scrolled to it: never leave the focus on
      // nothing. The new end row, or the row now at its place.
      at = switch (end) {
        _End.first => 0,
        _End.last => items.length - 1,
        null => index.clamp(0, items.length - 1),
      };
      id = items[at].id;
    }
    final node = _nodes[id];
    final box = _laidOutRow(node);
    FocusNode target(FocusNode row) =>
        control != null &&
            (control.context?.mounted ?? false) &&
            (control == row || control.ancestors.contains(row))
        ? control
        : row;
    if (node != null && box != null) {
      _focusPending = false;
      _lostFocusId = null;
      box.showOnScreen();
      final to = target(node);
      if (!to.hasPrimaryFocus) to.requestFocus();
      _releaseHold();
      return;
    }
    // A row that is built but off screen (the focused row is kept alive when
    // new copies push it down) takes the focus now; the scroll follows.
    if (node != null && (node.context?.mounted ?? false)) {
      final to = target(node);
      if (!to.hasPrimaryFocus) to.requestFocus();
    }
    if (triesLeft == 0 || !_scroll.hasClients) {
      _focusPending = false;
      _releaseHold();
      return;
    }
    _focusPending = true;
    _scrollTowards(at, items);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusStep(id, at, end, ticket, triesLeft - 1, control),
    );
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// The row's box if it is laid out in the list now: not a row whose element
  /// is gone (a resize or a scroll disposed it: BUG-H2), and not one only kept
  /// alive off screen.
  RenderBox? _laidOutRow(FocusNode? node) {
    final context = node?.context;
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    RenderObject? child = box;
    while (child != null &&
        child.parentData is! SliverMultiBoxAdaptorParentData) {
      child = child.parent;
    }
    final data = child?.parentData;
    if (data is SliverMultiBoxAdaptorParentData && data.keptAlive) return null;
    return box;
  }

  /// After the list changed (new copies above, a trim): the focused row is
  /// scrolled back into view, unless a focus request is already on its way.
  void _keepFocusedRowInView() {
    if (!mounted || _focusPending) return;
    for (final MapEntry(key: id, value: node) in _nodes.entries) {
      if (!node.hasFocus) continue;
      final box = _laidOutRow(node);
      if (box != null) {
        box.showOnScreen();
      } else {
        _showAndFocus(id, control: FocusManager.instance.primaryFocus);
      }
      return;
    }
  }

  /// One step towards the row at [target], which is not laid out: towards
  /// either end of the list for the first and last rows, else from the
  /// nearest laid-out row, by the average height of the laid-out rows.
  ///
  /// A step is at most 40 screens. Rows differ in height, so the list builds
  /// every row on the way to an offset; one jump across 5,000 rows built them
  /// all in one frame and took far longer than the same rows in small steps.
  void _scrollTowards(int target, List<ClipItem> items) {
    final pos = _scroll.position;
    final double to;
    if (target == 0) {
      to = pos.minScrollExtent;
    } else if (target == items.length - 1) {
      to = pos.maxScrollExtent;
    } else {
      to = _estimatedOffset(items, target, pos) ?? pos.pixels;
    }
    final step = pos.viewportDimension * 40;
    final next = (pos.pixels + (to - pos.pixels).clamp(-step, step)).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if (next != pos.pixels) pos.jumpTo(next);
  }

  /// Where the row at [target] probably is: from the nearest laid-out row,
  /// by the average height of the laid-out rows, centred on the screen.
  double? _estimatedOffset(
    List<ClipItem> items,
    int target,
    ScrollPosition pos,
  ) {
    (int, double)? nearest;
    var heights = 0.0;
    var count = 0;
    for (var i = 0; i < items.length; i++) {
      final box = _laidOutRow(_nodes[items[i].id]);
      if (box == null) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      heights += box.size.height + KusungaTokens.space1;
      count++;
      if (nearest == null || (i - target).abs() < (nearest.$1 - target).abs()) {
        nearest = (i, viewport.getOffsetToReveal(box, 0).offset);
      }
    }
    if (nearest == null) return null;
    final (index, top) = nearest;
    return top +
        (target - index) * (heights / count) -
        pos.viewportDimension / 2;
  }

  // Both confirm dialogs follow the live count while they are open (a copy
  // can arrive meanwhile), so they always say what confirming deletes
  // (BUG-W1).
  Future<void> _confirmClear() async {
    final confirmed = await showClearHistoryDialog(context, _service);
    if (confirmed == true) {
      _service.clear();
      // Undo must not bring back an item the user just cleared.
      _pendingUndo = null;
      _messenger.currentState?.hideCurrentSnackBar();
    }
    _focusMore();
  }

  /// The focus goes back to the "More options" button, the control that
  /// opened the menu and the Clear history dialog (spec: "Esc closes menus
  /// and dialogs and returns focus to the control that opened them"), with
  /// or without a copy meanwhile (BUG-D2). Not while another route is on top.
  void _focusMore() {
    if (!mounted || !canTakeFocus(context)) return;
    // The button is the node Tab reaches below the wrap: focusable and
    // traversable. Descendants are listed innermost first, so a wrapper that
    // Flutter may one day put around the button is never picked instead of
    // it (reviewer F-M1).
    final nodes = _moreWrap.traversalDescendants;
    if (nodes.isNotEmpty) nodes.first.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final items = _service.items;
    _prune(items);
    final setupCard = _service.pasteAccess == PasteAccess.needsSetup;
    // While a dialog or a menu is on top the rows never ask for the focus: a
    // copy or a delete must not pull it out of the modal (BUG-D1; see
    // canTakeFocus). Reading the route status here rebuilds on push and pop.
    final routeIsCurrent = canTakeFocus(context);

    return ScaffoldMessenger(
      key: _messenger,
      // Cmd/Ctrl+Z undoes a delete only when one is waiting and the focus is
      // not in a text field. Otherwise the action is disabled and the key goes
      // on to the text field's own undo.
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              _UndoDeleteIntent(),
          SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
              _UndoDeleteIntent(),
        },
        child: Actions(
          actions: {
            _UndoDeleteIntent: _UndoDeleteAction(
              isAvailable: () => _pendingUndo != null && !_focusIsInTextField(),
              onUndo: _undo,
            ),
          },
          child: Focus(
            focusNode: _screenFocus,
            onKeyEvent: _onScreenKey,
            child: Scaffold(
              backgroundColor: t.surface,
              body: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(KusungaTokens.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header, banners and the setup card scroll with the list, so
                      // nothing is cut off at 200% text on a small window.
                      Expanded(
                        child: Listener(
                          onPointerDown: _stopFollowing,
                          onPointerSignal: _stopFollowing,
                          onPointerPanZoomStart: _stopFollowing,
                          child: CustomScrollView(
                            controller: _scroll,
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _Header(
                                      count: items.length,
                                      moreWrap: _moreWrap,
                                      onClear: _confirmClear,
                                      onMenuCancelled: _focusMore,
                                    ),
                                    SizedBox(height: KusungaTokens.space3),
                                    // M1.6: while paused, before the list
                                    // (Resume comes first in tab order).
                                    PausedBanner(pause: _service.pause),
                                    for (final b in _service.banners)
                                      _Banner(
                                        banner: b,
                                        dataProfileRejected:
                                            widget.dataProfileRejected,
                                        onDismiss: () => _service.dismiss(b),
                                      ),
                                    if (setupCard)
                                      _SetupCard(service: _service),
                                    if (widget.topSlot != null) widget.topSlot!,
                                  ],
                                ),
                              ),
                              if (items.isEmpty)
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _EmptyState(),
                                )
                              else
                                _list(items, setupCard, routeIsCurrent),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: KusungaTokens.space2),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _footer,
                          style: KusungaTokens.caption.copyWith(
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _focusIsInTextField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Widget _list(List<ClipItem> items, bool setupCard, bool routeIsCurrent) {
    final now = _nowMs;
    // Tab enters the list at the rows in view, and every row it reaches is
    // scrolled into view (QA-M14-5).
    return FocusTraversalGroup(
      policy: ListTraversalPolicy(),
      child: SliverSemantics(
        label:
            'Clipboard history, ${items.length} '
            '${items.length == 1 ? 'item' : 'items'}',
        explicitChildNodes: true,
        sliver: SliverPadding(
          padding: EdgeInsets.only(bottom: KusungaTokens.space6 * 2),
          sliver: SliverList.separated(
            itemCount: items.length,

            separatorBuilder: (_, _) => SizedBox(height: KusungaTokens.space1),
            itemBuilder: (context, i) {
              final item = items[i];
              return HistoryRow(
                key: ValueKey(item.id),
                item: item,
                focusNode: _nodeFor(item.id),
                nowMs: now,
                animateIn: _newIds.contains(item.id),
                autofocus: i == 0 && !setupCard && routeIsCurrent,
                onCopy: () => _copy(item.id),
                onDelete: () => _delete(item.id),
                onMove: (m) => _move(item.id, m),
                onDisposedWithFocus: () => _rowLostFocus(item.id),
                onSaveAsSnippet: () => _saveAsSnippet(item.id),
                canSaveAsSnippet: _service.snippets.canCreate,
                keepAlive: item.id == _holdId,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The title and the ⋯ menu. The Keep field moved to the Settings tab
/// (M1.7, D1 A).
class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.moreWrap,
    required this.onClear,
    required this.onMenuCancelled,
  });

  final int count;
  final VoidCallback onClear;

  /// The menu closed without a choice.
  final VoidCallback onMenuCancelled;

  /// A node placed above the "More options" button (see `_focusMore`).
  final FocusNode moreWrap;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final title = Semantics(
      header: true,
      child: Text(
        'History',
        style: KusungaTokens.title.copyWith(color: t.text),
      ),
    );
    final controls = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: KusungaTokens.space2,
      runSpacing: KusungaTokens.space2,
      children: [
        Focus(
          focusNode: moreWrap,
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          child: PopupMenuButton<Object?>(
            tooltip: 'More options',
            icon: Icon(Icons.more_horiz, color: t.text),
            onSelected: (_) => onClear(),
            onCanceled: onMenuCancelled,
            itemBuilder: (context) => [
              PopupMenuItem<Object?>(
                value: 'clear',
                enabled: count > 0,
                child: const Text('Clear history'),
              ),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              SizedBox(height: KusungaTokens.space2),
              controls,
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [title, controls],
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.banner,
    required this.dataProfileRejected,
    required this.onDismiss,
  });

  final HistoryBanner banner;
  final bool dataProfileRejected;
  final VoidCallback onDismiss;

  static String textFor(
    HistoryBanner b, {
    required bool dataProfileRejected,
  }) => switch (b) {
    // Debug builds only: the keychain is fine, the switch was the cause
    // (QA-M14-6).
    HistoryBanner.memoryOnly when dataProfileRejected =>
      "History won't be kept after you quit, because the test profile switch wasn't recognised.",
    HistoryBanner.memoryOnly =>
      "History won't be kept after you quit, because Kusunga can't reach your keychain.",
    HistoryBanner.readError =>
      "Kusunga couldn't read your old history, so it started a new one.",
    HistoryBanner.incompatible =>
      "This history was made by a newer or different version of Kusunga. It's safe, but this version can't open it. History won't be kept until you update.",
    HistoryBanner.backupFailed =>
      "Kusunga couldn't make a safety copy of your data, so nothing was changed. Free up some disk space, then quit and reopen Kusunga.",
    HistoryBanner.writeError =>
      "Couldn't save the latest item. Kusunga will try again.",
    HistoryBanner.clearError => "Couldn't clear history. Try again.",
    HistoryBanner.expiryFailed =>
      "Couldn't remove old items. Kusunga will try again.",
  };

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: KusungaTokens.space2),
      child: Container(
        padding: EdgeInsets.only(
          left: KusungaTokens.space3,
          top: KusungaTokens.space1,
          bottom: KusungaTokens.space1,
        ),
        decoration: BoxDecoration(
          color: t.bannerWarnBg,
          borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                focusable: true,
                child: Focus(
                  child: Text(
                    textFor(banner, dataProfileRejected: dataProfileRejected),
                    style: KusungaTokens.body.copyWith(color: t.bannerWarnText),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: Icon(Icons.close, color: t.bannerWarnText),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// "History paused until 14:30. New copies aren't kept." with Resume (M1.6
/// UI spec), shown while paused; or, after a pause that failed, "Couldn't
/// apply the pause. Try again." The banner tokens of `_Banner`. While
/// paused, that error shows inside this banner, under its text (N1).
class PausedBanner extends StatelessWidget {
  const PausedBanner({super.key, required this.pause});

  final PauseService pause;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pause,
      builder: (context, _) {
        final t = KusungaTokens.of(context);
        if (!pause.isPaused) {
          // A pause that failed (from the tray, or anywhere): the warning
          // banner until the user's next pause or resume (PM decision
          // 2026-11-10, UI spec "Tray menu / Error").
          if (pause.error != PauseError.apply) return const SizedBox.shrink();
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
              child: _applyFailed(t),
            ),
          );
        }
        final end = pauseEndText(context, pause);
        final text = end == null
            ? "History paused. New copies aren't kept."
            : "History paused until $end. New copies aren't kept.";
        return Padding(
          padding: EdgeInsets.only(bottom: KusungaTokens.space2),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: KusungaTokens.space3,
              vertical: KusungaTokens.space1,
            ),
            decoration: BoxDecoration(
              color: t.bannerWarnBg,
              borderRadius: BorderRadius.circular(KusungaTokens.radius2),
            ),
            // Text and Resume on one row when they fit; at narrow widths
            // the text wraps and Resume moves below it. A failed apply
            // goes under them, in the same banner (N1).
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: KusungaTokens.space2,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.pause,
                            size: 16,
                            color: t.bannerWarnText,
                          ),
                        ),
                        SizedBox(width: KusungaTokens.space2),
                        Flexible(
                          child: Text(
                            text,
                            style: KusungaTokens.body.copyWith(
                              color: t.bannerWarnText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Semantics(
                      identifier: 'history-paused-resume',
                      label: 'Resume history',
                      button: true,
                      excludeSemantics: true,
                      onTap: () => unawaited(pause.resume()),
                      child: TextButton(
                        onPressed: () => unawaited(pause.resume()),
                        child: Text(
                          'Resume',
                          style: TextStyle(color: t.bannerWarnText),
                        ),
                      ),
                    ),
                  ],
                ),
                if (pause.error == PauseError.apply) ...[
                  SizedBox(height: KusungaTokens.space1),
                  _applyFailed(t),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _applyFailed(KusungaTokens t) => Semantics(
    identifier: 'history-pause-failed',
    liveRegion: true,
    child: Text(
      "Couldn't apply the pause. Try again.",
      style: KusungaTokens.body.copyWith(color: t.bannerWarnText),
    ),
  );
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.service});

  final HistoryService service;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: KusungaTokens.space2),
      child: Container(
        padding: EdgeInsets.all(KusungaTokens.space4),
        decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The heading takes the focus when the card appears, but never
            // from a dialog on top (BUG-D4; see canTakeFocus).
            Focus(
              autofocus: canTakeFocus(context),
              child: Semantics(
                header: true,
                child: Text(
                  'Allow Kusunga to read what you copy',
                  style: KusungaTokens.title.copyWith(color: t.text),
                ),
              ),
            ),
            SizedBox(height: KusungaTokens.space2),
            Text(
              'To keep your history, open System Settings > Privacy & Security > '
              'Paste from Other Apps and choose Allow for Kusunga.',
              style: KusungaTokens.body.copyWith(color: t.text),
            ),
            SizedBox(height: KusungaTokens.space3),
            FilledButton(
              onPressed: service.recheckPasteAccess,
              child: const Text("I've done this"),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.content_paste, size: 40, color: t.textMuted),
            ),
            SizedBox(height: KusungaTokens.space3),
            Text(
              'Nothing here yet',
              style: KusungaTokens.title.copyWith(color: t.text),
            ),
            SizedBox(height: KusungaTokens.space1),
            Text(
              'Copy some text in any app and it will appear here.',
              textAlign: TextAlign.center,
              style: KusungaTokens.body.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _UndoDeleteIntent extends Intent {
  const _UndoDeleteIntent();
}

class _UndoDeleteAction extends Action<_UndoDeleteIntent> {
  _UndoDeleteAction({required this.isAvailable, required this.onUndo});

  final bool Function() isAvailable;
  final VoidCallback onUndo;

  @override
  bool isEnabled(_UndoDeleteIntent intent) => isAvailable();

  @override
  Object? invoke(_UndoDeleteIntent intent) {
    onUndo();
    return null;
  }
}

/// A focus request for the first or the last row.
enum _End { first, last }

/// The "Clear all history?" dialog (M1.2), also used by Settings › Your
/// data › Delete all history… (M1.8 D4 A: the same dialog). True if the
/// user confirmed.
///
/// It follows the live count while it is open (a copy can arrive
/// meanwhile), so it always says what confirming deletes (BUG-W1). At a
/// count of 0 (items deleted elsewhere) it closes by itself, as Cancel
/// would (PM decision 2026-11-08, "Close or relabel"). The count is the
/// list in memory, never a store read, so a failed read or save cannot
/// close it.
Future<bool> showClearHistoryDialog(
  BuildContext context,
  HistoryService service,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => CloseAtZero(
      listenable: service,
      count: () => service.items.length,
      builder: (context, count) => AlertDialog(
        title: const Text('Clear all history?'),
        content: Text(
          // "all 1 item" reads oddly: one item is "the 1 item" (lead,
          // 2026-11-06, QA-M14-7).
          '${count == 1 ? 'This deletes the 1 item.' : 'This deletes all $count items.'} '
          'Snippets are not affected.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KusungaTokens.of(context).danger,
              foregroundColor: KusungaTokens.of(context).surface,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}
