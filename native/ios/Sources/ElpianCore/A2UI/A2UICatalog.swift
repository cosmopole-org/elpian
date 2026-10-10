import Foundation

/**
 * Catalogs as the renderer sees them (a2ui/catalog.ts): for each component
 * its properties (with the kind of value each accepts), required properties
 * and enums; for each function its arguments and return type. The basic
 * catalog below is a compact transcription of
 * `a2ui/spec/catalogs/basic/catalog.json` (a test checks the two agree), the
 * same table the TypeScript, Dart and Kotlin renderers carry.
 */

/** The `catalogId` inside the vendored basic catalog file. */
public let BASIC_CATALOG_ID = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

/**
 * Other spellings of the basic catalog id accepted on `createSurface` — the
 * protocol document's examples use the v0_9_1 path.
 */
public let BASIC_CATALOG_ALIASES: [String] = ["https://a2ui.org/specification/v0_9_1/catalogs/basic/catalog.json"]

public enum PropKind: String {
    case DynamicString, DynamicNumber, DynamicBoolean, DynamicStringList, DynamicValue
    case ComponentId, ChildList, Action, Checks, Accessibility, IconName, TabList, OptionList
    case string, number, boolean
    /** Function arguments only. */
    case any, DynamicBooleanList
}

public struct PropSpec {
    public let kind: PropKind
    public let enumValues: [String]?
    public let defaultValue: Any?

    public init(_ kind: PropKind, enum enumValues: [String]? = nil, default defaultValue: Any? = nil) {
        self.kind = kind
        self.enumValues = enumValues
        self.defaultValue = defaultValue
    }
}

public struct ComponentSpec {
    /** Property names in declaration order. */
    public let propNames: [String]
    public let props: [String: PropSpec]
    public let required: [String]

    public init(_ props: [(String, PropSpec)], required: [String]) {
        propNames = props.map { $0.0 }
        var m: [String: PropSpec] = [:]
        for (k, v) in props { m[k] = v }
        self.props = m
        self.required = required
    }
}

public enum ReturnType: String {
    case string, number, boolean, array, object, any, void
}

public struct FunctionSpec {
    public let argNames: [String]
    public let args: [String: PropKind]
    public let required: [String]
    /** At least one of these groups must be fully present (`length`/`numeric`: min or max). */
    public let anyOf: [[String]]?
    public let returnType: ReturnType

    public init(_ args: [(String, PropKind)], required: [String], anyOf: [[String]]? = nil, returnType: ReturnType) {
        argNames = args.map { $0.0 }
        var m: [String: PropKind] = [:]
        for (k, v) in args { m[k] = v }
        self.args = m
        self.required = required
        self.anyOf = anyOf
        self.returnType = returnType
    }
}

public final class A2UICatalog {
    public let id: String
    public let aliases: [String]
    public let componentNames: [String]
    public let components: [String: ComponentSpec]
    public let functionNames: [String]
    public let functions: [String: FunctionSpec]
    public let implementations: [String: A2UIFunction]

    public init(id: String, aliases: [String] = [], components: [(String, ComponentSpec)], functions: [(String, FunctionSpec)],
                implementations: [String: A2UIFunction]) {
        self.id = id
        self.aliases = aliases
        componentNames = components.map { $0.0 }
        var c: [String: ComponentSpec] = [:]
        for (k, v) in components { c[k] = v }
        self.components = c
        functionNames = functions.map { $0.0 }
        var f: [String: FunctionSpec] = [:]
        for (k, v) in functions { f[k] = v }
        self.functions = f
        self.implementations = implementations
    }
}

/** Properties every component accepts. */
public let COMMON_PROPS: [String: PropSpec] = [
    "id": PropSpec(.ComponentId),
    "component": PropSpec(.string),
    "accessibility": PropSpec(.Accessibility),
    "weight": PropSpec(.number),
]

private let CHECKABLE: [(String, PropSpec)] = [("checks", PropSpec(.Checks))]

public let ICON_NAMES: [String] = [
    "accountCircle", "add", "arrowBack", "arrowForward", "attachFile", "calendarToday", "call", "camera", "check", "close",
    "delete", "download", "edit", "event", "error", "fastForward", "favorite", "favoriteOff", "folder", "help", "home", "info",
    "locationOn", "lock", "lockOpen", "mail", "menu", "moreVert", "moreHoriz", "notificationsOff", "notifications", "pause",
    "payment", "person", "phone", "photo", "play", "print", "refresh", "rewind", "search", "send", "settings", "share",
    "shoppingCart", "skipNext", "skipPrevious", "star", "starHalf", "starOff", "stop", "upload", "visibility", "visibilityOff",
    "volumeDown", "volumeMute", "volumeOff", "volumeUp", "warning",
]

