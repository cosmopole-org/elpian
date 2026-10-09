import Foundation

/**
 * Stylesheets and the cascade — a port of `CSSStylesheet`,
 * `GlobalStylesheetManager` and `JsonStylesheetParser` (css/stylesheet.ts).
 *
 * Flutter resolves only bare `tag`, `.class` and `#id` selectors, in the order
 * tag → classes → id → @media → inline, with `!important` declarations
 * re-applied on top. That ordering is preserved exactly. The selector engine
 * is a superset: compound selectors (`button.primary#go`), selector lists
 * (`h1, h2`), and descendant / child combinators when the caller supplies the
 * element's ancestry. Custom properties (`--x`) declared on `:root` (or via a
 * JSON stylesheet's `variables`) are substituted into `var(--x, fallback)`.
 */
public typealias StyleMap = JSONObject

/** The facts about an element a selector can test. */
public struct ElementFacts {
    public var tagName: String
    public var id: String?
    public var classes: [String]?
    public var attributes: JSONObject?

    public init(tagName: String, id: String? = nil, classes: [String]? = nil, attributes: JSONObject? = nil) {
        self.tagName = tagName
        self.id = id
        self.classes = classes
        self.attributes = attributes
    }
}

struct CompoundSelector {
    var tag: String?
    var id: String?
    var classes: [String] = []
    var attrs: [(name: String, value: String?)] = []
    var universal = false
    var root = false
}

struct ComplexSelector {
    /** Rightmost compound first; each step names the combinator to its left (" " or ">"). */
    var parts: [(compound: CompoundSelector, combinator: Character?)]
    var specificity: Int
}

private let ruleCounterLock = NSLock()
private var ruleCounter = 0

private func nextRuleOrder() -> Int {
    ruleCounterLock.lock()
    defer { ruleCounterLock.unlock() }
    let n = ruleCounter
    ruleCounter += 1
    return n
}

public final class CSSRule {
    public let selector: String
    public let styles: StyleMap
    public let order: Int
    let selectors: [ComplexSelector]

    public init(_ selector: String, _ styles: StyleMap, _ order: Int) {
        self.selector = selector
        self.styles = styles
        self.order = order
        self.selectors = parseSelectorList(selector)
    }

    /** The selector's best specificity (ids × 10000 + classes × 100 + tags), or -1 when it parses to nothing. */
    public var specificity: Int { selectors.map { $0.specificity }.max() ?? -1 }

    public func toCSS() -> String {
        let body = styles.map { "  \($0.key): \(jsString($0.value));" }.joined(separator: "\n")
        return "\(selector) {\n\(body)\n}\n"
    }
}

public final class CSSStylesheet {
    private var rules: [CSSRule] = []
    private var keyframes: [String: [Keyframe]] = [:]
    private var keyframeOrder: [String] = []

    public init() {}

    public func addRule(_ selector: String, _ styles: StyleMap) {
        let rule = CSSRule(jsTrim(selector), styles, nextRuleOrder())
        // Re-declaring an identical selector replaces it (Flutter's map semantics).
        removeRule(rule.selector)
        rules.append(rule)
    }

    public func removeRule(_ selector: String) {
        rules.removeAll { $0.selector == selector }
    }

    public var allRules: [CSSRule] { rules }

    public func getStyle(_ selector: String) -> StyleMap? {
        rules.first { $0.selector == selector }?.styles
    }

    public func addKeyframeAnimation(_ name: String, _ frames: [Keyframe]) {
        if keyframes[name] == nil { keyframeOrder.append(name) }
        keyframes[name] = frames
    }

    public func getKeyframes(_ name: String) -> [Keyframe]? { keyframes[name] }

    public var keyframeNames: [String] { keyframeOrder }

    /** Root custom properties (`:root { --x: … }`). */
    public func variables() -> StyleMap {
        let out = StyleMap()
        for rule in rules where rule.selectors.contains(where: { $0.parts.count == 1 && $0.parts[0].compound.root }) {
            for (k, v) in rule.styles where k.hasPrefix("--") { out[k] = v }
        }
        return out
    }

