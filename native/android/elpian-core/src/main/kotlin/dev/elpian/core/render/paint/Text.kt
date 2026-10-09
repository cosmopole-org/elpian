package dev.elpian.core.render.paint

import dev.elpian.core.render.Constraints
import dev.elpian.core.render.INF
import dev.elpian.core.render.RenderObject
import dev.elpian.core.render.Size
import dev.elpian.core.render.TextMetrics
import dev.elpian.core.render.TextSpanSpec
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.ViewKinds
import dev.elpian.core.render.ViewProps
import dev.elpian.core.render.applyTextTransform
import dev.elpian.core.render.constrain
import dev.elpian.core.render.mergeTextStyle
import dev.elpian.core.render.toSpec
import dev.elpian.core.util.jsString
import kotlin.math.ceil
import kotlin.math.min

/**
 * RenderText — a paragraph of styled spans (Flutter `Text` / `RichText` /
 * `SelectableText`), render/paint/text.ts. Layout asks the platform to
 * measure the paragraph with the incoming max width (the platform renders the
 * exact same spec, so the measured and painted text always agree).
 */
data class SpanInput(val text: String, val style: TextStyle? = null, val link: String? = null) {
    companion object {
        /** A span given as a [SpanInput] or as a `{text, style, link}` map. */
        fun from(v: Any?): SpanInput = when (v) {
            is SpanInput -> v
            is Map<*, *> -> SpanInput(
                v["text"]?.let { it as? String ?: jsString(it) } ?: "",
                v["style"] as? TextStyle,
                v["link"]?.let { it as? String ?: jsString(it) },
            )
            is String -> SpanInput(v)
            else -> SpanInput("")
        }
    }
}

/** The merged DefaultTextStyle chain. */
data class InheritedTextStyle(
    val style: TextStyle,
    val align: String? = null,
    val maxLines: Int? = null,
    val overflow: String? = null,
    val softWrap: Boolean? = null,
)

private fun intOrNull(v: Any?): Int? = (v as? Number)?.toInt()

/**
 * props: {
 *   text?: string, spans?: SpanInput[], style?: TextStyle,
 *   align?, maxLines?, overflow?, softWrap?, selectable?, direction?,
 *   onLink?: (href) -> Unit
 * }
 */
open class RenderText : RenderObject() {
    private var metrics: TextMetrics? = null
    private var spec: TextSpec? = null

    /** The nearest DefaultTextStyle chain merged outermost-first. */
    fun inheritedStyle(): InheritedTextStyle {
        val chain = ArrayList<RenderDefaultTextStyle>()
        var node = parent
        while (node != null) {
            if (node is RenderDefaultTextStyle) chain.add(node)
            node = node.parent
        }
        var style = TextStyle()
        var align: String? = null
        var maxLines: Int? = null
        var overflow: String? = null
        var softWrap: Boolean? = null
        for (i in chain.indices.reversed()) {
            val p = chain[i].props
            style = mergeTextStyle(style, p["style"] as? TextStyle)
            (p["textAlign"] as? String)?.takeIf { it.isNotEmpty() }?.let { align = it }
            if (p.containsKey("maxLines")) maxLines = intOrNull(p["maxLines"])
            (p["overflow"] as? String)?.takeIf { it.isNotEmpty() }?.let { overflow = it }
            if (p.containsKey("softWrap")) softWrap = p["softWrap"] as? Boolean
        }
        return InheritedTextStyle(style, align, maxLines, overflow, softWrap)
    }

    fun buildSpec(): TextSpec {
        val inherited = inheritedStyle()
        val base = mergeTextStyle(inherited.style, props["style"] as? TextStyle)
        val scale = owner?.textScale ?: 1.0
        val inputs: List<SpanInput> = (props["spans"] as? List<*>)?.map { SpanInput.from(it) }
            ?: listOf(SpanInput(props["text"]?.let { it as? String ?: jsString(it) } ?: ""))
        val spans = inputs.map { s ->
            val style = mergeTextStyle(base, s.style)
            TextSpanSpec(
                text = applyTextTransform(s.text, style.textTransform),
                style = style.toSpec(scale),
                link = s.link?.takeIf { it.isNotEmpty() },
            )
        }
        val softWrap = props["softWrap"] as? Boolean ?: inherited.softWrap ?: true
        return TextSpec(
            spans = spans,
            align = props["align"] as? String ?: inherited.align ?: "start",
            maxLines = intOrNull(props["maxLines"]) ?: inherited.maxLines,
            overflow = props["overflow"] as? String ?: inherited.overflow ?: "clip",
            softWrap = softWrap,
            selectable = isTruthy(props["selectable"]),
            direction = if (props["direction"] == "rtl") "rtl" else "ltr",
        )
    }

    private fun measure(spec: TextSpec, maxWidth: Double): TextMetrics {
        val o = owner
        if (o == null) {
            val size = spec.spans.fold(0.0) { s, sp -> s + sp.text.length * sp.style.fontSize * 0.5 }
            return TextMetrics(min(size, maxWidth), 20.0, 15.0, 1, false)
        }
        return o.measureText(spec, maxWidth)
    }

    override fun performLayout(c: Constraints) {
        val spec = buildSpec()
        this.spec = spec
        val maxWidth = if (spec.softWrap || spec.overflow == "ellipsis" || spec.overflow == "fade") c.maxWidth else INF
        val metrics = measure(spec, maxWidth)
        this.metrics = metrics
        // Fractional widths are rounded up so the platform never wraps a line
        // the measurement placed on one line.
        size = constrain(c, Size(ceil(metrics.width - 0.001), ceil(metrics.height - 0.001)))
    }

    override fun baseline(): Double? = metrics?.baseline

    override fun computeMinIntrinsicWidth(height: Double): Double {
        val spec = buildSpec()
        if (!spec.softWrap) return ceil(measure(spec, INF).width)
        return ceil(measure(spec, 0.0).width)
    }
    override fun computeMaxIntrinsicWidth(height: Double): Double = ceil(measure(buildSpec(), INF).width)
    override fun computeMinIntrinsicHeight(width: Double): Double = ceil(measure(buildSpec(), width).height)
    override fun computeMaxIntrinsicHeight(width: Double): Double = computeMinIntrinsicHeight(width)

    override fun viewKind(): String? = ViewKinds.TEXT

    override fun viewProps(): ViewProps {
        val spec = this.spec ?: buildSpec()
        val hasLinks = spec.spans.any { !it.link.isNullOrEmpty() }
        return linkedMapOf("text" to spec, "gestures" to (if (hasLinks) listOf("tap") else null))
    }

    override fun handleViewEvent(event: ViewEvent) {
        val v = event.value
        if (event.type == "link" && v is String) callHandler(props["onLink"], v)
    }

    val lastMetrics: TextMetrics? get() = metrics
}
