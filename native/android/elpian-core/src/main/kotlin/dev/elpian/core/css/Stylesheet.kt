package dev.elpian.core.css

import dev.elpian.core.util.jsString
import dev.elpian.core.util.parseFloatPrefix

/**
 * Stylesheets and the cascade — a port of `CSSStylesheet`,
 * `GlobalStylesheetManager` and `JsonStylesheetParser` (css/stylesheet.ts in
 * the TypeScript core). Flutter's order (tag → class → id → @media → inline,
 * `!important` re-applied on top) is kept; the selector engine adds compound
 * selectors, lists, descendant / child combinators, attributes and `:root`
 * custom properties with `var()`.
 */
typealias StyleMap = Map<String, Any?>

/** The facts about an element a selector can test. */
data class ElementFacts(
    val tagName: String,
    val id: String? = null,
    val classes: List<String>? = null,
    val attributes: Map<String, Any?>? = null,
)

private class CompoundSelector(
    val tag: String?,
    val id: String?,
    val classes: List<String>,
    val attrs: List<Pair<String, String?>>,
    val universal: Boolean,
    val root: Boolean,
)

private class ComplexSelector(
    /** Rightmost compound first; each step names the combinator to its left. */
    val parts: List<Pair<CompoundSelector, Char?>>,
    val specificity: Int,
)

class CSSRule(val selector: String, val styles: StyleMap, val order: Int) {
    internal val selectors: List<Any> = parseSelectorList(selector)

    fun toCSS(): String = "$selector {\n" + styles.entries.joinToString("\n") { "  ${it.key}: ${jsString(it.value)};" } + "\n}\n"
}

private var ruleCounter = 0

class CSSStylesheet {
    private var rules = ArrayList<CSSRule>()
    private val keyframes = LinkedHashMap<String, List<Keyframe>>()

    @Synchronized
    fun addRule(selector: String, styles: StyleMap) {
        val rule = CSSRule(selector.trim(), styles, ruleCounter++)
        removeRule(rule.selector)
        rules.add(rule)
    }

    @Synchronized
    fun removeRule(selector: String) {
        rules.removeAll { it.selector == selector }
    }

    val allRules: List<CSSRule> get() = rules.toList()

    fun getStyle(selector: String): StyleMap? = rules.firstOrNull { it.selector == selector }?.styles

    fun addKeyframeAnimation(name: String, frames: List<Keyframe>) {
        keyframes[name] = frames
    }

    fun getKeyframes(name: String): List<Keyframe>? = keyframes[name]

    val keyframeNames: List<String> get() = keyframes.keys.toList()

    /** Root custom properties (`:root { --x: … }`). */
    fun variables(): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        for (rule in rules) {
            @Suppress("UNCHECKED_CAST")
            val sels = rule.selectors as List<ComplexSelector>
            if (sels.any { it.parts.size == 1 && it.parts[0].first.root }) {
                for ((k, v) in rule.styles) if (k.startsWith("--")) out[k] = v
            }
        }
        return out
    }

    /** Matched rules (specificity, then source order), then [inlineStyles]. */
    fun getComputedStyleMap(element: ElementFacts, ancestors: List<ElementFacts> = emptyList(), inlineStyles: StyleMap? = null): MutableMap<String, Any?> {
        val merged = LinkedHashMap<String, Any?>()
        for (rule in matching(element, ancestors)) merged.putAll(rule.styles)
        if (inlineStyles != null) merged.putAll(inlineStyles)
        return merged
    }

    fun matching(element: ElementFacts, ancestors: List<ElementFacts>): List<CSSRule> {
        val matched = ArrayList<Pair<CSSRule, Int>>()
        for (rule in rules) {
            var best = -1
            @Suppress("UNCHECKED_CAST")
            for (sel in rule.selectors as List<ComplexSelector>) {
                if (sel.specificity > best && matchesComplex(sel, element, ancestors)) best = sel.specificity
            }
            if (best >= 0) matched.add(rule to best)
        }
        matched.sortWith(compareBy<Pair<CSSRule, Int>> { it.second }.thenBy { it.first.order })
        return matched.map { it.first }
    }

    fun clear() {
        rules = ArrayList()
        keyframes.clear()
    }

    fun toCSS(): String = rules.joinToString("\n") { it.toCSS() }

    /** Parse CSS text into this stylesheet; returns the `@media` blocks found. */
    fun parseCSS(cssText: String): List<Pair<String, CSSStylesheet>> = parseCssText(cssText, this)
}