    /**
     * The raw cascaded map for an element: matched rules in specificity then
     * source order (tag < class < id, as in Flutter), then [inlineStyles].
     */
    public func getComputedStyleMap(_ element: ElementFacts, _ ancestors: [ElementFacts] = [], _ inlineStyles: StyleMap? = nil) -> StyleMap {
        let merged = StyleMap()
        for rule in matching(element, ancestors) { merged.assign(rule.styles) }
        if let inline = inlineStyles { merged.assign(inline) }
        return merged
    }

    public func matching(_ element: ElementFacts, _ ancestors: [ElementFacts]) -> [CSSRule] {
        var matched: [(rule: CSSRule, specificity: Int)] = []
        for rule in rules {
            var best = -1
            for sel in rule.selectors where sel.specificity > best && matchesComplex(sel, element, ancestors) {
                best = sel.specificity
            }
            if best >= 0 { matched.append((rule, best)) }
        }
        matched.sort { a, b in a.specificity != b.specificity ? a.specificity < b.specificity : a.rule.order < b.rule.order }
        return matched.map { $0.rule }
    }

    public func clear() {
        rules.removeAll()
        keyframes.removeAll()
        keyframeOrder.removeAll()
    }

    public func toCSS() -> String {
        rules.map { $0.toCSS() }.joined(separator: "\n")
    }

    /** Parse CSS text into this stylesheet; returns the `@media` blocks found. */
    @discardableResult
    public func parseCSS(_ cssText: String) -> [(query: String, sheet: CSSStylesheet)] {
        parseCssText(cssText, self)
    }
}

public final class MediaQuery {
    public let query: String
    public let stylesheet: CSSStylesheet

    public init(_ query: String, _ stylesheet: CSSStylesheet) {
        self.query = query
        self.stylesheet = stylesheet
    }

    public func matches(_ width: Double, _ height: Double) -> Bool {
        mediaMatches(query, width, height)
    }
}

private let ONLY_PREFIX = JSRegex("^only\\s+")
private let MINMAX = JSRegex("(min|max)-(width|height):\\s*([\\d.]+)(px|em|rem)?")
private let ORIENTATION = JSRegex("orientation:\\s*(portrait|landscape)")
private let ASPECT = JSRegex("(min|max)-aspect-ratio:\\s*(\\d+)\\s*/\\s*(\\d+)")
private let SCHEME = JSRegex("prefers-color-scheme:\\s*(dark|light)")
private let PRINT = JSRegex("\\bprint\\b")
private let SCREEN = JSRegex("\\bscreen\\b")

/** Flutter's media matcher, extended with `and`/`,`, `not`, aspect ratios and colour scheme. */
public func mediaMatches(_ query: String, _ width: Double, _ height: Double, _ darkMode: Bool = false) -> Bool {
    let alternatives = jsSplit(query, ",").map { jsTrim($0) }.filter { !$0.isEmpty }
    if alternatives.isEmpty { return true }
    return alternatives.contains { alt in
        var negate = false
        var q = alt.lowercased()
        if q.hasPrefix("not ") {
            negate = true
            q = jsSubstring(q, 4)
        }
        q = ONLY_PREFIX.replace(q, with: "", global: false)
        var ok = true
        for m in MINMAX.matchAll(q) {
            let isMin = m[1] == "min"
            let isWidth = m[2] == "width"
            var threshold = jsParseFloat(m[3] ?? "")
            if m[4] == "em" || m[4] == "rem" { threshold *= cssEnvironment().rootFontSize }
            let actual = isWidth ? width : height
            if isMin && actual < threshold { ok = false }
            if !isMin && actual > threshold { ok = false }
        }
        if let om = ORIENTATION.exec(q), (om[1] == "landscape") != (width >= height) { ok = false }
        for m in ASPECT.matchAll(q) {
            let ratio = jsParseFloat(m[2] ?? "") / jsParseFloat(m[3] ?? "")
            let actual = height > 0 ? width / height : 0
            if m[1] == "min" && actual < ratio { ok = false }
            if m[1] == "max" && actual > ratio { ok = false }
        }
        if let scheme = SCHEME.exec(q), (scheme[1] == "dark") != darkMode { ok = false }
        if PRINT.test(q) && !SCREEN.test(q) { ok = false }
        return negate ? !ok : ok
    }
}

