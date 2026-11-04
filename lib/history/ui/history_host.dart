import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../history_service.dart';
import 'history_screen.dart';

/// Shows the history once it has opened. If opening takes more than 300 ms a
/// spinner with "Opening your history…" shows; a fast open never flashes it.
class HistoryHost extends StatefulWidget {
  const HistoryHost({
    super.key,
    required this.history,
    this.initial,
    this.topSlot,
  });

  final Future<HistoryService> history;

  /// The history if it is already open, so there is no empty first frame.
  final HistoryService? initial;

  /// Extra content for the history screen (the picker settings).
  final Widget? topSlot;

  @override
  State<HistoryHost> createState() => _HistoryHostState();
}

class _HistoryHostState extends State<HistoryHost> {
  late HistoryService? _service = widget.initial;
  var _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _service == null) setState(() => _slow = true);
    });
    if (_service == null) {
      widget.history.then((s) {
        if (mounted) setState(() => _service = s);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service != null) {
      return HistoryScreen(service: service, topSlot: widget.topSlot);
    }
    final t = KusungaTokens.of(context);
    return Scaffold(
      backgroundColor: t.surface,
      body: _slow
          ? Center(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    SizedBox(height: KusungaTokens.space3),
                    Text(
                      'Opening your history…',
                      style: KusungaTokens.body.copyWith(color: t.text),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
