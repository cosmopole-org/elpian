package dev.elpian.core.godot

import dev.elpian.core.platform.GodotPlatformBinding
import dev.elpian.core.platform.Platforms
import dev.elpian.core.platform.platform
import dev.elpian.core.util.Json
import dev.elpian.core.util.jsString
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * The Godot controller — a port of `godot_binding.dart`, `godot_object.dart`
 * and `godot_controller.dart` (godot/controller.ts).
 *
 * Ops are queued and flushed once per turn (a whole scene build costs one
 * crossing); reads (`request`) flush the queue and await the engine's reply.
 * Signals come back by callback id. The [GodotBinding] is the transport: the
 * platform's native engine (Android OpQueue / iOS GodotRuntimeHost) or a
 * recording mock when no engine is present.
 *
 * The TypeScript Promises are `suspend` functions here.
 */
typealias GodotSignalCallback = (args: List<Any?>) -> Unit

interface GodotBinding {
    val isLive: Boolean
    suspend fun send(ops: List<Op>): List<Wire>
    fun post(ops: List<Op>)
    suspend fun mountSurface(surfaceId: Int, mountHandle: Long)
    suspend fun releaseSurface(surfaceId: Int)
    var onSignal: ((callbackId: Long, args: List<Any?>) -> Unit)?
    suspend fun stats(): Map<String, Any?>?
    fun dispose()
}

/** The transport over the platform's native engine bridge. */
class PlatformGodotBinding(private val native: GodotPlatformBinding) : GodotBinding {
    override var onSignal: ((callbackId: Long, args: List<Any?>) -> Unit)? = null

    init {
        native.setSignalHandler { cb, argsJson ->
            val args: List<Any?> = try {
                val parsed = Json.parse(argsJson)
                if (parsed is List<*>) parsed.toList() else listOf(parsed)
            } catch (_: Exception) {
                emptyList()
            }
            onSignal?.invoke(cb, args)
        }
    }

    override val isLive: Boolean get() = native.isLive

    override suspend fun send(ops: List<Op>): List<Wire> {
        if (ops.isEmpty()) return emptyList()
        val reply = native.send(encodeOps(ops))
        return if (reply.isNotEmpty()) decodeReplies(reply) else emptyList()
    }

    override fun post(ops: List<Op>) {
        if (ops.isNotEmpty()) native.post(encodeOps(ops))
    }

    override suspend fun mountSurface(surfaceId: Int, mountHandle: Long) {
        native.mountSurface(surfaceId, mountHandle)
    }

    override suspend fun releaseSurface(surfaceId: Int) {
        native.releaseSurface(surfaceId)
    }

    override suspend fun stats(): Map<String, Any?>? = native.stats()

    override fun dispose() {
        native.setSignalHandler(null)
    }
}

/** Records ops and echoes caller-allocated handles; used when no engine is linked. */
class MockGodotBinding : GodotBinding {
    val ops: MutableList<Op> = ArrayList()
    val surfaces: MutableMap<Int, Long> = LinkedHashMap()
    private var nextHostHandle = 1000000.0
    override var onSignal: ((callbackId: Long, args: List<Any?>) -> Unit)? = null

    override val isLive: Boolean get() = false

    private fun record(op: Op): Wire {
        ops.add(op)
        val produces = op.containsKey(OpKey.create) || op[OpKey.self] == true || op[OpKey.tree] == true ||
            op.containsKey(OpKey.singleton) || op.containsKey(OpKey.load)
        if (produces) {
            val def = op[OpKey.def]
            return if (def is Number && def.toDouble() != 0.0) def.toDouble() else nextHostHandle++
        }
        return null
    }

    override suspend fun send(ops: List<Op>): List<Wire> = ops.map { record(it) }

    override fun post(ops: List<Op>) {
        for (op in ops) record(op)
    }

    override suspend fun mountSurface(surfaceId: Int, mountHandle: Long) {
        surfaces[surfaceId] = mountHandle
    }

    override suspend fun releaseSurface(surfaceId: Int) {
        surfaces.remove(surfaceId)
    }

    fun fireSignal(callbackId: Long, args: List<Any?>) {
        onSignal?.invoke(callbackId, args)
    }

    fun clear() {
        ops.clear()
    }

    override suspend fun stats(): Map<String, Any?>? =
        linkedMapOf("pushed" to ops.size.toDouble(), "polls" to 0.0, "drained" to ops.size.toDouble())

