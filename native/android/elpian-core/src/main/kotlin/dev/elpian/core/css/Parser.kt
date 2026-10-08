package dev.elpian.core.css

import dev.elpian.core.util.jsString
import dev.elpian.core.util.parseFloatPrefix
import dev.elpian.core.util.stableKey
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The CSS value parser — a port of `CSSParser` (flutter/lib/src/css/css_parser.dart),
 * line for line with css/parser.ts in the TypeScript core.
 *
 * `parse(map)` turns an inline / cascaded style map (camelCase or kebab-case
 * keys, numbers or CSS strings) into a resolved [CSSStyle]. Everything the
 * Flutter parser accepts gives the same result; the CSS string forms Flutter
 * drops (border / box-shadow / transform strings, multi-value radii, em/rem,
 * filters) are parsed as well.
 */
object CSSParser {
    private const val MAX_CACHE = 512
    private val cache = object : LinkedHashMap<String, CSSStyle>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, CSSStyle>?) = size > MAX_CACHE
    }

    private val VIEWPORT_KEYS = listOf("width", "height", "minWidth", "min-width", "maxWidth", "max-width", "minHeight", "min-height", "maxHeight", "max-height", "top", "right", "bottom", "left", "padding", "margin", "gap")
    private val VIEWPORT_UNITS = Regex("%|vw|vh|vmin|vmax|calc\\(|env\\(")

    @Synchronized
    fun parse(styleMap: Map<String, Any?>): CSSStyle {
        val viewportDependent = VIEWPORT_KEYS.any { k -> (styleMap[k] as? String)?.let { VIEWPORT_UNITS.containsMatchIn(it) } == true }
        val key = (if (viewportDependent) "g${CssEnvironment.generation}:" else "") + stableKey(styleMap)
        cache[key]?.let { return it }
        val style = parseUncached(styleMap)
        cache[key] = style
        return style
    }

    @Synchronized
    fun clearCache() = cache.clear()

    val cacheSize: Int @Synchronized get() = cache.size

    private val IMPORTANT = Regex("\\s*!\\s*important\\s*$", RegexOption.IGNORE_CASE)

    fun stripImportant(value: Any?): Any? = if (value is String && IMPORTANT.containsMatchIn(value)) value.replace(IMPORTANT, "").trim() else value
    fun isImportant(value: Any?): Boolean = value is String && Regex("!\\s*important\\s*$", RegexOption.IGNORE_CASE).containsMatchIn(value)

    // ------------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------------

    private fun pick(m: Map<String, Any?>, camel: String): Any? {
        m[camel]?.let { return it }
        val kebab = camel.replace(Regex("[A-Z]")) { "-" + it.value.lowercase() }
        return if (kebab == camel) null else m[kebab]
    }

    private fun str(v: Any?): String? = if (v == null) null else jsString(v)

    private fun pf(s: String?): Double = s?.let { parseFloatPrefix(it) } ?: Double.NaN

    private fun Double.finite(): Double? = if (isFinite()) this else null

    /** JavaScript `Number.parseInt(s, 10)`. */
    private fun jsParseInt(s: String): Int? = Regex("^\\s*[+-]?\\d+").find(s)?.value?.trim()?.toIntOrNull()

    private fun <T> expandFour(parts: List<T>): List<T> = when (parts.size) {
        1 -> listOf(parts[0], parts[0], parts[0], parts[0])
        2 -> listOf(parts[0], parts[1], parts[0], parts[1])
        3 -> listOf(parts[0], parts[1], parts[2], parts[1])
        else -> listOf(parts[0], parts[1], parts[2], parts[3])
    }

    private val WS = Regex("\\s+")
    private fun words(s: String): List<String> = s.trim().split(WS).filter { it.isNotEmpty() }

    // ------------------------------------------------------------------------
    // parse
    // ------------------------------------------------------------------------

    private fun parseUncached(m: Map<String, Any?>): CSSStyle {
        val s = CSSStyle()
        val fontSize = parseFontSize(pick(m, "fontSize"))

        // ---- sizing ----
        s.width = parseDimension(m["width"], true)
        s.height = parseDimension(m["height"], false)
        s.widthFactor = percentFactor(m["width"])
        s.heightFactor = percentFactor(m["height"])
        s.aspectRatio = parseAspectRatio(pick(m, "aspectRatio"))
        s.minWidth = parseDimension(pick(m, "minWidth"), true)
        s.maxWidth = parseDimension(pick(m, "maxWidth"), true)
        s.minHeight = parseDimension(pick(m, "minHeight"), false)
        s.maxHeight = parseDimension(pick(m, "maxHeight"), false)

        // ---- spacing ----
        val pad = parseEdgeInsetsFor(m, "padding", fontSize)
        s.padding = pad.insets
        s.paddingPercent = pad.percent
        val mar = parseEdgeInsetsFor(m, "margin", fontSize)
        s.margin = mar.insets
        s.marginPercent = mar.percent
        s.marginAuto = mar.auto

        // ---- positioning ----
        s.alignment = parseAlignment(m["alignment"])
        s.position = str(m["position"])
        s.top = parseDimension(m["top"], false)
        s.right = parseDimension(m["right"], true)
        s.bottom = parseDimension(m["bottom"], false)
        s.left = parseDimension(m["left"], true)
        s.zIndex = parseDouble(pick(m, "zIndex"))

        // ---- layout ----
        s.display = str(m["display"])?.trim()
        s.flexDirection = str(pick(m, "flexDirection"))
        s.justifyContent = str(pick(m, "justifyContent"))
        s.alignItems = str(pick(m, "alignItems"))
        s.alignContent = str(pick(m, "alignContent"))
        s.alignSelf = str(pick(m, "alignSelf"))
        parseFlexShorthand(m, s)
        s.flexWrap = str(pick(m, "flexWrap"))
        str(pick(m, "flexFlow"))?.takeIf { it.isNotEmpty() }?.let { flow ->
            for (token in flow.split(WS)) {
                if (token.startsWith("row") || token.startsWith("column")) { if (s.flexDirection == null) s.flexDirection = token }
                else if (token.startsWith("wrap") || token == "nowrap") { if (s.flexWrap == null) s.flexWrap = token }
            }
        }
        s.order = parseIntValue(m["order"])?.toDouble()
        val gap = str(m["gap"])
        if (gap != null && gap.trim().contains(' ')) {
            val parts = gap.trim().split(WS)
            s.rowGap = parseDouble(parts[0], fontSize)
            s.columnGap = parseDouble(parts.getOrNull(1), fontSize)
            s.gap = s.columnGap
        } else {
            s.gap = parseDouble(m["gap"], fontSize)
            s.rowGap = parseDouble(pick(m, "rowGap"), fontSize)
            s.columnGap = parseDouble(pick(m, "columnGap"), fontSize)
        }
        s.overflow = parseOverflow(m["overflow"])
        s.overflowX = parseOverflow(pick(m, "overflowX"))
        s.overflowY = parseOverflow(pick(m, "overflowY"))
        s.boxSizing = str(pick(m, "boxSizing"))

        // ---- grid ----
        s.gridTemplateColumns = str(pick(m, "gridTemplateColumns"))
        s.gridTemplateRows = str(pick(m, "gridTemplateRows"))
        s.gridTemplateAreas = str(pick(m, "gridTemplateAreas"))
        s.gridAutoColumns = str(pick(m, "gridAutoColumns"))
        s.gridAutoRows = str(pick(m, "gridAutoRows"))
        s.gridAutoFlow = str(pick(m, "gridAutoFlow"))
        s.gridColumnGap = parseDouble(pick(m, "gridColumnGap") ?: pick(m, "columnGap") ?: s.columnGap, fontSize)
        s.gridRowGap = parseDouble(pick(m, "gridRowGap") ?: pick(m, "rowGap") ?: s.rowGap, fontSize)
        s.gridGap = parseDouble(pick(m, "gridGap"), fontSize)
        s.gridColumn = str(pick(m, "gridColumn"))
        s.gridRow = str(pick(m, "gridRow"))
        s.gridArea = str(pick(m, "gridArea"))
        s.justifyItems = str(pick(m, "justifyItems"))
        s.justifySelf = str(pick(m, "justifySelf"))

        // ---- background ----
        val background = m["background"]
        val bgLayers = (background as? String)?.let { parseBackgroundShorthand(it) }
        s.backgroundColor = parseColor(pick(m, "backgroundColor")) ?: bgLayers?.color
        val bgImage = str(pick(m, "backgroundImage"))
        s.backgroundImage = if (!bgImage.isNullOrEmpty() && !isGradientValue(bgImage)) extractUrl(bgImage) else bgLayers?.image
        s.backgroundSize = parseBoxFit(pick(m, "backgroundSize"))
        s.backgroundSizePx = parseBackgroundSizePx(pick(m, "backgroundSize"))
        s.backgroundPosition = parseAlignment(pick(m, "backgroundPosition"))
        s.backgroundRepeat = str(pick(m, "backgroundRepeat"))
        val gradients = ArrayList<Gradient>()
        parseGradient(m["gradient"])?.let { gradients.add(it) }
        if (!bgImage.isNullOrEmpty() && isGradientValue(bgImage)) gradients.addAll(parseGradientLayers(bgImage))
        if (bgLayers != null) gradients.addAll(bgLayers.gradients)
        s.gradient = gradients.firstOrNull()
        s.gradientLayers = if (gradients.size > 1) gradients.subList(1, gradients.size).toList() else null
        s.gradientColors = parseColorList(pick(m, "gradientColors"))
        s.gradientStops = parseNumberList(pick(m, "gradientStops"))

        // ---- border ----
        s.borderColor = parseColor(pick(m, "borderColor"))
        s.borderWidth = parseDouble(pick(m, "borderWidth"), fontSize)
        s.borderStyle = str(pick(m, "borderStyle"))
        s.border = parseBorder(m, s, fontSize)
        val radius = parseBorderRadius(m, fontSize)
        s.borderRadius = radius.first
        s.borderRadiusPercent = radius.second
        s.outlineColor = parseColor(pick(m, "outlineColor"))
        s.outlineWidth = parseDouble(pick(m, "outlineWidth"), fontSize)
        s.outlineStyle = str(pick(m, "outlineStyle"))
        s.outlineOffset = parseDouble(pick(m, "outlineOffset"), fontSize)
        str(m["outline"])?.takeIf { it.isNotEmpty() }?.let { outline ->
            parseBorderSideString(outline, fontSize)?.let { side ->
                if (s.outlineColor == null) s.outlineColor = side.color
                if (s.outlineWidth == null) s.outlineWidth = side.width
                if (s.outlineStyle == null) s.outlineStyle = side.style.name
            }
        }

        // ---- text ----
        s.color = parseColor(m["color"])
        s.fontSize = fontSize
        s.fontWeight = parseFontWeight(pick(m, "fontWeight"))
        s.fontStyle = parseFontStyle(pick(m, "fontStyle"))
        s.fontFamily = str(pick(m, "fontFamily"))
        parseFontShorthand(m["font"], s)
        s.letterSpacing = parseDouble(pick(m, "letterSpacing"), fontSize ?: 16.0)
        s.wordSpacing = parseDouble(pick(m, "wordSpacing"), fontSize ?: 16.0)
        parseLineHeight(pick(m, "lineHeight"), s)
        s.textAlign = parseTextAlign(pick(m, "textAlign"))
        val deco = parseTextDecoration(pick(m, "textDecoration") ?: pick(m, "textDecorationLine"))
        s.textDecoration = deco.first
        s.textDecorationColor = parseColor(pick(m, "textDecorationColor")) ?: deco.second
        s.textDecorationStyle = str(pick(m, "textDecorationStyle")) ?: deco.third
        s.textDecorationThickness = parseDouble(pick(m, "textDecorationThickness"))
        s.textOverflow = parseTextOverflow(pick(m, "textOverflow"))
        s.textTransform = str(pick(m, "textTransform"))
        s.whiteSpace = str(pick(m, "whiteSpace"))
        val collapse = str(pick(m, "borderCollapse"))
        s.borderCollapse = if (collapse == "collapse" || collapse == "separate") collapse else null
        s.borderSpacing = parseDouble(pick(m, "borderSpacing"))
        s.verticalAlign = str(pick(m, "verticalAlign"))
        s.writingMode = str(pick(m, "writingMode"))
        s.wordBreak = str(pick(m, "wordBreak"))
        s.lineClamp = parseIntValue(pick(m, "lineClamp") ?: pick(m, "WebkitLineClamp") ?: m["-webkit-line-clamp"])?.toDouble()

        // ---- effects ----
        s.boxShadow = parseBoxShadow(pick(m, "boxShadow"))
        s.textShadow = parseTextShadow(pick(m, "textShadow"))
        s.transform = parseTransform(m["transform"])
        s.rotate = parseAngleDegrees(m["rotate"])
        val scaleRaw = m["scale"]
        if (scaleRaw is String && scaleRaw.trim().contains(' ')) {
            val parts = scaleRaw.trim().split(WS).map { pf(it) }
            s.scaleX = parts[0].finite()
            s.scaleY = parts.getOrNull(1)?.finite()
        } else s.scale = parseDouble(scaleRaw)
        if (s.scaleX == null) s.scaleX = parseDouble(pick(m, "scaleX"))
        if (s.scaleY == null) s.scaleY = parseDouble(pick(m, "scaleY"))
        s.translate = parseOffset(m["translate"]) ?: parseTranslateString(m["translate"])
        s.transformOrigin = parseAlignment(pick(m, "transformOrigin")) ?: (pick(m, "transformOrigin") as? String)?.let { parsePositionKeywords(it.trim().lowercase()) }
        s.opacity = parseDouble(m["opacity"])
        s.visible = m["visible"] as? Boolean
        s.visibility = str(m["visibility"])
        s.filter = parseFilter(m["filter"])
        s.backdropFilter = parseFilter(pick(m, "backdropFilter"))
        s.mixBlendMode = str(pick(m, "mixBlendMode"))

        // ---- interaction ----
        s.cursor = str(m["cursor"])
        s.pointerEvents = str(pick(m, "pointerEvents"))
        s.userSelect = str(pick(m, "userSelect"))
        s.touchAction = str(pick(m, "touchAction"))

        // ---- media / shape ----
        s.objectFit = parseBoxFit(pick(m, "objectFit"))
        s.objectPosition = parseAlignment(pick(m, "objectPosition"))
        s.clipBehavior = str(pick(m, "clipBehavior"))
        val shape = str(m["shape"])?.lowercase()
        s.shape = if (shape == "circle" || shape == "rectangle") shape else null

        // ---- transitions / animation ----
        s.transitionDuration = parseDuration(pick(m, "transitionDuration"))
        s.transitionCurve = normalizeCurve(pick(m, "transitionCurve") ?: pick(m, "transitionTimingFunction"))
        s.transitionProperty = str(pick(m, "transitionProperty"))
        s.transitionDelay = parseDuration(pick(m, "transitionDelay"))
        str(m["transition"])?.takeIf { it.isNotEmpty() }?.let { parseTransitionShorthand(it, s) }
        s.animationName = str(pick(m, "animationName"))
        s.animationDuration = parseDuration(pick(m, "animationDuration"))
        s.animationTimingFunction = str(pick(m, "animationTimingFunction"))
        s.animationDelay = parseDuration(pick(m, "animationDelay"))
        s.animationIterationCount = parseIntValue(pick(m, "animationIterationCount"))?.toDouble()
        s.animationDirection = str(pick(m, "animationDirection"))
        s.animationFillMode = str(pick(m, "animationFillMode"))
        s.animationPlayState = str(pick(m, "animationPlayState"))
        str(m["animation"])?.takeIf { it.isNotEmpty() }?.let { parseAnimationShorthand(it, s) }
        s.animateOnBuild = asBool(pick(m, "animateOnBuild"))
        s.staggerDelay = parseDuration(pick(m, "staggerDelay"))
        s.staggerChildren = parseIntValue(pick(m, "staggerChildren"))?.toDouble()
        s.animationFrom = parseDouble(pick(m, "animationFrom"))
        s.animationTo = parseDouble(pick(m, "animationTo"))
        s.slideBegin = parseOffset(pick(m, "slideBegin"))
        s.slideEnd = parseOffset(pick(m, "slideEnd"))
        s.scaleBegin = parseDouble(pick(m, "scaleBegin"))
        s.scaleEnd = parseDouble(pick(m, "scaleEnd"))
        s.rotationBegin = parseDouble(pick(m, "rotationBegin"))
        s.rotationEnd = parseDouble(pick(m, "rotationEnd"))
        s.fadeBegin = parseDouble(pick(m, "fadeBegin"))
        s.fadeEnd = parseDouble(pick(m, "fadeEnd"))
        s.colorBegin = parseColor(pick(m, "colorBegin"))
        s.colorEnd = parseColor(pick(m, "colorEnd"))
        s.paddingBegin = parseEdgeInsets(pick(m, "paddingBegin"))
        s.paddingEnd = parseEdgeInsets(pick(m, "paddingEnd"))
        s.alignmentBegin = parseAlignment(pick(m, "alignmentBegin"))
        s.alignmentEnd = parseAlignment(pick(m, "alignmentEnd"))
        s.shimmerBaseColor = parseColor(pick(m, "shimmerBaseColor"))
        s.shimmerHighlightColor = parseColor(pick(m, "shimmerHighlightColor"))
        s.animationAutoReverse = asBool(pick(m, "animationAutoReverse"))
        s.animationRepeat = asBool(pick(m, "animationRepeat"))
        s.keyframes = parseKeyframes(m["keyframes"])
        return s
    }

    // ------------------------------------------------------------------------
    // numbers and lengths
    // ------------------------------------------------------------------------

    private fun asBool(v: Any?): Boolean? = when (v) {
        is Boolean -> v
        "true" -> true
        "false" -> false
        else -> null
    }

    private val VIEWPORT_LEN = Regex("^-?[\\d.]+(vw|vh|vmin|vmax)$")
    private val NON_NUMERIC = Regex("[^0-9.\\-eE+]")

    /** Flutter's `parseDouble`, with `em` (× [emBase]) and `rem` honoured. */
    fun parseDouble(value: Any?, emBase: Double? = null): Double? {
        when (value) {
            null -> return null
            is Number -> return value.toDouble().finite()
            is Boolean -> return null
        }
        val raw = jsString(stripImportant(value)).trim()
        if (raw.isEmpty()) return null
        val lower = raw.lowercase()
        if (lower.endsWith("rem")) return pf(lower).finite()?.let { it * CssEnvironment.rootFontSize }
        if (lower.endsWith("em")) return pf(lower).finite()?.let { it * (emBase ?: CssEnvironment.rootFontSize) }
        if (VIEWPORT_LEN.matches(lower)) return resolveLength(lower, true)
        val n = pf(raw.replace(NON_NUMERIC, ""))
        if (!n.isFinite()) return pf(raw.replace(Regex("[^0-9.\\-]"), "")).finite()
        return n
    }

    /** `parseInt` of the TypeScript parser (`infinite` → -1). */
    fun parseIntValue(value: Any?): Int? = when (value) {
        null -> null
        is Number -> value.toDouble().let { if (it >= 0) Math.floor(it) else Math.ceil(it) }.toInt()
        is String -> {
            val t = value.trim().lowercase()
            if (t == "infinite") -1 else jsParseInt(t)
        }
        else -> null
    }

    private val FONT_KEYWORDS = mapOf("xx-small" to 9.0, "x-small" to 10.0, "small" to 13.0, "medium" to 16.0, "large" to 18.0, "x-large" to 24.0, "xx-large" to 32.0, "xxx-large" to 48.0)

    fun parseFontSize(value: Any?): Double? {
        if (value == null) return null
        if (value is String) {
            val t = value.trim().lowercase()
            FONT_KEYWORDS[t]?.let { return it }
            if (t.endsWith("%")) return pf(t).finite()?.let { it / 100 * CssEnvironment.rootFontSize }
        }
        return parseDouble(value)
    }

    private fun percentFactor(value: Any?): Double? {
        if (value !is String) return null
        val raw = jsString(stripImportant(value)).trim()
        if (!raw.endsWith("%")) return null
        return pf(raw.dropLast(1)).finite()?.let { it / 100 }
    }

    private val MATH_FN = Regex("^(min|max|clamp)\\(")

    fun parseDimension(value: Any?, isWidth: Boolean): Double? {
        when (value) {
            null -> return null
            is Number -> return value.toDouble().finite()
            !is String -> return null
        }
        val raw = jsString(stripImportant(value)).trim()
        if (raw in setOf("", "auto", "none", "fit-content", "max-content", "min-content")) return null
        if (raw.contains("calc(")) return evalCalc(raw, isWidth)
        if (MATH_FN.containsMatchIn(raw)) return evalMathFn(raw, isWidth)
        return resolveLength(raw, isWidth)
    }

    private fun resolveLength(raw: String, isWidth: Boolean): Double? {
        val t = raw.trim().lowercase()
        if (t.isEmpty()) return null
        if (t.startsWith("env(")) return resolveEnv(t, isWidth)
        if (t.startsWith("var(")) return null
        if (t.contains('*') || t.contains('/') || t.contains('(')) return null
        val n = pf(t.replace(NON_NUMERIC, "")).finite() ?: return null
        val w = CssEnvironment.viewportWidth
        val h = CssEnvironment.viewportHeight
        return when {
            t.endsWith("vmin") -> n / 100 * min(w, h)
            t.endsWith("vmax") -> n / 100 * max(w, h)
            t.endsWith("vw") -> n / 100 * w
            t.endsWith("vh") || t.endsWith("dvh") || t.endsWith("svh") || t.endsWith("lvh") -> n / 100 * h
            t.endsWith("%") -> n / 100 * (if (isWidth) w else h)
            t.endsWith("rem") -> n * CssEnvironment.rootFontSize
            t.endsWith("em") -> n * CssEnvironment.rootFontSize
            t.endsWith("pt") -> n * 4 / 3
            else -> n
        }
    }

    private fun evalCalc(raw: String, isWidth: Boolean): Double? {
        val m = Regex("^calc\\(([\\s\\S]*)\\)$").find(raw.trim())
        val body = m?.groupValues?.get(1)?.trim()
        if (body.isNullOrEmpty()) return null
        return evalSum(body, isWidth)
    }

    private fun evalSum(body: String, isWidth: Boolean): Double? {
        var sum = 0.0
        var sign = 1.0
        var start = 0
        var depth = 0
        for (i in body.indices) {
            val c = body[i]
            if (c == '(') depth++
            else if (c == ')') depth--
            else if (depth == 0 && (c == '+' || c == '-') && i > 0 && body[i - 1] == ' ' && i + 1 < body.length && body[i + 1] == ' ') {
                val v = evalProduct(body.substring(start, i).trim(), isWidth) ?: return null
                sum += sign * v
                sign = if (c == '+') 1.0 else -1.0
                start = i + 1
            }
        }
        val last = evalProduct(body.substring(start).trim(), isWidth) ?: return null
        return sum + sign * last
    }

    private val MUL = Regex("^(.+?)\\s*([*/])\\s*(.+)$")

    private fun evalProduct(term: String, isWidth: Boolean): Double? {
        val mul = MUL.find(term)
        if (mul != null && !term.startsWith("env(") && !term.startsWith("calc(")) {
            val left = evalAtom(mul.groupValues[1].trim(), isWidth) ?: return null
            val right = evalAtom(mul.groupValues[3].trim(), isWidth) ?: return null
            return if (mul.groupValues[2] == "*") left * right else if (right == 0.0) null else left / right
        }
        return evalAtom(term, isWidth)
    }

    private fun evalAtom(atom: String, isWidth: Boolean): Double? {
        val t = atom.trim()
        if (t.startsWith("(") && t.endsWith(")")) return evalSum(t.substring(1, t.length - 1).trim(), isWidth)
        if (t.startsWith("calc(")) return evalCalc(t, isWidth)
        if (MATH_FN.containsMatchIn(t)) return evalMathFn(t, isWidth)
        return resolveLength(t, isWidth)
    }

    private fun evalMathFn(raw: String, isWidth: Boolean): Double? {
        val m = Regex("^(min|max|clamp)\\(([\\s\\S]*)\\)$").find(raw.trim()) ?: return null
        val args = splitTopLevel(m.groupValues[2], ",").map { evalSum(it.trim(), isWidth) }
        if (args.any { it == null }) return null
        val nums = args.map { it!! }
        return when (m.groupValues[1]) {
            "min" -> nums.minOrNull()
            "max" -> nums.maxOrNull()
            else -> if (nums.size != 3) null else min(max(nums[1], nums[0]), nums[2])
        }
    }

    private fun resolveEnv(raw: String, isWidth: Boolean): Double? {
        val m = Regex("^env\\(\\s*([a-z-]+)\\s*(?:,\\s*([^)]+))?\\)$").find(raw.trim()) ?: return null
        val insets = CssEnvironment.safeArea
        return when (m.groupValues[1]) {
            "safe-area-inset-top" -> insets.top
            "safe-area-inset-right" -> insets.right
            "safe-area-inset-bottom" -> insets.bottom
            "safe-area-inset-left" -> insets.left
            else -> if (m.groupValues[2].isNotEmpty()) resolveLength(m.groupValues[2].trim(), isWidth) ?: 0.0 else 0.0
        }
    }

    private fun parseAspectRatio(value: Any?): Double? {
        if (value is Number) return value.toDouble().takeIf { it > 0 }
        if (value !is String) return null
        val raw = value.trim().lowercase()
        if (raw.isEmpty() || raw == "auto") return null
        val parts = raw.split('/')
        if (parts.size == 2) {
            val w = pf(parts[0])
            val h = pf(parts[1])
            return if (w.isFinite() && h.isFinite() && h != 0.0) w / h else null
        }
        val v = pf(raw)
        return if (v.isFinite() && v > 0) v else null
    }

    private fun parseFlexShorthand(m: Map<String, Any?>, s: CSSStyle) {
        val flex = m["flex"]
        s.flexGrow = parseDouble(pick(m, "flexGrow"))
        s.flexShrink = parseDouble(pick(m, "flexShrink"))
        s.flexBasis = str(pick(m, "flexBasis"))
        if (flex == null) return
        if (flex is Number) {
            s.flex = flex.toDouble()
            return
        }
        val t = jsString(flex).trim().lowercase()
        if (t == "none") {
            if (s.flexShrink == null) s.flexShrink = 0.0
            return
        }
        if (t == "auto") {
            s.flex = 1.0
            if (s.flexBasis == null) s.flexBasis = "auto"
            return
        }
        val parts = t.split(WS)
        val grow = pf(parts[0])
        if (grow.isFinite()) {
            s.flex = grow
            if (parts.size > 1) {
                val shrink = pf(parts[1])
                if (shrink.isFinite()) { if (s.flexShrink == null) s.flexShrink = shrink } else if (s.flexBasis == null) s.flexBasis = parts[1]
            }
            if (parts.size > 2 && s.flexBasis == null) s.flexBasis = parts[2]
        } else if (s.flexBasis == null) s.flexBasis = parts[0]
    }

    // ------------------------------------------------------------------------
    // edge insets, alignment, offsets
    // ------------------------------------------------------------------------

    fun parseEdgeInsets(value: Any?, emBase: Double? = null): EdgeInsets? {
        when (value) {
            null -> return null
            is Map<*, *> -> return EdgeInsets(
                parseDouble(value["top"], emBase) ?: 0.0,
                parseDouble(value["right"], emBase) ?: 0.0,
                parseDouble(value["bottom"], emBase) ?: 0.0,
                parseDouble(value["left"], emBase) ?: 0.0,
            )
            is List<*> -> {
                val nums = value.map { parseDouble(it, emBase) ?: 0.0 }
                if (nums.isEmpty()) return null
                val f = expandFour(nums)
                return EdgeInsets(f[0], f[1], f[2], f[3])
            }
            is Number, is String -> {
                val parts = words(jsString(stripImportant(value)))
                if (parts.isEmpty() || parts.size > 4) return null
                val nums = parts.map { if (it == "auto") 0.0 else parseLengthToken(it, emBase) ?: 0.0 }
                val f = expandFour(nums)
                return EdgeInsets(f[0], f[1], f[2], f[3])
            }
            else -> return null
        }
    }

    private val DYN_TOKEN = Regex("vw$|vh$|vmin$|vmax$|^calc\\(|^env\\(")

    private fun parseLengthToken(token: String, emBase: Double?): Double? {
        val t = token.trim().lowercase()
        if (t.endsWith("%")) return null
        if (DYN_TOKEN.containsMatchIn(t)) return parseDimension(t, true)
        return parseDouble(t, emBase)
    }

    private class InsetsResult(val insets: EdgeInsets?, val percent: SidePercents?, val auto: MarginAuto?)

    private val SIDES = listOf("top", "right", "bottom", "left")

    private fun parseEdgeInsetsFor(m: Map<String, Any?>, base: String, emBase: Double?): InsetsResult {
        val percent = HashMap<String, Percent>()
        val auto = HashMap<String, Boolean>()
        val values = HashMap<String, Double?>()
        var any = false
        val shorthand = m[base]
        if (shorthand != null) {
            if (shorthand is Map<*, *> || shorthand is List<*>) {
                parseEdgeInsets(shorthand, emBase)?.let { e ->
                    values["top"] = e.top; values["right"] = e.right; values["bottom"] = e.bottom; values["left"] = e.left
                    any = true
                }
            } else {
                val parts = words(jsString(stripImportant(shorthand)))
                if (parts.isNotEmpty() && parts.size <= 4) {
                    val four = expandFour(parts)
                    SIDES.forEachIndexed { i, side -> applyInsetToken(four[i], side, values, percent, auto, emBase, false) }
                    any = true
                }
            }
        }
        for (side in SIDES) {
            val cap = side.replaceFirstChar { it.uppercase() }
            val raw = m["$base$cap"] ?: m["$base-$side"]
            if (raw != null) {
                applyInsetToken(jsString(stripImportant(raw)), side, values, percent, auto, emBase, false)
                any = true
            }
        }
        val x = m["${base}X"] ?: m["${base}Inline"] ?: m["$base-inline"]
        val y = m["${base}Y"] ?: m["${base}Block"] ?: m["$base-block"]
        if (x != null) {
            val parts = jsString(x).trim().split(WS)
            applyInsetToken(parts[0], "left", values, percent, auto, emBase, true)
            applyInsetToken(parts.getOrNull(1) ?: parts[0], "right", values, percent, auto, emBase, true)
            any = true
        }
        if (y != null) {
            val parts = jsString(y).trim().split(WS)
            applyInsetToken(parts[0], "top", values, percent, auto, emBase, true)
            applyInsetToken(parts.getOrNull(1) ?: parts[0], "bottom", values, percent, auto, emBase, true)
            any = true
        }
        if (!any) return InsetsResult(null, null, null)
        return InsetsResult(
            EdgeInsets(values["top"] ?: 0.0, values["right"] ?: 0.0, values["bottom"] ?: 0.0, values["left"] ?: 0.0),
            if (percent.isEmpty()) null else SidePercents(percent["top"], percent["right"], percent["bottom"], percent["left"]),
            if (auto.values.any { it }) MarginAuto(auto["top"] == true, auto["right"] == true, auto["bottom"] == true, auto["left"] == true) else null,
        )
    }

    private fun applyInsetToken(token: String, side: String, values: MutableMap<String, Double?>, percent: MutableMap<String, Percent>, auto: MutableMap<String, Boolean>, emBase: Double?, onlyIfUnset: Boolean) {
        if (onlyIfUnset && values[side] != null) return
        val t = token.trim().lowercase()
        if (t == "auto") {
            auto[side] = true
            values[side] = 0.0
            percent.remove(side)
            return
        }
        auto[side] = false
        if (t.endsWith("%")) {
            val n = pf(t)
            if (n.isFinite()) {
                percent[side] = Percent(n)
                values[side] = 0.0
            }
            return
        }
        percent.remove(side)
        values[side] = parseLengthToken(t, emBase) ?: 0.0
    }

    private val ALIGNMENTS = mapOf(
        "center" to Alignment.center,
        "topleft" to Alignment.topLeft, "top-left" to Alignment.topLeft,
        "topcenter" to Alignment.topCenter, "top-center" to Alignment.topCenter,
        "topright" to Alignment.topRight, "top-right" to Alignment.topRight,
        "centerleft" to Alignment.centerLeft, "center-left" to Alignment.centerLeft,
        "centerright" to Alignment.centerRight, "center-right" to Alignment.centerRight,
        "bottomleft" to Alignment.bottomLeft, "bottom-left" to Alignment.bottomLeft,
        "bottomcenter" to Alignment.bottomCenter, "bottom-center" to Alignment.bottomCenter,
        "bottomright" to Alignment.bottomRight, "bottom-right" to Alignment.bottomRight,
    )

    fun parseAlignment(value: Any?): Alignment? = when (value) {
        null -> null
        is String -> {
            val key = value.trim().lowercase()
            ALIGNMENTS[key] ?: parsePositionKeywords(key)
        }
        is Map<*, *> -> Alignment(parseDouble(value["x"]) ?: 0.0, parseDouble(value["y"]) ?: 0.0)
        else -> null
    }

    fun parsePositionKeywords(key: String): Alignment? {
        val tokens = words(key)
        if (tokens.isEmpty() || tokens.size > 2) return null
        var x: Double? = null
        var y: Double? = null
        var centers = 0
        for (t in tokens) {
            when {
                t == "left" -> x = -1.0
                t == "right" -> x = 1.0
                t == "top" -> y = -1.0
                t == "bottom" -> y = 1.0
                t.endsWith("%") -> {
                    val n = pf(t).finite() ?: return null
                    val v = n / 50 - 1
                    if (x == null) x = v else y = v
                }
                t == "center" -> centers++
                else -> return null
            }
        }
        repeat(centers) { if (x == null) x = 0.0 else if (y == null) y = 0.0 }
        if (x == null && y == null) return null
        return Alignment(x ?: 0.0, y ?: 0.0)
    }

    fun parseOffset(value: Any?): Offset? = when {
        value is List<*> && value.size == 2 -> Offset(parseDouble(value[0]) ?: 0.0, parseDouble(value[1]) ?: 0.0)
        value is Map<*, *> -> Offset(parseDouble(value["x"] ?: value["dx"]) ?: 0.0, parseDouble(value["y"] ?: value["dy"]) ?: 0.0)
        else -> null
    }

    private fun parseTranslateString(value: Any?): Offset? {
        if (value !is String) return null
        val parts = value.trim().split(WS)
        val dx = parseDouble(parts[0]) ?: return null
        return Offset(dx, parseDouble(parts.getOrNull(1)) ?: 0.0)
    }

    // ------------------------------------------------------------------------
    // enumerations
    // ------------------------------------------------------------------------

    private val FONT_WEIGHTS = mapOf(
        "thin" to 100, "hairline" to 100, "extralight" to 200, "extra-light" to 200, "ultralight" to 200,
        "light" to 300, "normal" to 400, "regular" to 400, "medium" to 500, "semibold" to 600, "semi-bold" to 600,
        "demibold" to 600, "bold" to 700, "extrabold" to 800, "extra-bold" to 800, "black" to 900, "heavy" to 900,
        "bolder" to 700, "lighter" to 300,
    )

    fun parseFontWeight(value: Any?): Int? {
        if (value == null) return null
        if (value is Number) return ((value.toDouble() / 100).toInt().coerceIn(1, 9)) * 100
        val t = jsString(value).trim().lowercase()
        FONT_WEIGHTS[t]?.let { return it }
        val n = jsParseInt(if (t.startsWith("w")) t.substring(1) else t) ?: return null
        return (n / 100).coerceIn(1, 9) * 100
    }

    private fun parseFontStyle(value: Any?): String? {
        if (value !is String) return null
        return when (value.trim().lowercase()) {
            "italic", "oblique" -> "italic"
            "normal" -> "normal"
            else -> null
        }
    }

    private val FONT_SHORTHAND = Regex("^\\s*((?:(?:italic|oblique|normal|bold|bolder|lighter|small-caps|\\d{3})\\s+)*)([\\d.]+(?:px|em|rem|pt|%)?)(?:\\s*/\\s*([\\d.]+(?:px|em|rem|%)?))?\\s+(.+)$", RegexOption.IGNORE_CASE)

    private fun parseFontShorthand(value: Any?, s: CSSStyle) {
        if (value !is String) return
        val m = FONT_SHORTHAND.find(value) ?: return
        for (token in words(m.groupValues[1])) {
            val lower = token.lowercase()
            if (lower == "italic" || lower == "oblique") { if (s.fontStyle == null) s.fontStyle = "italic" }
            else {
                val w = parseFontWeight(lower)
                if (w != null && lower != "normal" && s.fontWeight == null) s.fontWeight = w
            }
        }
        if (s.fontSize == null) s.fontSize = parseFontSize(m.groupValues[2])
        if (m.groupValues[3].isNotEmpty()) parseLineHeight(m.groupValues[3], s)
        if (s.fontFamily == null) s.fontFamily = m.groupValues[4].trim()
    }

    private fun parseLineHeight(value: Any?, s: CSSStyle) {
        if (value == null) return
        if (value is Number) {
            s.lineHeight = value.toDouble()
            return
        }
        val t = jsString(stripImportant(value)).trim().lowercase()
        when {
            t == "normal" -> return
            Regex("^[\\d.]+$").matches(t) -> s.lineHeight = pf(t)
            t.endsWith("%") -> s.lineHeight = pf(t) / 100
            t.endsWith("em") && !t.endsWith("rem") -> s.lineHeight = pf(t)
            else -> parseDouble(t)?.let { s.lineHeightPx = it }
        }
    }

    private fun parseTextAlign(value: Any?): String? {
        if (value !is String) return null
        val t = value.trim().lowercase()
        return if (t in setOf("left", "right", "center", "justify", "start", "end")) t else null
    }

    private fun parseTextDecoration(value: Any?): Triple<TextDecoration?, Color?, String?> {
        if (value !is String) return Triple(null, null, null)
        var underline = false
        var overline = false
        var through = false
        var color: Color? = null
        var style: String? = null
        var known = false
        for (token in splitTopLevel(value.trim().lowercase(), " ").filter { it.isNotEmpty() }) {
            when (token) {
                "underline" -> { underline = true; known = true }
                "overline" -> { overline = true; known = true }
                "line-through", "linethrough" -> { through = true; known = true }
                "none" -> known = true
                "solid", "double", "dotted", "dashed", "wavy" -> style = token
                else -> color = parseColor(token) ?: color
            }
        }
        return Triple(if (known) TextDecoration(underline, overline, through) else null, color, style)
    }

    private fun parseTextOverflow(value: Any?): TextOverflow? {
        if (value !is String) return null
        return when (value.trim().lowercase()) {
            "ellipsis" -> TextOverflow.ellipsis
            "clip" -> TextOverflow.clip
            "fade" -> TextOverflow.fade
            "visible" -> TextOverflow.visible
            else -> null
        }
    }

    private fun parseOverflow(value: Any?): String? {
        if (value !is String) return null
        return when (value.trim().lowercase().split(WS)[0]) {
            "visible" -> "visible"
            "hidden" -> "hidden"
            "clip" -> "clip"
            "auto", "scroll", "overlay" -> "scroll"
            else -> null
        }
    }

    private val BOX_FITS = mapOf(
        "fill" to BoxFit.fill, "contain" to BoxFit.contain, "cover" to BoxFit.cover, "fitwidth" to BoxFit.fitWidth, "fit-width" to BoxFit.fitWidth,
        "fitheight" to BoxFit.fitHeight, "fit-height" to BoxFit.fitHeight, "none" to BoxFit.none, "scaledown" to BoxFit.scaleDown, "scale-down" to BoxFit.scaleDown,
        "100% 100%" to BoxFit.fill,
    )

    fun parseBoxFit(value: Any?): BoxFit? = (value as? String)?.let { BOX_FITS[it.trim().lowercase()] }

    private fun parseBackgroundSizePx(value: Any?): SizePx? {
        if (value !is String) return null
        val t = value.trim().lowercase()
        if (BOX_FITS.containsKey(t)) return null
        val parts = t.split(WS)
        val w = if (parts[0] == "auto") null else parseDouble(parts[0])
        val h = if (parts.size > 1) (if (parts[1] == "auto") null else parseDouble(parts[1])) else null
        if (w == null && h == null) return null
        return SizePx(w, h)
    }

    // ------------------------------------------------------------------------
    // borders and radii
    // ------------------------------------------------------------------------

    private fun styleName(s: String): BorderStyleName? = BorderStyleName.entries.firstOrNull { it.name == s }

    private fun parseBorderSideMap(value: Any?, emBase: Double?): BorderSide? {
        if (value !is Map<*, *>) return null
        val style = jsString(value["style"] ?: "solid").lowercase()
        return BorderSide(parseDouble(value["width"], emBase) ?: 1.0, parseColor(value["color"]) ?: Colors.black, styleName(style) ?: BorderStyleName.solid)
    }

    fun parseBorderSideString(value: String, emBase: Double?): BorderSide? {
        val t = jsString(stripImportant(value)).trim()
        if (t.isEmpty()) return null
        if (Regex("^(none|0|hidden)$", RegexOption.IGNORE_CASE).matches(t)) return BorderSide(0.0, Colors.black, BorderStyleName.none)
        var width: Double? = null
        var style: BorderStyleName? = null
        var color: Color? = null
        for (token in splitTopLevel(t, " ").filter { it.isNotEmpty() }) {
            val lower = token.lowercase()
            when {
                styleName(lower) != null || lower in setOf("groove", "ridge", "inset", "outset") -> style = styleName(lower) ?: BorderStyleName.solid
                lower == "thin" -> width = 1.0
                lower == "medium" -> width = 3.0
                lower == "thick" -> width = 5.0
                Regex("^-?[\\d.]").containsMatchIn(lower) -> width = parseDouble(lower, emBase)
                else -> color = parseColor(token) ?: color
            }
        }
        return BorderSide(width ?: 3.0, color ?: Colors.black, style ?: BorderStyleName.none)
    }

    private fun parseBorderSideAny(value: Any?, emBase: Double?): BorderSide? = when (value) {
        null -> null
        is Map<*, *> -> parseBorderSideMap(value, emBase)
        else -> parseBorderSideString(jsString(value), emBase)
    }

    private fun parseBorder(m: Map<String, Any?>, s: CSSStyle, emBase: Double?): Border? {
        val none = BorderSide.NONE
        val sides = arrayOfNulls<BorderSide>(4) // top, right, bottom, left
        var any = false
        val all = m["border"]
        if (all != null) {
            if (all is Map<*, *>) {
                if (all.containsKey("top") || all.containsKey("right") || all.containsKey("bottom") || all.containsKey("left")) {
                    SIDES.forEachIndexed { i, n -> sides[i] = parseBorderSideMap(all[n], emBase) ?: none }
                } else {
                    val side = parseBorderSideMap(all, emBase)
                    for (i in 0 until 4) sides[i] = side
                }
                any = true
            } else {
                parseBorderSideString(jsString(all), emBase)?.let { side ->
                    for (i in 0 until 4) sides[i] = side
                    any = true
                }
            }
        }
        SIDES.forEachIndexed { i, sideName ->
            val cap = sideName.replaceFirstChar { it.uppercase() }
            val raw = m["border$cap"] ?: m["border-$sideName"]
            var side = if (raw != null) parseBorderSideAny(raw, emBase) else null
            val width = parseDouble(m["border${cap}Width"] ?: m["border-$sideName-width"], emBase)
            val color = parseColor(m["border${cap}Color"] ?: m["border-$sideName-color"])
            val styleRaw = m["border${cap}Style"] ?: m["border-$sideName-style"]
            if (width != null || color != null || styleRaw != null) {
                val base = side ?: sides[i]
                side = BorderSide(
                    width ?: base?.width ?: 1.0,
                    color ?: base?.color ?: s.borderColor ?: Colors.black,
                    if (styleRaw != null) styleName(jsString(styleRaw).lowercase()) ?: BorderStyleName.solid else base?.style ?: BorderStyleName.solid,
                )
            }
            if (side != null) {
                any = true
                sides[i] = side
            }
        }
        val widthRaw = pick(m, "borderWidth")
        val colorRaw = pick(m, "borderColor")
        val styleRaw = pick(m, "borderStyle")
        fun multi(v: Any?) = v is String && splitTopLevel(v.trim(), " ").filter { it.isNotEmpty() }.size > 1
        fun widthsOf(v: Any) = expandFour(splitTopLevel(jsString(v).trim(), " ").filter { it.isNotEmpty() }.map { parseDouble(it, emBase) ?: 0.0 })
        fun colorsOf(v: Any) = expandFour(splitTopLevel(jsString(v).trim(), " ").filter { it.isNotEmpty() }.map { parseColor(it) ?: Colors.black })
        fun stylesOf(v: Any) = expandFour(jsString(v).trim().split(WS).map { styleName(it.lowercase()) ?: BorderStyleName.solid })
        if (any && (widthRaw != null || colorRaw != null || styleRaw != null)) {
            val widths = widthRaw?.let { widthsOf(it) }
            val colors = colorRaw?.let { colorsOf(it) }
            val styles = styleRaw?.let { stylesOf(it) }
            for (i in 0 until 4) {
                val side = sides[i] ?: continue
                sides[i] = BorderSide(widths?.get(i) ?: side.width, colors?.get(i) ?: side.color, styles?.get(i) ?: side.style)
            }
        } else if (!any && (multi(widthRaw) || multi(colorRaw) || multi(styleRaw)) && (widthRaw != null || styleRaw != null)) {
            val widths = widthsOf(widthRaw ?: "1")
            val colors = colorsOf(colorRaw ?: "#000")
            val styles = stylesOf(styleRaw ?: "solid")
            for (i in 0 until 4) sides[i] = BorderSide(widths[i], colors[i], styles[i])
            any = true
        }
        if (!any) return null
        return Border(sides[0] ?: none, sides[1] ?: none, sides[2] ?: none, sides[3] ?: none)
    }

    private fun parseBorderRadius(m: Map<String, Any?>, emBase: Double?): Pair<BorderRadius?, BorderRadius?> {
        val px = DoubleArray(4)
        val pct = DoubleArray(4)
        var anyPx = false
        var anyPct = false
        fun assign(i: Int, token: Any?) {
            if (token == null) return
            if (token is String && token.trim().endsWith("%")) {
                val n = pf(token)
                if (n.isFinite()) {
                    pct[i] = n
                    px[i] = 0.0
                    anyPct = true
                }
                return
            }
            val n = parseDouble(token, emBase)
            if (n != null) {
                px[i] = n
                pct[i] = 0.0
                anyPx = true
            }
        }
        val corners = listOf("topLeft", "topRight", "bottomRight", "bottomLeft")
        val all = pick(m, "borderRadius")
        if (all != null) {
            when (all) {
                is Map<*, *> -> corners.forEachIndexed { i, c -> assign(i, all[c] ?: all[c.replace(Regex("[A-Z]")) { "-" + it.value.lowercase() }]) }
                is Number -> for (i in 0 until 4) assign(i, all)
                else -> {
                    val horizontal = words(jsString(stripImportant(all)).split('/')[0])
                    if (horizontal.isNotEmpty()) {
                        val four = expandFour(horizontal)
                        for (i in 0 until 4) assign(i, four[i])
                    }
                }
            }
        }
        listOf("borderTopLeftRadius", "borderTopRightRadius", "borderBottomRightRadius", "borderBottomLeftRadius").forEachIndexed { i, k -> assign(i, pick(m, k)) }
        return Pair(
            if (anyPx) BorderRadius(px[0], px[1], px[2], px[3]) else null,
            if (anyPct) BorderRadius(pct[0], pct[1], pct[2], pct[3]) else null,
        )
    }

    // ------------------------------------------------------------------------
    // shadows
    // ------------------------------------------------------------------------

    fun parseBoxShadow(value: Any?): List<BoxShadow>? {
        when (value) {
            null -> return null
            is List<*> -> return value.map { shadow ->
                when (shadow) {
                    is Map<*, *> -> {
                        val offset = parseOffset(shadow["offset"]) ?: Offset(parseDouble(shadow["dx"] ?: shadow["x"]) ?: 0.0, parseDouble(shadow["dy"] ?: shadow["y"]) ?: 0.0)
                        BoxShadow(
                            parseColor(shadow["color"]) ?: 0x42000000,
                            offset.dx,
                            offset.dy,
                            parseDouble(shadow["blurRadius"] ?: shadow["blur"]) ?: 0.0,
                            parseDouble(shadow["spreadRadius"] ?: shadow["spread"]) ?: 0.0,
                            shadow["inset"] == true,
                        )
                    }
                    is String -> parseShadowString(shadow) ?: zeroShadow()
                    else -> zeroShadow()
                }
            }
            is Map<*, *> -> return parseBoxShadow(listOf(value))
            is String -> {
                val t = value.trim()
                if (t.isEmpty() || t == "none") return null
                val out = splitTopLevel(t, ",").mapNotNull { parseShadowString(it) }
                return out.ifEmpty { null }
            }
            else -> return null
        }
    }

    private fun zeroShadow() = BoxShadow(Colors.black, 0.0, 0.0, 0.0, 0.0)

    private fun parseShadowString(raw: String): BoxShadow? {
        val lengths = ArrayList<Double>()
        var color: Color? = null
        var inset = false
        for (token in splitTopLevel(raw.trim(), " ").filter { it.isNotEmpty() }) {
            when {
                token.lowercase() == "inset" -> inset = true
                Regex("^-?[\\d.]").containsMatchIn(token) -> lengths.add(parseDouble(token) ?: 0.0)
                else -> color = parseColor(token) ?: color
            }
        }
        if (lengths.size < 2) return null
        return BoxShadow(color ?: Colors.black, lengths[0], lengths[1], lengths.getOrNull(2) ?: 0.0, lengths.getOrNull(3) ?: 0.0, inset)
    }

    private fun parseTextShadow(value: Any?): List<TextShadow>? {
        if (value == null) return null
        if (value is String || value is Map<*, *>) return parseBoxShadow(value)?.map { TextShadow(it.color, it.dx, it.dy, it.blur) }
        if (value is List<*>) return value.map { shadow ->
            when (shadow) {
                is Map<*, *> -> {
                    val offset = parseOffset(shadow["offset"]) ?: Offset(0.0, 0.0)
                    TextShadow(parseColor(shadow["color"]) ?: 0x42000000, offset.dx, offset.dy, parseDouble(shadow["blurRadius"] ?: shadow["blur"]) ?: 0.0)
                }
                is String -> parseShadowString(shadow)?.let { TextShadow(it.color, it.dx, it.dy, it.blur) } ?: TextShadow(Colors.black, 0.0, 0.0, 0.0)
                else -> TextShadow(Colors.black, 0.0, 0.0, 0.0)
            }
        }
        return null
    }

    // ------------------------------------------------------------------------
    // transforms
    // ------------------------------------------------------------------------

    fun parseAngleDegrees(value: Any?): Double? {
        if (value == null) return null
        if (value is Number) return value.toDouble()
        val t = jsString(value).trim().lowercase()
        val n = pf(t).finite() ?: return null
        return when {
            t.endsWith("rad") && !t.endsWith("grad") -> n * 180 / PI
            t.endsWith("turn") -> n * 360
            t.endsWith("grad") -> n * 0.9
            else -> n
        }
    }

    private fun angleRadians(token: String): Double = (parseAngleDegrees(token) ?: 0.0) * PI / 180

    private val TRANSFORM_FN = Regex("([a-zA-Z0-9]+)\\(([^)]*)\\)")

    fun parseTransform(value: Any?): Matrix4? {
        if (value == null) return null
        if (value is List<*> && value.size == 16) return DoubleArray(16) { (value[it] as? Number)?.toDouble() ?: 0.0 }
        if (value !is String) return null
        val t = value.trim()
        if (t.isEmpty() || t == "none") return null
        var matrix = Matrix.identity()
        var any = false
        for (match in TRANSFORM_FN.findAll(t)) {
            val fn = match.groupValues[1].lowercase()
            val args = match.groupValues[2].split(Regex("[\\s,]+")).filter { it.isNotEmpty() }
            val a = { i: Int -> args.getOrNull(i) }
            val step: Matrix4? = when (fn) {
                "translate" -> Matrix.translation(parseDouble(a(0)) ?: 0.0, parseDouble(a(1)) ?: 0.0, 0.0)
                "translatex" -> Matrix.translation(parseDouble(a(0)) ?: 0.0, 0.0, 0.0)
                "translatey" -> Matrix.translation(0.0, parseDouble(a(0)) ?: 0.0, 0.0)
                "translate3d" -> Matrix.translation(parseDouble(a(0)) ?: 0.0, parseDouble(a(1)) ?: 0.0, parseDouble(a(2)) ?: 0.0)
                "rotate", "rotatez" -> Matrix.rotationZ(angleRadians(a(0) ?: "0"))
                "scale" -> {
                    val sx = pf(a(0) ?: "1")
                    val sy = if (args.size > 1) pf(args[1]) else sx
                    Matrix.scaling(sx, sy, 1.0)
                }
                "scalex" -> Matrix.scaling(pf(a(0) ?: "1"), 1.0, 1.0)
                "scaley" -> Matrix.scaling(1.0, pf(a(0) ?: "1"), 1.0)
                "skew" -> Matrix.skew(angleRadians(a(0) ?: "0"), angleRadians(a(1) ?: "0"))
                "skewx" -> Matrix.skew(angleRadians(a(0) ?: "0"), 0.0)
                "skewy" -> Matrix.skew(0.0, angleRadians(a(0) ?: "0"))
                "matrix", "matrix3d" -> Matrix.fromCss(args.map { pf(it) })
                else -> null
            }
            if (step != null) {
                matrix = Matrix.multiply(matrix, step)
                any = true
            }
        }
        return if (any) matrix else null
    }

    // ------------------------------------------------------------------------
    // gradients and backgrounds
    // ------------------------------------------------------------------------

    fun isGradientValue(value: Any?): Boolean = value is String && value.contains("gradient(")

    private fun extractUrl(value: String): String? {
        Regex("url\\(\\s*(['\"]?)(.*?)\\1\\s*\\)").find(value)?.let { return it.groupValues[2] }
        val t = value.trim()
        return if (t.isEmpty() || t == "none") null else t
    }

    /** Split on [separator] outside parentheses and quotes (`" "` = any whitespace). */
    fun splitTopLevel(input: String, separator: String): List<String> {
        val out = ArrayList<String>()
        var depth = 0
        var quote: Char? = null
        var start = 0
        for (i in input.indices) {
            val ch = input[i]
            if (quote != null) {
                if (ch == quote) quote = null
                continue
            }
            when {
                ch == '"' || ch == '\'' -> quote = ch
                ch == '(' -> depth++
                ch == ')' -> depth = max(0, depth - 1)
                depth == 0 && (if (separator == " ") ch.isWhitespace() else ch.toString() == separator) -> {
                    out.add(input.substring(start, i))
                    start = i + 1
                }
            }
        }
        out.add(input.substring(start))
        return if (separator == " ") out.filter { it.isNotBlank() } else out
    }

    private fun angleForSideKeyword(side: String): Double = when (side.replace(WS, " ").trim()) {
        "top" -> 0.0
        "top right", "right top" -> 45.0
        "right" -> 90.0
        "bottom right", "right bottom" -> 135.0
        "bottom" -> 180.0
        "bottom left", "left bottom" -> 225.0
        "left" -> 270.0
        "top left", "left top" -> 315.0
        else -> 180.0
    }

    /** Begin / end alignments for a CSS angle on the unit square. */
    fun beginEndForAngle(deg: Double): Pair<Alignment, Alignment> {
        val a = (((deg % 360) + 360) % 360) * (PI / 180)
        val dx = sin(a)
        val dy = -cos(a)
        val scale = 1 / max(abs(dx), abs(dy))
        val ex = dx * scale
        val ey = dy * scale
        fun r(v: Double) = if (abs(v) < 1e-9) 0.0 else v
        return Pair(Alignment(r(-ex), r(-ey)), Alignment(r(ex), r(ey)))
    }

    private val ANGLE_TOKEN = Regex("^-?[\\d.]+(deg|rad|turn|grad)$")

    private fun parseCssGradientString(raw: String): Gradient? {
        val s = raw.trim()
        val lower = s.lowercase()
        val kind = if (lower.contains("radial-gradient")) GradientKind.radial else if (lower.contains("conic-gradient")) GradientKind.sweep else GradientKind.linear
        val repeat = lower.startsWith("repeating-")
        val open = s.indexOf('(')
        val close = s.lastIndexOf(')')
        if (open < 0 || close <= open) return null
        val parts = splitTopLevel(s.substring(open + 1, close), ",")
        if (parts.isEmpty()) return null
        var angleDeg: Double? = null
        var center: Alignment? = null
        var startAngle = 0.0
        var colorParts = parts
        val first = parts[0].trim().lowercase()
        when (kind) {
            GradientKind.linear -> {
                if (ANGLE_TOKEN.matches(first)) {
                    angleDeg = parseAngleDegrees(first)
                    colorParts = parts.drop(1)
                } else if (first.startsWith("to ")) {
                    angleDeg = angleForSideKeyword(first.substring(3))
                    colorParts = parts.drop(1)
                }
            }
            GradientKind.radial -> if (!looksLikeColorStop(first)) {
                val at = first.indexOf("at ")
                if (at >= 0) center = parsePositionKeywords(first.substring(at + 3).trim())
                colorParts = parts.drop(1)
            }
            GradientKind.sweep -> if (!looksLikeColorStop(first)) {
                Regex("from\\s+(-?[\\d.]+\\w*)").find(first)?.let { startAngle = angleRadians(it.groupValues[1]) }
                val at = first.indexOf("at ")
                if (at >= 0) center = parsePositionKeywords(first.substring(at + 3).trim())
                colorParts = parts.drop(1)
            }
        }
        val colors = ArrayList<Color>()
        val stops = ArrayList<Double?>()
        for (part in colorParts) {
            val t = part.trim()
            if (t.isEmpty()) continue
            val tokens = splitTopLevel(t, " ")
            val color = parseColor(tokens.getOrNull(0)) ?: continue
            val positions = tokens.drop(1).map { parseStopPosition(it) }
            if (positions.isEmpty()) {
                colors.add(color)
                stops.add(null)
            } else for (pos in positions) {
                colors.add(color)
                stops.add(pos)
            }
        }
        if (colors.isEmpty()) return null
        if (colors.size == 1) {
            colors.add(colors[0])
            stops.add(null)
        }
        val resolved = resolveStops(stops)
        return when (kind) {
            GradientKind.radial -> Gradient(kind, colors, resolved, center = center ?: Alignment.center, radius = 0.5, repeat = repeat)
            GradientKind.sweep -> Gradient(kind, colors, resolved, center = center ?: Alignment.center, startAngle = startAngle - PI / 2, endAngle = startAngle - PI / 2 + PI * 2, repeat = repeat)
            GradientKind.linear -> {
                val (b, e) = beginEndForAngle(angleDeg ?: 180.0)
                Gradient(kind, colors, resolved, begin = b, end = e, repeat = repeat)
            }
        }
    }

    private fun looksLikeColorStop(token: String): Boolean = parseColor(splitTopLevel(token, " ").firstOrNull()) != null

    private fun parseStopPosition(token: String): Double? {
        val t = token.trim()
        if (t.endsWith("%")) return pf(t).finite()?.let { (it / 100).coerceIn(0.0, 1.0) }
        if (t.endsWith("deg") || t.endsWith("turn")) return (parseAngleDegrees(t) ?: 0.0) / 360
        return null
    }

    private fun resolveStops(stops: List<Double?>): List<Double>? {
        if (stops.all { it == null }) return null
        val out = stops.toMutableList()
        if (out[0] == null) out[0] = 0.0
        if (out[out.size - 1] == null) out[out.size - 1] = 1.0
        var i = 0
        while (i < out.size) {
            if (out[i] != null) {
                i++
                continue
            }
            val startIdx = i - 1
            var endIdx = i
            while (out[endIdx] == null) endIdx++
            val a = out[startIdx]!!
            val b = out[endIdx]!!
            val span = endIdx - startIdx
            for (k in startIdx + 1 until endIdx) out[k] = a + (b - a) * (k - startIdx) / span
            i = endIdx
        }
        for (k in 1 until out.size) if (out[k]!! < out[k - 1]!!) out[k] = out[k - 1]
        return out.map { it!! }
    }

    private fun parseGradientLayers(value: String): List<Gradient> =
        splitTopLevel(value, ",").map { it.trim() }.filter { isGradientValue(it) }.mapNotNull { parseCssGradientString(it) }

    fun parseGradient(value: Any?): Gradient? {
        when (value) {
            null -> return null
            is String -> return parseGradientLayers(value).firstOrNull()
            is Map<*, *> -> {
                val type = jsString(value["type"] ?: "linear").lowercase()
                val colors = (value["colors"] as? List<*>)?.map { parseColor(it) ?: 0 } ?: return null
                if (colors.isEmpty()) return null
                val stops = parseNumberList(value["stops"])
                return when (type) {
                    "linear" -> Gradient(GradientKind.linear, colors, stops, begin = parseAlignment(value["begin"]) ?: Alignment.topCenter, end = parseAlignment(value["end"]) ?: Alignment.bottomCenter)
                    "radial" -> Gradient(GradientKind.radial, colors, stops, center = parseAlignment(value["center"]) ?: Alignment.center, radius = parseDouble(value["radius"]) ?: 0.5)
                    "sweep" -> Gradient(GradientKind.sweep, colors, stops, center = parseAlignment(value["center"]) ?: Alignment.center, startAngle = parseDouble(value["startAngle"]) ?: 0.0, endAngle = parseDouble(value["endAngle"]) ?: PI * 2)
                    else -> null
                }
            }
            else -> return null
        }
    }

    private class Background(val color: Color?, val gradients: List<Gradient>, val image: String?)

    private val GRADIENT_START = Regex("(repeating-)?(linear|radial|conic)-gradient\\(")

    private fun parseBackgroundShorthand(value: String): Background {
        val gradients = ArrayList<Gradient>()
        var color: Color? = null
        var image: String? = null
        for (layer in splitTopLevel(value.trim(), ",")) {
            val t = layer.trim()
            if (isGradientValue(t)) {
                val at = GRADIENT_START.find(t)?.range?.first ?: 0
                parseCssGradientString(t.substring(at))?.let { gradients.add(it) }
                continue
            }
            if (t.contains("url(")) image = extractUrl(t)
            for (token in splitTopLevel(t, " ")) parseColor(token)?.let { color = it }
        }
        return Background(color, gradients, image)
    }

    private fun parseColorList(value: Any?): List<Color>? = (value as? List<*>)?.mapNotNull { parseColor(it) }?.ifEmpty { null }

    private fun parseNumberList(value: Any?): List<Double>? = (value as? List<*>)?.mapNotNull { parseDouble(it) }?.ifEmpty { null }

    // ------------------------------------------------------------------------
    // filters
    // ------------------------------------------------------------------------

    private val FILTER_FN = Regex("([a-z-]+)\\(([^()]*(?:\\([^()]*\\)[^()]*)*)\\)", RegexOption.IGNORE_CASE)

    fun parseFilter(value: Any?): Filter? {
        if (value !is String) return null
        val t = value.trim()
        if (t.isEmpty() || t == "none") return null
        var f = Filter()
        fun amount(arg: String, def: Double): Double {
            val a = arg.trim()
            if (a.isEmpty()) return def
            return if (a.endsWith("%")) pf(a) / 100 else pf(a)
        }
        for (m in FILTER_FN.findAll(t)) {
            val arg = m.groupValues[2]
            f = when (m.groupValues[1].lowercase()) {
                "blur" -> f.copy(blur = parseDouble(arg) ?: 0.0)
                "brightness" -> f.copy(brightness = amount(arg, 1.0))
                "contrast" -> f.copy(contrast = amount(arg, 1.0))
                "grayscale" -> f.copy(grayscale = amount(arg, 1.0))
                "hue-rotate" -> f.copy(hueRotate = parseAngleDegrees(arg) ?: 0.0)
                "invert" -> f.copy(invert = amount(arg, 1.0))
                "saturate" -> f.copy(saturate = amount(arg, 1.0))
                "sepia" -> f.copy(sepia = amount(arg, 1.0))
                "opacity" -> f.copy(opacity = amount(arg, 1.0))
                "drop-shadow" -> parseShadowString(arg)?.let { f.copy(dropShadow = TextShadow(it.color, it.dx, it.dy, it.blur)) } ?: f
                else -> f
            }
        }
        return if (f.isEmpty) null else f
    }

    // ------------------------------------------------------------------------
    // time
    // ------------------------------------------------------------------------

    /** Milliseconds (ints are ms; `s` / `ms` suffixes honoured). */
    fun parseDuration(value: Any?): Double? {
        when (value) {
            null -> return null
            is Number -> return value.toDouble().let { if (it >= 0) Math.floor(it) else Math.ceil(it) }
            !is String -> return null
        }
        val t = (value as String).trim().lowercase()
        if (t.endsWith("ms")) return pf(t).finite()?.let { Math.floor(it) }
        if (t.endsWith("s")) return pf(t).finite()?.let { Math.floor(it * 1000) }
        return jsParseInt(t.replace(Regex("[^0-9]"), ""))?.toDouble()
    }

    /** Lowercase, dash-free curve key (`cubic-bezier(…)` / `steps(…)` kept). */
    fun normalizeCurve(value: Any?): String? {
        if (value !is String) return null
        val t = value.trim()
        if (t.isEmpty()) return null
        if (t.startsWith("cubic-bezier(") || t.startsWith("steps(")) return t.lowercase()
        return t.lowercase().replace(Regex("[-_\\s]"), "")
    }

    private val TIME = Regex("^[\\d.]+m?s$")
    private val TIMING = Regex("^(ease|linear|step|cubic-bezier|steps)")

    private fun parseTransitionShorthand(value: String, s: CSSStyle) {
        val tokens = splitTopLevel(splitTopLevel(value, ",")[0], " ")
        val times = ArrayList<Double>()
        for (token in tokens) {
            when {
                TIME.matches(token) -> times.add(parseDuration(token) ?: 0.0)
                TIMING.containsMatchIn(token) -> if (s.transitionCurve == null) s.transitionCurve = normalizeCurve(token)
                else -> if (s.transitionProperty == null) s.transitionProperty = token
            }
        }
        if (times.isNotEmpty() && s.transitionDuration == null) s.transitionDuration = times[0]
        if (times.size > 1 && s.transitionDelay == null) s.transitionDelay = times[1]
    }

    private fun parseAnimationShorthand(value: String, s: CSSStyle) {
        val tokens = splitTopLevel(splitTopLevel(value, ",")[0], " ")
        val times = ArrayList<Double>()
        for (token in tokens) {
            val lower = token.lowercase()
            when {
                TIME.matches(lower) -> times.add(parseDuration(lower) ?: 0.0)
                TIMING.containsMatchIn(lower) -> if (s.animationTimingFunction == null) s.animationTimingFunction = lower
                lower == "infinite" -> if (s.animationIterationCount == null) s.animationIterationCount = -1.0
                Regex("^\\d+$").matches(lower) -> if (s.animationIterationCount == null) s.animationIterationCount = lower.toDouble()
                lower in setOf("normal", "reverse", "alternate", "alternate-reverse") -> if (s.animationDirection == null) s.animationDirection = lower
                lower in setOf("forwards", "backwards", "both") -> if (s.animationFillMode == null) s.animationFillMode = lower
                lower in setOf("running", "paused") -> if (s.animationPlayState == null) s.animationPlayState = lower
                lower != "none" -> if (s.animationName == null) s.animationName = token
            }
        }
        if (times.isNotEmpty() && s.animationDuration == null) s.animationDuration = times[0]
        if (times.size > 1 && s.animationDelay == null) s.animationDelay = times[1]
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseKeyframes(value: Any?): List<Keyframe>? {
        if (value !is List<*>) return null
        val out = ArrayList<Keyframe>()
        for (frame in value) {
            if (frame !is Map<*, *>) continue
            val offset = parseDouble(frame["offset"])
            val styles = frame["styles"]
            if (offset != null && styles is Map<*, *>) out.add(Keyframe(offset, styles as Map<String, Any?>))
            else out.add(Keyframe(offset ?: 0.0, frame as Map<String, Any?>))
        }
        return out.ifEmpty { null }
    }
}
