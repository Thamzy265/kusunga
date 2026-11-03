import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../history_service.dart';
import '../history_store.dart';

/// "Keep [N] items": the history limit, 10 to 5,000. Saved on Enter or when
/// the field loses focus. Lowering it below the current count asks first.
class LimitField extends StatefulWidget {
  const LimitField({
    super.key,
    required this.service,
    required this.confirmLower,
  });

  final HistoryService service;

  /// Asks the user to confirm deleting [removed] older items. True to go on.
  final Future<bool> Function(int newLimit, int removed) confirmLower;

  @override
  State<LimitField> createState() => _LimitFieldState();
}

class _LimitFieldState extends State<LimitField> {
  static const _errorText = 'Enter a number from 10 to 5,000.';
  late final _controller = TextEditingController(
    text: '${widget.service.limit}',
  );
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  String? _error;
  var _committing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!up && !down) return KeyEventResult.ignored;
    final current =
        int.tryParse(_controller.text.replaceAll(',', '').trim()) ??
        widget.service.limit;
    final next = (current + (up ? 10 : -10)).clamp(
      HistoryStore.minLimit,
      HistoryStore.maxLimit,
    );
    _controller.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
    setState(() => _error = null);
    return KeyEventResult.handled;
  }

  Future<void> _commit() async {
    if (_committing) return;
    final n = int.tryParse(_controller.text.replaceAll(',', '').trim());
    if (n == null || n < HistoryStore.minLimit || n > HistoryStore.maxLimit) {
      setState(() => _error = _errorText);
      return;
    }
    setState(() => _error = null);
    if (n == widget.service.limit) return;
    _committing = true;
    try {
      final removed = widget.service.countRemovedBy(n);
      if (removed > 0 && !await widget.confirmLower(n, removed)) {
        if (mounted) _controller.text = '${widget.service.limit}';
        return;
      }
      widget.service.setLimit(n);
    } finally {
      _committing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final label = KusungaTokens.body.copyWith(color: t.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: KusungaTokens.space2,
          children: [
            ExcludeSemantics(child: Text('Keep', style: label)),
            SizedBox(
              width: 104,
              child: Semantics(
                label: 'Number of history items to keep',
                hint: _error,
                textField: true,
                child: TextField(
                  key: const Key('limit-field'),
                  controller: _controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.end,
                  style: label,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                  ],
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _commit(),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: KusungaTokens.space3,
                      vertical: KusungaTokens.space2,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        KusungaTokens.radius2,
                      ),
                      borderSide: BorderSide(
                        color: _error == null ? t.border : t.danger,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        KusungaTokens.radius2,
                      ),
                      borderSide: BorderSide(
                        color: _error == null ? t.focus : t.danger,
                        width: 2,
                      ),
                    ),
                    hoverColor: t.surfaceHover,
                  ),
                ),
              ),
            ),
            ExcludeSemantics(child: Text('items', style: label)),
          ],
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: KusungaTokens.space1),
            child: Text(
              _error!,
              style: KusungaTokens.caption.copyWith(color: t.danger),
            ),
          ),
      ],
    );
  }
}
