package dev.elpian.core.a2ui

import dev.elpian.core.util.JsonMap
import kotlinx.coroutines.CompletableDeferred

/**
 * `A2UIConversation` (a2ui/conversation.ts) — one conversation with one
 * agent: the A2UI processor holding its surfaces, the transcript of prose,
 * UI-local state, and the agent transport. Turns ([send], [sendAction]) run
 * one at a time; each carries the conversation id, the `sendDataModel`
 * surfaces' data models and the client's supported catalogs. Without an
 * endpoint a conversation renders static A2UI messages ([ingest]) and
 * actions are only reported to listeners.
 */
sealed class A2UIConversationEvent {
    class Conversation(val conversationId: String) : A2UIConversationEvent()
    class Text(val text: String, val role: String) : A2UIConversationEvent()
    class Status(val state: String, val tool: String?) : A2UIConversationEvent()
    class Error(val message: String, val error: A2UIError? = null) : A2UIConversationEvent()
    class Done(val stopReason: String, val conversationId: String?) : A2UIConversationEvent()
    class Action(val action: A2UIClientAction) : A2UIConversationEvent()

    /** Surfaces, transcript or busy state changed: render again. */
    object Changed : A2UIConversationEvent()
}

typealias A2UIConversationListener = (A2UIConversationEvent) -> Unit

data class A2UITranscriptEntry(val role: String, val text: String)

data class A2UITurnResult(val conversationId: String?, val stopReason: String)

class A2UITurn(
    /** Completes once the agent named the conversation (or the turn ended without one). */
    val conversationId: CompletableDeferred<String?>,
    /** Completes when the turn ends, with its stop reason. */
    val done: CompletableDeferred<A2UITurnResult>,
)

data class A2UIStatus(val state: String, val tool: String? = null)

