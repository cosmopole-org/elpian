import XCTest
@testable import ElpianCore

/**
 * Flex / wrap / grid / table / scroll layouts through the reconciler. Every
 * expected dump was produced by running the same tree through the
 * TypeScript engine (native/web/src) with the same fake text measurement
 * (see [TextFakePlatform]).
 */
final class RenderLayoutTests: XCTestCase {
    private func box(_ width: Double, _ height: Double) -> W { w("constrained", ["width": width, "height": height]) }
    private func loose(_ width: Double, _ height: Double) -> Constraints { Constraints(minWidth: 0, maxWidth: width, minHeight: 0, maxHeight: height) }
    private func text(_ s: String) -> W { w("text", ["text": s]) }

    private func check(_ tree: W, _ c: Constraints, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(dumpTree(layoutTree(tree, c)), expected, file: file, line: line)
    }

    // ---- flex ----

    func testFlexSpaceEvenlyCrossEnd() {
        check(w("flex", ["direction": "row", "mainAxisAlignment": "spaceEvenly", "crossAxisAlignment": "end"], [box(40, 10), box(60, 30), box(20, 20)]), loose(400, 300), [
            "flex 400 30 0 0", "constrained 40 10 70 20", "constrained 60 30 180 0", "constrained 20 20 310 10",
        ])
    }

    func testFlexColumnGapReverse() {
        check(w("flex", ["direction": "column", "gap": 5.0, "reverse": true, "mainAxisSize": "min", "crossAxisAlignment": "center"], [box(40, 10), box(60, 30), box(20, 20)]), loose(400, 300), [
            "flex 60 70 0 0", "constrained 40 10 10 60", "constrained 60 30 0 25", "constrained 20 20 20 0",
        ])
    }

    func testFlexLooseAndTightFlexibles() {
        check(w("flex", ["direction": "row"], [box(50, 10), w("flexible", ["flex": 2.0, "fit": "loose"], [box(30, 10)]), w("flexible", ["flex": 1.0], [box(10, 10)])]), loose(350, 100), [
            "flex 350 10 0 0", "constrained 50 10 0 0", "flexible 30 10 50 0", "constrained 30 10 0 0", "flexible 270 10 80 0", "constrained 270 10 0 0",
        ])
    }

    func testFlexCssShrink() {
        check(w("flex", ["direction": "row", "shrink": true], [
            w("flexible", ["shrink": 1.0], [text("aaaaaaaaaaaaaaaaaaaa")]),
            w("flexible", ["shrink": 2.0], [text("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")]),
        ]), loose(200, 300), [
            "flex 200 51 0 0", "flexible 102.5 34 0 0", "text 102.5 34 0 0", "flexible 97.5 51 102.5 0", "text 97.5 51 0 0",
        ])
    }

    func testFlexBaselineAlignment() {
        check(w("flex", ["direction": "row", "crossAxisAlignment": "baseline"], [w("text", ["text": "ab", "style": TextStyle(fontSize: 20)]), text("cd"), box(10, 5)]), loose(400, 300), [
            "flex 400 24 0 0", "text 20 24 0 0", "text 14 17 20 4.799999999999999", "constrained 10 5 34 11",
        ])
    }

    func testFlexStretchAndBasis() {
        check(w("flex", ["direction": "row", "crossAxisAlignment": "stretch"], [w("flexible", ["basis": 70.0], [box(10, 10)]), box(30, 20)]), loose(400, 120), [
            "flex 400 120 0 0", "flexible 70 120 0 0", "constrained 70 120 0 0", "constrained 30 120 70 0",
        ])
    }

    // ---- wrap ----

    func testWrapRuns() {
        check(w("wrap", ["spacing": 10.0, "runSpacing": 5.0], [box(100, 20), box(100, 30), box(100, 20), box(150, 10), box(50, 50)]), loose(330, 300), [
            "wrap 320 85 0 0", "constrained 100 20 0 0", "constrained 100 30 110 0", "constrained 100 20 220 0", "constrained 150 10 0 35", "constrained 50 50 160 35",
        ])
    }

