package dev.elpian.core.render

import dev.elpian.core.render.layout.RenderAlign
import dev.elpian.core.render.layout.RenderAspectRatio
import dev.elpian.core.render.layout.RenderBaseline
import dev.elpian.core.render.layout.RenderConstrainedBox
import dev.elpian.core.render.layout.RenderFillAxis
import dev.elpian.core.render.layout.RenderFittedBox
import dev.elpian.core.render.layout.RenderFittedContent
import dev.elpian.core.render.layout.RenderFlex
import dev.elpian.core.render.layout.RenderFlexible
import dev.elpian.core.render.layout.RenderFractional
import dev.elpian.core.render.layout.RenderGrid
import dev.elpian.core.render.layout.RenderGridItem
import dev.elpian.core.render.layout.RenderImageMap
import dev.elpian.core.render.layout.RenderIndexedStack
import dev.elpian.core.render.layout.RenderIntrinsicHeight
import dev.elpian.core.render.layout.RenderIntrinsicWidth
import dev.elpian.core.render.layout.RenderLimitedBox
import dev.elpian.core.render.layout.RenderOffstage
import dev.elpian.core.render.layout.RenderOverflowBox
import dev.elpian.core.render.layout.RenderPadding
import dev.elpian.core.render.layout.RenderPositioned
import dev.elpian.core.render.layout.RenderRotatedBox
import dev.elpian.core.render.layout.RenderSafeArea
import dev.elpian.core.render.layout.RenderScroll
import dev.elpian.core.render.layout.RenderStack
import dev.elpian.core.render.layout.RenderTable
import dev.elpian.core.render.layout.RenderTableCell
import dev.elpian.core.render.layout.RenderTableRow
import dev.elpian.core.render.layout.RenderWrap
import dev.elpian.core.render.paint.RenderCanvas
import dev.elpian.core.render.paint.RenderClip
import dev.elpian.core.render.paint.RenderControl
import dev.elpian.core.render.paint.RenderDecoratedBox
import dev.elpian.core.render.paint.RenderDefaultTextStyle
import dev.elpian.core.render.paint.RenderFilter
import dev.elpian.core.render.paint.RenderGesture
import dev.elpian.core.render.paint.RenderIgnorePointer
import dev.elpian.core.render.paint.RenderImage
import dev.elpian.core.render.paint.RenderMedia
import dev.elpian.core.render.paint.RenderNative
import dev.elpian.core.render.paint.RenderOpacity
import dev.elpian.core.render.paint.RenderScene3D
import dev.elpian.core.render.paint.RenderShaderMask
import dev.elpian.core.render.paint.RenderText
import dev.elpian.core.render.paint.RenderTransform
import dev.elpian.core.render.paint.RenderVisibility
import dev.elpian.core.render.paint.RenderWeb
import dev.elpian.core.util.deepEqual

/**
 * The reconciler keeps render objects alive across renders — a port of
 * Flutter's `Element.updateChildren` (render/reconciler.ts): children are
 * matched by type + key, first from the top, then from the bottom, then
 * through the keyed middle. A matched object receives the new configuration
 * (keeping its animation controllers, scroll offset, input text…); unmatched
 * ones are detached.
 */
typealias RenderObjectFactory = () -> RenderObject