    override fun dispose() {}
}

/**
 * `queueMicrotask`: run [fn] after the current turn on the platform's
 * dispatcher. Without an installed platform there is no event loop to defer
 * to, so [fn] runs at once.
 */
private fun scheduleMicrotask(fn: () -> Unit) {
    if (!Platforms.isInstalled) {
        fn()
        return
    }
    CoroutineScope(platform().dispatcher).launch { fn() }
}

/**
 * Start [block] now, like calling an `async` function without awaiting it
 * (`void promise`): it runs synchronously until its first suspension and
 * resumes on the platform dispatcher; failures are dropped as an unhandled
 * rejection would be.
 */
internal fun launchDetached(block: suspend () -> Unit) {
    val dispatcher = if (Platforms.isInstalled) platform().dispatcher else Dispatchers.Unconfined
    CoroutineScope(dispatcher).launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
        }
    }
}

class GodotController(val binding: GodotBinding, surfaceId: Int? = null) {
    val surfaceId: Int = surfaceId ?: nextSurfaceId++
    private val handles = HandleAllocator()
    private val callbacks = LinkedHashMap<Long, GodotSignalCallback>()
    private var pending: MutableList<Op> = ArrayList()
    private var nextCallbackId = 1L
    private var explicitBatch = false
    private var flushScheduled = false
    private var disposed = false
    private var mounted = false
    val root: GodotObject
    val g3: Godot3D
    private val listeners = LinkedHashSet<() -> Unit>()

    init {
        binding.onSignal = { id, args -> dispatchSignal(id, args) }
        root = GodotObject(this, HandleAllocator.selfHandle)
        g3 = Godot3D(this)
    }

    val isLive: Boolean get() = binding.isLive

    val pendingOps: Int get() = pending.size

    fun addListener(fn: () -> Unit) {
        listeners.add(fn)
    }

    fun removeListener(fn: () -> Unit) {
        listeners.remove(fn)
    }

    // ---- op submission ------------------------------------------------------

    fun enqueue(op: Op) {
        if (disposed) return
        pending.add(op)
        if (!explicitBatch) scheduleFlush()
    }

    suspend fun request(op: Op): Any? {
        if (disposed) return null
        val batch = ArrayList(pending).also { it.add(op) }
        pending = ArrayList()
        val replies = binding.send(batch)
        if (replies.size < batch.size) return null
        val reply = replies[batch.size - 1]
        if (isWireError(reply)) throw GodotOpException(wireErrorMessage(reply) ?: "engine error", op)
        return unmarshal(reply)
    }

    fun beginBatch() {
        explicitBatch = true
    }

    fun endBatch() {
        explicitBatch = false
        flush()
    }

    fun flush() {
        if (pending.isEmpty() || disposed) return
        val batch = pending
        pending = ArrayList()
        binding.post(batch)
    }

    private fun scheduleFlush() {
        if (flushScheduled) return
        flushScheduled = true
        scheduleMicrotask {
            flushScheduled = false
            flush()
        }
    }

    // ---- object creation (the GD facade) -----------------------------------

    fun create(className: String): GodotObject {
        val handle = handles.allocate()
        enqueue(linkedMapOf(OpKey.create to className, OpKey.def to handle.toDouble()))
        return GodotObject(this, handle)
    }

    fun createWith(className: String, properties: Map<String, Any?>): GodotObject {
        val node = create(className)
        node.setAll(properties)
        return node
    }

    fun singleton(name: String): GodotObject {
        val handle = handles.allocate()
        enqueue(linkedMapOf(OpKey.singleton to name, OpKey.def to handle.toDouble()))
        return GodotObject(this, handle)
    }

    fun tree(): GodotObject {
        val handle = handles.allocate()
        enqueue(linkedMapOf(OpKey.tree to true, OpKey.def to handle.toDouble()))
        return GodotObject(this, handle)
    }

    fun load(path: String): GodotObject {
        val handle = handles.allocate()
        enqueue(linkedMapOf(OpKey.load to path, OpKey.def to handle.toDouble()))
        return GodotObject(this, handle)
    }

    fun mount(node: GodotObject) {
        root.addChild(node)
    }

    suspend fun constant(name: String): Any? = request(linkedMapOf(OpKey.constant to name))

