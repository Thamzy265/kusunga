import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../snippet.dart';
import '../snippet_service.dart';

/// How the editor opens: empty ("New snippet"), with a snippet ("Edit
/// snippet"), or filled in from a history item ("Save as snippet").
class SnippetEditorStart {
  const SnippetEditorStart.create() : editing = null, historyText = null;
  const SnippetEditorStart.edit(SnippetItem this.editing) : historyText = null;
  const SnippetEditorStart.fromHistory(String this.historyText)
    : editing = null;

  final SnippetItem? editing;
  final String? historyText;
}

/// Copy from the UI spec (`docs/ui/saved-snippets.md`, "Copy").
const snippetCapMessage =
    'You have 1,000 snippets, the most Kusunga keeps. Delete one to add '
    'another.';
const _saveFailedMessage = "Couldn't save the snippet. Try again.";
const _vaultNote =
    'For bank or card details, wait for the secure vault in a later update.';

String _problemText(SnippetProblem p) => switch (p) {
  SnippetProblem.emptyName => 'Enter a name.',
  SnippetProblem.longName => 'Names can be up to 100 characters.',
  SnippetProblem.emptyContent => 'Enter the text to paste.',
  SnippetProblem.longContent => "That's too long. Snippets can be up to 1 MB.",
};

/// Opens the editor over the window: a 480 px sheet, or the full window under
/// 600 px. Returns the id of the saved snippet, or null if it was cancelled.
Future<int?> showSnippetEditor(
  BuildContext context, {
  required SnippetService service,
  required SnippetEditorStart start,
}) => showDialog<int>(
  context: context,
  // A click beside the sheet must not lose what was typed.
  barrierDismissible: false,
  builder: (context) => _SnippetEditor(service: service, start: start),
);

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({required this.service, required this.start});

  final SnippetService service;
  final SnippetEditorStart start;

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  final _nameNode = FocusNode(debugLabel: 'snippet name');
  final _contentNode = FocusNode(debugLabel: 'snippet content');
  late SnippetType _type;
  late bool _typeSuggested;
  late final String _initialName;
  late final String _initialContent;
  late final SnippetType _initialType;
  Set<SnippetProblem> _problems = const {};
  String? _banner;
  var _closing = false;

  SnippetItem? get _editing => widget.start.editing;
  bool get _fromHistory => widget.start.historyText != null;
  String get _title => _editing == null ? 'New snippet' : 'Edit snippet';

  @override
  void initState() {
    super.initState();
    final editing = _editing;
    final history = widget.start.historyText;
    final String name;
    final String content;
    if (editing != null) {
      name = editing.name;
      content = widget.service.textOf(editing.id) ?? editing.preview;
      _type = editing.type;
      _typeSuggested = false;
    } else if (history != null) {
      name = pinName(history);
      content = history;
      _type = suggestType(history);
      _typeSuggested = true;
    } else {
      name = '';
      content = '';
      _type = SnippetType.other;
      _typeSuggested = true;
    }
    _initialName = name;
    _initialContent = content;
    _initialType = _type;
    _name = TextEditingController(text: name);
    _content = TextEditingController(text: content)..addListener(_suggest);
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _nameNode.dispose();
    _contentNode.dispose();
    super.dispose();
  }

  void _suggest() {
    if (!_typeSuggested) return;
    final next = suggestType(_content.text);
    if (next != _type) setState(() => _type = next);
  }

  bool get _changed =>
      _name.text != _initialName ||
      _content.text != _initialContent ||
      _type != _initialType;

  void _save() {
    final r = widget.service.save(
      id: _editing?.id,
      name: _name.text,
      content: _content.text,
      type: _type,
    );
    switch (r.outcome) {
      case SnippetSave.saved:
        _closing = true;
        Navigator.of(context).pop(r.id);
      case SnippetSave.invalid:
        setState(() {
          _problems = r.problems;
          _banner = null;
        });
        final nameBad =
            r.problems.contains(SnippetProblem.emptyName) ||
            r.problems.contains(SnippetProblem.longName);
        (nameBad ? _nameNode : _contentNode).requestFocus();
      case SnippetSave.capReached:
        setState(() {
          _problems = const {};
          _banner = snippetCapMessage;
        });
      case SnippetSave.failed:
      case SnippetSave.unavailable:
        setState(() {
          _problems = const {};
          _banner = _saveFailedMessage;
        });
    }
  }

  Future<void> _cancel() async {
    if (!_changed) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text("Your changes to this snippet won't be saved."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _closing = true;
      Navigator.of(context).pop();
    }
  }

  String? _errorFor(Set<SnippetProblem> which) {
    for (final p in _problems) {
      if (which.contains(p)) return _problemText(p);
    }
    return null;
  }

  InputDecoration _decoration(KusungaTokens t, String label, String? error) =>
      InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorText: error,
        errorMaxLines: 3,
        // 1 px border, darker on hover, a 2 px focus ring (UI spec).
        border: WidgetStateInputBorder.resolveWith((states) {
          final focused = states.contains(WidgetState.focused);
          final color = states.contains(WidgetState.error)
              ? t.danger
              : focused
              ? t.focus
              : states.contains(WidgetState.hovered)
              ? t.borderHover
              : t.border;
          return OutlineInputBorder(
            borderRadius: BorderRadius.circular(KusungaTokens.radius2),
            borderSide: BorderSide(color: color, width: focused ? 2 : 1),
          );
        }),
        hoverColor: Colors.transparent,
      );

  Widget _form(KusungaTokens t) {
    final gap = SizedBox(height: KusungaTokens.space4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            _title,
            style: KusungaTokens.title.copyWith(color: t.text),
          ),
        ),
        gap,
        if (_banner != null) ...[
          Container(
            padding: EdgeInsets.all(KusungaTokens.space3),
            decoration: BoxDecoration(
              color: t.bannerWarnBg,
              borderRadius: BorderRadius.circular(KusungaTokens.radius2),
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _banner!,
                style: KusungaTokens.body.copyWith(color: t.bannerWarnText),
              ),
            ),
          ),
          gap,
        ],
        Semantics(
          identifier: 'snippet-editor-name',
          child: TextField(
            controller: _name,
            focusNode: _nameNode,
            autofocus: !_fromHistory,
            maxLines: 1,
            // A name is one line: a single-line field removes line breaks
            // (and the name is made one line again when it is saved).
            style: KusungaTokens.body.copyWith(color: t.text),
            decoration: _decoration(
              t,
              'Name',
              _errorFor(const {
                SnippetProblem.emptyName,
                SnippetProblem.longName,
              }),
            ),
          ),
        ),
        gap,
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: KusungaTokens.space2,
          runSpacing: KusungaTokens.space1,
          children: [
            _TypeField(
              value: _type,
              decoration: _decoration(t, 'Type', null),
              onChanged: (type) => setState(() {
                _type = type;
                _typeSuggested = false;
              }),
            ),
            if (_typeSuggested)
              Text(
                '(suggested)',
                style: KusungaTokens.caption.copyWith(color: t.textMuted),
              ),
          ],
        ),
        gap,
        Semantics(
          identifier: 'snippet-editor-content',
          child: TextField(
            controller: _content,
            focusNode: _contentNode,
            autofocus: _fromHistory,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            style: KusungaTokens.body.copyWith(color: t.text),
            decoration: _decoration(
              t,
              'Content',
              _errorFor(const {
                SnippetProblem.emptyContent,
                SnippetProblem.longContent,
              }),
            ),
          ),
        ),
        SizedBox(height: KusungaTokens.space3),
        Text(
          _vaultNote,
          style: KusungaTokens.caption.copyWith(color: t.textMuted),
        ),
      ],
    );
  }

  Widget _buttons() => Wrap(
    alignment: WrapAlignment.end,
    spacing: KusungaTokens.space2,
    runSpacing: KusungaTokens.space2,
    children: [
      Semantics(
        identifier: 'snippet-editor-cancel',
        child: TextButton(onPressed: _cancel, child: const Text('Cancel')),
      ),
      Semantics(
        identifier: 'snippet-editor-save',
        // Never disabled: it checks and explains instead (UI spec).
        child: FilledButton(onPressed: _save, child: const Text('Save')),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final full = MediaQuery.sizeOf(context).width < 600;
    final pad = EdgeInsets.all(KusungaTokens.space5);
    final body = Column(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(padding: pad, child: _form(t)),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: KusungaTokens.space5,
            right: KusungaTokens.space5,
            bottom: KusungaTokens.space5,
          ),
          child: _buttons(),
        ),
      ],
    );
    final editor = PopScope<int>(
      // Esc (and any other way back) asks first if something changed.
      canPop: _closing || !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: CallbackShortcuts(
        bindings: {
          // The sheet is not dismissed by the barrier, so Esc is handled here:
          // it closes at once, or asks first if something changed.
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
              _save,
          const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
              _save,
        },
        child: Semantics(
          identifier: 'snippet-editor',
          label: _title,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          child: body,
        ),
      ),
    );
    if (full) {
      return Dialog.fullscreen(backgroundColor: t.surface, child: editor);
    }
    return Dialog(
      backgroundColor: t.surface,
      child: SizedBox(
        key: const ValueKey('snippet-editor-sheet'),
        width: 480,
        child: editor,
      ),
    );
  }
}

