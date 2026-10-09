import Foundation

/**
 * The declarative scene DSL and the scene controller — ports of
 * `scene_dsl.dart` and `GodotSceneController` (scene3d_widget.dart),
 * via godot/scene.ts.
 *
 * ```json
 * { "environment": { "bg": "#0d1117", "ambient": "#8894b0" },
 *   "camera": { "position": [0, 3, 8], "rotation": [-18, 0, 0], "fov": 55 },
 *   "lights": [ { "type": "directional", "energy": 1.3, "shadow": true, "rotation": [-50, -30, 0] } ],
 *   "nodes":  [ { "type": "mesh", "shape": "torus", "id": "ring", "color": "#6699ff",
 *                 "position": [0, 1, 0], "children": [ … ] } ] }
 * ```
 */
public final class GodotScene {
    public let controller: GodotController
    /** Nodes by their DSL `id`. */
    public let nodesById: [String: GodotObject]
    public let roots: [GodotObject]

    public init(_ controller: GodotController, _ nodesById: [String: GodotObject], _ roots: [GodotObject]) {
        self.controller = controller
        self.nodesById = nodesById
        self.roots = roots
    }

    public func byId(_ id: String) -> GodotObject? { nodesById[id] }

    public func require(_ id: String) throws -> GodotObject {
        guard let node = byId(id) else { throw ElpianError("no node with id \"\(id)\" in the scene") }
        return node
    }
}

/** `#RRGGBB`, `#RRGGBBAA`, `#RGB`, `[r,g,b(,a)]` (0..1) or a GodotColor. */
public func parseGodotColor(_ value: Any?) -> GodotColor? {
    guard let value = flattenOptional(value) else { return nil }
    if let c = value as? GodotColor { return c }
    if let a = asArray(value), a.count >= 3 {
        func at(_ i: Int, _ f: Double) -> Double { i < a.count ? (jsNumber(a[i]) ?? f) : f }
        return GodotColor(at(0, 0), at(1, 0), at(2, 0), at(3, 1))
    }
    if let s = value as? String, s.hasPrefix("#") {
        var hex = jsSubstring(s, 1)
        if jsLength(hex) == 3 {
            hex = String(decoding: hex.utf16.flatMap { [$0, $0] }, as: UTF16.self)
        }
        let len = jsLength(hex)
        if len != 6 && len != 8 { return nil }
        let rgb = jsParseInt(jsSubstring(hex, 0, 6), 16)
        if !rgb.isFinite { return nil }
        var alpha = 1.0
        if len == 8 {
            let a = jsParseInt(jsSubstring(hex, 6, 8), 16)
            if a.isFinite { alpha = a / 255 }
        }
        return GodotColor.hex(Int(rgb), alpha)
    }
    return nil
}

private func looksLikeColor(_ v: String) -> Bool {
    let n = jsLength(v)
    return v.hasPrefix("#") && (n == 7 || n == 9 || n == 4)
}

/**
 * `v && typeof v === 'object'` read as a record: a map as it is, an array as
 * its index-keyed entries; nil for anything else.
 */
private func objectSpec(_ v: Any?) -> JSONObject? {
    if let m = asMap(v) { return m }
    if let a = asArray(v) {
        let m = JSONObject()
        for (i, e) in a.enumerated() { m[String(i)] = e }
        return m
    }
    return nil
}

public final class SceneDsl {
    public let controller: GodotController

    public init(_ controller: GodotController) {
        self.controller = controller
    }

    public func build(_ json: JSONObject) -> GodotScene {
        var byId: [String: GodotObject] = [:]
        var roots: [GodotObject] = []
        let c = controller
        c.beginBatch()
        defer { c.endBatch() }
        if let env = objectSpec(json["environment"]) {
            let node = environment(env)
            c.mount(node)
            roots.append(node)
        }
        if let cameraSpec = objectSpec(json["camera"]) {
            let node = camera(cameraSpec)
            c.mount(node)
            roots.append(node)
            register(&byId, cameraSpec, node)
        }
        if let lights = asArray(json["lights"]) {
            for entry in lights {
                guard let lightSpec = objectSpec(entry) else { continue }
                let node = light(lightSpec)
                c.mount(node)
                roots.append(node)
                register(&byId, lightSpec, node)
            }
        }
        if let nodes = asArray(json["nodes"]) {
            for entry in nodes {
                guard let spec = objectSpec(entry), let built = self.node(spec, &byId) else { continue }
                c.mount(built)
                roots.append(built)
            }
        }
        return GodotScene(c, byId, roots)
    }

