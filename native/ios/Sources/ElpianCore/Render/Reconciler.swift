import Foundation

/**
 * The reconciler keeps render objects alive across renders — a port of
 * Flutter's `Element.updateChildren` (render/reconciler.ts): children are
 * matched by type + key, first from the top, then from the bottom, then
 * through the keyed middle. A matched object receives the new configuration
 * (keeping its animation controllers, scroll offset, input text…); unmatched
 * ones are detached.
 */
public typealias RenderObjectFactory = () -> RenderObject

private let factoriesLock = NSLock()

private var factoryOrder: [String] = []
private var factories: [String: RenderObjectFactory] = {
    let entries: [(String, RenderObjectFactory)] = [
        ("proxy", { RenderProxy() }),
        ("padding", { RenderPadding() }),
        ("safeArea", { RenderSafeArea() }),
        ("fill", { RenderFillAxis() }),
        ("constrained", { RenderConstrainedBox() }),
        ("align", { RenderAlign() }),
        ("aspectRatio", { RenderAspectRatio() }),
        ("fractional", { RenderFractional() }),
        ("limited", { RenderLimitedBox() }),
        ("overflowBox", { RenderOverflowBox() }),
        ("fitted", { RenderFittedBox() }),
        ("fittedContent", { RenderFittedContent() }),
        ("baseline", { RenderBaseline() }),
        ("rotatedBox", { RenderRotatedBox() }),
        ("intrinsicWidth", { RenderIntrinsicWidth() }),
        ("intrinsicHeight", { RenderIntrinsicHeight() }),
        ("offstage", { RenderOffstage() }),
        ("indexedStack", { RenderIndexedStack() }),
        ("flex", { RenderFlex() }),
        ("flexible", { RenderFlexible() }),
        ("wrap", { RenderWrap() }),
        ("stack", { RenderStack() }),
        ("positioned", { RenderPositioned() }),
        ("grid", { RenderGrid() }),
        ("imageMap", { RenderImageMap() }),
        ("gridItem", { RenderGridItem() }),
        ("scroll", { RenderScroll() }),
        ("table", { RenderTable() }),
        ("tableRow", { RenderTableRow() }),
        ("tableCell", { RenderTableCell() }),
        ("decorated", { RenderDecoratedBox() }),
        ("opacity", { RenderOpacity() }),
        ("transform", { RenderTransform() }),
        ("clip", { RenderClip() }),
        ("ignorePointer", { RenderIgnorePointer() }),
        ("visibility", { RenderVisibility() }),
        ("filter", { RenderFilter() }),
        ("shaderMask", { RenderShaderMask() }),
        ("defaultTextStyle", { RenderDefaultTextStyle() }),
        ("text", { RenderText() }),
        ("image", { RenderImage() }),
        ("control", { RenderControl() }),
        ("canvas", { RenderCanvas() }),
        ("scene3d", { RenderScene3D() }),
        ("media", { RenderMedia() }),
        ("web", { RenderWeb() }),
        ("native", { RenderNative() }),
        ("gesture", { RenderGesture() }),
        // animated
        ("animatedPadding", { RenderAnimatedPadding() }),
        ("animatedAlign", { RenderAnimatedAlign() }),
        ("animatedOpacity", { RenderAnimatedOpacity() }),
        ("animatedTransform", { RenderAnimatedTransform() }),
        ("animatedConstrained", { RenderAnimatedConstrained() }),
        ("animatedDecorated", { RenderAnimatedDecorated() }),
        ("animatedPositioned", { RenderAnimatedPositioned() }),
        ("animatedDefaultTextStyle", { RenderAnimatedDefaultTextStyle() }),
        ("animatedSize", { RenderAnimatedSize() }),
        ("animatedCrossFade", { RenderAnimatedCrossFade() }),
        ("animatedSwitcher", { RenderAnimatedSwitcher() }),
        ("switcherSlot", { RenderSwitcherSlot() }),
        ("transition", { RenderTransition() }),
        ("staggered", { RenderStaggered() }),
        ("staggerItem", { RenderStaggerItem() }),
        ("shimmer", { RenderShimmer() }),
        ("animatedGradient", { RenderAnimatedGradient() }),
        ("keyframes", { RenderKeyframes() }),
        ("hero", { RenderHero() }),
    ]
    var out: [String: RenderObjectFactory] = [:]
    for (k, f) in entries {
        out[k] = f
        factoryOrder.append(k)
    }
    return out
}()

private func factory(_ type: String) -> RenderObjectFactory? {
    factoriesLock.lock()
    defer { factoriesLock.unlock() }
    return factories[type]
}

/** Register an additional render-object type (host extensions, islands). */
public func registerRenderObject(_ type: String, _ factory: @escaping RenderObjectFactory) {
    factoriesLock.lock()
    defer { factoriesLock.unlock() }
    if factories[type] == nil { factoryOrder.append(type) }
    factories[type] = factory
}

/** The registered render-object type keys. */
public func registeredRenderObjectTypes() -> Set<String> {
    factoriesLock.lock()
    defer { factoriesLock.unlock() }
    return Set(factories.keys)
}

/** The registered render-object type keys in registration order. */
public func registeredRenderObjectTypeList() -> [String] {
    factoriesLock.lock()
    defer { factoriesLock.unlock() }
    _ = factories.count
    return factoryOrder
}

/** Elpian: unknown render object type "<type>". */
public struct UnknownRenderObjectType: Error, CustomStringConvertible {
    public let type: String
    public var description: String { "Elpian: unknown render object type \"\(type)\"" }
}

/** `typeof v === 'function'`: a Swift closure stored in a props bag. */
public func jsIsFunction(_ v: Any?) -> Bool {
    guard let x = flattenOptional(v) else { return false }
    return String(describing: type(of: x)).contains("->")
}

