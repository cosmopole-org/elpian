import XCTest
@testable import ElpianCore

/** A platform whose timers run when the test advances the clock, with pluggable sandboxes. */
final class VmTestPlatform: Platform {
    let name = "vm-test"
    var clock = 0.0
    var timers: [(handle: Int, at: Double, fn: () -> Void)] = []
    var nextHandle = 1
    var logs: [String] = []
    var vm: ElpianVmBinding?
    var js: JsSandboxFactory?
    var wasmEngine: WasmEngine?
    var assets: [String: String] = [:]

    func now() -> Double { clock }
    func setTimeout(_ callback: @escaping () -> Void, _ ms: Double) -> Int {
        let h = nextHandle
        nextHandle += 1
        timers.append((h, clock + ms, callback))
        return h
    }
    func clearTimeout(_ handle: Int) { timers.removeAll { $0.handle == handle } }
    func requestFrame(_ callback: @escaping (Double) -> Void) -> Int { 0 }
    func cancelFrame(_ handle: Int) {}
    func commit(_ surface: String, _ ops: [ViewOp]) {}
    func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        TextMetrics(width: 0, height: 0, baseline: 0, lineCount: 1, didExceedMaxLines: false)
    }
    func viewport(_ surface: String) -> Viewport { Viewport(width: 100, height: 100) }
    func log(_ level: LogLevel, _ message: String) { logs.append(message) }
    func loadAsset(_ path: String, _ encoding: AssetEncoding) async throws -> String {
        guard let a = assets[path] else { throw ElpianError("no asset \(path)") }
        return a
    }
    var elpianVm: ElpianVmBinding? { vm }
    var jsSandbox: JsSandboxFactory? { js }
    var wasm: WasmEngine? { wasmEngine }

    /** Run every timer due by [to], in time order. */
    func advance(to: Double) {
        while true {
            guard let next = timers.filter({ $0.at <= to }).min(by: { $0.at < $1.at }) else { break }
            timers.removeAll { $0.handle == next.handle }
            clock = next.at
            next.fn()
        }
        clock = to
    }
}

/** An Elpian VM that asks for `add` once, then returns the host's answer. */
final class FakeVmBinding: ElpianVmBinding {
    var continued: [String] = []
    var created: [String] = []
    var destroyed: [String] = []
    var governanceReplies: [String: String] = [:]
    var governanceCalls: [(String, [Any])] = []

    func isAvailable() -> Bool { true }
    func lastError() -> String? { nil }
    func initialize() throws {}
    func createFromAst(_ machineId: String, _ astJson: String) throws -> Bool { created.append(machineId); return true }
    func createFromCode(_ machineId: String, _ code: String) throws -> Bool { created.append(machineId); return true }
    func createFromBytecode(_ machineId: String, _ bytecode: [UInt8]) throws -> Bool { created.append(machineId); return bytecode == [1, 2, 3] }
    func validateAst(_ astJson: String) throws -> Bool { true }
    private func hostCall(_ api: String, _ payload: Any?) -> String {
        JSON.stringify(JSONObject([
            ("hasHostCall", true),
            ("hostCallData", JSON.stringify(JSONObject([("apiName", api), ("payload", payload)]))),
            ("resultValue", ""),
        ]))
    }
    func execute(_ machineId: String) throws -> String { hostCall("add", [1.0, 2.0] as [Any?]) }
    func executeFunc(_ machineId: String, _ funcName: String, _ cbId: Int64) throws -> String { hostCall("later", "x") }
    func executeFuncWithInput(_ machineId: String, _ funcName: String, _ inputJson: String, _ cbId: Int64) throws -> String {
        hostCall("println", inputJson)
    }
    func continueExecution(_ machineId: String, _ inputJson: String) throws -> String {
        continued.append(inputJson)
        if continued.count == 1 && inputJson.contains("\"env\"") { return hostCall("env.get", nil) }
        return JSON.stringify(JSONObject([("hasHostCall", false), ("hostCallData", ""), ("resultValue", "result:\(inputJson)")]))
    }
    func deliverHostMessage(_ machineId: String, _ messageJson: String, _ cbId: Int64) throws -> String { hostCall("stringify", messageJson) }
    func destroy(_ machineId: String) throws -> Bool { destroyed.append(machineId); return true }
    func exists(_ machineId: String) throws -> Bool { true }
    func governance(_ symbol: String, _ args: [Any]) throws -> String? {
        governanceCalls.append((symbol, args))
        return governanceReplies[symbol]
    }
}