private let JUSTIFY_VALUES = ["start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly", "stretch"]
private let ALIGN_VALUES = ["start", "center", "end", "stretch"]

public let BASIC_COMPONENT_LIST: [(String, ComponentSpec)] = [
    ("Text", ComponentSpec([
        ("text", PropSpec(.DynamicString)),
        ("variant", PropSpec(.string, enum: ["h1", "h2", "h3", "h4", "h5", "caption", "body"], default: "body")),
    ], required: ["text"])),
    ("Image", ComponentSpec([
        ("url", PropSpec(.DynamicString)),
        ("description", PropSpec(.DynamicString)),
        ("fit", PropSpec(.string, enum: ["contain", "cover", "fill", "none", "scaleDown"], default: "fill")),
        ("variant", PropSpec(.string, enum: ["icon", "avatar", "smallFeature", "mediumFeature", "largeFeature", "header"], default: "mediumFeature")),
    ], required: ["url"])),
    ("Icon", ComponentSpec([("name", PropSpec(.IconName))], required: ["name"])),
    ("Video", ComponentSpec([("url", PropSpec(.DynamicString))], required: ["url"])),
    ("AudioPlayer", ComponentSpec([("url", PropSpec(.DynamicString)), ("description", PropSpec(.DynamicString))], required: ["url"])),
    ("Row", ComponentSpec([
        ("children", PropSpec(.ChildList)),
        ("justify", PropSpec(.string, enum: JUSTIFY_VALUES, default: "start")),
        ("align", PropSpec(.string, enum: ALIGN_VALUES, default: "stretch")),
    ], required: ["children"])),
    ("Column", ComponentSpec([
        ("children", PropSpec(.ChildList)),
        ("justify", PropSpec(.string, enum: JUSTIFY_VALUES, default: "start")),
        ("align", PropSpec(.string, enum: ALIGN_VALUES, default: "stretch")),
    ], required: ["children"])),
    ("List", ComponentSpec([
        ("children", PropSpec(.ChildList)),
        ("direction", PropSpec(.string, enum: ["vertical", "horizontal"], default: "vertical")),
        ("align", PropSpec(.string, enum: ALIGN_VALUES, default: "stretch")),
    ], required: ["children"])),
    ("Card", ComponentSpec([("child", PropSpec(.ComponentId))], required: ["child"])),
    ("Tabs", ComponentSpec([("tabs", PropSpec(.TabList))], required: ["tabs"])),
    ("Modal", ComponentSpec([("trigger", PropSpec(.ComponentId)), ("content", PropSpec(.ComponentId))], required: ["trigger", "content"])),
    ("Divider", ComponentSpec([("axis", PropSpec(.string, enum: ["horizontal", "vertical"], default: "horizontal"))], required: [])),
    ("Button", ComponentSpec(CHECKABLE + [
        ("child", PropSpec(.ComponentId)),
        ("variant", PropSpec(.string, enum: ["default", "primary", "borderless"], default: "default")),
        ("action", PropSpec(.Action)),
    ], required: ["child", "action"])),
    ("TextField", ComponentSpec(CHECKABLE + [
        ("label", PropSpec(.DynamicString)),
        ("value", PropSpec(.DynamicString)),
        ("variant", PropSpec(.string, enum: ["longText", "number", "shortText", "obscured"], default: "shortText")),
        ("validationRegexp", PropSpec(.string)),
    ], required: ["label"])),
    ("CheckBox", ComponentSpec(CHECKABLE + [("label", PropSpec(.DynamicString)), ("value", PropSpec(.DynamicBoolean))], required: ["label", "value"])),
    ("ChoicePicker", ComponentSpec(CHECKABLE + [
        ("label", PropSpec(.DynamicString)),
        ("variant", PropSpec(.string, enum: ["multipleSelection", "mutuallyExclusive"], default: "mutuallyExclusive")),
        ("options", PropSpec(.OptionList)),
        ("value", PropSpec(.DynamicStringList)),
        ("displayStyle", PropSpec(.string, enum: ["checkbox", "chips"], default: "checkbox")),
        ("filterable", PropSpec(.boolean, default: false)),
    ], required: ["options", "value"])),
    ("Slider", ComponentSpec(CHECKABLE + [
        ("label", PropSpec(.DynamicString)),
        ("min", PropSpec(.number, default: 0.0)),
        ("max", PropSpec(.number)),
        ("value", PropSpec(.DynamicNumber)),
    ], required: ["value", "max"])),
    ("DateTimeInput", ComponentSpec(CHECKABLE + [
        ("value", PropSpec(.DynamicString)),
        ("enableDate", PropSpec(.boolean, default: false)),
        ("enableTime", PropSpec(.boolean, default: false)),
        ("min", PropSpec(.DynamicString)),
        ("max", PropSpec(.DynamicString)),
        ("label", PropSpec(.DynamicString)),
    ], required: ["value"])),
]

