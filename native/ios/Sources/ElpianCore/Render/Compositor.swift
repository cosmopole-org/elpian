import Foundation

/**
 * The compositor walks the laid-out render tree, assigns a native view to
 * every object that paints, and diffs the result against the previous frame
 * into [ViewOp]s: creates (parents before children), moves, prop updates and
 * removals (render/compositor.ts). Layout-only objects (padding, alignment,
 * flex…) never reach the platform; they just shift the frames of the views
 * below them.
 */

/** Render objects whose children scroll (their offset shifts global frames). */
public protocol ScrollOffsetHolder: AnyObject {
    var scrollOffset: Vec { get }
}

/** An insertion-ordered dictionary (JavaScript `Map` iteration order). */
struct OrderedMap<K: Hashable, V> {
    private(set) var keys: [K] = []
    private var storage: [K: V] = [:]

    subscript(key: K) -> V? {
        get { storage[key] }
        set {
            if let v = newValue {
                if storage.updateValue(v, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    var count: Int { keys.count }
    var isEmpty: Bool { keys.isEmpty }
    func has(_ key: K) -> Bool { storage[key] != nil }
    var entries: [(K, V)] { keys.map { ($0, storage[$0]!) } }
    var values: [V] { keys.map { storage[$0]! } }

    mutating func removeAll() {
        keys.removeAll()
        storage.removeAll()
    }

    mutating func retain(_ keep: (K) -> Bool) {
        keys = keys.filter { k in
            if keep(k) { return true }
            storage.removeValue(forKey: k)
            return false
        }
    }
}

public final class Compositor {
    private final class ViewRecord {
        let kind: ViewKind
        var parent: Int
        var ro: RenderObject
        /** Last emitted JSON of each prop, for diffing. */
        var props: OrderedMap<String, String>

        init(kind: ViewKind, parent: Int, ro: RenderObject, props: OrderedMap<String, String>) {
            self.kind = kind
            self.parent = parent
            self.ro = ro
            self.props = props
        }
    }

    private struct Placement {
        let id: Int
        let parent: Int
        let kind: ViewKind
        let ro: RenderObject
        let props: ViewProps
    }

    /** Props sent when present and never diffed or reset (incremental payloads, one-shot requests). */
    public static let ONE_SHOT: Set<String> = ["commands", "appendCommands", "scrollTo"]

    private static func round(_ v: Double) -> Double { jsRound(v * 1000) / 1000 }

    private unowned let owner: RenderOwner
    private var views = OrderedMap<Int, ViewRecord>()
    private var childLists = OrderedMap<Int, [Int]>()
    private var pendingCommands: [ViewOp] = []

    public init(_ owner: RenderOwner) {
        self.owner = owner
    }

    public func objectFor(_ viewId: Int) -> RenderObject? { views[viewId]?.ro }

    public func hasView(_ viewId: Int) -> Bool { views.has(viewId) }

    /** Queue an imperative command for a view (focus, scroll, play…). */
    public func command(_ viewId: Int, _ name: String, _ args: Any? = nil) {
        pendingCommands.append(.command(id: viewId, name: name, args: args))
        owner.requestVisualUpdate()
    }

    /** Forget the last-sent value of [keys] so the next frame re-sends them (controlled inputs). */
    public func invalidateProps(_ viewId: Int, _ keys: [String]) {
        guard let record = views[viewId] else { return }
        for k in keys { record.props[k] = nil }
        owner.requestVisualUpdate()
    }

    /** The absolute frame of a view (sum of ancestor frames, minus scroll offsets). */
    public func globalFrame(_ ro: RenderObject) -> Rect {
        var x = 0.0
        var y = 0.0
        var node: RenderObject? = ro
        while let n = node {
            x += n.offset.x
            y += n.offset.y
            let parent = n.parent
            if let p = parent, p.viewKind() == .scroll, let holder = p as? ScrollOffsetHolder {
                let scroll = holder.scrollOffset
                x -= scroll.x
                y -= scroll.y
            }
            node = parent
        }
        return Rect(x: x, y: y, width: ro.size.width, height: ro.size.height)
    }

    public func composite(_ root: RenderObject) -> [ViewOp] {
        var placements: [Placement] = []
        var lists = OrderedMap<Int, [Int]>()
        func walk(_ ro: RenderObject, _ parentView: Int, _ ox: Double, _ oy: Double) {
            let x = ox + ro.offset.x
            let y = oy + ro.offset.y
            if let kind = ro.viewKind() {
                let previous = ro.viewId.flatMap { views[$0] }
                // A view that changed kind or parent is recreated under a new id (its
                // old subtree is removed wholesale), so the platform never has to
                // reparent native views.
                if ro.viewId == nil || (previous != nil && (previous!.kind != kind || previous!.parent != parentView)) {
                    ro.viewId = owner.allocateViewId()
                }
                let id = ro.viewId!
                let props = ViewProps()
                props["frame"] = [Compositor.round(x), Compositor.round(y), Compositor.round(ro.size.width), Compositor.round(ro.size.height)] as [Any?]
                props.assign(ro.viewProps())
                placements.append(Placement(id: id, parent: parentView, kind: kind, ro: ro, props: props))
                lists[parentView] = (lists[parentView] ?? []) + [id]
                let origin = ro.childOriginInView()
                for child in ro.children where ro.paintsChild(child) { walk(child, id, origin.x, origin.y) }
            } else {
                for child in ro.children where ro.paintsChild(child) { walk(child, parentView, x, y) }
            }
        }
        walk(root, ROOT_VIEW_ID, 0, 0)

        var ops: [ViewOp] = []
        let nextIds = Set(placements.map { $0.id })

        // Removals first — only the topmost removed view of each removed subtree.
        for (id, record) in views.entries {
            if nextIds.contains(id) { continue }
            let parentGone = record.parent != ROOT_VIEW_ID && !nextIds.contains(record.parent) && views.has(record.parent)
            if !parentGone { ops.append(.remove(id: id)) }
        }
        views.retain { nextIds.contains($0) }

        // Which parents' child orders changed?
        var reordered = Set<Int>()
        for (parent, list) in lists.entries {
            let prev = childLists[parent]
            if prev == nil || prev! != list { reordered.insert(parent) }
        }

        // Creates / moves / updates in tree order (parents before children).
        var indexOf: [Int: Int] = [:]
        for list in lists.values {
            for (i, id) in list.enumerated() { indexOf[id] = i }
        }
        for p in placements {
            let index = indexOf[p.id] ?? 0
            guard let existing = views[p.id] else {
                var recorded = OrderedMap<String, String>()
                for (k, v) in p.props where !Compositor.ONE_SHOT.contains(k) { recorded[k] = JSON.stringify(v) }
                views[p.id] = ViewRecord(kind: p.kind, parent: p.parent, ro: p.ro, props: recorded)
                ops.append(.create(id: p.id, kind: p.kind, parent: p.parent, index: index, props: p.props))
                continue
            }
            existing.ro = p.ro
            if reordered.contains(p.parent) {
                ops.append(.move(id: p.id, parent: p.parent, index: index))
                existing.parent = p.parent
            }
            let changed = ViewProps()
            var seenKeys = Set<String>()
            for (k, v) in p.props {
                if Compositor.ONE_SHOT.contains(k) {
                    if v != nil { changed[k] = v }
                    continue
                }
                seenKeys.insert(k)
                let json = JSON.stringify(v)
                if existing.props[k] != json {
                    existing.props[k] = json
                    changed[k] = v
                }
            }
            for k in existing.props.keys where !seenKeys.contains(k) {
                existing.props[k] = nil
                changed[k] = nil as Any?
            }
            if !changed.isEmpty { ops.append(.update(id: p.id, props: changed)) }
        }

        childLists = lists
        if !pendingCommands.isEmpty {
            for cmd in pendingCommands where views.has(cmd.id) { ops.append(cmd) }
            pendingCommands = []
        }
        return ops
    }

    /** Remove every view (unmount). */
    public func clear() -> [ViewOp] {
        var ops: [ViewOp] = []
        for (id, record) in views.entries where record.parent == ROOT_VIEW_ID { ops.append(.remove(id: id)) }
        views.removeAll()
        childLists.removeAll()
        pendingCommands = []
        return ops
    }

    public var viewCount: Int { views.count }
}
