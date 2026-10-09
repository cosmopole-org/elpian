package dev.elpian.core.host

import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.asMap
import dev.elpian.core.util.jsString

/**
 * The guest-visible document — a port of `dom_api.dart` (`ElpianDOM`,
 * `ElpianElement`) via host/dom.ts, backing the `dom.*` host APIs. Elements
 * can be turned into Elpian JSON (`toJson`) and rendered.
 */
class ElpianElement(
    val tagName: String,
    val id: String?,
    val classes: MutableList<String>,
    private val dom: ElpianDOM,
) {
    var parent: ElpianElement? = null
    private val kids = ArrayList<ElpianElement>()
    private var attrs = LinkedHashMap<String, Any?>()
    private var styles = LinkedHashMap<String, Any?>()
    private val listeners = LinkedHashMap<String, (Any?) -> Unit>()
    var textContent: String? = null

    var innerHTML: String?
        get() = textContent
        set(v) {
            textContent = v
        }

    fun getAttribute(name: String): Any? = attrs[name]

    fun setAttribute(name: String, value: Any?) {
        attrs[name] = value
    }

    fun removeAttribute(name: String) {
        attrs.remove(name)
    }

    fun hasAttribute(name: String): Boolean = attrs.containsKey(name)

    val attributes: JsonMap get() = LinkedHashMap(attrs)

    fun setStyle(property: String, value: Any?) {
        styles[property] = value
    }

    fun getStyle(property: String): Any? = styles[property]

    fun setStyleObject(styles: Map<String, Any?>) {
        this.styles.putAll(styles)
    }

    val style: JsonMap get() = LinkedHashMap(styles)

    fun addClass(className: String) {
        if (!classes.contains(className)) {
            classes.add(className)
            dom.indexClass(className, this)
        }
    }

    fun removeClass(className: String) {
        val i = classes.indexOf(className)
        if (i >= 0) classes.removeAt(i)
        dom.unindexClass(className, this)
    }

    fun hasClass(className: String): Boolean = classes.contains(className)

    fun toggleClass(className: String) {
        if (hasClass(className)) removeClass(className) else addClass(className)
    }

    fun appendChild(child: ElpianElement) {
        child.parent?.removeChild(child)
        child.parent = this
        kids.add(child)
    }

    fun insertBefore(newChild: ElpianElement, reference: ElpianElement?) {
        newChild.parent?.removeChild(newChild)
        newChild.parent = this
        if (reference == null) {
            kids.add(newChild)
            return
        }
        val index = kids.indexOf(reference)
        if (index >= 0) kids.add(index, newChild) else kids.add(newChild)
    }

    fun removeChild(child: ElpianElement) {
        val i = kids.indexOf(child)
        if (i >= 0) {
            kids.removeAt(i)
            child.parent = null
        }
    }

    fun replaceChild(newChild: ElpianElement, oldChild: ElpianElement) {
        if (!kids.contains(oldChild)) return
        newChild.parent?.removeChild(newChild)
        val index = kids.indexOf(oldChild)
        newChild.parent = this
        oldChild.parent = null
        if (index >= 0) kids[index] = newChild
    }

    val children: List<ElpianElement> get() = ArrayList(kids)

    val firstChild: ElpianElement? get() = kids.firstOrNull()

    val lastChild: ElpianElement? get() = kids.lastOrNull()

    val nextSibling: ElpianElement?
        get() {
            val p = parent ?: return null
            val s = p.kids
            val i = s.indexOf(this)
            return if (i >= 0 && i < s.size - 1) s[i + 1] else null
        }

    val previousSibling: ElpianElement?
        get() {
            val p = parent ?: return null
            val s = p.kids
            val i = s.indexOf(this)
            return if (i > 0) s[i - 1] else null
        }

    fun addEventListener(event: String, callback: (Any?) -> Unit) {
        listeners[event] = callback
    }

    fun removeEventListener(event: String) {
        listeners.remove(event)
    }

    fun dispatchEvent(event: String, data: Any? = null) {
        listeners[event]?.invoke(data)
    }

    fun clone(deep: Boolean = false): ElpianElement {
        val copy = dom.createElement(tagName, classes = ArrayList(classes))
        copy.attrs = LinkedHashMap(attrs)
        copy.styles = LinkedHashMap(styles)
        copy.textContent = textContent
        if (deep) for (k in kids) copy.appendChild(k.clone(true))
        return copy
    }

    /** The element as Elpian JSON (`toElpianNode().toJson()`). */
    fun toJson(): JsonMap {
        val props: JsonMap = LinkedHashMap(attrs)
        if (textContent != null) props["text"] = textContent
        if (classes.isNotEmpty()) props["className"] = classes.joinToString(" ")
        if (styles.isNotEmpty()) props["style"] = LinkedHashMap(styles)
        val out: JsonMap = linkedMapOf("type" to tagName, "props" to props, "children" to kids.map { it.toJson() }.toMutableList())
        if (id != null) out["key"] = id
        return out
    }

    fun encode(): JsonMap = linkedMapOf(
        "id" to id,
        "tagName" to tagName,
        "classes" to ArrayList<Any?>(classes),
        "attributes" to LinkedHashMap(attrs),
        "style" to LinkedHashMap(styles),
        "textContent" to textContent,
        "children" to kids.map { it.id }.toMutableList<Any?>(),
    )

    override fun toString(): String =
        "<$tagName${if (!id.isNullOrEmpty()) " id=\"$id\"" else ""}${if (classes.isNotEmpty()) " class=\"${classes.joinToString(" ")}\"" else ""}>"
}