    func testWrapCenteredRunsAtEnd() {
        check(w("wrap", ["spacing": 4.0, "runSpacing": 6.0, "alignment": "center", "crossAxisAlignment": "center", "runAlignment": "end"], [box(100, 20), box(100, 30), box(100, 20), box(150, 10)]), tight(300, 200), [
            "wrap 300 200 0 0", "constrained 100 20 48 149", "constrained 100 30 152 144", "constrained 100 20 23 180", "constrained 150 10 127 185",
        ])
    }

    func testWrapVerticalSpaceBetween() {
        check(w("wrap", ["direction": "vertical", "spacing": 2.0, "alignment": "spaceBetween"], [box(30, 40), box(20, 40), box(40, 40), box(10, 40)]), loose(300, 100), [
            "wrap 70 82 0 0", "constrained 30 40 0 0", "constrained 20 40 0 42", "constrained 40 40 30 0", "constrained 10 40 30 42",
        ])
    }

    func testWrapSpaceAroundReversedUp() {
        check(w("wrap", ["spacing": 0.0, "alignment": "spaceAround", "reverse": true, "verticalDirection": "up"], [box(60, 10), box(60, 20), box(60, 30)]), loose(130, 300), [
            "wrap 120 50 0 0", "constrained 60 10 60 30", "constrained 60 20 0 30", "constrained 60 30 30 0",
        ])
    }

    // ---- grid ----

    func testGridRepeatEqualColumns() {
        check(w("grid", ["columns": "repeat(3, 1fr)", "columnGap": 10.0, "rowGap": 5.0], [box(10, 20), box(10, 30), box(10, 10), box(10, 15), box(10, 25)]), loose(320, 500), [
            "grid 320 60 0 0", "constrained 100 20 0 0", "constrained 100 30 110 0", "constrained 100 10 220 0", "constrained 100 15 0 35", "constrained 100 25 110 35",
        ])
    }

    func testGridMixedPxAndFr() {
        check(w("grid", ["columns": "100px 1fr 2fr", "columnGap": 4.0], [box(10, 20), box(10, 30), box(10, 10)]), loose(400, 500), [
            "grid 400 30 0 0", "constrained 100 20 0 0", "constrained 97.33333333333333 30 104 0", "constrained 194.66666666666666 10 205.33333333333331 0",
        ])
    }

    func testGridAutoFillMinmax() {
        check(w("grid", ["columns": "repeat(auto-fill, minmax(80px, 1fr))", "columnGap": 10.0, "rowGap": 10.0], [box(10, 20), box(10, 20), box(10, 20), box(10, 20), box(10, 20)]), loose(300, 500), [
            "grid 300 50 0 0",
            "constrained 93.33333333333333 20 0 0",
            "constrained 93.33333333333333 20 103.33333333333333 0",
            "constrained 93.33333333333333 20 206.66666666666666 0",
            "constrained 93.33333333333333 20 0 30",
            "constrained 93.33333333333333 20 103.33333333333333 30",
        ])
    }

    func testGridSpansPlacementAndRowTracks() {
        check(w("grid", ["columns": "1fr 1fr 1fr", "rows": "40px auto", "alignItems": "center"], [
            w("gridItem", ["column": "span 2"], [box(10, 20)]),
            w("gridItem", ["row": "1 / 3", "column": "3"], [box(10, 100)]),
            w("gridItem", [:], [box(10, 30)]),
            w("gridItem", ["alignSelf": "end"], [box(10, 10)]),
        ]), loose(300, 500), [
            "grid 300 100 0 0",
            "gridItem 200 20 0 10", "constrained 200 20 0 0",
            "gridItem 100 100 200 0", "constrained 100 100 0 0",
            "gridItem 100 30 0 55", "constrained 100 30 0 0",
            "gridItem 100 10 100 90", "constrained 100 10 0 0",
        ])
    }