private func canUpdate(_ ro: RenderObject, _ w: W) -> Bool { ro.type == w.t && ro.key == w.k }

/** Compare props ignoring function identity (closures are rebuilt every render). */
public func propsEqual(_ a: JSONObject, _ b: JSONObject) -> Bool {
    let ka = a.keys.filter { !jsIsFunction(a[$0]) }
    let kb = b.keys.filter { !jsIsFunction(b[$0]) }
    if ka.count != kb.count { return false }
    for k in ka where !deepEqual(a[k], b[k]) { return false }
    return true
}

/** Create (and attach) the render object for [w]; traps on an unregistered type, as the TypeScript engine (native/web) throws. */
public func createRenderObject(_ w: W, _ owner: RenderOwner, _ parent: RenderObject?) -> RenderObject {
    guard let make = factory(w.t) else { fatalError(UnknownRenderObjectType(type: w.t).description) }
    let ro = make()
    ro.type = w.t
    ro.key = w.k
    ro.parent = parent
    ro.initialize(w.p)
    ro.attach(owner)
    reconcileChildren(ro, w.c ?? [], owner)
    return ro
}

/** Like [createRenderObject], but throws for an unregistered type instead of trapping. */
public func tryCreateRenderObject(_ w: W, _ owner: RenderOwner, _ parent: RenderObject?) throws -> RenderObject {
    if factory(w.t) == nil { throw UnknownRenderObjectType(type: w.t) }
    return createRenderObject(w, owner, parent)
}

@discardableResult
public func updateRenderObject(_ ro: RenderObject, _ w: W, _ owner: RenderOwner) -> RenderObject {
    if propsEqual(ro.props, w.p) {
        // Same configuration: refresh closures only, no relayout.
        for (k, v) in w.p where jsIsFunction(v) { ro.props[k] = v }
    } else {
        ro.update(w.p)
    }
    reconcileChildren(ro, w.c ?? [], owner)
    return ro
}

/** Reconcile [root] against [w]; returns the (possibly new) root object. */
public func reconcileRoot(_ root: RenderObject?, _ w: W, _ owner: RenderOwner) -> RenderObject {
    if let root = root, canUpdate(root, w) { return updateRenderObject(root, w, owner) }
    root?.detach()
    return createRenderObject(w, owner, nil)
}

private func detachChild(_ ro: RenderObject) {
    ro.detach()
    ro.parent = nil
}

public func reconcileChildren(_ parent: RenderObject, _ ws: [W], _ owner: RenderOwner) {
    if let switcher = parent as? RenderAnimatedSwitcher {
        reconcileSwitcher(switcher, ws, owner)
        return
    }
    let old = parent.children
    if old.isEmpty && ws.isEmpty { return }
    var result = [RenderObject?](repeating: nil, count: ws.count)
    var oldTop = 0
    var newTop = 0
    var oldBottom = old.count - 1
    var newBottom = ws.count - 1

    while oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldTop], ws[newTop]) {
        result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner)
        oldTop += 1
        newTop += 1
    }
    while oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldBottom], ws[newBottom]) {
        oldBottom -= 1
        newBottom -= 1
    }
    var keyed: [String: RenderObject] = [:]
    var keyedOrder: [String] = []
    if oldTop <= oldBottom {
        for i in oldTop...oldBottom {
            let o = old[i]
            if let k = o.key {
                let id = o.type + "\u{0}" + k
                if keyed[id] == nil { keyedOrder.append(id) }
                keyed[id] = o
            } else {
                detachChild(o)
            }
        }
    }
    while newTop <= newBottom {
        let w = ws[newTop]
        var match: RenderObject?
        if let k = w.k {
            let id = w.t + "\u{0}" + k
            match = keyed.removeValue(forKey: id)
        }
        result[newTop] = match != nil ? updateRenderObject(match!, w, owner) : createRenderObject(w, owner, parent)
        newTop += 1
    }
    // The bottom run matched above, in order (after the middle, which may have
    // shrunk or grown — so resume at the bottom run's first old object).
    oldTop = oldBottom + 1
    newBottom = ws.count - 1
    oldBottom = old.count - 1
    while oldTop <= oldBottom && newTop <= newBottom {
        result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner)
        oldTop += 1
        newTop += 1
    }
    for id in keyedOrder {
        if let o = keyed[id] { detachChild(o) }
    }

    var changed = result.count != old.count
    var i = 0
    while i < result.count && !changed {
        if result[i] !== old[i] { changed = true }
        i += 1
    }
    var next: [RenderObject] = []
    next.reserveCapacity(result.count)
    for r in result {
        let ro = r!
        ro.parent = parent
        next.append(ro)
    }
    parent.children = next
    if changed { parent.markNeedsLayout() }
}

private func reconcileSwitcher(_ parent: RenderAnimatedSwitcher, _ ws: [W], _ owner: RenderOwner) {
    let current = parent.children.filter { !parent.isOutgoing($0) }
    let active = current.last
    for extra in current.dropLast() {
        detachChild(extra)
        parent.children = parent.children.filter { $0 !== extra }
    }
    if ws.isEmpty {
        if let active = active { parent.childRemoved(active) }
        parent.markNeedsLayout()
        return
    }
    let w = ws[ws.count - 1]
    if let active = active, canUpdate(active, w) {
        updateRenderObject(active, w, owner)
        return
    }
    let fresh = createRenderObject(w, owner, parent)
    parent.children = parent.children.filter { parent.isOutgoing($0) } + [fresh]
    if let active = active, parent.isMounted {
        parent.childReplaced(active, fresh)
    } else if let active = active {
        detachChild(active)
    }
    parent.markNeedsLayout()
}
