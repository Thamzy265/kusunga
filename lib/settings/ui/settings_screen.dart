import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../history/history_service.dart';
import '../../history/history_store.dart';
import '../../history/ui/limit_field.dart';
import '../../theme/tokens.dart';
import '../../ui/close_at_zero.dart';
import '../../ui/focus_order.dart';
import '../../ui/section_heading.dart';
import '../login_item.dart';

// Copy from the UI spec (`docs/ui/settings-and-expiry.md`, "Copy").
const _general = 'General';
const _history = 'History';
const _loginLabel = 'Launch at login';
const _loginHelpMac = 'Start Kusunga in the menu bar when you log in.';
const _loginHelpWindows = 'Start Kusunga in the tray when you sign in.';
const _openLoginItems = 'Open Login Items';
const _autoDelete = 'Auto-delete';
const _autoDeleteName = 'Auto-delete history';
const _autoDeleteHelp =
    "Items you haven't copied for this long are removed. Snippets are never "
    'removed.';
const _saveFailed = "Couldn't save. Try again.";
const _deleteFailed = "Couldn't delete. Try again.";
const _countFailed = "Couldn't count the items. Try again.";
const _privacyLink = 'Ignored apps and pause are in Privacy';

/// The menu's options, in [historyExpiryChoices] order.
String expiryOption(int days) => switch (days) {
  0 => 'Never',
  1 => 'After 1 day',
  7 => 'After 7 days',
  _ => 'After 30 days',
};

String _expiryLength(int days) => days == 1 ? '1 day' : '$days days';

