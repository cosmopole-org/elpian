package dev.elpian.core.godot

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
class GodotScene(
    val controller: GodotController,
    val nodesById: Map<String, GodotObject>,
    val roots: List<GodotObject>,
) {
    fun byId(id: String): GodotObject? = nodesById[id]

    fun require(id: String): GodotObject = nodesById[id] ?: throw IllegalStateException("no node with id \"$id\" in the scene")
}

/** `#RRGGBB`, `#RRGGBBAA`, `#RGB`, `[r,g,b(,a)]` (0..1) or a GodotColor. */
fun parseGodotColor(value: Any?): GodotColor? {
    if (value == null) return null
    if (value is GodotColor) return value
    if (value is List<*> && value.size >= 3) {
        fun at(i: Int, f: Double): Double = (value.getOrNull(i) as? Number)?.toDouble() ?: f
        return GodotColor(at(0, 0.0), at(1, 0.0), at(2, 0.0), at(3, 1.0))
    }
    if (value is String && value.startsWith("#")) {
        var hex = value.substring(1)
        if (hex.length == 3) hex = hex.map { "$it$it" }.joinToString("")
        if (hex.length != 6 && hex.length != 8) return null
        val rgb = parseIntHex(hex.substring(0, 6)) ?: return null
        var alpha = 1.0
        if (hex.length == 8) {
            val a = parseIntHex(hex.substring(6, 8))
            if (a != null) alpha = a / 255.0
        }
        return GodotColor.hex(rgb.toInt(), alpha)
    }
    return null
}

/** JavaScript `parseInt(s, 16)`: the longest hex prefix (after whitespace, sign and `0x`); null for NaN. */
private fun parseIntHex(s: String): Long? {
    var t = s.trimStart()
    var negative = false
    if (t.startsWith("-") || t.startsWith("+")) {
        negative = t[0] == '-'
        t = t.substring(1)
    }
    if (t.startsWith("0x") || t.startsWith("0X")) t = t.substring(2)
    val digits = t.takeWhile { Character.digit(it, 16) >= 0 && it.code < 128 }
    if (digits.isEmpty()) return null
    val v = digits.toLong(16)
    return if (negative) -v else v
}

private fun looksLikeColor(v: String): Boolean = v.startsWith("#") && (v.length == 7 || v.length == 9 || v.length == 4)

/**
 * `v && typeof v === 'object'` read as a record: a map as it is, an array as
 * its index-keyed entries; null for anything else.
 */
@Suppress("UNCHECKED_CAST")
private fun objectSpec(v: Any?): Map<String, Any?>? = when (v) {
    is Map<*, *> -> v as Map<String, Any?>
    is List<*> -> LinkedHashMap<String, Any?>().also { m -> v.forEachIndexed { i, e -> m[i.toString()] = e } }
    else -> null
}

class SceneDsl(val controller: GodotController) {

    fun build(json: Map<String, Any?>): GodotScene {
        val byId = LinkedHashMap<String, GodotObject>()
        val roots = ArrayList<GodotObject>()
        val c = controller
        c.beginBatch()
        try {
            val env = objectSpec(json["environment"])
            if (env != null) {
                val node = environment(env)
                c.mount(node)
                roots.add(node)
            }
            val cameraSpec = objectSpec(json["camera"])
            if (cameraSpec != null) {
                val node = camera(cameraSpec)
                c.mount(node)
                roots.add(node)
                register(byId, cameraSpec, node)
            }
            val lights = json["lights"]
            if (lights is List<*>) {
                for (entry in lights) {
                    val lightSpec = objectSpec(entry) ?: continue
                    val node = light(lightSpec)
                    c.mount(node)
                    roots.add(node)
                    register(byId, lightSpec, node)
                }
            }
            val nodes = json["nodes"]
            if (nodes is List<*>) {
                for (entry in nodes) {
                    val spec = objectSpec(entry) ?: continue
                    val node = node(spec, byId) ?: continue
                    c.mount(node)
                    roots.add(node)
                }
            }
        } finally {
            c.endBatch()
        }
        return GodotScene(c, byId, roots)
    }

    private fun register(byId: MutableMap<String, GodotObject>, spec: Map<String, Any?>, node: GodotObject) {
        val id = spec["id"]
        if (id is String && id != "") byId[id] = node
    }