class MediaQuery(val query: String, val stylesheet: CSSStylesheet) {
    fun matches(width: Double, height: Double): Boolean = mediaMatches(query, width, height)
}

private val MINMAX = Regex("(min|max)-(width|height):\\s*([\\d.]+)(px|em|rem)?")
private val ASPECT = Regex("(min|max)-aspect-ratio:\\s*(\\d+)\\s*/\\s*(\\d+)")

/** Flutter's media matcher, extended with lists, `not`, aspect ratios and colour scheme. */
fun mediaMatches(query: String, width: Double, height: Double, darkMode: Boolean = false): Boolean {
    val alternatives = query.split(',').map { it.trim() }.filter { it.isNotEmpty() }
    if (alternatives.isEmpty()) return true
    return alternatives.any { alt ->
        var negate = false
        var q = alt.lowercase()
        if (q.startsWith("not ")) {
            negate = true
            q = q.substring(4)
        }
        q = q.replace(Regex("^only\\s+"), "")
        var ok = true
        for (m in MINMAX.findAll(q)) {
            val isMin = m.groupValues[1] == "min"
            var threshold = m.groupValues[3].toDouble()
            if (m.groupValues[4] == "em" || m.groupValues[4] == "rem") threshold *= CssEnvironment.rootFontSize
            val actual = if (m.groupValues[2] == "width") width else height
            if (isMin && actual < threshold) ok = false
            if (!isMin && actual > threshold) ok = false
        }
        Regex("orientation:\\s*(portrait|landscape)").find(q)?.let { if ((it.groupValues[1] == "landscape") != (width >= height)) ok = false }
        for (m in ASPECT.findAll(q)) {
            val ratio = m.groupValues[2].toDouble() / m.groupValues[3].toDouble()
            val actual = if (height > 0) width / height else 0.0
            if (m.groupValues[1] == "min" && actual < ratio) ok = false
            if (m.groupValues[1] == "max" && actual > ratio) ok = false
        }
        Regex("prefers-color-scheme:\\s*(dark|light)").find(q)?.let { if ((it.groupValues[1] == "dark") != darkMode) ok = false }
        if (Regex("\\bprint\\b").containsMatchIn(q) && !Regex("\\bscreen\\b").containsMatchIn(q)) ok = false
        if (negate) !ok else ok
    }
}

/** The per-mini-app stylesheet manager (`GlobalStylesheetManager`). */
class StylesheetManager {
    val global = CSSStylesheet()
    private var mediaQueries = ArrayList<MediaQuery>()
    /** Bumped on every change so render caches can invalidate. */
    var version = 0
        private set
    var darkMode = false

    fun addMediaQuery(query: String, sheet: CSSStylesheet) {
        mediaQueries.removeAll { it.query == query }
        mediaQueries.add(MediaQuery(query, sheet))
        version++
    }

    fun touch() {
        version++
    }

    fun keyframes(name: String): List<Keyframe>? {
        global.getKeyframes(name)?.let { return it }
        for (mq in mediaQueries) mq.stylesheet.getKeyframes(name)?.let { return it }
        return null
    }

    val hasRules: Boolean get() = global.allRules.isNotEmpty() || mediaQueries.isNotEmpty()

    fun getComputedStyleMap(
        element: ElementFacts,
        ancestors: List<ElementFacts> = emptyList(),
        inlineStyles: StyleMap? = null,
        screenWidth: Double? = null,
        screenHeight: Double? = null,
    ): Map<String, Any?> {
        val merged = LinkedHashMap<String, Any?>()
        val important = LinkedHashMap<String, Any?>()
        fun mergeRaw(raw: Map<String, Any?>?) {
            if (raw == null) return
            for ((key, value) in raw) {
                val stripped = CSSParser.stripImportant(value)
                merged[key] = stripped
                if (CSSParser.isImportant(value)) important[key] = stripped
            }
        }
        mergeRaw(global.getComputedStyleMap(element, ancestors))
        if (mediaQueries.isNotEmpty()) {
            val w = screenWidth ?: CssEnvironment.viewportWidth
            val h = screenHeight ?: CssEnvironment.viewportHeight
            for (mq in mediaQueries) if (mediaMatches(mq.query, w, h, darkMode)) mergeRaw(mq.stylesheet.getComputedStyleMap(element, ancestors))
        }
        mergeRaw(inlineStyles)
        merged.putAll(important)
        return substituteVariables(merged)
    }

