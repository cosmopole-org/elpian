import Foundation

/**
 * Easing curves — an exact port of Flutter's `Curves` (cubic bisection with
 * the same 0.001 error bound, Robert Penner's bounce, Flutter's elastic
 * curves) plus CSS `cubic-bezier()` and `steps()` (animation/curves.ts).
 */
public typealias Curve = (Double) -> Double

private let CUBIC_ERROR_BOUND = 0.001

private func evaluateCubic(_ a: Double, _ b: Double, _ m: Double) -> Double {
    3 * a * (1 - m) * (1 - m) * m + 3 * b * (1 - m) * m * m + m * m * m
}

public func cubic(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Curve {
    return { t in
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        var start = 0.0
        var end = 1.0
        for _ in 0..<64 {
            let mid = (start + end) / 2
            let estimate = evaluateCubic(a, c, mid)
            if abs(t - estimate) < CUBIC_ERROR_BOUND { return evaluateCubic(b, d, mid) }
            if estimate < t { start = mid } else { end = mid }
        }
        return evaluateCubic(b, d, (start + end) / 2)
    }
}

private func bounce(_ t0: Double) -> Double {
    var t = t0
    if t < 1 / 2.75 { return 7.5625 * t * t }
    if t < 2 / 2.75 {
        t -= 1.5 / 2.75
        return 7.5625 * t * t + 0.75
    }
    if t < 2.5 / 2.75 {
        t -= 2.25 / 2.75
        return 7.5625 * t * t + 0.9375
    }
    t -= 2.625 / 2.75
    return 7.5625 * t * t + 0.984375
}

public func elasticIn(_ period: Double = 0.4) -> Curve {
    return { t0 in
        if t0 <= 0 || t0 >= 1 { return t0 <= 0 ? 0 : 1 }
        let s = period / 4
        let t = t0 - 1
        return -pow(2, 10 * t) * sin((t - s) * (Double.pi * 2) / period)
    }
}

public func elasticOut(_ period: Double = 0.4) -> Curve {
    return { t in
        if t <= 0 || t >= 1 { return t <= 0 ? 0 : 1 }
        let s = period / 4
        return pow(2, -10 * t) * sin((t - s) * (Double.pi * 2) / period) + 1
    }
}

public func elasticInOut(_ period: Double = 0.4) -> Curve {
    return { t0 in
        if t0 <= 0 || t0 >= 1 { return t0 <= 0 ? 0 : 1 }
        let s = period / 4
        let t = 2 * t0 - 1
        if t < 0 { return -0.5 * pow(2, 10 * t) * sin((t - s) * (Double.pi * 2) / period) }
        return pow(2, -10 * t) * sin((t - s) * (Double.pi * 2) / period) * 0.5 + 1
    }
}

public func interval(_ begin: Double, _ end: Double, _ curve: @escaping Curve = Curves.linear) -> Curve {
    return { t in
        if end <= begin { return t >= end ? 1 : 0 }
        let local = max(0, min(1, (t - begin) / (end - begin)))
        if local == 0 || local == 1 { return local }
        return curve(local)
    }
}

/** CSS `steps()` jump positions. */
public enum StepPosition: String {
    case start, end, both, none
}

public func steps(_ count: Int, _ position: StepPosition = .end) -> Curve {
    let n = Double(max(1, count))
    return { t in
        if t >= 1 { return 1 }
        var step = (t * n).rounded(.down)
        if position == .start || position == .both { step += 1 }
        let jumps = position == .both ? n + 1 : position == .none ? n - 1 : n
        return max(0, min(1, step / max(1, jumps)))
    }
}

public enum Curves {
    public static let linear: Curve = { $0 }
    public static let decelerate: Curve = { t0 in
        let t = 1 - t0
        return 1 - t * t
    }
    public static let fastLinearToSlowEaseIn = cubic(0.18, 1.0, 0.04, 1.0)
    public static let ease = cubic(0.25, 0.1, 0.25, 1.0)
    public static let easeIn = cubic(0.42, 0.0, 1.0, 1.0)
    public static let easeInToLinear = cubic(0.67, 0.03, 0.65, 0.09)
    public static let easeInSine = cubic(0.47, 0.0, 0.745, 0.715)
    public static let easeInQuad = cubic(0.55, 0.085, 0.68, 0.53)
    public static let easeInCubic = cubic(0.55, 0.055, 0.675, 0.19)
    public static let easeInQuart = cubic(0.895, 0.03, 0.685, 0.22)
    public static let easeInQuint = cubic(0.755, 0.05, 0.855, 0.06)
    public static let easeInExpo = cubic(0.95, 0.05, 0.795, 0.035)
    public static let easeInCirc = cubic(0.6, 0.04, 0.98, 0.335)
    public static let easeInBack = cubic(0.6, -0.28, 0.735, 0.045)
    public static let easeOut = cubic(0.0, 0.0, 0.58, 1.0)
    public static let linearToEaseOut = cubic(0.35, 0.91, 0.33, 0.97)
    public static let easeOutSine = cubic(0.39, 0.575, 0.565, 1.0)
    public static let easeOutQuad = cubic(0.25, 0.46, 0.45, 0.94)
    public static let easeOutCubic = cubic(0.215, 0.61, 0.355, 1.0)
    public static let easeOutQuart = cubic(0.165, 0.84, 0.44, 1.0)
    public static let easeOutQuint = cubic(0.23, 1.0, 0.32, 1.0)
    public static let easeOutExpo = cubic(0.19, 1.0, 0.22, 1.0)
    public static let easeOutCirc = cubic(0.075, 0.82, 0.165, 1.0)
    public static let easeOutBack = cubic(0.175, 0.885, 0.32, 1.275)
    public static let easeInOut = cubic(0.42, 0.0, 0.58, 1.0)
    public static let easeInOutSine = cubic(0.445, 0.05, 0.55, 0.95)
    public static let easeInOutQuad = cubic(0.455, 0.03, 0.515, 0.955)
    public static let easeInOutCubic = cubic(0.645, 0.045, 0.355, 1.0)
    public static let easeInOutQuart = cubic(0.77, 0.0, 0.175, 1.0)
    public static let easeInOutQuint = cubic(0.86, 0.0, 0.07, 1.0)
    public static let easeInOutExpo = cubic(1.0, 0.0, 0.0, 1.0)
    public static let easeInOutCirc = cubic(0.785, 0.135, 0.15, 0.86)
    public static let easeInOutBack = cubic(0.68, -0.55, 0.265, 1.55)
    public static let fastOutSlowIn = cubic(0.4, 0.0, 0.2, 1.0)
    public static let slowMiddle = cubic(0.15, 0.85, 0.85, 0.15)
    public static let bounceIn: Curve = { 1 - bounce(1 - $0) }
    public static let bounceOut: Curve = { bounce($0) }
    public static let bounceInOut: Curve = { t in t < 0.5 ? (1 - bounce(1 - t * 2)) * 0.5 : bounce(t * 2 - 1) * 0.5 + 0.5 }
    public static let elasticIn: Curve = ElpianCore.elasticIn(0.4)
    public static let elasticOut: Curve = ElpianCore.elasticOut(0.4)
    public static let elasticInOut: Curve = ElpianCore.elasticInOut(0.4)
}

/** Normalised name (lowercase, no separators) → curve; mirrors `CSSParser._curveMap`. */
private let byName: [String: Curve] = [
    "linear": Curves.linear,
    "ease": Curves.ease,
    "easein": Curves.easeIn,
    "easeout": Curves.easeOut,
    "easeinout": Curves.easeInOut,
    "bounce": Curves.bounceIn,
    "bouncein": Curves.bounceIn,
    "bounceout": Curves.bounceOut,
    "bounceinout": Curves.bounceInOut,
    "elastic": Curves.elasticIn,
    "elasticin": Curves.elasticIn,
    "elasticout": Curves.elasticOut,
    "elasticinout": Curves.elasticInOut,
    "decelerate": Curves.decelerate,
    "fastoutslowin": Curves.fastOutSlowIn,
    "slowmiddle": Curves.slowMiddle,
    "fastlineartosloweasein": Curves.fastLinearToSlowEaseIn,
    "easeintolinear": Curves.easeInToLinear,
    "lineartoeaseout": Curves.linearToEaseOut,
    "easeinsine": Curves.easeInSine,
    "easeinquad": Curves.easeInQuad,
    "easeincubic": Curves.easeInCubic,
    "easeinquart": Curves.easeInQuart,
    "easeinquint": Curves.easeInQuint,
    "easeinexpo": Curves.easeInExpo,
    "easeincirc": Curves.easeInCirc,
    "easeinback": Curves.easeInBack,
    "easeoutsine": Curves.easeOutSine,
    "easeoutquad": Curves.easeOutQuad,
    "easeoutcubic": Curves.easeOutCubic,
    "easeoutquart": Curves.easeOutQuart,
    "easeoutquint": Curves.easeOutQuint,
    "easeoutexpo": Curves.easeOutExpo,
    "easeoutcirc": Curves.easeOutCirc,
    "easeoutback": Curves.easeOutBack,
    "easeinoutsine": Curves.easeInOutSine,
    "easeinoutquad": Curves.easeInOutQuad,
    "easeinoutcubic": Curves.easeInOutCubic,
    "easeinoutquart": Curves.easeInOutQuart,
    "easeinoutquint": Curves.easeInOutQuint,
    "easeinoutexpo": Curves.easeInOutExpo,
    "easeinoutcirc": Curves.easeInOutCirc,
    "easeinoutback": Curves.easeInOutBack,
    "stepstart": steps(1, .start),
    "stepend": steps(1, .end),
]

private let BEZIER = JSRegex("^cubic-bezier\\(\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*\\)$")
private let STEPS = JSRegex("^steps\\(\\s*(\\d+)\\s*(?:,\\s*([a-z-]+))?\\s*\\)$")
private let CURVE_SEPARATORS = JSRegex("[-_\\s]")

/** Resolve a curve name (`ease-in-out`, `easeInOut`, `cubic-bezier(…)`, `steps(4, end)`). */
public func curveByName(_ name: String?, _ fallback: @escaping Curve = Curves.linear) -> Curve {
    guard let name = name, !name.isEmpty else { return fallback }
    let raw = jsTrim(name).lowercased()
    if let bez = BEZIER.exec(raw) {
        return cubic(jsParseFloat(bez[1] ?? ""), jsParseFloat(bez[2] ?? ""), jsParseFloat(bez[3] ?? ""), jsParseFloat(bez[4] ?? ""))
    }
    if let st = STEPS.exec(raw) {
        let pos = st[2] ?? "end"
        let position: StepPosition = pos == "start" || pos == "jump-start" ? .start : pos == "jump-both" ? .both : pos == "jump-none" ? .none : .end
        return steps(Int(jsParseInt(st[1] ?? "1", 10)), position)
    }
    return byName[CURVE_SEPARATORS.replace(raw, with: "")] ?? fallback
}
