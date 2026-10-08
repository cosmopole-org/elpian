import Foundation

/**
 * The resolved style of one element — the Swift twin of the Flutter
 * `CSSStyle` model (css/style.ts), produced by [CSSParser.parse].
 *
 * Every field the Flutter parser fills is present with the same meaning; the
 * extra fields are values Flutter's model declares but its parser leaves
 * unread (filters, outlines, per-side borders from CSS strings, `margin:auto`
 * …), which the native renderers honour. Durations are milliseconds.
 * Instances returned by the parser are cached and shared: [copy] before
 * mutating one.
 */
public final class CSSStyle: JSONSerializable {
    public init() {}


    // Sizing
    public var width: Double?
    public var height: Double?
    public var widthFactor: Double?
    public var heightFactor: Double?
    public var minWidth: Double?
    public var maxWidth: Double?
    public var minHeight: Double?
    public var maxHeight: Double?
    public var aspectRatio: Double?

    // Spacing
    public var padding: EdgeInsets?
    public var margin: EdgeInsets?
    /** Sides whose margin is `auto` (centring in a flex/block parent). */
    public var marginAuto: MarginAuto?
    /** Padding/margin sides written as percentages, resolved against the parent width. */
    public var paddingPercent: SidePercents?
    public var marginPercent: SidePercents?

    // Positioning
    public var alignment: Alignment?
    public var position: String?
    public var top: Double?
    public var right: Double?
    public var bottom: Double?
    public var left: Double?
    public var zIndex: Double?

    // Layout
    public var display: String?
    public var flexDirection: String?
    public var justifyContent: String?
    public var alignItems: String?
    public var alignContent: String?
    public var alignSelf: String?
    public var flex: Double?
    public var flexGrow: Double?
    public var flexShrink: Double?
    public var flexBasis: String?
    public var flexWrap: String?
    public var order: Double?
    public var gap: Double?
    public var rowGap: Double?
    public var columnGap: Double?
    public var overflow: String?
    public var overflowX: String?
    public var overflowY: String?
    public var boxSizing: String?

    // Grid
    public var gridTemplateColumns: String?
    public var gridTemplateRows: String?
    public var gridTemplateAreas: String?
    public var gridAutoColumns: String?
    public var gridAutoRows: String?
    public var gridAutoFlow: String?
    public var gridColumnGap: Double?
    public var gridRowGap: Double?
    public var gridGap: Double?
    public var gridColumn: String?
    public var gridRow: String?
    public var gridArea: String?
    public var justifyItems: String?
    public var justifySelf: String?

    // Background
    public var backgroundColor: Color?
    public var backgroundImage: String?
    public var backgroundSize: BoxFit?
    public var backgroundSizePx: SizePx?
    public var backgroundPosition: Alignment?
    public var backgroundRepeat: String?
    public var gradient: Gradient?
    /** Extra gradient layers of a multi-layer `background` (painted under [gradient]). */
    public var gradientLayers: [Gradient]?

    // Border
    public var border: Border?
    public var borderRadius: BorderRadius?
    /** Corner radii given as percentages of the box (`border-radius: 50%`). */
    public var borderRadiusPercent: BorderRadius?
    public var borderColor: Color?
    public var borderWidth: Double?
    public var borderStyle: String?
    public var outlineColor: Color?
    public var outlineWidth: Double?
    public var outlineStyle: String?
    public var outlineOffset: Double?

    // Text
    public var color: Color?
    public var fontSize: Double?
    public var fontWeight: Int?
    public var fontStyle: String?
    public var fontFamily: String?
    public var letterSpacing: Double?
    public var wordSpacing: Double?
    /** Line height as a multiple of the font size (Flutter `TextStyle.height`). */
    public var lineHeight: Double?
    /** Line height given in pixels (`line-height: 24px`). */
    public var lineHeightPx: Double?
    public var textAlign: String?
    public var textDecoration: TextDecoration?
    public var textDecorationColor: Color?
    public var textDecorationStyle: String?
    public var textDecorationThickness: Double?
    public var textOverflow: TextOverflow?
    public var textTransform: String?
    public var whiteSpace: String?
    public var borderCollapse: String?
    public var borderSpacing: Double?
    public var verticalAlign: String?
    public var writingMode: String?
    public var wordBreak: String?
    public var lineClamp: Double?

