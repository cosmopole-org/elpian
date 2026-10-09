#if canImport(UIKit)
import UIKit
import os.log
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/** What the renderer needs from its platform. */
public protocol RendererHooks: AnyObject {
    /** Report an event for a view (the session dispatches it to the core). */
    func emit(_ event: ViewEvent)
    /** An image's natural size became known (0×0 = failed). */
    func imageLoaded(_ src: String, _ width: Int, _ height: Int)
    /** Load an image (the platform's cache). */
    func loadImage(_ src: String, _ callback: @escaping (UIImage?) -> Void)
    /** The Godot surface provider for `scene3d` views, when an engine is attached. */
    func godotSurfaces() -> GodotSurfaceProvider?
}

public extension RendererHooks {
    func godotSurfaces() -> GodotSurfaceProvider? { nil }
}

private final class HookImages: ImageSource {
    weak var hooks: RendererHooks?
    init(_ hooks: RendererHooks) { self.hooks = hooks }
    func load(_ src: String, _ callback: @escaping (UIImage?) -> Void) {
        guard let h = hooks else { return callback(nil) }
        h.loadImage(src, callback)
    }
}

/**
 * Applies the core's view operations to a tree of UIKit views under an
 * [ElpianSurfaceView] (ViewRenderer.kt on Android, DomRenderer on the web).
 *
 * Every view is an [ElpianView] positioned at the frame the core laid out
 * (logical px = points). A view paints its decoration itself so its frame
 * stays the border box Flutter lays children out in, and clipping applies to
 * its content without clipping its own shadow — Flutter's Container +
 * ClipRRect. Leaf kinds map onto native content views: paragraphs, images,
 * controls, canvases, media, web pages, the Godot surface and
 * host-registered native components.
 */
public final class ViewRenderer: ViewHost {
    private final class Rec {
        let id: Int
        let kind: ViewKind
        let view: ElpianView?
        var props = JSONObject()
        var children: [Int] = []
        var parent: Int
        var native: NativeComponentInstance?

        init(id: Int, kind: ViewKind, view: ElpianView?, parent: Int) {
            self.id = id
            self.kind = kind
            self.view = view
            self.parent = parent
        }
    }

    public let root: ElpianSurfaceView
    private let hooks: RendererHooks
    private var views: [Int: Rec] = [:]
    public private(set) var scale: CGFloat
    var surface: ElpianSurfaceView { root }
    let images: ImageSource
    private static let log = OSLog(subsystem: "dev.elpian", category: "renderer")

    public init(root: ElpianSurfaceView, hooks: RendererHooks) {
        self.root = root
        self.hooks = hooks
        scale = root.window?.screen.scale ?? UIScreen.main.scale
        images = HookImages(hooks)
        views[ROOT_VIEW_ID] = Rec(id: ROOT_VIEW_ID, kind: .view, view: nil, parent: -1)
    }

    func emit(_ event: ViewEvent) { hooks.emit(event) }

    /** The live view for [id] (tests and host integrations). */
    public func viewFor(_ id: Int) -> ElpianView? { views[id]?.view }

    /** The `scene3d` host showing Godot surface [surfaceId]. */
    public func scene3dContainer(_ surfaceId: Int) -> UIView? {
        for r in views.values {
            if let l = r.view?.leaf as? Scene3dLeaf, l.surfaceId == surfaceId { return l }
        }
        return nil
    }

    public func apply(_ ops: [ViewOp], scale: CGFloat? = nil) {
        if let s = scale, s != self.scale {
            self.scale = s
            repaintAll()
        }
        for op in ops {
            switch op {
            case let .create(id, kind, parent, index, props): create(id, kind, parent, index, props)
            case let .update(id, props): update(id, props)
            case let .move(id, parent, index): move(id, parent, index)
            case let .remove(id): remove(id)
            case let .command(id, name, args): command(id, name, args)
            }
        }
    }

    // ---------------------------------------------------------------------
    // Tree
    // ---------------------------------------------------------------------

    private func hostOf(_ rec: Rec) -> UIView { rec.view?.childHost ?? root }

    private func create(_ id: Int, _ kind: ViewKind, _ parent: Int, _ index: Int, _ props: ViewProps) {
        if views[id] != nil { remove(id) }
        let view = ElpianView(id: id, kind: kind, host: self)
        let rec = Rec(id: id, kind: kind, view: view, parent: parent)
        views[id] = rec
        buildLeaf(rec)
        insert(rec, parent, index)
        update(id, props)
    }

