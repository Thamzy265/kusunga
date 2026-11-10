import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../ignored_apps.dart';
import '../shortcut_service.dart';
import '../typed_shortcuts_port.dart';

// Copy from the UI specs (`docs/ui/typed-shortcuts.md` and, for the empty
// list, `docs/ui/sensitive-content.md`).
const _addAppText = 'Add app…';
const _restorePresets = 'Restore preset list';
const _noApps =
    'No apps. Kusunga still skips anything an app marks as private.';
const _presetRestored = 'Preset list restored';
const _listFailed = "Couldn't update the list. Try again.";
const _chooseTitle = 'Choose an app';
const _searchApps = 'Search apps…';
const _added = 'Added';
const _findingApps = 'Finding apps…';
const _noOtherApps = 'No other apps are open. Open the app, then try again.';

/// Names over 30 characters end with an ellipsis (the full name stays in the
/// accessible name).
String shortAppName(String name) {
  final runes = name.runes.toList();
  if (runes.length <= 30) return name;
  return '${String.fromCharCodes(runes.take(30)).trimRight()}…';
}

/// The ignored-apps list editor (M1.5, moved to the Privacy tab in M1.6):
/// chips with Remove and Undo, Add app…, and Restore preset list. Always
/// shown, whether typed shortcuts are on or off: the list also stops
/// history capture (D1 A).
class IgnoredAppsEditor extends StatefulWidget {
  const IgnoredAppsEditor({super.key, required this.service});

  final ShortcutService service;

  @override
  State<IgnoredAppsEditor> createState() => _IgnoredAppsEditorState();
}

class _IgnoredAppsEditorState extends State<IgnoredAppsEditor> {
  ShortcutService get _s => widget.service;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
  }

  @override
  void didUpdateWidget(IgnoredAppsEditor old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service.removeListener(_changed);
      widget.service.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Toasts queue: a new one never hides an earlier Undo, so each removal
  /// keeps its Undo for 5 s (U2). Only [replace] (the preset list is back,
  /// so an earlier Undo has nothing left to do) takes the place of the one
  /// showing.
  void _toast(
    String text, {
    SnackBarAction? action,
    Duration? duration,
    bool replace = false,
  }) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (replace) m?.hideCurrentSnackBar();
    m?.showSnackBar(
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
    final ok = _s.restorePresets();
    _toast(ok ? _presetRestored : _listFailed, replace: ok);
  }

  Future<void> _addApp() async {
    final app = await showDialog<RunningApp>(
      context: context,
      builder: (context) => _ChooseAppDialog(service: _s),
    );
    if (app == null || !mounted) return;
    if (!_s.addApp(app)) _toast(_listFailed);
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        SizedBox(height: KusungaTokens.space2),
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
                  shortAppName(name),
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
