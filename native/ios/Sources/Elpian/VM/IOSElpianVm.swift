#if canImport(UIKit) || ELPIAN_HOST_TYPECHECK
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif
#if canImport(CElpianVM)
import CElpianVM
#endif

/**
 * The C ABI of libelpian_vm (rust/crates/elpian-ffi/include/elpian_vm.h) as
 * function pointers: the linked symbols themselves when the library is linked
 * at build time (`ELPIAN_VM_LINKED` from Package.swift, `ELPIAN_VM` in the
 * Expo pod), otherwise looked up at run time with `dlsym` in the process (a
 * library the host app links or embeds) or in a library opened by path.
 */
struct ElpianVmSymbols {
    typealias CallJson = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FreeString = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    typealias LastError = @convention(c) () -> UnsafePointer<CChar>?
    typealias FromBytecode = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<UInt8>?, Int) -> Int32
    typealias Init = @convention(c) () -> Void

    let callJson: CallJson
    let freeString: FreeString
    let lastError: LastError
    let createFromBytecode: FromBytecode
    let initialize: Init

    /** The statically linked library, when the build links it. */
    static func linked() -> ElpianVmSymbols? {
        #if ELPIAN_VM_LINKED || ELPIAN_VM
        return ElpianVmSymbols(
            callJson: { elpian_call_json($0, $1) },
            freeString: { elpian_free_string($0) },
            lastError: { elpian_last_error() },
            createFromBytecode: { elpian_create_vm_from_bytecode($0, $1, $2) },
            initialize: { elpian_init() }
        )
        #else
        return nil
        #endif
    }

    /** The exports found with `dlsym` in [handle] (the whole process when nil); the missing one's name otherwise. */
    static func lookup(_ handle: UnsafeMutableRawPointer?) -> (symbols: ElpianVmSymbols?, missing: String?) {
        #if os(Linux)
        let h = handle
        #else
        let h = handle ?? UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        #endif
        func sym(_ name: String) -> UnsafeMutableRawPointer? { dlsym(h, name) }
        guard let call = sym("elpian_call_json") else { return (nil, "elpian_call_json") }
        guard let free = sym("elpian_free_string") else { return (nil, "elpian_free_string") }
        guard let last = sym("elpian_last_error") else { return (nil, "elpian_last_error") }
        guard let bytecode = sym("elpian_create_vm_from_bytecode") else { return (nil, "elpian_create_vm_from_bytecode") }
        guard let ini = sym("elpian_init") else { return (nil, "elpian_init") }
        return (ElpianVmSymbols(
            callJson: unsafeBitCast(call, to: CallJson.self),
            freeString: unsafeBitCast(free, to: FreeString.self),
            lastError: unsafeBitCast(last, to: LastError.self),
            createFromBytecode: unsafeBitCast(bytecode, to: FromBytecode.self),
            initialize: unsafeBitCast(ini, to: Init.self)
        ), nil)
    }
}

/**
 * [ElpianVmBinding] over the Rust runtime's C ABI (AndroidElpianVm.kt).
 *
 * Every method goes through the by-name dispatcher `elpian_call_json`, so the
 * JSON shapes, panic containment and error slot are exactly those of any C
 * caller; bytecode goes through `elpian_create_vm_from_bytecode` (it does not
 * travel as JSON). When the library is not present the binding reports
 * unavailable with the reason in [lastError], the boolean calls answer false
 * and the execution calls answer the `native_lib_not_loaded` error result in
 * the same shape as the core's own.
 */
public final class IOSElpianVm: ElpianVmBinding {
    private let symbols: ElpianVmSymbols?
    private let loadError: String?

    /**
     * The linked library, or the exports found in the process. [libraryPath]
     * opens a dynamic library (e.g. an embedded framework's binary) instead.
     */
    public init(libraryPath: String? = nil) {
        if libraryPath == nil, let s = ElpianVmSymbols.linked() {
            symbols = s
            loadError = nil
            return
        }
        var handle: UnsafeMutableRawPointer?
        if let path = libraryPath {
            handle = dlopen(path, RTLD_NOW)
            if handle == nil {
                let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
                symbols = nil
                loadError = "libelpian_vm could not be opened at \(path): \(reason)"
                return
            }
        }
        let found = ElpianVmSymbols.lookup(handle)
        symbols = found.symbols
        loadError = found.symbols != nil ? nil
            : "the Elpian VM is not linked into this app (no \(found.missing ?? "elpian_*") export); build it with native/ios/scripts/build-rust.sh"
    }

