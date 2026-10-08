import XCTest
@testable import ElpianCore

final class JSONTests: XCTestCase {
    func testNumberFormattingMatchesJavaScript() {
        // Expected strings are what `JSON.stringify` prints in V8.
        let cases: [(Double, String)] = [
            (1, "1"), (1.5, "1.5"), (0.1, "0.1"), (1e21, "1e+21"), (1e-7, "1e-7"),
            (123456789012345680000, "123456789012345680000"), (-0.0, "0"), (0.000001, "0.000001"),
            (1.7976931348623157e308, "1.7976931348623157e+308"), (5e-324, "5e-324"), (100, "100"),
            (9007199254740992, "9007199254740992"), (1e16, "10000000000000000"), (123.456e-10, "1.23456e-8"),
            (-2.5e-8, "-2.5e-8"), (-42, "-42"), (0.5, "0.5"), (1234.5678, "1234.5678"),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(JSON.formatNumber(value), expected, "formatting \(value)")
        }
        XCTAssertEqual(JSON.stringify(Double.nan), "null")
        XCTAssertEqual(JSON.stringify(Double.infinity), "null")
        XCTAssertEqual(jsNumberToString(.nan), "NaN")
    }

    func testRoundTripKeepsJavaScriptKeyOrder() throws {
        let text = #"{"b":1,"2":2,"1":3,"a":{"x":[1,"é\n",null,true]}}"#
        let parsed = try JSON.parse(text)
        XCTAssertEqual(JSON.stringify(parsed), #"{"1":3,"2":2,"b":1,"a":{"x":[1,"é\n",null,true]}}"#)
        let again = try JSON.parse(JSON.stringify(parsed))
        XCTAssertTrue(deepEqual(parsed, again))
    }

    func testStringEscapes() throws {
        let s = "q\"b\\s/\u{1}\t\u{2028}😀"
        let json = JSON.stringify(s)
        XCTAssertEqual(json, "\"q\\\"b\\\\s/\\u0001\\t\u{2028}😀\"")
        XCTAssertEqual(try JSON.parse(json) as? String, s)
        XCTAssertEqual(try JSON.parse(#""😀""#) as? String, "😀")
    }

    func testInvalidDocumentsThrow() {
        for bad in ["", "{", "[1,]", "{\"a\" 1}", "01", "1.", "tru", "\"a", "{} x", "-", "\"\u{1}\""] {
            XCTAssertThrowsError(try JSON.parse(bad), "should reject \(bad)")
        }
        XCTAssertNil(JSON.parseOrNil("nope"))
    }

    func testNullsAndPresence() throws {
        let o = try XCTUnwrap(JSON.parse(#"{"a":null,"b":[null]}"#) as? JSONObject)
        XCTAssertTrue(o.has("a"))
        XCTAssertNil(o["a"])
        XCTAssertFalse(o.has("c"))
        XCTAssertEqual(asArray(o["b"])?.count, 1)
        o["c"] = nil as Any?
        XCTAssertEqual(JSON.stringify(o), #"{"a":null,"b":[null],"c":null}"#)
        o.removeValue(forKey: "a")
        XCTAssertEqual(JSON.stringify(o), #"{"b":[null],"c":null}"#)
    }

    func testSwiftValuesSerialize() {
        let o: JSONObject = ["i": 3, "d": 2.5, "b": true, "s": "x", "arr": [1, 2] as [Any?], "ins": EdgeInsets.all(2)]
        XCTAssertEqual(JSON.stringify(o), #"{"i":3,"d":2.5,"b":true,"s":"x","arr":[1,2],"ins":{"top":2,"right":2,"bottom":2,"left":2}}"#)
        let typedArrays = JSONObject()
        typedArrays["m"] = [1.0, 0.5] as Matrix4
        typedArrays["c"] = [Color(0xFF000000)]
        typedArrays["g"] = [Gradient(kind: .linear, colors: [0], begin: .topLeft, end: .bottomRight)]
        XCTAssertEqual(JSON.stringify(typedArrays), #"{"m":[1,0.5],"c":[4278190080],"g":[{"kind":"linear","colors":[0],"stops":null,"begin":{"x":-1,"y":-1},"end":{"x":1,"y":1}}]}"#)
        XCTAssertTrue(deepEqual(typedArrays["m"], [1, 0.5] as [Any?]))
    }

    func testLooseHelpers() {
        XCTAssertEqual(toNumber("12.5px"), 12.5)
        XCTAssertNil(toNumber("px"))
        XCTAssertEqual(toInt(-3.7), -3)
        XCTAssertEqual(toStr(3.0), "3")
        XCTAssertEqual(jsString([1, nil, "a"] as [Any?]), "1,,a")
        XCTAssertEqual(parseVmPayload("\"abc") as? String, "\"abc")
        XCTAssertEqual(parseVmPayload("\"abc\"") as? String, "abc")
        XCTAssertEqual(parseVmPayload("hello") as? String, "hello")
        XCTAssertEqual(normalizedArgs(#"[{"k":1}]"#)["k"] as? Double, 1)
        XCTAssertEqual(coerceJsonMap(#"{"k":"v"}"#)?["k"] as? String, "v")
        XCTAssertEqual(stableKey(JSONObject([("b", 1), ("a", [true] as [Any?])])), #"{"a":[true],"b":1}"#)
        let merged = deepMerge(["a": JSONObject([("x", 1), ("y", 2)])], ["a": JSONObject([("y", 3)]), "b": 4])
        XCTAssertEqual(JSON.stringify(merged), #"{"a":{"x":1,"y":3},"b":4}"#)
        XCTAssertEqual(jsParseFloat("  -1.5e3abc"), -1500)
        XCTAssertEqual(jsParseFloat(".5"), 0.5)
        XCTAssertTrue(jsParseFloat("abc").isNaN)
        XCTAssertEqual(jsParseInt("42px"), 42)
        XCTAssertEqual(jsRound(-2.5), -2)
        XCTAssertEqual(jsRound(2.5), 3)
    }

    func testTypedEnvelope() throws {
        let typed = Typed.toTypedVmValue(try JSON.parse(#"{"a":1,"b":1.5,"c":[true,null,"x"]}"#))
        XCTAssertEqual(
            JSON.stringify(typed),
            #"{"type":"object","data":{"value":{"a":{"type":"i64","data":{"value":1}},"b":{"type":"f64","data":{"value":1.5}},"c":{"type":"array","data":{"value":[{"type":"bool","data":{"value":true}},{"type":"null","data":{"value":null}},{"type":"string","data":{"value":"x"}}]}}}}}"#
        )
        XCTAssertEqual(JSON.stringify(Typed.fromTypedVmValue(typed)), #"{"a":1,"b":1.5,"c":[true,null,"x"]}"#)
        XCTAssertEqual(Typed.OK_RESPONSE, #"{"type":"i16","data":{"value":0}}"#)
        XCTAssertEqual(Typed.NULL_RESPONSE, #"{"type":"null","data":{"value":null}}"#)
    }

    func testBytes() throws {
        let bytes = Bytes.utf8Encode("héllo 😀")
        XCTAssertEqual(Bytes.utf8Decode(bytes), "héllo 😀")
        XCTAssertEqual(Bytes.utf8Decode([0x61, 0xFF, 0x62, 0xE2, 0x82]), "a\u{FFFD}b\u{FFFD}")
        XCTAssertEqual(Bytes.base64Encode(Array("hello".utf8)), "aGVsbG8=")
        XCTAssertEqual(try Bytes.base64Decode("aGVs bG8="), Array("hello".utf8))
        XCTAssertEqual(try Bytes.base64Decode("-_8"), [0xFB, 0xFF])
        XCTAssertThrowsError(try Bytes.base64Decode("a*b"))
    }

    func testNodeFromJson() throws {
        let json = try XCTUnwrap(JSON.parse(#"{"type":"div","key":7,"style":{"color":"red"},"className":"a  b","children":["hi",3,{"type":"span"}],"events":{"click":"onClick"}}"#) as? JSONObject)
        let node = ElpianNode.fromJson(json)
        XCTAssertEqual(node.key, "7")
        XCTAssertEqual(node.classes, ["a", "b"])
        XCTAssertEqual(node.children.map { $0.type }, ["#text", "#text", "span"])
        XCTAssertEqual(node.children[1].text, "3")
        XCTAssertNotNil(asMap(node.props["style"]))
        XCTAssertEqual(
            JSON.stringify(node.toJson()),
            ##"{"type":"div","props":{"style":{"color":"red"},"className":"a  b"},"children":[{"type":"#text","props":{"text":"hi"},"children":[]},{"type":"#text","props":{"text":"3"},"children":[]},{"type":"span","props":{},"children":[]}],"key":"7","events":{"click":"onClick"}}"##
        )
    }
}