    private func insert(_ rec: Rec, _ parent: Int, _ index: Int) {
        guard let p = views[parent] ?? views[ROOT_VIEW_ID], let v = rec.view else { return }
        rec.parent = p.id
        p.children.removeAll { $0 == rec.id }
        let i = min(max(0, index), p.children.count)
        p.children.insert(rec.id, at: i)
        let host = hostOf(p)
        v.removeFromSuperview()
        var placed = false
        if i + 1 < p.children.count {
            for j in (i + 1)..<p.children.count {
                if let next = views[p.children[j]]?.view, next.superview === host {
                    host.insertSubview(v, belowSubview: next)
                    placed = true
                    break
                }
            }
        }
        if !placed { host.addSubview(v) }
    }

    private func move(_ id: Int, _ parent: Int, _ index: Int) {
        guard let rec = views[id], let newParent = views[parent] ?? views[ROOT_VIEW_ID] else { return }
        // Already in place: keep the view attached (focus, playback, scroll survive).
        if rec.parent == newParent.id && newParent.children.firstIndex(of: id) == index { return }
        views[rec.parent]?.children.removeAll { $0 == id }
        insert(rec, parent, index)
    }

    private func remove(_ id: Int) {
        guard let rec = views[id] else { return }
        views[rec.parent]?.children.removeAll { $0 == id }
        disposeTree(rec)
        rec.view?.removeFromSuperview()
    }

    private func disposeTree(_ rec: Rec) {
        for c in rec.children { if let r = views[c] { disposeTree(r) } }
        rec.view?.gestures?.dispose()
        rec.view?.setEffects(nil, nil)
        rec.view?.setBackdrop(nil)
        switch rec.view?.leaf {
        case let m as MediaLeaf: m.release()
        case let w as WebLeaf: w.release()
        case let s as Scene3dLeaf: s.release()
        case let c as CanvasLeafView: c.release()
        default: break
        }
        rec.native?.dispose()
        rec.native = nil
        views.removeValue(forKey: rec.id)
    }

    /** Remove every view (unmount). */
    public func clear() {
        guard let r = views[ROOT_VIEW_ID] else { return }
        for c in r.children { remove(c) }
        root.subviews.forEach { $0.removeFromSuperview() }
    }

    /** Re-run every canvas and re-measure text (scale or font change). */
    public func repaintAll() {
        for rec in views.values {
            (rec.view?.leaf as? CanvasLeafView)?.repaint()
            rec.view?.decoration?.layout(for: rec.view?.bounds.size ?? .zero, scale: scale)
        }
        TextEngine.clearCache()
    }

    // ---------------------------------------------------------------------
    // Leaves
    // ---------------------------------------------------------------------

    private func buildLeaf(_ rec: Rec) {
        guard let v = rec.view else { return }
        let leaf: UIView?
        switch rec.kind {
        case .text: leaf = TextLeafView(owner: v)
        case .image:
            leaf = ImageLeafView(owner: v) { [weak self] src, img in
                guard let self = self else { return }
                if let img = img, let cg = img.cgImage {
                    self.hooks.imageLoaded(src, cg.width, cg.height)
                    self.emit(ViewEvent(id: rec.id, type: "load", value: JSONObject([("width", Double(cg.width)), ("height", Double(cg.height))])))
                } else {
                    self.hooks.imageLoaded(src, 0, 0)
                    self.emit(ViewEvent(id: rec.id, type: "error"))
                }
            }
        case .scroll:
            let s = ScrollContainer(owner: v)
            v.childHost = s
            leaf = s
        case .textInput: leaf = TextInputLeaf(owner: v)
        case .checkbox: leaf = CheckboxView(owner: v)
        case .radio: leaf = RadioView(owner: v)
        case .switch: leaf = SwitchView(owner: v)
        case .slider: leaf = SliderView(owner: v)
        case .select: leaf = SelectLeaf(owner: v)
        case .progress: leaf = ProgressView(owner: v)
        case .canvas: leaf = CanvasLeafView(owner: v)
        case .scene3d: leaf = Scene3dLeaf { [weak self] in self?.hooks.godotSurfaces() }
        case .video: leaf = MediaLeaf(owner: v, video: true)
        case .audio: leaf = MediaLeaf(owner: v, video: false)
        case .web: leaf = WebLeaf(owner: v)
        default: leaf = nil
        }
        if let l = leaf {
            v.leaf = l
            l.frame = v.contentView.bounds
            v.contentView.insertSubview(l, at: 0)
        }
    }

    // ---------------------------------------------------------------------
    // Props
    // ---------------------------------------------------------------------

