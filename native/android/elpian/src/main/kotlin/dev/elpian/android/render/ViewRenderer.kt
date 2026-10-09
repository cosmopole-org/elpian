package dev.elpian.android.render

import android.graphics.Bitmap
import android.util.Log
import android.view.View
import dev.elpian.core.css.Border
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.BoxShadow
import dev.elpian.core.css.Filter
import dev.elpian.core.css.Gradient
import dev.elpian.core.css.Matrix4
import dev.elpian.core.render.ROOT_VIEW_ID
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.ViewKinds
import dev.elpian.core.render.ViewOp
import dev.elpian.core.render.paint.DecorationImage
import dev.elpian.core.render.paint.Outline
import kotlin.math.roundToInt

/** What the renderer needs from its platform. */
interface RendererHooks {
    /** Report an event for a view (the session dispatches it to the core). */
    fun emit(event: ViewEvent)
    /** An image's natural size became known (0×0 = failed). */
    fun imageLoaded(src: String, width: Int, height: Int)
    /** Load a bitmap (the platform's cache). */
    fun loadImage(src: String, callback: (Bitmap?) -> Unit)
    /** The Godot surface provider for `scene3d` views, when an engine is attached. */
    fun godotSurfaces(): GodotSurfaceProvider? = null
}

/**
 * Applies the core's view operations to a tree of Android views under an
 * [ElpianSurfaceView] (the counterpart of the web host's DomRenderer).
 *
 * Every view is an [ElpianView] absolutely positioned at the frame the core
 * laid out (logical px × density). A view paints its decoration itself so its
 * frame stays the border box Flutter lays children out in, and clipping
 * applies to its content without clipping its own shadow — Flutter's
 * Container + ClipRRect. Leaf kinds map onto native content views:
 * paragraphs, images, controls, canvases, media, web pages, the Godot surface
 * and host-registered native components.
 */
class ViewRenderer(val root: ElpianSurfaceView, private val hooks: RendererHooks) : ViewHost {
    private class Rec(val id: Int, val kind: String, val view: ElpianView?, val props: MutableMap<String, Any?>, val children: MutableList<Int>, var parent: Int) {
        var native: NativeComponentInstance? = null
    }

    private val views = HashMap<Int, Rec>()
    override var density: Float = root.resources.displayMetrics.density
        private set
    override val surface: ElpianSurfaceView get() = root
    override val images: ImageSource = ImageSource { src, cb -> hooks.loadImage(src, cb) }

    init {
        views[ROOT_VIEW_ID] = Rec(ROOT_VIEW_ID, ViewKinds.VIEW, null, HashMap(), ArrayList(), -1)
    }

    override fun emit(event: ViewEvent) = hooks.emit(event)

    /** The live view for [id] (tests and host integrations). */
    fun viewFor(id: Int): ElpianView? = views[id]?.view

    /** The `scene3d` host showing Godot surface [surfaceId] (for `AndroidGodotBinding`'s GodotSurfaceHost). */
    fun scene3dContainer(surfaceId: Int): android.view.ViewGroup? =
        views.values.firstNotNullOfOrNull { (it.view?.leaf as? Scene3dLeaf)?.takeIf { l -> l.surfaceId == surfaceId } }

    fun apply(ops: List<ViewOp>, density: Float = this.density) {
        if (density != this.density) {
            this.density = density
            repaintAll()
        }
        for (op in ops) {
            try {
                when (op) {
                    is ViewOp.Create -> create(op.id, op.kind, op.parent, op.index, op.props)
                    is ViewOp.Update -> update(op.id, op.props)
                    is ViewOp.Move -> move(op.id, op.parent, op.index)
                    is ViewOp.Remove -> remove(op.id)
                    is ViewOp.Command -> command(op.id, op.name, op.args)
                }
            } catch (e: Throwable) {
                Log.e("Elpian", "renderer: op failed $op", e)
            }
        }
    }

    // ---------------------------------------------------------------------
    // Tree
    // ---------------------------------------------------------------------

    private fun hostOf(rec: Rec): ElpianGroup = rec.view?.childHost ?: root

    private fun create(id: Int, kind: String, parent: Int, index: Int, props: Map<String, Any?>) {
        views[id]?.let { remove(id) }
        val view = ElpianView(root.context, id, kind, this)
        val rec = Rec(id, kind, view, HashMap(), ArrayList(), parent)
        views[id] = rec
        buildLeaf(rec)
        insert(rec, parent, index)
        update(id, props)
    }

