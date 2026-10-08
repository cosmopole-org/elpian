package dev.elpian.core.widgets

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.engine.ElpianEngine
import dev.elpian.core.engine.ElpianServices
import dev.elpian.core.host.HostHandler
import dev.elpian.core.host.HostHandlerOptions
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.FetchResponse
import dev.elpian.core.platform.Platform
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.Viewport
import dev.elpian.core.render.Constraints
import dev.elpian.core.render.INF
import dev.elpian.core.render.RenderOwner
import dev.elpian.core.render.TextMetrics
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.ViewOp
import dev.elpian.core.render.W
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.paint.SpanInput
import dev.elpian.core.render.reconcileRoot
import dev.elpian.core.render.registeredRenderObjectTypes
import dev.elpian.core.render.tight
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlin.math.ceil
import kotlin.math.min
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

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

class LoweringTest {
    @Suppress("UNCHECKED_CAST")
    private fun json(text: String): JsonMap = Json.parse(text) as JsonMap

    private fun walk(w: W, out: MutableList<W> = ArrayList()): List<W> {
        out.add(w)
        for (c in w.c ?: emptyList()) walk(c, out)
        return out
    }

    private fun types(w: W): List<String> = walk(w).map { it.t }

    @Test
    fun htmlDivWithInlineCssLowersToBoxModel() {
        val engine = ElpianEngine()
        val tree = engine.renderFromJson(
            json(
                """
                {"type": "div", "props": {"style": {"padding": "8px", "backgroundColor": "#ff0000", "borderRadius": "4px"}},
                 "children": [
                   {"type": "p", "props": {"text": "Hello "}, "children": [{"type": "strong", "props": {"text": "world"}}]},
                   {"type": "span", "props": {"text": "tail", "style": {"color": "#00ff00"}}}
                 ]}
                """,
            ),
        )
        // Container order: padding inside decoration.
        assertEquals("decorated", tree.t)
        val decoration = tree.p["decoration"] as Decoration
        assertEquals(0xffff0000.toInt(), decoration.color)
        assertNotNull(decoration.radius)
        val pad = tree.c!!.single()
        assertEquals("padding", pad.t)
        assertEquals(EdgeInsets(8.0, 8.0, 8.0, 8.0), pad.p["padding"])
        // Block flow: a column stretching its children.
        val flex = pad.c!!.single()
        assertEquals("flex", flex.t)
        assertEquals("column", flex.p["direction"])
        assertEquals(2, flex.c!!.size)
        // The paragraph becomes one rich text of spans, wrapped in its 8px vertical margin.
        val texts = walk(flex).filter { it.t == "text" }
        val rich = texts.first { it.p["spans"] != null }
        @Suppress("UNCHECKED_CAST")
        val spans = rich.p["spans"] as List<SpanInput>
        assertEquals(listOf("Hello ", "world"), spans.map { it.text })
        assertEquals(700, spans[1].style?.fontWeight)
        assertTrue(walk(flex.c!![0]).any { it.t == "padding" && it.p["padding"] == EdgeInsets(8.0, 0.0, 8.0, 0.0) })
        // The span keeps its colour.
        val tail = texts.first { it.p["text"] == "tail" }
        assertEquals(0xff00ff00.toInt(), (tail.p["style"] as TextStyle).color)
    }

    @Test
    fun flutterColumnRowContainerText() {
        val engine = ElpianEngine()
        val tree = engine.renderFromJson(
            json(
                """
                {"type": "Column", "style": {"justifyContent": "center", "alignItems": "stretch", "gap": 4},
                 "children": [
                   {"type": "Row", "style": {"justifyContent": "space-between"}, "children": [
                     {"type": "Text", "props": {"text": "a", "maxLines": 2}},
                     {"type": "Container", "props": {"width": 20, "height": 10, "padding": 2, "decoration": {"backgroundColor": "blue"}}}
                   ]},
                   {"type": "Text", "props": {"text": "b"}, "style": {"fontSize": 20}}
                 ]}
                """,
            ),
        )
        assertEquals("flex", tree.t)
        assertEquals("column", tree.p["direction"])
        assertEquals("center", tree.p["mainAxisAlignment"])
        assertEquals("stretch", tree.p["crossAxisAlignment"])
        assertEquals(4.0, tree.p["gap"])
        val row = tree.c!![0]
        assertEquals("row", row.p["direction"])
        assertEquals("spaceBetween", row.p["mainAxisAlignment"])
        val a = row.c!![0]
        assertEquals("text", a.t)
        assertEquals("a", a.p["text"])
        assertEquals(2.0, a.p["maxLines"])
        // Container(width, height, padding, decoration) without a child: constrained → decorated → padding.
        val box = row.c!![1]
        assertEquals(listOf("constrained", "decorated", "padding"), types(box))
        assertEquals(20.0, box.p["width"])
        assertEquals(10.0, box.p["height"])
        val b = tree.c!![1]
        assertEquals(20.0, (b.p["style"] as TextStyle).fontSize)
    }

