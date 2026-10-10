package dev.elpian.core.a2ui

/**
 * Catalogs as the renderer sees them (a2ui/catalog.ts): for each component
 * its properties (with the kind of value each accepts), required properties
 * and enums; for each function its arguments and return type. The basic
 * catalog below is a compact transcription of
 * `a2ui/spec/catalogs/basic/catalog.json` (a test checks the two agree), the
 * same table the web, Dart and Swift renderers carry.
 *
 * Property kinds: DynamicString, DynamicNumber, DynamicBoolean,
 * DynamicStringList, DynamicValue, ComponentId, ChildList, Action, Checks,
 * Accessibility, IconName, TabList, OptionList, string, number, boolean
 * (function arguments also: any, DynamicBooleanList).
 */

/** The `catalogId` inside the vendored basic catalog file. */
const val BASIC_CATALOG_ID = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

/**
 * Other spellings of the basic catalog id accepted on `createSurface` — the
 * protocol document's examples use the v0_9_1 path.
 */
val BASIC_CATALOG_ALIASES: List<String> = listOf("https://a2ui.org/specification/v0_9_1/catalogs/basic/catalog.json")

class PropSpec(val kind: String, val enum: List<String>? = null, val default: Any? = null)

class ComponentSpec(val props: Map<String, PropSpec>, val required: List<String>)

class FunctionSpec(
    val args: Map<String, String>,
    val required: List<String>,
    /** At least one of these groups must be fully present (`length`/`numeric`: min or max). */
    val anyOf: List<List<String>>? = null,
    /** string, number, boolean, array, object, any, void */
    val returnType: String,
)

class A2UICatalog(
    val id: String,
    val aliases: List<String> = emptyList(),
    val components: Map<String, ComponentSpec>,
    val functions: Map<String, FunctionSpec>,
    val implementations: Map<String, A2UIFunction>,
)

/** Properties every component accepts. */
val COMMON_PROPS: Map<String, PropSpec> = linkedMapOf(
    "id" to PropSpec("ComponentId"),
    "component" to PropSpec("string"),
    "accessibility" to PropSpec("Accessibility"),
    "weight" to PropSpec("number"),
)

private val CHECKABLE: Pair<String, PropSpec> = "checks" to PropSpec("Checks")

val ICON_NAMES: List<String> = listOf(
    "accountCircle", "add", "arrowBack", "arrowForward", "attachFile", "calendarToday", "call", "camera", "check", "close",
    "delete", "download", "edit", "event", "error", "fastForward", "favorite", "favoriteOff", "folder", "help", "home", "info",
    "locationOn", "lock", "lockOpen", "mail", "menu", "moreVert", "moreHoriz", "notificationsOff", "notifications", "pause",
    "payment", "person", "phone", "photo", "play", "print", "refresh", "rewind", "search", "send", "settings", "share",
    "shoppingCart", "skipNext", "skipPrevious", "star", "starHalf", "starOff", "stop", "upload", "visibility", "visibilityOff",
    "volumeDown", "volumeMute", "volumeOff", "volumeUp", "warning",
)

private val JUSTIFY_VALUES = listOf("start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly", "stretch")
private val ALIGN_VALUES = listOf("start", "center", "end", "stretch")