class ElpianDOM {
    private val byId = LinkedHashMap<String, ElpianElement>()
    private var all = ArrayList<ElpianElement>()
    private val byClass = LinkedHashMap<String, MutableList<ElpianElement>>()
    private val byTag = LinkedHashMap<String, MutableList<ElpianElement>>()

    fun getElementById(id: String): ElpianElement? = byId[id]

    fun getElementsByClassName(className: String): List<ElpianElement> = ArrayList(byClass[className] ?: emptyList())

    fun getElementsByTagName(tagName: String): List<ElpianElement> = ArrayList(byTag[tagName] ?: emptyList())

    fun querySelector(selector: String): ElpianElement? = querySelectorAll(selector).firstOrNull()

    fun querySelectorAll(selector: String): List<ElpianElement> {
        val s = selector.trim()
        if (s.startsWith("#")) {
            val e = getElementById(s.substring(1))
            return if (e != null) listOf(e) else emptyList()
        }
        if (s.startsWith(".")) return getElementsByClassName(s.substring(1))
        // `tag.class` compound selectors.
        val m = COMPOUND.matchEntire(s)
        if (m != null && m.groupValues[2].isNotEmpty()) {
            val tag = m.groups[1]?.value
            val wanted = m.groupValues[2].split('.').filter { it.isNotEmpty() }
            return all.filter { e -> (tag.isNullOrEmpty() || e.tagName == tag) && wanted.all { e.classes.contains(it) } }
        }
        return getElementsByTagName(s)
    }

    fun createElement(tagName: String, id: String? = null, classes: List<String>? = null): ElpianElement {
        val el = ElpianElement(tagName, id, ArrayList(classes ?: emptyList()), this)
        if (el.id != null) byId[el.id] = el
        all.add(el)
        val tags = byTag[tagName] ?: ArrayList()
        tags.add(el)
        byTag[tagName] = tags
        for (c in el.classes) indexClass(c, el)
        return el
    }

    /** Build elements from Elpian JSON (`ElpianElement.fromElpianNode`). */
    fun fromJson(json: Map<String, Any?>): ElpianElement {
        val props: Map<String, Any?> = json["props"].asMap() ?: LinkedHashMap()
        val cn = props["className"]
        val classes = when (cn) {
            is String -> cn.split(WHITESPACE).filter { it.isNotEmpty() }
            is List<*> -> cn.map { jsString(it) }
            else -> emptyList()
        }
        val el = createElement(jsString(json["type"] ?: "div"), id = json["key"]?.let { jsString(it) }, classes = classes)
        for ((k, v) in props) if (k != "className" && k != "style") el.setAttribute(k, v)
        val style = props["style"]
        if (style is Map<*, *>) el.setStyleObject(style.asMap()!!)
        if (props["text"] != null) el.textContent = jsString(props["text"])
        val children = json["children"]
        if (children is List<*>) for (child in children) el.appendChild(fromJson(child.asMap() ?: LinkedHashMap()))
        return el
    }

    fun indexClass(className: String, el: ElpianElement) {
        val list = byClass[className] ?: ArrayList()
        if (!list.contains(el)) list.add(el)
        byClass[className] = list
    }

    fun unindexClass(className: String, el: ElpianElement) {
        val list = byClass[className] ?: return
        val i = list.indexOf(el)
        if (i >= 0) list.removeAt(i)
    }

    fun removeElement(el: ElpianElement) {
        if (el.id != null) byId.remove(el.id)
        all = ArrayList(all.filter { it !== el })
        val tags = byTag[el.tagName]
        if (tags != null) byTag[el.tagName] = ArrayList(tags.filter { it !== el })
        for (c in el.classes.toList()) unindexClass(c, el)
        el.parent?.removeChild(el)
    }

    fun clear() {
        byId.clear()
        all = ArrayList()
        byClass.clear()
        byTag.clear()
    }

    val allElements: List<ElpianElement> get() = ArrayList(all)

    private companion object {
        val COMPOUND = Regex("^([a-zA-Z][\\w-]*)?((?:\\.[\\w-]+)*)$")
        /** JavaScript's `\s` (Unicode white space and line terminators). */
        val WHITESPACE = Regex("[\\s\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]+")
    }
}
