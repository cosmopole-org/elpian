package dev.elpian.core.render

import dev.elpian.core.css.CSSStyle
import dev.elpian.core.css.Color
import dev.elpian.core.css.M3
import dev.elpian.core.css.TextShadow

/**
 * The inheritable text style used while lowering (render/text-style.ts): merge
 * rules (`TextStyle.merge` / `DefaultTextStyle`), font-family resolution and
 * the conversion to the [TextStyleSpec] the platform renders with.
 */
data class TextStyle(
    val color: Color? = null,
    val fontSize: Double? = null,
    val fontWeight: Int? = null,
    val italic: Boolean? = null,
    val fontFamily: String? = null,
    val letterSpacing: Double? = null,
    val wordSpacing: Double? = null,
    /** Height multiplier. */
    val height: Double? = null,
    /** Pixel line height (resolved against the final font size). */
    val heightPx: Double? = null,
    val decoration: Int? = null,
    val decorationColor: Color? = null,
    val decorationStyle: String? = null,
    val decorationThickness: Double? = null,
    val shadows: List<TextShadow>? = null,
    val background: Color? = null,
    val baselineShift: Double? = null,
    val textTransform: String? = null,
) {
    /** Later wins for every field it defines. */
    fun merge(over: TextStyle?): TextStyle {
        if (over == null) return this
        var out = TextStyle(
            color = over.color ?: color,
            fontSize = over.fontSize ?: fontSize,
            fontWeight = over.fontWeight ?: fontWeight,
            italic = over.italic ?: italic,
            fontFamily = over.fontFamily ?: fontFamily,
            letterSpacing = over.letterSpacing ?: letterSpacing,
            wordSpacing = over.wordSpacing ?: wordSpacing,
            height = over.height ?: height,
            heightPx = over.heightPx ?: heightPx,
            decoration = over.decoration ?: decoration,
            decorationColor = over.decorationColor ?: decorationColor,
            decorationStyle = over.decorationStyle ?: decorationStyle,
            decorationThickness = over.decorationThickness ?: decorationThickness,
            shadows = over.shadows ?: shadows,
            background = over.background ?: background,
            baselineShift = over.baselineShift ?: baselineShift,
            textTransform = over.textTransform ?: textTransform,
        )
        if (over.height != null) out = out.copy(heightPx = null)
        if (over.heightPx != null) out = out.copy(height = null)
        return out
    }

    companion object {
        /** Material 3 `bodyMedium`. */
        val DEFAULT = TextStyle(color = M3.onSurface, fontSize = 14.0, fontWeight = 400, italic = false, fontFamily = null, letterSpacing = 0.25, wordSpacing = 0.0, height = 20.0 / 14, decoration = 0)
        /** Material 3 `labelLarge` (buttons). */
        val LABEL_LARGE = TextStyle(fontSize = 14.0, fontWeight = 500, letterSpacing = 0.1, height = 20.0 / 14)
        /** Material 3 `titleLarge` (app bar titles). */
        val TITLE_LARGE = TextStyle(fontSize = 22.0, fontWeight = 400, letterSpacing = 0.0, height = 28.0 / 22)
        /** Material 3 `bodyLarge` (text fields). */
        val BODY_LARGE = TextStyle(fontSize = 16.0, fontWeight = 400, letterSpacing = 0.5, height = 24.0 / 16)
        /** Material 3 `labelSmall` (badges). */
        val LABEL_SMALL = TextStyle(fontSize = 11.0, fontWeight = 500, letterSpacing = 0.5, height = 16.0 / 11)
    }
}

fun mergeTextStyle(base: TextStyle?, over: TextStyle?): TextStyle = (base ?: TextStyle()).merge(over)

object TextDecorationBits {
    const val underline = 1
    const val overline = 2
    const val lineThrough = 4
}