val BASIC_COMPONENTS: Map<String, ComponentSpec> = linkedMapOf(
    "Text" to ComponentSpec(
        linkedMapOf("text" to PropSpec("DynamicString"), "variant" to PropSpec("string", listOf("h1", "h2", "h3", "h4", "h5", "caption", "body"), "body")),
        listOf("text"),
    ),
    "Image" to ComponentSpec(
        linkedMapOf(
            "url" to PropSpec("DynamicString"),
            "description" to PropSpec("DynamicString"),
            "fit" to PropSpec("string", listOf("contain", "cover", "fill", "none", "scaleDown"), "fill"),
            "variant" to PropSpec("string", listOf("icon", "avatar", "smallFeature", "mediumFeature", "largeFeature", "header"), "mediumFeature"),
        ),
        listOf("url"),
    ),
    "Icon" to ComponentSpec(linkedMapOf("name" to PropSpec("IconName")), listOf("name")),
    "Video" to ComponentSpec(linkedMapOf("url" to PropSpec("DynamicString")), listOf("url")),
    "AudioPlayer" to ComponentSpec(linkedMapOf("url" to PropSpec("DynamicString"), "description" to PropSpec("DynamicString")), listOf("url")),
    "Row" to ComponentSpec(
        linkedMapOf("children" to PropSpec("ChildList"), "justify" to PropSpec("string", JUSTIFY_VALUES, "start"), "align" to PropSpec("string", ALIGN_VALUES, "stretch")),
        listOf("children"),
    ),
    "Column" to ComponentSpec(
        linkedMapOf("children" to PropSpec("ChildList"), "justify" to PropSpec("string", JUSTIFY_VALUES, "start"), "align" to PropSpec("string", ALIGN_VALUES, "stretch")),
        listOf("children"),
    ),
    "List" to ComponentSpec(
        linkedMapOf("children" to PropSpec("ChildList"), "direction" to PropSpec("string", listOf("vertical", "horizontal"), "vertical"), "align" to PropSpec("string", ALIGN_VALUES, "stretch")),
        listOf("children"),
    ),
    "Card" to ComponentSpec(linkedMapOf("child" to PropSpec("ComponentId")), listOf("child")),
    "Tabs" to ComponentSpec(linkedMapOf("tabs" to PropSpec("TabList")), listOf("tabs")),
    "Modal" to ComponentSpec(linkedMapOf("trigger" to PropSpec("ComponentId"), "content" to PropSpec("ComponentId")), listOf("trigger", "content")),
    "Divider" to ComponentSpec(linkedMapOf("axis" to PropSpec("string", listOf("horizontal", "vertical"), "horizontal")), emptyList()),
    "Button" to ComponentSpec(
        linkedMapOf(CHECKABLE, "child" to PropSpec("ComponentId"), "variant" to PropSpec("string", listOf("default", "primary", "borderless"), "default"), "action" to PropSpec("Action")),
        listOf("child", "action"),
    ),
    "TextField" to ComponentSpec(
        linkedMapOf(
            CHECKABLE,
            "label" to PropSpec("DynamicString"),
            "value" to PropSpec("DynamicString"),
            "variant" to PropSpec("string", listOf("longText", "number", "shortText", "obscured"), "shortText"),
            "validationRegexp" to PropSpec("string"),
        ),
        listOf("label"),
    ),
    "CheckBox" to ComponentSpec(linkedMapOf(CHECKABLE, "label" to PropSpec("DynamicString"), "value" to PropSpec("DynamicBoolean")), listOf("label", "value")),
    "ChoicePicker" to ComponentSpec(
        linkedMapOf(
            CHECKABLE,
            "label" to PropSpec("DynamicString"),
            "variant" to PropSpec("string", listOf("multipleSelection", "mutuallyExclusive"), "mutuallyExclusive"),
            "options" to PropSpec("OptionList"),
            "value" to PropSpec("DynamicStringList"),
            "displayStyle" to PropSpec("string", listOf("checkbox", "chips"), "checkbox"),
            "filterable" to PropSpec("boolean", default = false),
        ),
        listOf("options", "value"),
    ),
    "Slider" to ComponentSpec(
        linkedMapOf(CHECKABLE, "label" to PropSpec("DynamicString"), "min" to PropSpec("number", default = 0.0), "max" to PropSpec("number"), "value" to PropSpec("DynamicNumber")),
        listOf("value", "max"),
    ),
    "DateTimeInput" to ComponentSpec(
        linkedMapOf(
            CHECKABLE,
            "value" to PropSpec("DynamicString"),
            "enableDate" to PropSpec("boolean", default = false),
            "enableTime" to PropSpec("boolean", default = false),
            "min" to PropSpec("DynamicString"),
            "max" to PropSpec("DynamicString"),
            "label" to PropSpec("DynamicString"),
        ),
        listOf("value"),
    ),
)

