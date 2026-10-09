import Foundation

/**
 * Godot values on the wire — a port of `protocol.dart` and `godot_values.dart`
 * (godot/values.ts).
 *
 * Ops are JSON objects (`{"new": "MeshInstance3D", "def": 7}`,
 * `{"ref": 7, "set": "position", "value": {"vec3": [0, 1, 0]}}` …); typed
 * Godot values are single-key tagged objects. Handles are allocated on this
 * side, so a whole scene can be built and addressed before the engine has
 * rendered a frame.
 *
 * Numbers put on the wire are `Double`s (the JSON number model of the core);
 * handles and callback ids are `Int`s in the Swift API.
 */
public typealias Wire = Any?
public typealias Op = JSONObject

public enum OpKey {
    public static let create = "new"
    public static let def = "def"
    public static let self_ = "self"
    public static let tree = "tree"
    public static let singleton = "singleton"
    public static let load = "load"
    public static let free = "free"
    public static let ref = "ref"
    public static let get = "get"
    public static let set = "set"
    public static let getIndexed = "geti"
    public static let setIndexed = "seti"
    public static let value = "value"
    public static let props = "props"
    public static let method = "method"
    public static let args = "args"
    public static let static_ = "static"
    public static let connect = "connect"
    public static let disconnect = "disconnect"
    public static let cb = "cb"
    public static let flags = "flags"
    public static let constant = "const"
    public static let expr = "expr"
    public static let names = "names"
    public static let values = "values"
    public static let classes = "classes"
    public static let classInfo = "classinfo"
    public static let audit = "audit"
    public static let mount = "mount"
    public static let surface = "surface"
}

public struct GodotRef: Hashable, JSONSerializable {
    public let id: Int

    public init(_ id: Int) { self.id = id }

    public func toWire() -> JSONObject { JSONObject([("ref", Double(id))]) }

    public func toJSON() -> Any? { toWire() }

    /** `{ref: <integer>}` and nothing else. */
    public static func isRef(_ v: Any?) -> Bool {
        guard let m = asMap(v), m.count == 1, let r = jsNumber(m["ref"]) else { return false }
        return godotIsInteger(r)
    }
}

public struct GodotCallbackRef: Hashable, JSONSerializable {
    public let id: Int

    public init(_ id: Int) { self.id = id }

    public func toWire() -> JSONObject { JSONObject([("cb", Double(id))]) }

    public func toJSON() -> Any? { toWire() }
}

public final class HandleAllocator {
    public static let selfHandle = 1
    private var next: Int

    public init(start: Int = HandleAllocator.selfHandle + 1) {
        next = start
    }

    public func allocate() -> Int {
        let h = next
        next += 1
        return h
    }

    public var issued: Int { next - HandleAllocator.selfHandle - 1 }
}

public func wireError(_ message: String) -> JSONObject { JSONObject([("__dart_error__", message)]) }

public func isWireError(_ v: Any?) -> Bool {
    guard let m = asMap(v) else { return false }
    return m.has("__dart_error__")
}

public func wireErrorMessage(_ v: Any?) -> String? {
    guard isWireError(v), let m = asMap(v) else { return nil }
    return jsString(m["__dart_error__"])
}

public struct GodotOpException: Error, CustomStringConvertible {
    public let message: String
    public let op: Op?

    public init(_ message: String, op: Op? = nil) {
        self.message = message
        self.op = op
    }

    public var description: String {
        if let op = op { return "GodotOpException: \(message) (op: \(JSON.stringify(op)))" }
        return "GodotOpException: \(message)"
    }
}

public func encodeOps(_ ops: [Op]) -> String { JSON.stringify(ops.map { $0 as Any? }) }

public func decodeReplies(_ json: String?) throws -> [Wire] {
    guard let json = json, !json.isEmpty else { return [] }
    let decoded = try JSON.parse(json)
    if let a = asArray(decoded) { return a }
    return [decoded]
}

// ---------------------------------------------------------------------------
// Typed values
// ---------------------------------------------------------------------------

/** A typed Godot value: a single-key tagged object on the wire. */
public protocol GodotValue: JSONSerializable {
    func toWire() -> JSONObject
}

public extension GodotValue {
    func toJSON() -> Any? { toWire() }
}

private func tagged(_ tag: String, _ data: Any?) -> JSONObject { JSONObject([(tag, data)]) }