    private func update(_ id: Int, _ patch: ViewProps) {
        guard let rec = views[id], let v = rec.view else { return }
        for (k, value) in patch {
            if flattenOptional(value) == nil { rec.props.removeValue(forKey: k) } else { rec.props[k] = value }
        }
        let p = rec.props
        func has(_ k: String) -> Bool { patch.has(k) }
        let frameChanged = has("frame")

        if frameChanged, let f = HostProps.doubles(p["frame"]), f.count >= 4 { v.setFrame(f) }
        if has("opacity") { v.alpha = CGFloat(min(1, max(0, HostProps.num(p["opacity"]) ?? 1))) }
        if has("transform") || has("transformOrigin") { v.setTransform(HostProps.matrix(p["transform"]), HostProps.doubles(p["transformOrigin"])) }
        if has("hidden") { v.isHidden = HostProps.bool(p["hidden"]) }
        if has("pointerEvents") { v.pointerEventsNone = HostProps.str(p["pointerEvents"]) == "none" }
        if has("cursor") { v.applyCursor(HostProps.str(p["cursor"])) }
        if has("zIndex") { v.zIndex = HostProps.num(p["zIndex"]) ?? 0 }
        if has("filter") || has("blendMode") { v.setEffects(flattenOptional(p["filter"]) as? Filter, HostProps.str(p["blendMode"])) }
        if has("shaderMask") { v.shaderMask = flattenOptional(p["shaderMask"]) as? Gradient }
        if has("backdropFilter") { v.setBackdrop(flattenOptional(p["backdropFilter"]) as? Filter) }
        if has("role") { v.role = HostProps.str(p["role"]) }

        let decoKeys = ["background", "gradients", "backgroundImage", "border", "radius", "oval", "shadows", "outline"]
        if decoKeys.contains(where: { has($0) }) { applyDecoration(rec) }
        if has("clip") || has("radius") || has("oval") {
            v.clip = HostProps.bool(p["clip"])
            v.radius = flattenOptional(p["radius"]) as? BorderRadius
            v.oval = HostProps.bool(p["oval"])
            v.updateClip()
            v.updateRippleMask()
        }
        if ["gestures", "ripple", "tooltip", "dragData", "dismissDirection", "focusable"].contains(where: { has($0) }) { applyGestures(rec) }
        if has("semanticsLabel") || has("tooltip") || has("role") || has("gestures") {
            v.updateAccessibility(label: HostProps.str(p["semanticsLabel"]) ?? HostProps.str(p["tooltip"]))
        }
        updateHitOpaque(rec)
        applyLeaf(rec, patch, frameChanged)
    }

    private func applyDecoration(_ rec: Rec) {
        guard let v = rec.view else { return }
        let p = rec.props
        let gradients = HostProps.typed(p["gradients"], Gradient.self) ?? []
        let shadows = HostProps.typed(p["shadows"], BoxShadow.self) ?? []
        let needs = p["background"] != nil || !gradients.isEmpty || p["backgroundImage"] != nil || p["border"] != nil || !shadows.isEmpty || p["outline"] != nil
        if !needs {
            v.removeDecoration()
            return
        }
        let deco = v.ensureDecoration()
        deco.background = HostProps.color(p["background"])
        deco.gradients = gradients
        deco.setImage(flattenOptional(p["backgroundImage"]) as? DecorationImage, images)
        deco.border = flattenOptional(p["border"]) as? Border
        deco.radius = flattenOptional(p["radius"]) as? BorderRadius
        deco.oval = HostProps.bool(p["oval"])
        deco.shadows = shadows
        deco.outline = flattenOptional(p["outline"]) as? Outline
        deco.clearCaches()
        deco.layout(for: v.bounds.size, scale: scale)
    }

    /** Opaque to hits (HitTestBehavior.opaque / a painted box), so siblings below do not get the touch. */
    private func updateHitOpaque(_ rec: Rec) {
        guard let v = rec.view else { return }
        let p = rec.props
        v.hitOpaque = !(HostProps.list(p["gestures"]) ?? []).isEmpty || p["background"] != nil || !(HostProps.list(p["gradients"]) ?? []).isEmpty
            || p["backgroundImage"] != nil || p["ripple"] != nil
    }