    suspend fun evaluate(expression: String, names: List<String> = emptyList(), values: List<Any?> = emptyList()): Any? =
        request(linkedMapOf(OpKey.expr to expression, OpKey.names to names, OpKey.values to marshalArgs(values)))

    suspend fun classes(): List<String> {
        val reply = request(linkedMapOf(OpKey.classes to true))
        return if (reply is List<*>) reply.map { jsString(it) } else emptyList()
    }

    @Suppress("UNCHECKED_CAST")
    suspend fun classInfo(className: String): Map<String, Any?> {
        val reply = request(linkedMapOf(OpKey.classInfo to className))
        return if (reply is Map<*, *>) reply as Map<String, Any?> else LinkedHashMap()
    }

    suspend fun audit(): Any? = request(linkedMapOf(OpKey.audit to true))

    suspend fun stats(): Map<String, Any?>? = binding.stats()

    fun renderingServer(): GodotObject = singleton("RenderingServer")
    fun physicsServer3D(): GodotObject = singleton("PhysicsServer3D")
    fun physicsServer2D(): GodotObject = singleton("PhysicsServer2D")
    fun audioServer(): GodotObject = singleton("AudioServer")
    fun displayServer(): GodotObject = singleton("DisplayServer")
    fun input(): GodotObject = singleton("Input")
    fun engine(): GodotObject = singleton("Engine")
    fun os(): GodotObject = singleton("OS")
    fun time(): GodotObject = singleton("Time")
    fun projectSettings(): GodotObject = singleton("ProjectSettings")
    fun resourceLoader(): GodotObject = singleton("ResourceLoader")

    // ---- callbacks ----------------------------------------------------------

    fun registerCallback(callback: GodotSignalCallback): Long {
        val id = nextCallbackId++
        callbacks[id] = callback
        return id
    }

    fun unregisterCallback(id: Long) {
        callbacks.remove(id)
    }

    fun callable(callback: GodotSignalCallback): GCallable = GCallable(registerCallback(callback))

    private fun dispatchSignal(id: Long, args: List<Any?>) {
        val callback = callbacks[id] ?: return
        callback(args.map { unmarshal(it) })
    }

    fun releaseHandle(handle: Long) {
        enqueue(linkedMapOf(OpKey.free to handle.toDouble(), "weak" to true))
    }

    // ---- surface lifecycle ---------------------------------------------------

    suspend fun attachSurface() {
        if (mounted || disposed) return
        mounted = true
        flush()
        binding.mountSurface(this.surfaceId, root.handle)
        for (l in listeners.toList()) l()
    }

    suspend fun detachSurface() {
        if (!mounted) return
        mounted = false
        binding.releaseSurface(this.surfaceId)
    }

    val isAttached: Boolean get() = mounted

    fun dispose() {
        if (disposed) return
        disposed = true
        pending = ArrayList()
        callbacks.clear()
        launchDetached { detachSurface() }
        binding.onSignal = null
        listeners.clear()
    }

    companion object {
        private var nextSurfaceId = 1
    }
}

class GodotObject(val controller: GodotController, val handle: Long) : GodotHandle {
    override val ref: GodotRef get() = GodotRef(handle)

