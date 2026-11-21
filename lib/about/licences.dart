import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
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
    for (final (packages, asset) in [
      (const ['Kusunga'], kusungaLicenceAsset),
      (const ['Kusunga', 'SQLite3 Multiple Ciphers'], sqlite3mcNoticesAsset),
      (const ['Kusunga', 'SQLite'], sqliteNoticeAsset),
    ]) {
      String? text;
      try {
        text = await b.loadString(asset);
      } catch (_) {}
      if (text != null) yield LicenseEntryWithLineBreaks(packages, text);
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
      if (!mounted || _userMovedFocus) return;
      if (!_focusFirstRow()) _lookAfterNextFrame();
    });
  }

  /// True when the focus is on something other than the page's own start
  /// (the route's scope, or the node below): the user got there first.
  bool get _userMovedFocus {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null && focus != _start && focus is! FocusScopeNode;
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

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, focusNode: _start, child: widget.child);
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