    // Effects
    public var boxShadow: [BoxShadow]?
    public var textShadow: [TextShadow]?
    public var transform: Matrix4?
    public var rotate: Double?
    public var scale: Double?
    public var scaleX: Double?
    public var scaleY: Double?
    public var translate: Offset?
    public var transformOrigin: Alignment?
    public var opacity: Double?
    public var visible: Bool?
    public var visibility: String?
    public var filter: Filter?
    public var backdropFilter: Filter?
    public var mixBlendMode: String?

    // Interaction
    public var cursor: String?
    public var pointerEvents: String?
    public var userSelect: String?
    public var touchAction: String?

    // Media
    public var objectFit: BoxFit?
    public var objectPosition: Alignment?

    // Clipping / shape
    public var clipBehavior: String?
    public var shape: String?

    // Transitions and animation
    public var transitionDuration: Double? // ms
    public var transitionCurve: String?
    public var transitionProperty: String?
    public var transitionDelay: Double?
    public var animationName: String?
    public var animationDuration: Double?
    public var animationTimingFunction: String?
    public var animationDelay: Double?
    public var animationIterationCount: Double? // -1 = infinite
    public var animationDirection: String?
    public var animationFillMode: String?
    public var animationPlayState: String?
    public var animateOnBuild: Bool?
    public var staggerDelay: Double?
    public var staggerChildren: Double?
    public var animationFrom: Double?
    public var animationTo: Double?
    public var slideBegin: Offset?
    public var slideEnd: Offset?
    public var scaleBegin: Double?
    public var scaleEnd: Double?
    public var rotationBegin: Double?
    public var rotationEnd: Double?
    public var fadeBegin: Double?
    public var fadeEnd: Double?
    public var colorBegin: Color?
    public var colorEnd: Color?
    public var paddingBegin: EdgeInsets?
    public var paddingEnd: EdgeInsets?
    public var alignmentBegin: Alignment?
    public var alignmentEnd: Alignment?
    public var shimmerBaseColor: Color?
    public var shimmerHighlightColor: Color?
    public var animationAutoReverse: Bool?
    public var animationRepeat: Bool?
    public var keyframes: [Keyframe]?
    public var gradientColors: [Color]?
    public var gradientStops: [Double]?


