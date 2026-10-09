package dev.elpian.core.render

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.FetchResponse
import dev.elpian.core.platform.Platform
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.Viewport
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlin.math.ceil
import kotlin.math.min
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** A platform whose text measurement is deterministic: each character is half the font size wide, lines are 1.2 em. */
private class FakePlatform : Platform {
    override val name = "fake"
    override val dispatcher: CoroutineDispatcher = Dispatchers.Unconfined
    override fun now() = 0.0
    override fun setTimeout(ms: Double, callback: () -> Unit) = 1
    override fun clearTimeout(handle: Int) {}
    override fun requestFrame(callback: (Double) -> Unit) {}
    override fun commit(surface: String, ops: List<ViewOp>) {}
    override fun measureText(spec: TextSpec, maxWidth: Double): TextMetrics {
        val fs = spec.spans.firstOrNull()?.style?.fontSize ?: 14.0
        val chars = spec.spans.sumOf { it.text.length }
        val natural = chars * fs * 0.5
        val lines = if (maxWidth == INF || natural <= maxWidth) 1 else ceil(natural / maxWidth).toInt()
        return TextMetrics(min(natural, maxWidth), lines * fs * 1.2, fs * 0.8, lines, false)
    }
    override fun viewport(surface: String) = Viewport(400.0, 300.0, 1.0, EdgeInsets.ZERO, "en", "android", false, false, 1.0)
    override fun log(level: String, message: String) {}
    override suspend fun fetch(request: FetchRequest) = FetchResponse(404, emptyMap(), "")
    override fun fetchStream(request: FetchRequest, handlers: StreamHandlers): () -> Unit = {}
    override suspend fun loadAsset(path: String) = ByteArray(0)
}

class ReconcilerTest {
    private fun ins(t: Double, r: Double, b: Double, l: Double) = EdgeInsets(t, r, b, l)

    private fun dump(ro: RenderObject, out: MutableList<String> = ArrayList()): List<String> {
        fun n(v: Double) = if (v == Math.floor(v)) v.toLong().toString() else v.toString()
        out.add("${ro.type} ${n(ro.size.width)} ${n(ro.size.height)} ${n(ro.offset.x)} ${n(ro.offset.y)}")
        for (c in ro.children) dump(c, out)
        return out
    }

    private fun layoutTree(tree: W, c: Constraints): RenderObject {
        val owner = RenderOwner("s", FakePlatform())
        val root = reconcileRoot(null, tree, owner)
        root.layout(c)
        return root
    }

    // Expected outputs below were produced by running the same trees through
    // the TypeScript engine (native/web) (native/web/src) with the same fake measureText.

    @Test
    fun paddingAndFlexRow() {
        val root = layoutTree(
            w("padding", mapOf("padding" to ins(10.0, 10.0, 10.0, 10.0)), listOf(
                w("flex", mapOf("direction" to "row", "mainAxisAlignment" to "spaceBetween", "crossAxisAlignment" to "center"), listOf(
                    w("constrained", mapOf("width" to 50.0, "height" to 20.0)),
                    w("flexible", mapOf("flex" to 1.0), listOf(w("text", mapOf("text" to "hello world")))),
                    w("constrained", mapOf("width" to 30.0, "height" to 40.0)),
                )),
            )),
            tight(400.0, 300.0),
        )
        assertEquals(
            listOf(
                "padding 400 300 0 0",
                "flex 380 280 10 10",
                "constrained 50 20 0 130",
                "flexible 300 17 50 131.5",
                "text 300 17 0 0",
                "constrained 30 40 350 120",
            ),
            dump(root),
        )
    }

    @Test
    fun stackWithPositionedChildren() {
        val root = layoutTree(
            w("stack", mapOf("alignment" to Alignment(0.0, 0.0)), listOf(
                w("constrained", mapOf("width" to 100.0, "height" to 50.0)),
                w("positioned", mapOf("left" to 10.0, "bottom" to 5.0, "width" to 20.0), listOf(w("constrained", mapOf("height" to 10.0)))),
                w("positioned", mapOf("right" to 0.0, "top" to 0.0), listOf(w("text", mapOf("text" to "abc")))),
            )),
            Constraints(0.0, 400.0, 0.0, 300.0),
        )
        assertEquals(
            listOf(
                "stack 100 50 0 0",
                "constrained 100 50 0 0",
                "positioned 20 10 10 35",
                "constrained 20 10 0 0",
                "positioned 21 17 79 0",
                "text 21 17 0 0",
            ),
            dump(root),
        )
    }

