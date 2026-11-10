import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../history/pause_service.dart';
import '../../theme/tokens.dart';

// Copy from the UI spec (`docs/ui/sensitive-content.md`, "Copy").
const _pauseHeading = 'Pause history';
const _pauseText = 'Stop adding copies to history for a while.';
const _resume = 'Resume';
const _wontLast = "Pause won't last after Kusunga quits.";
const _applyFailed = "Couldn't apply the pause. Try again.";
const _resumeFailed = "Couldn't resume. Try again.";
const _ignoredHeading = 'Ignored apps';
const _ignoredText =
    "Copies from these apps aren't kept, and typed shortcuts don't work in "
    'them.';
const _ignoredFooter = 'Kusunga also skips anything an app marks as private.';

/// The three pause buttons: (identifier, label, accessible name, length).
const _pauseButtons = [
  (
    'pause-15',
    'For 15 minutes',
    'Pause history for 15 minutes',
    PauseLength.quarterHour,
  ),
  ('pause-60', 'For 1 hour', 'Pause history for 1 hour', PauseLength.hour),
  (
    'pause-until',
    'Until I resume',
    'Pause history until I resume',
    PauseLength.untilResumed,
  ),
];

/// "14:30" in the system's 12/24-hour format, "tomorrow 00:10" when the end
/// is not today; null when paused until resumed.
String? pauseEndText(BuildContext context, PauseService pause) {
  final end = pause.endsAt;
  if (end == null) return null;
  return formatPauseEnd(
    end,
    pause.now,
    use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// The Privacy tab (M1.6, decision D4 A): Pause history, and the ignored
/// apps list ([ignoredApps], from typed shortcuts) under its heading.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.pause,
    required this.ignoredHeadingFocus,
    this.ignoredApps,
  });

  final PauseService pause;

  /// "Edit ignored apps" moves the focus here (UI spec, states matrix).
  final FocusNode ignoredHeadingFocus;

  /// The list editor. Without it there is no Ignored apps section.
  final Widget? ignoredApps;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  final _resumeNode = FocusNode(debugLabel: 'Resume history');
  final _firstPauseNode = FocusNode(debugLabel: 'For 15 minutes');

  PauseService get _pause => widget.pause;

  @override
  void initState() {
    super.initState();
    _pause.addListener(_changed);
  }

  @override
  void didUpdateWidget(PrivacyScreen old) {
    super.didUpdateWidget(old);
    if (old.pause != widget.pause) {
      old.pause.removeListener(_changed);
      widget.pause.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _pause.removeListener(_changed);
    _resumeNode.dispose();
    _firstPauseNode.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _focusAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
  }

  Future<void> _pauseFor(PauseLength length) async {
    if (await _pause.pause(length)) _focusAfterFrame(_resumeNode);
  }

  Future<void> _resumeNow() async {
    if (await _pause.resume()) _focusAfterFrame(_firstPauseNode);
  }

  Widget _note(KusungaTokens t, String text, String id) => Padding(
    padding: EdgeInsets.only(top: KusungaTokens.space2),
    child: Semantics(
      identifier: id,
      liveRegion: true,
      child: Text(
        text,
        style: KusungaTokens.caption.copyWith(color: t.textMuted),
      ),
    ),
  );

  Widget _heading(KusungaTokens t, String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: KusungaTokens.body.copyWith(
        color: t.text,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _pauseSection(KusungaTokens t) {
    final paused = _pause.isPaused;
    final error = _pause.error;
    final children = <Widget>[
      _heading(t, _pauseHeading),
      SizedBox(height: KusungaTokens.space1),
    ];
    if (paused) {
      final end = pauseEndText(context, _pause);
      children.add(
        Wrap(
          spacing: KusungaTokens.space3,
          runSpacing: KusungaTokens.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.circle, size: 10, color: t.text),
                ),
                SizedBox(width: KusungaTokens.space2),
                Flexible(
                  child: Text(
                    end == null
                        ? 'Paused until you resume.'
                        : 'Paused until $end.',
                    style: KusungaTokens.body.copyWith(color: t.text),
                  ),
                ),
              ],
            ),
            Semantics(
              identifier: 'pause-resume',
              label: 'Resume history',
              button: true,
              excludeSemantics: true,
              onTap: _resumeNow,
              child: OutlinedButton(
                focusNode: _resumeNode,
                onPressed: _resumeNow,
                child: const Text(_resume),
              ),
            ),
          ],
        ),
      );
    } else {
      children.addAll([
        Text(_pauseText, style: KusungaTokens.body.copyWith(color: t.text)),
        SizedBox(height: KusungaTokens.space2),
        Wrap(
          spacing: KusungaTokens.space2,
          runSpacing: KusungaTokens.space2,
          children: [
            for (final (id, label, name, length) in _pauseButtons)
              Semantics(
                identifier: id,
                label: name,
                button: true,
                excludeSemantics: true,
                onTap: () => _pauseFor(length),
                child: OutlinedButton(
                  focusNode: length == PauseLength.quarterHour
                      ? _firstPauseNode
                      : null,
                  onPressed: () => _pauseFor(length),
                  child: Text(label),
                ),
              ),
          ],
        ),
      ]);
    }
    // Also while paused (N1): after a launch send that failed, or a
    // settings read error, native code may not be paused although this
    // says it is. The note then sits under the paused line and Resume.
    if (error == PauseError.apply) {
      children.add(_note(t, _applyFailed, 'pause-error'));
    }
    if (error == PauseError.resume && paused) {
      children.add(_note(t, _resumeFailed, 'pause-error'));
    }
    if (!_pause.willLast) children.add(_note(t, _wontLast, 'pause-wont-last'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _ignoredSection(KusungaTokens t, Widget list) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Takes the focus only when "Edit ignored apps" sends it here; Tab
      // goes from the pause buttons straight to the list.
      Focus(
        focusNode: widget.ignoredHeadingFocus,
        skipTraversal: true,
        child: Semantics(
          identifier: 'privacy-ignored-apps-heading',
          child: _heading(t, _ignoredHeading),
        ),
      ),
      SizedBox(height: KusungaTokens.space1),
      Text(_ignoredText, style: KusungaTokens.body.copyWith(color: t.text)),
      SizedBox(height: KusungaTokens.space2),
      list,
      SizedBox(height: KusungaTokens.space2),
      Text(
        _ignoredFooter,
        style: KusungaTokens.caption.copyWith(color: t.textMuted),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final list = widget.ignoredApps;
    return Material(
      color: t.surface,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(KusungaTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pauseSection(t),
            if (list != null) ...[
              SizedBox(height: KusungaTokens.space5),
              _ignoredSection(t, list),
            ],
          ],
        ),
      ),
    );
  }
}