    /** A field-by-field copy (`{...style}`). */
    public func copy() -> CSSStyle {
        let c = CSSStyle()
        c.width = width
        c.height = height
        c.widthFactor = widthFactor
        c.heightFactor = heightFactor
        c.minWidth = minWidth
        c.maxWidth = maxWidth
        c.minHeight = minHeight
        c.maxHeight = maxHeight
        c.aspectRatio = aspectRatio
        c.padding = padding
        c.margin = margin
        c.marginAuto = marginAuto
        c.paddingPercent = paddingPercent
        c.marginPercent = marginPercent
        c.alignment = alignment
        c.position = position
        c.top = top
        c.right = right
        c.bottom = bottom
        c.left = left
        c.zIndex = zIndex
        c.display = display
        c.flexDirection = flexDirection
        c.justifyContent = justifyContent
        c.alignItems = alignItems
        c.alignContent = alignContent
        c.alignSelf = alignSelf
        c.flex = flex
        c.flexGrow = flexGrow
        c.flexShrink = flexShrink
        c.flexBasis = flexBasis
        c.flexWrap = flexWrap
        c.order = order
        c.gap = gap
        c.rowGap = rowGap
        c.columnGap = columnGap
        c.overflow = overflow
        c.overflowX = overflowX
        c.overflowY = overflowY
        c.boxSizing = boxSizing
        c.gridTemplateColumns = gridTemplateColumns
        c.gridTemplateRows = gridTemplateRows
        c.gridTemplateAreas = gridTemplateAreas
        c.gridAutoColumns = gridAutoColumns
        c.gridAutoRows = gridAutoRows
        c.gridAutoFlow = gridAutoFlow
        c.gridColumnGap = gridColumnGap
        c.gridRowGap = gridRowGap
        c.gridGap = gridGap
        c.gridColumn = gridColumn
        c.gridRow = gridRow
        c.gridArea = gridArea
        c.justifyItems = justifyItems
        c.justifySelf = justifySelf
        c.backgroundColor = backgroundColor
        c.backgroundImage = backgroundImage
        c.backgroundSize = backgroundSize
        c.backgroundSizePx = backgroundSizePx
        c.backgroundPosition = backgroundPosition
        c.backgroundRepeat = backgroundRepeat
        c.gradient = gradient
        c.gradientLayers = gradientLayers
        c.border = border
        c.borderRadius = borderRadius
        c.borderRadiusPercent = borderRadiusPercent
        c.borderColor = borderColor
        c.borderWidth = borderWidth
        c.borderStyle = borderStyle
        c.outlineColor = outlineColor
        c.outlineWidth = outlineWidth
        c.outlineStyle = outlineStyle
        c.outlineOffset = outlineOffset
        c.color = color
        c.fontSize = fontSize
        c.fontWeight = fontWeight
        c.fontStyle = fontStyle
        c.fontFamily = fontFamily
        c.letterSpacing = letterSpacing
        c.wordSpacing = wordSpacing
        c.lineHeight = lineHeight
        c.lineHeightPx = lineHeightPx
        c.textAlign = textAlign
        c.textDecoration = textDecoration
        c.textDecorationColor = textDecorationColor
        c.textDecorationStyle = textDecorationStyle
        c.textDecorationThickness = textDecorationThickness
        c.textOverflow = textOverflow
        c.textTransform = textTransform
        c.whiteSpace = whiteSpace
        c.borderCollapse = borderCollapse
        c.borderSpacing = borderSpacing
        c.verticalAlign = verticalAlign
        c.writingMode = writingMode
        c.wordBreak = wordBreak
        c.lineClamp = lineClamp
        c.boxShadow = boxShadow
        c.textShadow = textShadow
        c.transform = transform
        c.rotate = rotate
        c.scale = scale
        c.scaleX = scaleX
        c.scaleY = scaleY
        c.translate = translate
        c.transformOrigin = transformOrigin
        c.opacity = opacity
        c.visible = visible
        c.visibility = visibility
        c.filter = filter
        c.backdropFilter = backdropFilter
        c.mixBlendMode = mixBlendMode
        c.cursor = cursor
        c.pointerEvents = pointerEvents
        c.userSelect = userSelect
        c.touchAction = touchAction
        c.objectFit = objectFit
        c.objectPosition = objectPosition
        c.clipBehavior = clipBehavior
        c.shape = shape
        c.transitionDuration = transitionDuration
        c.transitionCurve = transitionCurve
        c.transitionProperty = transitionProperty
        c.transitionDelay = transitionDelay
        c.animationName = animationName
        c.animationDuration = animationDuration
        c.animationTimingFunction = animationTimingFunction
        c.animationDelay = animationDelay
        c.animationIterationCount = animationIterationCount
        c.animationDirection = animationDirection
        c.animationFillMode = animationFillMode
        c.animationPlayState = animationPlayState
        c.animateOnBuild = animateOnBuild
        c.staggerDelay = staggerDelay
        c.staggerChildren = staggerChildren
        c.animationFrom = animationFrom
        c.animationTo = animationTo
        c.slideBegin = slideBegin
        c.slideEnd = slideEnd
        c.scaleBegin = scaleBegin
        c.scaleEnd = scaleEnd
        c.rotationBegin = rotationBegin
        c.rotationEnd = rotationEnd
        c.fadeBegin = fadeBegin
        c.fadeEnd = fadeEnd
        c.colorBegin = colorBegin
        c.colorEnd = colorEnd
        c.paddingBegin = paddingBegin
        c.paddingEnd = paddingEnd
        c.alignmentBegin = alignmentBegin
        c.alignmentEnd = alignmentEnd
        c.shimmerBaseColor = shimmerBaseColor
        c.shimmerHighlightColor = shimmerHighlightColor
        c.animationAutoReverse = animationAutoReverse
        c.animationRepeat = animationRepeat
        c.keyframes = keyframes
        c.gradientColors = gradientColors
        c.gradientStops = gradientStops
        return c
    }

