import XCTest
@testable import ElpianCore

final class GodotTests: XCTestCase {
    func testTypedValuesMarshalToTaggedWire() {
        XCTAssertEqual(JSON.stringify(marshal(Vector3(0, 1, 2.5))), #"{"vec3":[0,1,2.5]}"#)
        XCTAssertEqual(JSON.stringify(marshal(GInt(3.9))), #"{"int":3}"#)
        XCTAssertEqual(JSON.stringify(marshal(GSignal(7, "pressed"))), #"{"sig":[{"ref":7},"pressed"]}"#)
        XCTAssertEqual(JSON.stringify(marshal(GodotColor.hex(0xff8000))), #"{"color":[1,0.5019607843137255,0,1]}"#)
        XCTAssertEqual(JSON.stringify(marshal(["a": 1.0] as JSONObject)), #"{"dict":{"a":1}}"#)
        XCTAssertEqual(JSON.stringify(marshal([1, "x", true, nil, Vector2(1, 2)] as [Any?])), #"[1,"x",true,null,{"vec2":[1,2]}]"#)
        XCTAssertEqual(JSON.stringify(marshal(GDict([(1.0, Vector2i(1, 2))]))), #"{"dictv":[[1,{"vec2i":[1,2]}]]}"#)
        XCTAssertEqual(JSON.stringify(marshal(Packed.vector3s([1, 2, 3]))), #"{"pv3":[1,2,3]}"#)
    }

    func testRoundTrips() throws {
        let values: [Any?] = [
            Vector2(1, 2), Vector2i(3, 4), Vector3(1, 2, 3), Vector3i(1, 2, 3), Vector4(1, 2, 3, 4), Vector4i(1, 2, 3, 4),
            GodotColor(0.1, 0.2, 0.3, 0.4), Rect2(1, 2, 3, 4), Rect2i(1, 2, 3, 4), Plane(0, 1, 0, 5), Quaternion(0, 0, 0, 1),
            AABB(1, 2, 3, 4, 5, 6), Basis([[1, 0, 0], [0, 1, 0], [0, 0, 1]]), Transform2D([1, 0, 0, 1, 0, 0]),
            Transform3D([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]), Projection(Array(repeating: 0, count: 16)), StringName("s"),
            NodePath("a/b"), GRid(12), GCallable(4),
        ]
        for v in values {
            let wire = try JSON.parse(JSON.stringify(marshal(v)))
            let back = unmarshal(wire)
            XCTAssertEqual(JSON.stringify(marshal(back)), JSON.stringify(marshal(v)))
            XCTAssertEqual(String(describing: type(of: back!)), String(describing: type(of: v!)))
        }
        XCTAssertEqual(unmarshal(try JSON.parse(#"{"ref":9}"#)) as? GodotRef, GodotRef(9))
        XCTAssertEqual(unmarshal(try JSON.parse(#"{"int":"7.8"}"#)) as? Double, 7)
        XCTAssertEqual(unmarshal(try JSON.parse(#"{"vec2i":[1.7,-2.7]}"#)) as? Vector2i, Vector2i(1, -2))
        let dict = asMap(unmarshal(try JSON.parse(#"{"dict":{"p":{"vec3":[1,2,3]}}}"#)))
        XCTAssertEqual(dict?["p"] as? Vector3, Vector3(1, 2, 3))
        let dv = unmarshal(try JSON.parse(#"{"dictv":[[{"sname":"k"},{"float":1.5}]]}"#)) as? GDict
        XCTAssertEqual(dv?.entries.first?.0 as? StringName, StringName("k"))
        XCTAssertEqual(dv?.entries.first?.1 as? Double, 1.5)
        XCTAssertEqual((unmarshal(try JSON.parse(#"{"u8":"AAE="}"#)) as? Packed)?.tag, "u8")
        // Errors, multi-key objects and unknown tags pass through.
        XCTAssertTrue(isWireError(unmarshal(wireError("boom"))))
        XCTAssertEqual(wireErrorMessage(wireError("boom")), "boom")
        XCTAssertNotNil(unmarshal(JSONObject([("a", 1.0), ("b", 2.0)])) as? JSONObject)
        XCTAssertTrue(GodotRef.isRef(try JSON.parse(#"{"ref":3}"#)))
        XCTAssertFalse(GodotRef.isRef(try JSON.parse(#"{"ref":3.5}"#)))
        XCTAssertEqual(try decodeReplies("[1,null]").count, 2)
        XCTAssertEqual(try decodeReplies("5").count, 1)
        XCTAssertEqual(try decodeReplies("").count, 0)
    }

    func testControllerQueuesBatchesAndRequests() async throws {
        let mock = MockGodotBinding()
        let c = GodotController(mock, surfaceId: 42)
        c.beginBatch()
        let cube = c.g3.mesh("sphere", ["radius": 2.0, "color": GodotColor(1, 0, 0), "position": [1.0, 2.0, 3.0] as [Any?]])
        c.mount(cube)
        XCTAssertEqual(mock.ops.count, 0)
        XCTAssertGreaterThan(c.pendingOps, 0)
        c.endBatch()
        XCTAssertEqual(c.pendingOps, 0)
        let wire = mock.ops.map { JSON.stringify($0) }
        XCTAssertEqual(wire[0], #"{"new":"MeshInstance3D","def":2}"#)
        XCTAssertEqual(wire[1], #"{"new":"SphereMesh","def":3}"#)
        XCTAssertEqual(wire[2], #"{"ref":3,"set":"radius","value":{"float":2}}"#)
        XCTAssertEqual(wire[3], #"{"ref":3,"set":"height","value":{"float":4}}"#)
        XCTAssertTrue(wire.contains(#"{"ref":4,"set":"albedo_color","value":{"color":[1,0,0,1]}}"#))
        XCTAssertTrue(wire.contains(#"{"ref":2,"set":"position","value":{"vec3":[1,2,3]}}"#))
        XCTAssertEqual(wire.last, #"{"ref":1,"method":"add_child","args":[{"ref":2}]}"#)

        // request() flushes the queue with the read last and unmarshals the reply.
        let tree = c.tree()
        let reply = try await tree.call("get_root")
        XCTAssertNil(reply)
        let loaded = try await c.g3.instanceScene("res://x.tscn")
        XCTAssertNil(loaded)
        XCTAssertEqual(JSON.stringify(mock.ops[mock.ops.count - 2]), #"{"load":"res://x.tscn","def":6}"#)

        // Signals: connect registers a callback, the engine fires it with unmarshalled args.
        var got: [Any?] = []
        c.beginBatch()
        let id = cube.connect("ready", { got = $0 }, flags: 4)
        c.endBatch()
        XCTAssertEqual(JSON.stringify(mock.ops.last!), #"{"ref":2,"connect":"ready","cb":1,"flags":4}"#)
        mock.fireSignal(id, [JSONObject([("vec2", [1.0, 2.0] as [Any?])])])
        XCTAssertEqual(got.first as? Vector2, Vector2(1, 2))

        await c.attachSurface()
        XCTAssertEqual(mock.surfaces[42], 1)
        XCTAssertTrue(c.isAttached)
        await c.detachSurface()
        XCTAssertNil(mock.surfaces[42])
    }

    func testRequestErrorThrows() async {
        final class ErrBinding: GodotBinding {
            var isLive: Bool { true }
            var onSignal: ((Int, [Any?]) -> Void)?
            func send(_ ops: [Op]) async throws -> [Wire] { ops.map { _ in wireError("nope") } }
            func post(_ ops: [Op]) {}
            func mountSurface(_ surfaceId: Int, _ mountHandle: Int) async {}
            func releaseSurface(_ surfaceId: Int) async {}
            func stats() async -> JSONObject? { nil }
            func dispose() {}
        }
        let c = GodotController(ErrBinding())
        do {
            _ = try await c.constant("PI")
            XCTFail("expected a throw")
        } catch let e as GodotOpException {
            XCTAssertEqual(e.description, #"GodotOpException: nope (op: {"const":"PI"})"#)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSceneDsl() {
        let mock = MockGodotBinding()
        let sc = GodotSceneController(mock)
        let json = (try? JSON.parse(#"""
        {"environment":{"bg":"#0d1117"},"camera":{"id":"cam","position":[0,3,8],"fov":55},
         "lights":[{"type":"omni","energy":2}],
         "nodes":[{"type":"group","id":"g","children":[{"type":"mesh","shape":"torus","id":"ring","color":"#f00"}]},
                  {"type":"Label3D","props":{"modulate":"#00ff00","text":"hi"}}]}
        """#)) as? JSONObject
        let scene = sc.replaceScene(json!)
        XCTAssertEqual(scene.roots.count, 5)
        XCTAssertNotNil(scene.byId("ring"))
        XCTAssertNotNil(sc.node("cam"))
        XCTAssertEqual(parseGodotColor("#f00"), GodotColor(1, 0, 0, 1))
        XCTAssertEqual(parseGodotColor("#ff000080")?.a ?? 0, 128.0 / 255, accuracy: 1e-12)
        XCTAssertNil(parseGodotColor("#12345"))
        XCTAssertEqual(parseGodotColor([0.5, 0.5, 0.5] as [Any?]), GodotColor(0.5, 0.5, 0.5, 1))
        let wire = mock.ops.map { JSON.stringify($0) }
        XCTAssertTrue(wire.contains { $0.contains(#""props":{"modulate":{"color":[0,1,0,1]},"text":"hi"}"#) })
        XCTAssertTrue(wire.contains { $0.contains(#""set":"fov","value":{"float":55}"#) })
    }
}
