import Foundation

/**
 * The Godot controller — a port of `godot_binding.dart`, `godot_object.dart`
 * and `godot_controller.dart` (godot/controller.ts).
 *
 * Ops are queued and flushed once per turn (a whole scene build costs one
 * crossing); reads (`request`) flush the queue and await the engine's reply.
 * Signals come back by callback id. The [GodotBinding] is the transport: the
 * platform's native engine (iOS GodotRuntimeHost / Android OpQueue) or a
 * recording mock when no engine is present.
 *
 * The TypeScript Promises are `async` functions here.
 */
public typealias GodotSignalCallback = (_ args: [Any?]) -> Void

public protocol GodotBinding: AnyObject {
    var isLive: Bool { get }
    func send(_ ops: [Op]) async throws -> [Wire]
    func post(_ ops: [Op])
    func mountSurface(_ surfaceId: Int, _ mountHandle: Int) async
    func releaseSurface(_ surfaceId: Int) async
    var onSignal: ((_ callbackId: Int, _ args: [Any?]) -> Void)? { get set }
    func stats() async -> JSONObject?
    func dispose()
}

/** The transport over the platform's native engine bridge. */
public final class PlatformGodotBinding: GodotBinding {
    private let native: GodotPlatformBinding
    public var onSignal: ((_ callbackId: Int, _ args: [Any?]) -> Void)?

    public init(_ native: GodotPlatformBinding) {
        self.native = native
        native.setSignalHandler { [weak self] cb, argsJson in
            var args: [Any?] = []
            if let parsed = try? JSON.parse(argsJson) {
                args = asArray(parsed) ?? [parsed]
            }
            self?.onSignal?(cb, args)
        }
    }

    public var isLive: Bool { native.isLive }

    public func send(_ ops: [Op]) async throws -> [Wire] {
        if ops.isEmpty { return [] }
        let reply = try await native.send(encodeOps(ops))
        return reply.isEmpty ? [] : try decodeReplies(reply)
    }

    public func post(_ ops: [Op]) {
        if !ops.isEmpty { native.post(encodeOps(ops)) }
    }

    public func mountSurface(_ surfaceId: Int, _ mountHandle: Int) async {
        native.mountSurface(surfaceId, mountHandle)
    }

    public func releaseSurface(_ surfaceId: Int) async {
        native.releaseSurface(surfaceId)
    }

    public func stats() async -> JSONObject? { await native.stats() }

    public func dispose() {
        native.setSignalHandler(nil)
    }
}

/** Records ops and echoes caller-allocated handles; used when no engine is linked. */
public final class MockGodotBinding: GodotBinding {
    public private(set) var ops: [Op] = []
    public private(set) var surfaces: [Int: Int] = [:]
    private var nextHostHandle = 1_000_000.0
    public var onSignal: ((_ callbackId: Int, _ args: [Any?]) -> Void)?

    public init() {}

    public var isLive: Bool { false }

    private func record(_ op: Op) -> Wire {
        ops.append(op)
        let produces = op.has(OpKey.create) || jsBool(op[OpKey.self_]) == true || jsBool(op[OpKey.tree]) == true ||
            op.has(OpKey.singleton) || op.has(OpKey.load)
        if produces {
            if let def = jsNumber(op[OpKey.def]), def != 0 { return def }
            let h = nextHostHandle
            nextHostHandle += 1
            return h
        }
        return nil
    }

    public func send(_ batch: [Op]) async throws -> [Wire] { batch.map { record($0) } }

    public func post(_ batch: [Op]) {
        for op in batch { _ = record(op) }
    }

    public func mountSurface(_ surfaceId: Int, _ mountHandle: Int) async {
        surfaces[surfaceId] = mountHandle
    }

    public func releaseSurface(_ surfaceId: Int) async {
        surfaces.removeValue(forKey: surfaceId)
    }

    public func fireSignal(_ callbackId: Int, _ args: [Any?]) {
        onSignal?(callbackId, args)
    }

    public func clear() {
        ops.removeAll()
    }

    public func stats() async -> JSONObject? {
        JSONObject([("pushed", Double(ops.count)), ("polls", 0.0), ("drained", Double(ops.count))])
    }

    public func dispose() {}
}

public final class GodotController {
    private static var nextSurfaceId = 1

