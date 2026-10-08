import Foundation

/**
 * The typed value envelope the Elpian VM uses on its host boundary:
 * `{"type": "<tag>", "data": {"value": <payload>}}`.
 *
 * Host APIs answer with these, and event payloads delivered to guest
 * functions are encoded with [toTypedVmValue] so both the native and the wasm
 * VM decode arguments the same way (mirrors `_toTypedVmValue` in
 * elpian_vm_widget.dart).
 */
public enum Typed {
    public static func makeResponse(_ type: String, _ value: Any?) -> String {
        JSON.stringify(JSONObject([("type", type), ("data", JSONObject([("value", value)]))]))
    }

    public static let NULL_RESPONSE = makeResponse("null", nil)
    public static let OK_RESPONSE = makeResponse("i16", 0.0)
    public static let ONE_RESPONSE = makeResponse("i16", 1.0)

    /** `toTypedVmValue`: safe integers are i64, other numbers f64. */
    public static func toTypedVmValue(_ raw: Any?) -> JSONObject {
        let value = flattenOptional(raw)
        guard let v = value else { return env("null", nil) }
        if let b = jsBool(v) { return env("bool", b) }
        if let n = jsNumber(v) {
            if jsIsSafeInteger(n) { return env("i64", n) }
            return env("f64", n)
        }
        if let s = v as? String { return env("string", s) }
        if let a = asArray(v) { return env("array", a.map { toTypedVmValue($0) as Any? }) }
        if let m = asMap(v) {
            let out = JSONObject()
            for (k, e) in m { out[k] = toTypedVmValue(e) }
            return env("object", out)
        }
        if let s = v as? JSONSerializable, !(s is JSONObject) { return toTypedVmValue(s.toJSON()) }
        return env("string", jsString(v))
    }

    /** Decode a typed envelope back to a plain value (inverse of [toTypedVmValue]). */
    public static func fromTypedVmValue(_ raw: Any?) -> Any? {
        let value = flattenOptional(raw)
        guard let m = asMap(value) else { return value }
        guard let type = m["type"] as? String, let data = asMap(m["data"]), data.has("value") else { return value }
        let inner = data["value"]
        switch type {
        case "array":
            if let a = asArray(inner) { return a.map { fromTypedVmValue($0) } }
            return inner
        case "object":
            guard let o = asMap(inner) else { return inner }
            let out = JSONObject()
            for (k, v) in o { out[k] = fromTypedVmValue(v) }
            return out
        default:
            return inner
        }
    }

    private static func env(_ type: String, _ v: Any?) -> JSONObject {
        JSONObject([("type", type), ("data", JSONObject([("value", v)]))])
    }
}