    func testGridAutoColumnStretch() {
        check(w("grid", ["columns": "auto 1fr", "columnGap": 8.0, "alignItems": "stretch"], [text("label"), box(10, 30), text("longer label"), box(10, 10)]), loose(300, 500), [
            "grid 300 47 0 0", "text 84 30 0 0", "constrained 208 30 92 0", "text 84 17 0 30", "constrained 208 17 92 30",
        ])
    }

    func testGridUnboundedFallsBackToWrap() {
        check(w("grid", ["columns": "1fr 1fr", "columnGap": 3.0, "rowGap": 4.0], [box(50, 10), box(60, 20), box(70, 30)]), Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF), [
            "grid 186 30 0 0", "constrained 50 10 0 0", "constrained 60 20 53 0", "constrained 70 30 116 0",
        ])
    }

    func testParseTemplate() {
        let t = parseTemplate("[a] 100px repeat(2, 1fr) minmax(10px, auto) 2rem")!
        XCTAssertEqual(t.tracks, [.px(100), .fr(1), .fr(1), .minMax(.px(10), .auto), .px(32)])
        XCTAssertNil(t.autoRepeat)
        let a = parseTemplate("50px repeat(auto-fit, 1fr)")!
        XCTAssertEqual(a.autoIndex, 1)
        XCTAssertEqual(a.autoRepeat?.fit, true)
        XCTAssertNil(parseTemplate("none"))
    }

    // ---- table ----

    func testTableAutoLayout() {
        check(w("table", [:], [
            w("tableRow", [:], [w("tableCell", [:], [text("Name")]), w("tableCell", [:], [text("Value")])]),
            w("tableRow", [:], [w("tableCell", [:], [text("a")]), w("tableCell", [:], [text("longer value")])]),
        ]), loose(400, 300), [
            "table 112 34 0 0",
            "tableRow 112 17 0 0", "tableCell 28 17 0 0", "text 28 17 0 0", "tableCell 84 17 28 0", "text 84 17 0 0",
            "tableRow 112 17 0 17", "tableCell 28 17 0 0", "text 28 17 0 0", "tableCell 84 17 28 0", "text 84 17 0 0",
        ])
    }

    func testTableSpansSpacingAndCaption() {
        check(w("table", ["collapse": false, "borderSpacing": 4.0, "caption": "bottom"], [
            text("Caption"),
            w("tableRow", [:], [w("tableCell", ["colSpan": 2.0], [text("wide header cell")]), w("tableCell", ["rowSpan": 2.0, "verticalAlign": "top"], [box(20, 60)])]),
            w("tableRow", [:], [w("tableCell", [:], [text("x")]), w("tableCell", ["verticalAlign": "bottom"], [box(30, 30)])]),
        ]), loose(400, 300), [
            "table 144 85 0 0",
            "text 144 17 0 68",
            "tableRow 144 17 0 4", "tableCell 112 17 4 0", "text 112 17 0 0", "tableCell 20 60 120 0", "constrained 20 60 0 0",
            "tableRow 144 39 0 25", "tableCell 42.5 39 4 0", "text 42.5 17 0 11", "tableCell 65.5 39 50.5 0", "constrained 65.5 30 0 9",
        ])
    }

    func testTableSqueezedBelowMaxContent() {
        check(w("table", ["fullWidth": true], [
            w("tableRow", [:], [w("tableCell", [:], [text("some words here")]), w("tableCell", ["width": 50.0], [text("x")])]),
        ]), loose(120, 300), [
            "table 120 34 0 0", "tableRow 120 34 0 0", "tableCell 70 34 0 0", "text 70 34 0 0", "tableCell 50 34 70 0", "text 50 17 0 8.5",
        ])
    }

    func testTableFullWidthDistributesExtra() {
        check(w("table", ["fullWidth": true], [
            w("tableRow", [:], [w("tableCell", [:], [text("ab")]), w("tableCell", [:], [text("abcd")])]),
        ]), loose(300, 300), [
            "table 300 17 0 0", "tableRow 300 17 0 0", "tableCell 100 17 0 0", "text 100 17 0 0", "tableCell 200 17 100 0", "text 200 17 0 0",
        ])
    }

    // ---- scroll ----

    func testScrollFillsViewportAndReportsContentSize() {
        let root = layoutTree(w("scroll", ["axis": "vertical", "fillViewport": true], [w("flex", ["direction": "column"], [box(50, 200), box(50, 200)])]), tight(300, 250))
        XCTAssertEqual(dumpTree(root), ["scroll 300 250 0 0", "flex 300 400 0 0", "constrained 50 200 0 0", "constrained 50 200 0 200"])
        let scroll = root as! RenderScroll
        XCTAssertEqual(JSON.stringify(scroll.viewProps()), #"{"scrollAxis":"vertical","contentSize":[300,400],"scrollEnabled":true,"showScrollbar":true,"clip":true,"gestures":null}"#)
        scroll.handleViewEvent(ViewEvent(id: 1, type: "scroll", scrollY: 500))
        XCTAssertEqual(scroll.scrollOffset, Vec(x: 0, y: 500))
        scroll.markNeedsLayout()
        scroll.layout(tight(300, 250))
        XCTAssertEqual(scroll.scrollOffset, Vec(x: 0, y: 150))
    }

    // ---- paint ----

    func testDecorationViewPropsClampsRadius() {
        let d = BoxDecoration(color: 0xFF00_FF00, radius: .all(80), shadows: [])
        let p = decorationViewProps(d, 100, 60)
        XCTAssertEqual(p["radius"] as? BorderRadius, .all(30))
        XCTAssertNil(p["shadows"])
        XCTAssertTrue(decorationIsEmpty(BoxDecoration()))
        XCTAssertFalse(decorationIsEmpty(BoxDecoration(shape: "circle")))
        let pct = resolveRadius(BoxDecoration(radiusPercent: .all(50)), 40, 20)
        XCTAssertEqual(pct, .all(10))
    }

    func testCanvasStoreNormalizesCommands() {
        let cmd = commandFromJson(JSONObject([("type", "fillRect"), ("params", JSONObject([("x", "10"), ("color", "#ff0000"), ("text", "12")]))]))
        let n = normalizeCommand(cmd)
        XCTAssertEqual(JSON.stringify(n), #"{"type":"fillRect","params":{"x":10,"color":4294901760,"text":"12"}}"#)
        XCTAssertEqual(commandFromJson(JSONObject([("type", "bogus")])).type, "custom")
        let font = parseCanvasFont("bold italic 16px Open Sans")
        XCTAssertEqual(font, ParsedCanvasFont(size: 16, family: "Open Sans", bold: true, italic: true))
        let store = CanvasContextStore()
        let ctx = store.create()
        XCTAssertEqual(ctx.id, "ctx_1")
        var changes = 0
        ctx.onChange { changes += 1 }
        ctx.addCommand(cmd)
        ctx.clear()
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(ctx.generation, 1)
        XCTAssertTrue(store.create(id: "ctx_1") === ctx)
    }

    func testImageMapAreas() {
        let poly = AreaSpec(shape: "poly", coords: [0, 0, 10, 0, 10, 10, 0, 10])
        XCTAssertTrue(areaContains(poly, 5, 5))
        XCTAssertFalse(areaContains(poly, 15, 5))
        XCTAssertEqual(areaBounds(AreaSpec(shape: "circle", coords: [10, 10, 5]), 0, 0), AreaRect(x: 5, y: 5, width: 10, height: 10))
    }
}