    public func isAvailable() -> Bool { symbols != nil }

    public func lastError() -> String? {
        guard let s = symbols else { return loadError }
        guard let p = s.lastError() else { return nil }
        let e = String(cString: p)
        return e.isEmpty ? nil : e
    }

    public func initialize() throws {
        symbols?.initialize()
    }

    public func createFromAst(_ machineId: String, _ astJson: String) throws -> Bool { flag("elpian_create_vm_from_ast", [machineId, astJson]) }

    public func createFromCode(_ machineId: String, _ code: String) throws -> Bool { flag("elpian_create_vm_from_code", [machineId, code]) }

    public func createFromBytecode(_ machineId: String, _ bytecode: [UInt8]) throws -> Bool {
        guard let s = symbols else { return false }
        return machineId.withCString { id in
            bytecode.withUnsafeBufferPointer { buf in s.createFromBytecode(id, buf.baseAddress, buf.count) != 0 }
        }
    }

    public func validateAst(_ astJson: String) throws -> Bool { flag("elpian_validate_ast", [astJson]) }

    public func execute(_ machineId: String) throws -> String { result("elpian_execute", [machineId]) }

    public func executeFunc(_ machineId: String, _ funcName: String, _ cbId: Int64) throws -> String {
        result("elpian_execute_func", [machineId, funcName, Double(cbId)])
    }

    public func executeFuncWithInput(_ machineId: String, _ funcName: String, _ inputJson: String, _ cbId: Int64) throws -> String {
        result("elpian_execute_func_with_input", [machineId, funcName, inputJson, Double(cbId)])
    }

    public func continueExecution(_ machineId: String, _ inputJson: String) throws -> String {
        result("elpian_continue_execution", [machineId, inputJson])
    }

    public func deliverHostMessage(_ machineId: String, _ messageJson: String, _ cbId: Int64) throws -> String {
        result("elpian_deliver_host_message", [machineId, messageJson, Double(cbId)])
    }

    public func destroy(_ machineId: String) throws -> Bool { flag("elpian_destroy_vm", [machineId]) }

    public func exists(_ machineId: String) throws -> Bool { flag("elpian_vm_exists", [machineId]) }

    public func governance(_ symbol: String, _ args: [Any]) throws -> String? {
        guard symbols != nil else { return nil }
        return call(symbol, args.map { a -> Any? in
            if let i = a as? Int { return Double(i) }
            if let i = a as? Int64 { return Double(i) }
            if let i = a as? Int32 { return Double(i) }
            return a
        })
    }

    // ---------------------------------------------------------------------

    /** `elpian_call_json(symbol, JSON args)`: the reply, or nil for an unknown export. */
    private func call(_ symbol: String, _ args: [Any?]) -> String? {
        guard let s = symbols else { return nil }
        let json = JSON.stringify(args)
        guard let out = symbol.withCString({ sp in json.withCString { jp in s.callJson(sp, jp) } }) else { return nil }
        defer { s.freeString(out) }
        return String(cString: out)
    }

    private func flag(_ symbol: String, _ args: [Any?]) -> Bool { symbols != nil && call(symbol, args) == "true" }

    private func result(_ symbol: String, _ args: [Any?]) -> String {
        if symbols == nil { return IOSElpianVm.errorResult("native_lib_not_loaded") }
        return call(symbol, args) ?? IOSElpianVm.errorResult("missing_export:\(symbol)")
    }

    static func errorResult(_ reason: String) -> String {
        JSON.stringify(JSONObject([("hasHostCall", false), ("hostCallData", ""), ("resultValue", JSON.stringify(JSONObject([("error", reason)])))]))
    }
}
#endif
