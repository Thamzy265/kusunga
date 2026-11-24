import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../ui/section_heading.dart';
import 'build_info.dart';
import 'licences.dart';

// Copy from the UI spec (`docs/ui/about-and-licences.md`, "Copy").
const _heading = 'About';
const _copyright = 'Copyright (C) 2026 William Nasoni';
const _licenceSentence =
    'Kusunga is free software under the GNU General Public License, version 3 '
    'only. It comes with NO WARRANTY.';
const _copyVersion = 'Copy version';
const _copyLink = 'Copy link';
const _viewLicences = 'View licences';
const _versionCopied = 'Version copied';
const _linkCopied = 'Link copied';
const _copyFailed = "Couldn't copy. Try again.";

/// The About section at the bottom of Settings (M1.9a): the version and build,
/// the GPL notice, the source link and the licences. Nothing here uses the
/// network: the link is text with a Copy link button.
class AboutSection extends StatefulWidget {
  const AboutSection({
    super.key,
    required this.info,
    required this.copy,
    required this.toast,
  });

  final BuildInfo info;

  /// Puts text on the clipboard as Kusunga's own copy (not added to history).
  /// False if it failed.
  final Future<bool> Function(String text) copy;
  final void Function(String message) toast;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  final _licencesFocus = FocusNode(debugLabel: 'View licences');

  BuildInfo get info => widget.info;

  @override
  void dispose() {
    _licencesFocus.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String done) async {
    var ok = false;
    try {
      ok = await widget.copy(text);
    } catch (_) {}
    widget.toast(ok ? done : _copyFailed);
  }

  /// A mouse click does not focus a button, so the page's route had nothing to
  /// give the focus back to on Esc (M1.9a B4). The button takes it first, as
  /// it already does for Enter.
  void _openLicences() {
    _licencesFocus.requestFocus();
    showLicences(context, info);
  }

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    final body = KusungaTokens.body.copyWith(color: t.text);
    Widget button(
      String id,
      String label,
      VoidCallback onPressed, {
      String? name,
      FocusNode? focusNode,
    }) => Semantics(
      identifier: id,
      label: name ?? label,
      excludeSemantics: true,
      button: true,
      onTap: onPressed,
      child: OutlinedButton(
        style: ButtonStyle(
          overlayColor: WidgetStatePropertyAll(t.surfaceHover),
          foregroundColor: WidgetStatePropertyAll(t.text),
          minimumSize: const WidgetStatePropertyAll(Size(24, 40)),
        ),
        focusNode: focusNode,
        onPressed: onPressed,
        child: Text(label),
      ),
    );
    // 600 px and wider: the button at the end of its line. Narrower (360 px,
    // and 320 px or 360 px at 200% text): under it, left-aligned, so the text
    // wraps and nothing scrolls sideways.
    Widget line(Widget text, Widget action) => LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 600) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text),
              SizedBox(width: KusungaTokens.space3),
              action,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text,
            SizedBox(height: KusungaTokens.space2),
            action,
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(_heading),
        SizedBox(height: KusungaTokens.space2),
        line(
          Text(info.versionLine, style: body),
          button(
            'about-copy-version',
            _copyVersion,
            () => _copy(info.copyText, _versionCopied),
            name: info.copyVersionLabel,
          ),
        ),
        SizedBox(height: KusungaTokens.space2),
        Text(_copyright, style: body),
        SizedBox(height: KusungaTokens.space1),
        Text(_licenceSentence, style: body),
        SizedBox(height: KusungaTokens.space3),
        line(
          // The link is selectable text. It wraps wherever the line is full,
          // so a long address never scrolls sideways.
          SelectableText('Source code: ${info.sourceUrl}', style: body),
          button(
            'about-copy-link',
            _copyLink,
            () => _copy(info.sourceUrl, _linkCopied),
            name: 'Copy source code link',
          ),
        ),
        if (info.caption case final caption?) ...[
          SizedBox(height: KusungaTokens.space1),
          Text(
            caption,
            style: KusungaTokens.caption.copyWith(color: t.textMuted),
          ),
        ],
        SizedBox(height: KusungaTokens.space3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: button(
            'about-view-licences',
            _viewLicences,
            _openLicences,
            focusNode: _licencesFocus,
          ),
        ),
      ],
    );
  }
}
