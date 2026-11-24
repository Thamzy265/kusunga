import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../snippet.dart';
import '../snippet_service.dart';
import '../snippet_shortcut.dart';

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
const snippetOpenFailedMessage = "Couldn't open the snippet. Try again.";
const _vaultNote =
    'For bank or card details, wait for the secure vault in a later update.';

String _problemText(SnippetProblem p) => switch (p) {
  SnippetProblem.emptyName => 'Enter a name.',
  SnippetProblem.longName => 'Names can be up to 100 characters.',
  SnippetProblem.emptyContent => 'Enter the text to paste.',
  SnippetProblem.longContent => "That's too long. Snippets can be up to 1 MB.",
  SnippetProblem.shortcutLength => _shortcutLengthText,
  SnippetProblem.shortcutSpaces => _shortcutSpacesText,
};

// Typed shortcuts (M1.5 UI spec, "Copy", "Editor Shortcut field").
const _shortcutLabel = 'Shortcut (optional)';
const _shortcutHint = 'Type this in any app to paste.';
const _shortcutPlaceholder = ';email';
const _shortcutTip =
    "Tip: start with a symbol like ; so normal typing doesn't trigger it.";
const _shortcutLengthText = 'Use 2 to 32 characters.';
const _shortcutSpacesText = "Shortcuts can't have spaces or line breaks.";

/// The message for a clash of [mine] with another snippet's shortcut.
String shortcutClashText(ShortcutClash c, String mine) {
  final other = c.otherShortcut;
  final name = '“${c.otherName}”';
  return switch (c.kind) {
    ShortcutClashKind.same =>
      '$name already uses $other. Choose another shortcut.',
    ShortcutClashKind.otherIsStart =>
      "$name uses $other, so $mine would never fire. Choose one that doesn't "
          'start with $other.',
    ShortcutClashKind.newIsStart =>
      '$name uses $other, which starts with $mine, so $other would stop '
          'firing. Choose a longer or different shortcut.',
  };
}

String _issueText(ShortcutIssue issue, String mine) => switch (issue.problem) {
  ShortcutProblem.length => _shortcutLengthText,
  ShortcutProblem.spaces => _shortcutSpacesText,
  null => shortcutClashText(issue.clash!, mine),
};

