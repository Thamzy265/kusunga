import 'clip_item.dart';

/// A copy that is one web address (http or https) is a link; everything
/// else is text. Links are never opened by Kusunga.
ClipKind classify(String content) {
  final text = content.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return ClipKind.text;
  final uri = Uri.tryParse(text);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return ClipKind.link;
  }
  return ClipKind.text;
}