    suspend fun call(method: String, args: List<Any?>? = null): Any? =
        controller.request(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.method to method, OpKey.args to marshalArgs(args)))

    fun callVoid(method: String, args: List<Any?>? = null) {
        controller.enqueue(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.method to method, OpKey.args to marshalArgs(args)))
    }

    suspend fun get(property: String): Any? = controller.request(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.get to property))

    fun set(property: String, value: Any?) {
        controller.enqueue(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.set to property, OpKey.value to marshal(value)))
    }

    fun setAll(properties: Map<String, Any?>) {
        if (properties.isEmpty()) return
        val props = LinkedHashMap<String, Any?>()
        for ((k, v) in properties) props[k] = marshal(v)
        controller.enqueue(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.props to props))
    }

    suspend fun getIndexed(path: String): Any? = controller.request(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.getIndexed to path))

    fun setIndexed(path: String, value: Any?) {
        controller.enqueue(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.setIndexed to path, OpKey.value to marshal(value)))
    }

    fun connect(signal: String, callback: GodotSignalCallback, flags: Int = 0): Long {
        val id = controller.registerCallback(callback)
        val op: Op = linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.connect to signal, OpKey.cb to id.toDouble())
        if (flags != 0) op[OpKey.flags] = flags.toDouble()
        controller.enqueue(op)
        return id
    }

    fun disconnect(signal: String, callbackId: Long) {
        controller.enqueue(linkedMapOf(OpKey.ref to handle.toDouble(), OpKey.disconnect to signal, OpKey.cb to callbackId.toDouble()))
        controller.unregisterCallback(callbackId)
    }

    fun signal(name: String): GSignal = GSignal(handle, name)

    fun emitSignal(name: String, args: List<Any?> = emptyList()) {
        callVoid("emit_signal", listOf<Any?>(name) + args)
    }

    fun addChild(child: GodotObject) {
        callVoid("add_child", listOf(child))
    }

    fun removeChild(child: GodotObject) {
        callVoid("remove_child", listOf(child))
    }

    fun addChildren(children: List<GodotObject>) {
        for (c in children) addChild(c)
    }

    fun queueFree() {
        callVoid("queue_free")
    }

    fun freeNow() {
        controller.enqueue(linkedMapOf(OpKey.free to handle.toDouble()))
    }

    fun release() {
        controller.releaseHandle(handle)
    }
}

/** The 3D convenience layer (`controller.g3`). */
class Godot3D(private val c: GodotController) {

    fun node(position: Any? = null, rotation: Any? = null, scale: Any? = null, visible: Boolean? = null): GodotObject {
        val n = c.create("Node3D")
        setTransform(n, position, rotation, scale, visible)
        return n
    }

    fun material(
        color: GodotColor? = null,
        metallic: Double? = null,
        roughness: Double? = null,
        emission: GodotColor? = null,
        emissionEnergy: Double? = null,
        transparency: Boolean = false,
    ): GodotObject {
        val m = c.create("StandardMaterial3D")
        m.set("albedo_color", color ?: GodotColor(0.8, 0.82, 0.9, 1.0))
        if (metallic != null) m.set("metallic", GFloat(metallic))
        if (roughness != null) m.set("roughness", GFloat(roughness))
        if (emission != null) {
            m.set("emission_enabled", true)
            m.set("emission", emission)
            if (emissionEnergy != null) m.set("emission_energy_multiplier", GFloat(emissionEnergy))
        }
        if (transparency) m.set("transparency", GInt(1.0))
        return m
    }

    fun primitive(shape: String, options: Map<String, Any?> = emptyMap()): GodotObject {
        fun n(key: String, fallback: Double): Double = (options[key] as? Number)?.toDouble() ?: fallback
        return when (shape) {
            "sphere" -> {
                val mesh = c.create("SphereMesh")
                val r = n("radius", 0.5)
                mesh.set("radius", GFloat(r))
                mesh.set("height", GFloat(n("height", r * 2)))
                mesh
            }
            "cylinder" -> {
                val mesh = c.create("CylinderMesh")
                val r = n("radius", 0.5)
                mesh.set("top_radius", GFloat(n("topRadius", r)))
                mesh.set("bottom_radius", GFloat(n("bottomRadius", r)))
                mesh.set("height", GFloat(n("height", 1.0)))
                mesh
            }
            "capsule" -> {
                val mesh = c.create("CapsuleMesh")
                mesh.set("radius", GFloat(n("radius", 0.4)))
                mesh.set("height", GFloat(n("height", 1.4)))
                mesh
            }
            "plane" -> {
                val mesh = c.create("PlaneMesh")
                mesh.set("size", Vector2(n("width", 2.0), n("depth", 2.0)))
                mesh
            }
            "prism" -> {
                val mesh = c.create("PrismMesh")
                mesh.set("size", vec3(options["size"], 1.0, 1.0, 1.0))
                mesh
            }
            "torus" -> {
                val mesh = c.create("TorusMesh")
                mesh.set("inner_radius", GFloat(n("innerRadius", 0.3)))
                mesh.set("outer_radius", GFloat(n("outerRadius", 0.6)))
                mesh
            }
            else -> {
                val mesh = c.create("BoxMesh")
                mesh.set("size", vec3(options["size"], 1.0, 1.0, 1.0))
                mesh
            }
        }
    }

