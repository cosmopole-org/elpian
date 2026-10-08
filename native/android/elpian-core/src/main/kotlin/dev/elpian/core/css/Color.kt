package dev.elpian.core.css

import dev.elpian.core.util.parseFloatPrefix
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Colours as 32-bit ARGB [Int]s (Flutter's `Color.value` layout, Android's
 * colour ints). Parsing mirrors `CSSParser.parseColor` in the Flutter engine:
 * 8-digit hex is `#AARRGGBB`, Flutter's colour names resolve to its Material
 * swatches, the other CSS keywords are accepted as a superset.
 */
typealias Color = Int

object Colors {
    const val transparent: Color = 0x00000000
    const val black: Color = 0xff000000.toInt()
    const val black87: Color = 0xdd000000.toInt()
    const val black54: Color = 0x8a000000.toInt()
    const val black45: Color = 0x73000000
    const val black38: Color = 0x61000000
    const val black26: Color = 0x42000000
    const val black12: Color = 0x1f000000
    const val white: Color = 0xffffffff.toInt()
    const val white70: Color = 0xb3ffffff.toInt()
    const val white60: Color = 0x99ffffff.toInt()
    const val white54: Color = 0x8affffff.toInt()
    const val white38: Color = 0x62ffffff
    const val white30: Color = 0x4dffffff
    const val white24: Color = 0x3dffffff
    const val white12: Color = 0x1fffffff
    const val white10: Color = 0x1affffff
    const val red: Color = 0xfff44336.toInt()
    const val pink: Color = 0xffe91e63.toInt()
    const val purple: Color = 0xff9c27b0.toInt()
    const val deepPurple: Color = 0xff673ab7.toInt()
    const val indigo: Color = 0xff3f51b5.toInt()
    const val blue: Color = 0xff2196f3.toInt()
    const val lightBlue: Color = 0xff03a9f4.toInt()
    const val cyan: Color = 0xff00bcd4.toInt()
    const val teal: Color = 0xff009688.toInt()
    const val green: Color = 0xff4caf50.toInt()
    const val lightGreen: Color = 0xff8bc34a.toInt()
    const val lime: Color = 0xffcddc39.toInt()
    const val yellow: Color = 0xffffeb3b.toInt()
    const val amber: Color = 0xffffc107.toInt()
    const val orange: Color = 0xffff9800.toInt()
    const val deepOrange: Color = 0xffff5722.toInt()
    const val brown: Color = 0xff795548.toInt()
    const val grey: Color = 0xff9e9e9e.toInt()
    const val grey100: Color = 0xfff5f5f5.toInt()
    const val grey200: Color = 0xffeeeeee.toInt()
    const val grey300: Color = 0xffe0e0e0.toInt()
    const val grey400: Color = 0xffbdbdbd.toInt()
    const val grey600: Color = 0xff757575.toInt()
    const val blueGrey: Color = 0xff607d8b.toInt()
}

/** Material 3 baseline scheme (an un-themed Flutter app). */
object M3 {
    const val primary: Color = 0xff6750a4.toInt()
    const val onPrimary: Color = 0xffffffff.toInt()
    const val primaryContainer: Color = 0xffeaddff.toInt()
    const val secondaryContainer: Color = 0xffe8def8.toInt()
    const val onSecondaryContainer: Color = 0xff1d192b.toInt()
    const val surface: Color = 0xfffef7ff.toInt()
    const val surfaceContainerLow: Color = 0xfff7f2fa.toInt()
    const val surfaceContainerHighest: Color = 0xffe6e0e9.toInt()
    const val onSurface: Color = 0xff1d1b20.toInt()
    const val onSurfaceVariant: Color = 0xff49454f.toInt()
    const val outline: Color = 0xff79747e.toInt()
    const val outlineVariant: Color = 0xffcac4d0.toInt()
    const val error: Color = 0xffb3261e.toInt()
    const val inverseSurface: Color = 0xff322f35.toInt()
    const val onInverseSurface: Color = 0xfff5eff7.toInt()
    const val shadow: Color = 0xff000000.toInt()
}