    private func register(_ byId: inout [String: GodotObject], _ spec: JSONObject, _ node: GodotObject) {
        if let id = spec["id"] as? String, id != "" { byId[id] = node }
    }

    private func environment(_ spec: JSONObject) -> GodotObject {
        controller.g3.environment(
            bg: parseGodotColor(spec["bg"]),
            ambient: parseGodotColor(spec["ambient"]),
            ambientEnergy: jsNumber(spec["ambientEnergy"]) ?? 0.6
        )
    }

    private func camera(_ spec: JSONObject) -> GodotObject {
        controller.g3.camera(
            fov: jsNumber(spec["fov"]),
            current: jsBool(spec["current"]) != false,
            position: spec["position"],
            rotation: spec["rotation"]
        )
    }

    private func light(_ spec: JSONObject) -> GodotObject {
        let g3 = controller.g3
        func num(_ v: Any?, _ f: Double) -> Double { jsNumber(v) ?? f }
        switch spec["type"] as? String {
        case "omni", "point":
            return g3.omniLight(color: parseGodotColor(spec["color"]), energy: num(spec["energy"], 1), range: jsNumber(spec["range"]),
                                position: spec["position"])
        case "spot":
            return g3.spotLight(
                color: parseGodotColor(spec["color"]),
                energy: num(spec["energy"], 1),
                range: jsNumber(spec["range"]),
                angle: jsNumber(spec["angle"]),
                position: spec["position"],
                rotation: spec["rotation"]
            )
        default:
            return g3.dirLight(color: parseGodotColor(spec["color"]), energy: num(spec["energy"], 1), shadow: jsBool(spec["shadow"]) == true,
                               rotation: spec["rotation"], position: spec["position"])
        }
    }

    private func node(_ spec: JSONObject, _ byId: inout [String: GodotObject]) -> GodotObject? {
        let type = (spec["type"] as? String) ?? "node"
        let c = controller
        let built: GodotObject
        switch type {
        case "mesh":
            let options = spec.copy()
            if spec["color"] != nil { options["color"] = parseGodotColor(spec["color"]) }
            if spec["emission"] != nil { options["emission"] = parseGodotColor(spec["emission"]) }
            built = c.g3.mesh((spec["shape"] as? String) ?? "box", options)
        case "node", "group":
            built = c.g3.node(position: spec["position"], rotation: spec["rotation"], scale: spec["scale"], visible: jsBool(spec["visible"]))
        case "camera":
            built = camera(spec)
        case "light":
            built = light(spec)
        default:
            // Any other value is a raw ClassDB class name.
            built = c.create(type)
            c.g3.setTransform(built, position: spec["position"], rotation: spec["rotation"], scale: spec["scale"], visible: jsBool(spec["visible"]))
        }
        if let props = objectSpec(spec["props"]) {
            let coerced = JSONObject()
            for (k, v) in props {
                if let s = v as? String, looksLikeColor(s) {
                    coerced[k] = parseGodotColor(s) ?? s
                } else {
                    coerced[k] = v
                }
            }
            built.setAll(coerced)
        }
        register(&byId, spec, built)
        if let children = asArray(spec["children"]) {
            for entry in children {
                guard let child = objectSpec(entry) else { continue }
                if let childNode = node(child, &byId) { built.addChild(childNode) }
            }
        }
        return built
    }
}

/** `GodotSceneController`: owns the engine controller and the built scene across renders. */
public final class GodotSceneController {
    public let godot: GodotController
    private var current: GodotScene?
    private var disposed = false
    private var listeners: [(id: Int, fn: () -> Void)] = []
    private var nextListenerId = 1

    public init(_ binding: GodotBinding) {
        godot = GodotController(binding)
    }

    public var scene: GodotScene? { current }

    public var isLive: Bool { godot.isLive }

    public func node(_ id: String) -> GodotObject? { current?.byId(id) }

    public func adopt(_ scene: GodotScene) {
        current = scene
        if !disposed { for l in listeners { l.fn() } }
    }

    @discardableResult
    public func replaceScene(_ json: JSONObject) -> GodotScene {
        for root in current?.roots ?? [] { root.queueFree() }
        let built = SceneDsl(godot).build(json)
        adopt(built)
        return built
    }

    /** Returns a token for [removeListener]. */
    @discardableResult
    public func addListener(_ fn: @escaping () -> Void) -> Int {
        let id = nextListenerId
        nextListenerId += 1
        listeners.append((id, fn))
        return id
    }

    public func removeListener(_ token: Int) {
        listeners.removeAll { $0.id == token }
    }

    public func dispose() {
        if disposed { return }
        disposed = true
        godot.dispose()
        listeners.removeAll()
    }
}
