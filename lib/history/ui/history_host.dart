import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../privacy/ui/privacy_screen.dart';
import '../../snippets/snippet_service.dart';
import '../../snippets/ui/snippet_editor.dart';
import '../../snippets/ui/snippets_screen.dart';
import '../../theme/tokens.dart';
import '../../ui/focus_order.dart';
import '../../ui/tab_strip.dart';
import '../history_service.dart';
import 'history_screen.dart';

/// The main window: the History and Snippets tabs (M1.4) and the Privacy tab
/// (M1.6), each shown once the history has opened. If opening takes more than 300 ms a spinner with
/// "Opening your history…" (or "…snippets…") shows; a fast open never
/// flashes it.
class HistoryHost extends StatefulWidget {
  const HistoryHost({
    super.key,
    required this.history,
    this.initial,
    this.topSlot,
    this.snippetsTopSlot,
    this.dataProfile,
    this.dataProfileRejected = false,
    this.ignoredAppsSlot,
  });

  /// Opens the Privacy tab with the focus on its "Ignored apps" heading
  /// ("Edit ignored apps" in the Snippets tab). [context] is inside the
  /// window.
  static void showIgnoredApps(BuildContext context) =>
      context.findAncestorStateOfType<_HistoryHostState>()?._showIgnoredApps();

  final Future<HistoryService> history;

  /// The ignored-apps list editor for the Privacy tab (typed shortcuts,
  /// M1.5, moved there in M1.6). Without it the tab has Pause history only.
  final Widget? ignoredAppsSlot;

  /// The history if it is already open, so there is no empty first frame.
  final HistoryService? initial;

  /// Extra content for the history screen (the picker settings).
  final Widget? topSlot;

  /// Extra content for the snippets screen (typed shortcuts, M1.5).
  final Widget? snippetsTopSlot;

  /// The test data profile in use (Debug builds only), shown as "Test
  /// profile: `name`" so test data is never taken for real data.
  final String? dataProfile;

  /// A test profile switch was given but not recognised (Debug builds
  /// only): the session is memory only, and the banner names the switch,
  /// not the keychain (QA-M14-6).
  final bool dataProfileRejected;

  @override
  State<HistoryHost> createState() => _HistoryHostState();
}

class _HistoryHostState extends State<HistoryHost> {
  late HistoryService? _service = widget.initial;
  var _slow = false;
  Timer? _timer;

  /// 0 History (selected at start), 1 Snippets, 2 Privacy.
  var _tab = 0;
  final _tabNodes = [
    FocusNode(debugLabel: 'History tab'),
    FocusNode(debugLabel: 'Snippets tab'),
    FocusNode(debugLabel: 'Privacy tab'),
  ];
  final _ignoredHeading = FocusNode(debugLabel: 'Ignored apps heading');