    private fun insert(rec: Rec, parent: Int, index: Int) {
        val p = views[parent] ?: views[ROOT_VIEW_ID]!!
        rec.parent = p.id
        p.children.remove(rec.id)
        val i = index.coerceIn(0, p.children.size)
        p.children.add(i, rec.id)
        val host = hostOf(p)
        val v = rec.view!!
        (v.parent as? android.view.ViewGroup)?.removeView(v)
        var at = -1
        for (j in i + 1 until p.children.size) {
            val next = views[p.children[j]]?.view ?: continue
            if (next.parent === host) {
                at = host.indexOfChild(next)
                break
            }
        }
        if (at >= 0) host.addView(v, at) else host.addView(v)
        if (v.zIndex != 0.0) host.invalidateOrder()
        if (v.frame.any { it != 0.0 }) v.setFrame(v.frame)
    }

    private fun move(id: Int, parent: Int, index: Int) {
        val rec = views[id] ?: return
        val newParent = views[parent] ?: views[ROOT_VIEW_ID]!!
        // Already in place: keep the view attached (focus, playback, scroll survive).
        if (rec.parent == newParent.id && newParent.children.indexOf(id) == index) return
        views[rec.parent]?.children?.remove(id)
        insert(rec, parent, index)
    }

    private fun remove(id: Int) {
        val rec = views[id] ?: return
        views[rec.parent]?.children?.remove(id)
        disposeTree(rec)
        val v = rec.view ?: return
        (v.parent as? android.view.ViewGroup)?.removeView(v)
    }

    private fun disposeTree(rec: Rec) {
        for (c in rec.children.toList()) views[c]?.let { disposeTree(it) }
        rec.view?.gestures?.dispose()
        when (val leaf = rec.view?.leaf) {
            is MediaLeaf -> leaf.release()
            is WebLeaf -> leaf.release()
            is Scene3dLeaf -> leaf.release()
            is CanvasLeafView -> leaf.release()
        }
        rec.native?.dispose()
        rec.native = null
        views.remove(rec.id)
    }

    /** Remove every view (unmount). */
    fun clear() {
        val r = views[ROOT_VIEW_ID]!!
        for (c in r.children.toList()) remove(c)
        root.removeAllViews()
    }

    /** Re-run every canvas (density change). */
    fun repaintAll() {
        for (rec in views.values) (rec.view?.leaf as? CanvasLeafView)?.repaint()
        TextEngine.clearCache()
    }

    // ---------------------------------------------------------------------
    // Leaves
    // ---------------------------------------------------------------------

    private fun buildLeaf(rec: Rec) {
        val v = rec.view ?: return
        val ctx = root.context
        val leaf: View? = when (rec.kind) {
            ViewKinds.TEXT -> TextLeafView(ctx, v)
            ViewKinds.IMAGE -> ImageLeafView(ctx, v) { src, bmp ->
                if (bmp != null) {
                    hooks.imageLoaded(src, bmp.width, bmp.height)
                    emit(ViewEvent(id = rec.id, type = "load", value = mapOf("width" to bmp.width.toDouble(), "height" to bmp.height.toDouble())))
                } else {
                    hooks.imageLoaded(src, 0, 0)
                    emit(ViewEvent(id = rec.id, type = "error"))
                }
            }
            ViewKinds.SCROLL -> ScrollContainer(ctx, v).also { v.childHost = it }
            ViewKinds.TEXT_INPUT -> TextInputLeaf(ctx, v)
            ViewKinds.CHECKBOX -> CheckboxView(ctx, v)
            ViewKinds.RADIO -> RadioView(ctx, v)
            ViewKinds.SWITCH -> SwitchView(ctx, v)
            ViewKinds.SLIDER -> SliderView(ctx, v)
            ViewKinds.SELECT -> SelectLeaf(ctx, v)
            ViewKinds.PROGRESS -> ProgressView(ctx, v)
            ViewKinds.CANVAS -> CanvasLeafView(ctx, v)
            ViewKinds.SCENE3D -> Scene3dLeaf(ctx, v) { hooks.godotSurfaces() }
            ViewKinds.VIDEO -> MediaLeaf(ctx, v, true)
            ViewKinds.AUDIO -> MediaLeaf(ctx, v, false)
            ViewKinds.WEB -> WebLeaf(ctx, v)
            else -> null
        }
        if (leaf != null) {
            v.leaf = leaf
            v.addView(leaf, 0)
        }
    }