private func numbers(_ v: [Double]) -> [Any?] { v.map { $0 as Any? } }

public struct Vector2: GodotValue, Equatable {
    public let x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func toWire() -> JSONObject { tagged("vec2", numbers([x, y])) }
}

public struct Vector2i: GodotValue, Equatable {
    public let x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func toWire() -> JSONObject { tagged("vec2i", numbers([x, y])) }
}

public struct Vector3: GodotValue, Equatable {
    public let x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static func all(_ v: Double) -> Vector3 { Vector3(v, v, v) }
    public func plus(_ o: Vector3) -> Vector3 { Vector3(x + o.x, y + o.y, z + o.z) }
    public func minus(_ o: Vector3) -> Vector3 { Vector3(x - o.x, y - o.y, z - o.z) }
    public func times(_ s: Double) -> Vector3 { Vector3(x * s, y * s, z * s) }
    public func toWire() -> JSONObject { tagged("vec3", numbers([x, y, z])) }
}

public struct Vector3i: GodotValue, Equatable {
    public let x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public func toWire() -> JSONObject { tagged("vec3i", numbers([x, y, z])) }
}

public struct Vector4: GodotValue, Equatable {
    public let x: Double, y: Double, z: Double, w: Double
    public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
    public func toWire() -> JSONObject { tagged("vec4", numbers([x, y, z, w])) }
}

public struct Vector4i: GodotValue, Equatable {
    public let x: Double, y: Double, z: Double, w: Double
    public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
    public func toWire() -> JSONObject { tagged("vec4i", numbers([x, y, z, w])) }
}

public struct GodotColor: GodotValue, Equatable {
    public let r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public static func hex(_ rgb: Int, _ a: Double = 1) -> GodotColor {
        GodotColor(Double((rgb >> 16) & 0xff) / 255, Double((rgb >> 8) & 0xff) / 255, Double(rgb & 0xff) / 255, a)
    }
    public func toWire() -> JSONObject { tagged("color", numbers([r, g, b, a])) }
}

public struct Rect2: GodotValue, Equatable {
    public let x: Double, y: Double, w: Double, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public func toWire() -> JSONObject { tagged("rect2", numbers([x, y, w, h])) }
}

public struct Rect2i: GodotValue, Equatable {
    public let x: Double, y: Double, w: Double, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public func toWire() -> JSONObject { tagged("rect2i", numbers([x, y, w, h])) }
}

public struct Plane: GodotValue, Equatable {
    public let nx: Double, ny: Double, nz: Double, d: Double
    public init(_ nx: Double, _ ny: Double, _ nz: Double, _ d: Double) { self.nx = nx; self.ny = ny; self.nz = nz; self.d = d }
    public func toWire() -> JSONObject { tagged("plane", numbers([nx, ny, nz, d])) }
}

public struct Quaternion: GodotValue, Equatable {
    public let x: Double, y: Double, z: Double, w: Double
    public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
    public func toWire() -> JSONObject { tagged("quat", numbers([x, y, z, w])) }
}

public struct AABB: GodotValue, Equatable {
    public let px: Double, py: Double, pz: Double, sx: Double, sy: Double, sz: Double
    public init(_ px: Double, _ py: Double, _ pz: Double, _ sx: Double, _ sy: Double, _ sz: Double) {
        self.px = px; self.py = py; self.pz = pz; self.sx = sx; self.sy = sy; self.sz = sz
    }
    public func toWire() -> JSONObject { tagged("aabb", numbers([px, py, pz, sx, sy, sz])) }
}

public struct Basis: GodotValue, Equatable {
    public let rows: [[Double]]
    public init(_ rows: [[Double]]) { self.rows = rows }
    public func toWire() -> JSONObject { tagged("basis", rows.map { numbers($0) as Any? }) }
}

public struct Transform2D: GodotValue, Equatable {
    public let m: [Double]
    public init(_ m: [Double]) { self.m = m }
    public func toWire() -> JSONObject { tagged("xform2d", numbers(m)) }
}

public struct Transform3D: GodotValue, Equatable {
    public let m: [Double]
    public init(_ m: [Double]) { self.m = m }
    public func toWire() -> JSONObject { tagged("xform3d", numbers(m)) }
}

