import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';

import '../../theme/tokens.dart';
import '../picker_controller.dart';

/// The small "Copied — press ⌘V to paste" message shown near the pointer after
/// a paste that could not press the keys. The window shows it without taking
/// focus, so the user's app keeps it. Screen readers hear it at once.
class PickerToastView extends StatefulWidget {
  const PickerToastView({super.key, required this.controller});

  final PickerController controller;

  @override
  State<PickerToastView> createState() => _PickerToastViewState();
}

class _PickerToastViewState extends State<PickerToastView> {
  late final String _text = widget.controller.toastText ?? '';

  @override
  void initState() {
    super.initState();
    // The toast is a live region too; this assertive announcement is what
    // makes it reach VoiceOver and Narrator while another app has focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _text.isEmpty) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        _text,
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Center(
      child: Semantics(
        key: const ValueKey('picker-toast'),
        identifier: 'picker-toast',
        container: true,
        liveRegion: true,
        label: _text,
        child: ExcludeSemantics(
          child: Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KusungaTokens.radius2 + 4),
              side: BorderSide(color: t.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(KusungaTokens.space3),
              child: Text(
                _text,
                style: KusungaTokens.body.copyWith(color: t.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