public let BASIC_FUNCTION_SPEC_LIST: [(String, FunctionSpec)] = [
    ("required", FunctionSpec([("value", .any)], required: ["value"], returnType: .boolean)),
    ("regex", FunctionSpec([("value", .DynamicString), ("pattern", .string)], required: ["value", "pattern"], returnType: .boolean)),
    ("length", FunctionSpec([("value", .DynamicString), ("min", .number), ("max", .number)], required: ["value"], anyOf: [["min"], ["max"]], returnType: .boolean)),
    ("numeric", FunctionSpec([("value", .DynamicNumber), ("min", .number), ("max", .number)], required: ["value"], anyOf: [["min"], ["max"]], returnType: .boolean)),
    ("email", FunctionSpec([("value", .DynamicString)], required: ["value"], returnType: .boolean)),
    ("formatString", FunctionSpec([("value", .DynamicString)], required: ["value"], returnType: .string)),
    ("formatNumber", FunctionSpec([("value", .DynamicNumber), ("decimals", .DynamicNumber), ("grouping", .DynamicBoolean)], required: ["value"], returnType: .string)),
    ("formatCurrency", FunctionSpec([("value", .DynamicNumber), ("currency", .DynamicString), ("decimals", .DynamicNumber), ("grouping", .DynamicBoolean)],
                                    required: ["currency", "value"], returnType: .string)),
    ("formatDate", FunctionSpec([("value", .DynamicValue), ("format", .DynamicString)], required: ["format", "value"], returnType: .string)),
    ("pluralize", FunctionSpec([
        ("value", .DynamicNumber), ("zero", .DynamicString), ("one", .DynamicString), ("two", .DynamicString),
        ("few", .DynamicString), ("many", .DynamicString), ("other", .DynamicString),
    ], required: ["value", "other"], returnType: .string)),
    ("openUrl", FunctionSpec([("url", .string)], required: ["url"], returnType: .void)),
    ("and", FunctionSpec([("values", .DynamicBooleanList)], required: ["values"], returnType: .boolean)),
    ("or", FunctionSpec([("values", .DynamicBooleanList)], required: ["values"], returnType: .boolean)),
    ("not", FunctionSpec([("value", .DynamicBoolean)], required: ["value"], returnType: .boolean)),
]

public let BASIC_CATALOG = A2UICatalog(
    id: BASIC_CATALOG_ID,
    aliases: BASIC_CATALOG_ALIASES,
    components: BASIC_COMPONENT_LIST,
    functions: BASIC_FUNCTION_SPEC_LIST,
    implementations: BASIC_FUNCTIONS
)

public var BASIC_COMPONENTS: [String: ComponentSpec] { BASIC_CATALOG.components }
public var BASIC_FUNCTION_SPECS: [String: FunctionSpec] { BASIC_CATALOG.functions }

/** One component reference a component makes (`prop` is the pointer-ish location). */
public struct ChildReference {
    public let prop: String
    public let id: String
    public let template: Bool
}

/** Component properties that reference other components (validators walk these). */
public func childReferences(_ component: JSONObject, _ catalog: A2UICatalog) -> [ChildReference] {
    var out: [ChildReference] = []
    guard let spec = catalog.components[jsString(component["component"])] else { return out }
    for prop in spec.propNames {
        let ps = spec.props[prop]!
        guard let v = flattenOptional(component[prop]) else { continue }
        if ps.kind == .ComponentId, let s = v as? String {
            out.append(ChildReference(prop: prop, id: s, template: false))
        } else if ps.kind == .ChildList {
            if let a = asArray(v) {
                for (i, id) in a.enumerated() {
                    if let s = flattenOptional(id) as? String { out.append(ChildReference(prop: "\(prop)/\(i)", id: s, template: false)) }
                }
            } else if let m = asMap(v), let cid = m["componentId"] as? String {
                out.append(ChildReference(prop: "\(prop)/componentId", id: cid, template: true))
            }
        } else if ps.kind == .TabList, let a = asArray(v) {
            for (i, t) in a.enumerated() {
                if let m = asMap(t), let child = m["child"] as? String { out.append(ChildReference(prop: "\(prop)/\(i)/child", id: child, template: false)) }
            }
        }
    }
    return out
}