    /** Replace `var(--name, fallback)` with root / element custom properties. */
    fun substituteVariables(map: Map<String, Any?>): Map<String, Any?> {
        if (map.values.none { it is String && it.contains("var(") }) return map
        val vars = LinkedHashMap(global.variables())
        for ((k, v) in map) if (k.startsWith("--")) vars[k] = v
        val out = LinkedHashMap<String, Any?>()
        for ((k, v) in map) out[k] = if (v is String) resolveVars(v, vars, 0) else v
        return out
    }

    fun clear() {
        global.clear()
        mediaQueries = ArrayList()
        version++
    }

    /** Load a JSON stylesheet (`{rules, mediaQueries, variables, keyframes, css}`) or CSS text. */
    fun load(json: Any?) {
        when (json) {
            is String -> {
                for ((query, sheet) in global.parseCSS(json)) addMediaQuery(query, sheet)
                version++
            }
            is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                val map = json as Map<String, Any?>
                val sheet = parseJsonStylesheet(map) { query, mq -> addMediaQuery(query, mq) }
                for (rule in sheet.allRules) global.addRule(rule.selector, rule.styles)
                for (name in sheet.keyframeNames) global.addKeyframeAnimation(name, sheet.getKeyframes(name)!!)
                (map["css"] as? String)?.let { load(it) }
                version++
            }
        }
    }
}

private val VAR = Regex("var\\(\\s*(--[\\w-]+)\\s*(?:,\\s*([^()]*(?:\\([^()]*\\)[^()]*)*))?\\)")

private fun resolveVars(value: String, vars: Map<String, Any?>, depth: Int): Any {
    if (depth > 8 || !value.contains("var(")) return value
    val replaced = VAR.replace(value) { m ->
        val v = vars[m.groupValues[1]]
        if (v != null) jsString(v) else if (m.groups[2] != null) m.groupValues[2].trim() else ""
    }
    return resolveVars(replaced, vars, depth + 1)
}

/** `JsonStylesheetParser.parseJsonStylesheet`. */
@Suppress("UNCHECKED_CAST")
fun parseJsonStylesheet(json: Map<String, Any?>, onMedia: (String, CSSStylesheet) -> Unit): CSSStylesheet {
    val sheet = CSSStylesheet()
    (json["rules"] as? List<*>)?.let { rules ->
        val groups = LinkedHashMap<String, CSSStylesheet>()
        for (rule in rules) {
            if (rule !is Map<*, *>) continue
            val media = rule["media"] as? String
            if (media != null && media.isNotBlank()) addJsonRule(rule, groups.getOrPut(media) { CSSStylesheet() })
            else addJsonRule(rule, sheet)
        }
        for ((q, g) in groups) onMedia(q, g)
    }
    (json["mediaQueries"] as? List<*>)?.let { mqs ->
        for (mq in mqs) {
            if (mq !is Map<*, *>) continue
            val query = mq["query"] as? String ?: continue
            val group = CSSStylesheet()
            (mq["rules"] as? List<*>)?.forEach { addJsonRule(it, group) }
            onMedia(query, group)
        }
    }
    (json["variables"] as? Map<*, *>)?.let { variables ->
        val vars = LinkedHashMap<String, Any?>()
        for ((k, v) in variables) {
            val key = k.toString()
            vars[if (key.startsWith("--")) key else "--$key"] = v
        }
        sheet.addRule(":root", vars)
    }
    (json["keyframes"] as? List<*>)?.let { kfs ->
        for (kf in kfs) {
            if (kf !is Map<*, *>) continue
            val name = kf["name"] as? String ?: continue
            val frames = (kf["frames"] as? List<*>)?.mapNotNull { f ->
                if (f is Map<*, *> && f["offset"] is Number && f["styles"] is Map<*, *>) Keyframe((f["offset"] as Number).toDouble(), f["styles"] as Map<String, Any?>) else null
            } ?: continue
            sheet.addKeyframeAnimation(name, frames)
        }
    }
    return sheet
}

@Suppress("UNCHECKED_CAST")
private fun addJsonRule(rule: Any?, sheet: CSSStylesheet) {
    if (rule !is Map<*, *>) return
    val selector = rule["selector"] as? String ?: return
    val styles = rule["styles"] as? Map<String, Any?> ?: return
    sheet.addRule(selector, styles)
}

