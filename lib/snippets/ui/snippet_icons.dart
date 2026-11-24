import 'package:material_ui/material_ui.dart';

import '../snippet.dart';

/// The icon for a type. Icons are decorative: the type is always in the
/// accessible name too (UI spec, "Accessible names").
IconData snippetIcon(SnippetType type) => switch (type) {
  SnippetType.phone => Icons.phone_outlined,
  SnippetType.email => Icons.mail_outline,
  SnippetType.link => Icons.link,
  SnippetType.address => Icons.home_outlined,
  SnippetType.other => Icons.notes,
};
