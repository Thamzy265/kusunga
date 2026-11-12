import 'package:flutter/widgets.dart';

/// A confirm dialog whose count follows live changes, and that closes by
/// itself, with the same result as Cancel (`false`), when the count
/// reaches 0 while it is open (PM decision 2026-11-08, "Close or
/// relabel"). Used by the Clear history and the Auto-delete dialogs.
///
/// [count] is read once when the dialog opens and once per change of
/// [listenable]; null means it could not be read, which never closes the
/// dialog. While it closes it keeps the last count it showed. It listens
/// only while the dialog is there.
class CloseAtZero extends StatefulWidget {
  const CloseAtZero({
    super.key,
    required this.listenable,
    required this.count,
    required this.builder,
  });

  final Listenable listenable;
  final int? Function() count;
  final Widget Function(BuildContext context, int? count) builder;

  @override
  State<CloseAtZero> createState() => _CloseAtZeroState();
}

class _CloseAtZeroState extends State<CloseAtZero> {
  late int? _count = widget.count();
  var _closing = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(CloseAtZero old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted || _closing) return;
    final count = widget.count();
    if (count != 0) {
      setState(() => _count = count);
      return;
    }
    final route = ModalRoute.of(context);
    // Already closed (confirmed), and still on screen only while it leaves:
    // nothing to close (Delete all history clears right after the pop).
    if (route == null || !route.isActive) return;
    _closing = true;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop(false);
    } else {
      navigator.removeRoute(route, false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _count);
}
