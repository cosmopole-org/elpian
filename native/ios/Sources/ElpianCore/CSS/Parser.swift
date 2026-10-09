import Foundation

/**
 * The CSS value parser — a port of `CSSParser` (flutter/lib/src/css/css_parser.dart),
 * line for line with css/parser.ts in the TypeScript engine (native/web).
 *
 * `parse(map)` turns an inline/cascaded style map (camelCase or kebab-case
 * keys, numbers or CSS strings) into a resolved [CSSStyle]. Everything the
 * Flutter parser accepts is accepted here with the same result. Beyond that,
 * the CSS string forms Flutter silently drops — `border: 1px solid #ccc`,
 * `box-shadow: 0 2px 4px rgba(…)`, `transform: rotate(45deg)`, multi-value
 * `border-radius`, `em`/`rem` units, `filter: blur(4px)` — are parsed too, so
 * the native renderers can honour them.
 */
public enum CSSParser {
    private static let MAX_CACHE = 512
    private static let cacheLock = NSLock()
    private static var cache: [String: CSSStyle] = [:]
    private static var cacheOrder: [String] = []

    private static let VIEWPORT_KEYS = [
        "width", "height", "minWidth", "min-width", "maxWidth", "max-width", "minHeight", "min-height",
        "maxHeight", "max-height", "top", "right", "bottom", "left", "padding", "margin", "gap",
    ]
    private static let VIEWPORT_UNITS = JSRegex("%|vw|vh|vmin|vmax|calc\\(|env\\(")

    private static func hasViewportUnits(_ m: JSONObject) -> Bool {
        for key in VIEWPORT_KEYS {
            if let v = m[key] as? String, VIEWPORT_UNITS.test(v) { return true }
        }
        return false
    }

    /** Resolve a style map (LRU-cached; the returned style is shared — copy before mutating). */
    public static func parse(_ styleMap: JSONObject) -> CSSStyle {
        let viewportDependent = hasViewportUnits(styleMap)
        let key = (viewportDependent ? "g\(cssEnvironmentGeneration()):" : "") + stableKey(styleMap)
        cacheLock.lock()
        if let hit = cache[key] {
            if let i = cacheOrder.firstIndex(of: key) {
                cacheOrder.remove(at: i)
                cacheOrder.append(key)
            }
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()
        let style = parseUncached(styleMap)
        cacheLock.lock()
        if cache.count >= MAX_CACHE, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = style
        cacheLock.unlock()
        return style
    }

    public static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheOrder.removeAll()
        cacheLock.unlock()
    }