    public let binding: GodotBinding
    public let surfaceId: Int
    private let handles = HandleAllocator()
    private var callbacks: [Int: GodotSignalCallback] = [:]
    private var pending: [Op] = []
    private var nextCallbackId = 1
    private var explicitBatch = false
    private var flushScheduled = false
    private var disposed = false
    private var mounted = false
    /** The surface root (`self` handle). Objects hold their controller; the controller holds none of them. */
    public var root: GodotObject { GodotObject(self, HandleAllocator.selfHandle) }
    /** The 3D convenience layer. */
    public var g3: Godot3D { Godot3D(self) }
    private var listeners: [(id: Int, fn: () -> Void)] = []
    private var nextListenerId = 1

    public init(_ binding: GodotBinding, surfaceId: Int? = nil) {
        self.binding = binding
        if let s = surfaceId {
            self.surfaceId = s
        } else {
            self.surfaceId = GodotController.nextSurfaceId
            GodotController.nextSurfaceId += 1
        }
        binding.onSignal = { [weak self] id, args in self?.dispatchSignal(id, args) }
    }

    public var isLive: Bool { binding.isLive }

    public var pendingOps: Int { pending.count }

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

    // ---- op submission ------------------------------------------------------

    public func enqueue(_ op: Op) {
        if disposed { return }
        pending.append(op)
        if !explicitBatch { scheduleFlush() }
    }

    /** Flush the queue with [op] last and await the engine's reply to [op]. */
    public func request(_ op: Op) async throws -> Any? {
        if disposed { return nil }
        let batch = pending + [op]
        pending = []
        let replies = try await binding.send(batch)
        if replies.count < batch.count { return nil }
        let reply = replies[batch.count - 1]
        if isWireError(reply) { throw GodotOpException(wireErrorMessage(reply) ?? "engine error", op: op) }
        return unmarshal(reply)
    }

    public func beginBatch() {
        explicitBatch = true
    }

    public func endBatch() {
        explicitBatch = false
        flush()
    }

    public func flush() {
        if pending.isEmpty || disposed { return }
        let batch = pending
        pending = []
        binding.post(batch)
    }

    private func scheduleFlush() {
        if flushScheduled { return }
        flushScheduled = true
        scheduleMicrotask { [weak self] in
            guard let self = self else { return }
            self.flushScheduled = false
            self.flush()
        }
    }

    // ---- object creation (the GD facade) -----------------------------------

    public func create(_ className: String) -> GodotObject {
        let handle = handles.allocate()
        enqueue(JSONObject([(OpKey.create, className), (OpKey.def, Double(handle))]))
        return GodotObject(self, handle)
    }

    public func createWith(_ className: String, _ properties: JSONObject) -> GodotObject {
        let node = create(className)
        node.setAll(properties)
        return node
    }

    public func singleton(_ name: String) -> GodotObject {
        let handle = handles.allocate()
        enqueue(JSONObject([(OpKey.singleton, name), (OpKey.def, Double(handle))]))
        return GodotObject(self, handle)
    }

    public func tree() -> GodotObject {
        let handle = handles.allocate()
        enqueue(JSONObject([(OpKey.tree, true), (OpKey.def, Double(handle))]))
        return GodotObject(self, handle)
    }

    public func load(_ path: String) -> GodotObject {
        let handle = handles.allocate()
        enqueue(JSONObject([(OpKey.load, path), (OpKey.def, Double(handle))]))
        return GodotObject(self, handle)
    }

    public func mount(_ node: GodotObject) {
        root.addChild(node)
    }

    public func constant(_ name: String) async throws -> Any? {
        try await request(JSONObject([(OpKey.constant, name)]))
    }

    public func evaluate(_ expression: String, names: [String] = [], values: [Any?] = []) async throws -> Any? {
        try await request(JSONObject([(OpKey.expr, expression), (OpKey.names, names.map { $0 as Any? }), (OpKey.values, marshalArgs(values))]))
    }

    public func classes() async throws -> [String] {
        let reply = try await request(JSONObject([(OpKey.classes, true)]))
        guard let a = asArray(reply) else { return [] }
        return a.map { jsString($0) }
    }

    public func classInfo(_ className: String) async throws -> JSONObject {
        let reply = try await request(JSONObject([(OpKey.classInfo, className)]))
        return asMap(reply) ?? JSONObject()
    }

    public func audit() async throws -> Any? { try await request(JSONObject([(OpKey.audit, true)])) }

    public func stats() async -> JSONObject? { await binding.stats() }

