import 'package:flutter/foundation.dart'
    show
        LicenseEntry,
        LicenseEntryWithLineBreaks,
        LicenseParagraph,
        LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'build_info.dart';

/// The notices bundled with the app (M1.9a, GPLv3 section 5(d) and the
/// third-party notices Flutter's own collection misses; `docs/licences.md`).
/// The texts are assets, never fetched. `LICENSE` is the GPL text itself.
const kusungaLicenceAsset = 'LICENSE';
const sqlite3mcNoticesAsset = 'assets/licences/sqlite3mc.txt';
const sqliteNoticeAsset = 'assets/licences/sqlite.txt';

const licenceLegalese =
    'Copyright (C) 2026 William Nasoni. Licensed under the GNU GPL, version 3 '
    'only. This program comes with ABSOLUTELY NO WARRANTY. This is free '
    'software, and you are welcome to redistribute it under certain '
    'conditions; see the GNU GPL for details.';

/// A notice text for the licence page in which lines indented by four or more
/// spaces keep their line breaks (the SQLite blessing, the copyright lines of
/// a source header). Everything else is read as Flutter reads
/// [LicenseEntryWithLineBreaks]: lines of a paragraph run together, a blank
/// line starts a new paragraph. An indented run is shown as written, one
/// paragraph per blank-line block, without the indent they all share.
class NoticeEntry extends LicenseEntry {
  const NoticeEntry(this.packages, this.text);

  @override
  final List<String> packages;

  final String text;

  static const _preIndent = 4;

  static int _indent(String line) => line.length - line.trimLeft().length;

  static bool _isPre(String line) =>
      line.trim().isNotEmpty && _indent(line) >= _preIndent;

  @override
  Iterable<LicenseParagraph> get paragraphs sync* {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var flowed = <String>[];
    var i = 0;
    while (i < lines.length) {
      if (!_isPre(lines[i])) {
        flowed.add(lines[i++]);
        continue;
      }
      if (flowed.isNotEmpty) {
        yield* LicenseEntryWithLineBreaks(
          packages,
          flowed.join('\n'),
        ).paragraphs;
        flowed = [];
      }
      // The run goes on over blank lines while an indented line follows.
      var end = i;
      for (var j = i; j < lines.length; j++) {
        if (_isPre(lines[j])) {
          end = j;
        } else if (lines[j].trim().isNotEmpty) {
          break;
        }
      }
      final run = lines.sublist(i, end + 1);
      final common = run
          .where((l) => l.trim().isNotEmpty)
          .map(_indent)
          .reduce((a, b) => a < b ? a : b);
      var block = <String>[];
      for (final line in [...run, '']) {
        if (line.trim().isEmpty) {
          if (block.isNotEmpty) yield LicenseParagraph(block.join('\n'), 1);
          block = [];
        } else {
          block.add(line.substring(common).trimRight());
        }
      }
      i = end + 1;
    }
    if (flowed.isNotEmpty) {
      yield* LicenseEntryWithLineBreaks(packages, flowed.join('\n')).paragraphs;
    }
  }
}

/// Adds Kusunga, SQLite3 Multiple Ciphers and SQLite to Flutter's licence
/// registry, so they are listed at the top of the licence page. Each text is
/// read from [bundle] only when the page is opened.
///
/// Order matters. Flutter's licence page pins only the first package of the
/// FIRST collector at the top and sorts every other package by its lower-cased
/// name. [KusungaBinding] therefore calls this before the binding registers
/// its own NOTICES collector; otherwise "abseil-cpp" is pinned and Kusunga
/// lands in the middle of the list. Because "SQLite" and "SQLite3 Multiple
/// Ciphers" are sorted in with the pub packages, both notices are also listed
/// under the "Kusunga" package, so the top row leads to every notice.
void registerLicences({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final b = bundle ?? rootBundle;
    // Each notice stands alone: one that fails to load is left out and the
    // others still show. "Kusunga" is always first in a package list, so it is
    // the pinned package even if LICENSE itself cannot be read.
    // LICENSE is the GPL text, laid out the way Flutter reads licence files.
    // The two notices are ours, so they may keep line breaks ([NoticeEntry]).
    for (final (packages, asset, ours) in [
      (const ['Kusunga'], kusungaLicenceAsset, false),
      (
        const ['Kusunga', 'SQLite3 Multiple Ciphers'],
        sqlite3mcNoticesAsset,
        true,
      ),
      (const ['Kusunga', 'SQLite'], sqliteNoticeAsset, true),
    ]) {
      String? text;
      try {
        text = await b.loadString(asset);
      } catch (_) {}
      if (text == null) continue;
      yield ours
          ? NoticeEntry(packages, text)
          : LicenseEntryWithLineBreaks(packages, text);
    }
  });
}

