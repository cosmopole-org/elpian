/**
 * `A2UIConversation` — one conversation with one agent: the A2UI processor
 * holding its surfaces, the transcript of prose, UI-local state, and the
 * agent transport. Turns (`send(message)`, `sendAction(action)`) run one at
 * a time; each carries the conversation id, the `sendDataModel` surfaces'
 * data models and the client's supported catalogs. Without an endpoint a
 * conversation renders static A2UI messages ([ingest]) and actions are only
 * reported to listeners.
 */
import { A2UIError } from './errors.js';
import { A2UIUiState, type LoweringHooks } from './lowering.js';
import { A2UIProcessor, type A2UIClientAction, type A2UIProcessorOptions } from './processor.js';
import { openAgentStream, type AgentEndpoint, type AgentRequestBody, type AgentStreamLine } from './transport.js';

export type A2UIConversationEvent =
  | { type: 'conversation'; conversationId: string }
  | { type: 'text'; text: string; role: 'agent' | 'user' }
  | { type: 'status'; state: string; tool?: string }
  | { type: 'error'; message: string; error?: A2UIError }
  | { type: 'done'; stopReason: string; conversationId: string | null }
  | { type: 'action'; action: A2UIClientAction }
  /** Surfaces, transcript or busy state changed: render again. */
  | { type: 'changed' };

export type A2UIConversationListener = (event: A2UIConversationEvent) => void;

export interface A2UITranscriptEntry {
  role: 'agent' | 'user';
  text: string;
}

export interface A2UITurn {
  /** Resolves once the agent named the conversation (or the turn ended without one). */
  conversationId: Promise<string | null>;
  /** Resolves when the turn ends, with its stop reason. */
  done: Promise<{ conversationId: string | null; stopReason: string }>;
}

export interface A2UIConversationOptions {
  endpoint?: AgentEndpoint | null;
  conversationId?: string | null;
  processor?: A2UIProcessorOptions;
}

export class A2UIConversation {
  readonly processor: A2UIProcessor;
  readonly ui = new A2UIUiState();
  readonly transcript: A2UITranscriptEntry[] = [];
  endpoint: AgentEndpoint | null;
  conversationId: string | null;
  /** A turn is streaming. */
  busy = false;
  status: { state: string; tool?: string } | null = null;
  /** The `prompt` of an embedding widget was sent (once per conversation). */
  prompted = false;
  private readonly listeners = new Set<A2UIConversationListener>();
  private queue: Promise<unknown> = Promise.resolve();
  private cancel: (() => void) | null = null;
  private staticKey: string | null = null;
  private disposed = false;

  constructor(options: A2UIConversationOptions = {}) {
    this.endpoint = options.endpoint ?? null;
    this.conversationId = options.conversationId ?? null;
    this.processor = new A2UIProcessor(options.processor ?? {});
    this.processor.on((e) => {
      switch (e.type) {
        case 'error':
          this.emit({ type: 'error', message: e.error.message, error: e.error });
          break;
        case 'action':
          this.emit({ type: 'action', action: e.action });
          if (this.endpoint) void this.sendAction(e.action);
          break;
        case 'surfaceDeleted':
          this.ui.clearSurface(e.surfaceId);
          this.emit({ type: 'changed' });
          break;
        default:
          this.emit({ type: 'changed' });
      }
    });
  }

