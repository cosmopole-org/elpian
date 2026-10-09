import XCTest
@testable import ElpianCore

/**
 * Parser results compared with the TypeScript engine (native/web): each `expected` string is
 * `JSON.stringify(CSSParser.parse(input))` printed by native/web/src (the
 * default environment: 1280×800 viewport, 16px root font).
 */
final class CSSTests: XCTestCase {
    private func obj(_ json: String) -> JSONObject {
        // swiftlint:disable:next force_try
        try! JSON.parse(json) as! JSONObject
    }

    private func assertParses(_ input: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let style = CSSParser.parse(obj(input))
        let actual = style.toJSON()
        let want = try? JSON.parse(expected)
        XCTAssertTrue(deepEqual(actual, want), "\n  got:  \(JSON.stringify(actual))\n  want: \(expected)", file: file, line: line)
    }

    func testDeclarationsMatchTypeScript() {
        assertParses(
            #"{"width":"50%","height":"100px","padding":"10px 20px","margin":"0 auto"}"#,
            #"{"width":640,"height":100,"widthFactor":0.5,"padding":{"top":10,"right":20,"bottom":10,"left":20},"margin":{"top":0,"right":0,"bottom":0,"left":0},"marginAuto":{"top":false,"right":true,"bottom":false,"left":true}}"#
        )
        assertParses(
            #"{"border":"1px solid #ccc","borderRadius":"4px 8px","boxShadow":"0 2px 4px rgba(0,0,0,0.2)"}"#,
            #"{"border":{"top":{"width":1,"style":"solid","color":4291611852},"right":{"width":1,"style":"solid","color":4291611852},"bottom":{"width":1,"style":"solid","color":4291611852},"left":{"width":1,"style":"solid","color":4291611852}},"borderRadius":{"topLeft":4,"topRight":8,"bottomRight":4,"bottomLeft":8},"boxShadow":[{"dx":0,"dy":2,"blur":4,"spread":0,"color":855638016,"inset":false}]}"#
        )
        assertParses(
            #"{"transform":"translate(10px, 20px) rotate(90deg)","fontSize":"1.5rem","font":"italic bold 12px/1.5 Arial, sans-serif"}"#,
            #"{"fontSize":24,"fontWeight":700,"fontStyle":"italic","fontFamily":"Arial, sans-serif","lineHeight":1.5,"transform":[6.123233995736766e-17,1,0,0,-1,6.123233995736766e-17,0,0,0,0,1,0,10,20,0,1]}"#
        )
        assertParses(
            #"{"width":"calc(100% - 20px)","background":"linear-gradient(to right, red 10%, blue)","flex":"1 1 0%"}"#,
            #"{"width":1260,"flexShrink":1,"flexBasis":"0%","flex":1,"gradient":{"kind":"linear","colors":[4294198070,4280391411],"stops":[0.1,1],"begin":{"x":-1,"y":0},"end":{"x":1,"y":0},"repeat":false}}"#
        )
        assertParses(
            #"{"transition":"opacity 300ms ease-in-out 100ms","animation":"spin 2s linear infinite","filter":"blur(4px) brightness(50%)"}"#,
            #"{"filter":{"blur":4,"brightness":0.5},"transitionDuration":300,"transitionCurve":"easeinout","transitionProperty":"opacity","transitionDelay":100,"animationName":"spin","animationDuration":2000,"animationTimingFunction":"linear","animationIterationCount":-1}"#
        )
        assertParses(
            #"{"textDecoration":"underline dotted red","lineHeight":"24px","gap":"10px 20px","background-color":"hsl(120, 100%, 50%)"}"#,
            #"{"rowGap":10,"columnGap":20,"gap":20,"gridColumnGap":20,"gridRowGap":10,"backgroundColor":4278255360,"lineHeightPx":24,"textDecoration":{"underline":true,"overline":false,"lineThrough":false},"textDecorationColor":4294198070,"textDecorationStyle":"dotted"}"#
        )
        assertParses(
            #"{"borderTop":"2px dashed blue","borderWidth":"1px 2px","paddingLeft":"5%","marginX":"auto","border-radius":"50%"}"#,
            #"{"padding":{"top":0,"right":0,"bottom":0,"left":0},"paddingPercent":{"left":{"pct":5}},"margin":{"top":0,"right":0,"bottom":0,"left":0},"marginAuto":{"top":false,"right":true,"bottom":false,"left":true},"borderWidth":12,"border":{"top":{"width":1,"color":4280391411,"style":"dashed"},"right":{"width":0,"color":4278190080,"style":"none"},"bottom":{"width":0,"color":4278190080,"style":"none"},"left":{"width":0,"color":4278190080,"style":"none"}},"borderRadiusPercent":{"topLeft":50,"topRight":50,"bottomRight":50,"bottomLeft":50}}"#
        )
        assertParses(
            #"{"backgroundImage":"url('a.png')","objectFit":"cover","opacity":"0.5","zIndex":3,"maxWidth":"min(100px, 50vw)","minHeight":"10em","fontSize":20}"#,
            #"{"maxWidth":100,"minHeight":160,"zIndex":3,"backgroundImage":"a.png","fontSize":20,"opacity":0.5,"objectFit":"cover"}"#
        )
        assertParses(
            #"{"textShadow":"1px 1px 2px black","transformOrigin":"top left","translate":"5px 6px","scale":"1.5 2","fontWeight":"w600","aspectRatio":"16 / 9"}"#,
            #"{"aspectRatio":1.7777777777777777,"fontWeight":600,"textShadow":[{"color":4278190080,"dx":1,"dy":1,"blur":2}],"scaleX":1.5,"scaleY":2,"translate":{"dx":5,"dy":6},"transformOrigin":{"x":-1,"y":-1}}"#
        )
        assertParses(
            #"{"background":"radial-gradient(circle at top left, #fff 0%, rgba(0,0,0,.5) 100%), #123456","display":" flex ","flexFlow":"column wrap"}"#,
            #"{"display":"flex","flexDirection":"column","flexWrap":"wrap","backgroundColor":4279383126,"gradient":{"kind":"radial","colors":[4294967295,2130706432],"stops":[0,1],"center":{"x":-1,"y":-1},"radius":0.5,"repeat":false}}"#
        )
    }