    /** The style as the TypeScript object (absent fields left out). */
    public func toJSON() -> Any? {
        let o = JSONObject()
        if let v = width { o["width"] = v }
        if let v = height { o["height"] = v }
        if let v = widthFactor { o["widthFactor"] = v }
        if let v = heightFactor { o["heightFactor"] = v }
        if let v = minWidth { o["minWidth"] = v }
        if let v = maxWidth { o["maxWidth"] = v }
        if let v = minHeight { o["minHeight"] = v }
        if let v = maxHeight { o["maxHeight"] = v }
        if let v = aspectRatio { o["aspectRatio"] = v }
        if let v = padding { o["padding"] = v }
        if let v = margin { o["margin"] = v }
        if let v = marginAuto { o["marginAuto"] = v }
        if let v = paddingPercent { o["paddingPercent"] = v }
        if let v = marginPercent { o["marginPercent"] = v }
        if let v = alignment { o["alignment"] = v }
        if let v = position { o["position"] = v }
        if let v = top { o["top"] = v }
        if let v = right { o["right"] = v }
        if let v = bottom { o["bottom"] = v }
        if let v = left { o["left"] = v }
        if let v = zIndex { o["zIndex"] = v }
        if let v = display { o["display"] = v }
        if let v = flexDirection { o["flexDirection"] = v }
        if let v = justifyContent { o["justifyContent"] = v }
        if let v = alignItems { o["alignItems"] = v }
        if let v = alignContent { o["alignContent"] = v }
        if let v = alignSelf { o["alignSelf"] = v }
        if let v = flex { o["flex"] = v }
        if let v = flexGrow { o["flexGrow"] = v }
        if let v = flexShrink { o["flexShrink"] = v }
        if let v = flexBasis { o["flexBasis"] = v }
        if let v = flexWrap { o["flexWrap"] = v }
        if let v = order { o["order"] = v }
        if let v = gap { o["gap"] = v }
        if let v = rowGap { o["rowGap"] = v }
        if let v = columnGap { o["columnGap"] = v }
        if let v = overflow { o["overflow"] = v }
        if let v = overflowX { o["overflowX"] = v }
        if let v = overflowY { o["overflowY"] = v }
        if let v = boxSizing { o["boxSizing"] = v }
        if let v = gridTemplateColumns { o["gridTemplateColumns"] = v }
        if let v = gridTemplateRows { o["gridTemplateRows"] = v }
        if let v = gridTemplateAreas { o["gridTemplateAreas"] = v }
        if let v = gridAutoColumns { o["gridAutoColumns"] = v }
        if let v = gridAutoRows { o["gridAutoRows"] = v }
        if let v = gridAutoFlow { o["gridAutoFlow"] = v }
        if let v = gridColumnGap { o["gridColumnGap"] = v }
        if let v = gridRowGap { o["gridRowGap"] = v }
        if let v = gridGap { o["gridGap"] = v }
        if let v = gridColumn { o["gridColumn"] = v }
        if let v = gridRow { o["gridRow"] = v }
        if let v = gridArea { o["gridArea"] = v }
        if let v = justifyItems { o["justifyItems"] = v }
        if let v = justifySelf { o["justifySelf"] = v }
        if let v = backgroundColor { o["backgroundColor"] = v }
        if let v = backgroundImage { o["backgroundImage"] = v }
        if let v = backgroundSize { o["backgroundSize"] = v.rawValue }
        if let v = backgroundSizePx { o["backgroundSizePx"] = v }
        if let v = backgroundPosition { o["backgroundPosition"] = v }
        if let v = backgroundRepeat { o["backgroundRepeat"] = v }
        if let v = gradient { o["gradient"] = v }
        if let v = gradientLayers { o["gradientLayers"] = v.map { $0 as Any? } }
        if let v = border { o["border"] = v }
        if let v = borderRadius { o["borderRadius"] = v }
        if let v = borderRadiusPercent { o["borderRadiusPercent"] = v }
        if let v = borderColor { o["borderColor"] = v }
        if let v = borderWidth { o["borderWidth"] = v }
        if let v = borderStyle { o["borderStyle"] = v }
        if let v = outlineColor { o["outlineColor"] = v }
        if let v = outlineWidth { o["outlineWidth"] = v }
        if let v = outlineStyle { o["outlineStyle"] = v }
        if let v = outlineOffset { o["outlineOffset"] = v }
        if let v = color { o["color"] = v }
        if let v = fontSize { o["fontSize"] = v }
        if let v = fontWeight { o["fontWeight"] = v }
        if let v = fontStyle { o["fontStyle"] = v }
        if let v = fontFamily { o["fontFamily"] = v }
        if let v = letterSpacing { o["letterSpacing"] = v }
        if let v = wordSpacing { o["wordSpacing"] = v }
        if let v = lineHeight { o["lineHeight"] = v }
        if let v = lineHeightPx { o["lineHeightPx"] = v }
        if let v = textAlign { o["textAlign"] = v }
        if let v = textDecoration { o["textDecoration"] = v }
        if let v = textDecorationColor { o["textDecorationColor"] = v }
        if let v = textDecorationStyle { o["textDecorationStyle"] = v }
        if let v = textDecorationThickness { o["textDecorationThickness"] = v }
        if let v = textOverflow { o["textOverflow"] = v.rawValue }
        if let v = textTransform { o["textTransform"] = v }
        if let v = whiteSpace { o["whiteSpace"] = v }
        if let v = borderCollapse { o["borderCollapse"] = v }
        if let v = borderSpacing { o["borderSpacing"] = v }
        if let v = verticalAlign { o["verticalAlign"] = v }
        if let v = writingMode { o["writingMode"] = v }
        if let v = wordBreak { o["wordBreak"] = v }
        if let v = lineClamp { o["lineClamp"] = v }
        if let v = boxShadow { o["boxShadow"] = v.map { $0 as Any? } }
        if let v = textShadow { o["textShadow"] = v.map { $0 as Any? } }
        if let v = transform { o["transform"] = v }
        if let v = rotate { o["rotate"] = v }
        if let v = scale { o["scale"] = v }
        if let v = scaleX { o["scaleX"] = v }
        if let v = scaleY { o["scaleY"] = v }
        if let v = translate { o["translate"] = v }
        if let v = transformOrigin { o["transformOrigin"] = v }
        if let v = opacity { o["opacity"] = v }
        if let v = visible { o["visible"] = v }
        if let v = visibility { o["visibility"] = v }
        if let v = filter { o["filter"] = v }
        if let v = backdropFilter { o["backdropFilter"] = v }
        if let v = mixBlendMode { o["mixBlendMode"] = v }
        if let v = cursor { o["cursor"] = v }
        if let v = pointerEvents { o["pointerEvents"] = v }
        if let v = userSelect { o["userSelect"] = v }
        if let v = touchAction { o["touchAction"] = v }
        if let v = objectFit { o["objectFit"] = v.rawValue }
        if let v = objectPosition { o["objectPosition"] = v }
        if let v = clipBehavior { o["clipBehavior"] = v }
        if let v = shape { o["shape"] = v }
        if let v = transitionDuration { o["transitionDuration"] = v }
        if let v = transitionCurve { o["transitionCurve"] = v }
        if let v = transitionProperty { o["transitionProperty"] = v }
        if let v = transitionDelay { o["transitionDelay"] = v }
        if let v = animationName { o["animationName"] = v }
        if let v = animationDuration { o["animationDuration"] = v }
        if let v = animationTimingFunction { o["animationTimingFunction"] = v }
        if let v = animationDelay { o["animationDelay"] = v }
        if let v = animationIterationCount { o["animationIterationCount"] = v }
        if let v = animationDirection { o["animationDirection"] = v }
        if let v = animationFillMode { o["animationFillMode"] = v }
        if let v = animationPlayState { o["animationPlayState"] = v }
        if let v = animateOnBuild { o["animateOnBuild"] = v }
        if let v = staggerDelay { o["staggerDelay"] = v }
        if let v = staggerChildren { o["staggerChildren"] = v }
        if let v = animationFrom { o["animationFrom"] = v }
        if let v = animationTo { o["animationTo"] = v }
        if let v = slideBegin { o["slideBegin"] = v }
        if let v = slideEnd { o["slideEnd"] = v }
        if let v = scaleBegin { o["scaleBegin"] = v }
        if let v = scaleEnd { o["scaleEnd"] = v }
        if let v = rotationBegin { o["rotationBegin"] = v }
        if let v = rotationEnd { o["rotationEnd"] = v }
        if let v = fadeBegin { o["fadeBegin"] = v }
        if let v = fadeEnd { o["fadeEnd"] = v }
        if let v = colorBegin { o["colorBegin"] = v }
        if let v = colorEnd { o["colorEnd"] = v }
        if let v = paddingBegin { o["paddingBegin"] = v }
        if let v = paddingEnd { o["paddingEnd"] = v }
        if let v = alignmentBegin { o["alignmentBegin"] = v }
        if let v = alignmentEnd { o["alignmentEnd"] = v }
        if let v = shimmerBaseColor { o["shimmerBaseColor"] = v }
        if let v = shimmerHighlightColor { o["shimmerHighlightColor"] = v }
        if let v = animationAutoReverse { o["animationAutoReverse"] = v }
        if let v = animationRepeat { o["animationRepeat"] = v }
        if let v = keyframes { o["keyframes"] = v.map { $0 as Any? } }
        if let v = gradientColors { o["gradientColors"] = v.map { $0 as Any? } }
        if let v = gradientStops { o["gradientStops"] = v.map { $0 as Any? } }
        return o
    }
}