    // ---------------------------------------------------------------------
    // Props
    // ---------------------------------------------------------------------

    private fun update(id: Int, patch: Map<String, Any?>) {
        val rec = views[id] ?: return
        val v = rec.view ?: return
        for ((k, value) in patch) if (value == null) rec.props.remove(k) else rec.props[k] = value
        val p = rec.props
        fun has(k: String) = patch.containsKey(k)
        val frameChanged = has("frame")

        if (frameChanged) P.doubles(p["frame"])?.takeIf { it.size >= 4 }?.let { v.setFrame(it) }
        if (has("opacity")) v.alpha = (P.num(p["opacity"]) ?: 1.0).coerceIn(0.0, 1.0).toFloat()
        if (has("transform") || has("transformOrigin")) v.setTransform(p["transform"] as? Matrix4 ?: P.doubles(p["transform"]), P.doubles(p["transformOrigin"]))
        if (has("hidden")) v.visibility = if (p["hidden"] == true) View.INVISIBLE else View.VISIBLE
        if (has("pointerEvents")) v.pointerEventsNone = p["pointerEvents"] == "none"
        if (has("cursor")) Paints.applyCursor(v, P.str(p["cursor"]))
        if (has("zIndex")) {
            v.zIndex = P.num(p["zIndex"]) ?: 0.0
            (v.parent as? ElpianGroup)?.invalidateOrder()
        }
        if (has("filter") || has("blendMode")) v.setEffects(p["filter"] as? Filter, P.str(p["blendMode"]))
        if (has("shaderMask")) {
            v.shaderMask = p["shaderMask"] as? Gradient
            v.invalidate()
        }
        if (has("backdropFilter")) v.setBackdrop(p["backdropFilter"] as? Filter)
        if (has("semanticsLabel") || has("tooltip")) v.contentDescription = P.str(p["semanticsLabel"]) ?: P.str(p["tooltip"])
        if (has("role")) v.role = P.str(p["role"])

        val decoKeys = listOf("background", "gradients", "backgroundImage", "border", "radius", "oval", "shadows", "outline")
        if (decoKeys.any { has(it) }) applyDecoration(rec)
        if (has("clip") || has("radius") || has("oval")) {
            v.clip = p["clip"] == true
            v.radius = p["radius"] as? BorderRadius
            v.oval = p["oval"] == true
            v.updateRippleMask()
            v.invalidate()
        }
        if (listOf("gestures", "ripple", "tooltip", "dragData", "dismissDirection", "focusable").any { has(it) }) applyGestures(rec)
        updateHitOpaque(rec)
        applyLeaf(rec, patch, frameChanged)
    }

    @Suppress("UNCHECKED_CAST")
    private fun applyDecoration(rec: Rec) {
        val v = rec.view ?: return
        val p = rec.props
        val needs = p["background"] != null || !(p["gradients"] as? List<*>).isNullOrEmpty() || p["backgroundImage"] != null || p["border"] != null || !(p["shadows"] as? List<*>).isNullOrEmpty() || p["outline"] != null
        if (!needs) {
            v.decoration = null
            v.invalidate()
            return
        }
        val deco = v.decoration ?: DecorationPainter(v, images).also { v.decoration = it }
        deco.background = P.color(p["background"])
        deco.gradients = (p["gradients"] as? List<*>)?.filterIsInstance<Gradient>()
        deco.image = p["backgroundImage"] as? DecorationImage
        deco.border = p["border"] as? Border
        deco.radius = p["radius"] as? BorderRadius
        deco.oval = p["oval"] == true
        deco.shadows = (p["shadows"] as? List<*>)?.filterIsInstance<BoxShadow>()
        deco.outline = p["outline"] as? Outline
        deco.clearCaches()
        v.invalidate()
    }

    /** Opaque to hits (HitTestBehavior.opaque / a painted box), so siblings below do not get the touch. */
    private fun updateHitOpaque(rec: Rec) {
        val v = rec.view ?: return
        val p = rec.props
        v.hitOpaque = !(p["gestures"] as? List<*>).isNullOrEmpty() || p["background"] != null || !(p["gradients"] as? List<*>).isNullOrEmpty() || p["backgroundImage"] != null || p["ripple"] != null
    }

