import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_classifier.dart';
import 'package:kusunga/history/clip_item.dart';

void main() {
  test('a single web address is a link', () {
    expect(classify('https://example.com/a?b=c#d'), ClipKind.link);
    expect(classify('http://localhost:8080/x'), ClipKind.link);
    expect(classify('  https://example.com  \n'), ClipKind.link);
  });

  test('anything else is text', () {
    expect(classify('hello'), ClipKind.text);
    expect(classify('see https://example.com for more'), ClipKind.text);
    expect(classify('https://a.com https://b.com'), ClipKind.text);
    expect(classify('https://a.com\nhttps://b.com'), ClipKind.text);
    expect(classify('example.com'), ClipKind.text);
    expect(classify('javascript:alert(1)'), ClipKind.text);
    expect(classify('file:///etc/passwd'), ClipKind.text);
    expect(classify('https://'), ClipKind.text);
    expect(classify('mailto:a@b.com'), ClipKind.text);
  });
}