    @Test
    fun columnWithWrappingText() {
        val root = layoutTree(
            w("flex", mapOf("direction" to "column", "crossAxisAlignment" to "stretch", "mainAxisSize" to "min"), listOf(
                w("text", mapOf("text" to "a fairly long sentence that has to wrap around")),
                w("padding", mapOf("padding" to ins(5.0, 5.0, 5.0, 5.0)), listOf(w("text", mapOf("text" to "short")))),
                w("align", mapOf("alignment" to Alignment(1.0, 1.0), "heightFactor" to 2.0), listOf(w("constrained", mapOf("width" to 10.0, "height" to 10.0)))),
            )),
            Constraints(0.0, 120.0, 0.0, 500.0),
        )
        assertEquals(
            listOf(
                "flex 120 98 0 0",
                "text 120 51 0 0",
                "padding 120 27 0 51",
                "text 110 17 5 5",
                "align 120 20 0 78",
                "constrained 10 10 110 10",
            ),
            dump(root),
        )
    }

    @Test
    fun animatedPaddingInterpolatesOnTheFrameClock() {
        val owner = RenderOwner("s", FakePlatform())
        owner.rootConstraints = tight(200.0, 100.0)
        var root = reconcileRoot(null, w("animatedPadding", mapOf("padding" to ins(0.0, 0.0, 0.0, 0.0)), listOf(w("constrained"))), owner)
        owner.root = root
        owner.flush(0.0)
        root = reconcileRoot(root, w("animatedPadding", mapOf("padding" to ins(20.0, 20.0, 20.0, 20.0), "duration" to 100.0), listOf(w("constrained"))), owner)
        owner.flush(1000.0)
        owner.flush(1050.0)
        assertEquals(listOf("animatedPadding 200 100 0 0", "constrained 180 80 10 10"), dump(root))
        owner.flush(1200.0)
        assertEquals(listOf("animatedPadding 200 100 0 0", "constrained 160 60 20 20"), dump(root))
    }

    @Test
    fun keyedChildrenKeepIdentityAcrossReorder() {
        val owner = RenderOwner("s", FakePlatform())
        fun tree(order: List<String>) = w("flex", mapOf("direction" to "column"), order.map { w("constrained", mapOf("height" to 10.0), k = it) })
        val root = reconcileRoot(null, tree(listOf("a", "b", "c")), owner)
        val (a, b, c) = root.children.toList()
        val same = reconcileRoot(root, tree(listOf("c", "a", "b")), owner)
        assertSame(root, same)
        assertSame(c, root.children[0])
        assertSame(a, root.children[1])
        assertSame(b, root.children[2])
        root.layout(Constraints(0.0, 100.0, 0.0, 100.0))
        assertEquals(listOf(0.0, 10.0, 20.0), root.children.map { it.offset.y })
        // An unkeyed type change replaces the object.
        val replaced = reconcileRoot(root, w("padding"), owner)
        assertNotSame(root, replaced)
    }

    @Test
    fun everyTypeKeyIsRegistered() {
        val expected = listOf(
            "proxy", "padding", "safeArea", "fill", "constrained", "align", "aspectRatio", "fractional", "limited", "overflowBox",
            "fitted", "fittedContent", "baseline", "rotatedBox", "intrinsicWidth", "intrinsicHeight", "offstage", "indexedStack",
            "flex", "flexible", "wrap", "stack", "positioned", "grid", "imageMap", "gridItem", "scroll", "table", "tableRow",
            "tableCell", "decorated", "opacity", "transform", "clip", "ignorePointer", "visibility", "filter", "shaderMask",
            "defaultTextStyle", "text", "image", "control", "canvas", "scene3d", "media", "web", "native", "gesture",
            "animatedPadding", "animatedAlign", "animatedOpacity", "animatedTransform", "animatedConstrained", "animatedDecorated",
            "animatedPositioned", "animatedDefaultTextStyle", "animatedSize", "animatedCrossFade", "animatedSwitcher", "switcherSlot",
            "transition", "staggered", "staggerItem", "shimmer", "animatedGradient", "keyframes", "hero",
        )
        assertTrue(registeredRenderObjectTypes().containsAll(expected))
        val owner = RenderOwner("s", FakePlatform())
        for (t in expected) assertEquals(t, createRenderObject(w(t), owner, null).type)
        assertFailsWith<IllegalArgumentException> { createRenderObject(w("nope"), owner, null) }
    }

    @Test
    fun propsEqualIgnoresClosures() {
        assertTrue(propsEqual(mapOf("a" to 1.0, "f" to { -> }), mapOf("a" to 1.0, "f" to { x: Any? -> x })))
        assertTrue(!propsEqual(mapOf("a" to 1.0), mapOf("a" to 2.0)))
    }
}
