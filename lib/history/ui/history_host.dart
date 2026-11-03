import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../history_service.dart';
import 'history_screen.dart';

/// Shows the history once it has opened. If opening takes more than 300 ms a
/// spinner with "Opening your history…" shows; a fast open never flashes it.
class HistoryHost extends StatefulWidget {
  const HistoryHost({super.key, required this.history});

  final Future<HistoryService> history;

  @override
  State<HistoryHost> createState() => _HistoryHostState();
}

class _HistoryHostState extends State<HistoryHost> {
  HistoryService? _service;
  var _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _service == null) setState(() => _slow = true);
    });
    widget.history.then((s) {
      if (mounted) setState(() => _service = s);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service != null) return HistoryScreen(service: service);
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