  void _showIgnoredApps() {
    setState(() => _tab = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ignoredHeading.context != null) {
        _ignoredHeading.requestFocus();
      }
    });
  }

  final _snippetsKey = GlobalKey<SnippetsScreenState>();

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _service == null) setState(() => _slow = true);
    });
    if (_service == null) {
      widget.history.then((s) {
        if (mounted) setState(() => _service = s);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final n in _tabNodes) {
      n.dispose();
    }
    _ignoredHeading.dispose();
    super.dispose();
  }

  Widget _loading(KusungaTokens t) => _slow
      ? Center(
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                SizedBox(height: KusungaTokens.space3),
                Text(
                  _tab == 1
                      ? 'Opening your snippets…'
                      : 'Opening your history…',
                  style: KusungaTokens.body.copyWith(color: t.text),
                ),
              ],
            ),
          ),
        )
      : const SizedBox.shrink();

  // Each panel stays built while the other shows (a pending Undo, the scroll
  // position and focus are kept), but is hidden from view, touch, focus and
  // screen readers.
  Widget _panel(int index, String label, Widget child) {
    final shown = _tab == index;
    return Offstage(
      offstage: !shown,
      child: TickerMode(
        enabled: shown,
        child: ExcludeFocus(
          excluding: !shown,
          child: Semantics(
            role: SemanticsRole.tabPanel,
            label: label,
            explicitChildNodes: true,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _profileLabel(KusungaTokens t, String name) => Semantics(
    identifier: 'data-profile-label',
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: KusungaTokens.space2,
        vertical: KusungaTokens.space1,
      ),
      decoration: BoxDecoration(
        color: t.bannerWarnBg,
        borderRadius: BorderRadius.circular(KusungaTokens.radius2),
      ),
      child: Text(
        'Test profile: $name',
        style: KusungaTokens.caption.copyWith(color: t.bannerWarnText),
      ),
    ),
  );

  Widget _newButton(SnippetService? snippets) {
    final t = KusungaTokens.of(context);
    final enabled = snippets?.canCreate ?? false;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: KusungaTokens.space2,
      runSpacing: KusungaTokens.space1,
      children: [
        // At the cap the reason is shown as text, not only in a tooltip. In
        // memory-only mode the banner below explains.
        if (snippets != null && snippets.canEdit && snippets.atCap)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              snippetCapMessage,
              style: KusungaTokens.caption.copyWith(color: t.textMuted),
            ),
          ),
        Semantics(
          identifier: 'snippet-new',
          child: FilledButton.icon(
            onPressed: enabled
                ? () => _snippetsKey.currentState?.openNew()
                : null,
            icon: const Icon(Icons.add),
            label: const Text('New snippet'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final service = _service;
    final snippets = service?.snippets;
    final header = Padding(
      padding: EdgeInsets.only(
        left: KusungaTokens.space4,
        right: KusungaTokens.space4,
        top: KusungaTokens.space3,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: KusungaTokens.space3,
        runSpacing: KusungaTokens.space2,
        children: [
          TabStrip(
            labels: const ['History', 'Snippets', 'Privacy'],
            identifiers: const [
              'main-tab-history',
              'main-tab-snippets',
              'main-tab-privacy',
            ],
            selected: _tab,
            focusNodes: _tabNodes,
            onSelect: (i) => setState(() => _tab = i),
          ),
          if (widget.dataProfile case final name?) _profileLabel(t, name),
          if (_tab == 1)
            snippets == null
                ? _newButton(null)
                : ListenableBuilder(
                    listenable: snippets,
                    builder: (context, _) => _newButton(snippets),
                  ),
        ],
      ),
    );

    final Widget body;
    if (service == null) {
      body = _loading(t);
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          _panel(
            0,
            'History',
            HistoryScreen(
              service: service,
              topSlot: widget.topSlot,
              dataProfileRejected: widget.dataProfileRejected,
            ),
          ),
          _panel(
            1,
            'Snippets',
            SnippetsScreen(
              key: _snippetsKey,
              service: service.snippets,
              dataProfileRejected: widget.dataProfileRejected,
              topSlot: widget.snippetsTopSlot,
            ),
          ),
          _panel(
            2,
            'Privacy',
            PrivacyScreen(
              pause: service.pause,
              ignoredHeadingFocus: _ignoredHeading,
              ignoredApps: widget.ignoredAppsSlot,
            ),
          ),
          // Pausing and resuming are announced from any tab (and from the
          // tray), once each.
          Positioned(
            left: 0,
            top: 0,
            child: PauseAnnouncer(pause: service.pause),
          ),
        ],
      );
    }

    // Tab goes through the header (tabs, New snippet) before the panel,
    // wherever the panel is scrolled: rows built just above the view used to
    // come first, unseen (QA-M14-5).
    return Scaffold(
      backgroundColor: t.surface,
      body: SafeArea(
        bottom: false,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(
            secondary: revealingReadingOrder(),
            requestFocusCallback: revealOnTraversal,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: FocusTraversalGroup(
                  policy: revealingReadingOrder(),
                  child: header,
                ),
              ),
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: FocusTraversalGroup(
                    policy: revealingReadingOrder(),
                    child: body,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