public struct Projection: GodotValue, Equatable {
    public let m: [Double]
    public init(_ m: [Double]) { self.m = m }
    public func toWire() -> JSONObject { tagged("proj", numbers(m)) }
}

public struct StringName: GodotValue, Equatable {
    public let value: String
    public init(_ value: String) { self.value = value }
    public func toWire() -> JSONObject { tagged("sname", value) }
}

public struct NodePath: GodotValue, Equatable {
    public let value: String
    public init(_ value: String) { self.value = value }
    public func toWire() -> JSONObject { tagged("npath", value) }
}

public struct GRid: GodotValue, Equatable {
    public let id: Double
    public init(_ id: Double) { self.id = id }
    public func toWire() -> JSONObject { tagged("rid", id) }
}

public struct GSignal: GodotValue, Equatable {
    public let sourceHandle: Int
    public let name: String
    public init(_ sourceHandle: Int, _ name: String) { self.sourceHandle = sourceHandle; self.name = name }
    public func toWire() -> JSONObject { tagged("sig", [GodotRef(sourceHandle).toWire(), name] as [Any?]) }
}

public struct GCallable: GodotValue, Equatable {
    public let callbackId: Int
    public init(_ callbackId: Int) { self.callbackId = callbackId }
    public func toWire() -> JSONObject { tagged("callable", Double(callbackId)) }
}

public struct GInt: GodotValue, Equatable {
    public let value: Double
    public init(_ value: Double) { self.value = value }
    public func toWire() -> JSONObject { tagged("int", jsTrunc(value)) }
}

public struct GFloat: GodotValue, Equatable {
    public let value: Double
    public init(_ value: Double) { self.value = value }
    public func toWire() -> JSONObject { tagged("float", value) }
}

/** A Godot Dictionary with non-string keys: `[key, value]` entries. */
public struct GDict: GodotValue {
    public let entries: [(Any?, Any?)]
    public init(_ entries: [(Any?, Any?)]) { self.entries = entries }
    public func toWire() -> JSONObject {
        tagged("dictv", entries.map { [marshal($0.0), marshal($0.1)] as [Any?] as Any? })
    }
}

/** A packed array; `data` is the tag's wire payload (base64 for `u8`, a flat number list otherwise). */
public struct Packed: GodotValue {
    public let tag: String
    public let data: Any?
    public init(_ tag: String, _ data: Any?) { self.tag = tag; self.data = data }
    public static func bytesBase64(_ b64: String) -> Packed { Packed("u8", b64) }
    public static func i32(_ v: [Double]) -> Packed { Packed("i32", numbers(v)) }
    public static func i64(_ v: [Double]) -> Packed { Packed("i64", numbers(v)) }
    public static func f32(_ v: [Double]) -> Packed { Packed("f32", numbers(v)) }
    public static func f64(_ v: [Double]) -> Packed { Packed("f64", numbers(v)) }
    public static func strings(_ v: [String]) -> Packed { Packed("strs", v.map { $0 as Any? }) }
    public static func vector2s(_ flat: [Double]) -> Packed { Packed("pv2", numbers(flat)) }
    public static func vector3s(_ flat: [Double]) -> Packed { Packed("pv3", numbers(flat)) }
    public static func vector4s(_ flat: [Double]) -> Packed { Packed("pv4", numbers(flat)) }
    public static func colors(_ flat: [Double]) -> Packed { Packed("pcol", numbers(flat)) }
    public func toWire() -> JSONObject { tagged(tag, data) }
}

/** Anything that exposes a [GodotRef] (GodotObject). */
public protocol GodotHandle: AnyObject {
    var ref: GodotRef { get }
}

/** A Swift value as its wire form: typed values tag themselves, maps become `{"dict": …}`. */
public func marshal(_ value: Any?) -> Any? {
    guard let v = flattenOptional(value) else { return nil }
    if let b = jsBool(v) { return b }
    if let s = v as? String { return s }
    if let n = jsNumber(v) { return n }
    if let g = v as? GodotValue { return g.toWire() }
    if let r = v as? GodotRef { return r.toWire() }
    if let c = v as? GodotCallbackRef { return c.toWire() }
    if let h = v as? GodotHandle { return h.ref.toWire() }
    if let a = asArray(v) { return a.map { marshal($0) } }
    if let m = asMap(v) {
        let out = JSONObject()
        for (k, val) in m { out[k] = marshal(val) }
        return JSONObject([("dict", out)])
    }
    return v
}

