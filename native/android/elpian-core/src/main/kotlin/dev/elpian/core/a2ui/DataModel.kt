package dev.elpian.core.a2ui

import dev.elpian.core.platform.Platforms

/**
 * A surface's data model (a2ui/data-model.ts): one JSON document addressed by
 * JSON Pointers, with the write semantics the A2UI conformance suite
 * (`data_model.yaml`, `data_deletion.yaml`) fixes:
 *
 * - writes auto-vivify missing containers — a list when the next segment is
 *   an index, an object otherwise — and pad lists with `null`;
 * - writing through a primitive, a non-numeric (or leading-zero) list
 *   segment, or a list index above [MAX_LIST_INDEX] is a `DataError`,
 *   and leaves the model untouched;
 * - deleting removes an object key, but sets a list slot to `null` so list
 *   length is preserved; deleting the root resets it to `{}`;
 * - observers on a path fire when its value changes — writes to the path, to
 *   an ancestor, or to a descendant — but not on same-value rewrites.
 *
 * Kotlin has no `undefined`: [get] returns null both for a missing value and
 * for a stored `null` (internally the two stay distinct, so a `null` written
 * over nothing still notifies observers, as in TypeScript).
 */
const val MAX_LIST_INDEX = 10000

typealias DataObserver = (value: Any?, path: String) -> Unit

/** "Nothing is there" — TypeScript's `undefined` inside the model. */
private object Missing

private class Watch(val segments: List<String>, val path: String, val observer: DataObserver)

class DataModel(initial: Any? = LinkedHashMap<String, Any?>()) {
    private var root: Any? = cloneJson(initial)
    private var watches: List<Watch> = emptyList()

    /** The value at [path], or null when nothing is there. */
    fun get(path: String = "/"): Any? = lookup(root, parsePointer(path)).let { if (it === Missing) null else it }

    /** Whether a value (possibly `null`) is stored at [path]. */
    fun has(path: String): Boolean = lookup(root, parsePointer(path)) !== Missing

    /** The whole document (do not mutate). */
    val value: Any? get() = root

    /** A deep copy of the whole document. */
    fun snapshot(): Any? = cloneJson(root)

    /** Write [value] at [path] (`null` is stored as JSON null; use [delete] to remove). */
    @Suppress("UNCHECKED_CAST")
    fun set(path: String, value: Any?) {
        val segments = parsePointer(path)
        val fresh = cloneJson(value)
        if (segments.isEmpty()) {
            mutate(segments) { root = fresh }
            return
        }
        checkWritable(root, segments, path)
        mutate(segments) {
            if (root == null) root = if (isIndexSegment(segments[0])) ArrayList<Any?>() else LinkedHashMap<String, Any?>()
            var container: Any? = root
            for (i in 0 until segments.size - 1) {
                val seg = segments[i]
                var child: Any?
                if (container is MutableList<*>) {
                    val list = container as MutableList<Any?>
                    val index = seg.toInt()
                    padList(list, index)
                    child = if (index < list.size) list[index] else null
                    if (child == null) {
                        child = if (isIndexSegment(segments[i + 1])) ArrayList<Any?>() else LinkedHashMap<String, Any?>()
                        if (index < list.size) list[index] = child else list.add(child)
                    }
                } else {
                    val map = container as MutableMap<String, Any?>
                    child = map[seg]
                    if (child == null) {
                        child = if (isIndexSegment(segments[i + 1])) ArrayList<Any?>() else LinkedHashMap<String, Any?>()
                        map[seg] = child
                    }
                }
                container = child
            }
            val last = segments[segments.size - 1]
            if (container is MutableList<*>) {
                val list = container as MutableList<Any?>
                val index = last.toInt()
                padList(list, index)
                if (index < list.size) list[index] = fresh else list.add(fresh)
            } else {
                (container as MutableMap<String, Any?>)[last] = fresh
            }
        }
    }

    /**
     * Remove the value at [path]: an object key is deleted, a list slot is set
     * to `null` (length preserved), the root resets to `{}`. A missing path is a
     * no-op that creates nothing.
     */
    @Suppress("UNCHECKED_CAST")
    fun delete(path: String) {
        val segments = parsePointer(path)
        if (segments.isEmpty()) {
            mutate(segments) { root = LinkedHashMap<String, Any?>() }
            return
        }
        val parent = lookup(root, segments.subList(0, segments.size - 1))
        val last = segments[segments.size - 1]
        if (parent is MutableList<*>) {
            if (!isIndexSegment(last) || last.toInt() >= parent.size) return
            mutate(segments) { (parent as MutableList<Any?>)[last.toInt()] = null }
        } else if (parent is MutableMap<*, *>) {
            if (!parent.containsKey(last)) return
            mutate(segments) { (parent as MutableMap<String, Any?>).remove(last) }
        }
    }

    /** Observe [path]; returns the unsubscribe function. */
    fun watch(path: String, observer: DataObserver): () -> Unit {
        val segments = parsePointer(path)
        val entry = Watch(segments, formatPointer(segments), observer)
        watches = watches + entry
        return { watches = watches.filter { it !== entry } }
    }

