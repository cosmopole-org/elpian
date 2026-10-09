package dev.elpian.core.css

/**
 * The resolved style of one element — the Kotlin twin of the Flutter
 * `CSSStyle` model (and of css/style.ts in the TypeScript engine (native/web)), produced by
 * [CSSParser.parse]. Durations are milliseconds.
 */
class CSSStyle {

    // Sizing
    var width: Double? = null
    var height: Double? = null
    var widthFactor: Double? = null
    var heightFactor: Double? = null
    var minWidth: Double? = null
    var maxWidth: Double? = null
    var minHeight: Double? = null
    var maxHeight: Double? = null
    var aspectRatio: Double? = null

    // Spacing
    var padding: EdgeInsets? = null
    var margin: EdgeInsets? = null
    /** Sides whose margin is `auto` (centring in a flex/block parent). */
    var marginAuto: MarginAuto? = null
    /** Padding/margin sides written as percentages, resolved against the parent width. */
    var paddingPercent: SidePercents? = null
    var marginPercent: SidePercents? = null

    // Positioning
    var alignment: Alignment? = null
    var position: String? = null
    var top: Double? = null
    var right: Double? = null
    var bottom: Double? = null
    var left: Double? = null
    var zIndex: Double? = null

    // Layout
    var display: String? = null
    var flexDirection: String? = null
    var justifyContent: String? = null
    var alignItems: String? = null
    var alignContent: String? = null
    var alignSelf: String? = null
    var flex: Double? = null
    var flexGrow: Double? = null
    var flexShrink: Double? = null
    var flexBasis: String? = null
    var flexWrap: String? = null
    var order: Double? = null
    var gap: Double? = null
    var rowGap: Double? = null
    var columnGap: Double? = null
    var overflow: String? = null
    var overflowX: String? = null
    var overflowY: String? = null
    var boxSizing: String? = null

    // Grid
    var gridTemplateColumns: String? = null
    var gridTemplateRows: String? = null
    var gridTemplateAreas: String? = null
    var gridAutoColumns: String? = null
    var gridAutoRows: String? = null
    var gridAutoFlow: String? = null
    var gridColumnGap: Double? = null
    var gridRowGap: Double? = null
    var gridGap: Double? = null
    var gridColumn: String? = null
    var gridRow: String? = null
    var gridArea: String? = null
    var justifyItems: String? = null
    var justifySelf: String? = null

    // Background
    var backgroundColor: Color? = null
    var backgroundImage: String? = null
    var backgroundSize: BoxFit? = null
    var backgroundSizePx: SizePx? = null
    var backgroundPosition: Alignment? = null
    var backgroundRepeat: String? = null
    var gradient: Gradient? = null
    /** Extra gradient layers of a multi-layer `background` (painted under [gradient]). */
    var gradientLayers: List<Gradient>? = null

    // Border
    var border: Border? = null
    var borderRadius: BorderRadius? = null
    /** Corner radii given as percentages of the box (`border-radius: 50%`). */
    var borderRadiusPercent: BorderRadius? = null
    var borderColor: Color? = null
    var borderWidth: Double? = null
    var borderStyle: String? = null
    var outlineColor: Color? = null
    var outlineWidth: Double? = null
    var outlineStyle: String? = null
    var outlineOffset: Double? = null

    // Text
    var color: Color? = null
    var fontSize: Double? = null
    var fontWeight: Int? = null
    var fontStyle: String? = null
    var fontFamily: String? = null
    var letterSpacing: Double? = null
    var wordSpacing: Double? = null
    /** Line height as a multiple of the font size (Flutter `TextStyle.height`). */
    var lineHeight: Double? = null
    /** Line height given in pixels (`line-height: 24px`). */
    var lineHeightPx: Double? = null
    var textAlign: String? = null
    var textDecoration: TextDecoration? = null
    var textDecorationColor: Color? = null
    var textDecorationStyle: String? = null
    var textDecorationThickness: Double? = null
    var textOverflow: TextOverflow? = null
    var textTransform: String? = null
    var whiteSpace: String? = null
    var borderCollapse: String? = null
    var borderSpacing: Double? = null
    var verticalAlign: String? = null
    var writingMode: String? = null
    var wordBreak: String? = null
    var lineClamp: Double? = null

    // Effects
    var boxShadow: List<BoxShadow>? = null
    var textShadow: List<TextShadow>? = null
    var transform: Matrix4? = null
    var rotate: Double? = null
    var scale: Double? = null
    var scaleX: Double? = null
    var scaleY: Double? = null
    var translate: Offset? = null
    var transformOrigin: Alignment? = null
    var opacity: Double? = null
    var visible: Boolean? = null
    var visibility: String? = null
    var filter: Filter? = null
    var backdropFilter: Filter? = null
    var mixBlendMode: String? = null

    // Interaction
    var cursor: String? = null
    var pointerEvents: String? = null
    var userSelect: String? = null
    var touchAction: String? = null

    // Media
    var objectFit: BoxFit? = null
    var objectPosition: Alignment? = null

    // Clipping / shape
    var clipBehavior: String? = null
    var shape: String? = null

    // Transitions and animation
    var transitionDuration: Double? = null // ms
    var transitionCurve: String? = null
    var transitionProperty: String? = null
    var transitionDelay: Double? = null
    var animationName: String? = null
    var animationDuration: Double? = null
    var animationTimingFunction: String? = null
    var animationDelay: Double? = null
    var animationIterationCount: Double? = null // -1 = infinite
    var animationDirection: String? = null
    var animationFillMode: String? = null
    var animationPlayState: String? = null
    var animateOnBuild: Boolean? = null
    var staggerDelay: Double? = null
    var staggerChildren: Double? = null
    var animationFrom: Double? = null
    var animationTo: Double? = null
    var slideBegin: Offset? = null
    var slideEnd: Offset? = null
    var scaleBegin: Double? = null
    var scaleEnd: Double? = null
    var rotationBegin: Double? = null
    var rotationEnd: Double? = null
    var fadeBegin: Double? = null
    var fadeEnd: Double? = null
    var colorBegin: Color? = null
    var colorEnd: Color? = null
    var paddingBegin: EdgeInsets? = null
    var paddingEnd: EdgeInsets? = null
    var alignmentBegin: Alignment? = null
    var alignmentEnd: Alignment? = null
    var shimmerBaseColor: Color? = null
    var shimmerHighlightColor: Color? = null
    var animationAutoReverse: Boolean? = null
    var animationRepeat: Boolean? = null
    var keyframes: List<Keyframe>? = null
    var gradientColors: List<Color>? = null
    var gradientStops: List<Double>? = null

    fun copy(): CSSStyle = CSSStyle().also { c -> FIELDS.forEach { it.copy(this, c) } }

    private class Field(val copy: (CSSStyle, CSSStyle) -> Unit)

    companion object {
        private val FIELDS: List<Field> by lazy {
            CSSStyle::class.java.declaredFields.filter { !java.lang.reflect.Modifier.isStatic(it.modifiers) }.map { f ->
                f.isAccessible = true
                Field { a, b -> f.set(b, f.get(a)) }
            }
        }
    }
}

data class TextDecoration(val underline: Boolean = false, val overline: Boolean = false, val lineThrough: Boolean = false) {
    val isNone: Boolean get() = !underline && !overline && !lineThrough
}

data class MarginAuto(val top: Boolean, val right: Boolean, val bottom: Boolean, val left: Boolean)

data class SidePercents(val top: Percent? = null, val right: Percent? = null, val bottom: Percent? = null, val left: Percent? = null)

data class SizePx(val width: Double?, val height: Double?)