private val flutterNamed: Map<String, Color> = mapOf(
    "transparent" to Colors.transparent, "black" to Colors.black, "white" to Colors.white,
    "red" to Colors.red, "green" to Colors.green, "blue" to Colors.blue, "yellow" to Colors.yellow,
    "orange" to Colors.orange, "purple" to Colors.purple, "pink" to Colors.pink, "grey" to Colors.grey,
    "gray" to Colors.grey, "brown" to Colors.brown, "cyan" to Colors.cyan, "indigo" to Colors.indigo,
    "lime" to Colors.lime, "teal" to Colors.teal, "amber" to Colors.amber,
    "deeporange" to Colors.deepOrange, "deep-orange" to Colors.deepOrange,
    "deeppurple" to Colors.deepPurple, "deep-purple" to Colors.deepPurple,
    "lightblue" to Colors.lightBlue, "light-blue" to Colors.lightBlue,
    "lightgreen" to Colors.lightGreen, "light-green" to Colors.lightGreen,
    "bluegrey" to Colors.blueGrey, "blue-grey" to Colors.blueGrey,
)

private val cssNamed: Map<String, Int> = mapOf(
        "aliceblue" to 0xf0f8ff,
        "antiquewhite" to 0xfaebd7,
        "aqua" to 0x00ffff,
        "aquamarine" to 0x7fffd4,
        "azure" to 0xf0ffff,
        "beige" to 0xf5f5dc,
        "bisque" to 0xffe4c4,
        "blanchedalmond" to 0xffebcd,
        "blueviolet" to 0x8a2be2,
        "burlywood" to 0xdeb887,
        "cadetblue" to 0x5f9ea0,
        "chartreuse" to 0x7fff00,
        "chocolate" to 0xd2691e,
        "coral" to 0xff7f50,
        "cornflowerblue" to 0x6495ed,
        "cornsilk" to 0xfff8dc,
        "crimson" to 0xdc143c,
        "darkblue" to 0x00008b,
        "darkcyan" to 0x008b8b,
        "darkgoldenrod" to 0xb8860b,
        "darkgray" to 0xa9a9a9,
        "darkgrey" to 0xa9a9a9,
        "darkgreen" to 0x006400,
        "darkkhaki" to 0xbdb76b,
        "darkmagenta" to 0x8b008b,
        "darkolivegreen" to 0x556b2f,
        "darkorange" to 0xff8c00,
        "darkorchid" to 0x9932cc,
        "darkred" to 0x8b0000,
        "darksalmon" to 0xe9967a,
        "darkseagreen" to 0x8fbc8f,
        "darkslateblue" to 0x483d8b,
        "darkslategray" to 0x2f4f4f,
        "darkslategrey" to 0x2f4f4f,
        "darkturquoise" to 0x00ced1,
        "darkviolet" to 0x9400d3,
        "deeppink" to 0xff1493,
        "deepskyblue" to 0x00bfff,
        "dimgray" to 0x696969,
        "dimgrey" to 0x696969,
        "dodgerblue" to 0x1e90ff,
        "firebrick" to 0xb22222,
        "floralwhite" to 0xfffaf0,
        "forestgreen" to 0x228b22,
        "fuchsia" to 0xff00ff,
        "gainsboro" to 0xdcdcdc,
        "ghostwhite" to 0xf8f8ff,
        "gold" to 0xffd700,
        "goldenrod" to 0xdaa520,
        "greenyellow" to 0xadff2f,
        "honeydew" to 0xf0fff0,
        "hotpink" to 0xff69b4,
        "indianred" to 0xcd5c5c,
        "ivory" to 0xfffff0,
        "khaki" to 0xf0e68c,
        "lavender" to 0xe6e6fa,
        "lavenderblush" to 0xfff0f5,
        "lawngreen" to 0x7cfc00,
        "lemonchiffon" to 0xfffacd,
        "lightcoral" to 0xf08080,
        "lightcyan" to 0xe0ffff,
        "lightgoldenrodyellow" to 0xfafad2,
        "lightgray" to 0xd3d3d3,
        "lightgrey" to 0xd3d3d3,
        "lightpink" to 0xffb6c1,
        "lightsalmon" to 0xffa07a,
        "lightseagreen" to 0x20b2aa,
        "lightskyblue" to 0x87cefa,
        "lightslategray" to 0x778899,
        "lightslategrey" to 0x778899,
        "lightsteelblue" to 0xb0c4de,
        "lightyellow" to 0xffffe0,
        "limegreen" to 0x32cd32,
        "linen" to 0xfaf0e6,
        "magenta" to 0xff00ff,
        "maroon" to 0x800000,
        "mediumaquamarine" to 0x66cdaa,
        "mediumblue" to 0x0000cd,
        "mediumorchid" to 0xba55d3,
        "mediumpurple" to 0x9370db,
        "mediumseagreen" to 0x3cb371,
        "mediumslateblue" to 0x7b68ee,
        "mediumspringgreen" to 0x00fa9a,
        "mediumturquoise" to 0x48d1cc,
        "mediumvioletred" to 0xc71585,
        "midnightblue" to 0x191970,
        "mintcream" to 0xf5fffa,
        "mistyrose" to 0xffe4e1,
        "moccasin" to 0xffe4b5,
        "navajowhite" to 0xffdead,
        "navy" to 0x000080,
        "oldlace" to 0xfdf5e6,
        "olive" to 0x808000,
        "olivedrab" to 0x6b8e23,
        "orangered" to 0xff4500,
        "orchid" to 0xda70d6,
        "palegoldenrod" to 0xeee8aa,
        "palegreen" to 0x98fb98,
        "paleturquoise" to 0xafeeee,
        "palevioletred" to 0xdb7093,
        "papayawhip" to 0xffefd5,
        "peachpuff" to 0xffdab9,
        "peru" to 0xcd853f,
        "plum" to 0xdda0dd,
        "powderblue" to 0xb0e0e6,
        "rebeccapurple" to 0x663399,
        "rosybrown" to 0xbc8f8f,
        "royalblue" to 0x4169e1,
        "saddlebrown" to 0x8b4513,
        "salmon" to 0xfa8072,
        "sandybrown" to 0xf4a460,
        "seagreen" to 0x2e8b57,
        "seashell" to 0xfff5ee,
        "sienna" to 0xa0522d,
        "silver" to 0xc0c0c0,
        "skyblue" to 0x87ceeb,
        "slateblue" to 0x6a5acd,
        "slategray" to 0x708090,
        "slategrey" to 0x708090,
        "snow" to 0xfffafa,
        "springgreen" to 0x00ff7f,
        "steelblue" to 0x4682b4,
        "tan" to 0xd2b48c,
        "thistle" to 0xd8bfd8,
        "tomato" to 0xff6347,
        "turquoise" to 0x40e0d0,
        "violet" to 0xee82ee,
        "wheat" to 0xf5deb3,
        "whitesmoke" to 0xf5f5f5,
        "yellowgreen" to 0x9acd32
)

