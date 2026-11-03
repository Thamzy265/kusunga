import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../clipboard/clipboard_source.dart';
import '../../theme/tokens.dart';
import '../clip_item.dart';
import '../history_service.dart';
import 'history_row.dart';
import 'limit_field.dart';

/// The home view: what Kusunga has saved, with Copy, Delete (with Undo),
/// Clear history and the limit. Spec: `docs/ui/clipboard-history.md`.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.service, this.now});

  final HistoryService service;

  /// Unix milliseconds; replaced in tests.
  final int Function()? now;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _footerEvery = Duration(seconds: 2);

  final _nodes = <int, FocusNode>{};
  final _seen = <int>{};
  final _newIds = <int>{};
  final _messenger = GlobalKey<ScaffoldMessengerState>();
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
    _service.addListener(_onChange);
    _footer = _footerText();
    _holdFooter();
    // Relative times ("2 min") move on without any other event.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    _clock?.cancel();
    _footerTimer?.cancel();
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

  void _prune(List<ClipItem> items) {
    final ids = items.map((i) => i.id).toSet();
    final gone = _nodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in gone) {
      final node = _nodes.remove(id)!;
      // Dispose after this frame: the row is still being torn down.
      WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
    }
    _newIds.removeWhere((id) => !ids.contains(id));
  }

  void _toast(String message, {SnackBarAction? action, Duration? duration}) {
    final m = _messenger.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
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
    m?.hideCurrentSnackBar();
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
    if (hadFocus && neighbour != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nodes[neighbour]?.requestFocus();
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
    final items = _service.items;
    final i = items.indexWhere((e) => e.id == id);
    if (i < 0 || items.isEmpty) return;
    final target = switch (move) {
      RowMove.previous => (i - 1).clamp(0, items.length - 1),
      RowMove.next => (i + 1).clamp(0, items.length - 1),
      RowMove.first => 0,
      RowMove.last => items.length - 1,
    };
    _nodes[items[target].id]?.requestFocus();
  }

  Future<void> _confirmClear() async {
    final count = _service.items.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all history?'),
        content: Text(
          'This deletes all $count items. Snippets are not affected.',
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
    );
    if (confirmed == true) {
      _service.clear();
      // Undo must not bring back an item the user just cleared.
      _pendingUndo = null;
      _messenger.currentState?.hideCurrentSnackBar();
    }
  }

  Future<bool> _confirmLower(int newLimit, int removed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          'Keep only the newest $newLimit items? '
          '$removed older items will be deleted.',
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
            child: Text('Delete $removed items'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final items = _service.items;
    _prune(items);
    final setupCard = _service.pasteAccess == PasteAccess.needsSetup;

    return ScaffoldMessenger(
      key: _messenger,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        },
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
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Header(
                                service: _service,
                                count: items.length,
                                onClear: _confirmClear,
                                confirmLower: _confirmLower,
                                onSaveFailed: () => _toast(
                                  "Couldn't save that number. Try again.",
                                ),
                              ),
                              SizedBox(height: KusungaTokens.space3),
                              for (final b in _service.banners)
                                _Banner(
                                  banner: b,
                                  onDismiss: () => _service.dismiss(b),
                                ),
                              if (setupCard) _SetupCard(service: _service),
                            ],
                          ),
                        ),
                        if (items.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(),
                          )
                        else
                          _list(items, setupCard),
                      ],
                    ),
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

  Widget _list(List<ClipItem> items, bool setupCard) {
    final now = _nowMs;
    return SliverSemantics(
      label: 'Clipboard history, ${items.length} items',
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
              autofocus: i == 0 && !setupCard,
              onCopy: () => _copy(item.id),
              onDelete: () => _delete(item.id),
              onMove: (m) => _move(item.id, m),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.service,
    required this.count,
    required this.onClear,
    required this.confirmLower,
    required this.onSaveFailed,
  });

  final HistoryService service;
  final int count;
  final VoidCallback onSaveFailed;
  final VoidCallback onClear;
  final Future<bool> Function(int newLimit, int removed) confirmLower;

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
        LimitField(
          service: service,
          confirmLower: confirmLower,
          onSaveFailed: onSaveFailed,
        ),
        PopupMenuButton<Object?>(
          tooltip: 'More options',
          icon: Icon(Icons.more_horiz, color: t.text),
          onSelected: (_) => onClear(),
          itemBuilder: (context) => [
            PopupMenuItem<Object?>(
              value: 'clear',
              enabled: count > 0,
              child: const Text('Clear history'),
            ),
          ],
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
  const _Banner({required this.banner, required this.onDismiss});

  final HistoryBanner banner;
  final VoidCallback onDismiss;

  static String textFor(HistoryBanner b) => switch (b) {
    HistoryBanner.memoryOnly =>
      "History won't be kept after you quit, because Kusunga can't reach your keychain.",
    HistoryBanner.readError =>
      "Kusunga couldn't read your old history, so it started a new one.",
    HistoryBanner.incompatible =>
      "This history was made by a newer or different version of Kusunga. It's safe, but this version can't open it. History won't be kept until you update.",
    HistoryBanner.writeError =>
      "Couldn't save the latest item. Kusunga will try again.",
    HistoryBanner.clearError => "Couldn't clear history. Try again.",
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
                    textFor(banner),
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
            Focus(
              autofocus: true,
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
