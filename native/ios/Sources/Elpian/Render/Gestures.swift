#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * Per-pointer-down arena flags shared by the nested recognizers that see the
 * same down event (the DOM version marks the event object itself). The
 * innermost view's recognizer runs first, so outer ones see its claims.
 */
enum GestureArena {
    private static var key: String?
    static var tapClaimed = false
    static var panClaimed = false

    static func enter(_ k: String) {
        if k != key {
            key = k
            tapClaimed = false
            panClaimed = false
        }
    }
}

/**
 * Feeds every Elpian view's [GestureRecognizer] on a surface. Installed on the
 * [ElpianSurfaceView], it sees all touches next to normal UIKit delivery
 * (never cancelling or delaying them) and routes each touch to the recognizers
 * of the hit view and its Elpian ancestors, innermost first — the order
 * Android's dispatchTouchEvent gives (ElpianView.kt). A scroll container that
 * starts dragging cancels the touch for the views inside it (an intercept),
 * and a recognizer that claims a drag keeps enclosing scroll containers from
 * starting (requestDisallowInterceptTouchEvent).
 */
final class TouchRouter: UIGestureRecognizer {
    weak var surface: ElpianSurfaceView?
    /** Each live touch → the views whose recognizers follow it, innermost first. */
    private var chains: [ObjectIdentifier: [ElpianView]] = [:]
    private var touchesById: [ObjectIdentifier: UITouch] = [:]
    /** Views that asked their ancestors not to intercept the current gesture. */
    private var disallowing: [WeakView] = []

    private struct WeakView {
        weak var view: UIView?
    }

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /** A recognizer under [view] owns the drag: enclosing scroll containers must not start. */
    func requestDisallowIntercept(_ view: UIView) {
        disallowing.append(WeakView(view: view))
    }

    /** Whether a scroll container may begin its pan (no descendant claimed the gesture). */
    func allowsIntercept(by scroll: UIView) -> Bool {
        !disallowing.contains { w in w.view.map { $0.isDescendant(of: scroll) && $0 !== scroll } ?? false }
    }

    /** A scroll container took the gesture over: cancel the touch for every view inside it. */
    func cancelTouches(within container: UIView) {
        for (id, chain) in chains {
            guard let touch = touchesById[id] else { continue }
            let inside = chain.filter { $0.isDescendant(of: container) }
            if inside.isEmpty { continue }
            for v in inside { v.gestures?.touch(touch, phase: .cancelled, event: nil) }
            chains[id] = chain.filter { !$0.isDescendant(of: container) }
        }
    }