    fun mesh(shape: String, options: Map<String, Any?> = emptyMap(), material: GodotObject? = null): GodotObject {
        val mi = c.create("MeshInstance3D")
        val prim = primitive(shape, options)
        prim.set(
            "material",
            material ?: this.material(
                color = options["color"] as? GodotColor,
                metallic = (options["metallic"] as? Number)?.toDouble(),
                roughness = (options["roughness"] as? Number)?.toDouble(),
                emission = options["emission"] as? GodotColor,
                emissionEnergy = (options["emissionEnergy"] as? Number)?.toDouble(),
                transparency = options["transparency"] == true,
            ),
        )
        mi.set("mesh", prim)
        setTransform(mi, options["position"], options["rotation"], options["scale"], options["visible"] as? Boolean)
        return mi
    }

    fun camera(fov: Double? = null, current: Boolean? = null, position: Any? = null, rotation: Any? = null): GodotObject {
        val cam = c.create("Camera3D")
        if (fov != null) cam.set("fov", GFloat(fov))
        if (current != false) cam.set("current", true)
        setTransform(cam, position = position, rotation = rotation)
        return cam
    }

    fun dirLight(color: GodotColor? = null, energy: Double? = null, shadow: Boolean = false, rotation: Any? = null, position: Any? = null): GodotObject {
        val l = c.create("DirectionalLight3D")
        l.set("light_color", color ?: GodotColor(1.0, 0.98, 0.92, 1.0))
        l.set("light_energy", GFloat(energy ?: 1.0))
        if (shadow) l.set("shadow_enabled", true)
        setTransform(l, position = position, rotation = rotation)
        return l
    }

    fun omniLight(color: GodotColor? = null, energy: Double? = null, range: Double? = null, position: Any? = null): GodotObject {
        val l = c.create("OmniLight3D")
        l.set("light_color", color ?: GodotColor(1.0, 1.0, 1.0, 1.0))
        l.set("light_energy", GFloat(energy ?: 1.0))
        if (range != null) l.set("omni_range", GFloat(range))
        setTransform(l, position = position)
        return l
    }

    fun spotLight(
        color: GodotColor? = null,
        energy: Double? = null,
        range: Double? = null,
        angle: Double? = null,
        position: Any? = null,
        rotation: Any? = null,
    ): GodotObject {
        val l = c.create("SpotLight3D")
        l.set("light_color", color ?: GodotColor(1.0, 1.0, 1.0, 1.0))
        l.set("light_energy", GFloat(energy ?: 1.0))
        if (range != null) l.set("spot_range", GFloat(range))
        if (angle != null) l.set("spot_angle", GFloat(angle))
        setTransform(l, position = position, rotation = rotation)
        return l
    }

    fun environment(bg: GodotColor? = null, ambient: GodotColor? = null, ambientEnergy: Double? = null): GodotObject {
        val we = c.create("WorldEnvironment")
        val env = c.create("Environment")
        env.set("background_mode", GInt(1.0))
        env.set("background_color", bg ?: GodotColor(0.05, 0.06, 0.09, 1.0))
        env.set("ambient_light_source", GInt(3.0))
        env.set("ambient_light_color", ambient ?: GodotColor(0.5, 0.55, 0.7, 1.0))
        env.set("ambient_light_energy", GFloat(ambientEnergy ?: 0.6))
        we.set("environment", env)
        return we
    }

    suspend fun instanceScene(path: String): GodotObject? {
        val packed = c.load(path)
        val instance = packed.call("instantiate")
        return if (instance is GodotRef) GodotObject(c, instance.id) else null
    }

    fun setTransform(node: GodotObject, position: Any? = null, rotation: Any? = null, scale: Any? = null, visible: Boolean? = null) {
        if (position != null) node.set("position", vec3(position, 0.0, 0.0, 0.0))
        if (rotation != null) node.set("rotation_degrees", vec3(rotation, 0.0, 0.0, 0.0))
        if (scale != null) node.set("scale", vec3(scale, 1.0, 1.0, 1.0))
        if (visible != null) node.set("visible", visible)
    }

    companion object {
        fun vec3(v: Any?, dx: Double, dy: Double, dz: Double): Vector3 {
            if (v is Vector3) return v
            if (v is Number) return v.toDouble().let { Vector3(it, it, it) }
            if (v is List<*> && v.size >= 3) return Vector3(jsNumber(v[0]), jsNumber(v[1]), jsNumber(v[2]))
            return Vector3(dx, dy, dz)
        }
    }
}