/// The type: a button that opens a menu of the five types. Up and Down
/// change the value while it has focus (UI spec, "Type field").
class _TypeField extends StatefulWidget {
  const _TypeField({
    required this.value,
    required this.decoration,
    required this.onChanged,
  });

  final SnippetType value;
  final InputDecoration decoration;
  final ValueChanged<SnippetType> onChanged;

  @override
  State<_TypeField> createState() => _TypeFieldState();
}

class _TypeFieldState extends State<_TypeField> {
  final _node = FocusNode(debugLabel: 'snippet type');
  var _focused = false;
  var _hovered = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _step(int by) {
    const all = SnippetType.values;
    final i = (all.indexOf(widget.value) + by).clamp(0, all.length - 1);
    if (all[i] != widget.value) widget.onChanged(all[i]);
  }

  Future<void> _open() async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
    final picked = await showMenu<SnippetType>(
      context: context,
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        overlay.size.width - at.dx - box.size.width,
        0,
      ),
      initialValue: widget.value,
      items: [
        for (final type in SnippetType.values)
          PopupMenuItem(value: type, child: Text(type.label)),
      ],
    );
    if (picked != null && picked != widget.value) widget.onChanged(picked);
    _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Semantics(
      identifier: 'snippet-editor-type',
      button: true,
      label: 'Type',
      value: widget.value.label,
      onTap: _open,
      excludeSemantics: true,
      child: Focus(
        focusNode: _node,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown) {
            _step(1);
          } else if (key == LogicalKeyboardKey.arrowUp) {
            _step(-1);
          } else if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            _open();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _open,
            child: SizedBox(
              width: 180,
              child: InputDecorator(
                isFocused: _focused,
                isHovering: _hovered,
                decoration: widget.decoration,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.value.label,
                        overflow: TextOverflow.ellipsis,
                        style: KusungaTokens.body.copyWith(color: t.text),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Icon(Icons.arrow_drop_down, color: t.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