/**
 * The per-mini-app stylesheet manager (`GlobalStylesheetManager`): a global
 * sheet, `@media` sheets, keyframes, and the `!important` cascade.
 */
public final class StylesheetManager {
    public let global = CSSStylesheet()
    private var mediaQueries: [MediaQuery] = []
    /** Bumped on every change so render caches can invalidate. */
    public var version = 0
    public var darkMode = false

    public init() {}

    public func addMediaQuery(_ query: String, _ sheet: CSSStylesheet) {
        mediaQueries.removeAll { $0.query == query }
        mediaQueries.append(MediaQuery(query, sheet))
        version += 1
    }

    public func touch() {
        version += 1
    }

    public func keyframes(_ name: String) -> [Keyframe]? {
        if let own = global.getKeyframes(name) { return own }
        for mq in mediaQueries {
            if let frames = mq.stylesheet.getKeyframes(name) { return frames }
        }
        return nil
    }

    public var hasRules: Bool { !global.allRules.isEmpty || !mediaQueries.isEmpty }

    public func getComputedStyleMap(
        _ element: ElementFacts,
        ancestors: [ElementFacts] = [],
        inlineStyles: StyleMap? = nil,
        screenWidth: Double? = nil,
        screenHeight: Double? = nil
    ) -> StyleMap {
        let merged = StyleMap()
        let important = StyleMap()
        func mergeRaw(_ raw: StyleMap?) {
            guard let raw = raw else { return }
            for (key, value) in raw {
                let stripped = stripImportant(value)
                merged[key] = stripped
                if isImportant(value) { important[key] = stripped }
            }
        }
        mergeRaw(global.getComputedStyleMap(element, ancestors))
        if !mediaQueries.isEmpty {
            let env = cssEnvironment()
            let w = screenWidth ?? env.viewportWidth
            let h = screenHeight ?? env.viewportHeight
            for mq in mediaQueries where mediaMatches(mq.query, w, h, darkMode) {
                mergeRaw(mq.stylesheet.getComputedStyleMap(element, ancestors))
            }
        }
        if let inline = inlineStyles { mergeRaw(inline) }
        merged.assign(important)
        return substituteVariables(merged)
    }

    /** Replace `var(--name, fallback)` with root / element custom properties. */
    public func substituteVariables(_ map: StyleMap) -> StyleMap {
        var needs = false
        for v in map.values {
            if let s = v as? String, s.contains("var(") {
                needs = true
                break
            }
        }
        if !needs { return map }
        let vars = global.variables().copy()
        for (k, v) in map where k.hasPrefix("--") { vars[k] = v }
        let out = StyleMap()
        for (k, v) in map {
            if let s = v as? String { out[k] = resolveVars(s, vars, 0) } else { out[k] = v }
        }
        return out
    }

    public func clear() {
        global.clear()
        mediaQueries.removeAll()
        version += 1
    }

    /** Load a JSON stylesheet (`{rules, mediaQueries, variables, keyframes}`) or CSS text. */
    public func load(_ json: Any?) {
        if let css = flattenOptional(json) as? String {
            for block in global.parseCSS(css) { addMediaQuery(block.query, block.sheet) }
            version += 1
            return
        }
        guard let map = asMap(json) else { return }
        let sheet = parseJsonStylesheet(map) { query, mq in self.addMediaQuery(query, mq) }
        for rule in sheet.allRules { global.addRule(rule.selector, rule.styles) }
        for name in sheet.keyframeNames { global.addKeyframeAnimation(name, sheet.getKeyframes(name)!) }
        if let css = map["css"] as? String { load(css) }
        version += 1
    }
}

private let VAR_RE = JSRegex("var\\(\\s*(--[A-Za-z0-9_-]+)\\s*(?:,\\s*([^()]*(?:\\([^()]*\\)[^()]*)*))?\\)")

private func resolveVars(_ value: String, _ vars: StyleMap, _ depth: Int) -> Any? {
    if depth > 8 || !value.contains("var(") { return value }
    let replaced = VAR_RE.replace(value) { m in
        if let v = vars[m[1] ?? ""] { return jsString(v) }
        if let fallback = m[2] { return jsTrim(fallback) }
        return ""
    }
    return resolveVars(replaced, vars, depth + 1)
}