class A2UIConversation(
    endpoint: AgentEndpoint? = null,
    conversationId: String? = null,
    processorOptions: A2UIProcessorOptions = A2UIProcessorOptions(),
) {
    val processor = A2UIProcessor(processorOptions)
    val ui = A2UIUiState()
    val transcript = ArrayList<A2UITranscriptEntry>()
    var endpoint: AgentEndpoint? = endpoint
    var conversationId: String? = conversationId

    /** A turn is streaming. */
    var busy = false
        private set
    var status: A2UIStatus? = null
        private set

    /** The `prompt` of an embedding widget was sent (once per conversation). */
    var prompted = false
    private val listeners = LinkedHashSet<A2UIConversationListener>()
    private val queue = ArrayDeque<() -> Unit>()
    private var running = false
    private var cancel: (() -> Unit)? = null
    private var staticKey: String? = null
    private var disposed = false

    init {
        processor.on { e ->
            when (e) {
                is A2UIProcessorEvent.Error -> emit(A2UIConversationEvent.Error(e.error.message, e.error))
                is A2UIProcessorEvent.Action -> {
                    emit(A2UIConversationEvent.Action(e.action))
                    if (this.endpoint != null) sendAction(e.action.toJson())
                }
                is A2UIProcessorEvent.SurfaceDeleted -> {
                    ui.clearSurface(e.surfaceId)
                    emit(A2UIConversationEvent.Changed)
                }
                else -> emit(A2UIConversationEvent.Changed)
            }
        }
    }

    fun on(listener: A2UIConversationListener): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    private fun emit(event: A2UIConversationEvent) {
        for (l in listeners.toList()) {
            try {
                l(event)
            } catch (e: Exception) {
                warn("A2UI conversation listener failed: $e")
            }
        }
    }

    /** Hooks the lowering uses for this conversation's surfaces. */
    fun loweringHooks(invalidate: () -> Unit): LoweringHooks {
        val rerender = invalidate
        return object : LoweringHooks {
        override fun write(surfaceId: String, path: String, value: Any?) = processor.setData(surfaceId, path, value)

        override fun action(surfaceId: String, componentId: String, action: Any?, scope: String) {
            processor.dispatchAction(surfaceId, componentId, action, scope)
        }

        override fun invalidate() = rerender()

        override fun error(error: A2UIError) = emit(A2UIConversationEvent.Error(error.message, error))
        }
    }

    /** Render static A2UI messages (no agent). */
    fun ingest(messages: List<Any?>): List<A2UIError> = processor.processAll(messages)

    /** Static messages from a widget prop: re-applied from scratch when they change. */
    fun syncStatic(messages: List<Any?>, key: String) {
        if (key == staticKey) return
        staticKey = key
        processor.reset()
        ingest(messages)
    }

    /** Send a user message to the agent. */
    fun send(message: String): A2UITurn {
        transcript.add(A2UITranscriptEntry("user", message))
        emit(A2UIConversationEvent.Text(message, "user"))
        return turn(linkedMapOf("message" to message))
    }

    /** Send a client-to-server `action` to the agent. */
    fun sendAction(action: Map<String, Any?>): A2UITurn = turn(linkedMapOf("action" to LinkedHashMap(action)))

    fun sendAction(action: A2UIClientAction): A2UITurn = sendAction(action.toJson())

    /** The current data model of [surfaceId] (a copy), or null. */
    fun dataModel(surfaceId: String): Any? = processor.dataModel(surfaceId)

    /** A JSON summary (session `conversation()`). */
    fun describe(): JsonMap = linkedMapOf(
        "conversationId" to conversationId,
        "busy" to busy,
        "surfaces" to processor.surfaces.map { s ->
            linkedMapOf<String, Any?>("surfaceId" to s.id, "catalogId" to s.catalogId, "components" to s.components.size.toDouble(), "ready" to s.isReady)
        },
        "transcript" to transcript.map { linkedMapOf<String, Any?>("role" to it.role, "text" to it.text) },
    )

    private fun pump() {
        if (running) return
        val next = queue.removeFirstOrNull() ?: return
        running = true
        next()
    }

    private fun turn(payload: JsonMap): A2UITurn {
        val idDeferred = CompletableDeferred<String?>()
        val doneDeferred = CompletableDeferred<A2UITurnResult>()
        queue.addLast {
            var finished = false
            fun finish(stopReason: String) {
                if (finished) return
                finished = true
                idDeferred.complete(conversationId)
                busy = false
                status = null
                cancel = null
                emit(A2UIConversationEvent.Done(stopReason, conversationId))
                emit(A2UIConversationEvent.Changed)
                doneDeferred.complete(A2UITurnResult(conversationId, stopReason))
                running = false
                pump()
            }
            val endpoint = this.endpoint
            if (disposed) finish("error")
            else if (endpoint == null) {
                emit(A2UIConversationEvent.Error("this conversation has no agent endpoint"))
                finish("error")
            } else {
                val body: JsonMap = LinkedHashMap(payload)
                body["capabilities"] = linkedMapOf("supportedCatalogIds" to processor.supportedCatalogIds)
                conversationId?.let { body["conversationId"] = it }
                processor.clientDataModel()?.let { body["dataModel"] = it }
                busy = true
                status = A2UIStatus("working")
                emit(A2UIConversationEvent.Changed)
                var stopReason: String? = null
                val c = openAgentStream(
                    endpoint,
                    body,
                    object : AgentStreamSink {
                        override fun onLine(line: AgentStreamLine) {
                            if (line is AgentStreamLine.Done) stopReason = line.stopReason
                            handleLine(line)
                            if (line is AgentStreamLine.Conversation) idDeferred.complete(line.conversationId)
                        }

                        override fun onError(message: String) = emit(A2UIConversationEvent.Error(message))

                        override fun onClose() = finish(stopReason ?: "error")
                    },
                )
                // A transport may finish synchronously, before returning its canceller.
                if (!finished) cancel = c
            }
        }
        pump()
        return A2UITurn(idDeferred, doneDeferred)
    }

    /** Apply one response line (exposed for transports other than HTTP). */
    fun handleLine(line: AgentStreamLine) {
        when (line) {
            is AgentStreamLine.A2UI -> processor.process(line.message)
            is AgentStreamLine.Conversation -> {
                conversationId = line.conversationId
                emit(A2UIConversationEvent.Conversation(line.conversationId))
            }
            is AgentStreamLine.Text -> {
                transcript.add(A2UITranscriptEntry("agent", line.text))
                emit(A2UIConversationEvent.Text(line.text, "agent"))
                emit(A2UIConversationEvent.Changed)
            }
            is AgentStreamLine.Status -> {
                val s = A2UIStatus(line.state, line.tool)
                status = s
                emit(A2UIConversationEvent.Status(s.state, s.tool))
                emit(A2UIConversationEvent.Changed)
            }
            is AgentStreamLine.Error -> emit(A2UIConversationEvent.Error(line.message))
            is AgentStreamLine.Done -> {}
        }
    }

    fun dispose() {
        disposed = true
        cancel?.invoke()
        cancel = null
        listeners.clear()
    }
}