    public func renderingServer() -> GodotObject { singleton("RenderingServer") }
    public func physicsServer3D() -> GodotObject { singleton("PhysicsServer3D") }
    public func physicsServer2D() -> GodotObject { singleton("PhysicsServer2D") }
    public func audioServer() -> GodotObject { singleton("AudioServer") }
    public func displayServer() -> GodotObject { singleton("DisplayServer") }
    public func input() -> GodotObject { singleton("Input") }
    public func engine() -> GodotObject { singleton("Engine") }
    public func os() -> GodotObject { singleton("OS") }
    public func time() -> GodotObject { singleton("Time") }
    public func projectSettings() -> GodotObject { singleton("ProjectSettings") }
    public func resourceLoader() -> GodotObject { singleton("ResourceLoader") }

    // ---- callbacks ----------------------------------------------------------

    public func registerCallback(_ callback: @escaping GodotSignalCallback) -> Int {
        let id = nextCallbackId
        nextCallbackId += 1
        callbacks[id] = callback
        return id
    }

    public func unregisterCallback(_ id: Int) {
        callbacks.removeValue(forKey: id)
    }

    public func callable(_ callback: @escaping GodotSignalCallback) -> GCallable { GCallable(registerCallback(callback)) }

    private func dispatchSignal(_ id: Int, _ args: [Any?]) {
        guard let callback = callbacks[id] else { return }
        callback(args.map { unmarshal($0) })
    }

    public func releaseHandle(_ handle: Int) {
        enqueue(JSONObject([(OpKey.free, Double(handle)), ("weak", true)]))
    }

    // ---- surface lifecycle ---------------------------------------------------

    public func attachSurface() async {
        if mounted || disposed { return }
        mounted = true
        flush()
        await binding.mountSurface(surfaceId, root.handle)
        for l in listeners { l.fn() }
    }

    public func detachSurface() async {
        if !mounted { return }
        mounted = false
        await binding.releaseSurface(surfaceId)
    }

    public var isAttached: Bool { mounted }

    public func dispose() {
        if disposed { return }
        disposed = true
        pending = []
        callbacks.removeAll()
        launchDetached { [self] in await self.detachSurface() }
        binding.onSignal = nil
        listeners.removeAll()
    }
}

public final class GodotObject: GodotHandle {
    public let controller: GodotController
    public let handle: Int

    public init(_ controller: GodotController, _ handle: Int) {
        self.controller = controller
        self.handle = handle
    }

    public var ref: GodotRef { GodotRef(handle) }

    public func call(_ method: String, _ args: [Any?]? = nil) async throws -> Any? {
        try await controller.request(JSONObject([(OpKey.ref, Double(handle)), (OpKey.method, method), (OpKey.args, marshalArgs(args))]))
    }

    public func callVoid(_ method: String, _ args: [Any?]? = nil) {
        controller.enqueue(JSONObject([(OpKey.ref, Double(handle)), (OpKey.method, method), (OpKey.args, marshalArgs(args))]))
    }

    public func get(_ property: String) async throws -> Any? {
        try await controller.request(JSONObject([(OpKey.ref, Double(handle)), (OpKey.get, property)]))
    }

    public func set(_ property: String, _ value: Any?) {
        controller.enqueue(JSONObject([(OpKey.ref, Double(handle)), (OpKey.set, property), (OpKey.value, marshal(value))]))
    }

    public func setAll(_ properties: JSONObject) {
        if properties.isEmpty { return }
        let props = JSONObject()
        for (k, v) in properties { props[k] = marshal(v) }
        controller.enqueue(JSONObject([(OpKey.ref, Double(handle)), (OpKey.props, props)]))
    }

    public func getIndexed(_ path: String) async throws -> Any? {
        try await controller.request(JSONObject([(OpKey.ref, Double(handle)), (OpKey.getIndexed, path)]))
    }

    public func setIndexed(_ path: String, _ value: Any?) {
        controller.enqueue(JSONObject([(OpKey.ref, Double(handle)), (OpKey.setIndexed, path), (OpKey.value, marshal(value))]))
    }

    /** Connect [signal] to [callback]; returns the callback id for [disconnect]. */
    @discardableResult
    public func connect(_ signal: String, _ callback: @escaping GodotSignalCallback, flags: Int = 0) -> Int {
        let id = controller.registerCallback(callback)
        let op = JSONObject([(OpKey.ref, Double(handle)), (OpKey.connect, signal), (OpKey.cb, Double(id))])
        if flags != 0 { op[OpKey.flags] = Double(flags) }
        controller.enqueue(op)
        return id
    }

