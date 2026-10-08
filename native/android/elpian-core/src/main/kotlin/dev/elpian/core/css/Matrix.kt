package dev.elpian.core.css

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.tan

/** 4x4 matrices in Flutter's column-major order: (row r, column c) is at c * 4 + r. */
object Matrix {
    fun identity(): Matrix4 = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)

    fun isIdentity(m: Matrix4?): Boolean {
        if (m == null) return true
        val id = identity()
        for (i in 0 until 16) if (abs(m[i] - id[i]) > 1e-12) return false
        return true
    }

    /** a × b — applying b first, then a (Flutter `a.multiplied(b)`). */
    fun multiply(a: Matrix4, b: Matrix4): Matrix4 {
        val out = DoubleArray(16)
        for (c in 0 until 4) for (r in 0 until 4) {
            var sum = 0.0
            for (k in 0 until 4) sum += a[k * 4 + r] * b[c * 4 + k]
            out[c * 4 + r] = sum
        }
        return out
    }

    fun translation(x: Double, y: Double, z: Double = 0.0): Matrix4 = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, x, y, z, 1.0)
    fun scaling(x: Double, y: Double, z: Double = 1.0): Matrix4 = doubleArrayOf(x, 0.0, 0.0, 0.0, 0.0, y, 0.0, 0.0, 0.0, 0.0, z, 0.0, 0.0, 0.0, 0.0, 1.0)

    fun rotationZ(rad: Double): Matrix4 {
        val c = cos(rad)
        val s = sin(rad)
        return doubleArrayOf(c, s, 0.0, 0.0, -s, c, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)
    }

    fun rotationX(rad: Double): Matrix4 {
        val c = cos(rad)
        val s = sin(rad)
        return doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, c, s, 0.0, 0.0, -s, c, 0.0, 0.0, 0.0, 0.0, 1.0)
    }

    fun rotationY(rad: Double): Matrix4 {
        val c = cos(rad)
        val s = sin(rad)
        return doubleArrayOf(c, 0.0, -s, 0.0, 0.0, 1.0, 0.0, 0.0, s, 0.0, c, 0.0, 0.0, 0.0, 0.0, 1.0)
    }

    /** CSS `skew(ax, ay)`. */
    fun skew(ax: Double, ay: Double): Matrix4 = doubleArrayOf(1.0, tan(ay), 0.0, 0.0, tan(ax), 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)

    /** CSS `matrix(a,b,c,d,e,f)` / `matrix3d(…)`. */
    fun fromCss(v: List<Double>): Matrix4? = when (v.size) {
        6 -> doubleArrayOf(v[0], v[1], 0.0, 0.0, v[2], v[3], 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, v[4], v[5], 0.0, 1.0)
        16 -> v.toDoubleArray()
        else -> null
    }

    fun aboutOrigin(m: Matrix4, ox: Double, oy: Double): Matrix4 = multiply(multiply(translation(ox, oy), m), translation(-ox, -oy))

    fun transformPoint(m: Matrix4, x: Double, y: Double): Pair<Double, Double> {
        val tx = m[0] * x + m[4] * y + m[12]
        val ty = m[1] * x + m[5] * y + m[13]
        val tw = m[3] * x + m[7] * y + m[15]
        return if (tw != 0.0 && tw != 1.0) Pair(tx / tw, ty / tw) else Pair(tx, ty)
    }

    fun invert(m: Matrix4): Matrix4? {
        val inv = DoubleArray(16)
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
        if (abs(det) < 1e-12) return null
        det = 1 / det
        for (i in 0 until 16) inv[i] *= det
        return inv
    }

    fun lerp(a: Matrix4, b: Matrix4, t: Double): Matrix4 = DoubleArray(16) { a[it] + (b[it] - a[it]) * t }
}
