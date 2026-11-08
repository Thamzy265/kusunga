import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../ignored_apps.dart';
import '../shortcut_service.dart';
import '../typed_shortcuts_port.dart';

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
const _addAppText = 'Add app…';
const _restorePresets = 'Restore preset list';
const _noApps = 'No apps. Kusunga still skips password fields.';
const _presetRestored = 'Preset list restored';
const _listFailed = "Couldn't update the list. Try again.";
const _cardTitle = 'Turn on typed shortcuts?';
const _cardText =
    'To notice your shortcuts, Kusunga needs the Input Monitoring permission.';
const _cardBullets = [
  'Kusunga keeps only the last few characters you type, for 5 seconds, in '
      'memory. It never saves or sends them.',
  'Password fields and the apps you list are always skipped.',
  'You can turn this off at any time.',
];
const _chooseTitle = 'Choose an app';
const _searchApps = 'Search apps…';
const _added = 'Added';
const _findingApps = 'Finding apps…';
const _noOtherApps = 'No other apps are open. Open the app, then try again.';

/// Names over 30 characters end with an ellipsis (the full name stays in the
/// accessible name).
String _shortName(String name) {
  final runes = name.runes.toList();
  if (runes.length <= 30) return name;
  return '${String.fromCharCodes(runes.take(30)).trimRight()}…';
}

/// "Typed shortcuts" in the Snippets tab: the switch, the status line, and
/// the ignore list (M1.5 UI spec). On a Mac, turning the switch on without
/// Input Monitoring first explains what Kusunga watches.
class TypedShortcutsSection extends StatefulWidget {
  const TypedShortcutsSection({
    super.key,
    required this.service,
    required this.isMac,
  });