private val factories: MutableMap<String, RenderObjectFactory> = linkedMapOf(
    "proxy" to { RenderProxy() },
    "padding" to { RenderPadding() },
    "safeArea" to { RenderSafeArea() },
    "fill" to { RenderFillAxis() },
    "constrained" to { RenderConstrainedBox() },
    "align" to { RenderAlign() },
    "aspectRatio" to { RenderAspectRatio() },
    "fractional" to { RenderFractional() },
    "limited" to { RenderLimitedBox() },
    "overflowBox" to { RenderOverflowBox() },
    "fitted" to { RenderFittedBox() },
    "fittedContent" to { RenderFittedContent() },
    "baseline" to { RenderBaseline() },
    "rotatedBox" to { RenderRotatedBox() },
    "intrinsicWidth" to { RenderIntrinsicWidth() },
    "intrinsicHeight" to { RenderIntrinsicHeight() },
    "offstage" to { RenderOffstage() },
    "indexedStack" to { RenderIndexedStack() },
    "flex" to { RenderFlex() },
    "flexible" to { RenderFlexible() },
    "wrap" to { RenderWrap() },
    "stack" to { RenderStack() },
    "positioned" to { RenderPositioned() },
    "grid" to { RenderGrid() },
    "imageMap" to { RenderImageMap() },
    "gridItem" to { RenderGridItem() },
    "scroll" to { RenderScroll() },
    "table" to { RenderTable() },
    "tableRow" to { RenderTableRow() },
    "tableCell" to { RenderTableCell() },
    "decorated" to { RenderDecoratedBox() },
    "opacity" to { RenderOpacity() },
    "transform" to { RenderTransform() },
    "clip" to { RenderClip() },
    "ignorePointer" to { RenderIgnorePointer() },
    "visibility" to { RenderVisibility() },
    "filter" to { RenderFilter() },
    "shaderMask" to { RenderShaderMask() },
    "defaultTextStyle" to { RenderDefaultTextStyle() },
    "text" to { RenderText() },
    "image" to { RenderImage() },
    "control" to { RenderControl() },
    "canvas" to { RenderCanvas() },
    "scene3d" to { RenderScene3D() },
    "media" to { RenderMedia() },
    "web" to { RenderWeb() },
    "native" to { RenderNative() },
    "gesture" to { RenderGesture() },
    // animated
    "animatedPadding" to { RenderAnimatedPadding() },
    "animatedAlign" to { RenderAnimatedAlign() },
    "animatedOpacity" to { RenderAnimatedOpacity() },
    "animatedTransform" to { RenderAnimatedTransform() },
    "animatedConstrained" to { RenderAnimatedConstrained() },
    "animatedDecorated" to { RenderAnimatedDecorated() },
    "animatedPositioned" to { RenderAnimatedPositioned() },
    "animatedDefaultTextStyle" to { RenderAnimatedDefaultTextStyle() },
    "animatedSize" to { RenderAnimatedSize() },
    "animatedCrossFade" to { RenderAnimatedCrossFade() },
    "animatedSwitcher" to { RenderAnimatedSwitcher() },
    "switcherSlot" to { RenderSwitcherSlot() },
    "transition" to { RenderTransition() },
    "staggered" to { RenderStaggered() },
    "staggerItem" to { RenderStaggerItem() },
    "shimmer" to { RenderShimmer() },
    "animatedGradient" to { RenderAnimatedGradient() },
    "keyframes" to { RenderKeyframes() },
    "hero" to { RenderHero() },
)

/** Register an additional render-object type (host extensions, islands). */
fun registerRenderObject(type: String, factory: RenderObjectFactory) {
    factories[type] = factory
}

/** The registered render-object type keys. */
fun registeredRenderObjectTypes(): Set<String> = factories.keys.toSet()

private fun canUpdate(ro: RenderObject, w: W): Boolean = ro.type == w.t && ro.key == w.k

/** Compare props ignoring function identity (closures are rebuilt every render). */
fun propsEqual(a: Map<String, Any?>, b: Map<String, Any?>): Boolean {
    val ka = a.keys.filter { a[it] !is Function<*> }
    val kb = b.keys.filter { b[it] !is Function<*> }
    if (ka.size != kb.size) return false
    for (k in ka) if (!deepEqual(a[k], b[k])) return false
    return true
}

fun createRenderObject(w: W, owner: RenderOwner, parent: RenderObject?): RenderObject {
    val factory = factories[w.t] ?: throw IllegalArgumentException("Elpian: unknown render object type \"${w.t}\"")
    val ro = factory()
    ro.type = w.t
    ro.key = w.k
    ro.parent = parent
    ro.init(w.p)
    ro.attach(owner)
    reconcileChildren(ro, w.c ?: emptyList(), owner)
    return ro
}