    private func applyGestures(_ rec: Rec) {
        guard let v = rec.view else { return }
        let p = rec.props
        let kinds = HostProps.strings(p["gestures"])
        let ripple = HostProps.color(p["ripple"])
        let tooltip = HostProps.str(p["tooltip"])
        let wants = !kinds.isEmpty || ripple != nil || tooltip != nil
        if !wants {
            v.gestures?.dispose()
            v.gestures = nil
            v.rippleColor = nil
            v.setHoverEnabled(false)
        } else {
            let g = v.gestures ?? GestureRecognizer(v)
            v.gestures = g
            g.dismissDirection = HostProps.str(p["dismissDirection"]) ?? "horizontal"
            g.dragData = p["dragData"]
            g.tooltip = tooltip
            g.ripple = ripple
            g.configure(kinds)
            v.rippleColor = ripple
        }
        if HostProps.bool(p["focusable"]) { v.focusable = true }
    }

    private func applyLeaf(_ rec: Rec, _ patch: ViewProps, _ frameChanged: Bool) {
        guard let v = rec.view else { return }
        let p = rec.props
        func has(_ k: String) -> Bool { patch.has(k) }
        let colors = HostProps.map(p["colors"]) ?? JSONObject()
        switch v.leaf {
        case let leaf as TextLeafView:
            if has("text") { leaf.setSpec(flattenOptional(p["text"]) as? TextSpec) }
        case let leaf as ImageLeafView:
            if has("fit") { leaf.fit = HostProps.fit(p["fit"]) ?? "contain" }
            if has("alignment") { leaf.alignment = HostProps.alignment(p["alignment"]) ?? .center }
            if has("tint") { leaf.tint = HostProps.color(p["tint"]) }
            if has("alt") {
                leaf.accessibilityLabel = HostProps.str(p["alt"])
                leaf.isAccessibilityElement = leaf.accessibilityLabel != nil
                leaf.accessibilityTraits = .image
            }
            if has("src") { leaf.setSrc(HostProps.str(p["src"])) }
        case let leaf as ScrollContainer:
            if has("contentSize"), let cs = HostProps.doubles(p["contentSize"]) { leaf.setContentSize(cs.count > 0 ? cs[0] : 0, cs.count > 1 ? cs[1] : 0) }
            if has("scrollAxis") { leaf.axis = HostProps.str(p["scrollAxis"]) ?? "vertical" }
            if has("scrollEnabled") { leaf.scrollingEnabled = !HostProps.isFalse(p["scrollEnabled"]) }
            if has("showScrollbar") { leaf.showScrollbar = !HostProps.isFalse(p["showScrollbar"]) }
            if has("scrollTo"), let s = HostProps.doubles(patch["scrollTo"]), s.count >= 2 { leaf.scrollToLogical(s[0], s[1], smooth: false) }
        case let leaf as TextInputLeaf:
            leaf.apply(p, patch)
        case let leaf as CheckboxView:
            if has("checked") { leaf.checked = HostProps.bool(p["checked"]) }
            if has("enabled") { leaf.enabledState = !HostProps.isFalse(p["enabled"]) }
            if has("colors") { leaf.colors = colors }
        case let leaf as RadioView:
            if has("checked") { leaf.checked = HostProps.bool(p["checked"]) }
            if has("value") { leaf.value = p["value"] }
            if has("enabled") { leaf.enabledState = !HostProps.isFalse(p["enabled"]) }
            if has("colors") { leaf.colors = colors }
        case let leaf as SwitchView:
            if has("checked") { leaf.checked = HostProps.bool(p["checked"]) }
            if has("enabled") { leaf.enabledState = !HostProps.isFalse(p["enabled"]) }
            if has("colors") { leaf.colors = colors }
        case let leaf as SliderView:
            if has("min") { leaf.min = HostProps.num(p["min"]) ?? 0 }
            if has("max") { leaf.max = HostProps.num(p["max"]) ?? 1 }
            if has("step") { leaf.step = HostProps.num(p["step"]).flatMap { $0 > 0 ? $0 : nil } }
            if has("value") { leaf.value = HostProps.num(p["value"]) ?? 0 }
            if has("enabled") { leaf.enabledState = !HostProps.isFalse(p["enabled"]) }
            if has("colors") { leaf.colors = colors }
            leaf.setNeedsDisplay()
        case let leaf as SelectLeaf:
            leaf.apply(p, patch)
        case let leaf as ProgressView:
            leaf.setVariant(HostProps.str(p["variant"]) == "circular")
            leaf.strokeWidth = HostProps.num(p["strokeWidth"])
            if has("colors") { leaf.colors = colors }
            leaf.value = jsNumber(flattenOptional(p["value"]))
            leaf.accessibilityValue = leaf.value.map { "\(Int(jsRound($0 * 100)))%" }
        case let leaf as CanvasLeafView:
            if has("background") { leaf.backgroundColorValue = HostProps.color(p["background"]) }
            if let cmds = asArray(patch["commands"]) {
                leaf.replace(cmds)
            } else if frameChanged && leaf.commands != nil {
                leaf.repaint()
            }
            if let more = asArray(patch["appendCommands"]) { leaf.append(more) }
        case let leaf as Scene3dLeaf:
            if has("surfaceId") { leaf.setSurface(HostProps.int(p["surfaceId"])) }
            if has("clickable") { v.applyCursor(HostProps.bool(p["clickable"]) ? "pointer" : HostProps.str(p["cursor"])) }
        case let leaf as MediaLeaf:
            if has("autoplay") { leaf.autoplay = HostProps.bool(p["autoplay"]) }
            if has("loop") { leaf.loop = HostProps.bool(p["loop"]) }
            if has("muted") { leaf.muted = HostProps.bool(p["muted"]) }
            if has("controls") { leaf.controls = !HostProps.isFalse(p["controls"]) }
            if has("fit") { leaf.fit = HostProps.fit(p["fit"]) ?? "contain" }
            if has("poster") { leaf.setPoster(HostProps.str(p["poster"])) }
            if has("tracks") { leaf.setTracks((HostProps.list(p["tracks"]) ?? []).compactMap { asMap($0) }) }
            if has("src") { leaf.setSrc(HostProps.str(p["src"])) }
        case let leaf as WebLeaf:
            leaf.apply(p, patch)
        default:
            if rec.kind == .native { applyNative(rec, patch) }
        }
    }