// ---------------------------------------------------------------------------
// CSS text
// ---------------------------------------------------------------------------

private val NUMERIC_DECL = Regex("^-?\\d+(\\.\\d+)?(px)?$")

private fun parseDeclarations(body: String): Map<String, Any?> {
    val styles = LinkedHashMap<String, Any?>()
    for (decl in CSSParser.splitTopLevel(body, ";")) {
        val idx = decl.indexOf(':')
        if (idx <= 0) continue
        val key = decl.substring(0, idx).trim()
        var value: Any = decl.substring(idx + 1).trim()
        val v = value as String
        if (key.isEmpty() || v.isEmpty()) continue
        if ((v.startsWith("\"") && v.endsWith("\"") && v.length >= 2) || (v.startsWith("'") && v.endsWith("'") && v.length >= 2)) value = v.substring(1, v.length - 1)
        else if (NUMERIC_DECL.matches(v)) value = parseFloatPrefix(v) ?: v
        styles[key] = value
    }
    return styles
}

private fun stripComments(css: String): String = css.replace(Regex("/\\*[\\s\\S]*?\\*/"), "")

private fun blocksOf(css: String): List<Pair<String, String>> {
    val out = ArrayList<Pair<String, String>>()
    var depth = 0
    var preludeStart = 0
    var bodyStart = -1
    for (i in css.indices) {
        when (css[i]) {
            '{' -> {
                if (depth == 0) bodyStart = i + 1
                depth++
            }
            '}' -> {
                depth--
                if (depth == 0 && bodyStart >= 0) {
                    out.add(css.substring(preludeStart, bodyStart - 1).trim() to css.substring(bodyStart, i))
                    preludeStart = i + 1
                    bodyStart = -1
                }
            }
            ';' -> if (depth == 0) preludeStart = i + 1
        }
    }
    return out
}

private fun parseCssText(css: String, sheet: CSSStylesheet): List<Pair<String, CSSStylesheet>> {
    val media = ArrayList<Pair<String, CSSStylesheet>>()
    for ((prelude, body) in blocksOf(stripComments(css))) {
        when {
            prelude.startsWith("@media") -> {
                val inner = CSSStylesheet()
                parseCssText(body, inner)
                media.add(prelude.substring(6).trim() to inner)
            }
            prelude.startsWith("@keyframes") || prelude.startsWith("@-webkit-keyframes") -> {
                val name = prelude.replace(Regex("^@(-webkit-)?keyframes"), "").trim()
                val frames = ArrayList<Keyframe>()
                for ((sel, decls) in blocksOf(body)) {
                    val styles = parseDeclarations(decls)
                    for (part in sel.split(',')) {
                        val t = part.trim().lowercase()
                        val offset = if (t == "from") 0.0 else if (t == "to") 1.0 else (parseFloatPrefix(t) ?: Double.NaN) / 100
                        if (offset.isFinite()) frames.add(Keyframe(offset, styles))
                    }
                }
                frames.sortBy { it.offset }
                sheet.addKeyframeAnimation(name, frames)
            }
            prelude.startsWith("@supports") || prelude.startsWith("@layer") -> media.addAll(parseCssText(body, sheet))
            !prelude.startsWith("@") -> sheet.addRule(prelude, parseDeclarations(body))
        }
    }
    return media
}

/** `JsonStylesheetParser.cssToJson`. */
fun cssToJson(cssText: String): Map<String, Any?> {
    val sheet = CSSStylesheet()
    val media = parseCssText(cssText, sheet)
    val rules = ArrayList<Map<String, Any?>>()
    for (r in sheet.allRules) rules.add(mapOf("selector" to r.selector, "styles" to r.styles))
    for ((q, s) in media) for (r in s.allRules) rules.add(mapOf("selector" to r.selector, "styles" to r.styles, "media" to q))
    return mapOf("rules" to rules)
}

// ---------------------------------------------------------------------------
// Selectors
// ---------------------------------------------------------------------------

private val IDENT = Regex("^-?[_a-zA-Z0-9\\u00A0-\\uFFFF][_a-zA-Z0-9\\u00A0-\\uFFFF\\\\-]*")
private val PSEUDO = Regex("^::?([a-zA-Z-]+)(\\([^)]*\\))?")