    private fun applyGestures(rec: Rec) {
        val v = rec.view ?: return
        val p = rec.props
        val kinds = P.strings(p["gestures"])
        val ripple = P.color(p["ripple"])
        val tooltip = P.str(p["tooltip"])
        val wants = kinds.isNotEmpty() || ripple != null || tooltip != null
        if (!wants) {
            v.gestures?.dispose()
            v.gestures = null
            v.rippleColor = null
        } else {
            val g = v.gestures ?: GestureRecognizer(v).also { v.gestures = it }
            g.dismissDirection = P.str(p["dismissDirection"]) ?: "horizontal"
            g.dragData = p["dragData"]
            g.tooltip = tooltip
            g.ripple = ripple
            g.configure(kinds)
            v.rippleColor = ripple
        }
        if (p["focusable"] == true) {
            v.isFocusable = true
            v.isFocusableInTouchMode = true
        }
    }

    private fun applyLeaf(rec: Rec, patch: Map<String, Any?>, frameChanged: Boolean) {
        val v = rec.view ?: return
        val p = rec.props
        fun has(k: String) = patch.containsKey(k)
        val colors = P.map(p["colors"]) ?: emptyMap()
        when (val leaf = v.leaf) {
            is TextLeafView -> if (has("text")) leaf.setSpec(p["text"] as? TextSpec)
            is ImageLeafView -> {
                if (has("fit")) leaf.fit = P.fit(p["fit"]) ?: "contain"
                if (has("alignment")) leaf.alignment = P.alignment(p["alignment"]) ?: dev.elpian.core.css.Alignment.center
                if (has("tint")) leaf.tint = P.color(p["tint"])
                if (has("alt")) leaf.contentDescription = P.str(p["alt"])
                if (has("src")) leaf.setSrc(P.str(p["src"]))
            }
            is ScrollContainer -> {
                if (has("contentSize")) P.doubles(p["contentSize"])?.let { cs ->
                    leaf.setContentSize((cs.getOrElse(0) { 0.0 } * density).roundToInt(), (cs.getOrElse(1) { 0.0 } * density).roundToInt())
                }
                if (has("scrollAxis")) leaf.axis = P.str(p["scrollAxis"]) ?: "vertical"
                if (has("scrollEnabled")) leaf.scrollEnabled = p["scrollEnabled"] != false
                if (has("showScrollbar")) leaf.showScrollbar = p["showScrollbar"] != false
                if (has("scrollTo")) P.doubles(patch["scrollTo"])?.takeIf { it.size >= 2 }?.let { leaf.scrollToLogical(it[0], it[1], false) }
            }
            is TextInputLeaf -> leaf.apply(p, patch)
            is CheckboxView -> {
                if (has("checked")) leaf.checked = p["checked"] == true
                if (has("enabled")) leaf.enabledState = p["enabled"] != false
                if (has("colors")) leaf.colors = colors
            }
            is RadioView -> {
                if (has("checked")) leaf.checked = p["checked"] == true
                if (has("value")) leaf.value = p["value"]
                if (has("enabled")) leaf.enabledState = p["enabled"] != false
                if (has("colors")) leaf.colors = colors
            }
            is SwitchView -> {
                if (has("checked")) leaf.checked = p["checked"] == true
                if (has("enabled")) leaf.enabledState = p["enabled"] != false
                if (has("colors")) leaf.colors = colors
            }
            is SliderView -> {
                if (has("min")) leaf.min = P.num(p["min"]) ?: 0.0
                if (has("max")) leaf.max = P.num(p["max"]) ?: 1.0
                if (has("step")) leaf.step = P.num(p["step"])?.takeIf { it > 0 }
                if (has("value")) leaf.value = P.num(p["value"]) ?: 0.0
                if (has("enabled")) leaf.enabledState = p["enabled"] != false
                if (has("colors")) leaf.colors = colors
                leaf.invalidate()
            }
            is SelectLeaf -> leaf.apply(p, patch)
            is ProgressView -> {
                leaf.setVariant(P.str(p["variant"]) == "circular")
                leaf.strokeWidth = P.num(p["strokeWidth"])
                if (has("colors")) leaf.colors = colors
                leaf.value = (p["value"] as? Number)?.toDouble()
                v.contentDescription = leaf.value?.let { "${(it * 100).roundToInt()}%" }
            }
            is CanvasLeafView -> {
                if (has("background")) leaf.backgroundColorValue = P.color(p["background"])
                val cmds = patch["commands"] as? List<*>
                if (cmds != null) leaf.replace(cmds)
                else if (frameChanged && leaf.commands != null) leaf.repaint()
                (patch["appendCommands"] as? List<*>)?.let { leaf.append(it) }
            }
            is Scene3dLeaf -> {
                if (has("surfaceId")) leaf.setSurface(P.int(p["surfaceId"]))
                if (has("clickable")) Paints.applyCursor(v, if (p["clickable"] == true) "pointer" else P.str(p["cursor"]))
            }
            is MediaLeaf -> {
                if (has("autoplay")) leaf.autoplay = p["autoplay"] == true
                if (has("loop")) leaf.loop = p["loop"] == true
                if (has("muted")) leaf.muted = p["muted"] == true
                if (has("controls")) leaf.controls = p["controls"] != false
                if (has("fit")) leaf.fit = P.fit(p["fit"]) ?: "contain"
                if (has("poster")) leaf.setPoster(P.str(p["poster"]))
                @Suppress("UNCHECKED_CAST")
                if (has("tracks")) leaf.setTracks((P.list(p["tracks"]) ?: emptyList()).mapNotNull { it as? Map<String, Any?> })
                if (has("src")) leaf.setSrc(P.str(p["src"]))
            }
            is WebLeaf -> leaf.apply(p, patch)
            else -> if (rec.kind == ViewKinds.NATIVE) applyNative(rec, patch)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun applyNative(rec: Rec, patch: Map<String, Any?>) {
        val v = rec.view ?: return
        val p = rec.props
        val name = P.str(p["component"])
        val props = (p["componentProps"] as? Map<String, Any?>) ?: emptyMap()
        if (patch.containsKey("component") && !name.isNullOrEmpty()) {
            rec.native?.let {
                it.dispose()
                v.removeView(it.view)
            }
            rec.native = null
            v.leaf = null
            val factory = NativeComponents.factory(name)
            if (factory == null) {
                Log.w("Elpian", "no native component registered as \"$name\"")
                return
            }
            val inst = factory.create(root.context, props) { type, value -> emit(ViewEvent(id = rec.id, type = type, value = value)) }
            (inst.view.parent as? android.view.ViewGroup)?.removeView(inst.view)
            v.addView(inst.view, 0)
            v.leaf = inst.view
            rec.native = inst
        } else if (patch.containsKey("componentProps")) {
            rec.native?.update(props)
        }
    }

    // ---------------------------------------------------------------------
    // Commands
    // ---------------------------------------------------------------------

    private fun command(id: Int, name: String, args: Any?) {
        val rec = views[id] ?: return
        val v = rec.view ?: return
        val leaf = v.leaf
        when (name) {
            "focus" -> when (leaf) {
                is TextInputLeaf -> leaf.focusAndShowKeyboard()
                is SelectLeaf -> leaf.open()
                null -> { v.isFocusable = true; v.isFocusableInTouchMode = true; v.requestFocus() }
                else -> leaf.requestFocus()
            }
            "blur" -> when (leaf) {
                is TextInputLeaf -> leaf.blurAndHideKeyboard()
                else -> v.clearFocus()
            }
            "play" -> (leaf as? MediaLeaf)?.play()
            "pause" -> (leaf as? MediaLeaf)?.pause()
            "seek" -> P.num(args)?.let { (leaf as? MediaLeaf)?.seek(it) }
            "scrollTo" -> P.doubles(args)?.takeIf { it.size >= 2 }?.let { (leaf as? ScrollContainer)?.scrollToLogical(it[0], it[1], true) }
            "jumpTo" -> P.doubles(args)?.takeIf { it.size >= 2 }?.let { (leaf as? ScrollContainer)?.scrollToLogical(it[0], it[1], false) }
            "selectAll" -> (leaf as? TextInputLeaf)?.input?.selectAll()
            "open" -> (leaf as? SelectLeaf)?.open()
            "draw", "appendCommands" -> (args as? List<*>)?.let { (leaf as? CanvasLeafView)?.append(it) }
            "commands" -> (args as? List<*>)?.let { (leaf as? CanvasLeafView)?.replace(it) }
            "clear" -> (leaf as? CanvasLeafView)?.replace(emptyList<Any?>())
            "repaint" -> (leaf as? CanvasLeafView)?.repaint()
        }
    }
}
