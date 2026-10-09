import Foundation

/**
 * 4x4 matrices in Flutter's column-major `Matrix4.storage` order
 * (css/matrix.ts): element (row r, column c) lives at index c * 4 + r.
 */
public enum Matrix {
    public static func identity() -> Matrix4 {
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    }

    public static func isIdentity(_ m: Matrix4?) -> Bool {
        guard let m = m else { return true }
        let id = identity()
        for i in 0..<16 where abs(m[i] - id[i]) > 1e-12 { return false }
        return true
    }

    /** a × b — applying b first, then a (Flutter `a.multiplied(b)`). */
    public static func multiply(_ a: Matrix4, _ b: Matrix4) -> Matrix4 {
        var out = [Double](repeating: 0, count: 16)
        for c in 0..<4 {
            for r in 0..<4 {
                var sum = 0.0
                for k in 0..<4 { sum += a[k * 4 + r] * b[c * 4 + k] }
                out[c * 4 + r] = sum
            }
        }
        return out
    }

    public static func translation(_ x: Double, _ y: Double, _ z: Double = 0) -> Matrix4 {
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]
    }

    public static func scaling(_ x: Double, _ y: Double, _ z: Double = 1) -> Matrix4 {
        [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1]
    }

    public static func rotationZ(_ radians: Double) -> Matrix4 {
        let c = cos(radians)
        let s = sin(radians)
        return [c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    }

    public static func rotationX(_ radians: Double) -> Matrix4 {
        let c = cos(radians)
        let s = sin(radians)
        return [1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1]
    }

    public static func rotationY(_ radians: Double) -> Matrix4 {
        let c = cos(radians)
        let s = sin(radians)
        return [c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1]
    }

    /** CSS `skew(ax, ay)` — shear by the tangents of the angles. */
    public static func skew(_ ax: Double, _ ay: Double) -> Matrix4 {
        [1, tan(ay), 0, 0, tan(ax), 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    }

    /** From CSS `matrix(a,b,c,d,e,f)` or `matrix3d(…16…)` (both column-major). */
    public static func fromCssMatrix(_ v: [Double]) -> Matrix4? {
        if v.count == 6 {
            let (a, b, c, d, e, f) = (v[0], v[1], v[2], v[3], v[4], v[5])
            return [a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]
        }
        if v.count == 16 { return v }
        return nil
    }

    /** Wrap [m] so it applies about the point (ox, oy) instead of the origin. */
    public static func aboutOrigin(_ m: Matrix4, _ ox: Double, _ oy: Double) -> Matrix4 {
        multiply(multiply(translation(ox, oy), m), translation(-ox, -oy))
    }

    /** Transform a 2D point (z = 0) with perspective divide. */
    public static func transformPoint(_ m: Matrix4, _ x: Double, _ y: Double) -> (Double, Double) {
        let tx = m[0] * x + m[4] * y + m[12]
        let ty = m[1] * x + m[5] * y + m[13]
        let tw = m[3] * x + m[7] * y + m[15]
        return tw != 0 && tw != 1 ? (tx / tw, ty / tw) : (tx, ty)
    }

    public static func invert(_ m: Matrix4) -> Matrix4? {
        var inv = [Double](repeating: 0, count: 16)
        inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
        inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
        inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
        inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
        inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
        inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
        inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
        inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
        inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
        inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
        inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
        inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
        inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
        inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
        inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
        inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]
        var det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12]
        if abs(det) < 1e-12 { return nil }
        det = 1 / det
        return inv.map { $0 * det }
    }

    /** Interpolate two matrices element-wise (adequate for the affine animations Elpian uses). */
    public static func lerp(_ a: Matrix4, _ b: Matrix4, _ t: Double) -> Matrix4 {
        (0..<a.count).map { a[$0] + (b[$0] - a[$0]) * t }
    }
}
