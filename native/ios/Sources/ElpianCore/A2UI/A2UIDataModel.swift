import Foundation

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
 * Swift has no `undefined`: [get] returns nil both for a missing value and a
 * JSON null, and `set(path, nil)` writes a null (the TypeScript `set(path,
 * undefined)` — a delete — is [delete]). Lists are `[Any?]` values, so writes
 * rebuild the lists along the path; objects ([JSONObject]) are updated in place.
 */
public let MAX_LIST_INDEX = 10000

public typealias DataObserver = (_ value: Any?, _ path: String) -> Void

private final class Watch {
    let segments: [String]
    let path: String
    let observer: DataObserver

    init(_ segments: [String], _ path: String, _ observer: @escaping DataObserver) {
        self.segments = segments
        self.path = path
        self.observer = observer
    }
}

public final class DataModel {
    private var root: Any?
    private var watches: [Watch] = []

    public init(_ initial: Any? = JSONObject()) {
        root = cloneJson(initial)
    }

    /** The value at [path], or nil when nothing (or null) is there. */
    public func get(_ path: String = "/") throws -> Any? {
        lookup(root, try parsePointer(path))
    }

    /** The whole document (do not mutate). */
    public var value: Any? { root }

    /** A deep copy of the whole document. */
    public func snapshot() -> Any? { cloneJson(root) }

    /** Write [value] at [path] (nil writes a JSON null). */
    public func set(_ path: String, _ value: Any?) throws {
        let segments = try parsePointer(path)
        let fresh = cloneJson(value)
        if segments.isEmpty {
            mutate(segments) { self.root = fresh }
            return
        }
        try checkWritable(root, segments, path)
        mutate(segments) { self.root = writeIn(self.root, segments, 0, fresh) }
    }

    /**
     * Remove the value at [path]: an object key is deleted, a list slot is set
     * to `null` (length preserved), the root resets to `{}`. A missing path is a
     * no-op that creates nothing.
     */
    public func delete(_ path: String) throws {
        let segments = try parsePointer(path)
        if segments.isEmpty {
            mutate(segments) { self.root = JSONObject() }
            return
        }
        let parent = lookup(root, Array(segments.dropLast()))
        let last = segments[segments.count - 1]
        if let list = parent as? [Any?] {
            guard isIndexSegment(last), let i = Int(last), i < list.count else { return }
            mutate(segments) { self.root = writeIn(self.root, segments, 0, nil) }
        } else if let obj = parent as? JSONObject {
            if !obj.has(last) { return }
            mutate(segments) { obj.removeValue(forKey: last) }
        }
    }

    /** Observe [path]; returns the unsubscribe function. */
    @discardableResult
    public func watch(_ path: String, _ observer: @escaping DataObserver) throws -> () -> Void {
        let segments = try parsePointer(path)
        let entry = Watch(segments, formatPointer(segments), observer)
        watches.append(entry)
        return { [weak self] in self?.watches.removeAll { $0 === entry } }
    }

    /** Detach every observer. */
    public func dispose() {
        watches = []
    }

    /**
     * Run [change] (which replaces or removes the value at [target]) and notify
     * every observer whose value changed: ancestors when the target changed,
     * the target itself, and descendants whose own value differs afterwards.
     */
    private func mutate(_ target: [String], _ change: () -> Void) {
        let related = watches.filter { isPrefixOf($0.segments, target) || isPrefixOf(target, $0.segments) }
        let before = cloneJson(lookup(root, target))
        // Snapshots: objects inside the old subtree may be shared with the new document.
        let descendantsBefore = related.filter { $0.segments.count > target.count }.map { cloneJson(lookup(root, $0.segments)) }
        change()
        if related.isEmpty { return }
        let after = lookup(root, target)
        let targetChanged = !jsonEqual(before, after)
        var d = 0
        var fire: [Watch] = []
        for w in related {
            if w.segments.count <= target.count {
                if targetChanged { fire.append(w) }
            } else {
                let old = descendantsBefore[d]
                d += 1
                if !jsonEqual(old, lookup(root, w.segments)) { fire.append(w) }
            }
        }
        for w in fire { w.observer(lookup(root, w.segments), w.path) }
    }
}

/** [container] with [fresh] written at [segments] from index [i] on (containers vivified, lists padded). */
private func writeIn(_ container: Any?, _ segments: [String], _ i: Int, _ fresh: Any?) -> Any? {
    let seg = segments[i]
    let last = i == segments.count - 1
    var c = flattenOptional(container)
    if c == nil { c = isIndexSegment(seg) ? [Any?]() : JSONObject() }
    if var list = c as? [Any?] {
        let index = Int(seg) ?? 0
        while list.count < index { list.append(nil) }
        let value: Any? = last ? fresh : writeIn(index < list.count ? list[index] : nil, segments, i + 1, fresh)
        if index < list.count { list[index] = value } else { list.append(value) }
        return list
    }
    if let obj = c as? JSONObject {
        obj[seg] = last ? fresh : writeIn(obj.has(seg) ? obj[seg] : nil, segments, i + 1, fresh)
        return obj
    }
    return c
}

private func lookup(_ root: Any?, _ segments: [String]) -> Any? {
    var current = flattenOptional(root)
    for seg in segments {
        if let list = current as? [Any?] {
            guard isIndexSegment(seg), let i = Int(seg), i < list.count else { return nil }
            current = flattenOptional(list[i])
        } else if let obj = current as? JSONObject {
            guard obj.has(seg) else { return nil }
            current = obj[seg]
        } else {
            return nil
        }
        if current == nil { return nil }
    }
    return current
}

/** Validate a write before touching the model, so a failed write changes nothing. */
private func checkWritable(_ root: Any?, _ segments: [String], _ path: String) throws {
    var current = flattenOptional(root)
    var vivified = false
    for i in 0..<segments.count {
        let seg = segments[i]
        let isList: Bool
        if vivified || current == nil {
            // A missing or null slot (including a null root) becomes a container.
            isList = isIndexSegment(seg)
            vivified = true
        } else if current is [Any?] {
            isList = true
        } else if current is JSONObject {
            isList = false
        } else {
            throw dataError("Cannot set path \"\(path)\": \"\(formatPointer(Array(segments[0..<i])))\" holds a primitive value")
        }
        if isList {
            if !isIndexSegment(seg) { throw dataError("Cannot set path \"\(path)\": non-numeric segment \"\(seg)\" addresses a list") }
            if (Double(seg) ?? .infinity) > Double(MAX_LIST_INDEX) {
                throw dataError("Cannot set path \"\(path)\": list index \(seg) exceeds the maximum of \(MAX_LIST_INDEX)")
            }
        }
        if !vivified {
            var next: Any?
            if let list = current as? [Any?] {
                let n = Int(seg) ?? Int.max
                next = n < list.count ? flattenOptional(list[n]) : nil
            } else if let obj = current as? JSONObject {
                next = obj.has(seg) ? obj[seg] : nil
            }
            if next == nil { vivified = true }
            current = next
        }
    }
}

/** Deep copy of a JSON value (closures dropped from objects). */
public func cloneJson(_ value: Any?) -> Any? {
    guard let v = flattenOptional(value) else { return nil }
    if let o = v as? JSONObject {
        let out = JSONObject()
        for (k, x) in o {
            if x is ElpianEventListener { continue }
            out[k] = cloneJson(x)
        }
        return out
    }
    if let a = asArray(v) { return a.map { cloneJson($0) } as [Any?] }
    if let m = asMap(v) { return cloneJson(m) }
    return v
}

/** Structural equality of JSON values (`-0` equals `0`). */
public func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
    deepEqual(a, b)
}
