import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../ignored_apps.dart';
import '../shortcut_service.dart';
import '../typed_shortcuts_port.dart';
import 'ignored_apps_editor.dart' show shortAppName;

// Copy from the UI spec (`docs/ui/typed-shortcuts.md`, "Copy").
const _title = 'Typed shortcuts';
const _description =
    "Type a snippet's shortcut, like ;email, in any app to paste it.";
const _statusOn = 'On · Skipped in password fields and these apps:';
const _statusStarting = 'Starting…';
const _statusNeedsPermission =
    "Needs Input Monitoring. Kusunga can't see your shortcuts until you "
    'allow it.';
const _statusPaused = 'Paused while another app protects your typing.';
const _statusFailed = "Couldn't start typed shortcuts.";
const _statusStopped = 'Typed shortcuts stopped. Turn them off and on again.';
const _statusUnavailable =
    "Typed shortcuts are off because snippets can't be opened right now.";
const _openSettings = 'Open System Settings';
const _noApps = 'No apps. Kusunga still skips password fields.';
const _editIgnored = 'Edit ignored apps';
const _cardTitle = 'Turn on typed shortcuts?';
const _cardText =
    'To notice your shortcuts, Kusunga needs the Input Monitoring permission.';
const _cardBullets = [
  'Kusunga keeps only the last few characters you type, for 5 seconds, in '
      'memory. It never saves or sends them.',
  'Password fields and the apps you list are always skipped.',
  'You can turn this off at any time.',
];

/// "Typed shortcuts" in the Snippets tab: the switch, the status line, and
/// the ignore list (M1.5 UI spec), read only since M1.6: it is edited in the
/// Privacy tab, which "Edit ignored apps" opens. On a Mac, turning the switch on without
/// Input Monitoring first explains what Kusunga watches.
class TypedShortcutsSection extends StatefulWidget {
  const TypedShortcutsSection({
    super.key,
    required this.service,
    required this.isMac,
    this.onEditIgnoredApps,
  });

  final ShortcutService service;
  final bool isMac;

  /// "Edit ignored apps": opens the Privacy tab with the focus on the list
  /// (M1.6). Without it the link is not shown.
  final VoidCallback? onEditIgnoredApps;

  @override
  State<TypedShortcutsSection> createState() => _TypedShortcutsSectionState();
}

class _TypedShortcutsSectionState extends State<TypedShortcutsSection> {
  final _switchNode = FocusNode(debugLabel: 'typed shortcuts switch');
  Timer? _startingTimer;
  var _showStarting = false;

