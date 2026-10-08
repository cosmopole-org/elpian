package dev.elpian.core.render

import dev.elpian.core.util.deepEqual
import kotlin.math.roundToLong

/**
 * Walks the laid-out tree, assigns a native view to every object that paints
 * and diffs against the previous frame into [ViewOp]s (render/compositor.ts).
 */
class Compositor(private val owner: RenderOwner) {
    private class ViewRecord(val kind: String, var parent: Int, var ro: RenderObject, val props: HashMap<String, Any?>)
    private class Placement(val id: Int, val parent: Int, val kind: String, val ro: RenderObject, val props: Map<String, Any?>)

    private val views = LinkedHashMap<Int, ViewRecord>()
    private var childLists = HashMap<Int, List<Int>>()
    private var pendingCommands = ArrayList<ViewOp.Command>()

    companion object {
        /** Props sent when present and never diffed or reset. */
        val ONE_SHOT = setOf("commands", "appendCommands", "scrollTo")
        private fun round(v: Double) = (v * 1000).roundToLong() / 1000.0
    }

    fun objectFor(viewId: Int): RenderObject? = views[viewId]?.ro
    fun hasView(viewId: Int): Boolean = views.containsKey(viewId)
    val viewCount: Int get() = views.size

    /** Queue an imperative command for a view (focus, scroll, play…). */
    fun command(viewId: Int, name: String, args: Any? = null) {
        pendingCommands.add(ViewOp.Command(viewId, name, args))
        owner.requestVisualUpdate()
    }

    /** Forget the last-sent value of [keys] so the next frame re-sends them. */
    fun invalidateProps(viewId: Int, keys: List<String>) {
        val record = views[viewId] ?: return
        for (k in keys) record.props.remove(k)
        owner.requestVisualUpdate()
    }

    /** The absolute frame of [ro] (ancestor offsets minus scroll offsets). */
    fun globalFrame(ro: RenderObject): DoubleArray {
        var x = 0.0
        var y = 0.0
        var node: RenderObject? = ro
        while (node != null) {
            x += node.offset.x
            y += node.offset.y
            val parent = node.parent
            if (parent != null && parent.viewKind() == ViewKinds.SCROLL) {
                (parent as? ScrollOffsetHolder)?.scrollOffset?.let {
                    x -= it.x
                    y -= it.y
                }
            }
            node = parent
        }
        return doubleArrayOf(x, y, ro.size.width, ro.size.height)
    }

    fun composite(root: RenderObject): List<ViewOp> {
        val placements = ArrayList<Placement>()
        val lists = LinkedHashMap<Int, MutableList<Int>>()
        fun walk(ro: RenderObject, parentView: Int, ox: Double, oy: Double) {
            val x = ox + ro.offset.x
            val y = oy + ro.offset.y
            val kind = ro.viewKind()
            if (kind != null) {
                val previous = ro.viewId?.let { views[it] }
                if (ro.viewId == null || (previous != null && (previous.kind != kind || previous.parent != parentView))) {
                    ro.viewId = owner.allocateViewId()
                }
                val id = ro.viewId!!
                val props = LinkedHashMap<String, Any?>()
                props["frame"] = listOf(round(x), round(y), round(ro.size.width), round(ro.size.height))
                props.putAll(ro.viewProps())
                placements.add(Placement(id, parentView, kind, ro, props))
                lists.getOrPut(parentView) { ArrayList() }.add(id)
                val origin = ro.childOriginInView()
                for (child in ro.children) if (ro.paintsChild(child)) walk(child, id, origin.x, origin.y)
            } else {
                for (child in ro.children) if (ro.paintsChild(child)) walk(child, parentView, x, y)
            }
        }
        walk(root, ROOT_VIEW_ID, 0.0, 0.0)

        val ops = ArrayList<ViewOp>()
        val nextIds = placements.map { it.id }.toHashSet()
        for ((id, record) in views) {
            if (id in nextIds) continue
            val parentGone = record.parent != ROOT_VIEW_ID && record.parent !in nextIds && views.containsKey(record.parent)
            if (!parentGone) ops.add(ViewOp.Remove(id))
        }
        views.keys.retainAll(nextIds)

        val reordered = HashSet<Int>()
        for ((parent, list) in lists) {
            val prev = childLists[parent]
            if (prev == null || prev != list) reordered.add(parent)
        }
        val indexOf = HashMap<Int, Int>()
        for (list in lists.values) list.forEachIndexed { i, id -> indexOf[id] = i }
        for (p in placements) {
            val index = indexOf[p.id] ?: 0
            val existing = views[p.id]
            if (existing == null) {
                val record = ViewRecord(p.kind, p.parent, p.ro, HashMap())
                for ((k, v) in p.props) if (v != null && k !in ONE_SHOT) record.props[k] = v
                views[p.id] = record
                ops.add(ViewOp.Create(p.id, p.kind, p.parent, index, p.props.filterValues { it != null }))
                continue
            }
            existing.ro = p.ro
            if (p.parent in reordered) {
                ops.add(ViewOp.Move(p.id, p.parent, index))
                existing.parent = p.parent
            }
            val changed = LinkedHashMap<String, Any?>()
            val seen = HashSet<String>()
            for ((k, v) in p.props) {
                if (v == null) continue
                if (k in ONE_SHOT) {
                    changed[k] = v
                    continue
                }
                seen.add(k)
                if (!existing.props.containsKey(k) || !deepEqual(existing.props[k], v)) {
                    existing.props[k] = v
                    changed[k] = v
                }
            }
            for (k in existing.props.keys.toList()) {
                if (k !in seen) {
                    existing.props.remove(k)
                    changed[k] = null
                }
            }
            if (changed.isNotEmpty()) ops.add(ViewOp.Update(p.id, changed))
        }
        childLists = HashMap(lists)
        if (pendingCommands.isNotEmpty()) {
            for (cmd in pendingCommands) if (views.containsKey(cmd.id)) ops.add(cmd)
            pendingCommands = ArrayList()
        }
        return ops
    }

    /** Remove every view (unmount). */
    fun clear(): List<ViewOp> {
        val ops = views.filterValues { it.parent == ROOT_VIEW_ID }.keys.map { ViewOp.Remove(it) }
        views.clear()
        childLists.clear()
        pendingCommands = ArrayList()
        return ops
    }
}

/** Render objects whose children scroll (their offset shifts global frames). */
interface ScrollOffsetHolder {
    val scrollOffset: Vec
}