/// The Settings tab (M1.7, PM decision D1 A): General (launch at login, the
/// picker shortcut) and History (Keep, Auto-delete, and a link to Privacy).
/// Spec: `docs/ui/settings-and-expiry.md`.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.service,
    required this.onShowPrivacy,
    this.loginItem,
    this.pickerShortcut,
  });

  final HistoryService service;

  /// Launch at login (desktop). Without it there is no switch.
  final LoginItemService? loginItem;

  /// The picker shortcut row (M1.3), moved here from History.
  final Widget? pickerShortcut;

  /// Opens the Privacy tab with the focus on its "Pause history" heading.
  final VoidCallback onShowPrivacy;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _menuFocus = FocusNode(debugLabel: 'Auto-delete');
  final _loginFocus = FocusNode(debugLabel: 'Launch at login');
  var _saveError = false;

  HistoryService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _service.expiry.addListener(_changed);
    widget.loginItem?.addListener(_changed);
  }

  @override
  void didUpdateWidget(SettingsScreen old) {
    super.didUpdateWidget(old);
    if (old.loginItem != widget.loginItem) {
      old.loginItem?.removeListener(_changed);
      widget.loginItem?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _service.expiry.removeListener(_changed);
    widget.loginItem?.removeListener(_changed);
    _menuFocus.dispose();
    _loginFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    final m = _messenger.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        persist: false,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Longer or Never, or shorter with nothing to delete: saved at once. A
  /// shorter time that deletes items asks first, with the count (R3).
  Future<void> _choose(int? days) async {
    final expiry = _service.expiry;
    if (days == null || days == expiry.days) return;
    final removed = expiry.countRemovedBy(days);
    if (removed == 0) {
      final n = expiry.setDays(days);
      setState(() => _saveError = n == null);
      if (n != null && n > 0) _toast(_deletedText(n));
      return;
    }
    final confirmed = await _confirmShorter(days);
    // The focus goes back to the menu that opened the dialog.
    if (mounted && canTakeFocus(context)) _menuFocus.requestFocus();
    if (!confirmed || !mounted) return;
    final n = expiry.setDays(days);
    setState(() => _saveError = false);
    if (n == null) {
      _toast(_deleteFailed);
    } else if (n > 0) {
      _toast(_deletedText(n));
    }
  }

  String _deletedText(int n) => '$n ${n == 1 ? 'item' : 'items'} deleted';

  Future<bool> _confirmShorter(int days) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _ExpiryDialog(service: _service, days: days),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final login = widget.loginItem;
    return ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor: t.surface,
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.all(KusungaTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeading(_general),
                  SizedBox(height: KusungaTokens.space2),
                  if (login != null) ...[
                    _loginSection(t, login),
                    SizedBox(height: KusungaTokens.space3),
                  ],
                  ?widget.pickerShortcut,
                  SizedBox(height: KusungaTokens.space5),
                  const SectionHeading(_history),
                  SizedBox(height: KusungaTokens.space2),
                  LimitField(
                    service: _service,
                    confirmLower: (n, _) =>
                        confirmLowerLimit(context, _service, n),
                    onSaveFailed: () =>
                        _toast("Couldn't save that number. Try again."),
                  ),
                  SizedBox(height: KusungaTokens.space3),
                  _autoDeleteSection(t),
                  SizedBox(height: KusungaTokens.space3),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _PrivacyLink(onPressed: widget.onShowPrivacy),
                  ),
                ],
              ),
            ),
            if (login != null)
              Positioned(
                left: 0,
                top: 0,
                child: _LoginAnnouncer(service: login),
              ),
          ],
        ),
      ),
    );
  }

  Widget _caption(KusungaTokens t, String text, {bool live = false}) => Padding(
    padding: EdgeInsets.only(top: KusungaTokens.space1),
    child: Semantics(
      liveRegion: live,
      child: Text(
        text,
        style: KusungaTokens.caption.copyWith(color: t.textMuted),
      ),
    ),
  );

  Widget _loginSection(KusungaTokens t, LoginItemService login) {
    final note = login.note;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  _loginLabel,
                  style: KusungaTokens.body.copyWith(color: t.text),
                ),
              ),
            ),
            MergeSemantics(
              child: Semantics(
                identifier: 'settings-launch-at-login',
                label: _loginLabel,
                hint: note,
                child: _FocusRing(
                  ringKey: const ValueKey('settings-launch-at-login-ring'),
                  node: _loginFocus,
                  radius: 24,
                  child: Switch(
                    focusNode: _loginFocus,
                    value: login.isOn,
                    hoverColor: t.surfaceHover,
                    focusColor: t.surfaceHover,
                    // Ignored while the OS call runs, and on macOS 12.
                    onChanged: login.enabled
                        ? (on) => unawaited(login.set(on))
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        ExcludeSemantics(
          child: _caption(t, isWindows ? _loginHelpWindows : _loginHelpMac),
        ),
        // Read with the switch, as its description; also announced when it
        // appears.
        if (note != null)
          Semantics(
            identifier: 'settings-login-note',
            liveRegion: true,
            excludeSemantics: true,
            label: note,
            child: _caption(t, note),
          ),
        if (login.showOpenLoginItems)
          Padding(
            padding: EdgeInsets.only(top: KusungaTokens.space2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                identifier: 'settings-open-login-items',
                child: OutlinedButton(
                  onPressed: () => unawaited(login.openLoginItems()),
                  child: const Text(_openLoginItems),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _autoDeleteSection(KusungaTokens t) {
    final days = _service.expiry.days;
    final label = ExcludeSemantics(
      child: Text(
        _autoDelete,
        style: KusungaTokens.body.copyWith(color: t.text),
      ),
    );
    Widget menu({required bool expand}) => MergeSemantics(
      child: Semantics(
        identifier: 'settings-auto-delete',
        label: _autoDeleteName,
        hint: _saveError ? _saveFailed : null,
        child: _FocusRing(
          ringKey: const ValueKey('settings-auto-delete-ring'),
          node: _menuFocus,
          radius: KusungaTokens.radius2,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: KusungaTokens.space3),
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(KusungaTokens.radius2),
            ),
            child: DropdownButton<int>(
              key: const Key('auto-delete-menu'),
              focusNode: _menuFocus,
              value: days,
              isExpanded: expand,
              underline: const SizedBox.shrink(),
              focusColor: t.surfaceHover,
              borderRadius: BorderRadius.circular(KusungaTokens.radius2),
              style: KusungaTokens.body.copyWith(color: t.text),
              dropdownColor: t.surface,
              items: [
                for (final d in historyExpiryChoices)
                  DropdownMenuItem(value: d, child: Text(expiryOption(d))),
              ],
              onChanged: (d) => unawaited(_choose(d)),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            // 320 px (360 px at 200% text): the menu takes the full width
            // under its label. Wider: they share a row when they fit.
            if (box.maxWidth < 400) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  SizedBox(height: KusungaTokens.space1),
                  menu(expand: true),
                ],
              );
            }
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: KusungaTokens.space3,
              runSpacing: KusungaTokens.space1,
              children: [label, menu(expand: false)],
            );
          },
        ),
        if (_saveError) _caption(t, _saveFailed, live: true),
        ExcludeSemantics(child: _caption(t, _autoDeleteHelp)),
      ],
    );
  }
}