val BASIC_FUNCTION_SPECS: Map<String, FunctionSpec> = linkedMapOf(
    "required" to FunctionSpec(linkedMapOf("value" to "any"), listOf("value"), returnType = "boolean"),
    "regex" to FunctionSpec(linkedMapOf("value" to "DynamicString", "pattern" to "string"), listOf("value", "pattern"), returnType = "boolean"),
    "length" to FunctionSpec(linkedMapOf("value" to "DynamicString", "min" to "number", "max" to "number"), listOf("value"), listOf(listOf("min"), listOf("max")), "boolean"),
    "numeric" to FunctionSpec(linkedMapOf("value" to "DynamicNumber", "min" to "number", "max" to "number"), listOf("value"), listOf(listOf("min"), listOf("max")), "boolean"),
    "email" to FunctionSpec(linkedMapOf("value" to "DynamicString"), listOf("value"), returnType = "boolean"),
    "formatString" to FunctionSpec(linkedMapOf("value" to "DynamicString"), listOf("value"), returnType = "string"),
    "formatNumber" to FunctionSpec(linkedMapOf("value" to "DynamicNumber", "decimals" to "DynamicNumber", "grouping" to "DynamicBoolean"), listOf("value"), returnType = "string"),
    "formatCurrency" to FunctionSpec(
        linkedMapOf("value" to "DynamicNumber", "currency" to "DynamicString", "decimals" to "DynamicNumber", "grouping" to "DynamicBoolean"),
        listOf("currency", "value"),
        returnType = "string",
    ),
    "formatDate" to FunctionSpec(linkedMapOf("value" to "DynamicValue", "format" to "DynamicString"), listOf("format", "value"), returnType = "string"),
    "pluralize" to FunctionSpec(
        linkedMapOf(
            "value" to "DynamicNumber",
            "zero" to "DynamicString",
            "one" to "DynamicString",
            "two" to "DynamicString",
            "few" to "DynamicString",
            "many" to "DynamicString",
            "other" to "DynamicString",
        ),
        listOf("value", "other"),
        returnType = "string",
    ),
    "openUrl" to FunctionSpec(linkedMapOf("url" to "string"), listOf("url"), returnType = "void"),
    "and" to FunctionSpec(linkedMapOf("values" to "DynamicBooleanList"), listOf("values"), returnType = "boolean"),
    "or" to FunctionSpec(linkedMapOf("values" to "DynamicBooleanList"), listOf("values"), returnType = "boolean"),
    "not" to FunctionSpec(linkedMapOf("value" to "DynamicBoolean"), listOf("value"), returnType = "boolean"),
)

val BASIC_CATALOG: A2UICatalog = A2UICatalog(
    id = BASIC_CATALOG_ID,
    aliases = BASIC_CATALOG_ALIASES,
    components = BASIC_COMPONENTS,
    functions = BASIC_FUNCTION_SPECS,
    implementations = BASIC_FUNCTIONS,
)

/** One component reference: the property path, the referenced id, and whether it is a template. */
data class ChildReference(val prop: String, val id: String, val template: Boolean)

/** Component properties that reference other components (validators walk these). */
fun childReferences(component: Map<String, Any?>, catalog: A2UICatalog): List<ChildReference> {
    val spec = catalog.components[component["component"]?.toString()] ?: return emptyList()
    val out = ArrayList<ChildReference>()
    for ((prop, ps) in spec.props) {
        val v = component[prop] ?: continue
        if (ps.kind == "ComponentId" && v is String) out.add(ChildReference(prop, v, false))
        else if (ps.kind == "ChildList") {
            if (v is List<*>) v.forEachIndexed { i, id -> if (id is String) out.add(ChildReference("$prop/$i", id, false)) }
            else if (v is Map<*, *> && v["componentId"] is String) out.add(ChildReference("$prop/componentId", v["componentId"] as String, true))
        } else if (ps.kind == "TabList" && v is List<*>) {
            v.forEachIndexed { i, t -> if (t is Map<*, *> && t["child"] is String) out.add(ChildReference("$prop/$i/child", t["child"] as String, false)) }
        }
    }
    return out
}