final class FakeJsSandbox: JsSandbox, JsSandboxFactory {
    var handler: ((String, String) -> String)?
    var evaluated: [String] = []
    var disposed = false
    /** What `evaluate` does for code other than the bootstrap: (code) -> result. */
    var onEvaluate: ((String) -> String)?

    func create(_ machineId: String) throws -> JsSandbox { self }
    func setHostCallHandler(_ handler: @escaping (String, String) -> String) { self.handler = handler }
    func evaluate(_ code: String) throws -> String {
        evaluated.append(code)
        return onEvaluate?(code) ?? "undefined"
    }
    func dispose() { disposed = true }
}

/** A linear-memory WASM instance whose `run` export calls the host import once. */
final class FakeWasmInstance: WasmInstanceHandle, WasmEngine {
    var memory = [UInt8](repeating: 0, count: 4096)
    var heap: Int64 = 16
    var onImport: WasmImportHandler?
    var resultPtr: Int64 = 0
    var resultLen: Int64 = 0
    var calls: [String] = []
    var deallocs: [[Int64]] = []

    func instantiate(_ bytes: [UInt8], _ onImport: @escaping WasmImportHandler) throws -> WasmInstanceHandle {
        XCTAssertEqual(bytes, [0, 97, 115, 109])
        self.onImport = onImport
        return self
    }
    func hasExport(_ name: String) -> Bool {
        ["memory", "alloc", "dealloc", "run", "call_function", "call_function_with_input", "get_result_ptr", "get_result_len"].contains(name)
    }
    private func put(_ s: String) -> (Int64, Int64) {
        let b = Array(s.utf8)
        let p = heap
        heap += Int64(b.count)
        for (i, x) in b.enumerated() { memory[Int(p) + i] = x }
        return (p, Int64(b.count))
    }
    private func get(_ p: Int64, _ n: Int64) -> String { String(decoding: memory[Int(p)..<Int(p + n)], as: UTF8.self) }
    func call(_ exportName: String, _ args: [Int64]) throws -> [Int64] {
        calls.append(exportName)
        switch exportName {
        case "alloc":
            let p = heap
            heap += args[0]
            return [p]
        case "dealloc":
            deallocs.append(args)
            return []
        case "run":
            let api = put("echo")
            let payload = put("{\"a\":1}")
            let out = heap
            heap += 256
            let written = onImport!("env", "elpian_host_call", [api.0, api.1, payload.0, payload.1, out, 256])[0]
            (resultPtr, resultLen) = (out, written)
            return []
        case "call_function":
            let name = get(args[0], args[1])
            (resultPtr, resultLen) = put("called \(name)")
            return []
        case "call_function_with_input":
            (resultPtr, resultLen) = put("\(get(args[0], args[1]))(\(get(args[2], args[3])))")
            return []
        case "get_result_ptr": return [resultPtr]
        case "get_result_len": return [resultLen]
        default: return [0]
        }
    }
    func memoryLength(_ memoryExport: String) -> Int64 { Int64(memory.count) }
    func memoryRead(_ memoryExport: String, _ ptr: Int64, _ length: Int) throws -> [UInt8] { Array(memory[Int(ptr)..<Int(ptr) + length]) }
    func memoryWrite(_ memoryExport: String, _ ptr: Int64, _ bytes: [UInt8]) throws {
        for (i, b) in bytes.enumerated() { memory[Int(ptr) + i] = b }
    }
    func dispose() {}
}

final class HostVmTests: XCTestCase {
    var plat: VmTestPlatform!

    override func setUp() {
        plat = VmTestPlatform()
        setPlatform(plat)
        resetElpianGovernanceProbe()
    }

    // ---- DOM ----------------------------------------------------------------

