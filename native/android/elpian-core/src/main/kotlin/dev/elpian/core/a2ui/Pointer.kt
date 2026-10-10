package dev.elpian.core.a2ui

/**
 * JSON Pointers (RFC 6901) as A2UI uses them (a2ui/pointer.ts): absolute
 * paths (`/user/name`), relative paths resolved against a data scope (`name`
 * inside a template item at `/users/0`), `.`/`..` segments, and tolerant
 * normalisation of empty segments (`//a///b//` is `/a/b`).
 */

/** Segments that would reach a JavaScript prototype; refused on read and write (kept for parity). */
private val FORBIDDEN = setOf("__proto__", "constructor", "prototype")

private val BAD_ESCAPE = Regex("~(?![01])")
private val INDEX_SEGMENT = Regex("^(0|[1-9][0-9]*)$")

/** True when [path] only uses valid `~0` / `~1` escapes. */
fun isValidPointerSyntax(path: String): Boolean = !BAD_ESCAPE.containsMatchIn(path)

/** Decode one reference token (`~1` → `/`, then `~0` → `~`). */
fun decodeSegment(token: String): String = token.replace("~1", "/").replace("~0", "~")

/** Encode one key as a reference token. */
fun encodeSegment(key: String): String = key.replace("~", "~0").replace("/", "~1")

/**
 * The decoded segments of an absolute pointer. Empty segments are dropped, so
 * `''`, `'/'` and `'///'` all address the root.
 */
fun parsePointer(path: String): List<String> {
    if (!isValidPointerSyntax(path)) {
        throw A2UIError("ValidationError", "Invalid path syntax: \"$path\" uses an escape other than ~0 or ~1", A2UIErrorDetails(path = path))
    }
    val segments = path.split('/').filter { it != "" }.map { decodeSegment(it) }
    for (s in segments) if (s in FORBIDDEN) throw dataError("Forbidden path segment \"$s\" in \"$path\"")
    return segments
}

/** The canonical pointer for [segments] (`/` for the root). */
fun formatPointer(segments: List<String>): String =
    if (segments.isEmpty()) "/" else "/" + segments.joinToString("/") { encodeSegment(it) }

/** Normalise a pointer to its canonical spelling. */
fun normalizePointer(path: String): String = formatPointer(parsePointer(path))

/**
 * Resolve [path] against the data scope [contextPath] (`/` when absent):
 * absolute paths ignore the scope; `''` and `.` mean the scope itself; `..`
 * walks up one level.
 */
fun resolvePath(path: String, contextPath: String? = null): String {
    if (path.startsWith("/")) return path
    val base = (contextPath ?: "/").split('/').filter { it != "" }.toMutableList()
    for (raw in path.split('/')) {
        if (raw == "" || raw == ".") continue
        if (raw == "..") {
            if (base.isNotEmpty()) base.removeAt(base.size - 1)
        } else base.add(raw)
    }
    return if (base.isEmpty()) "/" else "/" + base.joinToString("/")
}

/** Array index segments: `0` or a digit run without a leading zero. */
fun isIndexSegment(segment: String): Boolean = INDEX_SEGMENT.matches(segment)

/** Whether [ancestor] is [path] or a prefix of it, segment-wise. */
fun isPrefixOf(ancestor: List<String>, path: List<String>): Boolean {
    if (ancestor.size > path.size) return false
    for (i in ancestor.indices) if (ancestor[i] != path[i]) return false
    return true
}