    public static var cacheSize: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache.count
    }

    public static func parseColor(_ value: Any?) -> Color? { ElpianCore.parseColor(value) }

    // ------------------------------------------------------------------------
    // !important
    // ------------------------------------------------------------------------

    private static let IMPORTANT = JSRegex("\\s*!\\s*important\\s*$", ignoreCase: true)
    private static let IS_IMPORTANT = JSRegex("!\\s*important\\s*$", ignoreCase: true)

    public static func stripImportant(_ value: Any?) -> Any? {
        let v = flattenOptional(value)
        if let s = v as? String, IMPORTANT.test(s) {
            return jsTrim(IMPORTANT.replace(s, with: "", global: false))
        }
        return v
    }

    public static func isImportant(_ value: Any?) -> Bool {
        guard let s = flattenOptional(value) as? String else { return false }
        return IS_IMPORTANT.test(s)
    }

    // ------------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------------

    private static let kebabLock = NSLock()
    private static var kebabCache: [String: String] = [:]

    private static func kebab(_ camel: String) -> String {
        kebabLock.lock()
        if let k = kebabCache[camel] {
            kebabLock.unlock()
            return k
        }
        kebabLock.unlock()
        var out = ""
        for u in camel.unicodeScalars {
            if u.value >= 65 && u.value <= 90 {
                out += "-"
                out.unicodeScalars.append(Unicode.Scalar(u.value + 32)!)
            } else {
                out.unicodeScalars.append(u)
            }
        }
        kebabLock.lock()
        kebabCache[camel] = out
        kebabLock.unlock()
        return out
    }

    /** Read a property by camelCase name, falling back to its kebab-case spelling. */
    private static func pick(_ m: JSONObject, _ camel: String) -> Any? {
        if let v = m[camel] { return v }
        let k = kebab(camel)
        return k == camel ? nil : m[k]
    }

    private static func str(_ v: Any?) -> String? {
        guard let x = flattenOptional(v) else { return nil }
        return x as? String ?? jsString(x)
    }

    /** `typeof v === 'object' && !Array.isArray(v)` — maps and typed values (read by their JSON fields). */
    private static func objectOf(_ v: Any?) -> JSONObject? {
        let f = flattenOptional(v)
        if let m = asMap(f) { return m }
        if f is String || jsNumber(f) != nil || jsBool(f) != nil || f == nil { return nil }
        if let s = f as? JSONSerializable { return asMap(s.toJSON()) }
        return nil
    }

    /** `typeof v === 'object'` (arrays included). */
    private static func isObject(_ v: Any?) -> Bool {
        objectOf(v) != nil || asArray(v) != nil
    }

    /** `obj.key` where arrays have no such key. */
    private static func field(_ v: Any?, _ key: String) -> Any? { objectOf(v)?[key] }

    private static func expandFour<T>(_ parts: [T]) -> [T?] {
        if parts.count == 1 { return [parts[0], parts[0], parts[0], parts[0]] }
        if parts.count == 2 { return [parts[0], parts[1], parts[0], parts[1]] }
        if parts.count == 3 { return [parts[0], parts[1], parts[2], parts[1]] }
        return (0..<4).map { $0 < parts.count ? parts[$0] : nil }
    }

    private static func words(_ s: String) -> [String] {
        jsSplitWhitespace(jsTrim(s)).filter { !$0.isEmpty }
    }

    private static func finite(_ d: Double) -> Double? { d.isFinite ? d : nil }

    // ========================================================================
    // The style
    // ========================================================================

    private static let NONE_RE = JSRegex("^\\s*none\\s*$", ignoreCase: true)

    private static func parseUncached(_ m: JSONObject) -> CSSStyle {
        let s = CSSStyle()
        let fontSize = parseFontSize(pick(m, "fontSize"))

        // ---- sizing ----------------------------------------------------------
        s.width = parseDimension(m["width"], true)
        s.height = parseDimension(m["height"], false)
        s.widthFactor = percentFactor(m["width"])
        s.heightFactor = percentFactor(m["height"])
        s.aspectRatio = parseAspectRatio(pick(m, "aspectRatio"))
        s.minWidth = parseDimension(pick(m, "minWidth"), true)
        s.maxWidth = parseDimension(pick(m, "maxWidth"), true)
        s.minHeight = parseDimension(pick(m, "minHeight"), false)
        s.maxHeight = parseDimension(pick(m, "maxHeight"), false)
        if s.maxWidth == nil && NONE_RE.test(str(pick(m, "maxWidth")) ?? "") { s.maxWidth = nil }

        // ---- spacing ---------------------------------------------------------
        let pad = parseEdgeInsetsFor(m, "padding", fontSize)
        s.padding = pad.insets
        s.paddingPercent = pad.percent
        let mar = parseEdgeInsetsFor(m, "margin", fontSize)
        s.margin = mar.insets
        s.marginPercent = mar.percent
        s.marginAuto = mar.auto

        // ---- positioning -----------------------------------------------------
        s.alignment = parseAlignment(m["alignment"])
        s.position = str(m["position"])
        s.top = parseDimension(m["top"], false)
        s.right = parseDimension(m["right"], true)
        s.bottom = parseDimension(m["bottom"], false)
        s.left = parseDimension(m["left"], true)
        s.zIndex = parseDouble(pick(m, "zIndex"))

        // ---- layout ----------------------------------------------------------
        s.display = str(m["display"]).map { jsTrim($0) }
        s.flexDirection = str(pick(m, "flexDirection"))
        s.justifyContent = str(pick(m, "justifyContent"))
        s.alignItems = str(pick(m, "alignItems"))
        s.alignContent = str(pick(m, "alignContent"))
        s.alignSelf = str(pick(m, "alignSelf"))
        parseFlexShorthand(m, s)
        s.flexWrap = str(pick(m, "flexWrap"))
        if let flow = str(pick(m, "flexFlow")), !flow.isEmpty {
            for token in jsSplitWhitespace(flow) {
                if token.hasPrefix("row") || token.hasPrefix("column") {
                    if s.flexDirection == nil { s.flexDirection = token }
                } else if token.hasPrefix("wrap") || token == "nowrap" {
                    if s.flexWrap == nil { s.flexWrap = token }
                }
            }
        }
        s.order = parseIntValue(m["order"])
        let gap = str(m["gap"])
        if let gap = gap, !gap.isEmpty, jsTrim(gap).contains(" ") {
            // `gap: <row> <column>`
            let parts = jsSplitWhitespace(jsTrim(gap))
            s.rowGap = parseDouble(parts[0], fontSize)
            s.columnGap = parseDouble(parts.count > 1 ? parts[1] : nil, fontSize)
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

        // ---- grid ------------------------------------------------------------
        s.gridTemplateColumns = str(pick(m, "gridTemplateColumns"))
        s.gridTemplateRows = str(pick(m, "gridTemplateRows"))
        s.gridTemplateAreas = str(pick(m, "gridTemplateAreas"))
        s.gridAutoColumns = str(pick(m, "gridAutoColumns"))
        s.gridAutoRows = str(pick(m, "gridAutoRows"))
        s.gridAutoFlow = str(pick(m, "gridAutoFlow"))
        s.gridColumnGap = parseDouble(pick(m, "gridColumnGap") ?? pick(m, "columnGap") ?? s.columnGap, fontSize)
        s.gridRowGap = parseDouble(pick(m, "gridRowGap") ?? pick(m, "rowGap") ?? s.rowGap, fontSize)
        s.gridGap = parseDouble(pick(m, "gridGap"), fontSize)
        s.gridColumn = str(pick(m, "gridColumn"))
        s.gridRow = str(pick(m, "gridRow"))
        s.gridArea = str(pick(m, "gridArea"))
        s.justifyItems = str(pick(m, "justifyItems"))
        s.justifySelf = str(pick(m, "justifySelf"))

        // ---- background ------------------------------------------------------
        let background = m["background"]
        let bgLayers = (background as? String).map { parseBackgroundShorthand($0) }
        s.backgroundColor = ElpianCore.parseColor(pick(m, "backgroundColor")) ?? bgLayers?.color
        let bgImage = str(pick(m, "backgroundImage"))
        if let img = bgImage, !img.isEmpty, !isGradientValue(img) {
            s.backgroundImage = extractUrl(img)
        } else {
            s.backgroundImage = bgLayers?.image
        }
        s.backgroundSize = parseBoxFit(pick(m, "backgroundSize"))
        s.backgroundSizePx = parseBackgroundSizePx(pick(m, "backgroundSize"))
        s.backgroundPosition = parseAlignment(pick(m, "backgroundPosition"))
        s.backgroundRepeat = str(pick(m, "backgroundRepeat"))
        var gradients: [Gradient] = []
        if let explicit = parseGradient(m["gradient"]) { gradients.append(explicit) }
        if let img = bgImage, !img.isEmpty, isGradientValue(img) { gradients += parseGradientLayers(img) }
        if let layers = bgLayers { gradients += layers.gradients }
        s.gradient = gradients.first
        s.gradientLayers = gradients.count > 1 ? Array(gradients.dropFirst()) : nil
        s.gradientColors = parseColorList(pick(m, "gradientColors"))
        s.gradientStops = parseNumberList(pick(m, "gradientStops"))

        // ---- border ----------------------------------------------------------
        s.borderColor = ElpianCore.parseColor(pick(m, "borderColor"))
        s.borderWidth = parseDouble(pick(m, "borderWidth"), fontSize)
        s.borderStyle = str(pick(m, "borderStyle"))
        s.border = parseBorder(m, s, fontSize)
        let radius = parseBorderRadius(m, fontSize)
        s.borderRadius = radius.px
        s.borderRadiusPercent = radius.percent
        s.outlineColor = ElpianCore.parseColor(pick(m, "outlineColor"))
        s.outlineWidth = parseDouble(pick(m, "outlineWidth"), fontSize)
        s.outlineStyle = str(pick(m, "outlineStyle"))
        s.outlineOffset = parseDouble(pick(m, "outlineOffset"), fontSize)
        if let outline = str(m["outline"]), !outline.isEmpty, let side = parseBorderSideString(outline, fontSize) {
            if s.outlineColor == nil { s.outlineColor = side.color }
            if s.outlineWidth == nil { s.outlineWidth = side.width }
            if s.outlineStyle == nil { s.outlineStyle = side.style.rawValue }
        }

        // ---- text ------------------------------------------------------------
        s.color = ElpianCore.parseColor(m["color"])
        s.fontSize = fontSize
        s.fontWeight = parseFontWeight(pick(m, "fontWeight"))
        s.fontStyle = parseFontStyle(pick(m, "fontStyle"))
        s.fontFamily = str(pick(m, "fontFamily"))
        parseFontShorthand(m["font"], s)
        s.letterSpacing = parseDouble(pick(m, "letterSpacing"), fontSize ?? 16)
        s.wordSpacing = parseDouble(pick(m, "wordSpacing"), fontSize ?? 16)
        parseLineHeight(pick(m, "lineHeight"), s)
        s.textAlign = parseTextAlign(pick(m, "textAlign"))
        let deco = parseTextDecoration(pick(m, "textDecoration") ?? pick(m, "textDecorationLine"))
        s.textDecoration = deco.decoration
        s.textDecorationColor = ElpianCore.parseColor(pick(m, "textDecorationColor")) ?? deco.color
        s.textDecorationStyle = str(pick(m, "textDecorationStyle")) ?? deco.style
        s.textDecorationThickness = parseDouble(pick(m, "textDecorationThickness"))
        s.textOverflow = parseTextOverflow(pick(m, "textOverflow"))
        s.textTransform = str(pick(m, "textTransform"))
        s.whiteSpace = str(pick(m, "whiteSpace"))
        let collapse = str(pick(m, "borderCollapse"))
        s.borderCollapse = collapse == "collapse" || collapse == "separate" ? collapse : nil
        s.borderSpacing = parseDouble(pick(m, "borderSpacing"))
        s.verticalAlign = str(pick(m, "verticalAlign"))
        s.writingMode = str(pick(m, "writingMode"))
        s.wordBreak = str(pick(m, "wordBreak"))
        s.lineClamp = parseIntValue(pick(m, "lineClamp") ?? pick(m, "WebkitLineClamp") ?? m["-webkit-line-clamp"])

        // ---- effects ---------------------------------------------------------
        s.boxShadow = parseBoxShadow(pick(m, "boxShadow"))
        s.textShadow = parseTextShadow(pick(m, "textShadow"))
        s.transform = parseTransform(m["transform"])
        s.rotate = parseAngleDegrees(m["rotate"])
        let scaleRaw = m["scale"]
        if let sr = scaleRaw as? String, jsTrim(sr).contains(" ") {
            let parts = jsSplitWhitespace(jsTrim(sr)).map { jsParseFloat($0) }
            s.scaleX = finite(parts[0])
            s.scaleY = parts.count > 1 ? finite(parts[1]) : nil
        } else {
            s.scale = parseDouble(scaleRaw)
        }
        if s.scaleX == nil { s.scaleX = parseDouble(pick(m, "scaleX")) }
        if s.scaleY == nil { s.scaleY = parseDouble(pick(m, "scaleY")) }
        s.translate = parseOffset(m["translate"]) ?? parseTranslateString(m["translate"])
        s.transformOrigin = parseAlignment(pick(m, "transformOrigin")) ?? parseOriginString(pick(m, "transformOrigin"))
        s.opacity = parseDouble(m["opacity"])
        s.visible = jsBool(m["visible"])
        s.visibility = str(m["visibility"])
        s.filter = parseFilter(m["filter"])
        s.backdropFilter = parseFilter(pick(m, "backdropFilter"))
        s.mixBlendMode = str(pick(m, "mixBlendMode"))

        // ---- interaction -----------------------------------------------------
        s.cursor = str(m["cursor"])
        s.pointerEvents = str(pick(m, "pointerEvents"))
        s.userSelect = str(pick(m, "userSelect"))
        s.touchAction = str(pick(m, "touchAction"))

        // ---- media / shape ---------------------------------------------------
        s.objectFit = parseBoxFit(pick(m, "objectFit"))
        s.objectPosition = parseAlignment(pick(m, "objectPosition"))
        s.clipBehavior = str(pick(m, "clipBehavior"))
        let shape = str(m["shape"])?.lowercased()
        s.shape = shape == "circle" ? "circle" : shape == "rectangle" ? "rectangle" : nil

        // ---- transitions / animation -----------------------------------------
        s.transitionDuration = parseDuration(pick(m, "transitionDuration"))
        s.transitionCurve = normalizeCurve(pick(m, "transitionCurve") ?? pick(m, "transitionTimingFunction"))
        s.transitionProperty = str(pick(m, "transitionProperty"))
        s.transitionDelay = parseDuration(pick(m, "transitionDelay"))
        if let transition = str(m["transition"]), !transition.isEmpty { parseTransitionShorthand(transition, s) }
        s.animationName = str(pick(m, "animationName"))
        s.animationDuration = parseDuration(pick(m, "animationDuration"))
        s.animationTimingFunction = str(pick(m, "animationTimingFunction"))
        s.animationDelay = parseDuration(pick(m, "animationDelay"))
        s.animationIterationCount = parseIntValue(pick(m, "animationIterationCount"))
        s.animationDirection = str(pick(m, "animationDirection"))
        s.animationFillMode = str(pick(m, "animationFillMode"))
        s.animationPlayState = str(pick(m, "animationPlayState"))
        if let animation = str(m["animation"]), !animation.isEmpty { parseAnimationShorthand(animation, s) }
        s.animateOnBuild = asBool(pick(m, "animateOnBuild"))
        s.staggerDelay = parseDuration(pick(m, "staggerDelay"))
        s.staggerChildren = parseIntValue(pick(m, "staggerChildren"))
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
        s.colorBegin = ElpianCore.parseColor(pick(m, "colorBegin"))
        s.colorEnd = ElpianCore.parseColor(pick(m, "colorEnd"))
        s.paddingBegin = parseEdgeInsets(pick(m, "paddingBegin"))
        s.paddingEnd = parseEdgeInsets(pick(m, "paddingEnd"))
        s.alignmentBegin = parseAlignment(pick(m, "alignmentBegin"))
        s.alignmentEnd = parseAlignment(pick(m, "alignmentEnd"))
        s.shimmerBaseColor = ElpianCore.parseColor(pick(m, "shimmerBaseColor"))
        s.shimmerHighlightColor = ElpianCore.parseColor(pick(m, "shimmerHighlightColor"))
        s.animationAutoReverse = asBool(pick(m, "animationAutoReverse"))
        s.animationRepeat = asBool(pick(m, "animationRepeat"))
        s.keyframes = parseKeyframes(m["keyframes"])
        return s
    }

    // ========================================================================
    // Numbers and lengths
    // ========================================================================

    private static func asBool(_ v: Any?) -> Bool? {
        let f = flattenOptional(v)
        if let b = jsBool(f) { return b }
        if let s = f as? String {
            if s == "true" { return true }
            if s == "false" { return false }
        }
        return nil
    }

    private static let VIEWPORT_LENGTH = JSRegex("^-?[\\d.]+(vw|vh|vmin|vmax)$")
    private static let NON_NUMERIC = JSRegex("[^0-9.\\-eE+]")
    private static let NON_NUMERIC_STRICT = JSRegex("[^0-9.\\-]")

    /**
     * Flutter's `parseDouble`: numbers pass through; strings have their unit
     * stripped. `em`/`rem` are honoured (×[emBase] / ×root size) rather than
     * read as bare pixel counts.
     */
    public static func parseDouble(_ value: Any?, _ emBase: Double? = nil) -> Double? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if jsBool(x) != nil { return nil }
        if let n = jsNumber(x) { return n.isFinite ? n : nil }
        let raw = jsTrim(jsString(stripImportant(x)))
        if raw.isEmpty { return nil }
        let lower = raw.lowercased()
        if lower.hasSuffix("rem") {
            let n = jsParseFloat(lower)
            return n.isFinite ? n * cssEnvironment().rootFontSize : nil
        }
        if lower.hasSuffix("em") && !lower.hasSuffix("rem") {
            let n = jsParseFloat(lower)
            return n.isFinite ? n * (emBase ?? cssEnvironment().rootFontSize) : nil
        }
        if VIEWPORT_LENGTH.test(lower) { return resolveLength(lower, true) }
        let n = jsParseFloat(NON_NUMERIC.replace(raw, with: ""))
        if !n.isFinite {
            let fallback = jsParseFloat(NON_NUMERIC_STRICT.replace(raw, with: ""))
            return fallback.isFinite ? fallback : nil
        }
        return n
    }

    /** The style's integer parser (`animation-iteration-count: infinite` → -1). */
    public static func parseIntValue(_ value: Any?) -> Double? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let n = jsNumber(x) { return jsTrunc(n) }
        if let s = x as? String {
            let t = jsTrim(s).lowercased()
            if t == "infinite" { return -1 }
            let n = jsParseInt(t, 10)
            return n.isFinite ? n : nil
        }
        return nil
    }

    private static let FONT_SIZE_KEYWORDS: [String: Double] = [
        "xx-small": 9, "x-small": 10, "small": 13, "medium": 16, "large": 18, "x-large": 24, "xx-large": 32, "xxx-large": 48,
    ]

    public static func parseFontSize(_ value: Any?) -> Double? {
        let v = flattenOptional(value)
        guard v != nil else { return nil }
        if let s = v as? String {
            let t = jsTrim(s).lowercased()
            if let k = FONT_SIZE_KEYWORDS[t] { return k }
            if t.hasSuffix("%") {
                let n = jsParseFloat(t)
                return n.isFinite ? n / 100 * cssEnvironment().rootFontSize : nil
            }
        }
        return parseDouble(v)
    }

    private static func percentFactor(_ value: Any?) -> Double? {
        guard let s = flattenOptional(value) as? String else { return nil }
        let raw = jsTrim(jsString(stripImportant(s)))
        if !raw.hasSuffix("%") { return nil }
        let n = jsParseFloat(String(raw.dropLast()))
        return n.isFinite ? n / 100 : nil
    }

    private static let MATH_FN_START = JSRegex("^(min|max|clamp)\\(")

    public static func parseDimension(_ value: Any?, _ isWidth: Bool) -> Double? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let n = jsNumber(x) { return n.isFinite ? n : nil }
        guard let s = x as? String else { return nil }
        let raw = jsTrim(jsString(stripImportant(s)))
        if raw.isEmpty || raw == "auto" || raw == "none" || raw == "fit-content" || raw == "max-content" || raw == "min-content" {
            return nil
        }
        if raw.contains("calc(") { return evalCalc(raw, isWidth) }
        if MATH_FN_START.test(raw) { return evalMathFn(raw, isWidth) }
        return resolveLength(raw, isWidth)
    }

    private static func resolveLength(_ raw: String, _ isWidth: Bool) -> Double? {
        let t = jsTrim(raw).lowercased()
        if t.isEmpty { return nil }
        if t.hasPrefix("env(") { return resolveEnv(t, isWidth) }
        if t.hasPrefix("var(") { return nil }
        if t.contains("*") || t.contains("/") || t.contains("(") { return nil }
        let n = jsParseFloat(NON_NUMERIC.replace(t, with: ""))
        if !n.isFinite { return nil }
        let env = cssEnvironment()
        let w = env.viewportWidth
        let h = env.viewportHeight
        if t.hasSuffix("vmin") { return n / 100 * min(w, h) }
        if t.hasSuffix("vmax") { return n / 100 * max(w, h) }
        if t.hasSuffix("vw") { return n / 100 * w }
        if t.hasSuffix("vh") || t.hasSuffix("dvh") || t.hasSuffix("svh") || t.hasSuffix("lvh") { return n / 100 * h }
        if t.hasSuffix("%") { return n / 100 * (isWidth ? w : h) }
        if t.hasSuffix("rem") { return n * env.rootFontSize }
        if t.hasSuffix("em") { return n * env.rootFontSize }
        if t.hasSuffix("pt") { return n * 4 / 3 }
        return n
    }

    private static let CALC = JSRegex("^calc\\(([\\s\\S]*)\\)$")

    private static func evalCalc(_ raw: String, _ isWidth: Bool) -> Double? {
        guard let m = CALC.exec(jsTrim(raw)), let inner = m[1] else { return nil }
        let body = jsTrim(inner)
        if body.isEmpty { return nil }
        return evalSum(body, isWidth)
    }

    private static func evalSum(_ body: String, _ isWidth: Bool) -> Double? {
        let u = Array(body.utf16)
        var sum = 0.0
        var sign = 1.0
        var start = 0
        var depth = 0
        for i in 0..<u.count {
            let c = u[i]
            if c == 0x28 { depth += 1 }
            else if c == 0x29 { depth -= 1 }
            else if depth == 0 && (c == 0x2B || c == 0x2D) && i > 0 && u[i - 1] == 0x20 && i + 1 < u.count && u[i + 1] == 0x20 {
                guard let v = evalProduct(jsTrim(String(decoding: u[start..<i], as: UTF16.self)), isWidth) else { return nil }
                sum += sign * v
                sign = c == 0x2B ? 1 : -1
                start = i + 1
            }
        }
        guard let last = evalProduct(jsTrim(String(decoding: u[start...], as: UTF16.self)), isWidth) else { return nil }
        return sum + sign * last
    }

    private static let PRODUCT = JSRegex("^(.+?)\\s*([*/])\\s*(.+)$")

    private static func evalProduct(_ term: String, _ isWidth: Bool) -> Double? {
        // `a * b` / `a / b` with at most one length operand.
        if let mul = PRODUCT.exec(term), !term.hasPrefix("env("), !term.hasPrefix("calc(") {
            guard let left = evalAtom(jsTrim(mul[1] ?? ""), isWidth), let right = evalAtom(jsTrim(mul[3] ?? ""), isWidth) else { return nil }
            if mul[2] == "*" { return left * right }
            return right == 0 ? nil : left / right
        }
        return evalAtom(term, isWidth)
    }

    private static func evalAtom(_ atom: String, _ isWidth: Bool) -> Double? {
        let t = jsTrim(atom)
        if t.hasPrefix("(") && t.hasSuffix(")") { return evalSum(jsTrim(jsSubstring(t, 1, jsLength(t) - 1)), isWidth) }
        if t.hasPrefix("calc(") { return evalCalc(t, isWidth) }
        if MATH_FN_START.test(t) { return evalMathFn(t, isWidth) }
        return resolveLength(t, isWidth)
    }

    private static let MATH_FN = JSRegex("^(min|max|clamp)\\(([\\s\\S]*)\\)$")

    private static func evalMathFn(_ raw: String, _ isWidth: Bool) -> Double? {
        guard let m = MATH_FN.exec(jsTrim(raw)) else { return nil }
        let args = splitTopLevel(m[2] ?? "", ",").map { evalSum(jsTrim($0), isWidth) }
        if args.contains(where: { $0 == nil }) { return nil }
        let nums = args.map { $0! }
        if m[1] == "min" { return nums.min() ?? .infinity }
        if m[1] == "max" { return nums.max() ?? -.infinity }
        if nums.count != 3 { return nil }
        return min(max(nums[1], nums[0]), nums[2])
    }

    private static let ENV = JSRegex("^env\\(\\s*([a-z-]+)\\s*(?:,\\s*([^)]+))?\\)$")

    private static func resolveEnv(_ raw: String, _ isWidth: Bool) -> Double? {
        guard let m = ENV.exec(jsTrim(raw)) else { return nil }
        let insets = cssEnvironment().safeArea
        switch m[1] {
        case "safe-area-inset-top": return insets.top
        case "safe-area-inset-right": return insets.right
        case "safe-area-inset-bottom": return insets.bottom
        case "safe-area-inset-left": return insets.left
        default: break
        }
        if let fallback = m[2] { return resolveLength(jsTrim(fallback), isWidth) ?? 0 }
        return 0
    }

    private static func parseAspectRatio(_ value: Any?) -> Double? {
        let v = flattenOptional(value)
        if let n = jsNumber(v) { return n > 0 ? n : nil }
        guard let s = v as? String else { return nil }
        let raw = jsTrim(s).lowercased()
        if raw.isEmpty || raw == "auto" { return nil }
        let parts = jsSplit(raw, "/")
        if parts.count == 2 {
            let w = jsParseFloat(parts[0])
            let h = jsParseFloat(parts[1])
            return w.isFinite && h.isFinite && h != 0 ? w / h : nil
        }
        let r = jsParseFloat(raw)
        return r.isFinite && r > 0 ? r : nil
    }

    private static func parseFlexShorthand(_ m: JSONObject, _ s: CSSStyle) {
        let flex = m["flex"]
        s.flexGrow = parseDouble(pick(m, "flexGrow"))
        s.flexShrink = parseDouble(pick(m, "flexShrink"))
        s.flexBasis = str(pick(m, "flexBasis"))
        guard let f = flex else { return }
        if let n = jsNumber(f) {
            s.flex = n
            return
        }
        let t = jsTrim(jsString(f)).lowercased()
        if t == "none" {
            if s.flexShrink == nil { s.flexShrink = 0 }
            return
        }
        if t == "auto" {
            s.flex = 1
            if s.flexBasis == nil { s.flexBasis = "auto" }
            return
        }
        let parts = jsSplitWhitespace(t)
        let grow = jsParseFloat(parts[0])
        if grow.isFinite {
            // Flutter reads `flex` with parseInt — `flex: "1 1 0%"` → 1.
            s.flex = grow
            if parts.count > 1 {
                let shrink = jsParseFloat(parts[1])
                if shrink.isFinite {
                    if s.flexShrink == nil { s.flexShrink = shrink }
                } else if s.flexBasis == nil {
                    s.flexBasis = parts[1]
                }
            }
            if parts.count > 2 && s.flexBasis == nil { s.flexBasis = parts[2] }
        } else if s.flexBasis == nil {
            s.flexBasis = parts[0]
        }
    }

    // ========================================================================
    // Edge insets, alignment, offsets
    // ========================================================================

    public static func parseEdgeInsets(_ value: Any?, _ emBase: Double? = nil) -> EdgeInsets? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let e = x as? EdgeInsets { return e }
        if let o = objectOf(x) {
            return EdgeInsets(
                top: parseDouble(o["top"], emBase) ?? 0,
                right: parseDouble(o["right"], emBase) ?? 0,
                bottom: parseDouble(o["bottom"], emBase) ?? 0,
                left: parseDouble(o["left"], emBase) ?? 0
            )
        }
        if let a = asArray(x) {
            let nums = a.map { parseDouble($0, emBase) ?? 0 }
            if nums.isEmpty { return nil }
            let f = expandFour(nums)
            return EdgeInsets(top: f[0] ?? 0, right: f[1] ?? 0, bottom: f[2] ?? 0, left: f[3] ?? 0)
        }
        if jsNumber(x) != nil || x is String {
            let parts = jsSplitWhitespace(jsTrim(jsString(stripImportant(x)))).filter { !$0.isEmpty }
            if parts.isEmpty || parts.count > 4 { return nil }
            let nums = parts.map { $0 == "auto" ? 0 : parseLengthToken($0, emBase) ?? 0 }
            let f = expandFour(nums)
            return EdgeInsets(top: f[0] ?? 0, right: f[1] ?? 0, bottom: f[2] ?? 0, left: f[3] ?? 0)
        }
        return nil
    }

    private static let LENGTH_TOKEN_VIEWPORT = JSRegex("vw$|vh$|vmin$|vmax$|^calc\\(|^env\\(")

    private static func parseLengthToken(_ token: String, _ emBase: Double?) -> Double? {
        let t = jsTrim(token).lowercased()
        if t.hasSuffix("%") { return nil } // handled as a percentage by the caller
        if LENGTH_TOKEN_VIEWPORT.test(t) { return parseDimension(t, true) }
        return parseDouble(t, emBase)
    }

    private struct InsetsResult {
        var insets: EdgeInsets?
        var percent: SidePercents?
        var auto: MarginAuto?
    }

    private static let SIDES = ["top", "right", "bottom", "left"]

    private static func parseEdgeInsetsFor(_ m: JSONObject, _ base: String, _ emBase: Double?) -> InsetsResult {
        var percent: [String: Percent] = [:]
        var auto: [String: Bool] = ["top": false, "right": false, "bottom": false, "left": false]
        var any = false
        var values: [String: Double?] = ["top": nil, "right": nil, "bottom": nil, "left": nil]

        if let shorthandRaw = m[base] {
            if isObject(shorthandRaw) {
                if let e = parseEdgeInsets(shorthandRaw, emBase) {
                    values["top"] = e.top
                    values["right"] = e.right
                    values["bottom"] = e.bottom
                    values["left"] = e.left
                    any = true
                }
            } else {
                let parts = jsSplitWhitespace(jsTrim(jsString(stripImportant(shorthandRaw)))).filter { !$0.isEmpty }
                if !parts.isEmpty && parts.count <= 4 {
                    let four = expandFour(parts)
                    for (i, side) in SIDES.enumerated() {
                        applyInsetToken(four[i] ?? "", side, &values, &percent, &auto, emBase)
                    }
                    any = true
                }
            }
        }

        for side in SIDES {
            let sideCap = side.prefix(1).uppercased() + side.dropFirst()
            if let raw = m["\(base)\(sideCap)"] ?? m["\(base)-\(side)"] {
                applyInsetToken(jsString(stripImportant(raw)), side, &values, &percent, &auto, emBase)
                any = true
            }
        }
        // `paddingX`/`paddingY` convenience forms, plus the CSS logical properties.
        let x = m["\(base)X"] ?? m["\(base)Inline"] ?? m["\(base)-inline"]
        let y = m["\(base)Y"] ?? m["\(base)Block"] ?? m["\(base)-block"]
        if let x = x {
            let parts = jsSplitWhitespace(jsTrim(jsString(x)))
            applyInsetToken(parts[0], "left", &values, &percent, &auto, emBase, onlyIfUnset: true)
            applyInsetToken(parts.count > 1 ? parts[1] : parts[0], "right", &values, &percent, &auto, emBase, onlyIfUnset: true)
            any = true
        }
        if let y = y {
            let parts = jsSplitWhitespace(jsTrim(jsString(y)))
            applyInsetToken(parts[0], "top", &values, &percent, &auto, emBase, onlyIfUnset: true)
            applyInsetToken(parts.count > 1 ? parts[1] : parts[0], "bottom", &values, &percent, &auto, emBase, onlyIfUnset: true)
            any = true
        }
        if !any { return InsetsResult(insets: nil, percent: nil, auto: nil) }
        func val(_ k: String) -> Double { (values[k] ?? nil) ?? 0 }
        let pct = SidePercents(top: percent["top"], right: percent["right"], bottom: percent["bottom"], left: percent["left"])
        let a = MarginAuto(top: auto["top"]!, right: auto["right"]!, bottom: auto["bottom"]!, left: auto["left"]!)
        return InsetsResult(
            insets: EdgeInsets(top: val("top"), right: val("right"), bottom: val("bottom"), left: val("left")),
            percent: percent.isEmpty ? nil : pct,
            auto: a.top || a.right || a.bottom || a.left ? a : nil
        )
    }

    private static func applyInsetToken(
        _ token: String,
        _ side: String,
        _ values: inout [String: Double?],
        _ percent: inout [String: Percent],
        _ auto: inout [String: Bool],
        _ emBase: Double?,
        onlyIfUnset: Bool = false
    ) {
        if onlyIfUnset, let existing = values[side], existing != nil { return }
        let t = jsTrim(token).lowercased()
        if t == "auto" {
            auto[side] = true
            values[side] = .some(0)
            percent.removeValue(forKey: side)
            return
        }
        auto[side] = false
        if t.hasSuffix("%") {
            let n = jsParseFloat(t)
            if n.isFinite {
                percent[side] = Percent(n)
                values[side] = .some(0)
            }
            return
        }
        percent.removeValue(forKey: side)
        values[side] = .some(parseLengthToken(t, emBase) ?? 0)
    }

    private static let alignmentMap: [String: Alignment] = [
        "center": .center,
        "topleft": .topLeft,
        "top-left": .topLeft,
        "topcenter": .topCenter,
        "top-center": .topCenter,
        "topright": .topRight,
        "top-right": .topRight,
        "centerleft": .centerLeft,
        "center-left": .centerLeft,
        "centerright": .centerRight,
        "center-right": .centerRight,
        "bottomleft": .bottomLeft,
        "bottom-left": .bottomLeft,
        "bottomcenter": .bottomCenter,
        "bottom-center": .bottomCenter,
        "bottomright": .bottomRight,
        "bottom-right": .bottomRight,
    ]

    public static func parseAlignment(_ value: Any?) -> Alignment? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let a = x as? Alignment { return a }
        if let s = x as? String {
            let key = jsTrim(s).lowercased()
            if let direct = alignmentMap[key] { return direct }
            // CSS position keywords: `top`, `left`, `center center`, `right bottom`, `25% 75%`.
            return parsePositionKeywords(key)
        }
        if isObject(x) {
            return Alignment(x: parseDouble(field(x, "x")) ?? 0, y: parseDouble(field(x, "y")) ?? 0)
        }
        return nil
    }

    public static func parsePositionKeywords(_ key: String) -> Alignment? {
        let tokens = jsSplitWhitespace(key).filter { !$0.isEmpty }
        if tokens.isEmpty || tokens.count > 2 { return nil }
        var x: Double?
        var y: Double?
        var unresolved = 0
        for t in tokens {
            if t == "left" { x = -1 }
            else if t == "right" { x = 1 }
            else if t == "top" { y = -1 }
            else if t == "bottom" { y = 1 }
            else if t.hasSuffix("%") {
                let n = jsParseFloat(t)
                if !n.isFinite { return nil }
                let v = n / 50 - 1
                if x == nil { x = v } else { y = v }
            } else if t == "center" {
                unresolved += 1
            } else {
                return nil
            }
        }
        for _ in 0..<unresolved {
            if x == nil { x = 0 } else if y == nil { y = 0 }
        }
        if x == nil && y == nil { return nil }
        return Alignment(x: x ?? 0, y: y ?? 0)
    }

    private static func parseOriginString(_ value: Any?) -> Alignment? {
        guard let s = flattenOptional(value) as? String else { return nil }
        return parsePositionKeywords(jsTrim(s).lowercased())
    }

    public static func parseOffset(_ value: Any?) -> Offset? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let o = x as? Offset { return o }
        if let a = asArray(x), a.count == 2 {
            return Offset(dx: parseDouble(a[0]) ?? 0, dy: parseDouble(a[1]) ?? 0)
        }
        if let o = objectOf(x) {
            return Offset(dx: parseDouble(o["x"] ?? o["dx"]) ?? 0, dy: parseDouble(o["y"] ?? o["dy"]) ?? 0)
        }
        return nil
    }

    private static func parseTranslateString(_ value: Any?) -> Offset? {
        guard let s = flattenOptional(value) as? String else { return nil }
        let parts = jsSplitWhitespace(jsTrim(s))
        guard let dx = parseDouble(parts[0]) else { return nil }
        return Offset(dx: dx, dy: parseDouble(parts.count > 1 ? parts[1] : nil) ?? 0)
    }

    // ========================================================================
    // Enumerations
    // ========================================================================

    private static let fontWeightMap: [String: Int] = [
        "thin": 100, "hairline": 100, "extralight": 200, "extra-light": 200, "ultralight": 200,
        "light": 300, "normal": 400, "regular": 400, "medium": 500, "semibold": 600, "semi-bold": 600,
        "demibold": 600, "bold": 700, "extrabold": 800, "extra-bold": 800, "black": 900, "heavy": 900,
        "bolder": 700, "lighter": 300,
    ]

    public static func parseFontWeight(_ value: Any?) -> Int? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let n = jsNumber(x) {
            let idx = min(9, max(1, jsTrunc(n / 100)))
            return Int(idx.isNaN ? 1 : idx) * 100
        }
        let t = jsTrim(jsString(x)).lowercased()
        if let w = fontWeightMap[t] { return w }
        let n = jsParseInt(t.hasPrefix("w") ? String(t.dropFirst()) : t, 10)
        if n.isFinite {
            let idx = min(9, max(1, jsTrunc(n / 100)))
            return Int(idx) * 100
        }
        return nil
    }

    private static func parseFontStyle(_ value: Any?) -> String? {
        guard let s = flattenOptional(value) as? String else { return nil }
        let t = jsTrim(s).lowercased()
        if t == "italic" || t == "oblique" { return "italic" }
        if t == "normal" { return "normal" }
        return nil
    }

    private static let FONT_SHORTHAND = JSRegex(
        "^\\s*((?:(?:italic|oblique|normal|bold|bolder|lighter|small-caps|\\d{3})\\s+)*)([\\d.]+(?:px|em|rem|pt|%)?)(?:\\s*/\\s*([\\d.]+(?:px|em|rem|%)?))?\\s+(.+)$",
        ignoreCase: true
    )

    private static func parseFontShorthand(_ value: Any?, _ s: CSSStyle) {
        guard let str = flattenOptional(value) as? String else { return }
        // [style] [variant] [weight] size[/line-height] family
        guard let m = FONT_SHORTHAND.exec(str) else { return }
        for token in jsSplitWhitespace(jsTrim(m[1] ?? "")).filter({ !$0.isEmpty }) {
            let lower = token.lowercased()
            if lower == "italic" || lower == "oblique" {
                if s.fontStyle == nil { s.fontStyle = "italic" }
            } else if let w = parseFontWeight(lower), lower != "normal" {
                if s.fontWeight == nil { s.fontWeight = w }
            }
        }
        if s.fontSize == nil { s.fontSize = parseFontSize(m[2]) }
        if let lh = m[3], !lh.isEmpty { parseLineHeight(lh, s) }
        if s.fontFamily == nil { s.fontFamily = jsTrim(m[4] ?? "") }
    }

    private static let PLAIN_NUMBER = JSRegex("^[\\d.]+$")

    private static func parseLineHeight(_ value: Any?, _ s: CSSStyle) {
        let v = flattenOptional(value)
        guard let x = v else { return }
        if let n = jsNumber(x) {
            s.lineHeight = n
            return
        }
        let t = jsTrim(jsString(stripImportant(x))).lowercased()
        if t == "normal" { return }
        if PLAIN_NUMBER.test(t) {
            s.lineHeight = jsParseFloat(t)
            return
        }
        if t.hasSuffix("%") {
            s.lineHeight = jsParseFloat(t) / 100
            return
        }
        if t.hasSuffix("em") && !t.hasSuffix("rem") {
            s.lineHeight = jsParseFloat(t)
            return
        }
        if let px = parseDouble(t) { s.lineHeightPx = px }
    }

    private static let textAlignMap: [String: String] = [
        "left": "left", "right": "right", "center": "center", "justify": "justify", "start": "start", "end": "end",
    ]

    private static func parseTextAlign(_ value: Any?) -> String? {
        guard let s = flattenOptional(value) as? String else { return nil }
        return textAlignMap[jsTrim(s).lowercased()]
    }

    private static func parseTextDecoration(_ value: Any?) -> (decoration: TextDecoration?, color: Color?, style: String?) {
        guard let s = flattenOptional(value) as? String else { return (nil, nil, nil) }
        var deco = TextDecoration()
        var color: Color?
        var style: String?
        var known = false
        for token in splitTopLevel(jsTrim(s).lowercased(), " ").filter({ !$0.isEmpty }) {
            if token == "underline" { deco.underline = true; known = true }
            else if token == "overline" { deco.overline = true; known = true }
            else if token == "line-through" || token == "linethrough" { deco.lineThrough = true; known = true }
            else if token == "none" { known = true }
            else if ["solid", "double", "dotted", "dashed", "wavy"].contains(token) { style = token }
            else { color = ElpianCore.parseColor(token) ?? color }
        }
        return (known ? deco : nil, color, style)
    }

    private static func parseTextOverflow(_ value: Any?) -> TextOverflow? {
        guard let s = flattenOptional(value) as? String else { return nil }
        return TextOverflow(rawValue: jsTrim(s).lowercased())
    }

    private static let overflowMap: [String: String] = [
        "visible": "visible", "hidden": "hidden", "clip": "clip", "auto": "scroll", "scroll": "scroll", "overlay": "scroll",
    ]

    private static func parseOverflow(_ value: Any?) -> String? {
        guard let s = flattenOptional(value) as? String else { return nil }
        let token = jsSplitWhitespace(jsTrim(s).lowercased())[0]
        return overflowMap[token]
    }

    private static let boxFitMap: [String: BoxFit] = [
        "fill": .fill, "contain": .contain, "cover": .cover, "fitwidth": .fitWidth, "fit-width": .fitWidth,
        "fitheight": .fitHeight, "fit-height": .fitHeight, "none": .none, "scaledown": .scaleDown, "scale-down": .scaleDown,
        "100% 100%": .fill,
    ]

    public static func parseBoxFit(_ value: Any?) -> BoxFit? {
        guard let s = flattenOptional(value) as? String else { return nil }
        return boxFitMap[jsTrim(s).lowercased()]
    }

    private static func parseBackgroundSizePx(_ value: Any?) -> SizePx? {
        guard let s = flattenOptional(value) as? String else { return nil }
        let t = jsTrim(s).lowercased()
        if boxFitMap[t] != nil { return nil }
        let parts = jsSplitWhitespace(t)
        let w = parts[0] == "auto" ? nil : parseDouble(parts[0])
        let h = parts.count > 1 ? (parts[1] == "auto" ? nil : parseDouble(parts[1])) : nil
        if w == nil && h == nil { return nil }
        return SizePx(width: w, height: h)
    }

    // ========================================================================
    // Borders and radii
    // ========================================================================

    private static func borderStyle(_ s: String) -> BorderStyleName? { BorderStyleName(rawValue: s) }

    private static func parseBorderSideMap(_ value: Any?, _ emBase: Double?) -> BorderSide? {
        let v = flattenOptional(value)
        guard v != nil, isObject(v) else { return nil }
        let style = jsString(field(v, "style") ?? "solid").lowercased()
        return BorderSide(
            width: parseDouble(field(v, "width"), emBase) ?? 1,
            color: ElpianCore.parseColor(field(v, "color")) ?? 0xFF00_0000,
            style: borderStyle(style) ?? .solid
        )
    }

    private static let BORDER_NONE = JSRegex("^(none|0|hidden)$", ignoreCase: true)
    private static let STARTS_NUMERIC = JSRegex("^-?[\\d.]")

    public static func parseBorderSideString(_ value: String, _ emBase: Double?) -> BorderSide? {
        let t = jsTrim(jsString(stripImportant(value)))
        if t.isEmpty { return nil }
        if BORDER_NONE.test(t) { return BorderSide(width: 0, color: 0xFF00_0000, style: .none) }
        var width: Double?
        var style: BorderStyleName?
        var color: Color?
        for token in splitTopLevel(t, " ").filter({ !$0.isEmpty }) {
            let lower = token.lowercased()
            if borderStyle(lower) != nil || lower == "groove" || lower == "ridge" || lower == "inset" || lower == "outset" {
                style = borderStyle(lower) ?? .solid
            } else if lower == "thin" { width = 1 }
            else if lower == "medium" { width = 3 }
            else if lower == "thick" { width = 5 }
            else if STARTS_NUMERIC.test(lower) { width = parseDouble(lower, emBase) }
            else { color = ElpianCore.parseColor(token) ?? color }
        }
        return BorderSide(width: width ?? 3, color: color ?? 0xFF00_0000, style: style ?? .none)
    }

    private static func parseBorderSideAny(_ value: Any?, _ emBase: Double?) -> BorderSide? {
        let v = flattenOptional(value)
        guard v != nil else { return nil }
        if isObject(v) { return parseBorderSideMap(v, emBase) }
        return parseBorderSideString(jsString(v), emBase)
    }

    private static func parseBorder(_ m: JSONObject, _ s: CSSStyle, _ emBase: Double?) -> Border? {
        let none = BorderSide(width: 0, color: 0xFF00_0000, style: .none)
        var top: BorderSide?, right: BorderSide?, bottom: BorderSide?, left: BorderSide?
        var any = false

        if let all = m["border"] {
            if let o = objectOf(all) {
                // Flutter's map form: { top: {color,width}, right: …, … }
                if o.has("top") || o.has("right") || o.has("bottom") || o.has("left") {
                    top = parseBorderSideMap(o["top"], emBase) ?? none
                    right = parseBorderSideMap(o["right"], emBase) ?? none
                    bottom = parseBorderSideMap(o["bottom"], emBase) ?? none
                    left = parseBorderSideMap(o["left"], emBase) ?? none
                } else {
                    let side = parseBorderSideMap(o, emBase)
                    top = side; right = side; bottom = side; left = side
                }
                any = true
            } else if let side = parseBorderSideString(jsString(all), emBase) {
                top = side; right = side; bottom = side; left = side
                any = true
            }
        }

        for sideName in SIDES {
            let cap = sideName.prefix(1).uppercased() + sideName.dropFirst()
            let raw = m["border\(cap)"] ?? m["border-\(sideName)"]
            var side: BorderSide? = raw != nil ? parseBorderSideAny(raw, emBase) : nil
            let width = parseDouble(m["border\(cap)Width"] ?? m["border-\(sideName)-width"], emBase)
            let color = ElpianCore.parseColor(m["border\(cap)Color"] ?? m["border-\(sideName)-color"])
            let styleRaw = m["border\(cap)Style"] ?? m["border-\(sideName)-style"]
            if width != nil || color != nil || styleRaw != nil {
                let base = side ?? (sideName == "top" ? top : sideName == "right" ? right : sideName == "bottom" ? bottom : left)
                let style: BorderStyleName = jsTruthy(styleRaw)
                    ? (borderStyle(jsString(styleRaw).lowercased()) ?? .solid)
                    : (base?.style ?? .solid)
                side = BorderSide(
                    width: width ?? base?.width ?? 1,
                    color: color ?? base?.color ?? s.borderColor ?? 0xFF00_0000,
                    style: style
                )
            }
            if let side = side {
                any = true
                switch sideName {
                case "top": top = side
                case "right": right = side
                case "bottom": bottom = side
                default: left = side
                }
            }
        }

        // `border-color` / `border-width` / `border-style` multi-value shorthands
        // refine a border declared elsewhere (Flutter combines borderColor +
        // borderWidth into Border.all — that case is handled in lowering).
        let widthRaw = pick(m, "borderWidth")
        let colorRaw = pick(m, "borderColor")
        let styleRaw = pick(m, "borderStyle")
        func multi(_ v: Any?) -> Bool {
            guard let s = flattenOptional(v) as? String else { return false }
            return splitTopLevel(jsTrim(s), " ").filter { !$0.isEmpty }.count > 1
        }
        func widthsOf(_ v: Any?) -> [Double?] {
            expandFour(splitTopLevel(jsTrim(jsString(v)), " ").filter { !$0.isEmpty }.map { parseDouble($0, emBase) ?? 0 })
        }
        func colorsOf(_ v: Any?) -> [Color?] {
            expandFour(splitTopLevel(jsTrim(jsString(v)), " ").filter { !$0.isEmpty }.map { ElpianCore.parseColor($0) ?? 0xFF00_0000 })
        }
        func stylesOf(_ v: Any?) -> [BorderStyleName?] {
            expandFour(jsSplitWhitespace(jsTrim(jsString(v))).map { borderStyle($0.lowercased()) ?? .solid })
        }
        if any && (widthRaw != nil || colorRaw != nil || styleRaw != nil) {
            let widths = widthRaw != nil ? widthsOf(widthRaw) : nil
            let colors = colorRaw != nil ? colorsOf(colorRaw) : nil
            let styles = styleRaw != nil ? stylesOf(styleRaw) : nil
            let sides = [top, right, bottom, left].enumerated().map { (i, side) -> BorderSide? in
                guard let side = side else { return nil }
                return BorderSide(
                    width: (widths?[i] ?? nil) ?? side.width,
                    color: (colors?[i] ?? nil) ?? side.color,
                    style: (styles?[i] ?? nil) ?? side.style
                )
            }
            top = sides[0]; right = sides[1]; bottom = sides[2]; left = sides[3]
        } else if !any && (multi(widthRaw) || multi(colorRaw) || multi(styleRaw)) && (widthRaw != nil || styleRaw != nil) {
            let widths = widthsOf(widthRaw ?? "1")
            let colors = colorsOf(colorRaw ?? "#000")
            let styles = stylesOf(styleRaw ?? "solid")
            let sides = (0..<4).map { i in
                BorderSide(width: widths[i] ?? 0, color: colors[i] ?? 0xFF00_0000, style: styles[i] ?? .solid)
            }
            top = sides[0]; right = sides[1]; bottom = sides[2]; left = sides[3]
            any = true
        }

        if !any { return nil }
        return Border(top: top ?? none, right: right ?? none, bottom: bottom ?? none, left: left ?? none)
    }

    private static let CORNERS = ["topLeft", "topRight", "bottomRight", "bottomLeft"]
    private static let CORNER_LONGHAND = ["borderTopLeftRadius", "borderTopRightRadius", "borderBottomRightRadius", "borderBottomLeftRadius"]

    private static func parseBorderRadius(_ m: JSONObject, _ emBase: Double?) -> (px: BorderRadius?, percent: BorderRadius?) {
        var px = BorderRadius.zero
        var pct = BorderRadius.zero
        var anyPx = false
        var anyPct = false

        func assign(_ corner: Int, _ token: Any?) {
            let t = flattenOptional(token)
            guard t != nil else { return }
            if let s = t as? String, jsTrim(s).hasSuffix("%") {
                let n = jsParseFloat(s)
                if n.isFinite {
                    pct[corner] = n
                    px[corner] = 0
                    anyPct = true
                }
                return
            }
            if let n = parseDouble(t, emBase) {
                px[corner] = n
                pct[corner] = 0
                anyPx = true
            }
        }

        if let all = pick(m, "borderRadius") {
            if let o = objectOf(all) {
                for (i, c) in CORNERS.enumerated() { assign(i, o[c] ?? o[kebab(c)]) }
            } else if jsNumber(all) != nil {
                for i in 0..<4 { assign(i, all) }
            } else {
                // `a b c d` (elliptical `/` forms use the horizontal radius).
                let first = jsSplit(jsString(stripImportant(all)), "/")[0]
                let horizontal = jsSplitWhitespace(jsTrim(first)).filter { !$0.isEmpty }
                if !horizontal.isEmpty {
                    let four = expandFour(horizontal)
                    for i in 0..<4 { assign(i, four[i]) }
                }
            }
        }
        for i in 0..<4 { assign(i, pick(m, CORNER_LONGHAND[i])) }
        return (anyPx ? px : nil, anyPct ? pct : nil)
    }

    // ========================================================================
    // Shadows
    // ========================================================================

    public static func parseBoxShadow(_ value: Any?) -> [BoxShadow]? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let a = asArray(x) {
            return a.map { raw -> BoxShadow in
                let shadow = flattenOptional(raw)
                if isObject(shadow) {
                    let offset = parseOffset(field(shadow, "offset"))
                        ?? Offset(dx: parseDouble(field(shadow, "dx") ?? field(shadow, "x")) ?? 0, dy: parseDouble(field(shadow, "dy") ?? field(shadow, "y")) ?? 0)
                    return BoxShadow(
                        color: ElpianCore.parseColor(field(shadow, "color")) ?? 0x4200_0000,
                        dx: offset.dx,
                        dy: offset.dy,
                        blur: parseDouble(field(shadow, "blurRadius") ?? field(shadow, "blur")) ?? 0,
                        spread: parseDouble(field(shadow, "spreadRadius") ?? field(shadow, "spread")) ?? 0,
                        inset: jsBool(field(shadow, "inset")) == true
                    )
                }
                if let s = shadow as? String { return parseShadowString(s) ?? zeroShadow() }
                return zeroShadow()
            }
        }
        if objectOf(x) != nil { return parseBoxShadow([x]) }
        if let s = x as? String {
            let t = jsTrim(s)
            if t.isEmpty || t == "none" { return nil }
            let out = splitTopLevel(t, ",").compactMap { parseShadowString($0) }
            return out.isEmpty ? nil : out
        }
        return nil
    }

    private static func zeroShadow() -> BoxShadow {
        BoxShadow(color: 0xFF00_0000, dx: 0, dy: 0, blur: 0, spread: 0)
    }

    private static func parseShadowString(_ raw: String) -> BoxShadow? {
        let tokens = splitTopLevel(jsTrim(raw), " ").filter { !$0.isEmpty }
        var lengths: [Double] = []
        var color: Color?
        var inset = false
        for token in tokens {
            if token.lowercased() == "inset" { inset = true }
            else if STARTS_NUMERIC.test(token) { lengths.append(parseDouble(token) ?? 0) }
            else { color = ElpianCore.parseColor(token) ?? color }
        }
        if lengths.count < 2 { return nil }
        return BoxShadow(
            color: color ?? 0xFF00_0000,
            dx: lengths[0],
            dy: lengths[1],
            blur: lengths.count > 2 ? lengths[2] : 0,
            spread: lengths.count > 3 ? lengths[3] : 0,
            inset: inset
        )
    }

    private static func parseTextShadow(_ value: Any?) -> [TextShadow]? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if x is String || objectOf(x) != nil {
            return parseBoxShadow(x)?.map { TextShadow(color: $0.color, dx: $0.dx, dy: $0.dy, blur: $0.blur) }
        }
        if let a = asArray(x) {
            return a.map { raw -> TextShadow in
                let shadow = flattenOptional(raw)
                if isObject(shadow) {
                    let offset = parseOffset(field(shadow, "offset")) ?? Offset(dx: 0, dy: 0)
                    return TextShadow(
                        color: ElpianCore.parseColor(field(shadow, "color")) ?? 0x4200_0000,
                        dx: offset.dx,
                        dy: offset.dy,
                        blur: parseDouble(field(shadow, "blurRadius") ?? field(shadow, "blur")) ?? 0
                    )
                }
                if let s = shadow as? String, let parsed = parseShadowString(s) {
                    return TextShadow(color: parsed.color, dx: parsed.dx, dy: parsed.dy, blur: parsed.blur)
                }
                return TextShadow(color: 0xFF00_0000, dx: 0, dy: 0, blur: 0)
            }
        }
        return nil
    }

    // ========================================================================
    // Transforms
    // ========================================================================

    public static func parseAngleDegrees(_ value: Any?) -> Double? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let n = jsNumber(x) { return n }
        let t = jsTrim(jsString(x)).lowercased()
        let n = jsParseFloat(t)
        if !n.isFinite { return nil }
        if t.hasSuffix("rad") { return n * 180 / Double.pi }
        if t.hasSuffix("turn") { return n * 360 }
        if t.hasSuffix("grad") { return n * 0.9 }
        return n
    }

    private static func angleRadians(_ token: String) -> Double {
        (parseAngleDegrees(token) ?? 0) * Double.pi / 180
    }

    private static let TRANSFORM_FN = JSRegex("([a-zA-Z0-9]+)\\(([^)]*)\\)")
    private static let ARG_SEPARATORS = JSRegex("[\\s,]+")

    public static func parseTransform(_ value: Any?) -> Matrix4? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let a = asArray(x), a.count == 16 { return a.map { jsToNumber($0) } }
        guard let s = x as? String else { return nil }
        let t = jsTrim(s)
        if t.isEmpty || t == "none" { return nil }
        var matrix = Matrix.identity()
        var any = false
        for match in TRANSFORM_FN.matchAll(t) {
            let fn = (match[1] ?? "").lowercased()
            let args = ARG_SEPARATORS.split(match[2] ?? "").filter { !$0.isEmpty }
            func arg(_ i: Int) -> String? { i < args.count ? args[i] : nil }
            var step: Matrix4?
            switch fn {
            case "translate":
                step = Matrix.translation(parseDouble(arg(0)) ?? 0, parseDouble(arg(1)) ?? 0, 0)
            case "translatex":
                step = Matrix.translation(parseDouble(arg(0)) ?? 0, 0, 0)
            case "translatey":
                step = Matrix.translation(0, parseDouble(arg(0)) ?? 0, 0)
            case "translate3d":
                step = Matrix.translation(parseDouble(arg(0)) ?? 0, parseDouble(arg(1)) ?? 0, parseDouble(arg(2)) ?? 0)
            case "rotate", "rotatez":
                step = Matrix.rotationZ(angleRadians(arg(0) ?? "0"))
            case "scale":
                let sx = jsParseFloat(arg(0) ?? "1")
                let sy = args.count > 1 ? jsParseFloat(args[1]) : sx
                step = Matrix.scaling(sx, sy, 1)
            case "scalex":
                step = Matrix.scaling(jsParseFloat(arg(0) ?? "1"), 1, 1)
            case "scaley":
                step = Matrix.scaling(1, jsParseFloat(arg(0) ?? "1"), 1)
            case "skew":
                step = Matrix.skew(angleRadians(arg(0) ?? "0"), angleRadians(arg(1) ?? "0"))
            case "skewx":
                step = Matrix.skew(angleRadians(arg(0) ?? "0"), 0)
            case "skewy":
                step = Matrix.skew(0, angleRadians(arg(0) ?? "0"))
            case "matrix", "matrix3d":
                step = Matrix.fromCssMatrix(args.map { jsParseFloat($0) })
            default:
                step = nil
            }
            if let step = step {
                matrix = Matrix.multiply(matrix, step)
                any = true
            }
        }
        return any ? matrix : nil
    }

    // ========================================================================
    // Gradients and backgrounds
    // ========================================================================

    public static func isGradientValue(_ value: Any?) -> Bool {
        guard let s = flattenOptional(value) as? String else { return false }
        return s.contains("gradient(")
    }

    private static let URL_RE = JSRegex("url\\(\\s*(['\"]?)(.*?)\\1\\s*\\)")

    private static func extractUrl(_ value: String) -> String? {
        if let m = URL_RE.exec(value) { return m[2] ?? "" }
        let t = jsTrim(value)
        return t.isEmpty || t == "none" ? nil : t
    }

    /** Split on [separator] outside parentheses and quotes (`' '` splits on any whitespace and drops empties). */
    public static func splitTopLevel(_ input: String, _ separator: String) -> [String] {
        let u = Array(input.utf16)
        let sep = separator.utf16.first ?? 0
        let isSpace = separator == " "
        var out: [String] = []
        var depth = 0
        var quote: UInt16?
        var start = 0
        for i in 0..<u.count {
            let ch = u[i]
            if let q = quote {
                if ch == q { quote = nil }
                continue
            }
            if ch == 0x22 || ch == 0x27 { quote = ch }
            else if ch == 0x28 { depth += 1 }
            else if ch == 0x29 { depth = max(0, depth - 1) }
            else if depth == 0 && (isSpace ? isRegexSpace(ch) : ch == sep) {
                out.append(String(decoding: u[start..<i], as: UTF16.self))
                start = i + 1
            }
        }
        out.append(String(decoding: u[start...], as: UTF16.self))
        return isSpace ? out.filter { !jsTrim($0).isEmpty } : out
    }

    private static func isRegexSpace(_ c: UInt16) -> Bool {
        switch c {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        case 0x2000...0x200A: return true
        default: return false
        }
    }

    private static func angleForSideKeyword(_ side: String) -> Double {
        switch jsTrim(WHITESPACE.replace(side, with: " ")) {
        case "top": return 0
        case "top right", "right top": return 45
        case "right": return 90
        case "bottom right", "right bottom": return 135
        case "bottom": return 180
        case "bottom left", "left bottom": return 225
        case "left": return 270
        case "top left", "left top": return 315
        default: return 180
        }
    }

    private static let WHITESPACE = JSRegex("\\s+")

    /**
     * Begin/end alignments for a CSS angle. Flutter snaps to the nearest 45°
     * (eight compass directions); arbitrary angles are expressed exactly here
     * with alignments on the unit square, which is the same line for the eight
     * snapped angles.
     */
    public static func beginEndForAngle(_ deg: Double) -> (Alignment, Alignment) {
        let a = ((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) * (Double.pi / 180)
        // CSS: 0deg points up, angles turn clockwise.
        let dx = sin(a)
        let dy = -cos(a)
        let scale = 1 / max(abs(dx), abs(dy))
        let ex = dx * scale
        let ey = dy * scale
        func round(_ v: Double) -> Double { abs(v) < 1e-9 ? 0 : v }
        return (Alignment(x: round(-ex), y: round(-ey)), Alignment(x: round(ex), y: round(ey)))
    }

    private static let ANGLE_TOKEN = JSRegex("^-?[\\d.]+(deg|rad|turn|grad)$")
    private static let FROM_ANGLE = JSRegex("from\\s+(-?[\\d.]+\\w*)")

    private static func parseCssGradientString(_ raw: String) -> Gradient? {
        let s = jsTrim(raw)
        let lower = s.lowercased()
        let kind: GradientKind = lower.contains("radial-gradient") ? .radial : lower.contains("conic-gradient") ? .sweep : .linear
        let repeating = lower.hasPrefix("repeating-")
        let open = jsIndexOf(s, "(")
        let close = jsLastIndexOf(s, ")")
        if open < 0 || close <= open { return nil }
        let parts = splitTopLevel(jsSubstring(s, open + 1, close), ",")
        if parts.isEmpty { return nil }

        var angleDeg: Double?
        var center: Alignment?
        var startAngle = 0.0
        var colorParts = parts
        let first = jsTrim(parts[0]).lowercased()
        if kind == .linear {
            if ANGLE_TOKEN.test(first) {
                angleDeg = parseAngleDegrees(first)
                colorParts = Array(parts.dropFirst())
            } else if first.hasPrefix("to ") {
                angleDeg = angleForSideKeyword(jsSubstring(first, 3))
                colorParts = Array(parts.dropFirst())
            }
        } else if kind == .radial {
            if !looksLikeColorStop(first) {
                let at = jsIndexOf(first, "at ")
                if at >= 0 { center = parsePositionKeywords(jsTrim(jsSubstring(first, at + 3))) }
                colorParts = Array(parts.dropFirst())
            }
        } else {
            if !looksLikeColorStop(first) {
                if let from = FROM_ANGLE.exec(first), let a = from[1] { startAngle = angleRadians(a) }
                let at = jsIndexOf(first, "at ")
                if at >= 0 { center = parsePositionKeywords(jsTrim(jsSubstring(first, at + 3))) }
                colorParts = Array(parts.dropFirst())
            }
        }

        var colors: [Color] = []
        var stops: [Double?] = []
        for part in colorParts {
            let t = jsTrim(part)
            if t.isEmpty { continue }
            let tokens = splitTopLevel(t, " ")
            guard let color = ElpianCore.parseColor(tokens.first) else { continue }
            let positions = tokens.dropFirst().map { parseStopPosition($0) }
            if positions.isEmpty {
                colors.append(color)
                stops.append(nil)
            } else {
                for pos in positions {
                    colors.append(color)
                    stops.append(pos)
                }
            }
        }
        if colors.isEmpty { return nil }
        if colors.count == 1 {
            colors.append(colors[0])
            stops.append(nil)
        }
        let resolvedStops = resolveStops(stops)

        if kind == .radial {
            return Gradient(kind: kind, colors: colors, stops: resolvedStops, center: center ?? .center, radius: 0.5, repeat: repeating)
        }
        if kind == .sweep {
            // CSS conic gradients start at 12 o'clock; Flutter sweeps start at 3 o'clock.
            return Gradient(
                kind: kind,
                colors: colors,
                stops: resolvedStops,
                center: center ?? .center,
                startAngle: startAngle - Double.pi / 2,
                endAngle: startAngle - Double.pi / 2 + Double.pi * 2,
                repeat: repeating
            )
        }
        let (begin, end) = beginEndForAngle(angleDeg ?? 180)
        return Gradient(kind: kind, colors: colors, stops: resolvedStops, begin: begin, end: end, repeat: repeating)
    }

    private static func looksLikeColorStop(_ token: String) -> Bool {
        ElpianCore.parseColor(splitTopLevel(token, " ").first) != nil
    }

    private static let DEG_OR_TURN = JSRegex("deg$|turn$")

    private static func parseStopPosition(_ token: String) -> Double? {
        let t = jsTrim(token)
        if t.hasSuffix("%") {
            let n = jsParseFloat(t)
            return n.isFinite ? max(0, min(1, n / 100)) : nil
        }
        if DEG_OR_TURN.test(t) { return (parseAngleDegrees(t) ?? 0) / 360 }
        return nil
    }

    /** Fill missing stop positions by spreading evenly between known ones (CSS rules). */
    private static func resolveStops(_ stops: [Double?]) -> [Double]? {
        if stops.allSatisfy({ $0 == nil }) { return nil }
        var out = stops
        if out[0] == nil { out[0] = 0 }
        if out[out.count - 1] == nil { out[out.count - 1] = 1 }
        var i = 0
        while i < out.count {
            if out[i] != nil {
                i += 1
                continue
            }
            let startIdx = i - 1
            var endIdx = i
            while out[endIdx] == nil { endIdx += 1 }
            let a = out[startIdx]!
            let b = out[endIdx]!
            let span = Double(endIdx - startIdx)
            for k in (startIdx + 1)..<endIdx { out[k] = a + (b - a) * Double(k - startIdx) / span }
            i = endIdx
        }
        // Monotonic, as CSS requires.
        for k in 1..<max(1, out.count) where out[k]! < out[k - 1]! { out[k] = out[k - 1] }
        return out.map { $0! }
    }

    private static func parseGradientLayers(_ value: String) -> [Gradient] {
        splitTopLevel(value, ",")
            .map { jsTrim($0) }
            .filter { isGradientValue($0) }
            .compactMap { parseCssGradientString($0) }
    }

    public static func parseGradient(_ value: Any?) -> Gradient? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let g = x as? Gradient { return g }
        if let s = x as? String { return parseGradientLayers(s).first }
        if let o = objectOf(x) {
            let type = jsString(o["type"] ?? "linear").lowercased()
            guard let rawColors = asArray(o["colors"]) else { return nil }
            let colors = rawColors.map { ElpianCore.parseColor($0) ?? 0x0000_0000 }
            if colors.isEmpty { return nil }
            let stops = parseNumberList(o["stops"])
            if type == "linear" {
                return Gradient(kind: .linear, colors: colors, stops: stops,
                                begin: parseAlignment(o["begin"]) ?? .topCenter, end: parseAlignment(o["end"]) ?? .bottomCenter)
            }
            if type == "radial" {
                return Gradient(kind: .radial, colors: colors, stops: stops,
                                center: parseAlignment(o["center"]) ?? .center, radius: parseDouble(o["radius"]) ?? 0.5)
            }
            if type == "sweep" {
                return Gradient(kind: .sweep, colors: colors, stops: stops, center: parseAlignment(o["center"]) ?? .center,
                                startAngle: parseDouble(o["startAngle"]) ?? 0, endAngle: parseDouble(o["endAngle"]) ?? Double.pi * 2)
            }
        }
        return nil
    }

    private static let GRADIENT_START = JSRegex("(repeating-)?(linear|radial|conic)-gradient\\(")

    private static func parseBackgroundShorthand(_ value: String) -> (color: Color?, gradients: [Gradient], image: String?) {
        let layers = splitTopLevel(jsTrim(value), ",")
        var gradients: [Gradient] = []
        var color: Color?
        var image: String?
        for layer in layers {
            let t = jsTrim(layer)
            if isGradientValue(t) {
                let at = GRADIENT_START.matchesWithRanges(t).first?.range.location ?? -1
                if let g = parseCssGradientString(at < 0 ? t : jsSubstring(t, at)) { gradients.append(g) }
                continue
            }
            if t.contains("url(") {
                image = extractUrl(t)
            }
            for token in splitTopLevel(t, " ") {
                if let c = ElpianCore.parseColor(token) { color = c }
            }
        }
        return (color, gradients, image)
    }

    private static func parseColorList(_ value: Any?) -> [Color]? {
        guard let a = asArray(value) else { return nil }
        let out = a.compactMap { ElpianCore.parseColor($0) }
        return out.isEmpty ? nil : out
    }

    private static func parseNumberList(_ value: Any?) -> [Double]? {
        guard let a = asArray(value) else { return nil }
        let out = a.compactMap { parseDouble($0) }
        return out.isEmpty ? nil : out
    }

    // ========================================================================
    // Filters
    // ========================================================================

    private static let FILTER_FN = JSRegex("([a-z-]+)\\(([^()]*(?:\\([^()]*\\)[^()]*)*)\\)", ignoreCase: true)

    public static func parseFilter(_ value: Any?) -> Filter? {
        guard let s = flattenOptional(value) as? String else { return nil }
        let t = jsTrim(s)
        if t.isEmpty || t == "none" { return nil }
        var f = Filter()
        func amount(_ arg: String, _ def: Double) -> Double {
            let a = jsTrim(arg)
            if a.isEmpty { return def }
            if a.hasSuffix("%") { return jsParseFloat(a) / 100 }
            return jsParseFloat(a)
        }
        var anySet = false
        for m in FILTER_FN.matchAll(t) {
            let name = (m[1] ?? "").lowercased()
            let arg = m[2] ?? ""
            switch name {
            case "blur": f.blur = parseDouble(arg) ?? 0; anySet = true
            case "brightness": f.brightness = amount(arg, 1); anySet = true
            case "contrast": f.contrast = amount(arg, 1); anySet = true
            case "grayscale": f.grayscale = amount(arg, 1); anySet = true
            case "hue-rotate": f.hueRotate = parseAngleDegrees(arg) ?? 0; anySet = true
            case "invert": f.invert = amount(arg, 1); anySet = true
            case "saturate": f.saturate = amount(arg, 1); anySet = true
            case "sepia": f.sepia = amount(arg, 1); anySet = true
            case "opacity": f.opacity = amount(arg, 1); anySet = true
            case "drop-shadow":
                if let sh = parseShadowString(arg) {
                    f.dropShadow = TextShadow(color: sh.color, dx: sh.dx, dy: sh.dy, blur: sh.blur)
                    anySet = true
                }
            default: break
            }
        }
        return anySet ? f : nil
    }

    // ========================================================================
    // Time
    // ========================================================================

    private static let NON_DIGITS = JSRegex("[^0-9]")

    /** Milliseconds. Flutter: ints are ms; `s`/`ms` suffixes are honoured. */
    public static func parseDuration(_ value: Any?) -> Double? {
        let v = flattenOptional(value)
        guard let x = v else { return nil }
        if let n = jsNumber(x) { return jsTrunc(n) }
        guard let s = x as? String else { return nil }
        let t = jsTrim(s).lowercased()
        if t.hasSuffix("ms") {
            let n = jsParseFloat(t)
            return n.isFinite ? jsTrunc(n) : nil
        }
        if t.hasSuffix("s") {
            let n = jsParseFloat(t)
            return n.isFinite ? jsTrunc(n * 1000) : nil
        }
        let n = jsParseInt(NON_DIGITS.replace(t, with: ""), 10)
        return n.isFinite ? n : nil
    }

    private static let CURVE_SEPARATORS = JSRegex("[-_\\s]")

    /** Normalise a curve name to the lowercase, dash-free key the curve table uses. */
    public static func normalizeCurve(_ value: Any?) -> String? {
        guard let s = flattenOptional(value) as? String else { return nil }
        let t = jsTrim(s)
        if t.isEmpty { return nil }
        if t.hasPrefix("cubic-bezier(") || t.hasPrefix("steps(") { return t.lowercased() }
        return CURVE_SEPARATORS.replace(t.lowercased(), with: "")
    }

    private static let TIME_TOKEN = JSRegex("^[\\d.]+m?s$")
    private static let CURVE_TOKEN = JSRegex("^(ease|linear|step|cubic-bezier|steps)")
    private static let INT_TOKEN = JSRegex("^\\d+$")

    private static func parseTransitionShorthand(_ value: String, _ s: CSSStyle) {
        // `transition: opacity 300ms ease-in-out 100ms` (first layer wins).
        let first = splitTopLevel(value, ",")[0]
        let tokens = splitTopLevel(first, " ")
        var times: [Double] = []
        for token in tokens {
            if TIME_TOKEN.test(token) { times.append(parseDuration(token) ?? 0) }
            else if CURVE_TOKEN.test(token) {
                if s.transitionCurve == nil { s.transitionCurve = normalizeCurve(token) }
            } else if s.transitionProperty == nil {
                s.transitionProperty = token
            }
        }
        if times.count > 0 && s.transitionDuration == nil { s.transitionDuration = times[0] }
        if times.count > 1 && s.transitionDelay == nil { s.transitionDelay = times[1] }
    }

    private static func parseAnimationShorthand(_ value: String, _ s: CSSStyle) {
        let first = splitTopLevel(value, ",")[0]
        let tokens = splitTopLevel(first, " ")
        var times: [Double] = []
        for token in tokens {
            let lower = token.lowercased()
            if TIME_TOKEN.test(lower) { times.append(parseDuration(lower) ?? 0) }
            else if CURVE_TOKEN.test(lower) {
                if s.animationTimingFunction == nil { s.animationTimingFunction = lower }
            } else if lower == "infinite" {
                if s.animationIterationCount == nil { s.animationIterationCount = -1 }
            } else if INT_TOKEN.test(lower) {
                if s.animationIterationCount == nil { s.animationIterationCount = jsParseInt(lower, 10) }
            } else if ["normal", "reverse", "alternate", "alternate-reverse"].contains(lower) {
                if s.animationDirection == nil { s.animationDirection = lower }
            } else if ["forwards", "backwards", "both"].contains(lower) {
                if s.animationFillMode == nil { s.animationFillMode = lower }
            } else if ["running", "paused"].contains(lower) {
                if s.animationPlayState == nil { s.animationPlayState = lower }
            } else if lower != "none" {
                if s.animationName == nil { s.animationName = token }
            }
        }
        if times.count > 0 && s.animationDuration == nil { s.animationDuration = times[0] }
        if times.count > 1 && s.animationDelay == nil { s.animationDelay = times[1] }
    }

    private static func parseKeyframes(_ value: Any?) -> [Keyframe]? {
        guard let a = asArray(value) else { return nil }
        var out: [Keyframe] = []
        for raw in a {
            guard let frame = asMap(raw) else { continue }
            let offset = parseDouble(frame["offset"])
            if let offset = offset, let styles = asMap(frame["styles"]) {
                out.append(Keyframe(offset: offset, styles: styles))
            } else {
                out.append(Keyframe(offset: offset ?? 0, styles: frame))
            }
        }
        return out.isEmpty ? nil : out
    }
}

