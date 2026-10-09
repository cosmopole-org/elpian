import XCTest
@testable import ElpianCore

/** A platform that records commits; frames run when the test flushes. */
final class FakePlatform: Platform {
    let name = "test"
    var committed: [[ViewOp]] = []
    var frameRequests = 0
    var viewportSize = Viewport(width: 400, height: 300, safeArea: EdgeInsets(top: 20, right: 0, bottom: 10, left: 0))

    func now() -> Double { 0 }
    func setTimeout(_ callback: @escaping () -> Void, _ ms: Double) -> Int { 0 }
    func clearTimeout(_ handle: Int) {}
    func requestFrame(_ callback: @escaping (Double) -> Void) -> Int {
        frameRequests += 1
        return frameRequests
    }
    func cancelFrame(_ handle: Int) {}
    func commit(_ surface: String, _ ops: [ViewOp]) { committed.append(ops) }
    func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        TextMetrics(width: 10, height: 10, baseline: 8, lineCount: 1, didExceedMaxLines: false)
    }
    func viewport(_ surface: String) -> Viewport { viewportSize }
    func log(_ level: LogLevel, _ message: String) {}
}

final class LayoutTests: XCTestCase {
    private func make<T: RenderObject>(_ type: T.Type, _ props: Props = Props(), _ children: [RenderObject] = []) -> T {
        let ro = T()
        ro.initialize(props)
        ro.children = children
        for c in children { c.parent = ro }
        return ro
    }

    private func sized(_ w: Double, _ h: Double) -> RenderConstrainedBox {
        make(RenderConstrainedBox.self, ["width": w, "height": h])
    }

    private let loose400x300 = Constraints(minWidth: 0, maxWidth: 400, minHeight: 0, maxHeight: 300)

    func testPaddingAroundSizedBox() {
        let box = sized(50, 30)
        let pad = make(RenderPadding.self, ["padding": EdgeInsets(top: 10, right: 20, bottom: 10, left: 20)], [box])
        pad.layout(loose400x300)
        XCTAssertEqual(pad.size, Size(width: 90, height: 50))
        XCTAssertEqual(box.size, Size(width: 50, height: 30))
        XCTAssertEqual(box.offset, Vec(x: 20, y: 10))
        XCTAssertEqual(pad.minIntrinsicWidth(INF), 90)
        XCTAssertEqual(pad.maxIntrinsicHeight(INF), 50)
    }

    func testPercentPaddingResolvesAgainstMaxWidth() {
        let box = sized(50, 30)
        let pad = make(RenderPadding.self, ["padding": EdgeInsets.all(4), "percent": SidePercents(left: Percent(10))], [box])
        pad.layout(loose400x300)
        XCTAssertEqual(box.offset, Vec(x: 40, y: 4))
        XCTAssertEqual(pad.size, Size(width: 94, height: 38))
    }

    func testPaddingTightConstraintsShrinkChild() {
        let box = sized(500, 500)
        let pad = make(RenderPadding.self, ["padding": EdgeInsets.all(10)], [box])
        pad.layout(tight(100, 80))
        XCTAssertEqual(pad.size, Size(width: 100, height: 80))
        XCTAssertEqual(box.size, Size(width: 80, height: 60))
    }

    func testAlignCentersInTightConstraints() {
        let box = sized(50, 30)
        let align = make(RenderAlign.self, ["alignment": Alignment.center], [box])
        align.layout(tight(200, 100))
        XCTAssertEqual(align.size, Size(width: 200, height: 100))
        XCTAssertEqual(box.offset, Vec(x: 75, y: 35))
    }