  final ShortcutService service;
  final bool isMac;

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
  }

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

  void _toast(String text, {SnackBarAction? action, Duration? duration}) {
    final m = ScaffoldMessenger.maybeOf(context);
    m
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: action,
          duration: duration ?? const Duration(seconds: 2),
          persist: false,
          behavior: SnackBarBehavior.floating,
          width: 320,
        ),
      );
  }

  void _remove(IgnoredApp app) {
    final removed = _s.removeApp(app.appId);
    if (removed == null) {
      _toast(_listFailed);
      return;
    }
    _toast(
      '${removed.displayName} removed',
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          if (!_s.undoRemove(removed)) _toast(_listFailed);
        },
      ),
    );
  }

  void _restore() {
    _toast(_s.restorePresets() ? _presetRestored : _listFailed);
  }

  Future<void> _addApp() async {
    final app = await showDialog<RunningApp>(
      context: context,
      builder: (context) => _ChooseAppDialog(service: _s),
    );
    if (app == null || !mounted) return;
    if (!_s.addApp(app)) _toast(_listFailed);
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
                // With reduce motion on, a new switch is built for each value,
                // so it starts at its end position and never slides.
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
                  for (final app in _s.ignoredApps)
                    _AppChip(app: app, onRemove: () => _remove(app)),
                ],
              ),
            gap,
            Wrap(
              spacing: KusungaTokens.space2,
              runSpacing: KusungaTokens.space2,
              children: [
                Semantics(
                  identifier: 'typed-shortcuts-add-app',
                  label: 'Add an app to ignore',
                  button: true,
                  excludeSemantics: true,
                  onTap: _addApp,
                  child: OutlinedButton(
                    onPressed: _addApp,
                    child: const Text(_addAppText),
                  ),
                ),
                if (_s.canRestorePresets)
                  Semantics(
                    identifier: 'typed-shortcuts-restore-presets',
                    child: TextButton(
                      onPressed: _restore,
                      child: const Text(_restorePresets),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One ignored app: its name and a 24 px Remove button.
class _AppChip extends StatefulWidget {
  const _AppChip({required this.app, required this.onRemove});

  final IgnoredApp app;
  final VoidCallback onRemove;

  @override
  State<_AppChip> createState() => _AppChipState();
}

class _AppChipState extends State<_AppChip> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final name = widget.app.displayName;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: EdgeInsetsDirectional.only(start: KusungaTokens.space2),
        decoration: BoxDecoration(
          color: _hovered ? t.surfaceHover : t.surface,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The chip is never wider than the row: a long name ends with an
            // ellipsis, and Remove stays on screen (U1).
            Flexible(
              child: ExcludeSemantics(
                child: Text(
                  _shortName(name),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: KusungaTokens.body.copyWith(color: t.text),
                ),
              ),
            ),
            Semantics(
              identifier: 'ignored-app-remove-${widget.app.appId}',
              label: 'Remove $name from ignored apps',
              button: true,
              excludeSemantics: true,
              onTap: widget.onRemove,
              child: SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  tooltip: 'Remove',
                  onPressed: widget.onRemove,
                  icon: Icon(Icons.close, color: t.text),
                ),
              ),
            ),
          ],
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

/// "Choose an app": the running apps, searchable by name. Enter adds the
/// first one that can be added; apps already on the list say "Added".
class _ChooseAppDialog extends StatefulWidget {
  const _ChooseAppDialog({required this.service});

  final ShortcutService service;

  @override
  State<_ChooseAppDialog> createState() => _ChooseAppDialogState();
}

class _ChooseAppDialogState extends State<_ChooseAppDialog> {
  List<RunningAppChoice>? _apps;
  var _query = '';
  var _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _apps == null) setState(() => _slow = true);
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final apps = await widget.service.runningApps();
    if (!mounted) return;
    _slowTimer?.cancel();
    setState(() => _apps = apps);
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  List<RunningAppChoice> get _shown {
    final q = _query.trim().toLowerCase();
    final apps = _apps ?? const <RunningAppChoice>[];
    if (q.isEmpty) return apps;
    return [
      for (final a in apps)
        if (a.app.name.toLowerCase().contains(q)) a,
    ];
  }

  void _choose(RunningApp app) => Navigator.of(context).pop(app);

  void _enter() {
    for (final a in _shown) {
      if (!a.added) return _choose(a.app);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final full = MediaQuery.sizeOf(context).width < 600;
    final apps = _apps;
    final shown = _shown;
    Widget list;
    if (apps == null) {
      list = Padding(
        padding: EdgeInsets.all(KusungaTokens.space3),
        child: Semantics(
          liveRegion: true,
          child: Text(
            _slow ? _findingApps : '',
            style: KusungaTokens.body.copyWith(color: t.textMuted),
          ),
        ),
      );
    } else if (apps.isEmpty) {
      list = Padding(
        padding: EdgeInsets.all(KusungaTokens.space3),
        child: Text(
          _noOtherApps,
          style: KusungaTokens.body.copyWith(color: t.textMuted),
        ),
      );
    } else {
      list = ListView(
        shrinkWrap: true,
        children: [
          for (final a in shown)
            Semantics(
              identifier: 'add-app-row-${a.app.appId}',
              label: a.added ? '${a.app.name}, $_added' : a.app.name,
              button: true,
              enabled: !a.added,
              excludeSemantics: true,
              onTap: a.added ? null : () => _choose(a.app),
              child: ListTile(
                enabled: !a.added,
                dense: true,
                leading: SizedBox(
                  width: 24,
                  height: 24,
                  child: a.app.icon == null
                      ? Icon(Icons.apps, size: 20, color: t.textMuted)
                      : Image.memory(
                          a.app.icon!,
                          width: 24,
                          height: 24,
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.apps, size: 20, color: t.textMuted),
                        ),
                ),
                title: Text(
                  a.app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KusungaTokens.body.copyWith(color: t.text),
                ),
                trailing: a.added
                    ? Text(
                        _added,
                        style: KusungaTokens.caption.copyWith(
                          color: t.textMuted,
                        ),
                      )
                    : null,
                onTap: a.added ? null : () => _choose(a.app),
              ),
            ),
        ],
      );
    }
    final body = Semantics(
      identifier: 'choose-app-dialog',
      label: _chooseTitle,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: Padding(
        padding: EdgeInsets.all(KusungaTokens.space5),
        child: Column(
          mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                _chooseTitle,
                style: KusungaTokens.title.copyWith(color: t.text),
              ),
            ),
            SizedBox(height: KusungaTokens.space3),
            Semantics(
              identifier: 'choose-app-search',
              child: TextField(
                autofocus: true,
                onChanged: (q) => setState(() => _query = q),
                onSubmitted: (_) => _enter(),
                style: KusungaTokens.body.copyWith(color: t.text),
                decoration: const InputDecoration(hintText: _searchApps),
              ),
            ),
            SizedBox(height: KusungaTokens.space2),
            // Esc or a click outside closes the list.
            Flexible(child: list),
          ],
        ),
      ),
    );
    final framed = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: body,
    );
    if (full) {
      return Dialog.fullscreen(backgroundColor: t.surface, child: framed);
    }
    return Dialog(
      backgroundColor: t.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 480),
        child: framed,
      ),
    );
  }
}
