import Foundation

/**
 * The guest-visible document — a port of `dom_api.dart` (`ElpianDOM`,
 * `ElpianElement`) via host/dom.ts, backing the `dom.*` host APIs. Elements
 * can be turned into Elpian JSON (`toJson`) and rendered.
 *
 * The document owns its elements; an element refers back to its document and
 * its parent weakly (they always outlive it while it is attached).
 */
public final class ElpianElement: CustomStringConvertible {
    public let tagName: String
    public let id: String?
    public private(set) var classes: [String]
    private weak var dom: ElpianDOM?
    public weak var parent: ElpianElement?
    private var kids: [ElpianElement] = []
    private var attrs = JSONObject()
    private var styles = JSONObject()
    private var listeners: [String: (Any?) -> Void] = [:]
    public var textContent: String?

    init(_ tagName: String, _ id: String?, _ classes: [String], _ dom: ElpianDOM?) {
        self.tagName = tagName
        self.id = id
        self.classes = classes
        self.dom = dom
    }

    public var innerHTML: String? {
        get { textContent }
        set { textContent = newValue }
    }

    public func getAttribute(_ name: String) -> Any? { attrs[name] }

    public func setAttribute(_ name: String, _ value: Any?) {
        attrs[name] = value
    }

    public func removeAttribute(_ name: String) {
        _ = attrs.removeValue(forKey: name)
    }

    public func hasAttribute(_ name: String) -> Bool { attrs.has(name) }

    public var attributes: JSONObject { attrs.copy() }

    public func setStyle(_ property: String, _ value: Any?) {
        styles[property] = value
    }

    public func getStyle(_ property: String) -> Any? { styles[property] }

    public func setStyleObject(_ styles: JSONObject) {
        self.styles.assign(styles)
    }

    public var style: JSONObject { styles.copy() }

    public func addClass(_ className: String) {
        if !classes.contains(className) {
            classes.append(className)
            dom?.indexClass(className, self)
        }
    }

    public func removeClass(_ className: String) {
        if let i = classes.firstIndex(of: className) { classes.remove(at: i) }
        dom?.unindexClass(className, self)
    }

    public func hasClass(_ className: String) -> Bool { classes.contains(className) }

    public func toggleClass(_ className: String) {
        if hasClass(className) { removeClass(className) } else { addClass(className) }
    }

    public func appendChild(_ child: ElpianElement) {
        child.parent?.removeChild(child)
        child.parent = self
        kids.append(child)
    }

    public func insertBefore(_ newChild: ElpianElement, _ reference: ElpianElement?) {
        newChild.parent?.removeChild(newChild)
        newChild.parent = self
        guard let reference = reference else {
            kids.append(newChild)
            return
        }
        if let index = kids.firstIndex(where: { $0 === reference }) {
            kids.insert(newChild, at: index)
        } else {
            kids.append(newChild)
        }
    }

    public func removeChild(_ child: ElpianElement) {
        if let i = kids.firstIndex(where: { $0 === child }) {
            kids.remove(at: i)
            child.parent = nil
        }
    }

    public func replaceChild(_ newChild: ElpianElement, _ oldChild: ElpianElement) {
        if !kids.contains(where: { $0 === oldChild }) { return }
        newChild.parent?.removeChild(newChild)
        let index = kids.firstIndex(where: { $0 === oldChild })
        newChild.parent = self
        oldChild.parent = nil
        if let index = index { kids[index] = newChild }
    }

    public var children: [ElpianElement] { kids }

    public var firstChild: ElpianElement? { kids.first }

    public var lastChild: ElpianElement? { kids.last }

    public var nextSibling: ElpianElement? {
        guard let p = parent else { return nil }
        let s = p.kids
        guard let i = s.firstIndex(where: { $0 === self }), i < s.count - 1 else { return nil }
        return s[i + 1]
    }

    public var previousSibling: ElpianElement? {
        guard let p = parent else { return nil }
        let s = p.kids
        guard let i = s.firstIndex(where: { $0 === self }), i > 0 else { return nil }
        return s[i - 1]
    }

    public func addEventListener(_ event: String, _ callback: @escaping (Any?) -> Void) {
        listeners[event] = callback
    }

    public func removeEventListener(_ event: String) {
        listeners.removeValue(forKey: event)
    }

    public func dispatchEvent(_ event: String, _ data: Any? = nil) {
        listeners[event]?(data)
    }

    public func clone(deep: Bool = false) -> ElpianElement {
        let copy = dom?.createElement(tagName, classes: classes) ?? ElpianElement(tagName, nil, classes, nil)
        copy.attrs = attrs.copy()
        copy.styles = styles.copy()
        copy.textContent = textContent
        if deep { for k in kids { copy.appendChild(k.clone(deep: true)) } }
        return copy
    }