public func marshalArgs(_ args: [Any?]?) -> [Any?] {
    guard let args = args else { return [] }
    return args.map { marshal($0) }
}

/** A wire value back as Swift: tagged objects become typed values, `int`/`float` plain numbers. */
public func unmarshal(_ value: Any?) -> Any? {
    let v = flattenOptional(value)
    if let a = asArray(v) { return a.map { unmarshal($0) } }
    guard let map = asMap(v) else { return v }
    if map.has("__dart_error__") { return v }
    if map.count != 1 { return v }
    let key = map.keys[0]
    let data = map[key]
    func nums() -> [Double] { (asArray(data) ?? []).map { jsToNumber($0) } }
    func ints() -> [Double] { (asArray(data) ?? []).map { jsTrunc(jsToNumber($0)) } }
    func at(_ n: [Double], _ i: Int) -> Double { i < n.count ? n[i] : .nan }
    switch key {
    case "ref":
        return GodotRef(godotInt(jsToNumber(data)))
    case "vec2":
        let n = nums(); return Vector2(at(n, 0), at(n, 1))
    case "vec2i":
        let n = ints(); return Vector2i(at(n, 0), at(n, 1))
    case "vec3":
        let n = nums(); return Vector3(at(n, 0), at(n, 1), at(n, 2))
    case "vec3i":
        let n = ints(); return Vector3i(at(n, 0), at(n, 1), at(n, 2))
    case "vec4":
        let n = nums(); return Vector4(at(n, 0), at(n, 1), at(n, 2), at(n, 3))
    case "vec4i":
        let n = ints(); return Vector4i(at(n, 0), at(n, 1), at(n, 2), at(n, 3))
    case "color":
        let n = nums(); return GodotColor(at(n, 0), at(n, 1), at(n, 2), at(n, 3))
    case "rect2":
        let n = nums(); return Rect2(at(n, 0), at(n, 1), at(n, 2), at(n, 3))
    case "rect2i":
        let n = ints(); return Rect2i(at(n, 0), at(n, 1), at(n, 2), at(n, 3))
    case "plane":
        let n = nums(); return Plane(at(n, 0), at(n, 1), at(n, 2), at(n, 3))
    case "quat":
        let n = nums(); return Quaternion(at(n, 0), at(n, 1), at(n, 2), at(n, 3))
    case "aabb":
        let n = nums(); return AABB(at(n, 0), at(n, 1), at(n, 2), at(n, 3), at(n, 4), at(n, 5))
    case "basis":
        return Basis((asArray(data) ?? []).map { row in (asArray(row) ?? []).map { jsToNumber($0) } })
    case "xform2d":
        return Transform2D(nums())
    case "xform3d":
        return Transform3D(nums())
    case "proj":
        return Projection(nums())
    case "sname":
        return StringName(jsString(data))
    case "npath":
        return NodePath(jsString(data))
    case "rid":
        return GRid(jsToNumber(data))
    case "int":
        return jsTrunc(jsToNumber(data))
    case "float":
        return jsToNumber(data)
    case "callable":
        return GCallable(godotInt(jsToNumber(data)))
    case "dict":
        let out = JSONObject()
        if let d = asMap(data) {
            for (k, val) in d { out[k] = unmarshal(val) }
        }
        return out
    case "dictv":
        return GDict((asArray(data) ?? []).map { pair -> (Any?, Any?) in
            let p = asArray(pair) ?? []
            return (unmarshal(p.count > 0 ? p[0] : nil), unmarshal(p.count > 1 ? p[1] : nil))
        })
    case "u8", "i32", "i64", "f32", "f64", "strs", "pv2", "pv3", "pv4", "pcol":
        return Packed(key, data)
    default:
        return v
    }
}

// ---------------------------------------------------------------------------
// Number helpers used by the wire codec
// ---------------------------------------------------------------------------

/** `Number.isInteger`. */
func godotIsInteger(_ d: Double) -> Bool { d.isFinite && d == d.rounded(.down) }

/** A wire number as an `Int` handle / id (NaN and out-of-range read as 0). */
func godotInt(_ d: Double) -> Int {
    guard d.isFinite, abs(d) < 9.2e18 else { return 0 }
    return Int(d.rounded(.towardZero))
}