    @Test
    fun stylesheetEventsKeysAndDisplayNone() {
        val engine = ElpianEngine()
        engine.loadStylesheet(".card { padding: 12px; } .gone { display: none; }")
        val tree = engine.renderFromJson(
            json(
                """
                {"type": "section", "key": "root", "children": [
                  {"type": "div", "props": {"className": "card"}, "events": {"click": "onCard"}, "children": [{"type": "Text", "props": {"text": "x"}}]},
                  {"type": "div", "props": {"className": "gone"}}
                ]}
                """,
            ),
        )
        assertEquals("root", tree.k)
        val all = walk(tree)
        val gesture = all.first { it.t == "gesture" }
        assertEquals(listOf("tap"), gesture.p["gestures"])
        assertEquals("pointer", gesture.p["cursor"])
        assertTrue(gesture.k!!.startsWith("ev:"))
        assertTrue(all.any { it.t == "padding" && it.p["padding"] == EdgeInsets(12.0, 12.0, 12.0, 12.0) })
        assertTrue(all.any { it.t == "constrained" && it.p["width"] == 0.0 && it.p["height"] == 0.0 && it.c == null })

        // A tap reaches the guest handler through the dispatcher.
        val received = ArrayList<String>()
        engine.services.events.onGlobalEvent { received.add("${it.type}@${it.target}") }
        @Suppress("UNCHECKED_CAST")
        (gesture.p["onEvent"] as (ViewEvent) -> Unit)(ViewEvent(1, "tap", x = 1.0, y = 2.0))
        assertEquals(1, received.size)
        assertTrue(received[0].startsWith("click@"))
    }

