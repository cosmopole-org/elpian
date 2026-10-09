import Foundation

/**
 * Image maps (`<img usemap="#m">` + `<map name="m"><area …></map>`,
 * render/layout/imagemap.ts): the image is the first child; every following
 * child is a tappable area whose coordinates are in the image's natural
 * pixels and are scaled to the rendered size.
 */
public struct AreaSpec: Equatable, Hashable, JSONSerializable {
    /** rect, circle, poly or default. */
    public var shape: String
    public var coords: [Double]

    public init(shape: String, coords: [Double]) {
        self.shape = shape
        self.coords = coords
    }

    /** From its JSON form `{shape, coords}`. */
    public init?(json: Any?) {
        if let a = flattenOptional(json) as? AreaSpec {
            self = a
            return
        }
        guard let m = asMap(json), let shape = m["shape"] as? String else { return nil }
        self.shape = shape
        self.coords = (asArray(m["coords"]) ?? []).map { jsNumber($0) ?? .nan }
    }

    public func toJSON() -> Any? { JSONObject([("shape", shape), ("coords", coords.map { $0 as Any? })]) }
}

/** Bounds of a rectangle in natural image pixels. */
public struct AreaRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}

/** JavaScript array indexing: a missing coordinate reads as NaN (`undefined` in arithmetic). */
private func at(_ c: [Double], _ i: Int) -> Double { i >= 0 && i < c.count ? c[i] : .nan }

/** JavaScript `Math.min` / `Math.max` of two numbers (NaN-propagating). */
private func jsMin2(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : Swift.min(a, b) }
private func jsMax2(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : Swift.max(a, b) }

/** JavaScript `Math.min(...xs)` / `Math.max(...xs)`: NaN-propagating, ±Infinity when empty. */
private func jsMinAll(_ xs: [Double]) -> Double {
    var m = Double.infinity
    for x in xs {
        if x.isNaN { return .nan }
        if x < m { m = x }
    }
    return m
}

private func jsMaxAll(_ xs: [Double]) -> Double {
    var m = -Double.infinity
    for x in xs {
        if x.isNaN { return .nan }
        if x > m { m = x }
    }
    return m
}

public func areaBounds(_ area: AreaSpec, _ w: Double, _ h: Double) -> AreaRect {
    let c = area.coords
    switch area.shape {
    case "rect":
        return AreaRect(x: jsMin2(at(c, 0), at(c, 2)), y: jsMin2(at(c, 1), at(c, 3)), width: abs(at(c, 2) - at(c, 0)), height: abs(at(c, 3) - at(c, 1)))
    case "circle":
        return AreaRect(x: at(c, 0) - at(c, 2), y: at(c, 1) - at(c, 2), width: at(c, 2) * 2, height: at(c, 2) * 2)
    case "poly":
        let xs = c.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
        let ys = c.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
        let x = jsMinAll(xs)
        let y = jsMinAll(ys)
        return AreaRect(x: x, y: y, width: jsMaxAll(xs) - x, height: jsMaxAll(ys) - y)
    default:
        return AreaRect(x: 0, y: 0, width: w, height: h)
    }
}

/** Whether a point in natural image pixels lies inside [area]. */
public func areaContains(_ area: AreaSpec, _ px: Double, _ py: Double) -> Bool {
    let c = area.coords
    switch area.shape {
    case "rect":
        return px >= jsMin2(at(c, 0), at(c, 2)) && px <= jsMax2(at(c, 0), at(c, 2)) && py >= jsMin2(at(c, 1), at(c, 3)) && py <= jsMax2(at(c, 1), at(c, 3))
    case "circle":
        return (px - at(c, 0)) * (px - at(c, 0)) + (py - at(c, 1)) * (py - at(c, 1)) <= at(c, 2) * at(c, 2)
    case "poly":
        var inside = false
        let n = c.count / 2
        var j = n - 1
        for i in 0..<n {
            let xi = at(c, 2 * i)
            let yi = at(c, 2 * i + 1)
            let xj = at(c, 2 * j)
            let yj = at(c, 2 * j + 1)
            if (yi > py) != (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi { inside = !inside }
            j = i
        }
        return inside
    default:
        return true
    }
}

/** props: { src, areas: [AreaSpec] } */
open class RenderImageMap: RenderObject {
    public var scale = Vec(x: 1, y: 1)

    open override func performLayout(_ c: Constraints) {
        guard let image = children.first else {
            size = constrain(c, .zero)
            return
        }
        let areas = children.dropFirst()
        image.layout(c)
        image.offset = .zero
        size = image.size
        let natural = props.s("src").flatMap { owner?.imageSize($0) }
        if let n = natural, n.width > 0, n.height > 0 {
            scale = Vec(x: size.width / n.width, y: size.height / n.height)
        } else {
            scale = Vec(x: 1, y: 1)
        }
        let specs = asArray(props["areas"]) ?? []
        for (i, area) in areas.enumerated() {
            guard i < specs.count, let spec = AreaSpec(json: specs[i]) else {
                area.layout(Constraints(minWidth: 0, maxWidth: 0, minHeight: 0, maxHeight: 0))
                continue
            }
            let b = areaBounds(spec, natural?.width ?? size.width, natural?.height ?? size.height)
            let w = b.width * scale.x
            let h = b.height * scale.y
            area.layout(Constraints(minWidth: w, maxWidth: w, minHeight: h, maxHeight: h))
            area.offset = Vec(x: b.x * scale.x, y: b.y * scale.y)
        }
    }
}
