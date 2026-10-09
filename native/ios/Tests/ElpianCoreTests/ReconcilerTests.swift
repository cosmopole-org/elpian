import XCTest
@testable import ElpianCore

/** A platform whose text measurement is deterministic: each character is half the font size wide, lines are 1.2 em. */
final class TextFakePlatform: Platform {
    let name = "fake"
    func now() -> Double { 0 }
    func setTimeout(_ callback: @escaping () -> Void, _ ms: Double) -> Int { 1 }
    func clearTimeout(_ handle: Int) {}
    func requestFrame(_ callback: @escaping (Double) -> Void) -> Int { 1 }
    func cancelFrame(_ handle: Int) {}
    func commit(_ surface: String, _ ops: [ViewOp]) {}
    func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        let fs = spec.spans.first?.style.fontSize ?? 14
        let chars = spec.spans.reduce(0) { $0 + jsLength($1.text) }
        let natural = Double(chars) * fs * 0.5
        // Math.ceil(natural / 0) is Infinity in JavaScript: keep the line count a Double.
        let lines: Double = maxWidth == INF || natural <= maxWidth ? 1 : (natural / maxWidth).rounded(.up)
        let lineCount = lines.isFinite ? Int(lines) : Int.max
        return TextMetrics(width: min(natural, maxWidth), height: lines * fs * 1.2, baseline: fs * 0.8, lineCount: lineCount, didExceedMaxLines: false)
    }
    func viewport(_ surface: String) -> Viewport { Viewport(width: 400, height: 300, locale: "en", platform: "ios") }
    func log(_ level: LogLevel, _ message: String) {}
}

/** `type width height x y` for every object, depth first (numbers formatted as JavaScript prints them). */
func dumpTree(_ ro: RenderObject, _ out: inout [String]) {
    func n(_ v: Double) -> String { jsNumberToString(v) }
    out.append("\(ro.type) \(n(ro.size.width)) \(n(ro.size.height)) \(n(ro.offset.x)) \(n(ro.offset.y))")
    for c in ro.children { dumpTree(c, &out) }
}

func dumpTree(_ ro: RenderObject) -> [String] {
    var out: [String] = []
    dumpTree(ro, &out)
    return out
}

func layoutTree(_ tree: W, _ c: Constraints) -> RenderObject {
    let owner = RenderOwner(surface: "s", platform: TextFakePlatform())
    let root = reconcileRoot(nil, tree, owner)
    root.layout(c)
    // Keep the owner alive with the tree (render objects hold it weakly).
    retainedOwners.append(owner)
    return root
}

private var retainedOwners: [RenderOwner] = []

final class ReconcilerTests: XCTestCase {
    private func ins(_ t: Double, _ r: Double, _ b: Double, _ l: Double) -> EdgeInsets { EdgeInsets(top: t, right: r, bottom: b, left: l) }

    // Expected outputs below were produced by running the same trees through
    // the TypeScript engine (native/web) (native/web/src) with the same fake measureText.

    func testPaddingAndFlexRow() {
        let root = layoutTree(
            w("padding", ["padding": ins(10, 10, 10, 10)], [
                w("flex", ["direction": "row", "mainAxisAlignment": "spaceBetween", "crossAxisAlignment": "center"], [
                    w("constrained", ["width": 50.0, "height": 20.0]),
                    w("flexible", ["flex": 1.0], [w("text", ["text": "hello world"])]),
                    w("constrained", ["width": 30.0, "height": 40.0]),
                ]),
            ]),
            tight(400, 300)
        )
        XCTAssertEqual(dumpTree(root), [
            "padding 400 300 0 0",
            "flex 380 280 10 10",
            "constrained 50 20 0 130",
            "flexible 300 17 50 131.5",
            "text 300 17 0 0",
            "constrained 30 40 350 120",
        ])
    }

    func testStackWithPositionedChildren() {
        let root = layoutTree(
            w("stack", ["alignment": Alignment(x: 0, y: 0)], [
                w("constrained", ["width": 100.0, "height": 50.0]),
                w("positioned", ["left": 10.0, "bottom": 5.0, "width": 20.0], [w("constrained", ["height": 10.0])]),
                w("positioned", ["right": 0.0, "top": 0.0], [w("text", ["text": "abc"])]),
            ]),
            Constraints(minWidth: 0, maxWidth: 400, minHeight: 0, maxHeight: 300)
        )
        XCTAssertEqual(dumpTree(root), [
            "stack 100 50 0 0",
            "constrained 100 50 0 0",
            "positioned 20 10 10 35",
            "constrained 20 10 0 0",
            "positioned 21 17 79 0",
            "text 21 17 0 0",
        ])
    }

    func testColumnWithWrappingText() {
        let root = layoutTree(
            w("flex", ["direction": "column", "crossAxisAlignment": "stretch", "mainAxisSize": "min"], [
                w("text", ["text": "a fairly long sentence that has to wrap around"]),
                w("padding", ["padding": ins(5, 5, 5, 5)], [w("text", ["text": "short"])]),
                w("align", ["alignment": Alignment(x: 1, y: 1), "heightFactor": 2.0], [w("constrained", ["width": 10.0, "height": 10.0])]),
            ]),
            Constraints(minWidth: 0, maxWidth: 120, minHeight: 0, maxHeight: 500)
        )
        XCTAssertEqual(dumpTree(root), [
            "flex 120 98 0 0",
            "text 120 51 0 0",
            "padding 120 27 0 51",
            "text 110 17 5 5",
            "align 120 20 0 78",
            "constrained 10 10 110 10",
        ])
    }