    @Test
    fun everyEmittedTypeIsRegisteredAndReconciles() {
        val engine = ElpianEngine()
        val tree = engine.renderFromJson(
            json(
                """
                {"type": "div", "children": [
                  {"type": "h1", "props": {"text": "Title"}},
                  {"type": "ul", "children": [{"type": "li", "props": {"text": "one"}}, {"type": "li", "props": {"text": "two"}}]},
                  {"type": "ol", "children": [{"type": "li", "props": {"text": "first"}}]},
                  {"type": "table", "children": [{"type": "tr", "children": [{"type": "th", "props": {"text": "h"}}, {"type": "td", "props": {"text": "d"}}]}]},
                  {"type": "form", "children": [
                    {"type": "input", "props": {"name": "q", "placeholder": "Search"}},
                    {"type": "input", "props": {"type": "checkbox", "name": "c"}},
                    {"type": "input", "props": {"type": "range", "name": "r"}},
                    {"type": "select", "children": [{"type": "option", "props": {"value": "a", "text": "A"}}]},
                    {"type": "textarea"},
                    {"type": "button", "props": {"text": "Go"}}
                  ]},
                  {"type": "details", "children": [{"type": "summary", "props": {"text": "More"}}, {"type": "p", "props": {"text": "hidden"}}]},
                  {"type": "img", "props": {"src": "a.png"}},
                  {"type": "progress", "props": {"value": 0.5}},
                  {"type": "pre", "props": {"text": "code"}},
                  {"type": "blockquote", "props": {"text": "quote"}},
                  {"type": "hr"},
                  {"type": "div", "props": {"style": {"display": "grid", "gridTemplateColumns": "1fr 1fr"}}, "children": [{"type": "span", "props": {"text": "g1"}}, {"type": "span", "props": {"text": "g2"}}]},
                  {"type": "div", "props": {"style": {"position": "relative"}}, "children": [{"type": "span", "props": {"text": "abs", "style": {"position": "absolute", "top": "0px"}}}]},
                  {"type": "div", "props": {"style": {"display": "flex", "opacity": 0.5, "transform": "rotate(10deg)", "overflow": "hidden"}}, "children": [{"type": "span", "props": {"text": "f"}}]},
                  {"type": "Card", "children": [{"type": "Text", "props": {"text": "card"}}]},
                  {"type": "Scaffold", "children": [{"type": "AppBar", "props": {"title": "App"}}, {"type": "Center", "children": [{"type": "Icon", "props": {"icon": "home"}}]}]},
                  {"type": "Stack", "children": [{"type": "Positioned", "style": {"top": 1}, "children": [{"type": "Badge", "props": {"label": "3"}}]}]},
                  {"type": "ListView", "children": [{"type": "Chip", "props": {"label": "chip"}}, {"type": "Divider"}]},
                  {"type": "Wrap", "children": [{"type": "Switch"}, {"type": "Slider"}, {"type": "Checkbox"}, {"type": "Radio"}]},
                  {"type": "AnimatedContainer", "style": {"width": 10, "backgroundColor": "red"}},
                  {"type": "FadeTransition", "children": [{"type": "Text", "props": {"text": "fade"}}]},
                  {"type": "Shimmer"},
                  {"type": "MathExpression", "props": {"expression": "x^2 + \\alpha"}},
                  {"type": "NextjsLink", "props": {"href": "/a", "text": "link"}},
                  {"type": "NextjsForm", "props": {"fields": [{"name": "email", "type": "text"}, {"name": "ok", "type": "checkbox"}]}}
                ]}
                """,
            ),
        )
        val registered = registeredRenderObjectTypes()
        val unknown = types(tree).toSet() - registered
        assertTrue(unknown.isEmpty(), "unregistered render object types: $unknown")
        assertTrue(walk(tree).none { it.t == "decorated" && it.c?.singleOrNull()?.c?.singleOrNull()?.p?.get("text").toString().startsWith("Unknown widget") })

        val math = walk(tree).first { it.t == "text" && (it.p["text"] as? String)?.contains("α") == true }
        assertEquals("x² + α", math.p["text"])

        // The tree builds render objects and lays out.
        val owner = RenderOwner("s", FakePlatform())
        val root = reconcileRoot(null, engine.wrapAsDocument(tree, mapOf("type" to "div")), owner)
        root.layout(tight(400.0, 800.0))
        assertEquals(400.0, root.size.width)
    }

    @Test
    fun blockLayoutStacksChildren() {
        val engine = ElpianEngine()
        val tree = engine.renderFromJson(
            json(
                """
                {"type": "div", "props": {"style": {"padding": "10px"}}, "children": [
                  {"type": "div", "props": {"style": {"height": "20px", "backgroundColor": "red"}}},
                  {"type": "div", "props": {"style": {"height": "30px", "width": "50%"}}}
                ]}
                """,
            ),
        )
        val owner = RenderOwner("s", FakePlatform())
        val root = reconcileRoot(null, tree, owner)
        root.layout(Constraints(0.0, 300.0, 0.0, INF))
        assertEquals(300.0, root.size.width)
        assertEquals(70.0, root.size.height)
    }

    @Test
    fun hostHandlerRendersAndServicesCanvasContexts() {
        val services = ElpianServices("app")
        var rendered: JsonMap? = null
        val handler = HostHandler(services, HostHandlerOptions(onRender = { view, _ -> rendered = view }))
        handler.handleHostCall("render", """[{"type": "div", "children": []}]""")
        assertEquals("div", rendered?.get("type"))
        val created = handler.handleHostCall("canvas.ctx.create", """{"id": "c1", "width": 10, "height": 20}""")
        assertTrue(created.contains("c1"))
        handler.handleHostCall("canvas.ctx.addCommand", """{"id": "c1", "command": {"type": "fillRect", "params": {"x": 0, "y": 0, "width": 5, "height": 5}}}""")
        assertEquals(1, services.canvasContexts["app::c1"]!!.commands.size)

        val engine = ElpianEngine(services)
        val tree = engine.renderFromJson(json("""{"type": "CachedCanvas", "props": {"contextId": "c1"}}"""))
        assertEquals("canvas", tree.t)
        assertEquals(10.0, tree.p["width"])
        assertEquals(Alignment(0.0, 0.0), Alignment.center)
    }
}
