import Foundation

/**
 * JSON Pointers (RFC 6901) as A2UI uses them (a2ui/pointer.ts): absolute
 * paths (`/user/name`), relative paths resolved against a data scope (`name`
 * inside a template item at `/users/0`), `.`/`..` segments, and tolerant
 * normalisation of empty segments (`//a///b//` is `/a/b`).
 */

/** Segments that would reach a JavaScript prototype; refused on read and write (as the TypeScript renderer does). */
private let FORBIDDEN: Set<String> = ["__proto__", "constructor", "prototype"]

private let BAD_ESCAPE = JSRegex("~(?![01])")
private let INDEX_SEGMENT = JSRegex("^(0|[1-9][0-9]*)$")

/** True when [path] only uses valid `~0` / `~1` escapes. */
public func isValidPointerSyntax(_ path: String) -> Bool {
    !BAD_ESCAPE.test(path)
}

/** Decode one reference token (`~1` → `/`, then `~0` → `~`). */
public func decodeSegment(_ token: String) -> String {
    token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
}

/** Encode one key as a reference token. */
public func encodeSegment(_ key: String) -> String {
    key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
}

/** `path.split('/')` (JavaScript semantics: empty leading/trailing parts kept). */
func a2uiSplitSlash(_ path: String) -> [String] {
    path.components(separatedBy: "/")
}

/**
 * The decoded segments of an absolute pointer. Empty segments are dropped, so
 * `''`, `'/'` and `'///'` all address the root.
 */
public func parsePointer(_ path: String) throws -> [String] {
    if !isValidPointerSyntax(path) {
        throw A2UIError(.ValidationError, "Invalid path syntax: \"\(path)\" uses an escape other than ~0 or ~1", path: path)
    }
    let segments = a2uiSplitSlash(path).filter { !$0.isEmpty }.map(decodeSegment)
    for s in segments where FORBIDDEN.contains(s) { throw dataError("Forbidden path segment \"\(s)\" in \"\(path)\"") }
    return segments
}

/** The canonical pointer for [segments] (`/` for the root). */
public func formatPointer(_ segments: [String]) -> String {
    segments.isEmpty ? "/" : "/" + segments.map(encodeSegment).joined(separator: "/")
}

/** Normalise a pointer to its canonical spelling. */
public func normalizePointer(_ path: String) throws -> String {
    formatPointer(try parsePointer(path))
}

/**
 * Resolve [path] against the data scope [contextPath] (`/` when absent):
 * absolute paths ignore the scope; `''` and `.` mean the scope itself; `..`
 * walks up one level.
 */
public func resolvePath(_ path: String, _ contextPath: String? = nil) -> String {
    if path.hasPrefix("/") { return path }
    var base = a2uiSplitSlash(contextPath ?? "/").filter { !$0.isEmpty }
    for raw in a2uiSplitSlash(path) {
        if raw.isEmpty || raw == "." { continue }
        if raw == ".." {
            if !base.isEmpty { base.removeLast() }
        } else {
            base.append(raw)
        }
    }
    return base.isEmpty ? "/" : "/" + base.joined(separator: "/")
}

/** Array index segments: `0` or a digit run without a leading zero. */
public func isIndexSegment(_ segment: String) -> Bool {
    INDEX_SEGMENT.test(segment)
}

/** Whether [ancestor] is [path] or a prefix of it, segment-wise. */
public func isPrefixOf(_ ancestor: [String], _ path: [String]) -> Bool {
    if ancestor.count > path.count { return false }
    for i in 0..<ancestor.count where ancestor[i] != path[i] { return false }
    return true
}
