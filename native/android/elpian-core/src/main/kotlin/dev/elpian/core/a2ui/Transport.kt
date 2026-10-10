package dev.elpian.core.a2ui

import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.platform
import dev.elpian.core.session.encodeURIComponent
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.jsString

/**
 * The agent transport (a2ui/transport.ts): `POST <baseUrl>/apps/<app>/agent/<agent>`,
 * answered with NDJSON (`application/x-ndjson`, one JSON object per line),
 * read incrementally through the platform's `fetchStream`. Chunk boundaries
 * fall anywhere and the decoder reassembles lines across them.
 *
 * Response lines (the Elpian agent contract):
 *   {"type":"conversation","conversationId":"…"}          always first
 *   {"version":"v0.9.1","createSurface":{…}}               A2UI messages, verbatim
 *   {"type":"text","text":"…"}                             the agent's prose
 *   {"type":"status","state":"working"|"tool","tool":"…"}  progress
 *   {"type":"error","message":"…"}
 *   {"type":"done","stopReason":"end_turn"|…}              always last
 */
class AgentEndpoint(
    val baseUrl: String,
    val appId: String,
    val agent: String,
    val headers: Map<String, String> = emptyMap(),
    val timeoutMs: Long? = null,
)

/** One decoded response line. */
sealed class AgentStreamLine {
    data class A2UI(val message: JsonMap) : AgentStreamLine()
    data class Conversation(val conversationId: String) : AgentStreamLine()
    data class Text(val text: String) : AgentStreamLine()
    data class Status(val state: String, val tool: String? = null) : AgentStreamLine()
    data class Error(val message: String) : AgentStreamLine()
    data class Done(val stopReason: String) : AgentStreamLine()
}

/** `<baseUrl>/apps/<app>/agent/<agent>` (names percent-encoded). */
fun agentUrl(endpoint: AgentEndpoint): String =
    "${endpoint.baseUrl.trimEnd('/')}/apps/${encodeURIComponent(endpoint.appId)}/agent/${encodeURIComponent(endpoint.agent)}"

/** Classify one decoded response line (null for lines this client does not know). */
@Suppress("UNCHECKED_CAST")
fun classifyLine(value: Any?): AgentStreamLine? {
    if (value !is Map<*, *>) return null
    val v = value as Map<String, Any?>
    if (messageKind(v) != null) return AgentStreamLine.A2UI(LinkedHashMap(v))
    return when (v["type"]) {
        "conversation" -> (v["conversationId"] as? String)?.let { AgentStreamLine.Conversation(it) }
        "text" -> AgentStreamLine.Text(v["text"] as? String ?: (v["text"]?.let { jsString(it) } ?: ""))
        "status" -> AgentStreamLine.Status(v["state"]?.let { jsString(it) } ?: "working", v["tool"] as? String)
        "error" -> AgentStreamLine.Error(v["message"] as? String ?: "the agent failed")
        "done" -> AgentStreamLine.Done(v["stopReason"] as? String ?: "end_turn")
        else -> null
    }
}

/**
 * Newline-delimited JSON decoding across arbitrary chunk boundaries. Blank
 * lines are skipped; a line that is not JSON is reported and skipped.
 */
class NdjsonDecoder(private val onBadLine: ((String) -> Unit)? = null) {
    private val buffer = StringBuilder()

    /** Feed a chunk; returns the complete values it finished. */
    fun push(chunk: String): List<Any?> {
        buffer.append(chunk)
        val out = ArrayList<Any?>()
        while (true) {
            val i = buffer.indexOf("\n")
            if (i < 0) break
            val line = buffer.substring(0, i)
            buffer.delete(0, i + 1)
            decode(line, out)
        }
        return out
    }

    /** The stream ended: decode a final unterminated line. */
    fun end(): List<Any?> {
        val out = ArrayList<Any?>()
        val rest = buffer.toString()
        buffer.setLength(0)
        decode(rest, out)
        return out
    }

    private fun decode(raw: String, out: MutableList<Any?>) {
        val line = raw.removeSuffix("\r").trim()
        if (line.isEmpty()) return
        try {
            out.add(Json.parse(line))
        } catch (_: Exception) {
            onBadLine?.invoke(line)
        }
    }
}

interface AgentStreamSink {
    fun onLine(line: AgentStreamLine)

    /** Transport-level failure (no connection, HTTP error, unparseable line). */
    fun onError(message: String)

    /** The response ended (after any error). */
    fun onClose()
}

/** Start one agent turn with the JSON request [body]; returns a canceller. */
fun openAgentStream(endpoint: AgentEndpoint, body: Map<String, Any?>, sink: AgentStreamSink): () -> Unit {
    val host = platform()
    val decoder = NdjsonDecoder { sink.onError("the agent sent an unreadable line") }
    var closed = false
    fun deliver(values: List<Any?>) {
        for (v in values) classifyLine(v)?.let { sink.onLine(it) }
    }
    fun close() {
        if (closed) return
        closed = true
        sink.onClose()
    }
    val request = FetchRequest(
        url = agentUrl(endpoint),
        method = "POST",
        headers = linkedMapOf("content-type" to "application/json", "accept" to "application/x-ndjson") + endpoint.headers,
        body = Json.stringify(body),
        timeoutMs = endpoint.timeoutMs ?: 300000L,
    )
    val cancel = host.fetchStream(
        request,
        object : StreamHandlers {
            override fun onChunk(text: String) {
                if (!closed) deliver(decoder.push(text))
            }

            override fun onDone() {
                if (closed) return
                deliver(decoder.end())
                close()
            }

            override fun onError(message: String) {
                if (closed) return
                deliver(decoder.end())
                sink.onError(message.ifEmpty { "the agent could not be reached" })
                close()
            }
        },
    )
    return {
        closed = true
        cancel()
    }
}
