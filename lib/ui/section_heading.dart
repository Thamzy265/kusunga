import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A section heading in a tab panel ("General", "Pause history"): body
/// text in semi-bold, marked as a heading for screen readers.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = KusungaTokens.of(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: KusungaTokens.body.copyWith(
          color: t.text,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