  on(listener: A2UIConversationListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(event: A2UIConversationEvent): void {
    for (const l of [...this.listeners]) {
      try {
        l(event);
      } catch (e) {
        console.warn('A2UI conversation listener failed:', e);
      }
    }
  }

  /** Hooks the lowering uses for this conversation's surfaces. */
  loweringHooks(invalidate: () => void): LoweringHooks {
    return {
      write: (surfaceId, path, value) => this.processor.setData(surfaceId, path, value),
      action: (surfaceId, componentId, action, scope) => {
        this.processor.dispatchAction(surfaceId, componentId, action, scope);
      },
      invalidate,
      error: (error) => this.emit({ type: 'error', message: error.message, error }),
    };
  }

  /** Render static A2UI messages (no agent). */
  ingest(messages: readonly unknown[]): A2UIError[] {
    return this.processor.processAll(messages);
  }

  /** Static messages from a widget prop: re-applied from scratch when they change. */
  syncStatic(messages: readonly unknown[], key: string): void {
    if (key === this.staticKey) return;
    this.staticKey = key;
    this.processor.reset();
    this.ingest(messages);
  }

  /** Send a user message to the agent. */
  send(message: string): A2UITurn {
    this.transcript.push({ role: 'user', text: message });
    this.emit({ type: 'text', text: message, role: 'user' });
    return this.turn({ message });
  }

  /** Send a client-to-server `action` to the agent. */
  sendAction(action: A2UIClientAction | Record<string, unknown>): A2UITurn {
    return this.turn({ action: { ...action } });
  }

  /** The current data model of [surfaceId] (a copy), or undefined. */
  dataModel(surfaceId: string): unknown {
    return this.processor.dataModel(surfaceId);
  }

  /** A JSON summary (session `conversation()`). */
  describe(): Record<string, unknown> {
    return {
      conversationId: this.conversationId,
      busy: this.busy,
      surfaces: this.processor.surfaces.map((s) => ({ surfaceId: s.id, catalogId: s.catalogId, components: s.components.size, ready: s.isReady })),
      transcript: this.transcript.map((t) => ({ ...t })),
    };
  }

  private turn(payload: Pick<AgentRequestBody, 'message' | 'action'>): A2UITurn {
    let resolveId!: (id: string | null) => void;
    const conversationId = new Promise<string | null>((r) => (resolveId = r));
    const done = new Promise<{ conversationId: string | null; stopReason: string }>((resolveDone) => {
      this.queue = this.queue.then(
        () =>
          new Promise<void>((next) => {
            const finish = (stopReason: string) => {
              resolveId(this.conversationId);
              this.busy = false;
              this.status = null;
              this.cancel = null;
              this.emit({ type: 'done', stopReason, conversationId: this.conversationId });
              this.emit({ type: 'changed' });
              resolveDone({ conversationId: this.conversationId, stopReason });
              next();
            };
            if (this.disposed) return finish('error');
            const endpoint = this.endpoint;
            if (!endpoint) {
              this.emit({ type: 'error', message: 'this conversation has no agent endpoint' });
              return finish('error');
            }
            const body: AgentRequestBody = { ...payload, capabilities: { supportedCatalogIds: this.processor.supportedCatalogIds } };
            if (this.conversationId) body.conversationId = this.conversationId;
            const dataModel = this.processor.clientDataModel();
            if (dataModel) body.dataModel = dataModel;
            this.busy = true;
            this.status = { state: 'working' };
            this.emit({ type: 'changed' });
            let stopReason: string | null = null;
            this.cancel = openAgentStream(endpoint, body, {
              onLine: (line) => {
                if (line.kind === 'done') stopReason = line.stopReason;
                this.handleLine(line);
                if (line.kind === 'conversation') resolveId(line.conversationId);
              },
              onError: (message) => this.emit({ type: 'error', message }),
              onClose: () => finish(stopReason ?? 'error'),
            });
          }),
      );
    });
    return { conversationId, done };
  }

  /** Apply one response line (exposed for transports other than HTTP). */
  handleLine(line: AgentStreamLine): void {
    switch (line.kind) {
      case 'a2ui':
        this.processor.process(line.message);
        break;
      case 'conversation':
        this.conversationId = line.conversationId;
        this.emit({ type: 'conversation', conversationId: line.conversationId });
        break;
      case 'text':
        this.transcript.push({ role: 'agent', text: line.text });
        this.emit({ type: 'text', text: line.text, role: 'agent' });
        this.emit({ type: 'changed' });
        break;
      case 'status':
        this.status = line.tool ? { state: line.state, tool: line.tool } : { state: line.state };
        this.emit({ type: 'status', ...this.status });
        this.emit({ type: 'changed' });
        break;
      case 'error':
        this.emit({ type: 'error', message: line.message });
        break;
      case 'done':
        break;
    }
  }

  dispose(): void {
    this.disposed = true;
    this.cancel?.();
    this.cancel = null;
    this.listeners.clear();
  }
}
