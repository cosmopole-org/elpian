/**
 * The "simple Markdown" A2UI `Text` supports, parsed to plain data the
 * lowering turns into rich text: ATX headings, bullet and numbered list items,
 * paragraphs, and inline `**bold**`, `*italic*` / `_italic_`, `~~strike~~`,
 * `` `code` `` and `[links](https://…)`. Anything else stays literal text.
 */

export interface MarkdownInline {
  text: string;
  bold?: boolean;
  italic?: boolean;
  strike?: boolean;
  code?: boolean;
  href?: string;
}

export type MarkdownBlock =
  | { type: 'heading'; level: number; inlines: MarkdownInline[] }
  | { type: 'paragraph'; inlines: MarkdownInline[] }
  | { type: 'bullet'; inlines: MarkdownInline[] }
  | { type: 'ordered'; number: number; inlines: MarkdownInline[] };

export function parseMarkdown(source: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  let paragraph: string[] = [];
  const flush = () => {
    if (paragraph.length) blocks.push({ type: 'paragraph', inlines: parseInlines(paragraph.join('\n')) });
    paragraph = [];
  };
  for (const line of source.replace(/\r\n?/g, '\n').split('\n')) {
    const heading = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
    const bullet = /^\s*[-*+]\s+(.*)$/.exec(line);
    const ordered = /^\s*(\d{1,9})[.)]\s+(.*)$/.exec(line);
    if (line.trim() === '') flush();
    else if (heading) {
      flush();
      blocks.push({ type: 'heading', level: heading[1].length, inlines: parseInlines(heading[2]) });
    } else if (bullet) {
      flush();
      blocks.push({ type: 'bullet', inlines: parseInlines(bullet[1]) });
    } else if (ordered) {
      flush();
      blocks.push({ type: 'ordered', number: Number(ordered[1]), inlines: parseInlines(ordered[2]) });
    } else paragraph.push(line);
  }
  flush();
  return blocks;
}

const INLINE = /(\*\*|__)(.+?)\1|(\*|_)(?!\s)(.+?)\3|~~(.+?)~~|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)/;

export function parseInlines(text: string, inherited: Omit<MarkdownInline, 'text'> = {}): MarkdownInline[] {
  const out: MarkdownInline[] = [];
  let rest = text;
  while (rest.length) {
    const m = INLINE.exec(rest);
    if (!m) {
      out.push({ ...inherited, text: rest });
      break;
    }
    if (m.index > 0) out.push({ ...inherited, text: rest.substring(0, m.index) });
    if (m[2] !== undefined) out.push(...parseInlines(m[2], { ...inherited, bold: true }));
    else if (m[4] !== undefined) out.push(...parseInlines(m[4], { ...inherited, italic: true }));
    else if (m[5] !== undefined) out.push(...parseInlines(m[5], { ...inherited, strike: true }));
    else if (m[6] !== undefined) out.push({ ...inherited, text: m[6], code: true });
    else if (m[7] !== undefined) out.push(...parseInlines(m[7], { ...inherited, href: m[8] }));
    rest = rest.substring(m.index + m[0].length);
  }
  return out.filter((i) => i.text !== '');
}

/** Whether [blocks] is one paragraph of unformatted text. */
export function isPlainText(blocks: MarkdownBlock[]): boolean {
  return blocks.length === 1 && blocks[0].type === 'paragraph' && blocks[0].inlines.every((i) => !i.bold && !i.italic && !i.strike && !i.code && !i.href);
}

/** The text without Markdown markers (for accessibility labels and fallbacks). */
export function plainText(blocks: MarkdownBlock[]): string {
  return blocks.map((b) => b.inlines.map((i) => i.text).join('')).join('\n');
}
