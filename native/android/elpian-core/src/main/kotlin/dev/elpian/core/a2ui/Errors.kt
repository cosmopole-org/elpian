package dev.elpian.core.a2ui

/**
 * A2UI errors (a2ui/errors.ts). Every failure the renderer reports carries a
 * category (the conformance suites' `expect_error.category`) and, for
 * validation failures, the protocol's standard error shape:
 *
 * ```json
 * { "code": "VALIDATION_FAILED", "surfaceId": "s1", "path": "/components/0/text", "message": "…" }
 * ```
 *
 * Categories: `DataError`, `ParseError`, `ValidationError`, `ExpressionError`,
 * `TransportError`. Issue codes (machine-readable cause of a schema issue):
 * `missing_field`, `invalid_value`, `type_mismatch`, `unknown_field`,
 * `topology`, `limit`.
 */
class A2UIErrorDetails(
    val surfaceId: String? = null,
    val path: String? = null,
    val issue: String? = null,
) {
    fun copy(surfaceId: String? = this.surfaceId, path: String? = this.path, issue: String? = this.issue): A2UIErrorDetails =
        A2UIErrorDetails(surfaceId, path, issue)
}

class A2UIError(
    val category: String,
    message: String,
    val details: A2UIErrorDetails = A2UIErrorDetails(),
) : RuntimeException(message) {
    override val message: String get() = super.message ?: ""

    val surfaceId: String? get() = details.surfaceId

    val path: String? get() = details.path

    /** The client→server `error` payload (A2UI's standard shape). */
    fun toWire(): MutableMap<String, Any?> {
        if (category == "ValidationError") {
            return linkedMapOf("code" to "VALIDATION_FAILED", "surfaceId" to (surfaceId ?: ""), "path" to (path ?: "/"), "message" to message)
        }
        return linkedMapOf("code" to category.removeSuffix("Error").uppercase() + "_ERROR", "surfaceId" to (surfaceId ?: ""), "message" to message)
    }

    override fun toString(): String = "$category: $message"
}

fun dataError(message: String): A2UIError = A2UIError("DataError", message)

fun parseError(message: String): A2UIError = A2UIError("ParseError", message)

fun expressionError(message: String): A2UIError = A2UIError("ExpressionError", message)