/// A page route that has no transition when the system asks for reduced
/// motion (the app's reduced-motion rule, like `history_row.dart`).
class _LicencesRoute extends MaterialPageRoute<void> {
  _LicencesRoute({required super.builder, required this.reduceMotion});

  final bool reduceMotion;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : super.reverseTransitionDuration;
}

enum _PageFocus { notYet, pageHolds, userMoved }

/// Gives the page a focus to hold the Esc binding at once, then moves it to the
/// first row of the list when the notices have loaded (spec: "Focus moves to
/// the first row"). Flutter's page gives no signal when its list is ready, so
/// this looks after each frame. It leaves the focus alone if the user has
/// already moved it.
class _FocusFirstRow extends StatefulWidget {
  const _FocusFirstRow({required this.child});

  final Widget child;

  @override
  State<_FocusFirstRow> createState() => _FocusFirstRowState();
}

class _FocusFirstRowState extends State<_FocusFirstRow> {
  final _start = FocusNode(debugLabel: 'licences start');

  @override
  void initState() {
    super.initState();
    _lookAfterNextFrame();
  }

  @override
  void dispose() {
    _start.dispose();
    super.dispose();
  }

  void _lookAfterNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (_focusNow) {
        case _PageFocus.notYet:
          _lookAfterNextFrame();
        case _PageFocus.pageHolds:
          if (!_focusFirstRow()) _lookAfterNextFrame();
        case _PageFocus.userMoved:
          return;
      }
    });
  }

  /// Where the focus is, seen from the page. The route moves the focus in only
  /// after the first frame (a microtask), so until then it is still on
  /// whatever opened the page, such as View licences after Tab and Enter: that
  /// is [_PageFocus.notYet], not the user. Inside the page, [_start] or a
  /// route's scope (Flutter's page has its own navigator) is the page's own
  /// focus; the user never Tabs to a scope. Any other node inside the page is
  /// one the user moved to.
  _PageFocus get _focusNow {
    if (!_start.hasFocus) return _PageFocus.notYet;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == _start || focus is FocusScopeNode) {
      return _PageFocus.pageHolds;
    }
    return _PageFocus.userMoved;
  }

  /// False while the list has not been built yet.
  bool _focusFirstRow() {
    Element? row;
    void visit(Element e) {
      if (row != null) return;
      if (e.widget is ListTile) {
        row = e;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    if (row == null) return false;
    Element? label;
    void findLabel(Element e) {
      if (label != null) return;
      if (e.widget is Text) {
        label = e;
        return;
      }
      e.visitChildren(findLabel);
    }

    row!.visitChildren(findLabel);
    // The Text sits inside the row's own InkWell, so the nearest Focus above
    // it is the row's.
    Focus.maybeOf(label ?? row!)?.requestFocus();
    return true;
  }

  /// [_start] has no focus ring, so it is never a Tab stop (WCAG 2.4.7).
  /// Autofocus still gives it the focus at once, so Esc works from the start;
  /// [_focusNow] reads focus, not traversal, so it still sees [_start].
  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    skipTraversal: true,
    focusNode: _start,
    child: widget.child,
  );
}

/// Opens Flutter's licence page for this build, with Esc to go back (what
/// `showLicensePage` does, plus the key the spec asks for). Closing it returns
/// the focus to the button that opened it.
Future<void> showLicences(BuildContext context, BuildInfo info) =>
    Navigator.of(context).push<void>(
      _LicencesRoute(
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        builder: (context) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: _FocusFirstRow(
            child: LicensePage(
              applicationName: 'Kusunga',
              applicationVersion: info.licenceVersion,
              applicationLegalese: licenceLegalese,
            ),
          ),
        ),
      ),
    );