/// Announces pausing and resuming once each (UI spec, "Announcements"),
/// wherever they came from: the Privacy tab, the banner, the tray, or a
/// timed pause ending while Kusunga is open. A polite live region, and on
/// the Mac also a direct announcement.
class PauseAnnouncer extends StatefulWidget {
  const PauseAnnouncer({super.key, required this.pause});

  final PauseService pause;

  @override
  State<PauseAnnouncer> createState() => _PauseAnnouncerState();
}

class _PauseAnnouncerState extends State<PauseAnnouncer> {
  late int _serial;
  String? _message;

  @override
  void initState() {
    super.initState();
    _serial = widget.pause.announceSerial;
    widget.pause.addListener(_changed);
  }

  @override
  void didUpdateWidget(PauseAnnouncer old) {
    super.didUpdateWidget(old);
    if (old.pause != widget.pause) {
      old.pause.removeListener(_changed);
      widget.pause.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.pause.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final pause = widget.pause;
    // Only a user pause or resume, or a timed end (O6).
    if (pause.announceSerial == _serial) return;
    _serial = pause.announceSerial;
    String message;
    if (!pause.isPaused) {
      message = 'History resumed';
    } else {
      final end = pauseEndText(context, pause);
      message = end == null ? 'History paused' : 'History paused until $end';
    }
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