/** `JsonStylesheetParser.parseJsonStylesheet`. */
public func parseJsonStylesheet(_ json: StyleMap, _ onMedia: (String, CSSStylesheet) -> Void) -> CSSStylesheet {
    let sheet = CSSStylesheet()
    if let rules = asArray(json["rules"]) {
        var mediaGroups: [(String, CSSStylesheet)] = []
        for raw in rules {
            guard let rule = asMap(raw) else { continue }
            if let media = rule["media"] as? String, !jsTrim(media).isEmpty {
                let group: CSSStylesheet
                if let existing = mediaGroups.first(where: { $0.0 == media }) {
                    group = existing.1
                } else {
                    group = CSSStylesheet()
                    mediaGroups.append((media, group))
                }
                addJsonRule(rule, group)
            } else {
                addJsonRule(rule, sheet)
            }
        }
        for (query, group) in mediaGroups { onMedia(query, group) }
    }
    if let mediaQueries = asArray(json["mediaQueries"]) {
        for raw in mediaQueries {
            guard let mq = asMap(raw), let query = mq["query"] as? String else { continue }
            let group = CSSStylesheet()
            if let rs = asArray(mq["rules"]) { for r in rs { addJsonRule(r, group) } }
            onMedia(query, group)
        }
    }
    if let variables = asMap(json["variables"]) {
        let vars = StyleMap()
        for (k, v) in variables { vars[k.hasPrefix("--") ? k : "--\(k)"] = v }
        sheet.addRule(":root", vars)
    }
    if let keyframes = asArray(json["keyframes"]) {
        for raw in keyframes {
            guard let kf = asMap(raw), let name = kf["name"] as? String, let rawFrames = asArray(kf["frames"]) else { continue }
            var frames: [Keyframe] = []
            for rf in rawFrames {
                if let f = asMap(rf), let offset = jsNumber(f["offset"]), let styles = asMap(f["styles"]) {
                    frames.append(Keyframe(offset: offset, styles: styles))
                }
            }
            sheet.addKeyframeAnimation(name, frames)
        }
    }
    return sheet
}

private func addJsonRule(_ raw: Any?, _ sheet: CSSStylesheet) {
    guard let rule = asMap(raw), let selector = rule["selector"] as? String, let styles = asMap(rule["styles"]) else { return }
    sheet.addRule(selector, styles)
}

// ============================================================================
// CSS text
// ============================================================================

private let NUMERIC_DECL = JSRegex("^-?\\d+(\\.\\d+)?(px)?$")

private func parseDeclarations(_ body: String) -> StyleMap {
    let styles = StyleMap()
    for decl in splitTopLevel(body, ";") {
        let idx = jsIndexOf(decl, ":")
        if idx <= 0 { continue }
        let key = jsTrim(jsSubstring(decl, 0, idx))
        let text = jsTrim(jsSubstring(decl, idx + 1))
        if key.isEmpty || text.isEmpty { continue }
        var value: Any? = text
        if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
            value = jsSubstring(text, 1, jsLength(text) - 1)
        } else if NUMERIC_DECL.test(text) {
            value = jsParseFloat(text)
        }
        styles[key] = value
    }
    return styles
}

private let COMMENTS = JSRegex("/\\*[\\s\\S]*?\\*/")

private func stripComments(_ css: String) -> String {
    COMMENTS.replace(css, with: "")
}

/** Split CSS text into top-level blocks: `[prelude, body]`. */
private func blocksOf(_ css: String) -> [(String, String)] {
    let u = Array(css.utf16)
    var out: [(String, String)] = []
    var depth = 0
    var preludeStart = 0
    var bodyStart = -1
    func text(_ a: Int, _ b: Int) -> String { a < b ? String(decoding: u[a..<b], as: UTF16.self) : "" }
    for i in 0..<u.count {
        let ch = u[i]
        if ch == 0x7B {
            if depth == 0 { bodyStart = i + 1 }
            depth += 1
        } else if ch == 0x7D {
            depth -= 1
            if depth == 0 && bodyStart >= 0 {
                out.append((jsTrim(text(preludeStart, bodyStart - 1)), text(bodyStart, i)))
                preludeStart = i + 1
                bodyStart = -1
            }
        } else if ch == 0x3B && depth == 0 {
            // A top-level at-statement such as `@import …;` — skipped.
            preludeStart = i + 1
        }
    }
    return out
}