private val SERIF = setOf("serif", "georgia", "times", "times new roman", "cambria", "garamond", "cinzel", "playfair display", "merriweather", "crimson", "crimson pro", "pt serif", "noto serif", "liberation serif", "roboto serif")
private val MONO = setOf("monospace", "courier", "courier new", "consolas", "menlo", "monaco", "roboto mono", "sf mono", "source code pro", "fira code", "jetbrains mono", "liberation mono", "ui-monospace")
private val SANS = setOf("sans-serif", "arial", "helvetica", "helvetica neue", "roboto", "inter", "segoe ui", "verdana", "tahoma", "noto sans", "liberation sans", "ubuntu")
private val QUOTES = Regex("^['\"]|['\"]$")

/** Resolve a CSS font-family list as Flutter's engine does. */
fun resolveFontFamily(family: String?): String? {
    if (family.isNullOrEmpty()) return null
    if (family == "icons") return "icons"
    for (raw in family.split(',')) {
        val name = raw.trim().replace(QUOTES, "").lowercase()
        if (name.isEmpty()) continue
        if (name in SERIF || (name.contains("serif") && !name.contains("sans"))) return "serif"
        if (name in MONO || name.contains("mono")) return "monospace"
        if (name in SANS || name.contains("sans") || name == "system-ui" || name.startsWith("-apple") || name == "ui-sans-serif") return null
        if (name == "material icons" || name == "materialicons") return "icons"
        return raw.trim().replace(QUOTES, "")
    }
    return null
}

/** `CSSProperties.createTextStyle` — the text part of a resolved style. */
fun textStyleFromCss(style: CSSStyle?): TextStyle? {
    if (style == null) return null
    val d = style.textDecoration
    return TextStyle(
        color = style.color,
        fontSize = style.fontSize,
        fontWeight = style.fontWeight,
        italic = style.fontStyle?.let { it == "italic" },
        fontFamily = style.fontFamily?.let { resolveFontFamily(it) ?: "" },
        letterSpacing = style.letterSpacing,
        wordSpacing = style.wordSpacing,
        height = style.lineHeight,
        heightPx = style.lineHeightPx,
        decoration = d?.let { (if (it.underline) 1 else 0) or (if (it.overline) 2 else 0) or (if (it.lineThrough) 4 else 0) },
        decorationColor = style.textDecorationColor,
        decorationStyle = style.textDecorationStyle,
        decorationThickness = style.textDecorationThickness,
        shadows = style.textShadow,
        textTransform = style.textTransform,
    )
}

/** Resolve an inheritable style into the platform spec. */
fun TextStyle.toSpec(textScale: Double = 1.0): TextStyleSpec {
    val m = TextStyle.DEFAULT.merge(this)
    val fontSize = (m.fontSize ?: 14.0) * textScale
    var height = m.height
    if (m.heightPx != null && fontSize > 0) height = m.heightPx * textScale / fontSize
    return TextStyleSpec(
        color = m.color ?: M3.onSurface,
        fontSize = fontSize,
        fontWeight = m.fontWeight ?: 400,
        italic = m.italic == true,
        fontFamily = if (m.fontFamily == "") null else m.fontFamily,
        letterSpacing = m.letterSpacing ?: 0.0,
        wordSpacing = m.wordSpacing ?: 0.0,
        height = height,
        decoration = m.decoration ?: 0,
        decorationColor = m.decorationColor,
        decorationStyle = m.decorationStyle,
        decorationThickness = m.decorationThickness,
        shadows = m.shadows,
        background = m.background,
        baselineShift = m.baselineShift ?: 0.0,
    )
}

private val CAPITALIZE = Regex("(^|\\s|[-(\\[\"'])(\\p{L})")

/** CSS `text-transform`. */
fun applyTextTransform(text: String, transform: String?): String = when (transform) {
    "uppercase" -> text.uppercase()
    "lowercase" -> text.lowercase()
    "capitalize" -> CAPITALIZE.replace(text) { it.groupValues[1] + it.groupValues[2].uppercase() }
    else -> text
}