// Module-level names, as css/parser.ts exports them.
public func parseDouble(_ value: Any?, _ emBase: Double? = nil) -> Double? { CSSParser.parseDouble(value, emBase) }
public func parseDimension(_ value: Any?, _ isWidth: Bool) -> Double? { CSSParser.parseDimension(value, isWidth) }
public func parseEdgeInsets(_ value: Any?, _ emBase: Double? = nil) -> EdgeInsets? { CSSParser.parseEdgeInsets(value, emBase) }
public func parseAlignment(_ value: Any?) -> Alignment? { CSSParser.parseAlignment(value) }
public func parseOffset(_ value: Any?) -> Offset? { CSSParser.parseOffset(value) }
public func parseBoxShadow(_ value: Any?) -> [BoxShadow]? { CSSParser.parseBoxShadow(value) }
public func parseTransform(_ value: Any?) -> Matrix4? { CSSParser.parseTransform(value) }
public func parseGradient(_ value: Any?) -> Gradient? { CSSParser.parseGradient(value) }
public func parseDuration(_ value: Any?) -> Double? { CSSParser.parseDuration(value) }
public func normalizeCurve(_ value: Any?) -> String? { CSSParser.normalizeCurve(value) }
public func isGradientValue(_ value: Any?) -> Bool { CSSParser.isGradientValue(value) }
public func splitTopLevel(_ input: String, _ separator: String) -> [String] { CSSParser.splitTopLevel(input, separator) }
public func beginEndForAngle(_ deg: Double) -> (Alignment, Alignment) { CSSParser.beginEndForAngle(deg) }
public func stripImportant(_ value: Any?) -> Any? { CSSParser.stripImportant(value) }
public func isImportant(_ value: Any?) -> Bool { CSSParser.isImportant(value) }