    func testCacheReturnsSharedInstance() {
        let a = CSSParser.parse(["width": "10px"])
        let b = CSSParser.parse(["width": "10px"])
        XCTAssertTrue(a === b)
        XCTAssertEqual(a.width, 10)
        let copy = a.copy()
        copy.width = 3
        XCTAssertEqual(a.width, 10)
    }

    func testColors() {
        let inputs: [Any?] = ["#fff", "#80ff0000", "rgba(255,0,0,0.5)", "red", "hsl(120, 100%, 50%)", "teal", "0xff00ff", "rgb(10 20 30 / 50%)"]
        let expected: [Color] = [4294967295, 2164195328, 2147418112, 4294198070, 4278255360, 4278228616, 4294902015, 2131366942]
        XCTAssertEqual(inputs.map { parseColor($0) }, expected)
        XCTAssertNil(parseColor("notacolor"))
        XCTAssertNil(parseColor("currentColor"))
        XCTAssertEqual(parseColor(0xFF112233), 0xFF112233)
        XCTAssertEqual(toCssColor(0x80FF0000), "rgba(255,0,0,0.502)")
        XCTAssertEqual(toCssColor(0xFF123456), "#123456")
        XCTAssertEqual(lerpColor(0xFF000000, 0xFFFFFFFF, 0.5), 0xFF808080)
        XCTAssertEqual(withOpacity(0xFF102030, 0.5), 0x80102030)
    }

    func testValueParsers() {
        XCTAssertEqual(CSSParser.parseDouble("2em", 10), 20)
        XCTAssertEqual(CSSParser.parseDouble("12pt"), 12)
        XCTAssertEqual(CSSParser.parseDimension("12pt", true), 16)
        XCTAssertEqual(CSSParser.parseDimension("10vh", false), 80)
        XCTAssertEqual(CSSParser.parseDimension("calc((100% - 40px) / 2)", true), 620)
        XCTAssertEqual(CSSParser.parseDimension("clamp(10px, 50%, 300px)", true), 300)
        XCTAssertNil(CSSParser.parseDimension("auto", true))
        XCTAssertEqual(CSSParser.parseDuration("1.5s"), 1500)
        XCTAssertEqual(CSSParser.parseDuration(250.9), 250)
        XCTAssertEqual(CSSParser.parseAlignment("bottom-right"), .bottomRight)
        XCTAssertEqual(CSSParser.parseAlignment("25% 75%"), Alignment(x: -0.5, y: 0.5))
        XCTAssertEqual(CSSParser.parseEdgeInsets([1, 2, 3] as [Any?]), EdgeInsets(top: 1, right: 2, bottom: 3, left: 2))
        XCTAssertEqual(CSSParser.normalizeCurve("Ease-In_Out"), "easeinout")
        XCTAssertEqual(CSSParser.splitTopLevel("a, rgb(1, 2, 3), 'x,y'", ","), ["a", " rgb(1, 2, 3)", " 'x,y'"])
        XCTAssertEqual(CSSParser.stripImportant("red !important") as? String, "red")
        XCTAssertTrue(CSSParser.isImportant("red ! important"))
        let (begin, end) = CSSParser.beginEndForAngle(45)
        XCTAssertEqual(begin.x, -1, accuracy: 1e-12)
        XCTAssertEqual(begin.y, 1)
        XCTAssertEqual(end.x, 1, accuracy: 1e-12)
        XCTAssertEqual(end.y, -1)
    }

    func testEnvironmentAffectsViewportUnits() {
        defer { CssEnvironment.update(viewportWidth: 1280, viewportHeight: 800) }
        XCTAssertEqual(CSSParser.parse(["width": "50vw"]).width, 640)
        XCTAssertTrue(CssEnvironment.update(viewportWidth: 400))
        XCTAssertFalse(CssEnvironment.update(viewportWidth: 400))
        XCTAssertEqual(CSSParser.parse(["width": "50vw"]).width, 200)
    }

    func testCurves() {
        XCTAssertEqual(Curves.linear(0.3), 0.3)
        XCTAssertEqual(curveByName("ease-in-out")(0), 0)
        XCTAssertEqual(curveByName("ease-in-out")(1), 1)
        XCTAssertEqual(curveByName("easeInOut")(0.5), 0.5, accuracy: 0.01)
        XCTAssertEqual(curveByName("steps(4, end)")(0.3), 0.25)
        XCTAssertEqual(curveByName("steps(4, start)")(0.3), 0.5)
        XCTAssertEqual(curveByName("cubic-bezier(0, 0, 1, 1)")(0.4), 0.4, accuracy: 0.01)
        XCTAssertEqual(Curves.bounceOut(1), 1, accuracy: 1e-9)
        XCTAssertEqual(curveByName("nope", Curves.decelerate)(0.5), 0.75)
    }
}