  ShortcutService get _s => widget.service;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
    _switchNode.addListener(_ringChanged);
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
  }

  /// The switch's focus ring (QA-M15-1): shown, like the buttons' ring, only
  /// for keyboard focus.
  bool get _showRing =>
      _switchNode.hasFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  void _ringChanged() {
    if (mounted) setState(() {});
  }

  void _highlightChanged(FocusHighlightMode _) => _ringChanged();

  @override
  void didUpdateWidget(TypedShortcutsSection old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service.removeListener(_changed);
      widget.service.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    _switchNode.removeListener(_ringChanged);
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    _startingTimer?.cancel();
    _switchNode.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // "Starting…" only if native code takes more than 300 ms.
    if (_s.busy && _startingTimer == null && !_showStarting) {
      _startingTimer = Timer(const Duration(milliseconds: 300), () {
        _startingTimer = null;
        if (mounted && _s.busy) setState(() => _showStarting = true);
      });
    } else if (!_s.busy) {
      _startingTimer?.cancel();
      _startingTimer = null;
      _showStarting = false;
    }
    setState(() {});
  }

  Future<void> _toggle(bool on) async {
    if (!_s.available) return;
    final status = await _s.setEnabled(on);
    if (!mounted || !on) return;
    if (widget.isMac && status == TypedShortcutStatus.needsPermission) {
      await _explain();
    }
  }

  /// The explanation card, before macOS's own prompt.
  Future<void> _explain() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => const _ExplanationCard(),
    );
    if (!mounted) return;
    if (go == true) {
      await _s.requestPermission();
    } else {
      // "Not now" (or Esc): the switch goes back to Off, with the focus.
      await _s.setEnabled(false);
      if (mounted) _switchNode.requestFocus();
    }
  }

  String? _statusText() {
    if (!_s.available) return _statusUnavailable;
    if (!_s.enabled) return null;
    if (_showStarting) return _statusStarting;
    return switch (_s.status) {
      TypedShortcutStatus.on => _statusOn,
      TypedShortcutStatus.needsPermission => _statusNeedsPermission,
      TypedShortcutStatus.paused => _statusPaused,
      TypedShortcutStatus.failed => _statusFailed,
      TypedShortcutStatus.stopped => _statusStopped,
      // The switch is on but native code has not answered yet.
      TypedShortcutStatus.off => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final on = _s.enabled;
    final status = _statusText();
    final gap = SizedBox(height: KusungaTokens.space2);
    final showPermissionButton =
        widget.isMac &&
        on &&
        _s.available &&
        _s.status == TypedShortcutStatus.needsPermission;

    return Padding(
      padding: EdgeInsets.only(bottom: KusungaTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _title,
                    style: KusungaTokens.body.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  on ? 'On' : 'Off',
                  style: KusungaTokens.body.copyWith(color: t.text),
                ),
              ),
              SizedBox(width: KusungaTokens.space2),
              Semantics(
                identifier: 'typed-shortcuts-switch',
                label: _title,
                toggled: on,
                enabled: _s.available,
                // Keyboard focus: the 2 px `focus` ring of the buttons, chips
                // and tabs, drawn outside the switch on the background (3:1
                // there). Material's own halo is about 1.25:1 (QA-M15-1).
                child: DecoratedBox(
                  key: const ValueKey('typed-shortcuts-switch-ring'),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _showRing ? t.focus : Colors.transparent,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  // With reduce motion on, a new switch is built for each
                  // value, so it starts at its end position and never slides.
                  child: KeyedSubtree(
                    key: ValueKey(
                      MediaQuery.disableAnimationsOf(context) ? on : null,
                    ),
                    child: Switch(
                      key: const ValueKey('typed-shortcuts-switch'),
                      focusNode: _switchNode,
                      value: on,
                      onChanged: _s.available ? _toggle : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(_description, style: KusungaTokens.body.copyWith(color: t.text)),
          if (status != null) ...[
            gap,
            Semantics(
              identifier: 'typed-shortcuts-status',
              liveRegion: true,
              child: Text(
                status,
                style: KusungaTokens.caption.copyWith(color: t.textMuted),
              ),
            ),
          ],
          if (showPermissionButton) ...[
            gap,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                identifier: 'typed-shortcuts-open-settings',
                child: OutlinedButton(
                  onPressed: _s.openSettings,
                  child: const Text(_openSettings),
                ),
              ),
            ),
          ],
          if (on && _s.available) ...[
            gap,
            if (_s.ignoredApps.isEmpty)
              Text(
                _noApps,
                style: KusungaTokens.caption.copyWith(color: t.textMuted),
              )
            else
              Wrap(
                spacing: KusungaTokens.space2,
                runSpacing: KusungaTokens.space2,
                children: [
                  for (final app in _s.ignoredApps) _ReadOnlyChip(app: app),
                ],
              ),
            if (widget.onEditIgnoredApps case final edit?) ...[
              gap,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  identifier: 'typed-shortcuts-edit-ignored',
                  child: _LinkButton(label: _editIgnored, onPressed: edit),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One ignored app, read only: its name (editing is in the Privacy tab).
class _ReadOnlyChip extends StatelessWidget {
  const _ReadOnlyChip({required this.app});

  final IgnoredApp app;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Semantics(
      identifier: 'typed-shortcuts-ignored-${app.appId}',
      label: app.displayName,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: KusungaTokens.space2,
          vertical: KusungaTokens.space1,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        ),
        child: Text(
          shortAppName(app.displayName),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: KusungaTokens.body.copyWith(color: t.text),
        ),
      ),
    );
  }
}

/// A text button whose label is underlined on hover (UI spec, "Edit ignored
/// apps" link).
class _LinkButton extends StatefulWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_LinkButton> createState() => _LinkButtonState();
}

class _LinkButtonState extends State<_LinkButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TextButton(
        onPressed: widget.onPressed,
        child: Text(
          widget.label,
          style: TextStyle(
            decoration: _hovered ? TextDecoration.underline : null,
          ),
        ),
      ),
    );
  }
}

/// The explanation card (Mac): what Kusunga watches, before macOS asks.
/// Answers true for Continue, false or null for Not now (Esc).
class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard();

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final full = MediaQuery.sizeOf(context).width < 600;
    final body = Semantics(
      identifier: 'typed-shortcuts-card',
      label: _cardTitle,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(KusungaTokens.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                _cardTitle,
                style: KusungaTokens.title.copyWith(color: t.text),
              ),
            ),
            SizedBox(height: KusungaTokens.space3),
            Text(_cardText, style: KusungaTokens.body.copyWith(color: t.text)),
            SizedBox(height: KusungaTokens.space2),
            for (final b in _cardBullets)
              Padding(
                padding: EdgeInsets.only(top: KusungaTokens.space1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        '•  ',
                        style: KusungaTokens.body.copyWith(color: t.text),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        b,
                        style: KusungaTokens.body.copyWith(color: t.text),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: KusungaTokens.space4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: KusungaTokens.space2,
              runSpacing: KusungaTokens.space2,
              children: [
                Semantics(
                  identifier: 'typed-shortcuts-card-not-now',
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                ),
                Semantics(
                  identifier: 'typed-shortcuts-card-continue',
                  child: FilledButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (full) return Dialog.fullscreen(backgroundColor: t.surface, child: body);
    return Dialog(
      backgroundColor: t.surface,
      child: SizedBox(width: 440, child: body),
    );
  }
}
