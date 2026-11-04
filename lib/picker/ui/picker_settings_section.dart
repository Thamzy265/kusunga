import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../picker_controller.dart';
import '../shortcut.dart';

/// What the main window adds for the picker: the shortcut setting, the banner
/// when the shortcut is taken, and (Mac) the card that asks for permission to
/// paste. Spec: `docs/ui/history-picker.md`.
class PickerSettingsSection extends StatefulWidget {
  const PickerSettingsSection({super.key, required this.controller});

  final PickerController controller;

  @override
  State<PickerSettingsSection> createState() => _PickerSettingsSectionState();
}

class _PickerSettingsSectionState extends State<PickerSettingsSection>
    with WidgetsBindingObserver {
  var _recording = false;
  Timer? _giveUp;
  String? _message;
  var _messageIsError = false;

  PickerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _giveUp?.cancel();
    // Leaving the screen mid-recording must not leave the shortcut released.
    if (_recording) unawaited(_c.endRecording());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission may have been given in System Settings meanwhile.
    if (state == AppLifecycleState.resumed) unawaited(_c.recheckPostAccess());
    // The window lost focus: whoever is pressing keys is not talking to us.
    if (_recording && state != AppLifecycleState.resumed) _cancelRecording();
  }

  Future<void> _startRecording() async {
    await _c.beginRecording();
    if (!mounted) return;
    setState(() {
      _recording = true;
      _message = null;
    });
    // If no key ever arrives the shortcut must not stay released.
    _giveUp?.cancel();
    _giveUp = Timer(const Duration(seconds: 20), _cancelRecording);
  }

  void _cancelRecording() {
    _giveUp?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    unawaited(_c.endRecording());
  }

  KeyEventResult _onRecordKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelRecording();
      return KeyEventResult.handled;
    }
    final hw = HardwareKeyboard.instance;
    final shortcut = PickerShortcut.fromKey(
      physical: event.physicalKey,
      logical: event.logicalKey,
      modifiers: {
        if (hw.isControlPressed) ShortcutModifier.ctrl,
        if (hw.isAltPressed) ShortcutModifier.alt,
        if (hw.isShiftPressed) ShortcutModifier.shift,
        if (hw.isMetaPressed) ShortcutModifier.meta,
      },
      isMac: _c.isMac,
    );
    if (shortcut != null) unawaited(_apply(shortcut));
    return KeyEventResult.handled;
  }

  Future<void> _apply(PickerShortcut shortcut) async {
    final result = await _c.changeShortcut(shortcut);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case ShortcutChange.saved:
          _recording = false;
          _message = 'Shortcut saved';
          _messageIsError = false;
        case ShortcutChange.taken:
          _recording = false;
          _message = 'That shortcut is used by another app. Choose another.';
          _messageIsError = true;
        case ShortcutChange.needModifier:
          _message = PickerShortcut.needModifierMessage(isMac: _c.isMac);
          _messageIsError = true;
        case ShortcutChange.reserved:
          _message = PickerShortcut.reservedMessage;
          _messageIsError = true;
        case ShortcutChange.notSaved:
          _recording = false;
          _message = "Couldn't save the shortcut. Try again.";
          _messageIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final t = KusungaTokens.of(context);
        final banner = _c.shortcutBannerText;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (banner != null) _Banner(text: banner),
            if (_c.isMac && _c.permissionCardVisible)
              _PermissionCard(controller: _c),
            Padding(
              padding: EdgeInsets.only(bottom: KusungaTokens.space2),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: KusungaTokens.space3,
                runSpacing: KusungaTokens.space2,
                children: [
                  Text(
                    'Picker shortcut: ${_c.shortcut.display(isMac: _c.isMac)}',
                    style: KusungaTokens.body.copyWith(color: t.text),
                  ),
                  if (_recording)
                    _Recorder(onKey: _onRecordKey, onLost: _cancelRecording)
                  else
                    Semantics(
                      identifier: 'shortcut-change',
                      child: OutlinedButton(
                        onPressed: _startRecording,
                        child: const Text(
                          'Change',
                          semanticsLabel: 'Change picker shortcut',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_message == null && _c.shortcutSaveFailed)
              Padding(
                padding: EdgeInsets.only(bottom: KusungaTokens.space2),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    "Couldn't save the shortcut. Try again.",
                    style: KusungaTokens.body.copyWith(color: t.danger),
                  ),
                ),
              ),
            if (_message != null)
              Padding(
                padding: EdgeInsets.only(bottom: KusungaTokens.space2),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: KusungaTokens.body.copyWith(
                      color: _messageIsError ? t.danger : t.text,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Listens for the next key combination. It takes every key (so Tab and the
/// like are not used for anything else meanwhile) and gives up when it loses
/// focus.
class _Recorder extends StatefulWidget {
  const _Recorder({required this.onKey, required this.onLost});

  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback onLost;

  @override
  State<_Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<_Recorder> {
  final _node = FocusNode(debugLabel: 'shortcut recorder');

  @override
  void initState() {
    super.initState();
    // Take the focus explicitly: the Change button had it a moment ago.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: widget.onKey,
      onFocusChange: (has) {
        if (!has) widget.onLost();
      },
      child: Semantics(
        identifier: 'shortcut-recording',
        liveRegion: true,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: KusungaTokens.space3,
            vertical: KusungaTokens.space2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: t.focus, width: 2),
            borderRadius: BorderRadius.circular(KusungaTokens.radius2),
          ),
          child: Text(
            'Press the new shortcut…',
            style: KusungaTokens.body.copyWith(color: t.text),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: KusungaTokens.space2),
      child: Container(
        padding: EdgeInsets.all(KusungaTokens.space3),
        decoration: BoxDecoration(
          color: t.bannerWarnBg,
          borderRadius: BorderRadius.circular(KusungaTokens.radius2),
        ),
        child: Semantics(
          liveRegion: true,
          child: Text(
            text,
            style: KusungaTokens.body.copyWith(color: t.bannerWarnText),
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.controller});

  final PickerController controller;

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
                  'Let Kusunga paste for you',
                  style: KusungaTokens.title.copyWith(color: t.text),
                ),
              ),
            ),
            SizedBox(height: KusungaTokens.space2),
            Text(
              "To paste into other apps, Kusunga needs permission to send the ⌘V keystroke. It never reads what's on your screen.",
              style: KusungaTokens.body.copyWith(color: t.text),
            ),
            if (controller.permissionHelpVisible) ...[
              SizedBox(height: KusungaTokens.space2),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Turn on Kusunga in System Settings > Privacy & Security > Accessibility.',
                  style: KusungaTokens.body.copyWith(color: t.text),
                ),
              ),
            ],
            SizedBox(height: KusungaTokens.space3),
            // Both buttons look and weigh the same: "Not now" is as easy as
            // "Allow pasting" (no deceptive patterns).
            Wrap(
              spacing: KusungaTokens.space2,
              runSpacing: KusungaTokens.space2,
              children: [
                Semantics(
                  identifier: 'permission-allow',
                  child: OutlinedButton(
                    onPressed: () => unawaited(controller.allowPasting()),
                    child: const Text('Allow pasting'),
                  ),
                ),
                Semantics(
                  identifier: 'permission-not-now',
                  child: OutlinedButton(
                    onPressed: controller.dismissPermissionCard,
                    child: const Text('Not now'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