/// "Delete items after 1 day? 143 older items will be deleted. Snippets
/// aren't affected." Built like the Keep dialog: the focus starts on
/// Cancel, the count follows live changes, and while it cannot be read only
/// Cancel works. At a count of 0 (items went meanwhile) it closes by
/// itself, as Cancel would, like the Clear history dialog (PM decision
/// 2026-11-08, [CloseAtZero]): then nothing is deleted and the user can
/// choose again.
class _ExpiryDialog extends StatelessWidget {
  const _ExpiryDialog({required this.service, required this.days});

  final HistoryService service;
  final int days;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return CloseAtZero(
      listenable: Listenable.merge([service, service.expiry]),
      count: () => service.expiry.countRemovedBy(days),
      builder: (context, count) => AlertDialog(
        content: Text(
          count == null
              ? _countFailed
              : 'Delete items after ${_expiryLength(days)}? $count older '
                    "${count == 1 ? 'item' : 'items'} will be deleted. "
                    "Snippets aren't affected.",
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: t.danger,
              foregroundColor: t.surface,
            ),
            onPressed: count == null
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Keyboard focus on a switch or a menu: the 2 px `focus` ring of the
/// buttons, rows and tabs, drawn outside [child] so it sits on the
/// background (3:1 there, reviewer F1). Material's own focus tint on these
/// controls is about 1.1:1. Shown, like the buttons' ring, only for keyboard
/// focus.
class _FocusRing extends StatefulWidget {
  const _FocusRing({
    required this.ringKey,
    required this.node,
    required this.radius,
    required this.child,
  });

  /// On the box that draws the ring (a test hook).
  final Key ringKey;
  final FocusNode node;
  final double radius;
  final Widget child;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  @override
  void initState() {
    super.initState();
    widget.node.addListener(_changed);
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void didUpdateWidget(_FocusRing old) {
    super.didUpdateWidget(old);
    if (old.node != widget.node) {
      old.node.removeListener(_changed);
      widget.node.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.node.removeListener(_changed);
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _modeChanged(FocusHighlightMode _) => _changed();

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final show =
        widget.node.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return DecoratedBox(
      key: widget.ringKey,
      decoration: BoxDecoration(
        border: Border.all(
          color: show ? t.focus : Colors.transparent,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: widget.child,
    );
  }
}

/// "Ignored apps and pause are in Privacy": a text button, underlined on
/// hover.
class _PrivacyLink extends StatelessWidget {
  const _PrivacyLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Semantics(
      identifier: 'settings-privacy-link',
      link: true,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(t.text),
          overlayColor: WidgetStatePropertyAll(t.surfaceHover),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => KusungaTokens.body.copyWith(
              decoration: states.contains(WidgetState.hovered)
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
        ),
        child: const Text(_privacyLink),
      ),
    );
  }
}

/// Announces "Launch at login on" or "off" after the user's own change, as
/// a polite live region, and on the Mac also directly (like the pause).
class _LoginAnnouncer extends StatefulWidget {
  const _LoginAnnouncer({required this.service});

  final LoginItemService service;

  @override
  State<_LoginAnnouncer> createState() => _LoginAnnouncerState();
}

class _LoginAnnouncerState extends State<_LoginAnnouncer> {
  late int _serial = widget.service.announceSerial;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
  }

  @override
  void didUpdateWidget(_LoginAnnouncer old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service.removeListener(_changed);
      widget.service.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final s = widget.service;
    if (s.announceSerial == _serial) return;
    _serial = s.announceSerial;
    final message = s.announcement;
    if (message == null) return;
    setState(() => _message = message);
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();
    // 1 x 1 so screen readers keep the node; nothing visible.
    return Semantics(
      key: ValueKey(message),
      liveRegion: true,
      label: message,
      child: const SizedBox(width: 1, height: 1),
    );
  }
}