    private func chain(for touch: UITouch) -> [ElpianView] {
        var out: [ElpianView] = []
        var node: UIView? = touch.view
        while let n = node, n !== surface {
            if let e = n as? ElpianView, !e.pointerEventsNone { out.append(e) }
            node = n.superview
        }
        return out
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if chains.isEmpty { disallowing.removeAll() }
        for t in touches {
            let id = ObjectIdentifier(t)
            let c = chain(for: t)
            chains[id] = c
            touchesById[id] = t
            GestureArena.enter("\(id.hashValue)@\(t.timestamp)")
            for v in c { v.gestures?.touch(t, phase: .began, event: event) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches {
            for v in chains[ObjectIdentifier(t)] ?? [] { v.gestures?.touch(t, phase: .moved, event: event) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, .ended, event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, .cancelled, event)
    }

    private func finish(_ touches: Set<UITouch>, _ phase: UITouch.Phase, _ event: UIEvent) {
        for t in touches {
            let id = ObjectIdentifier(t)
            for v in chains[id] ?? [] { v.gestures?.touch(t, phase: phase, event: event) }
            chains.removeValue(forKey: id)
            touchesById.removeValue(forKey: id)
        }
        if chains.isEmpty {
            disallowing.removeAll()
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        chains.removeAll()
        touchesById.removeAll()
    }
}

/**
 * Gesture recognition on Elpian views with Flutter's arena semantics where it
 * matters (Gestures.kt / native/web/src/gestures.ts): the innermost tap
 * recognizer wins a tap, a pan beats a tap once the pointer moves past the
 * touch slop, a double-tap delays the single tap, long-press fires after
 * 500 ms without movement, and a fast pan end is also reported as a swipe.
 * Dismissible and Draggable gestures move the view (or a floating copy of it)
 * natively while they run.
 */
final class GestureRecognizer {
    static let SLOP = 18.0 // kTouchSlop
    static let DOUBLE_TAP_TIMEOUT = 0.3 // kDoubleTapTimeout
    static let LONG_PRESS_TIMEOUT = 0.5 // kLongPressTimeout
    static let SWIPE_VELOCITY = 600.0 // px/s (Dismissible's fling threshold is 700)
    private static let TAP_KINDS = ["tap", "doubletap", "longpress", "tapdown", "tapup", "tapcancel"]

    private(set) var kinds: Set<String> = []
    var dismissDirection = "horizontal"
    var dragData: Any?
    var tooltip: String?
    var ripple: Color?

    /** Positions in logical px relative to the surface. */
    private final class Tracked {
        var x: Double
        var y: Double
        let startX: Double
        let startY: Double
        init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
            startX = x
            startY = y
        }
    }

    private struct Sample {
        let t: Double
        let x: Double
        let y: Double
    }

    private struct C {
        let x: Double
        let y: Double
        let localX: Double
        let localY: Double
    }

    private weak var view: ElpianView?
    private var pointers: [(id: ObjectIdentifier, p: Tracked)] = []
    private var pointerIds: [ObjectIdentifier: Int] = [:]
    private var nextPointerId = 1
    private var mayPan = false
    private var panning = false
    private var claimed = false
    private var longPressTimer: DispatchWorkItem?
    private var longPressed = false
    private var lastTapTime = 0.0
    private var pendingTap: DispatchWorkItem?
    private var velocity: [Sample] = []
    private var scaleStart: (dist: Double, angle: Double)?
    private var dismissOffset = 0.0
    private var feedback: UIView?
    private var feedbackGrab = CGPoint.zero
    private var feedbackAlpha: CGFloat = 1
    private var tooltipView: UIView?
    private var tooltipTimer: DispatchWorkItem?
    private var tooltipHide: DispatchWorkItem?

    init(_ view: ElpianView) {
        self.view = view
    }

    func configure(_ list: [String]) {
        kinds = Set(list)
        if has("key") || has("focus") { view?.focusable = true }
        view?.setHoverEnabled(has("hover") || tooltip != nil)
    }

    func has(_ k: String) -> Bool { kinds.contains(k) }

    private func emit(_ type: String, _ c: C? = nil, dx: Double? = nil, dy: Double? = nil, vx: Double? = nil, vy: Double? = nil, scale: Double? = nil,
                      rotation: Double? = nil, buttons: Int? = nil, pressure: Double? = nil, pointerId: Int? = nil, direction: String? = nil,
                      data: Any? = nil, x: Double? = nil, y: Double? = nil) {
        guard let v = view else { return }
        v.host?.emit(ViewEvent(id: v.viewId, type: type, x: x ?? c?.x, y: y ?? c?.y, localX: c?.localX, localY: c?.localY, dx: dx, dy: dy, vx: vx, vy: vy,
                               scale: scale, rotation: rotation, buttons: buttons, pressure: pressure, pointerId: pointerId, direction: direction, data: data))
    }

    private func coords(_ t: UITouch) -> C {
        guard let v = view else { return C(x: 0, y: 0, localX: 0, localY: 0) }
        let s = t.location(in: v.host?.surface)
        let l = t.location(in: v)
        return C(x: Double(s.x), y: Double(s.y), localX: Double(l.x), localY: Double(l.y))
    }

    private func pressure(_ t: UITouch) -> Double {
        t.maximumPossibleForce > 0 && t.force > 0 ? Double(t.force / t.maximumPossibleForce) : 1
    }

    private func tracked(_ id: ObjectIdentifier) -> Tracked? { pointers.first { $0.id == id }?.p }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) -> DispatchWorkItem {
        let w = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
        return w
    }

    // ---------------------------------------------------------------------
    // Pointer stream
    // ---------------------------------------------------------------------

    /** Feed one touch phase (routed by the surface's [TouchRouter]). */
    func touch(_ t: UITouch, phase: UITouch.Phase, event: UIEvent?) {
        if kinds.isEmpty && ripple == nil { return }
        switch phase {
        case .began: down(t, event)
        case .moved: move(t)
        case .ended: up(t, cancelled: false)
        case .cancelled: up(t, cancelled: true)
        default: break
        }
    }

    private func down(_ t: UITouch, _ event: UIEvent?) {
        let mouse = t.type == .indirectPointer
        if mouse, let e = event, e.buttonMask.contains(.secondary), !has("pointer") { return }
        let c = coords(t)
        let oid = ObjectIdentifier(t)
        let pid = nextPointerId
        nextPointerId += 1
        pointerIds[oid] = pid
        if has("pointer") {
            emit("pointerdown", c, buttons: mouse ? Int(event?.buttonMask.rawValue ?? 1) : 1, pressure: pressure(t), pointerId: pid)
        }
        pointers.append((oid, Tracked(c.x, c.y)))
        if pointers.count == 2 && has("scale") {
            beginScale()
            return
        }
        if pointers.count > 1 { return }

        let inner = GestureArena.tapClaimed
        let tapping = GestureRecognizer.TAP_KINDS.contains { has($0) }
        claimed = tapping && !inner
        if claimed { GestureArena.tapClaimed = true }
        // Drags: the innermost recognizer that drags wins (Flutter's arena).
        let drags = has("pan") || has("swipe") || has("draggable") || has("dismiss")
        mayPan = drags && !GestureArena.panClaimed
        if mayPan { GestureArena.panClaimed = true }
        // Like `touch-action: none`: ancestors (scroll views) must not steal this drag.
        if (mayPan && (has("pan") || has("draggable"))) || has("scale") || has("pointer") { disallowIntercept() }
        panning = false
        longPressed = false
        velocity = [Sample(t: t.timestamp, x: c.x, y: c.y)]
        if claimed {
            if has("tapdown") { emit("tapdown", c) }
            if has("longpress") || tooltip != nil {
                longPressTimer = after(GestureRecognizer.LONG_PRESS_TIMEOUT) { [weak self] in
                    guard let self = self else { return }
                    self.longPressTimer = nil
                    self.longPressed = true
                    if self.has("longpress") { self.emit("longpress", c) }
                    if self.tooltip != nil { self.showTooltip() }
                }
            }
        }
        if ripple != nil && !inner { view?.startRipple(at: CGPoint(x: c.localX, y: c.localY)) }
    }

    private func disallowIntercept() {
        guard let v = view, let router = v.host?.surface.router else { return }
        router.requestDisallowIntercept(v)
    }

    private func move(_ t: UITouch) {
        let oid = ObjectIdentifier(t)
        guard let p = tracked(oid) else { return }
        let c = coords(t)
        let dx = c.x - p.x
        let dy = c.y - p.y
        if dx == 0 && dy == 0 { return }
        p.x = c.x
        p.y = c.y
        if has("pointer") { emit("pointermove", c, dx: dx, dy: dy, buttons: 1, pressure: pressure(t), pointerId: pointerIds[oid]) }
        if scaleStart != nil && pointers.count >= 2 {
            updateScale()
            return
        }
        if pointers.first?.id != oid { return }
        velocity.append(Sample(t: t.timestamp, x: c.x, y: c.y))
        if velocity.count > 20 { velocity.removeFirst() }
        let tx = c.x - p.startX
        let ty = c.y - p.startY
        let travelled = hypot(tx, ty)
        if !panning && travelled > GestureRecognizer.SLOP {
            cancelLongPress()
            if claimed && has("tapcancel") { emit("tapcancel") }
            claimed = false
            view?.stopRipple()
            if mayPan {
                panning = true
                if has("dismiss") {
                    if isVerticalDismiss() == (abs(ty) > abs(tx)) { disallowIntercept() }
                } else {
                    disallowIntercept()
                }
                if has("pan") { emit("dragstart", c) }
                if has("draggable") { startFeedback(c) }
            }
        }
        if panning {
            if has("pan") { emit("drag", c, dx: dx, dy: dy) }
            if has("draggable") { moveFeedback(c) }
            if has("dismiss") { dragDismiss(tx, ty) }
        }
    }

    private func up(_ t: UITouch, cancelled: Bool) {
        let oid = ObjectIdentifier(t)
        guard let idx = pointers.firstIndex(where: { $0.id == oid }) else { return }
        pointers.remove(at: idx)
        let pid = pointerIds.removeValue(forKey: oid)
        let c = coords(t)
        if has("pointer") { emit(cancelled ? "pointercancel" : "pointerup", c, pointerId: pid) }
        if scaleStart != nil {
            if pointers.count < 2 {
                scaleStart = nil
                emit("scaleend")
            }
            return
        }
        if !pointers.isEmpty && !panning { return }
        cancelLongPress()
        view?.stopRipple()
        let v = flingVelocity()
        if panning {
            panning = false
            if has("pan") { emit("dragend", c, vx: v.0, vy: v.1) }
            if has("swipe") && max(abs(v.0), abs(v.1)) > GestureRecognizer.SWIPE_VELOCITY {
                let direction = abs(v.0) > abs(v.1) ? (v.0 < 0 ? "left" : "right") : (v.1 < 0 ? "up" : "down")
                emit("swipe", vx: v.0, vy: v.1, direction: direction)
            }
            if has("draggable") { endFeedback(c, cancelled) }
            if has("dismiss") { endDismiss(v) }
            return
        }
        if cancelled || !claimed || longPressed {
            if claimed && has("tapcancel") && cancelled { emit("tapcancel") }
            return
        }
        if has("tapup") { emit("tapup", c) }
        let now = t.timestamp
        if has("doubletap") {
            if let pending = pendingTap, now - lastTapTime < GestureRecognizer.DOUBLE_TAP_TIMEOUT {
                pending.cancel()
                pendingTap = nil
                emit("doubletap", c)
                return
            }
            lastTapTime = now
            // The single tap waits for the double-tap window, as in Flutter.
            pendingTap = after(GestureRecognizer.DOUBLE_TAP_TIMEOUT) { [weak self] in
                guard let self = self else { return }
                self.pendingTap = nil
                if self.has("tap") { self.emit("tap", c) }
            }
            return
        }
        if has("tap") { emit("tap", c) }
    }

    /** Accessibility activation (VoiceOver double-tap): a plain tap at the centre. */
    func accessibilityTap() {
        guard has("tap"), let v = view else { return }
        let lx = Double(v.bounds.width) / 2
        let ly = Double(v.bounds.height) / 2
        let s = v.convert(CGPoint(x: lx, y: ly), to: v.host?.surface)
        emit("tap", C(x: Double(s.x), y: Double(s.y), localX: lx, localY: ly))
    }

    private func flingVelocity() -> (Double, Double) {
        let s = velocity
        guard s.count >= 2, let last = s.last else { return (0, 0) }
        var first = s[0]
        for p in s where last.t - p.t <= 0.1 {
            first = p
            break
        }
        let dt = last.t - first.t
        if dt <= 0 { return (0, 0) }
        return ((last.x - first.x) / dt, (last.y - first.y) / dt)
    }

    private func cancelLongPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    // ---------------------------------------------------------------------
    // Hover, keys, focus
    // ---------------------------------------------------------------------

    func onHover(_ g: UIHoverGestureRecognizer) {
        guard let v = view else { return }
        let s = g.location(in: v.host?.surface)
        let l = g.location(in: v)
        let c = C(x: Double(s.x), y: Double(s.y), localX: Double(l.x), localY: Double(l.y))
        switch g.state {
        case .began:
            if has("hover") { emit("pointerenter", c) }
            if tooltip != nil {
                tooltipTimer = after(GestureRecognizer.LONG_PRESS_TIMEOUT) { [weak self] in self?.showTooltip() }
            }
        case .changed:
            if has("hover") { emit("pointerhover", c) }
        case .ended, .cancelled:
            if has("hover") { emit("pointerexit", c) }
            if tooltip != nil { hideTooltip() }
        default:
            break
        }
    }

    func onKey(_ type: String, _ press: UIPress) -> Bool {
        guard has("key"), let k = press.key, let v = view else { return false }
        let name = HostKeys.name(k)
        let code = HostKeys.domKeyCode(k)
        let m = k.modifierFlags
        v.host?.emit(ViewEvent(id: v.viewId, type: type, key: name, keyCode: code, altKey: m.contains(.alternate), ctrlKey: m.contains(.control),
                               shiftKey: m.contains(.shift), metaKey: m.contains(.command)))
        if type == "keydown" && name.count == 1 {
            v.host?.emit(ViewEvent(id: v.viewId, type: "keypress", key: name, keyCode: code, altKey: m.contains(.alternate), ctrlKey: m.contains(.control),
                                   shiftKey: m.contains(.shift), metaKey: m.contains(.command)))
        }
        return true
    }

    func onFocus(_ gained: Bool) {
        if has("focus") { emit(gained ? "focus" : "blur") }
    }

    // ---------------------------------------------------------------------
    // Scale (pinch / rotate)
    // ---------------------------------------------------------------------

    private func beginScale() {
        cancelLongPress()
        claimed = false
        view?.stopRipple()
        let a = pointers[0].p
        let b = pointers[1].p
        let d = hypot(b.x - a.x, b.y - a.y)
        scaleStart = (d != 0 ? d : 1, atan2(b.y - a.y, b.x - a.x))
        emit("scalestart", scale: 1, rotation: 0, x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private func updateScale() {
        guard let s = scaleStart else { return }
        let a = pointers[0].p
        let b = pointers[1].p
        emit("scaleupdate", scale: hypot(b.x - a.x, b.y - a.y) / s.dist, rotation: atan2(b.y - a.y, b.x - a.x) - s.angle, x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    // ---------------------------------------------------------------------
    // Dismissible
    // ---------------------------------------------------------------------

    private func isVerticalDismiss() -> Bool {
        dismissDirection.contains("vertical") || dismissDirection.contains("up") || dismissDirection.contains("down")
    }

    private func dragDismiss(_ dx: Double, _ dy: Double) {
        let dir = dismissDirection
        let vertical = isVerticalDismiss()
        var d = vertical ? dy : dx
        if dir == "endToStart" && d > 0 { d = 0 }
        if dir == "startToEnd" && d < 0 { d = 0 }
        if dir == "up" && d > 0 { d = 0 }
        if dir == "down" && d < 0 { d = 0 }
        dismissOffset = d
        view?.layer.removeAllAnimations()
        setDismiss(d, vertical)
    }

    private func setDismiss(_ d: Double, _ vertical: Bool) {
        guard let v = view else { return }
        v.gestureDx = vertical ? 0 : CGFloat(d)
        v.gestureDy = vertical ? CGFloat(d) : 0
        v.applyTransform()
    }

    private func endDismiss(_ vel: (Double, Double)) {
        guard let v = view else { return }
        let vertical = isVerticalDismiss()
        let extent = Double(vertical ? v.bounds.height : v.bounds.width)
        let fling = vertical ? vel.1 : vel.0
        let d = dismissOffset
        let sgnD: Double = d > 0 ? 1 : (d < 0 ? -1 : 0)
        let sgnF: Double = fling > 0 ? 1 : (fling < 0 ? -1 : 0)
        let passes = abs(d) > extent * 0.4 || (abs(fling) > 700 && sgnF == sgnD && d != 0)
        let target = passes ? (sgnD != 0 ? sgnD : 1) * extent : 0
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.setDismiss(target, vertical)
        })
        if !passes {
            dismissOffset = 0
            return
        }
        let sgn = sgnD != 0 ? sgnD : 1
        let direction = vertical ? (sgn < 0 ? "up" : "down") : (sgn < 0 ? "endToStart" : "startToEnd")
        _ = after(0.2) { [weak self] in self?.emit("dismissed", direction: direction) }
    }

    // ---------------------------------------------------------------------
    // Draggable
    // ---------------------------------------------------------------------

    private func startFeedback(_ c: C) {
        guard let v = view, let root = v.host?.surface else { return }
        if v.bounds.width > 0 && v.bounds.height > 0, let snap = v.snapshotView(afterScreenUpdates: false) {
            let origin = v.convert(CGPoint.zero, to: root)
            snap.frame = CGRect(origin: origin, size: v.bounds.size)
            snap.alpha = 0.7
            snap.isUserInteractionEnabled = false
            snap.layer.zPosition = 100_000
            root.addSubview(snap)
            feedbackGrab = CGPoint(x: c.x - Double(origin.x), y: c.y - Double(origin.y))
            feedback = snap
        }
        feedbackAlpha = v.alpha
        v.alpha = 0.3
        emit("dragstart", c, data: dragData)
    }

    private func moveFeedback(_ c: C) {
        if let f = feedback {
            f.frame.origin = CGPoint(x: c.x - Double(feedbackGrab.x), y: c.y - Double(feedbackGrab.y))
        }
        emit("dragupdate", data: dragData, x: c.x, y: c.y)
    }

    private func endFeedback(_ c: C, _ cancelled: Bool) {
        removeFeedback()
        view?.alpha = feedbackAlpha
        emit(cancelled ? "dragend" : "drop", data: dragData, x: c.x, y: c.y)
    }

    private func removeFeedback() {
        feedback?.removeFromSuperview()
        feedback = nil
    }

    // ---------------------------------------------------------------------
    // Tooltip
    // ---------------------------------------------------------------------

    private func showTooltip() {
        guard let text = tooltip, tooltipView == nil, let v = view, let window = v.window else { return }
        // Material Tooltip: grey 700 @ 90%, 4 px radius, 12 px white text, 24 px below.
        let label = PaddedLabel()
        label.text = text
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 12)
        label.backgroundColor = Paints.uiColor(0xE661_6161)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isUserInteractionEnabled = false
        let size = label.sizeThatFits(CGSize(width: window.bounds.width - 16, height: .greatestFiniteMagnitude))
        let h = max(24, size.height)
        let center = v.convert(CGPoint(x: v.bounds.midX, y: v.bounds.maxY), to: window)
        var x = center.x - size.width / 2
        x = max(8, min(window.bounds.width - size.width - 8, x))
        label.frame = CGRect(x: x, y: center.y + 24 - h / 2, width: size.width, height: h)
        window.addSubview(label)
        tooltipView = label
        tooltipHide = after(1.5) { [weak self] in self?.hideTooltip() }
    }

    private func hideTooltip() {
        tooltipTimer?.cancel()
        tooltipTimer = nil
        tooltipHide?.cancel()
        tooltipHide = nil
        tooltipView?.removeFromSuperview()
        tooltipView = nil
    }

    /** The view left the window: drop timers and floating feedback. */
    func detached() {
        cancelLongPress()
        pendingTap?.cancel()
        pendingTap = nil
        hideTooltip()
        removeFeedback()
    }

    func dispose() {
        detached()
        view?.layer.removeAllAnimations()
        pointers.removeAll()
        pointerIds.removeAll()
        view?.stopRipple()
    }
}

/** A label with Material tooltip padding (8 × 4). */
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(CGSize(width: size.width - insets.left - insets.right, height: size.height))
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

/** DOM `KeyboardEvent.key` / `keyCode` for UIKit hardware keys. */
enum HostKeys {
    static func name(_ k: UIKey) -> String {
        switch k.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter: return "Enter"
        case .keyboardEscape: return "Escape"
        case .keyboardDeleteOrBackspace: return "Backspace"
        case .keyboardDeleteForward: return "Delete"
        case .keyboardTab: return "Tab"
        case .keyboardSpacebar: return " "
        case .keyboardUpArrow: return "ArrowUp"
        case .keyboardDownArrow: return "ArrowDown"
        case .keyboardLeftArrow: return "ArrowLeft"
        case .keyboardRightArrow: return "ArrowRight"
        case .keyboardHome: return "Home"
        case .keyboardEnd: return "End"
        case .keyboardPageUp: return "PageUp"
        case .keyboardPageDown: return "PageDown"
        case .keyboardLeftShift, .keyboardRightShift: return "Shift"
        case .keyboardLeftControl, .keyboardRightControl: return "Control"
        case .keyboardLeftAlt, .keyboardRightAlt: return "Alt"
        case .keyboardLeftGUI, .keyboardRightGUI: return "Meta"
        case .keyboardCapsLock: return "CapsLock"
        case .keyboardInsert: return "Insert"
        case .keyboardF1: return "F1"
        case .keyboardF2: return "F2"
        case .keyboardF3: return "F3"
        case .keyboardF4: return "F4"
        case .keyboardF5: return "F5"
        case .keyboardF6: return "F6"
        case .keyboardF7: return "F7"
        case .keyboardF8: return "F8"
        case .keyboardF9: return "F9"
        case .keyboardF10: return "F10"
        case .keyboardF11: return "F11"
        case .keyboardF12: return "F12"
        default:
            let s = k.characters
            if let u = s.unicodeScalars.first, s.unicodeScalars.count == 1, u.properties.generalCategory == .control { return "Unidentified" }
            return s.isEmpty ? "Unidentified" : s
        }
    }

    static func domKeyCode(_ k: UIKey) -> Int {
        switch k.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter: return 13
        case .keyboardDeleteOrBackspace: return 8
        case .keyboardTab: return 9
        case .keyboardEscape: return 27
        case .keyboardSpacebar: return 32
        case .keyboardPageUp: return 33
        case .keyboardPageDown: return 34
        case .keyboardEnd: return 35
        case .keyboardHome: return 36
        case .keyboardLeftArrow: return 37
        case .keyboardUpArrow: return 38
        case .keyboardRightArrow: return 39
        case .keyboardDownArrow: return 40
        case .keyboardInsert: return 45
        case .keyboardDeleteForward: return 46
        case .keyboardLeftShift, .keyboardRightShift: return 16
        case .keyboardLeftControl, .keyboardRightControl: return 17
        case .keyboardLeftAlt, .keyboardRightAlt: return 18
        default:
            let raw = k.keyCode.rawValue
            // HID usage: a–z 0x04…0x1D, 1–9 0x1E…0x26, 0 0x27, F1–F12 0x3A…0x45.
            if raw >= 0x04 && raw <= 0x1D { return 65 + raw - 0x04 }
            if raw >= 0x1E && raw <= 0x26 { return 49 + raw - 0x1E }
            if raw == 0x27 { return 48 }
            if raw >= 0x3A && raw <= 0x45 { return 112 + raw - 0x3A }
            return raw
        }
    }
}
#endif