    /** The element as Elpian JSON (`toElpianNode().toJson()`). */
    public func toJson() -> JSONObject {
        let props = attrs.copy()
        if let t = textContent { props["text"] = t }
        if !classes.isEmpty { props["className"] = classes.joined(separator: " ") }
        if !styles.isEmpty { props["style"] = styles.copy() }
        let out = JSONObject([("type", tagName), ("props", props), ("children", kids.map { $0.toJson() as Any? })])
        if let id = id { out["key"] = id }
        return out
    }

    public func encode() -> JSONObject {
        JSONObject([
            ("id", id),
            ("tagName", tagName),
            ("classes", classes.map { $0 as Any? }),
            ("attributes", attrs.copy()),
            ("style", styles.copy()),
            ("textContent", textContent),
            ("children", kids.map { $0.id as Any? }),
        ])
    }

    public var description: String {
        let idPart = (id?.isEmpty == false) ? " id=\"\(id!)\"" : ""
        let classPart = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
        return "<\(tagName)\(idPart)\(classPart)>"
    }
}

public final class ElpianDOM {
    private var byId: [String: ElpianElement] = [:]
    private var all: [ElpianElement] = []
    private var byClass: [String: [ElpianElement]] = [:]
    private var byTag: [String: [ElpianElement]] = [:]

    public init() {}

    public func getElementById(_ id: String) -> ElpianElement? { byId[id] }

    public func getElementsByClassName(_ className: String) -> [ElpianElement] { byClass[className] ?? [] }

    public func getElementsByTagName(_ tagName: String) -> [ElpianElement] { byTag[tagName] ?? [] }

    public func querySelector(_ selector: String) -> ElpianElement? { querySelectorAll(selector).first }

    public func querySelectorAll(_ selector: String) -> [ElpianElement] {
        let s = jsTrim(selector)
        if s.hasPrefix("#") {
            if let e = getElementById(jsSubstring(s, 1)) { return [e] }
            return []
        }
        if s.hasPrefix(".") { return getElementsByClassName(jsSubstring(s, 1)) }
        // `tag.class` compound selectors.
        if let m = ElpianDOM.COMPOUND.exec(s), let compound = m[2], !compound.isEmpty {
            let tag = m[1]
            let wanted = compound.split(separator: ".").map(String.init).filter { !$0.isEmpty }
            return all.filter { e in
                (tag == nil || tag!.isEmpty || e.tagName == tag!) && wanted.allSatisfy { e.classes.contains($0) }
            }
        }
        return getElementsByTagName(s)
    }

    public func createElement(_ tagName: String, id: String? = nil, classes: [String]? = nil) -> ElpianElement {
        let el = ElpianElement(tagName, id, classes ?? [], self)
        if let id = el.id { byId[id] = el }
        all.append(el)
        byTag[tagName, default: []].append(el)
        for c in el.classes { indexClass(c, el) }
        return el
    }

    /** Build elements from Elpian JSON (`ElpianElement.fromElpianNode`). */
    public func fromJson(_ json: JSONObject) -> ElpianElement {
        let props = asMap(json["props"]) ?? JSONObject()
        let cn = props["className"]
        let classes: [String]
        if let s = cn as? String {
            classes = jsSplitWhitespace(s).filter { !$0.isEmpty }
        } else if let a = asArray(cn) {
            classes = a.map { jsString($0) }
        } else {
            classes = []
        }
        let key = json["key"]
        let el = createElement(jsString(json["type"] ?? "div"), id: key == nil ? nil : jsString(key), classes: classes)
        for (k, v) in props where k != "className" && k != "style" { el.setAttribute(k, v) }
        if let style = asMap(props["style"]) { el.setStyleObject(style) }
        if props["text"] != nil { el.textContent = jsString(props["text"]) }
        if let children = asArray(json["children"]) {
            for child in children { el.appendChild(fromJson(asMap(child) ?? JSONObject())) }
        }
        return el
    }

    public func indexClass(_ className: String, _ el: ElpianElement) {
        var list = byClass[className] ?? []
        if !list.contains(where: { $0 === el }) { list.append(el) }
        byClass[className] = list
    }

    public func unindexClass(_ className: String, _ el: ElpianElement) {
        guard var list = byClass[className] else { return }
        if let i = list.firstIndex(where: { $0 === el }) {
            list.remove(at: i)
            byClass[className] = list
        }
    }

    public func removeElement(_ el: ElpianElement) {
        if let id = el.id { byId.removeValue(forKey: id) }
        all = all.filter { $0 !== el }
        if let tags = byTag[el.tagName] { byTag[el.tagName] = tags.filter { $0 !== el } }
        for c in el.classes { unindexClass(c, el) }
        el.parent?.removeChild(el)
    }

    public func clear() {
        byId.removeAll()
        all = []
        byClass.removeAll()
        byTag.removeAll()
    }

    public var allElements: [ElpianElement] { all }

    private static let COMPOUND = JSRegex("^([a-zA-Z][A-Za-z0-9_-]*)?((?:\\.[A-Za-z0-9_-]+)*)$")
}