fun argb(a: Int, r: Int, g: Int, b: Int): Color = ((a and 0xff) shl 24) or ((r and 0xff) shl 16) or ((g and 0xff) shl 8) or (b and 0xff)
fun alphaOf(c: Color): Int = (c ushr 24) and 0xff
fun redOf(c: Color): Int = (c ushr 16) and 0xff
fun greenOf(c: Color): Int = (c ushr 8) and 0xff
fun blueOf(c: Color): Int = c and 0xff

/** Replace the alpha with [opacity] (0..1) — `Color.withValues(alpha:)`. */
fun withOpacity(c: Color, opacity: Double): Color {
    val a = (opacity.coerceIn(0.0, 1.0) * 255).roundToInt()
    return (c and 0x00ffffff) or (a shl 24)
}

fun scaleAlpha(c: Color, factor: Double): Color = withOpacity(c, alphaOf(c) / 255.0 * factor)

fun lerpColor(a: Color, b: Color, t: Double): Color {
    fun l(x: Int, y: Int) = Math.round(x + (y - x) * t).toInt()
    return argb(l(alphaOf(a), alphaOf(b)), l(redOf(a), redOf(b)), l(greenOf(a), greenOf(b)), l(blueOf(a), blueOf(b)))
}

private fun hslToRgb(h: Double, s: Double, l: Double): IntArray {
    val chroma = (1 - abs(2 * l - 1)) * s
    val hp = (((h % 360) + 360) % 360) / 60
    val x = chroma * (1 - abs((hp % 2) - 1))
    val (r, g, b) = when {
        hp < 1 -> Triple(chroma, x, 0.0)
        hp < 2 -> Triple(x, chroma, 0.0)
        hp < 3 -> Triple(0.0, chroma, x)
        hp < 4 -> Triple(0.0, x, chroma)
        hp < 5 -> Triple(x, 0.0, chroma)
        else -> Triple(chroma, 0.0, x)
    }
    val m = l - chroma / 2
    return intArrayOf(Math.round((r + m) * 255).toInt(), Math.round((g + m) * 255).toInt(), Math.round((b + m) * 255).toInt())
}