    public func disconnect(_ signal: String, _ callbackId: Int) {
        controller.enqueue(JSONObject([(OpKey.ref, Double(handle)), (OpKey.disconnect, signal), (OpKey.cb, Double(callbackId))]))
        controller.unregisterCallback(callbackId)
    }

    public func signal(_ name: String) -> GSignal { GSignal(handle, name) }

    public func emitSignal(_ name: String, _ args: [Any?] = []) {
        callVoid("emit_signal", [name] + args)
    }

    public func addChild(_ child: GodotObject) {
        callVoid("add_child", [child])
    }

    public func removeChild(_ child: GodotObject) {
        callVoid("remove_child", [child])
    }

    public func addChildren(_ children: [GodotObject]) {
        for c in children { addChild(c) }
    }

    public func queueFree() {
        callVoid("queue_free")
    }

    public func freeNow() {
        controller.enqueue(JSONObject([(OpKey.free, Double(handle))]))
    }

    public func release() {
        controller.releaseHandle(handle)
    }
}

/** The 3D convenience layer (`controller.g3`). */
public final class Godot3D {
    private let c: GodotController

    init(_ c: GodotController) {
        self.c = c
    }

    public func node(position: Any? = nil, rotation: Any? = nil, scale: Any? = nil, visible: Bool? = nil) -> GodotObject {
        let n = c.create("Node3D")
        setTransform(n, position: position, rotation: rotation, scale: scale, visible: visible)
        return n
    }

    public func material(color: GodotColor? = nil, metallic: Double? = nil, roughness: Double? = nil, emission: GodotColor? = nil,
                         emissionEnergy: Double? = nil, transparency: Bool = false) -> GodotObject {
        let m = c.create("StandardMaterial3D")
        m.set("albedo_color", color ?? GodotColor(0.8, 0.82, 0.9, 1))
        if let metallic = metallic { m.set("metallic", GFloat(metallic)) }
        if let roughness = roughness { m.set("roughness", GFloat(roughness)) }
        if let emission = emission {
            m.set("emission_enabled", true)
            m.set("emission", emission)
            if let e = emissionEnergy { m.set("emission_energy_multiplier", GFloat(e)) }
        }
        if transparency { m.set("transparency", GInt(1)) }
        return m
    }

    public func primitive(_ shape: String, _ options: JSONObject = JSONObject()) -> GodotObject {
        func n(_ key: String, _ fallback: Double) -> Double { jsNumber(options[key]) ?? fallback }
        switch shape {
        case "sphere":
            let mesh = c.create("SphereMesh")
            let r = n("radius", 0.5)
            mesh.set("radius", GFloat(r))
            mesh.set("height", GFloat(n("height", r * 2)))
            return mesh
        case "cylinder":
            let mesh = c.create("CylinderMesh")
            let r = n("radius", 0.5)
            mesh.set("top_radius", GFloat(n("topRadius", r)))
            mesh.set("bottom_radius", GFloat(n("bottomRadius", r)))
            mesh.set("height", GFloat(n("height", 1)))
            return mesh
        case "capsule":
            let mesh = c.create("CapsuleMesh")
            mesh.set("radius", GFloat(n("radius", 0.4)))
            mesh.set("height", GFloat(n("height", 1.4)))
            return mesh
        case "plane":
            let mesh = c.create("PlaneMesh")
            mesh.set("size", Vector2(n("width", 2), n("depth", 2)))
            return mesh
        case "prism":
            let mesh = c.create("PrismMesh")
            mesh.set("size", Godot3D.vec3(options["size"], 1, 1, 1))
            return mesh
        case "torus":
            let mesh = c.create("TorusMesh")
            mesh.set("inner_radius", GFloat(n("innerRadius", 0.3)))
            mesh.set("outer_radius", GFloat(n("outerRadius", 0.6)))
            return mesh
        default:
            let mesh = c.create("BoxMesh")
            mesh.set("size", Godot3D.vec3(options["size"], 1, 1, 1))
            return mesh
        }
    }

