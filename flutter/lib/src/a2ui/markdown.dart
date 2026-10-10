/// The "simple Markdown" A2UI `Text` supports, parsed to plain data the
/// lowering turns into rich text: ATX headings, bullet and numbered list items,
/// paragraphs, and inline `**bold**`, `*italic*` / `_italic_`, `~~strike~~`,
/// `` `code` `` and `[links](https://…)`. Anything else stays literal text.
library;

class MarkdownInline {
  const MarkdownInline(this.text,
      {this.bold = false,
      this.italic = false,
      this.strike = false,
      this.code = false,
      this.href});

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final String? href;

  MarkdownInline withText(String text) => MarkdownInline(text,
      bold: bold, italic: italic, strike: strike, code: code, href: href);

  MarkdownInline copyWith(
          {bool? bold, bool? italic, bool? strike, bool? code, String? href}) =>
      MarkdownInline(text,
          bold: bold ?? this.bold,
          italic: italic ?? this.italic,
          strike: strike ?? this.strike,
          code: code ?? this.code,
          href: href ?? this.href);
}

/// `heading` (with [level]), `paragraph`, `bullet` or `ordered` (with [number]).
class MarkdownBlock {
  const MarkdownBlock(this.type, this.inlines,
      {this.level = 0, this.number = 0});
  final String type;
  final List<MarkdownInline> inlines;
  final int level;
  final int number;
}

final RegExp _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _ordered = RegExp(r'^\s*(\d{1,9})[.)]\s+(.*)$');

List<MarkdownBlock> parseMarkdown(String source) {
  final blocks = <MarkdownBlock>[];
  var paragraph = <String>[];
  void flush() {
    if (paragraph.isNotEmpty) {
      blocks
          .add(MarkdownBlock('paragraph', parseInlines(paragraph.join('\n'))));
    }
    paragraph = [];
  }

  for (final line in source.replaceAll(RegExp(r'\r\n?'), '\n').split('\n')) {
    final heading = _heading.firstMatch(line);
    final bullet = _bullet.firstMatch(line);
    final ordered = _ordered.firstMatch(line);
    if (line.trim().isEmpty) {
      flush();
    } else if (heading != null) {
      flush();
      blocks.add(MarkdownBlock('heading', parseInlines(heading[2]!),
          level: heading[1]!.length));
    } else if (bullet != null) {
      flush();
      blocks.add(MarkdownBlock('bullet', parseInlines(bullet[1]!)));
    } else if (ordered != null) {
      flush();
      blocks.add(MarkdownBlock('ordered', parseInlines(ordered[2]!),
          number: int.parse(ordered[1]!)));
    } else {
      paragraph.add(line);
    }
  }
  flush();
  return blocks;
}

final RegExp _inline = RegExp(
    r'(\*\*|__)(.+?)\1|(\*|_)(?!\s)(.+?)\3|~~(.+?)~~|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)');

List<MarkdownInline> parseInlines(String text,
    [MarkdownInline inherited = const MarkdownInline('')]) {
  final out = <MarkdownInline>[];
  var rest = text;
  while (rest.isNotEmpty) {
    final m = _inline.firstMatch(rest);
    if (m == null) {
      out.add(inherited.withText(rest));
      break;
    }
    if (m.start > 0) out.add(inherited.withText(rest.substring(0, m.start)));
    if (m[2] != null) {
      out.addAll(parseInlines(m[2]!, inherited.copyWith(bold: true)));
    } else if (m[4] != null) {
      out.addAll(parseInlines(m[4]!, inherited.copyWith(italic: true)));
    } else if (m[5] != null) {
      out.addAll(parseInlines(m[5]!, inherited.copyWith(strike: true)));
    } else if (m[6] != null) {
      out.add(inherited.copyWith(code: true).withText(m[6]!));
    } else if (m[7] != null) {
      out.addAll(parseInlines(m[7]!, inherited.copyWith(href: m[8])));
    }
    rest = rest.substring(m.end);
  }
  return out.where((i) => i.text.isNotEmpty).toList();
}

/// Whether [blocks] is one paragraph of unformatted text.
bool isPlainText(List<MarkdownBlock> blocks) =>
    blocks.length == 1 &&
    blocks.first.type == 'paragraph' &&
    blocks.first.inlines.every(
        (i) => !i.bold && !i.italic && !i.strike && !i.code && i.href == null);

/// The text without Markdown markers (for accessibility labels and fallbacks).
String plainText(List<MarkdownBlock> blocks) =>
    blocks.map((b) => b.inlines.map((i) => i.text).join()).join('\n');
