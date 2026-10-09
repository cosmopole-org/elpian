import Foundation

/**
 * Leaf render objects backed by native elements (render/paint/leaves.ts):
 * images, native controls, canvases, Godot surfaces, media players and
 * embedded web content, plus the transparent gesture region every
 * event-bearing element is wrapped in.
 */

private let UNBOUNDED = Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF)

/** A `[top, right, bottom, left]` padding given as an array or [EdgeInsets]. */
private func padding4(_ v: Any?, _ fallback: [Double]) -> [Double] {
    let value = flattenOptional(v)
    if let e = value as? EdgeInsets { return [e.top, e.right, e.bottom, e.left] }
    if let a = value as? [Double], a.count >= 4 { return a }
    if let a = asArray(value) { return (0..<4).map { i in i < a.count ? jsNumber(a[i]) ?? 0 : 0 } }
    return fallback
}

/** `fontSize` / `height` of a control's `textStyle` (a [TextStyleSpec] or its JSON form). */
private func textStyleMetrics(_ v: Any?) -> (fontSize: Double?, height: Double?)? {
    let value = flattenOptional(v)
    if let ts = value as? TextStyleSpec { return (ts.fontSize, ts.height) }
    if let m = asMap(value) { return (jsNumber(m["fontSize"]), jsNumber(m["height"])) }
    return nil
}

// ----------------------------------------------------------------------------
// Image
// ----------------------------------------------------------------------------

/** props: { src, fit, alignment, width, height, alt, repeat, tint, semanticsLabel, onEvent } */
open class RenderImage: RenderObject {
    public func naturalSize() -> Size? {
        guard let src = props.s("src"), !src.isEmpty, let owner = owner else { return nil }
        return owner.imageSize(src)
    }