/** Sides whose margin is `auto` (centring in a flex/block parent). */
public struct MarginAuto: Equatable, Hashable, JSONSerializable {
    public var top: Bool
    public var right: Bool
    public var bottom: Bool
    public var left: Bool

    public init(top: Bool = false, right: Bool = false, bottom: Bool = false, left: Bool = false) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public func toJSON() -> Any? { JSONObject([("top", top), ("right", right), ("bottom", bottom), ("left", left)]) }
}

/** Padding/margin sides written as percentages (absent sides are not percentages). */
public struct SidePercents: Equatable, Hashable, JSONSerializable {
    public var top: Percent?
    public var right: Percent?
    public var bottom: Percent?
    public var left: Percent?

    public init(top: Percent? = nil, right: Percent? = nil, bottom: Percent? = nil, left: Percent? = nil) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public var isEmpty: Bool { top == nil && right == nil && bottom == nil && left == nil }

    public func toJSON() -> Any? {
        let o = JSONObject()
        if let v = top { o["top"] = v }
        if let v = right { o["right"] = v }
        if let v = bottom { o["bottom"] = v }
        if let v = left { o["left"] = v }
        return o
    }
}

/** `background-size` in pixels (`120px auto`). */
public struct SizePx: Equatable, Hashable, JSONSerializable {
    public var width: Double?
    public var height: Double?

    public init(width: Double?, height: Double?) {
        self.width = width
        self.height = height
    }

    public func toJSON() -> Any? { JSONObject([("width", width), ("height", height)]) }
}