    /** Detach every observer. */
    fun dispose() {
        watches = emptyList()
    }

    /**
     * Run [change] (which replaces or removes the value at [target]) and notify
     * every observer whose value changed: ancestors when the target changed,
     * the target itself, and descendants whose own value differs afterwards.
     */
    private fun mutate(target: List<String>, change: () -> Unit) {
        val related = watches.filter { isPrefixOf(it.segments, target) || isPrefixOf(target, it.segments) }
        val before = cloneJson(lookup(root, target))
        // Snapshots: Kotlin containers are mutated in place, so copy what the observers saw.
        val descendantsBefore = related.filter { it.segments.size > target.size }.map { cloneJson(lookup(root, it.segments)) }
        change()
        if (related.isEmpty()) return
        val after = lookup(root, target)
        val targetChanged = !jsonEqual(before, after)
        var d = 0
        val fire = ArrayList<Watch>()
        for (w in related) {
            if (w.segments.size <= target.size) {
                if (targetChanged) fire.add(w)
            } else {
                val old = descendantsBefore[d++]
                if (!jsonEqual(old, lookup(root, w.segments))) fire.add(w)
            }
        }
        for (w in fire) {
            try {
                w.observer(lookup(root, w.segments).let { if (it === Missing) null else it }, w.path)
            } catch (e: Exception) {
                warn("A2UI data observer failed: $e")
            }
        }
    }
}

private fun lookup(root: Any?, segments: List<String>): Any? {
    var current: Any? = root
    for (seg in segments) {
        current = when (current) {
            is List<*> -> {
                if (!isIndexSegment(seg)) return Missing
                val i = seg.toIntOrNull() ?: return Missing
                if (i >= current.size) return Missing
                current[i]
            }
            is Map<*, *> -> {
                if (!current.containsKey(seg)) return Missing
                current[seg]
            }
            else -> return Missing
        }
    }
    return current
}

/** Validate a write before touching the model, so a failed write changes nothing. */
private fun checkWritable(root: Any?, segments: List<String>, path: String) {
    var current: Any? = root
    var vivified = false
    for (i in segments.indices) {
        val seg = segments[i]
        val isList: Boolean
        if (vivified || current == null) {
            // A missing or null slot (including a null root) becomes a container.
            isList = isIndexSegment(seg)
            vivified = true
        } else if (current is List<*>) {
            isList = true
        } else if (current is Map<*, *>) {
            isList = false
        } else {
            throw dataError("Cannot set path \"$path\": \"${formatPointer(segments.subList(0, i))}\" holds a primitive value")
        }
        if (isList) {
            if (!isIndexSegment(seg)) throw dataError("Cannot set path \"$path\": non-numeric segment \"$seg\" addresses a list")
            if ((seg.toDoubleOrNull() ?: 0.0) > MAX_LIST_INDEX) throw dataError("Cannot set path \"$path\": list index $seg exceeds the maximum of $MAX_LIST_INDEX")
        }
        if (!vivified) {
            val next = when (current) {
                is List<*> -> seg.toInt().let { if (it < current.size) current[it] else null }
                is Map<*, *> -> current[seg]
                else -> null
            }
            if (next == null) vivified = true
            current = next
        }
    }
}

private fun padList(list: MutableList<Any?>, index: Int) {
    while (list.size < index) list.add(null)
}

/**
 * Deep copy of a JSON value into mutable containers (functions dropped;
 * numbers become Doubles, as every JSON number is).
 */
fun cloneJson(value: Any?): Any? = when (value) {
    null -> null
    is Map<*, *> -> {
        val out = LinkedHashMap<String, Any?>()
        for ((k, v) in value) {
            if (v is Function<*>) continue
            out[k.toString()] = cloneJson(v)
        }
        out
    }
    is List<*> -> value.mapTo(ArrayList()) { cloneJson(it) }
    is Array<*> -> value.mapTo(ArrayList()) { cloneJson(it) }
    is Double -> value
    is Number -> value.toDouble()
    else -> value
}

/** Structural equality of JSON values (`-0` equals `0`; a missing value equals nothing else). */
fun jsonEqual(a: Any?, b: Any?): Boolean {
    if (a === b) return true
    if (a === Missing || b === Missing) return false
    if (a == null || b == null) return false
    if (a is Number && b is Number) return a.toDouble() == b.toDouble()
    if (a is List<*> && b is List<*>) {
        if (a.size != b.size) return false
        for (i in a.indices) if (!jsonEqual(a[i], b[i])) return false
        return true
    }
    if (a is Map<*, *> && b is Map<*, *>) {
        if (a.size != b.size) return false
        for ((k, v) in a) {
            if (!b.containsKey(k)) return false
            if (!jsonEqual(v, b[k])) return false
        }
        return true
    }
    if (a is List<*> || b is List<*> || a is Map<*, *> || b is Map<*, *>) return false
    return a == b
}

/** `console.warn`. */
internal fun warn(message: String) {
    if (Platforms.isInstalled) {
        try {
            dev.elpian.core.platform.platform().log("warn", message)
            return
        } catch (_: Exception) {
        }
    }
    System.err.println(message)
}