    open override func performLayout(_ c: Constraints) {
        let inner = enforce(tightFor(UNBOUNDED, props.d("width"), props.d("height")), c)
        guard let natural = naturalSize() else {
            size = smallest(inner)
            return
        }
        size = preserveAspect(inner, natural)
    }

    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        if let w = props.d("width") { return w }
        guard let n = naturalSize() else { return 0 }
        return height.isFinite && n.height > 0 ? height * n.width / n.height : n.width
    }
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double { computeMaxIntrinsicWidth(height) }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        if let h = props.d("height") { return h }
        guard let n = naturalSize() else { return 0 }
        return width.isFinite && n.width > 0 ? width * n.height / n.width : n.height
    }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double { computeMaxIntrinsicHeight(width) }

    open override func viewKind() -> ViewKind? { .image }
    open override func viewProps() -> ViewProps {
        let rep = props.s("repeat")
        let fit = props["fit"]
        return ViewProps([
            ("src", props["src"]),
            ("fit", fit ?? "contain"),
            ("alignment", props["alignment"]),
            ("alt", props["alt"]),
            ("tint", props["tint"]),
            ("semanticsLabel", props["semanticsLabel"] ?? props["alt"]),
            ("backgroundImage", rep != nil && !rep!.isEmpty && rep != "no-repeat" ? DecorationImage(src: props.s("src") ?? "", fit: nil, alignment: nil, repeat: rep) : nil),
        ])
    }
    open override func handleViewEvent(_ event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Native controls
// ----------------------------------------------------------------------------

/**
 * props: {
 *   kind: 'checkbox'|'radio'|'switch'|'slider'|'progress'|'textInput'|'select',
 *   view: JSONObject (partial view props: value, checked, options, colors, textStyle …),
 *   width?, height?, lines?, lineHeight?, padding?: [t,r,b,l], onEvent, controlled
 * }
 */
open class RenderControl: RenderObject {
    private func kind() -> ViewKind? {
        if let k = props["kind"] as? ViewKind { return k }
        return props.s("kind").flatMap { ViewKind(rawValue: $0) }
    }

    private func view() -> JSONObject { asMap(props["view"]) ?? JSONObject() }

    private func defaultSize(_ c: Constraints) -> Size {
        let view = self.view()
        func fillW(_ fallback: Double) -> Double { c.maxWidth.isFinite ? c.maxWidth : fallback }
        switch kind() {
        case .checkbox?, .radio?:
            return Size(width: 48, height: 48)
        case .switch?:
            return Size(width: 60, height: 48)
        case .slider?:
            return Size(width: fillW(200), height: 48)
        case .progress?:
            return view.s("variant") == "circular"
                ? Size(width: 36, height: 36)
                : Size(width: fillW(200), height: view.d("strokeWidth") ?? 4)
        case .textInput?:
            let ts = textStyleMetrics(view["textStyle"])
            let fontSize = ts?.fontSize ?? 16
            let lineH = props.d("lineHeight") ?? fontSize * (ts?.height ?? 1.5)
            let lines = max(1, props.d("lines") ?? 1)
            let pad = padding4(props["padding"], [12, 0, 12, 0])
            return Size(width: fillW(280), height: (lines * lineH + pad[0] + pad[2]).rounded(.up))
        case .select?:
            let ts = textStyleMetrics(view["textStyle"])
            let fontSize = ts?.fontSize ?? 14
            let lineH = max(24, fontSize * (ts?.height ?? 1.3))
            let pad = padding4(props["padding"], [0, 0, 0, 0])
            return Size(width: fillW(200), height: (lineH + pad[0] + pad[2]).rounded(.up))
        default:
            return Size(width: 48, height: 48)
        }
    }

    open override func performLayout(_ c: Constraints) {
        var size = defaultSize(c)
        if let owner = owner, let k = kind(), let measured = owner.platform.measureControl(ControlMeasureSpec(kind: k, props: view()), c.maxWidth) {
            size = measured
        }
        if let w = props.d("width") { size.width = w }
        if let h = props.d("height") { size.height = h }
        self.size = constrain(c, size)
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double { props.d("width") ?? defaultSize(UNBOUNDED).width }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double { computeMinIntrinsicWidth(height) }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double { props.d("height") ?? defaultSize(UNBOUNDED).height }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double { computeMinIntrinsicHeight(width) }

    open override func baseline() -> Double? {
        let k = kind()
        if k == .textInput || k == .select {
            let ts = textStyleMetrics(view()["textStyle"])
            let pad = padding4(props["padding"], [12, 0, 12, 0])
            return pad[0] + (ts?.fontSize ?? 16) * 0.95
        }
        return nil
    }

    open override func viewKind() -> ViewKind? { kind() }
    open override func viewProps() -> ViewProps { view().copy() }

    open override func handleViewEvent(_ event: ViewEvent) {
        callHandler(props["onEvent"], event)
        // Controlled controls (Flutter Checkbox/Switch/Slider/Radio) show the
        // guest's value, not the user's gesture, until the guest re-renders: make
        // the next frame re-assert the configured value on the native control.
        if jsTruthy(props["controlled"]), let id = viewId, let owner = owner {
            owner.compositor.invalidateProps(id, ["checked", "value"])
        }
    }
}

// ----------------------------------------------------------------------------
// Canvas
// ----------------------------------------------------------------------------

/**
 * props: {
 *   width?, height?, background?: Color,
 *   commands?: [Any?]          — inline command list (Canvas / canvas)
 *   commandsKey?: string       — identity of the inline list (defaults to its JSON)
 *   context?: CanvasContext    — cached context
 * }
 */
open class RenderCanvas: RenderObject {
    private var sentGeneration = -1
    private var sentCount = 0
    private var sentInlineKey: String?

    open override func performLayout(_ c: Constraints) {
        let w = props.d("width")
        let h = props.d("height")
        let b = biggest(c)
        size = constrain(c, Size(width: w ?? (c.maxWidth.isFinite ? b.width : 0), height: h ?? (c.maxHeight.isFinite ? b.height : 0)))
    }

    open override func viewKind() -> ViewKind? { .canvas }

    open override func viewProps() -> ViewProps {
        let out = ViewProps([("background", props["background"])])
        if let ctx = props["context"] as? CanvasContext {
            if ctx.generation != sentGeneration {
                out["commands"] = ctx.commands.map { $0 as Any? }
                sentGeneration = ctx.generation
                sentCount = ctx.commands.count
            } else if ctx.commands.count > sentCount {
                out["appendCommands"] = ctx.commands[sentCount...].map { $0 as Any? }
                sentCount = ctx.commands.count
            }
            out["canvasVersion"] = Double(ctx.version)
            return out
        }
        let commands = asArray(props["commands"]) ?? []
        let rawKey = props["commandsKey"]
        let key = rawKey != nil ? (rawKey as? String ?? jsString(rawKey)) : JSON.stringify(commands)
        if key != sentInlineKey {
            out["commands"] = commands
            sentInlineKey = key
        }
        return out
    }

    /** Force the next frame to resend the full command list (e.g. after re-mount). */
    public func resetSent() {
        sentGeneration = -1
        sentCount = 0
        sentInlineKey = nil
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Scene3D (embedded Godot)
// ----------------------------------------------------------------------------

/** props: { surfaceId, width, height, clickable, live, placeholder?, onEvent } */
open class RenderScene3D: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let w = props.d("width")
        let h = props.d("height")
        let width = w ?? (c.maxWidth.isFinite ? c.maxWidth : 300)
        let height = h ?? (c.maxHeight.isFinite ? c.maxHeight : width * 9 / 16)
        size = constrain(c, Size(width: width, height: height))
        for ch in children {
            ch.layout(tight(size.width, size.height))
            ch.offset = .zero
        }
    }

    open override func viewKind() -> ViewKind? { .scene3d }

    /** The placeholder child paints only when no engine is live. */
    open override func paintsChild(_ child: RenderObject) -> Bool { !jsTruthy(props["live"]) }

    open override func viewProps() -> ViewProps {
        let clickable = jsTruthy(props["clickable"])
        return ViewProps([
            ("surfaceId", props["surfaceId"]),
            ("clickable", clickable),
            ("gestures", clickable ? ["tap"] as [Any?] : nil),
            ("clip", true),
        ])
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Media (video / audio)
// ----------------------------------------------------------------------------

/** props: { kind: 'video'|'audio', src, autoplay, loop, muted, controls, poster, tracks, fit, width, height, onEvent } */
open class RenderMedia: RenderObject {
    private var aspect: Double?

    open override func performLayout(_ c: Constraints) {
        let kind = props.s("kind") == "audio" ? "audio" : "video"
        let w = props.d("width")
        let h = props.d("height")
        if kind == "audio" {
            size = constrain(c, Size(width: w ?? (c.maxWidth.isFinite ? c.maxWidth : 300), height: h ?? 54))
            return
        }
        let aspect = self.aspect ?? (16.0 / 9)
        let width = w ?? (c.maxWidth.isFinite ? c.maxWidth : 300)
        let height = h ?? (width / aspect)
        size = constrain(c, Size(width: width, height: height))
    }

    open override func viewKind() -> ViewKind? { props.s("kind") == "audio" ? .audio : .video }

    open override func viewProps() -> ViewProps {
        ViewProps([
            ("src", props["src"]),
            ("autoplay", jsTruthy(props["autoplay"])),
            ("loop", jsTruthy(props["loop"])),
            ("muted", jsTruthy(props["muted"])),
            ("controls", !props.isFalse("controls")),
            ("poster", props["poster"]),
            ("tracks", props["tracks"]),
            ("fit", props["fit"] ?? "contain"),
        ])
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        if event.type == "load", let value = asMap(event.value) {
            let vw = jsToNumber(value["width"])
            let vh = jsToNumber(value["height"])
            if vw > 0 && vh > 0 {
                let next = vw / vh
                if aspect == nil || abs(aspect! - next) > 0.001 {
                    aspect = next
                    markNeedsLayout()
                }
            }
        }
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Web content (iframe / embed / object)
// ----------------------------------------------------------------------------

/** props: { src, html, width, height, javascript, onEvent } */
open class RenderWeb: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let w = props.d("width")
        let h = props.d("height")
        size = constrain(c, Size(width: w ?? (c.maxWidth.isFinite ? c.maxWidth : 300), height: h ?? (c.maxHeight.isFinite ? c.maxHeight : 150)))
    }

    open override func viewKind() -> ViewKind? { .web }

    open override func viewProps() -> ViewProps {
        ViewProps([
            ("src", props["src"]),
            ("html", props["html"]),
            ("javascript", !props.isFalse("javascript")),
            ("clip", true),
        ])
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

/**
 * A host-registered native component (an island). props { component,
 * componentProps, width?, height?, onEvent }. Fills bounded constraints, else
 * the platform's measured size, else its explicit size; Elpian children are
 * laid over it (server-rendered content the native component wraps).
 */
open class RenderNative: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let measured = owner?.platform.measureControl(
            ControlMeasureSpec(kind: .native, props: JSONObject([("component", props["component"]), ("componentProps", props["componentProps"] ?? JSONObject())])),
            c.maxWidth
        )
        let w = props.d("width") ?? measured?.width ?? (c.maxWidth.isFinite ? c.maxWidth : 0)
        let h = props.d("height") ?? measured?.height ?? (c.maxHeight.isFinite ? c.maxHeight : 0)
        size = constrain(c, Size(width: w, height: h))
        for ch in children {
            ch.layout(Constraints(minWidth: 0, maxWidth: size.width, minHeight: 0, maxHeight: size.height))
            ch.offset = .zero
        }
    }

    open override func viewKind() -> ViewKind? { .native }

    open override func viewProps() -> ViewProps {
        ViewProps([
            ("component", props["component"]),
            ("componentProps", props["componentProps"] ?? JSONObject()),
        ])
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Gesture region
// ----------------------------------------------------------------------------

/**
 * props: {
 *   gestures: [String], ripple?, cursor?, tooltip?, focusable?, semanticsLabel?,
 *   role?, dragData?, dismissDirection?, onEvent(ViewEvent, RenderGesture)
 * }
 * Sizes to its child (HitTestBehavior.opaque) and owns a transparent view.
 */
open class RenderGesture: RenderProxy {
    /** A Dismissible that was swiped away collapses to nothing. */
    public var dismissed = false
    public var collapse = 1.0

    open override func performLayout(_ c: Constraints) {
        super.performLayout(c)
        if dismissed {
            size = Size(width: size.width, height: size.height * collapse)
        }
    }

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        let gestures = asArray(props["gestures"]) ?? []
        return ViewProps([
            ("gestures", !gestures.isEmpty ? gestures : nil),
            ("ripple", props["ripple"]),
            ("cursor", props["cursor"]),
            ("tooltip", props["tooltip"]),
            ("focusable", jsTruthy(props["focusable"]) ? true : nil),
            ("semanticsLabel", props["semanticsLabel"]),
            ("role", props["role"]),
            ("dragData", props["dragData"]),
            ("dismissDirection", props["dismissDirection"]),
            ("hidden", dismissed && collapse <= 0 ? true : nil),
            ("clip", dismissed ? true : nil),
        ])
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        callHandler(props["onEvent"], event, self)
    }
}