private fun channel(token: String, scale: Double): Double {
    val t = token.trim()
    val v = parseFloatPrefix(t) ?: Double.NaN
    return if (t.endsWith("%")) v / 100 * scale else v
}

private fun alphaChannel(token: String?): Double {
    if (token == null || token.isBlank()) return 1.0
    val t = token.trim()
    val v = parseFloatPrefix(t) ?: Double.NaN
    return if (t.endsWith("%")) v / 100 else v
}

private val NONE = Any()
private val cache = ConcurrentHashMap<String, Any>()

/** Parse a colour value: an ARGB number or a CSS / Flutter colour string. */
fun parseColor(value: Any?): Color? {
    when (value) {
        null -> return null
        is Number -> return value.toLong().toInt()
        !is String -> return null
    }
    val s = value as String
    val hit = cache[s]
    if (hit != null) return if (hit === NONE) null else hit as Int
    val parsed = parseColorString(s.trim())
    if (cache.size > 2048) cache.clear()
    cache[s] = parsed ?: NONE
    return parsed
}

private val FN = Regex("^(rgba?|hsla?)\\(\\s*([^)]*)\\)$")
private val HEX = Regex("^[0-9a-f]+$")

private fun parseColorString(raw: String): Color? {
    if (raw.isEmpty()) return null
    val lower = raw.lowercase()
    if (lower.startsWith("#")) {
        var hex = lower.substring(1)
        if (hex.length == 3 || hex.length == 4) hex = hex.map { "$it$it" }.joinToString("")
        if (!HEX.matches(hex)) return null
        if (hex.length == 6) return (0xff000000L or hex.toLong(16)).toInt()
        if (hex.length == 8) return hex.toLong(16).toInt()
        return null
    }
    if (lower.startsWith("0x")) {
        val n = lower.substring(2).toLongOrNull(16) ?: return null
        return (if (lower.length <= 8) 0xff000000L or n else n).toInt()
    }
    val fn = FN.find(lower)
    if (fn != null) {
        val body = fn.groupValues[2]
        val parts: MutableList<String>
        var alphaPart: String? = null
        if (body.contains(',')) {
            parts = body.split(',').map { it.trim() }.toMutableList()
            if (parts.size == 4) alphaPart = parts.removeAt(3)
        } else {
            val split = body.split('/')
            parts = split[0].trim().split(Regex("\\s+")).toMutableList()
            alphaPart = split.getOrNull(1)
            if (parts.size == 4 && alphaPart == null) alphaPart = parts.removeAt(3)
        }
        if (parts.size < 3) return null
        val alpha = alphaChannel(alphaPart).coerceIn(0.0, 1.0)
        if (fn.groupValues[1].startsWith("rgb")) {
            val r = channel(parts[0], 255.0)
            val g = channel(parts[1], 255.0)
            val b = channel(parts[2], 255.0)
            if (listOf(r, g, b, alpha).any { it.isNaN() }) return null
            // Flutter truncates alpha: (a * 255).toInt()
            return argb((alpha * 255).toInt(), Math.round(r).toInt(), Math.round(g).toInt(), Math.round(b).toInt())
        }
        var h = parseFloatPrefix(parts[0]) ?: Double.NaN
        if (parts[0].endsWith("turn")) h *= 360 else if (parts[0].endsWith("rad")) h = h * 180 / Math.PI
        val s = (parseFloatPrefix(parts[1]) ?: Double.NaN) / 100
        val l = (parseFloatPrefix(parts[2]) ?: Double.NaN) / 100
        if (listOf(h, s, l, alpha).any { it.isNaN() }) return null
        val rgb = hslToRgb(h, s, l)
        return argb(Math.round(alpha * 255).toInt(), rgb[0], rgb[1], rgb[2])
    }
    flutterNamed[lower]?.let { return it }
    cssNamed[lower]?.let { return (0xff000000L or it.toLong()).toInt() }
    return null
}

/** `#rrggbb` / `rgba(…)` — for diagnostics and the web view of a colour. */
fun toCssColor(c: Color): String {
    val a = alphaOf(c)
    return if (a == 255) "#" + String.format("%06x", c and 0xffffff)
    else "rgba(${redOf(c)},${greenOf(c)},${blueOf(c)},${"%.4f".format(a / 255.0).trimEnd('0').trimEnd('.')})"
}