final _allLetters = RegExp(r'^\p{L}+$', unicode: true);

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
  late final TextEditingController _shortcut;
  final _nameNode = FocusNode(debugLabel: 'snippet name');
  final _shortcutNode = FocusNode(debugLabel: 'snippet shortcut');
  final _contentNode = FocusNode(debugLabel: 'snippet content');
  late SnippetType _type;
  late bool _typeSuggested;
  late final String _initialName;
  late final String _initialContent;
  late final SnippetType _initialType;
  late final String _initialShortcut;
  Set<SnippetProblem> _problems = const {};

  /// The message under the Shortcut field: from the live check (500 ms after
  /// typing stops) or from Save.
  String? _shortcutError;
  Timer? _shortcutCheck;
  String? _banner;
  var _closing = false;

  /// Edit could not read the whole text: the content is shown read-only (its
  /// preview) and Save reads the whole text again before it saves, so a long
  /// snippet is never overwritten by its preview (TB-2).
  var _contentUnread = false;

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
      final full = widget.service.fullTextForEdit(editing.id);
      _contentUnread = full == null;
      if (_contentUnread) _banner = snippetOpenFailedMessage;
      content = full ?? editing.preview;
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
    _initialShortcut = editing?.shortcut ?? '';
    _name = TextEditingController(text: name);
    _content = TextEditingController(text: content)..addListener(_suggest);
    _shortcut = TextEditingController(text: _initialShortcut);
  }

  @override
  void dispose() {
    _shortcutCheck?.cancel();
    _name.dispose();
    _content.dispose();
    _shortcut.dispose();
    _nameNode.dispose();
    _shortcutNode.dispose();
    _contentNode.dispose();
    super.dispose();
  }

  void _shortcutChanged(String _) {
    // Rebuilds the hint (the tip depends on the text) and checks again
    // 500 ms after typing stops (UI spec).
    setState(() {});
    _shortcutCheck?.cancel();
    _shortcutCheck = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _shortcutError = _liveShortcutIssue());
    });
  }

  void _suggest() {
    if (!_typeSuggested) return;
    final next = suggestType(_content.text);
    if (next != _type) setState(() => _type = next);
  }

  bool get _changed =>
      _name.text != _initialName ||
      _content.text != _initialContent ||
      _type != _initialType ||
      _shortcut.text != _initialShortcut;

  void _save() {
    if (_closing) return;
    var content = _content.text;
    if (_contentUnread) {
      final full = widget.service.fullTextForEdit(_editing!.id);
      if (full == null) {
        setState(() {
          _problems = const {};
          _banner = snippetOpenFailedMessage;
        });
        return;
      }
      content = full;
    }
    _shortcutCheck?.cancel();
    final r = widget.service.save(
      id: _editing?.id,
      name: _name.text,
      content: content,
      type: _type,
      shortcut: _shortcut.text,
    );
    switch (r.outcome) {
      case SnippetSave.saved:
        _closing = true;
        Navigator.of(context).pop(r.id);
      case SnippetSave.invalid:
        setState(() {
          _problems = r.problems;
          _banner = null;
          // A save that failed for another field keeps the live clash
          // message (it is checked here too, in case Save came before the
          // 500 ms check).
          _shortcutError =
              _errorFor(const {
                SnippetProblem.shortcutLength,
                SnippetProblem.shortcutSpaces,
              }) ??
              _liveShortcutIssue();
        });
        // The first bad field in the Tab order gets the focus.
        final nameBad =
            r.problems.contains(SnippetProblem.emptyName) ||
            r.problems.contains(SnippetProblem.longName);
        final shortcutBad = _shortcutError != null;
        (nameBad
                ? _nameNode
                : shortcutBad
                ? _shortcutNode
                : _contentNode)
            .requestFocus();
      case SnippetSave.shortcutTaken:
        setState(() {
          _problems = const {};
          _banner = null;
          _shortcutError = shortcutClashText(r.clash!, _shortcut.text);
        });
        _shortcutNode.requestFocus();
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

  static final _breaks = RegExp('\r\n|[\r\n\u2028\u2029]');

  /// Paste into Name (the paste key and the menu's Paste): a single-line
  /// field would drop the line breaks and glue the words together, so each
  /// break becomes a space first ("Line one Line two").
  Future<void> _pasteName() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty || !mounted) return;
    final text = raw.replaceAll(_breaks, ' ');
    final value = _name.value;
    final sel = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _name.value = TextEditingValue(
      text: value.text.replaceRange(sel.start, sel.end, text),
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
  }

  String? _liveShortcutIssue() {
    final text = _shortcut.text;
    final issue = widget.service.shortcutIssue(text, selfId: _editing?.id);
    return issue == null ? null : _issueText(issue, text);
  }

  String? _errorFor(Set<SnippetProblem> which) {
    for (final p in _problems) {
      if (which.contains(p)) return _problemText(p);
    }
    return null;
  }

  InputDecoration _decoration(
    KusungaTokens t,
    String label,
    String? error, {
    String? hint,
    String? helper,
  }) => InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    errorText: error,
    errorMaxLines: 3,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 4,
    helperStyle: KusungaTokens.caption.copyWith(color: t.textMuted),
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
          child: Actions(
            actions: {
              PasteTextIntent: CallbackAction<PasteTextIntent>(
                onInvoke: (_) {
                  _pasteName();
                  return null;
                },
              ),
            },
            child: TextField(
              contextMenuBuilder: (context, state) =>
                  AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: state.contextMenuAnchors,
                    buttonItems: [
                      for (final item in state.contextMenuButtonItems)
                        item.type == ContextMenuButtonType.paste
                            ? item.copyWith(
                                onPressed: () {
                                  state.hideToolbar();
                                  _pasteName();
                                },
                              )
                            : item,
                    ],
                  ),
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
          identifier: 'snippet-editor-shortcut',
          child: TextField(
            controller: _shortcut,
            focusNode: _shortcutNode,
            maxLines: 1,
            autocorrect: false,
            enableSuggestions: false,
            // 32 characters at most: the field refuses more (UI spec).
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxShortcutLength),
            ],
            onChanged: _shortcutChanged,
            style: KusungaTokens.mono.copyWith(color: t.text),
            decoration: _decoration(
              t,
              _shortcutLabel,
              _shortcutError,
              hint: _shortcutPlaceholder,
              helper: _allLetters.hasMatch(_shortcut.text)
                  ? '$_shortcutHint\n$_shortcutTip'
                  : _shortcutHint,
            ),
          ),
        ),
        gap,
        Semantics(
          identifier: 'snippet-editor-content',
          child: TextField(
            controller: _content,
            focusNode: _contentNode,
            autofocus: _fromHistory,
            readOnly: _contentUnread,
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
      // Every other way back (maybePop, the system back) goes through
      // _cancel, which reads the fields at that moment: a value computed at
      // build time would be stale after typing (F3). Closing itself uses
      // Navigator.pop, which PopScope does not block.
      canPop: false,
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