    func testAnimatedPaddingInterpolatesOnTheFrameClock() {
        let owner = RenderOwner(surface: "s", platform: TextFakePlatform())
        owner.rootConstraints = tight(200, 100)
        var root = reconcileRoot(nil, w("animatedPadding", ["padding": ins(0, 0, 0, 0)], [w("constrained")]), owner)
        owner.root = root
        owner.flush(0)
        root = reconcileRoot(root, w("animatedPadding", ["padding": ins(20, 20, 20, 20), "duration": 100.0], [w("constrained")]), owner)
        owner.flush(1000)
        owner.flush(1050)
        XCTAssertEqual(dumpTree(root), ["animatedPadding 200 100 0 0", "constrained 180 80 10 10"])
        owner.flush(1200)
        XCTAssertEqual(dumpTree(root), ["animatedPadding 200 100 0 0", "constrained 160 60 20 20"])
    }

    func testKeyedChildrenKeepIdentityAcrossReorder() {
        let owner = RenderOwner(surface: "s", platform: TextFakePlatform())
        func tree(_ order: [String]) -> W { w("flex", ["direction": "column"], order.map { w("constrained", ["height": 10.0], nil, $0) }) }
        let root = reconcileRoot(nil, tree(["a", "b", "c"]), owner)
        let a = root.children[0]
        let b = root.children[1]
        let c = root.children[2]
        let same = reconcileRoot(root, tree(["c", "a", "b"]), owner)
        XCTAssertTrue(root === same)
        XCTAssertTrue(c === root.children[0])
        XCTAssertTrue(a === root.children[1])
        XCTAssertTrue(b === root.children[2])
        root.layout(Constraints(minWidth: 0, maxWidth: 100, minHeight: 0, maxHeight: 100))
        XCTAssertEqual(root.children.map { $0.offset.y }, [0, 10, 20])
        // An unkeyed type change replaces the object.
        let replaced = reconcileRoot(root, w("padding"), owner)
        XCTAssertFalse(root === replaced)
    }

    func testEveryTypeKeyIsRegistered() {
        let expected = [
            "proxy", "padding", "safeArea", "fill", "constrained", "align", "aspectRatio", "fractional", "limited", "overflowBox",
            "fitted", "fittedContent", "baseline", "rotatedBox", "intrinsicWidth", "intrinsicHeight", "offstage", "indexedStack",
            "flex", "flexible", "wrap", "stack", "positioned", "grid", "imageMap", "gridItem", "scroll", "table", "tableRow",
            "tableCell", "decorated", "opacity", "transform", "clip", "ignorePointer", "visibility", "filter", "shaderMask",
            "defaultTextStyle", "text", "image", "control", "canvas", "scene3d", "media", "web", "native", "gesture",
            "animatedPadding", "animatedAlign", "animatedOpacity", "animatedTransform", "animatedConstrained", "animatedDecorated",
            "animatedPositioned", "animatedDefaultTextStyle", "animatedSize", "animatedCrossFade", "animatedSwitcher", "switcherSlot",
            "transition", "staggered", "staggerItem", "shimmer", "animatedGradient", "keyframes", "hero",
        ]
        XCTAssertEqual(expected.count, 67)
        XCTAssertTrue(registeredRenderObjectTypes().isSuperset(of: expected))
        let owner = RenderOwner(surface: "s", platform: TextFakePlatform())
        for t in expected { XCTAssertEqual(createRenderObject(w(t), owner, nil).type, t) }
        XCTAssertThrowsError(try tryCreateRenderObject(w("nope"), owner, nil))
    }

    func testPropsEqualIgnoresClosures() {
        let f1: () -> Void = {}
        let f2: (Any?) -> Void = { _ in }
        XCTAssertTrue(propsEqual(["a": 1.0, "f": f1], ["a": 1.0, "f": f2]))
        XCTAssertFalse(propsEqual(["a": 1.0], ["a": 2.0]))
        XCTAssertTrue(propsEqual(["s": TextStyle(fontSize: 12)], ["s": TextStyle(fontSize: 12)]))
        XCTAssertFalse(propsEqual(["s": TextStyle(fontSize: 12)], ["s": TextStyle(fontSize: 13)]))
    }

    func testSameConfigurationOnlyRefreshesClosures() {
        let owner = RenderOwner(surface: "s", platform: TextFakePlatform())
        var calls: [String] = []
        let first: ViewEventHandler = { _ in calls.append("first") }
        let second: ViewEventHandler = { _ in calls.append("second") }
        let root = reconcileRoot(nil, w("scroll", ["axis": "vertical", "onScroll": first]), owner)
        root.layout(tight(100, 100))
        XCTAssertFalse(root.needsLayout)
        _ = reconcileRoot(root, w("scroll", ["axis": "vertical", "onScroll": second]), owner)
        XCTAssertFalse(root.needsLayout)
        root.handleViewEvent(ViewEvent(id: 1, type: "scroll", scrollY: 0))
        XCTAssertEqual(calls, ["second"])
    }
}
