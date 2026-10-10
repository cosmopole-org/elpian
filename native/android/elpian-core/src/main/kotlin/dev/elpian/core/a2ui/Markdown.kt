package dev.elpian.core.a2ui

/**
 * The "simple Markdown" A2UI `Text` supports (a2ui/markdown.ts), parsed to
 * plain data the lowering turns into rich text: ATX headings, bullet and
 * numbered list items, paragraphs, and inline `**bold**`, `*italic*` /
 * `_italic_`, `~~strike~~`, `` `code` `` and `[links](https://…)`. Anything
 * else stays literal text.
 */
data class MarkdownInline(
    val text: String,
    val bold: Boolean = false,
    val italic: Boolean = false,
    val strike: Boolean = false,
    val code: Boolean = false,
    val href: String? = null,
)

/** A block: `heading` (with [level]), `paragraph`, `bullet` or `ordered` (with [number]). */
data class MarkdownBlock(val type: String, val inlines: List<MarkdownInline>, val level: Int = 0, val number: Int = 0)

private val HEADING = Regex("^\\s{0,3}(#{1,6})\\s+(.*?)\\s*#*\\s*$")
private val BULLET = Regex("^\\s*[-*+]\\s+(.*)$")
private val ORDERED = Regex("^\\s*(\\d{1,9})[.)]\\s+(.*)$")
private val INLINE = Regex("(\\*\\*|__)(.+?)\\1|(\\*|_)(?!\\s)(.+?)\\3|~~(.+?)~~|`([^`]+)`|\\[([^\\]]+)\\]\\(([^)\\s]+)\\)")
private val NEWLINES = Regex("\\r\\n?")

fun parseMarkdown(source: String): List<MarkdownBlock> {
    val blocks = ArrayList<MarkdownBlock>()
    val paragraph = ArrayList<String>()
    fun flush() {
        if (paragraph.isNotEmpty()) blocks.add(MarkdownBlock("paragraph", parseInlines(paragraph.joinToString("\n"))))
        paragraph.clear()
    }
    for (line in source.replace(NEWLINES, "\n").split("\n")) {
        val heading = HEADING.find(line)
        val bullet = BULLET.find(line)
        val ordered = ORDERED.find(line)
        if (line.trim().isEmpty()) flush()
        else if (heading != null) {
            flush()
            blocks.add(MarkdownBlock("heading", parseInlines(heading.groupValues[2]), level = heading.groupValues[1].length))
        } else if (bullet != null) {
            flush()
            blocks.add(MarkdownBlock("bullet", parseInlines(bullet.groupValues[1])))
        } else if (ordered != null) {
            flush()
            blocks.add(MarkdownBlock("ordered", parseInlines(ordered.groupValues[2]), number = ordered.groupValues[1].toInt()))
        } else paragraph.add(line)
    }
    flush()
    return blocks
}

fun parseInlines(text: String, inherited: MarkdownInline = MarkdownInline("")): List<MarkdownInline> {
    val out = ArrayList<MarkdownInline>()
    var rest = text
    while (rest.isNotEmpty()) {
        val m = INLINE.find(rest)
        if (m == null) {
            out.add(inherited.copy(text = rest))
            break
        }
        if (m.range.first > 0) out.add(inherited.copy(text = rest.substring(0, m.range.first)))
        val g = m.groups
        when {
            g[2] != null -> out.addAll(parseInlines(g[2]!!.value, inherited.copy(bold = true)))
            g[4] != null -> out.addAll(parseInlines(g[4]!!.value, inherited.copy(italic = true)))
            g[5] != null -> out.addAll(parseInlines(g[5]!!.value, inherited.copy(strike = true)))
            g[6] != null -> out.add(inherited.copy(text = g[6]!!.value, code = true))
            g[7] != null -> out.addAll(parseInlines(g[7]!!.value, inherited.copy(href = g[8]!!.value)))
        }
        rest = rest.substring(m.range.last + 1)
    }
    return out.filter { it.text != "" }
}

/** Whether [blocks] is one paragraph of unformatted text. */
fun isPlainText(blocks: List<MarkdownBlock>): Boolean =
    blocks.size == 1 && blocks[0].type == "paragraph" && blocks[0].inlines.all { !it.bold && !it.italic && !it.strike && !it.code && it.href == null }

/** The text without Markdown markers (for accessibility labels and fallbacks). */
fun plainText(blocks: List<MarkdownBlock>): String = blocks.joinToString("\n") { b -> b.inlines.joinToString("") { it.text } }