    private fun environment(spec: Map<String, Any?>): GodotObject = controller.g3.environment(
        bg = parseGodotColor(spec["bg"]),
        ambient = parseGodotColor(spec["ambient"]),
        ambientEnergy = (spec["ambientEnergy"] as? Number)?.toDouble() ?: 0.6,
    )

    private fun camera(spec: Map<String, Any?>): GodotObject = controller.g3.camera(
        fov = (spec["fov"] as? Number)?.toDouble(),
        current = spec["current"] != false,
        position = spec["position"],
        rotation = spec["rotation"],
    )

    private fun light(spec: Map<String, Any?>): GodotObject {
        val g3 = controller.g3
        fun num(v: Any?, f: Double): Double = (v as? Number)?.toDouble() ?: f
        return when (spec["type"]) {
            "omni", "point" -> g3.omniLight(
                color = parseGodotColor(spec["color"]),
                energy = num(spec["energy"], 1.0),
                range = (spec["range"] as? Number)?.toDouble(),
                position = spec["position"],
            )
            "spot" -> g3.spotLight(
                color = parseGodotColor(spec["color"]),
                energy = num(spec["energy"], 1.0),
                range = (spec["range"] as? Number)?.toDouble(),
                angle = (spec["angle"] as? Number)?.toDouble(),
                position = spec["position"],
                rotation = spec["rotation"],
            )
            else -> g3.dirLight(
                color = parseGodotColor(spec["color"]),
                energy = num(spec["energy"], 1.0),
                shadow = spec["shadow"] == true,
                position = spec["position"],
                rotation = spec["rotation"],
            )
        }
    }

    private fun node(spec: Map<String, Any?>, byId: MutableMap<String, GodotObject>): GodotObject? {
        val type = spec["type"] as? String ?: "node"
        val c = controller
        val built: GodotObject = when (type) {
            "mesh" -> {
                val options = LinkedHashMap(spec)
                if (spec["color"] != null) options["color"] = parseGodotColor(spec["color"])
                if (spec["emission"] != null) options["emission"] = parseGodotColor(spec["emission"])
                c.g3.mesh(spec["shape"] as? String ?: "box", options)
            }
            "node", "group" -> c.g3.node(
                position = spec["position"],
                rotation = spec["rotation"],
                scale = spec["scale"],
                visible = spec["visible"] as? Boolean,
            )
            "camera" -> camera(spec)
            "light" -> light(spec)
            else -> {
                // Any other value is a raw ClassDB class name.
                val n = c.create(type)
                c.g3.setTransform(n, position = spec["position"], rotation = spec["rotation"], scale = spec["scale"], visible = spec["visible"] as? Boolean)
                n
            }
        }
        val props = objectSpec(spec["props"])
        if (props != null) {
            val coerced = LinkedHashMap<String, Any?>()
            for ((k, v) in props) coerced[k] = if (v is String && looksLikeColor(v)) parseGodotColor(v) ?: v else v
            built.setAll(coerced)
        }
        register(byId, spec, built)
        val children = spec["children"]
        if (children is List<*>) {
            for (entry in children) {
                val child = objectSpec(entry) ?: continue
                val childNode = node(child, byId)
                if (childNode != null) built.addChild(childNode)
            }
        }
        return built
    }
}

/** `GodotSceneController`: owns the engine controller and the built scene across renders. */
class GodotSceneController(binding: GodotBinding) {
    val godot: GodotController = GodotController(binding)
    private var current: GodotScene? = null
    private var disposed = false
    private val listeners = LinkedHashSet<() -> Unit>()

    val scene: GodotScene? get() = current

    val isLive: Boolean get() = godot.isLive

    fun node(id: String): GodotObject? = current?.byId(id)

    fun adopt(scene: GodotScene) {
        current = scene
        if (!disposed) for (l in listeners.toList()) l()
    }

    fun replaceScene(json: Map<String, Any?>): GodotScene {
        for (root in current?.roots ?: emptyList()) root.queueFree()
        val built = SceneDsl(godot).build(json)
        adopt(built)
        return built
    }

    fun addListener(fn: () -> Unit) {
        listeners.add(fn)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        godot.dispose()
        listeners.clear()
    }
}