private let KEYFRAMES_PREFIX = JSRegex("^@(-webkit-)?keyframes")

private func parseCssText(_ css: String, _ sheet: CSSStylesheet) -> [(query: String, sheet: CSSStylesheet)] {
    var media: [(query: String, sheet: CSSStylesheet)] = []
    for (prelude, body) in blocksOf(stripComments(css)) {
        if prelude.hasPrefix("@media") {
            let query = jsTrim(jsSubstring(prelude, 6))
            let inner = CSSStylesheet()
            _ = parseCssText(body, inner)
            media.append((query, inner))
        } else if prelude.hasPrefix("@keyframes") || prelude.hasPrefix("@-webkit-keyframes") {
            let name = jsTrim(KEYFRAMES_PREFIX.replace(prelude, with: "", global: false))
            var frames: [Keyframe] = []
            for (sel, decls) in blocksOf(body) {
                let styles = parseDeclarations(decls)
                for part in jsSplit(sel, ",") {
                    let t = jsTrim(part).lowercased()
                    let offset = t == "from" ? 0 : t == "to" ? 1 : jsParseFloat(t) / 100
                    if offset.isFinite { frames.append(Keyframe(offset: offset, styles: styles)) }
                }
            }
            // A stable sort, as Array.prototype.sort is.
            frames = frames.enumerated().sorted { a, b in
                a.element.offset != b.element.offset ? a.element.offset < b.element.offset : a.offset < b.offset
            }.map { $0.element }
            sheet.addKeyframeAnimation(name, frames)
        } else if prelude.hasPrefix("@supports") || prelude.hasPrefix("@layer") {
            media += parseCssText(body, sheet)
        } else if !prelude.hasPrefix("@") {
            sheet.addRule(prelude, parseDeclarations(body))
        }
    }
    return media
}

/** `JsonStylesheetParser.cssToJson`. */
public func cssToJson(_ cssText: String) -> StyleMap {
    let sheet = CSSStylesheet()
    let media = parseCssText(cssText, sheet)
    var rules: [Any?] = sheet.allRules.map { JSONObject([("selector", $0.selector), ("styles", $0.styles)]) }
    for m in media {
        for r in m.sheet.allRules {
            rules.append(JSONObject([("selector", r.selector), ("styles", r.styles), ("media", m.query)]))
        }
    }
    return JSONObject([("rules", rules)])
}

// ============================================================================
// Selectors
// ============================================================================

private let IDENT = JSRegex("^-?[_a-zA-Z0-9\\u00A0-\\uFFFF][_a-zA-Z0-9\\u00A0-\\uFFFF\\\\-]*")
private let PSEUDO = JSRegex("^::?([a-zA-Z-]+)(\\([^)]*\\))?")
private let ATTR_QUOTES = JSRegex("^[\"']|[\"']$")
private let LETTER = JSRegex("[a-zA-Z]")