    func testAlignWithWidthFactorAndBottomRight() {
        let box = sized(50, 30)
        let align = make(RenderAlign.self, ["alignment": Alignment.bottomRight, "widthFactor": 2.0], [box])
        align.layout(loose400x300)
        XCTAssertEqual(align.size, Size(width: 100, height: 300))
        XCTAssertEqual(box.offset, Vec(x: 50, y: 270))
        XCTAssertEqual(align.maxIntrinsicWidth(INF), 100)

        // Unbounded axes shrink-wrap.
        let free = make(RenderAlign.self, [:], [sized(50, 30)])
        free.layout(Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF))
        XCTAssertEqual(free.size, Size(width: 50, height: 30))
    }

    func testConstrainedBoxEnforcesConstraints() {
        let inner = sized(50, 50)
        let outer = make(RenderConstrainedBox.self, ["minWidth": 100.0, "maxHeight": 20.0], [inner])
        outer.layout(loose400x300)
        XCTAssertEqual(inner.size, Size(width: 100, height: 20))
        XCTAssertEqual(outer.size, Size(width: 100, height: 20))
        XCTAssertEqual(outer.additional(), Constraints(minWidth: 100, maxWidth: INF, minHeight: 0, maxHeight: 20))

        let empty = make(RenderConstrainedBox.self, ["minWidth": 30.0, "minHeight": 10.0])
        empty.layout(loose400x300)
        XCTAssertEqual(empty.size, Size(width: 30, height: 10))
        XCTAssertEqual(empty.minIntrinsicWidth(INF), 30)
        XCTAssertEqual(sized(12, 7).maxIntrinsicHeight(INF), 7)
    }

    func testAspectRatioAndLimitedBox() {
        let ar = make(RenderAspectRatio.self, ["aspectRatio": 2.0], [sized(10, 10)])
        ar.layout(loose400x300)
        XCTAssertEqual(ar.size, Size(width: 400, height: 200))
        XCTAssertEqual(ar.children[0].size, Size(width: 400, height: 200))

        let limited = make(RenderLimitedBox.self, ["maxWidth": 120.0], [make(RenderFillAxis.self, ["width": true])])
        limited.layout(Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: 50))
        XCTAssertEqual(limited.size, Size(width: 120, height: 0))
    }

    func testRelayoutIsSkippedForSameConstraints() {
        let box = sized(50, 30)
        let pad = make(RenderPadding.self, ["padding": EdgeInsets.all(5)], [box])
        pad.layout(loose400x300)
        XCTAssertFalse(pad.needsLayout)
        box.update(["width": 60.0, "height": 30.0])
        XCTAssertTrue(pad.needsLayout)
        pad.layout(loose400x300)
        XCTAssertEqual(pad.size, Size(width: 70, height: 40))
    }

    func testOwnerCompositesPaintingObjects() {
        let platform = FakePlatform()
        let owner = RenderOwner(surface: "s", platform: platform)
        let leaf = sized(50, 30)
        let rotated = make(RenderRotatedBox.self, ["quarterTurns": 1.0], [leaf])
        let root = make(RenderAlign.self, [:], [rotated])
        owner.root = root
        root.visit { $0.attach(owner) }

        let first = owner.flush(16)
        XCTAssertEqual(rotated.size, Size(width: 30, height: 50))
        XCTAssertEqual(first.count, 1)
        guard case let .create(id, kind, parent, index, props)? = first.first else { return XCTFail("expected a create") }
        XCTAssertEqual(kind, .view)
        XCTAssertEqual(parent, ROOT_VIEW_ID)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(JSON.stringify(props["frame"]), "[185,125,30,50]")
        XCTAssertEqual(JSON.stringify(props["transformOrigin"]), "[0,0]")
        XCTAssertEqual(platform.committed.count, 1)

        // Nothing changed: no ops, nothing committed.
        XCTAssertTrue(owner.flush(32).isEmpty)
        XCTAssertEqual(platform.committed.count, 1)

        // Moving the child updates only the frame.
        root.update(["alignment": Alignment.topLeft])
        let moved = owner.flush(48)
        guard case let .update(uid, changed)? = moved.first else { return XCTFail("expected an update") }
        XCTAssertEqual(uid, id)
        XCTAssertEqual(changed.keys, ["frame"])
        XCTAssertEqual(JSON.stringify(changed["frame"]), "[0,0,30,50]")
        XCTAssertTrue(owner.compositor.objectFor(id) === rotated)

        owner.dispose()
        XCTAssertEqual(platform.committed.last.map { JSON.stringify($0.map { $0.toJSON() }) }, #"[{"op":"remove","id":1}]"#)
    }

    func testSafeAreaAndIndexedStack() {
        let platform = FakePlatform()
        let owner = RenderOwner(surface: "s", platform: platform)
        let safe = make(RenderSafeArea.self, ["bottom": false], [sized(10, 10)])
        safe.attach(owner)
        safe.layout(loose400x300)
        XCTAssertEqual(safe.children[0].offset, Vec(x: 0, y: 20))
        XCTAssertEqual(safe.size, Size(width: 10, height: 30))

        let a = sized(10, 10)
        let b = sized(30, 20)
        let stack = make(RenderIndexedStack.self, ["index": 1.0, "alignment": Alignment.center], [a, b])
        stack.layout(loose400x300)
        XCTAssertEqual(stack.size, Size(width: 30, height: 20))
        XCTAssertEqual(a.offset, Vec(x: 10, y: 5))
        XCTAssertFalse(stack.paintsChild(a))
        XCTAssertTrue(stack.paintsChild(b))
    }

    func testAnimationControllerTicks() {
        let platform = FakePlatform()
        let owner = RenderOwner(surface: "s", platform: platform)
        let controller = AnimationController(100)
        controller.attach(owner)
        var completed = false
        controller.forward().then { completed = true }
        XCTAssertEqual(controller.status, .forward)
        owner.flush(0)
        owner.flush(50)
        XCTAssertEqual(controller.value, 0.5, accuracy: 1e-9)
        owner.flush(100)
        XCTAssertEqual(controller.status, .completed)
        XCTAssertTrue(completed)
        XCTAssertFalse(owner.hasActiveTickers)

        var seen: [Double] = []
        let implicit = ImplicitValue(0.0, lerp: lerpNumber, equals: { $0 == $1 }, onChange: {})
        implicit.set(10, duration: 100, curve: Curves.linear, owner: owner)
        owner.flush(200)
        owner.flush(225)
        seen.append(implicit.current)
        owner.flush(300)
        seen.append(implicit.current)
        XCTAssertEqual(seen, [2.5, 10])
    }

    func testTextStyleSpec() {
        let style = CSSParser.parse(["fontSize": "20px", "lineHeight": "30px", "fontFamily": "'Fira Code', monospace", "textDecoration": "underline"])
        let spec = toSpec(textStyleFromCss(style)!, 2)
        XCTAssertEqual(spec.fontSize, 40)
        XCTAssertEqual(spec.height, 1.5)
        XCTAssertEqual(spec.fontFamily, "monospace")
        XCTAssertEqual(spec.decoration, Decoration.underline)
        XCTAssertEqual(spec.letterSpacing, 0.25)
        XCTAssertEqual(resolveFontFamily("Helvetica, Arial"), nil)
        XCTAssertEqual(resolveFontFamily("\"Lobster\", cursive"), "Lobster")
        XCTAssertEqual(applyTextTransform("hello big-world (x)", "capitalize"), "Hello Big-World (X)")
    }

    func testEventDispatchPhases() {
        let dispatcher = EventDispatcher()
        var log: [String] = []
        let parent = ElpianNode(type: "div", props: [:], events: ["click": { (e: ElpianEvent) in log.append("p:\(e.phase.rawValue)") } as ElpianEventListener])
        let child = ElpianNode(type: "button", props: [:], events: ["click": "onClick"])
        dispatcher.registerNode("p", parent, nil)
        dispatcher.registerNode("c", child, "p")
        dispatcher.addNodeHandler("c", "click", { e in log.append("c:\(e.phase.rawValue)") })
        dispatcher.onGlobalEvent { e in log.append("global:\(e.currentTarget ?? "")") }
        dispatcher.dispatchClick("c", Point(x: 1, y: 2))
        XCTAssertEqual(log, ["p:capturing", "c:atTarget", "p:bubbling", "global:c"])
        XCTAssertEqual(dispatcher.handlersAlongPath(makeEvent("click", "click", "c"), "c").map { $0.nodeId }, ["c", "p"])

        let e = makeEvent("click", "click", "c") { $0.position = Point(x: 3, y: 4) }
        let json = e.toJson()
        XCTAssertEqual(JSON.stringify(json["localPosition"]), #"{"x":3,"y":4}"#)
        XCTAssertEqual(json["phase"] as? String, "none")
        XCTAssertEqual(isoTimestamp(1_700_000_000_123), "2023-11-14T22:13:20.123Z")
    }
}