    private func applyNative(_ rec: Rec, _ patch: ViewProps) {
        guard let v = rec.view else { return }
        let p = rec.props
        let name = HostProps.str(p["component"])
        let props = HostProps.map(p["componentProps"]) ?? JSONObject()
        if patch.has("component"), let name = name, !name.isEmpty {
            if let n = rec.native {
                n.dispose()
                n.view.removeFromSuperview()
            }
            rec.native = nil
            v.leaf = nil
            guard let factory = NativeComponents.factory(name) else {
                os_log("no native component registered as \"%{public}@\"", log: ViewRenderer.log, type: .info, name)
                return
            }
            let id = rec.id
            let inst = factory(props) { [weak self] type, value in self?.emit(ViewEvent(id: id, type: type, value: value)) }
            inst.view.removeFromSuperview()
            inst.view.frame = v.contentView.bounds
            inst.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.contentView.insertSubview(inst.view, at: 0)
            v.leaf = inst.view
            rec.native = inst
        } else if patch.has("componentProps") {
            rec.native?.update(props)
        }
    }

    // ---------------------------------------------------------------------
    // Commands
    // ---------------------------------------------------------------------

    private func command(_ id: Int, _ name: String, _ args: Any?) {
        guard let rec = views[id], let v = rec.view else { return }
        let leaf = v.leaf
        switch name {
        case "focus":
            switch leaf {
            case let t as TextInputLeaf: t.focusAndShowKeyboard()
            case let s as SelectLeaf: s.open()
            case nil:
                v.focusable = true
                _ = v.becomeFirstResponder()
            default:
                _ = leaf?.becomeFirstResponder()
            }
        case "blur":
            if let t = leaf as? TextInputLeaf { t.blurAndHideKeyboard() } else { _ = v.resignFirstResponder() }
        case "play": (leaf as? MediaLeaf)?.play()
        case "pause": (leaf as? MediaLeaf)?.pause()
        case "seek": if let s = HostProps.num(args) { (leaf as? MediaLeaf)?.seek(s) }
        case "scrollTo": if let a = HostProps.doubles(args), a.count >= 2 { (leaf as? ScrollContainer)?.scrollToLogical(a[0], a[1], smooth: true) }
        case "jumpTo": if let a = HostProps.doubles(args), a.count >= 2 { (leaf as? ScrollContainer)?.scrollToLogical(a[0], a[1], smooth: false) }
        case "selectAll": (leaf as? TextInputLeaf)?.selectAll()
        case "open": (leaf as? SelectLeaf)?.open()
        case "draw", "appendCommands": if let l = asArray(args) { (leaf as? CanvasLeafView)?.append(l) }
        case "commands": if let l = asArray(args) { (leaf as? CanvasLeafView)?.replace(l) }
        case "clear": (leaf as? CanvasLeafView)?.replace([])
        case "repaint": (leaf as? CanvasLeafView)?.repaint()
        default: break
        }
    }
}
#endif
