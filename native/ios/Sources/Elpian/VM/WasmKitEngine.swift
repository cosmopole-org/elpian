#if canImport(WasmKit)
import Foundation
import WasmKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * WASM guests on WasmKit, a pure-Swift WebAssembly runtime (ChicoryWasm.kt on
 * Android, `WebWasmEngine` on the web): every function import is bound to the
 * core's handler, non-function imports are left to the module, and memory is
 * addressed by export name with a fallback to the first exported memory.
 *
 * Values cross as the numbers they denote, as a JS host would see them: i32 is
 * sign-extended, i64 passes through, and f32 / f64 are converted to and from
 * their numeric value (truncated to an integer, since the handler's numbers
 * are integers).
 */
public final class WasmKitEngine: WasmEngine {
    public init() {}

    public func instantiate(_ bytes: [UInt8], _ onImport: @escaping WasmImportHandler) throws -> WasmInstanceHandle {
        let module = try parseWasm(bytes: bytes)
        let engine = Engine()
        let store = Store(engine: engine)
        var imports = Imports()
        for imp in module.imports {
            guard case .function(let typeIndex) = imp.descriptor, Int(typeIndex) < module.types.count else { continue }
            let type = module.types[Int(typeIndex)]
            let moduleName = imp.module
            let name = imp.name
            let fn = Function(store: store, type: type) { _, args in
                var decoded: [Int64] = []
                decoded.reserveCapacity(args.count)
                for a in args { decoded.append(WasmKitEngine.decode(a)) }
                let out = onImport(moduleName, name, decoded)
                return type.results.enumerated().map { k, t in WasmKitEngine.encode(t, k < out.count ? out[k] : 0) }
            }
            imports.define(module: moduleName, name: name, fn)
        }
        let instance = try module.instantiate(store: store, imports: imports)
        return WasmKitInstance(instance, module)
    }

    /** A WasmKit value → the number it denotes. */
    static func decode(_ v: Value) -> Int64 {
        switch v {
        case .i32(let u): return Int64(Int32(bitPattern: u))
        case .i64(let u): return Int64(bitPattern: u)
        case .f32(let bits):
            let f = Float(bitPattern: bits)
            return f.isFinite ? Int64(max(min(Double(f), 9.2e18), -9.2e18)) : 0
        case .f64(let bits):
            let d = Double(bitPattern: bits)
            return d.isFinite ? Int64(max(min(d, 9.2e18), -9.2e18)) : 0
        default:
            return 0
        }
    }

    /** A number → the WasmKit value of [type]. */
    static func encode(_ type: ValueType, _ value: Int64) -> Value {
        switch type {
        case .i32: return .i32(UInt32(bitPattern: Int32(truncatingIfNeeded: value)))
        case .i64: return .i64(UInt64(bitPattern: value))
        case .f32: return .f32(Float(value).bitPattern)
        case .f64: return .f64(Double(value).bitPattern)
        default: return .i32(0)
        }
    }
}

private final class WasmKitInstance: WasmInstanceHandle {
    private var instance: Instance?
    private let exportNames: Set<String>
    private let memoryNames: [String]

    init(_ instance: Instance, _ module: Module) {
        self.instance = instance
        exportNames = Set(module.exports.map { $0.name })
        memoryNames = module.exports.compactMap { e -> String? in
            if case .memory = e.descriptor { return e.name }
            return nil
        }
    }

    private func live() throws -> Instance {
        guard let i = instance else { throw PlatformError("WASM instance is disposed.") }
        return i
    }

    func hasExport(_ name: String) -> Bool { instance != nil && exportNames.contains(name) }

    func call(_ exportName: String, _ args: [Int64]) throws -> [Int64] {
        let inst = try live()
        guard let fn = inst.exports[function: exportName] else { throw PlatformError("WASM function export not found: \(exportName)") }
        let params = fn.type.parameters
        let raw = params.enumerated().map { i, t in WasmKitEngine.encode(t, i < args.count ? args[i] : 0) }
        return try fn.invoke(raw).map { WasmKitEngine.decode($0) }
    }

    private func memory(_ name: String) throws -> Memory {
        let inst = try live()
        if let m = inst.exports[memory: name] { return m }
        for n in memoryNames { if let m = inst.exports[memory: n] { return m } }
        throw PlatformError("WASM memory export not found: \(name)")
    }

    /** The memory's byte length (`Memory.data` shares the engine's buffer copy-on-write, so this does not copy). */
    func memoryLength(_ memoryExport: String) -> Int64 {
        guard let m = try? memory(memoryExport) else { return 0 }
        return Int64(m.data.count)
    }

    private func checkRange(_ size: Int64, _ ptr: Int64, _ length: Int64) throws {
        if ptr < 0 || length < 0 || ptr + length > size {
            throw PlatformError("WASM memory access out of range (ptr=\(ptr) len=\(length) size=\(size))")
        }
    }

    func memoryRead(_ memoryExport: String, _ ptr: Int64, _ length: Int) throws -> [UInt8] {
        let m = try memory(memoryExport)
        try checkRange(Int64(m.data.count), ptr, Int64(length))
        if length == 0 { return [] }
        return m.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: length) { Array($0.bindMemory(to: UInt8.self)) }
    }

    func memoryWrite(_ memoryExport: String, _ ptr: Int64, _ bytes: [UInt8]) throws {
        let m = try memory(memoryExport)
        try checkRange(Int64(m.data.count), ptr, Int64(bytes.count))
        if bytes.isEmpty { return }
        m.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: bytes.count) { buf in
            bytes.withUnsafeBytes { src in buf.copyMemory(from: src) }
        }
    }

    func dispose() {
        instance = nil
    }
}
#endif