fun updateRenderObject(ro: RenderObject, w: W, owner: RenderOwner): RenderObject {
    if (propsEqual(ro.props, w.p)) {
        // Same configuration: refresh closures only, no relayout.
        for ((k, v) in w.p) if (v is Function<*>) ro.props[k] = v
    } else {
        ro.update(w.p)
    }
    reconcileChildren(ro, w.c ?: emptyList(), owner)
    return ro
}

/** Reconcile [root] against [w]; returns the (possibly new) root object. */
fun reconcileRoot(root: RenderObject?, w: W, owner: RenderOwner): RenderObject {
    if (root != null && canUpdate(root, w)) return updateRenderObject(root, w, owner)
    root?.detach()
    return createRenderObject(w, owner, null)
}

private fun detachChild(ro: RenderObject) {
    ro.detach()
    ro.parent = null
}

fun reconcileChildren(parent: RenderObject, ws: List<W>, owner: RenderOwner) {
    if (parent is RenderAnimatedSwitcher) {
        reconcileSwitcher(parent, ws, owner)
        return
    }
    val old = parent.children
    if (old.isEmpty() && ws.isEmpty()) return
    val result = arrayOfNulls<RenderObject>(ws.size)
    var oldTop = 0
    var newTop = 0
    var oldBottom = old.size - 1
    var newBottom = ws.size - 1

    while (oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldTop], ws[newTop])) {
        result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner)
        oldTop++
        newTop++
    }
    while (oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldBottom], ws[newBottom])) {
        oldBottom--
        newBottom--
    }
    val keyed = LinkedHashMap<String, RenderObject>()
    for (i in oldTop..oldBottom) {
        val o = old[i]
        val k = o.key
        if (k != null) keyed[o.type + "\u0000" + k] = o else detachChild(o)
    }
    while (newTop <= newBottom) {
        val w = ws[newTop]
        var match: RenderObject? = null
        if (w.k != null) {
            val id = w.t + "\u0000" + w.k
            match = keyed.remove(id)
        }
        result[newTop] = if (match != null) updateRenderObject(match, w, owner) else createRenderObject(w, owner, parent)
        newTop++
    }
    newBottom = ws.size - 1
    oldBottom = old.size - 1
    while (oldTop <= oldBottom && newTop <= newBottom) {
        result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner)
        oldTop++
        newTop++
    }
    for (o in keyed.values) detachChild(o)

    var changed = result.size != old.size
    var i = 0
    while (i < result.size && !changed) {
        if (result[i] !== old[i]) changed = true
        i++
    }
    val next = ArrayList<RenderObject>(result.size)
    for (r in result) {
        r!!.parent = parent
        next.add(r)
    }
    parent.children = next
    if (changed) parent.markNeedsLayout()
}

private fun reconcileSwitcher(parent: RenderAnimatedSwitcher, ws: List<W>, owner: RenderOwner) {
    val current = parent.children.filter { !parent.outgoing.containsKey(it) }
    val active = current.lastOrNull()
    for (extra in current.dropLast(1)) {
        detachChild(extra)
        parent.children = parent.children.filter { it !== extra }.toMutableList()
    }
    if (ws.isEmpty()) {
        if (active != null) parent.childRemoved(active)
        parent.markNeedsLayout()
        return
    }
    val w = ws[ws.size - 1]
    if (active != null && canUpdate(active, w)) {
        updateRenderObject(active, w, owner)
        return
    }
    val fresh = createRenderObject(w, owner, parent)
    parent.children = (parent.children.filter { parent.outgoing.containsKey(it) } + fresh).toMutableList()
    if (active != null && parent.isMounted) parent.childReplaced(active, fresh)
    else if (active != null) detachChild(active)
    parent.markNeedsLayout()
}