    public func mesh(_ shape: String, _ options: JSONObject = JSONObject(), material: GodotObject? = nil) -> GodotObject {
        let mi = c.create("MeshInstance3D")
        let prim = primitive(shape, options)
        prim.set("material", material ?? self.material(
            color: options["color"] as? GodotColor,
            metallic: jsNumber(options["metallic"]),
            roughness: jsNumber(options["roughness"]),
            emission: options["emission"] as? GodotColor,
            emissionEnergy: jsNumber(options["emissionEnergy"]),
            transparency: jsBool(options["transparency"]) == true
        ))
        mi.set("mesh", prim)
        setTransform(mi, position: options["position"], rotation: options["rotation"], scale: options["scale"], visible: jsBool(options["visible"]))
        return mi
    }

    public func camera(fov: Double? = nil, current: Bool? = nil, position: Any? = nil, rotation: Any? = nil) -> GodotObject {
        let cam = c.create("Camera3D")
        if let fov = fov { cam.set("fov", GFloat(fov)) }
        if current != false { cam.set("current", true) }
        setTransform(cam, position: position, rotation: rotation)
        return cam
    }

    public func dirLight(color: GodotColor? = nil, energy: Double? = nil, shadow: Bool = false, rotation: Any? = nil, position: Any? = nil) -> GodotObject {
        let l = c.create("DirectionalLight3D")
        l.set("light_color", color ?? GodotColor(1, 0.98, 0.92, 1))
        l.set("light_energy", GFloat(energy ?? 1))
        if shadow { l.set("shadow_enabled", true) }
        setTransform(l, position: position, rotation: rotation)
        return l
    }

    public func omniLight(color: GodotColor? = nil, energy: Double? = nil, range: Double? = nil, position: Any? = nil) -> GodotObject {
        let l = c.create("OmniLight3D")
        l.set("light_color", color ?? GodotColor(1, 1, 1, 1))
        l.set("light_energy", GFloat(energy ?? 1))
        if let range = range { l.set("omni_range", GFloat(range)) }
        setTransform(l, position: position)
        return l
    }

    public func spotLight(color: GodotColor? = nil, energy: Double? = nil, range: Double? = nil, angle: Double? = nil,
                          position: Any? = nil, rotation: Any? = nil) -> GodotObject {
        let l = c.create("SpotLight3D")
        l.set("light_color", color ?? GodotColor(1, 1, 1, 1))
        l.set("light_energy", GFloat(energy ?? 1))
        if let range = range { l.set("spot_range", GFloat(range)) }
        if let angle = angle { l.set("spot_angle", GFloat(angle)) }
        setTransform(l, position: position, rotation: rotation)
        return l
    }

    public func environment(bg: GodotColor? = nil, ambient: GodotColor? = nil, ambientEnergy: Double? = nil) -> GodotObject {
        let we = c.create("WorldEnvironment")
        let env = c.create("Environment")
        env.set("background_mode", GInt(1))
        env.set("background_color", bg ?? GodotColor(0.05, 0.06, 0.09, 1))
        env.set("ambient_light_source", GInt(3))
        env.set("ambient_light_color", ambient ?? GodotColor(0.5, 0.55, 0.7, 1))
        env.set("ambient_light_energy", GFloat(ambientEnergy ?? 0.6))
        we.set("environment", env)
        return we
    }

    public func instanceScene(_ path: String) async throws -> GodotObject? {
        let packed = c.load(path)
        let instance = try await packed.call("instantiate")
        if let r = instance as? GodotRef { return GodotObject(c, r.id) }
        return nil
    }

    public func setTransform(_ node: GodotObject, position: Any? = nil, rotation: Any? = nil, scale: Any? = nil, visible: Bool? = nil) {
        if flattenOptional(position) != nil { node.set("position", Godot3D.vec3(position, 0, 0, 0)) }
        if flattenOptional(rotation) != nil { node.set("rotation_degrees", Godot3D.vec3(rotation, 0, 0, 0)) }
        if flattenOptional(scale) != nil { node.set("scale", Godot3D.vec3(scale, 1, 1, 1)) }
        if let visible = visible { node.set("visible", visible) }
    }

    public static func vec3(_ value: Any?, _ dx: Double, _ dy: Double, _ dz: Double) -> Vector3 {
        let v = flattenOptional(value)
        if let v3 = v as? Vector3 { return v3 }
        if let n = jsNumber(v) { return Vector3(n, n, n) }
        if let a = asArray(v), a.count >= 3 { return Vector3(jsToNumber(a[0]), jsToNumber(a[1]), jsToNumber(a[2])) }
        return Vector3(dx, dy, dz)
    }
}
