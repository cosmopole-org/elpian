package dev.elpian.core.render

import dev.elpian.core.css.Color
import dev.elpian.core.css.TextShadow

/**
 * The view protocol (render/view.ts): the core lays out the tree and emits
 * operations over primitive view kinds; the Android renderer maps each kind
 * onto a native View. Frames are logical pixels relative to the parent view
 * (a scroll view's children are relative to its content origin).
 *
 * Kinds: view, text, image, scroll, textInput, checkbox, radio, switch,
 * slider, select, progress, canvas, scene3d, video, audio, web, native.
 */
object ViewKinds {
    const val VIEW = "view"
    const val TEXT = "text"
    const val IMAGE = "image"
    const val SCROLL = "scroll"
    const val TEXT_INPUT = "textInput"
    const val CHECKBOX = "checkbox"
    const val RADIO = "radio"
    const val SWITCH = "switch"
    const val SLIDER = "slider"
    const val SELECT = "select"
    const val PROGRESS = "progress"
    const val CANVAS = "canvas"
    const val SCENE3D = "scene3d"
    const val VIDEO = "video"
    const val AUDIO = "audio"
    const val WEB = "web"
    const val NATIVE = "native"
}

const val ROOT_VIEW_ID = 0

data class TextStyleSpec(
    val color: Color,
    val fontSize: Double,
    val fontWeight: Int,
    val italic: Boolean,
    /** null = platform sans-serif; `serif`, `monospace`, `icons` or a family name. */
    val fontFamily: String?,
    val letterSpacing: Double,
    val wordSpacing: Double,
    /** Line height as a multiple of the font size (Flutter `height`); null = font default. */
    val height: Double?,
    /** Bit flags: 1 underline, 2 overline, 4 line-through. */
    val decoration: Int,
    val decorationColor: Color?,
    val decorationStyle: String?,
    val decorationThickness: Double?,
    val shadows: List<TextShadow>?,
    val background: Color?,
    /** Vertical shift in px (positive = down) for `sub` / `sup`. */
    val baselineShift: Double,
)

data class TextSpanSpec(val text: String, val style: TextStyleSpec, val link: String? = null)

data class TextSpec(
    val spans: List<TextSpanSpec>,
    /** left, right, center, justify, start, end */
    val align: String,
    val maxLines: Int?,
    /** clip, ellipsis, fade, visible */
    val overflow: String,
    val softWrap: Boolean,
    val selectable: Boolean,
    /** ltr, rtl */
    val direction: String,
)

data class TextMetrics(
    val width: Double,
    val height: Double,
    /** Distance from the top to the first line's alphabetic baseline. */
    val baseline: Double,
    val lineCount: Int,
    val didExceedMaxLines: Boolean,
)

/** Sizes a native control the core cannot measure itself. */
data class ControlMeasureSpec(val kind: String, val props: Map<String, Any?>)

sealed class ViewOp {
    data class Create(val id: Int, val kind: String, val parent: Int, val index: Int, val props: Map<String, Any?>) : ViewOp()
    data class Update(val id: Int, val props: Map<String, Any?>) : ViewOp()
    data class Move(val id: Int, val parent: Int, val index: Int) : ViewOp()
    data class Remove(val id: Int) : ViewOp()
    data class Command(val id: Int, val name: String, val args: Any? = null) : ViewOp()
}

/**
 * An event the platform reports for a view: tap, doubletap, longpress,
 * tapdown/up/cancel, dragstart/drag/dragend, swipe, pointer*, scale*,
 * keydown/up, focus/blur, change, input, submit, scroll, dismissed,
 * dragupdate, drop, load, error, play, pause, ended, timeupdate, link …
 */
data class ViewEvent(
    val id: Int,
    val type: String,
    val x: Double? = null,
    val y: Double? = null,
    val localX: Double? = null,
    val localY: Double? = null,
    val dx: Double? = null,
    val dy: Double? = null,
    val vx: Double? = null,
    val vy: Double? = null,
    val scale: Double? = null,
    val rotation: Double? = null,
    val buttons: Int? = null,
    val pressure: Double? = null,
    val pointerId: Int? = null,
    val key: String? = null,
    val keyCode: Int? = null,
    val altKey: Boolean? = null,
    val ctrlKey: Boolean? = null,
    val shiftKey: Boolean? = null,
    val metaKey: Boolean? = null,
    val value: Any? = null,
    val scrollX: Double? = null,
    val scrollY: Double? = null,
    val direction: String? = null,
    val data: Any? = null,
)