func parseCompound(_ text: String) -> CompoundSelector? {
    var c = CompoundSelector()
    var i = 0
    let n = jsLength(text)
    func ident() -> String? {
        guard let m = IDENT.exec(jsSubstring(text, i)), let s = m[0] else { return nil }
        i += jsLength(s)
        return s
    }
    func charAt(_ k: Int) -> String { k < n ? jsSubstring(text, k, k + 1) : "" }
    if charAt(0) == "*" {
        c.universal = true
        i = 1
    } else if LETTER.test(charAt(0)) {
        c.tag = ident()
    }
    while i < n {
        let ch = charAt(i)
        if ch == "." {
            i += 1
            guard let name = ident() else { return nil }
            c.classes.append(name)
        } else if ch == "#" {
            i += 1
            guard let name = ident() else { return nil }
            c.id = name
        } else if ch == "[" {
            let end = jsIndexOf(text, "]", i)
            if end < 0 { return nil }
            let inner = jsSubstring(text, i + 1, end)
            let eq = jsIndexOf(inner, "=")
            if eq < 0 {
                c.attrs.append((jsTrim(inner), nil))
            } else {
                c.attrs.append((jsTrim(jsSubstring(inner, 0, eq)), ATTR_QUOTES.replace(jsTrim(jsSubstring(inner, eq + 1)), with: "")))
            }
            i = end + 1
        } else if ch == ":" {
            // Pseudo-classes: `:root` is honoured; interactive states (hover, focus…)
            // never match statically, which is what an un-hovered element shows.
            guard let m = PSEUDO.exec(jsSubstring(text, i)) else { return nil }
            i += jsLength(m[0] ?? "")
            if m[1] == "root" { c.root = true }
            else if !["first-child", "last-child"].contains(m[1] ?? "") { return nil }
        } else {
            return nil
        }
    }
    return c
}

private let CHILD_COMBINATOR = JSRegex("\\s*>\\s*")
private let SELECTOR_SPACE = JSRegex("\\s+")

func parseComplex(_ text: String) -> ComplexSelector? {
    var tokens: [String] = []
    var combinators: [Character] = []
    let normalized = jsTrim(SELECTOR_SPACE.replace(CHILD_COMBINATOR.replace(text, with: ">"), with: " "))
    var current = ""
    for ch in normalized {
        if ch == " " || ch == ">" {
            if !current.isEmpty { tokens.append(current) }
            current = ""
            combinators.append(ch)
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    if tokens.isEmpty || combinators.count != tokens.count - 1 { return nil }
    let compounds = tokens.map { parseCompound($0) }
    if compounds.contains(where: { $0 == nil }) { return nil }
    var parts: [(compound: CompoundSelector, combinator: Character?)] = []
    for k in stride(from: compounds.count - 1, through: 0, by: -1) {
        parts.append((compounds[k]!, k > 0 ? combinators[k - 1] : nil))
    }
    var ids = 0, classes = 0, tags = 0
    for c in compounds {
        if c!.id != nil { ids += 1 }
        classes += c!.classes.count + c!.attrs.count + (c!.root ? 1 : 0)
        if c!.tag != nil { tags += 1 }
    }
    return ComplexSelector(parts: parts, specificity: ids * 10000 + classes * 100 + tags)
}

func parseSelectorList(_ selector: String) -> [ComplexSelector] {
    splitTopLevel(selector, ",")
        .map { jsTrim($0) }
        .filter { !$0.isEmpty }
        .compactMap { parseComplex($0) }
}

func matchesCompound(_ c: CompoundSelector, _ el: ElementFacts) -> Bool {
    if c.root { return el.tagName == ":root" || el.tagName == "html" }
    if let tag = c.tag, tag != el.tagName && tag.lowercased() != el.tagName.lowercased() { return false }
    if let id = c.id, id != el.id { return false }
    if !c.classes.isEmpty {
        let own = el.classes ?? []
        for cls in c.classes where !own.contains(cls) { return false }
    }
    for attr in c.attrs {
        guard let attrs = el.attributes, attrs.has(attr.name) else { return false }
        if let value = attr.value, jsString(attrs[attr.name]) != value { return false }
    }
    return c.universal || c.tag != nil || c.id != nil || !c.classes.isEmpty || !c.attrs.isEmpty
}

func matchesComplex(_ sel: ComplexSelector, _ el: ElementFacts, _ ancestors: [ElementFacts]) -> Bool {
    guard let first = sel.parts.first else { return false }
    if !matchesCompound(first.compound, el) { return false }
    // ancestors are ordered nearest-first.
    var combinator = first.combinator
    var index = 0
    for part in sel.parts.dropFirst() {
        if combinator == ">" {
            if index >= ancestors.count || !matchesCompound(part.compound, ancestors[index]) { return false }
            index += 1
        } else {
            var found = false
            while index < ancestors.count {
                let candidate = ancestors[index]
                index += 1
                if matchesCompound(part.compound, candidate) {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        combinator = part.combinator
    }
    return true
}
