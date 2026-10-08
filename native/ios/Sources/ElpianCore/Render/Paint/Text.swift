import Foundation

/**
 * RenderText — a paragraph of styled spans (Flutter `Text` / `RichText` /
 * `SelectableText`), render/paint/text.ts. Layout asks the platform to
 * measure the paragraph with the incoming max width (the platform renders the
 * exact same spec, so the measured and painted text always agree).
 */
public struct SpanInput: Equatable, Hashable {
    public var text: String
    public var style: TextStyle?
    public var link: String?

    public init(text: String, style: TextStyle? = nil, link: String? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }

    /** A span given as a [SpanInput] or as a `{text, style, link}` object. */
    public static func from(_ v: Any?) -> SpanInput {
        let value = flattenOptional(v)
        if let s = value as? SpanInput { return s }
        if let m = asMap(value) {
            let text = m["text"]
            let link = m["link"]
            return SpanInput(
                text: text == nil ? "" : (text as? String ?? jsString(text)),
                style: m["style"] as? TextStyle,
                link: link == nil ? nil : (link as? String ?? jsString(link))
            )
        }
        if let s = value as? String { return SpanInput(text: s) }
        return SpanInput(text: "")
    }
}

/** The merged DefaultTextStyle chain. */
public struct InheritedTextStyle: Equatable {
    public var style: TextStyle
    public var align: String?
    public var maxLines: Int?
    public var overflow: String?
    public var softWrap: Bool?

    public init(style: TextStyle, align: String? = nil, maxLines: Int? = nil, overflow: String? = nil, softWrap: Bool? = nil) {
        self.style = style
        self.align = align
        self.maxLines = maxLines
        self.overflow = overflow
        self.softWrap = softWrap
    }
}

private func intOrNil(_ v: Any?) -> Int? {
    guard let d = jsNumber(v), d.isFinite else { return nil }
    return Int(max(Double(Int32.min), min(Double(Int32.max), d.rounded(.towardZero))))
}

/**
 * props: {
 *   text?: string, spans?: [SpanInput], style?: TextStyle,
 *   align?, maxLines?, overflow?, softWrap?, selectable?, direction?,
 *   onLink?: (String) -> Void
 * }
 */
open class RenderText: RenderObject {
    private var metrics: TextMetrics?
    private var spec: TextSpec?

    /** The nearest DefaultTextStyle chain merged outermost-first. */
    public func inheritedStyle() -> InheritedTextStyle {
        var chain: [RenderDefaultTextStyle] = []
        var node = parent
        while let n = node {
            if let d = n as? RenderDefaultTextStyle { chain.append(d) }
            node = n.parent
        }
        var style = TextStyle()
        var align: String?
        var maxLines: Int?
        var overflow: String?
        var softWrap: Bool?
        for i in chain.indices.reversed() {
            let p = chain[i].props
            style = mergeTextStyle(style, p["style"] as? TextStyle)
            if let a = p.s("textAlign"), !a.isEmpty { align = a }
            if p.has("maxLines") { maxLines = intOrNil(p["maxLines"]) }
            if let o = p.s("overflow"), !o.isEmpty { overflow = o }
            if p.has("softWrap") { softWrap = jsBool(p["softWrap"]) }
        }
        return InheritedTextStyle(style: style, align: align, maxLines: maxLines, overflow: overflow, softWrap: softWrap)
    }

    public func buildSpec() -> TextSpec {
        let inherited = inheritedStyle()
        let base = mergeTextStyle(inherited.style, props["style"] as? TextStyle)
        let scale = owner?.textScale ?? 1
        let inputs: [SpanInput]
        if let list = asArray(props["spans"]) {
            inputs = list.map { SpanInput.from($0) }
        } else if let typed = props["spans"] as? [SpanInput] {
            inputs = typed
        } else {
            let text = props["text"]
            inputs = [SpanInput(text: text == nil ? "" : (text as? String ?? jsString(text)))]
        }
        let spans = inputs.map { s -> TextSpanSpec in
            let style = mergeTextStyle(base, s.style)
            return TextSpanSpec(
                text: applyTextTransform(s.text, style.textTransform),
                style: style.toSpec(scale),
                link: s.link.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        let softWrap = jsBool(props["softWrap"]) ?? inherited.softWrap ?? true
        return TextSpec(
            spans: spans,
            align: props.s("align") ?? inherited.align ?? "start",
            maxLines: intOrNil(props["maxLines"]) ?? inherited.maxLines,
            overflow: props.s("overflow") ?? inherited.overflow ?? "clip",
            softWrap: softWrap,
            selectable: jsTruthy(props["selectable"]),
            direction: props.s("direction") == "rtl" ? "rtl" : "ltr"
        )
    }

    private func measure(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        guard let owner = owner else {
            let size = spec.spans.reduce(0.0) { s, sp in s + Double(jsLength(sp.text)) * sp.style.fontSize * 0.5 }
            return TextMetrics(width: min(size, maxWidth), height: 20, baseline: 15, lineCount: 1, didExceedMaxLines: false)
        }
        return owner.measureText(spec, maxWidth)
    }

    open override func performLayout(_ c: Constraints) {
        let spec = buildSpec()
        self.spec = spec
        let maxWidth = spec.softWrap || spec.overflow == "ellipsis" || spec.overflow == "fade" ? c.maxWidth : INF
        let metrics = measure(spec, maxWidth)
        self.metrics = metrics
        // Fractional widths are rounded up so the platform never wraps a line
        // the measurement placed on one line.
        size = constrain(c, Size(width: (metrics.width - 0.001).rounded(.up), height: (metrics.height - 0.001).rounded(.up)))
    }

    open override func baseline() -> Double? { metrics?.baseline }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let spec = buildSpec()
        if !spec.softWrap { return measure(spec, INF).width.rounded(.up) }
        return measure(spec, 0).width.rounded(.up)
    }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double { measure(buildSpec(), INF).width.rounded(.up) }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double { measure(buildSpec(), width).height.rounded(.up) }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double { computeMinIntrinsicHeight(width) }

    open override func viewKind() -> ViewKind? { .text }

    open override func viewProps() -> ViewProps {
        let spec = self.spec ?? buildSpec()
        let hasLinks = spec.spans.contains { !($0.link ?? "").isEmpty }
        return ViewProps([("text", spec), ("gestures", hasLinks ? ["tap"] as [Any?] : nil)])
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        if event.type == "link", let v = flattenOptional(event.value) as? String { callHandler(props["onLink"], v) }
    }

    public var lastMetrics: TextMetrics? { metrics }
}
