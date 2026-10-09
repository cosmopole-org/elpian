package dev.elpian.android.render

import android.graphics.Bitmap
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** CPU Gaussian blur (three box passes) for backdrop filters and pre-31 fallbacks. */
object Blur {
    /** Blur [src] (ARGB_8888) in place with a Gaussian of [sigma] px. */
    fun gaussian(src: Bitmap, sigma: Float) {
        if (sigma < 0.3f || src.config != Bitmap.Config.ARGB_8888) return
        val w = src.width
        val h = src.height
        val a = IntArray(w * h)
        val b = IntArray(w * h)
        src.getPixels(a, 0, w, 0, 0, w, h)
        for (box in boxes(sigma, 3)) {
            val r = (box - 1) / 2
            if (r <= 0) continue
            boxH(a, b, w, h, r)
            boxV(b, a, w, h, r)
        }
        src.setPixels(a, 0, w, 0, 0, w, h)
    }

    private fun boxes(sigma: Float, n: Int): IntArray {
        val wIdeal = sqrt((12 * sigma * sigma / n) + 1)
        var wl = floor(wIdeal).toInt()
        if (wl % 2 == 0) wl--
        val wu = wl + 2
        val mIdeal = (12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4)
        val m = mIdeal.roundToInt()
        return IntArray(n) { if (it < m) wl else wu }
    }

    private fun boxH(src: IntArray, dst: IntArray, w: Int, h: Int, r: Int) {
        val div = 2 * r + 1
        for (y in 0 until h) {
            var sa = 0; var sr = 0; var sg = 0; var sb = 0
            val row = y * w
            for (i in -r..r) {
                val p = src[row + min(w - 1, max(0, i))]
                sa += p ushr 24; sr += (p shr 16) and 0xff; sg += (p shr 8) and 0xff; sb += p and 0xff
            }
            for (x in 0 until w) {
                dst[row + x] = ((sa / div) shl 24) or ((sr / div) shl 16) or ((sg / div) shl 8) or (sb / div)
                val pOut = src[row + max(0, x - r)]
                val pIn = src[row + min(w - 1, x + r + 1)]
                sa += (pIn ushr 24) - (pOut ushr 24)
                sr += ((pIn shr 16) and 0xff) - ((pOut shr 16) and 0xff)
                sg += ((pIn shr 8) and 0xff) - ((pOut shr 8) and 0xff)
                sb += (pIn and 0xff) - (pOut and 0xff)
            }
        }
    }

    private fun boxV(src: IntArray, dst: IntArray, w: Int, h: Int, r: Int) {
        val div = 2 * r + 1
        for (x in 0 until w) {
            var sa = 0; var sr = 0; var sg = 0; var sb = 0
            for (i in -r..r) {
                val p = src[min(h - 1, max(0, i)) * w + x]
                sa += p ushr 24; sr += (p shr 16) and 0xff; sg += (p shr 8) and 0xff; sb += p and 0xff
            }
            for (y in 0 until h) {
                dst[y * w + x] = ((sa / div) shl 24) or ((sr / div) shl 16) or ((sg / div) shl 8) or (sb / div)
                val pOut = src[max(0, y - r) * w + x]
                val pIn = src[min(h - 1, y + r + 1) * w + x]
                sa += (pIn ushr 24) - (pOut ushr 24)
                sr += ((pIn shr 16) and 0xff) - ((pOut shr 16) and 0xff)
                sg += ((pIn shr 8) and 0xff) - ((pOut shr 8) and 0xff)
                sb += (pIn and 0xff) - (pOut and 0xff)
            }
        }
    }
}