    func testDomQuerySelector() {
        let dom = ElpianDOM()
        let root = dom.fromJson(asMap(try? JSON.parse(#"""
        {"type":"div","key":"root","props":{"className":"app main","style":{"color":"red"}},
         "children":[{"type":"span","props":{"className":["item","first"],"text":"a"}},
                     {"type":"span","key":"two","props":{"className":"item"}},
                     {"type":"p","props":{"className":"item first"}}]}
        """#))!)
        XCTAssertTrue(dom.querySelector("#root") === root)
        XCTAssertEqual(dom.querySelectorAll(".item").count, 3)
        XCTAssertEqual(dom.querySelectorAll("span.item").count, 2)
        XCTAssertEqual(dom.querySelectorAll("span.item.first").count, 1)
        XCTAssertEqual(dom.querySelectorAll(".item.first").count, 0, "a leading dot is a single class name")
        XCTAssertEqual(dom.querySelectorAll("p").count, 1)
        XCTAssertNil(dom.querySelector("#nope"))
        let two = dom.getElementById("two")!
        XCTAssertTrue(two.previousSibling === root.children[0])
        XCTAssertTrue(two.nextSibling === root.children[2])
        two.toggleClass("item")
        XCTAssertEqual(dom.querySelectorAll(".item").count, 2)
        XCTAssertEqual(JSON.stringify(root.children[0].toJson()),
                       #"{"type":"span","props":{"text":"a","className":"item first"},"children":[]}"#)
        XCTAssertEqual(root.description, #"<div id="root" class="app main">"#)
        let copy = root.clone(deep: true)
        XCTAssertEqual(copy.children.count, 3)
        XCTAssertEqual(dom.querySelectorAll("span").count, 4)
        dom.removeElement(two)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertNil(dom.getElementById("two"))
    }

    // ---- timers ---------------------------------------------------------------

    func testTimersFireThroughThePlatform() {
        var calls: [(String, String?)] = []
        let fired = expectation(description: "invoked")
        fired.expectedFulfillmentCount = 3
        let timers = VmTimerHostApi({ name, input in
            calls.append((name, input))
            fired.fulfill()
        })
        let r = timers.handle("setTimeout", #"[{"handler":"tick","delay":"100","input":{"n":1}}]"#)
        XCTAssertEqual(r, Typed.makeResponse("i64", 1.0))
        let interval = timers.handle("setInterval", #"{"type":"object","data":{"value":{"fn":"every","ms":40.4}}}"#)
        XCTAssertEqual(interval, Typed.makeResponse("i64", 2.0))
        XCTAssertEqual(timers.handle("setTimeout", #"{"delay":5}"#), Typed.OK_RESPONSE)
        XCTAssertEqual(timers.activeCount, 2)
        plat.advance(to: 90)
        _ = timers.handle("clearInterval", "2")
        XCTAssertEqual(timers.activeCount, 1)
        plat.advance(to: 200)
        XCTAssertEqual(timers.activeCount, 0)
        wait(for: [fired], timeout: 2)
        // Each guest call runs as its own task, so only the set of calls is ordered by the clock.
        XCTAssertEqual(calls.map { $0.0 }.sorted(), ["every", "every", "tick"])
        XCTAssertEqual(calls.first { $0.0 == "tick" }?.1, #"{"n":1}"#)
        XCTAssertTrue(plat.timers.isEmpty)
    }

    // ---- governance -------------------------------------------------------------

    func testGovernanceJsonParsing() throws {
        XCTAssertThrowsError(try decodeGovernanceReply(#"{"error":"no such vm"}"#, call: "elpian_usage")) { e in
            XCTAssertEqual("\(e)", "ElpianGovernanceException: elpian_usage failed: no such vm")
        }
        XCTAssertThrowsError(try decodeGovernanceReply("[1]"))
        let snap = snapshotFromJson(try decodeGovernanceReply(#"""
        {"machineId":"m","state":{"state":"paused","trapReason":"","processing":true},
         "limits":{"maxInstructions":100,"maxCallDepth":null},
         "usage":{"instructions":50.7,"memoryBytes":10},
         "localCapabilities":{"network":false,"dom":true,"bogus":true},
         "tree":{"parent":"p","children":["c1"],"subtree":["c1","c2"]}}
        """#))
        XCTAssertEqual(snap.machineId, "m")
        XCTAssertEqual(snap.state, ElpianVmState(state: .paused, trapReason: nil, processing: true))
        XCTAssertEqual(snap.limits, ElpianLimits(maxInstructions: 100))
        XCTAssertEqual(snap.usage.instructions, 50)
        XCTAssertEqual(snap.localCapabilities.granted, [.dom])
        XCTAssertEqual(snap.localCapabilities.denied, [.network])
        XCTAssertFalse(snap.localCapabilities.allows(.gpu))
        XCTAssertEqual(snap.tree.subtree, ["c1", "c2"])
        XCTAssertEqual(snap.effectiveCapabilities.granted, [])
        XCTAssertEqual(JSON.stringify(Limits.toJson(Limits.tightest(Limits.sandboxed, ElpianLimits(maxCallDepth: 10)))),
                       #"{"maxInstructions":50000000,"maxInstructionsPerTurn":5000000,"maxMemoryBytes":67108864,"maxStorageBytes":16777216,"maxCallDepth":10}"#)
        XCTAssertEqual(JSON.stringify(pressureAgainst(snap.usage, snap.limits)), #"{"instructions":0.5}"#)
        XCTAssertTrue(isDead(vmStateFromJson(["state": "bogus"])))
    }

    func testElpianGovernorOverBinding() async throws {
        let b = FakeVmBinding()
        plat.vm = b
        b.governanceReplies["elpian_usage"] = #"{"instructions":3}"#
        b.governanceReplies["elpian_capability_allows"] = #"{"allowed":true}"#
        b.governanceReplies["elpian_enforce_tree_budgets"] = #"[{"machineId":"a","axis":"memory","destroyed":["a","b"]},5]"#
        let available = await elpianGovernanceAvailable()
        XCTAssertTrue(available)
        let g = ElpianVmGovernor("m1")
        XCTAssertEqual(g.governanceSupport, FULL_SUPPORT)
        let usage = try await g.usage()
        XCTAssertEqual(usage.instructions, 3)
        let allows = try await g.allowsApi("fetch")
        XCTAssertTrue(allows)
        do {
            try await g.pause()
            XCTFail("missing export must throw")
        } catch let e as ElpianGovernanceException {
            XCTAssertEqual(e.call, "elpian_pause")
        }
        let violations = try await ElpianTreeGovernor().enforceTreeBudgets()
        XCTAssertEqual(violations, [ElpianBudgetViolation(machineId: "a", axis: "memory", destroyed: ["a", "b"])])
    }

    func testHostSideGovernorGatesAndTraps() async throws {
        var terminated = 0
        let g = HostSideGovernor("q", enforcesInstructions: true, hooks: GovernorHooks(onTerminate: { terminated += 1 }))
        try await g.sandbox([.logging])
        XCTAssertNil(g.checkAndCharge("println", 3))
        XCTAssertEqual(g.checkAndCharge("net.fetch"), "capability network is denied")
        try await g.setLimits(ElpianLimits(maxInstructions: 1))
        XCTAssertEqual(g.checkAndCharge("println"), "host-call limit exceeded (1)")
        XCTAssertEqual(terminated, 1)
        XCTAssertEqual(g.checkAndCharge("println"), "instance is terminated")
        let usage = try await g.usage()
        XCTAssertEqual(usage.storageBytes, 3)
        do {
            try await UnenforcedGovernor("not here").setLimits(Limits.sandboxed)
            XCTFail()
        } catch {
            XCTAssertEqual("\(error)", "ElpianGovernanceException: setLimits failed: not here")
        }
    }

    // ---- Elpian VM host-call loop ------------------------------------------------

    func testElpianVmHostCallLoop() async throws {
        let b = FakeVmBinding()
        plat.vm = b
        let vm = try await ElpianVm.fromCode("m1", "code")!
        var seen: [(String, String)] = []
        vm.registerHostHandler("add") { api, payload in
            seen.append((api, payload))
            return .now(Typed.makeResponse("i64", 3.0))
        }
        let out = try await vm.run()
        XCTAssertEqual(seen.map { $0.1 }, ["[1,2]"])
        XCTAssertEqual(out, "result:" + Typed.makeResponse("i64", 3.0))
        XCTAssertFalse(vm.isRunning)

        // An async (`later`) reply is awaited.
        vm.registerHostHandler("later") { _, _ in .deferred { "async-answer" } }
        let later = try await vm.callFunction("f")
        XCTAssertEqual(later, "result:async-answer")

        // Built-ins: println logs, env.get returns the host data, stringify wraps the payload.
        try await vm.setGlobalHostData(["env": "dev"])
        _ = try await vm.callFunctionWithInput("g", "{\"x\":1}")
        XCTAssertTrue(plat.logs.contains("ElpianVm[m1]: {\"x\":1}"))
        let msg = try await vm.deliverHostMessage("hi")
        XCTAssertEqual(msg, "result:" + #"{"type":"string","data":{"value":"hi"}}"#)

        // A throwing handler answers the VM with an error string.
        vm.registerHostHandler("add") { _, _ in .deferred { throw ElpianError("bad") } }
        let errOut = try await vm.run()
        XCTAssertEqual(errOut, "result:" + #"{"type":"string","data":{"value":"error: Error: bad"}}"#)

        let bc = try await ElpianVm.fromBytecode("m2", base64: "AQID")
        XCTAssertNotNil(bc)
        await vm.dispose()
        XCTAssertEqual(b.destroyed, ["m1"])
        let created = try await createRuntime(.elpian, "m3", RuntimeSource(astJson: "{}"))
        XCTAssertNotNil(created as? ElpianVm)
    }

    func testElpianVmWithoutRuntime() async throws {
        let vm = ElpianVm(machineId: "x")
        let out = try await vm.run()
        XCTAssertEqual(out, #"{"error":"native_lib_not_loaded"}"#)
        XCTAssertFalse(ElpianVm.isRuntimeAvailable)
        do {
            _ = try await ElpianVm.fromCode("x", "")
            XCTFail()
        } catch {
            XCTAssertEqual("\(error)", "Error: Elpian VM runtime unavailable: no Elpian VM binding on this platform")
        }
    }

    // ---- QuickJS ------------------------------------------------------------------

    func testQuickJsProtocol() async throws {
        let sandbox = FakeJsSandbox()
        plat.js = sandbox
        let vm = try await QuickJsVm.fromCode("q1", "main()")
        XCTAssertEqual(sandbox.evaluated, [ASK_HOST_BOOTSTRAP])
        XCTAssertTrue(ASK_HOST_BOOTSTRAP.hasPrefix("\nglobalThis.askHost = function(apiName) {\n"))
        XCTAssertTrue(ASK_HOST_BOOTSTRAP.hasSuffix("};\n"))

        vm.registerHostHandler("sum") { _, payload in .now("sum:" + payload) }
        vm.registerHostHandler("slow") { _, _ in .deferred { "never seen" } }
        sandbox.onEvaluate = { code in
            if code == "main()" { return sandbox.handler!("sum", "[1,2]") + "|" + sandbox.handler!("slow", "") }
            return "ok"
        }
        let out = try await vm.run()
        XCTAssertEqual(out, "sum:[1,2]|" + Typed.OK_RESPONSE)
        XCTAssertEqual(sandbox.handler!("env.get", ""), #"{"type":"object","data":{"value":{}}}"#)

        _ = try await vm.callFunctionWithInput("handle", "{\"a\":\"b\"}")
        XCTAssertEqual(sandbox.evaluated.last, #"handle(JSON.parse("{\"a\":\"b\"}"));"#)
        _ = try await vm.callFunction("tick")
        XCTAssertEqual(sandbox.evaluated.last, "tick();")
        try await vm.setGlobalHostData(["k": 1.0])
        XCTAssertEqual(sandbox.evaluated.last, """
        (function() {
          var __env = JSON.parse("{\\"k\\":1}");
          globalThis.__ELPIAN_HOST_ENV__ = __env;
          globalThis.ELPIAN_HOST_ENV = __env;
          globalThis.getElpianHostEnv = function() { return globalThis.__ELPIAN_HOST_ENV__; };
        })();
        """)

        // The governor gates host calls; a trap disposes the sandbox.
        try await vm.governor.sandbox([.logging])
        XCTAssertEqual(sandbox.handler!("sum", "[]"), Typed.NULL_RESPONSE)
        try await vm.governor.setLimits(ElpianLimits(maxStorageBytes: 2))
        XCTAssertEqual(sandbox.handler!("println", "too long"), Typed.NULL_RESPONSE)
        XCTAssertTrue(sandbox.disposed)
        let after = try await vm.run()
        XCTAssertEqual(after, "")
    }

    // ---- WASM ---------------------------------------------------------------------

    func testWasmAbi() async throws {
        let inst = FakeWasmInstance()
        plat.wasmEngine = inst
        plat.assets["guest.wasm"] = "AGFzbQ=="
        let vm = try await WasmVm.fromCode("w1", #"{"wasmAssetPath":"guest.wasm"}"#)
        do {
            _ = try await vm.callFunction("f")
            XCTFail()
        } catch {
            XCTAssertEqual("\(error)", "Error: WASM runtime is not initialized. Call run() first.")
        }
        var payloads: [String] = []
        vm.registerHostHandler("echo") { _, p in
            payloads.append(p)
            return .now("echo:" + p)
        }
        let out = try await vm.run()
        XCTAssertEqual(payloads, [#"{"a":1}"#])
        XCTAssertEqual(out, #"echo:{"a":1}"#)

        let called = try await vm.callFunction("go")
        XCTAssertEqual(called, "called go")
        XCTAssertEqual(inst.deallocs.count, 1)
        XCTAssertEqual(inst.deallocs[0][1], 2)
        let withInput = try await vm.callFunctionWithInput("fn", "[1]")
        XCTAssertEqual(withInput, "fn([1])")
        XCTAssertEqual(inst.deallocs.count, 3)

        let cfg = try parseWasmConfig(#"{"wasmBase64":"AGFzbQ==","exports":{"run":"start"}}"#)
        XCTAssertEqual(cfg.exports.run, "start")
        XCTAssertEqual(cfg.exports.getResultLen, "get_result_len")
        XCTAssertThrowsError(try parseWasmConfig("[]"))
        await vm.dispose()
        do {
            _ = try await vm.callFunction("go")
            XCTFail()
        } catch {}
    }
}