private fun parseCompound(text: String): CompoundSelector? {
    var tag: String? = null
    var id: String? = null
    val classes = ArrayList<String>()
    val attrs = ArrayList<Pair<String, String?>>()
    var universal = false
    var root = false
    var i = 0
    fun ident(): String? {
        val m = IDENT.find(text.substring(i)) ?: return null
        i += m.value.length
        return m.value
    }
    if (text.startsWith("*")) {
        universal = true
        i = 1
    } else if (text.isNotEmpty() && text[0].isLetter()) tag = ident()
    while (i < text.length) {
        when (text[i]) {
            '.' -> {
                i++
                classes.add(ident() ?: return null)
            }
            '#' -> {
                i++
                id = ident() ?: return null
            }
            '[' -> {
                val end = text.indexOf(']', i)
                if (end < 0) return null
                val inner = text.substring(i + 1, end)
                val eq = inner.indexOf('=')
                if (eq < 0) attrs.add(inner.trim() to null)
                else attrs.add(inner.substring(0, eq).trim() to inner.substring(eq + 1).trim().replace(Regex("^[\"']|[\"']$"), ""))
                i = end + 1
            }
            ':' -> {
                // `:root` is honoured; interactive states never match statically.
                val m = PSEUDO.find(text.substring(i)) ?: return null
                i += m.value.length
                val name = m.groupValues[1]
                if (name == "root") root = true else if (name != "first-child" && name != "last-child") return null
            }
            else -> return null
        }
    }
    return CompoundSelector(tag, id, classes, attrs, universal, root)
}

private fun parseComplex(text: String): ComplexSelector? {
    val tokens = ArrayList<String>()
    val combinators = ArrayList<Char>()
    val normalized = text.replace(Regex("\\s*>\\s*"), ">").replace(Regex("\\s+"), " ").trim()
    val current = StringBuilder()
    for (ch in normalized) {
        if (ch == ' ' || ch == '>') {
            if (current.isNotEmpty()) tokens.add(current.toString())
            current.clear()
            combinators.add(ch)
        } else current.append(ch)
    }
    if (current.isNotEmpty()) tokens.add(current.toString())
    if (tokens.isEmpty() || combinators.size != tokens.size - 1) return null
    val compounds = tokens.map { parseCompound(it) ?: return null }
    val parts = ArrayList<Pair<CompoundSelector, Char?>>()
    for (k in compounds.indices.reversed()) parts.add(compounds[k] to (if (k > 0) combinators[k - 1] else null))
    var ids = 0
    var cls = 0
    var tags = 0
    for (c in compounds) {
        if (c.id != null) ids++
        cls += c.classes.size + c.attrs.size + (if (c.root) 1 else 0)
        if (c.tag != null) tags++
    }
    return ComplexSelector(parts, ids * 10000 + cls * 100 + tags)
}

private fun parseSelectorList(selector: String): List<Any> =
    CSSParser.splitTopLevel(selector, ",").map { it.trim() }.filter { it.isNotEmpty() }.mapNotNull { parseComplex(it) }

private fun matchesCompound(c: CompoundSelector, el: ElementFacts): Boolean {
    if (c.root) return el.tagName == ":root" || el.tagName == "html"
    if (c.tag != null && c.tag != el.tagName && !c.tag.equals(el.tagName, ignoreCase = true)) return false
    if (c.id != null && c.id != el.id) return false
    if (c.classes.isNotEmpty()) {
        val own = el.classes ?: emptyList()
        for (cls in c.classes) if (cls !in own) return false
    }
    for ((name, value) in c.attrs) {
        val attrs = el.attributes ?: return false
        if (!attrs.containsKey(name)) return false
        if (value != null && jsString(attrs[name]) != value) return false
    }
    return c.universal || c.tag != null || c.id != null || c.classes.isNotEmpty() || c.attrs.isNotEmpty()
}

private fun matchesComplex(sel: ComplexSelector, el: ElementFacts, ancestors: List<ElementFacts>): Boolean {
    val first = sel.parts[0]
    if (!matchesCompound(first.first, el)) return false
    var combinator = first.second
    var index = 0
    for (k in 1 until sel.parts.size) {
        val part = sel.parts[k]
        if (combinator == '>') {
            val parent = ancestors.getOrNull(index) ?: return false
            if (!matchesCompound(part.first, parent)) return false
            index++
        } else {
            var found = false
            while (index < ancestors.size) {
                if (matchesCompound(part.first, ancestors[index++])) {
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        combinator = part.second
    }
    return true
}
