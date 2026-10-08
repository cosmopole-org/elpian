import XCTest
@testable import ElpianCore

/** Cascade results compared with the TypeScript core (`StylesheetManager.getComputedStyleMap`). */
final class StylesheetTests: XCTestCase {
    private let css = """
    :root { --main: #f00; }
    div { color: blue; padding: 4px; }
    .card { color: green !important; margin: 2px; }
    #hero { color: yellow; }
    .list > .item { width: 10px; }
    .list .deep { height: 5px; }
    @media (min-width: 600px) { .card { padding: 8px; } }
    @keyframes spin { from { opacity: 0 } to { opacity: 1 } 50% { opacity: 0.5 } }
    p { color: var(--main); border-color: var(--missing, #0f0); }
    """

    private func manager() -> StylesheetManager {
        let m = StylesheetManager()
        m.load(css)
        return m
    }

    func testImportantMediaAndInline() {
        let m = manager()
        let map = m.getComputedStyleMap(
            ElementFacts(tagName: "div", id: "hero", classes: ["card"]),
            inlineStyles: ["color": "black"], screenWidth: 800, screenHeight: 600
        )
        // TypeScript: {"color":"black","padding":8,"margin":2}
        XCTAssertEqual(JSON.stringify(map), #"{"color":"black","padding":8,"margin":2}"#)
        let narrow = m.getComputedStyleMap(ElementFacts(tagName: "div", classes: ["card"]), screenWidth: 400, screenHeight: 600)
        XCTAssertEqual(JSON.stringify(narrow), #"{"color":"green","padding":4,"margin":2}"#)
    }

    func testCombinators() {
        let m = manager()
        XCTAssertEqual(JSON.stringify(m.getComputedStyleMap(ElementFacts(tagName: "span", classes: ["item"]), ancestors: [ElementFacts(tagName: "ul", classes: ["list"])])), #"{"width":10}"#)
        XCTAssertEqual(
            JSON.stringify(m.getComputedStyleMap(ElementFacts(tagName: "span", classes: ["deep"]), ancestors: [ElementFacts(tagName: "li"), ElementFacts(tagName: "ul", classes: ["list"])])),
            #"{"height":5}"#
        )
        // `>` needs the direct parent.
        XCTAssertEqual(JSON.stringify(m.getComputedStyleMap(ElementFacts(tagName: "span", classes: ["item"]), ancestors: [ElementFacts(tagName: "li"), ElementFacts(tagName: "ul", classes: ["list"])])), "{}")
    }

    func testVariablesAndKeyframes() {
        let m = manager()
        XCTAssertEqual(JSON.stringify(m.getComputedStyleMap(ElementFacts(tagName: "p"))), ##"{"color":"#f00","border-color":"#0f0"}"##)
        let frames = m.keyframes("spin")
        XCTAssertEqual(frames?.map { $0.offset }, [0, 0.5, 1])
        XCTAssertEqual(frames.map { JSON.stringify($0.map { $0.toJSON() }) }, #"[{"offset":0,"styles":{"opacity":0}},{"offset":0.5,"styles":{"opacity":0.5}},{"offset":1,"styles":{"opacity":1}}]"#)
    }

    func testSpecificityOrdering() {
        let sheet = CSSStylesheet()
        sheet.addRule("#a", ["color": "id"])
        sheet.addRule("button.primary", ["color": "tag+class"])
        sheet.addRule(".primary", ["color": "class"])
        sheet.addRule("button", ["color": "tag"])
        sheet.addRule("*", ["color": "universal"])
        let el = ElementFacts(tagName: "button", id: "a", classes: ["primary"])
        let order = sheet.matching(el, []).map { $0.selector }
        XCTAssertEqual(order, ["*", "button", ".primary", "button.primary", "#a"])
        XCTAssertEqual(sheet.getComputedStyleMap(el)["color"] as? String, "id")
        XCTAssertEqual(sheet.allRules.map { $0.specificity }, [10000, 101, 100, 1, 0])
        // Same specificity: source order wins; re-declaring a selector replaces it (and moves it last).
        sheet.addRule(".primary", ["color": "class2"])
        XCTAssertEqual(sheet.matching(ElementFacts(tagName: "a", classes: ["primary"]), []).map { $0.selector }, ["*", ".primary"])
        XCTAssertEqual(sheet.getStyle(".primary")?["color"] as? String, "class2")
        // Selector lists use their best matching selector.
        sheet.addRule("h1, .x#a", ["k": 1])
        XCTAssertEqual(sheet.matching(ElementFacts(tagName: "h1"), []).last?.selector, "h1, .x#a")
        // Attribute selectors and pseudo-classes.
        sheet.addRule("input[type=\"text\"]", ["k": 2])
        sheet.addRule("a:hover", ["k": 3])
        let input = ElementFacts(tagName: "input", attributes: ["type": "text"])
        XCTAssertTrue(sheet.matching(input, []).contains { $0.selector == "input[type=\"text\"]" })
        XCTAssertFalse(sheet.matching(ElementFacts(tagName: "a"), []).contains { $0.selector == "a:hover" })
    }

    func testJsonStylesheetAndCssToJson() {
        let m = StylesheetManager()
        // swiftlint:disable:next force_try
        let json = try! JSON.parse(#"{"rules":[{"selector":".a","styles":{"color":"red"}},{"selector":".a","styles":{"width":5},"media":"(max-width: 500px)"}],"variables":{"gap":"4px"},"keyframes":[{"name":"f","frames":[{"offset":0,"styles":{"x":1}}]}]}"#)
        m.load(json)
        XCTAssertEqual(JSON.stringify(m.getComputedStyleMap(ElementFacts(tagName: "i", classes: ["a"]), screenWidth: 400, screenHeight: 400)), #"{"color":"red","width":5}"#)
        XCTAssertEqual(JSON.stringify(m.getComputedStyleMap(ElementFacts(tagName: "i", classes: ["a"]), screenWidth: 900, screenHeight: 400)), #"{"color":"red"}"#)
        XCTAssertEqual(m.global.variables()["--gap"] as? String, "4px")
        XCTAssertEqual(m.keyframes("f")?.count, 1)
        XCTAssertEqual(
            JSON.stringify(cssToJson(#"a { color: red; width: 10px } @media print { b { x: "y" } }"#)),
            #"{"rules":[{"selector":"a","styles":{"color":"red","width":10}},{"selector":"b","styles":{"x":"y"},"media":"print"}]}"#
        )
    }

    func testMediaMatches() {
        XCTAssertTrue(mediaMatches("(min-width: 600px) and (max-width: 900px)", 700, 500))
        XCTAssertFalse(mediaMatches("(min-width: 600px)", 500, 500))
        XCTAssertTrue(mediaMatches("not (min-width: 600px)", 500, 500))
        XCTAssertTrue(mediaMatches("(max-width: 300px), (orientation: landscape)", 800, 500))
        XCTAssertFalse(mediaMatches("print", 800, 500))
        XCTAssertTrue(mediaMatches("(prefers-color-scheme: dark)", 800, 500, true))
        XCTAssertTrue(mediaMatches("(min-width: 40em)", 640, 500))
        XCTAssertTrue(mediaMatches("", 1, 1))
    }
}
