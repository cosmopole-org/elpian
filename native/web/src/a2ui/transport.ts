/**
 * The agent transport: `POST <baseUrl>/apps/<app>/agent/<agent>`, answered
 * with NDJSON (`application/x-ndjson`, one JSON object per line), read
 * incrementally through the platform's `fetchStream`. Chunk boundaries fall
 * anywhere — mid-line, mid-UTF-8 character text, several lines at once — and
 * the decoder reassembles lines across them.
 *
 * Response lines (the Elpian agent contract):
 *   {"type":"conversation","conversationId":"…"}          always first
 *   {"version":"v0.9.1","createSurface":{…}}               A2UI messages, verbatim
 *   {"type":"text","text":"…"}                             the agent's prose
 *   {"type":"status","state":"working"|"tool","tool":"…"}  progress
 *   {"type":"error","message":"…"}
 *   {"type":"done","stopReason":"end_turn"|…}              always last
 */
import { platform, type FetchRequest, type StreamHandlers } from '../platform/platform.js';
import { messageKind } from './validator.js';

/** Where an agent lives. */
export interface AgentEndpoint {
  baseUrl: string;
  appId: string;
  agent: string;
  headers?: Record<string, string>;
  timeoutMs?: number;
}

/** The request body of one agent turn. */
export interface AgentRequestBody {
  conversationId?: string;
  message?: string;
  action?: Record<string, unknown>;
  dataModel?: { version?: string; surfaces: Record<string, unknown> };
  capabilities?: { supportedCatalogIds: string[] };
}

export type AgentStreamLine =
  | { kind: 'a2ui'; message: Record<string, unknown> }
  | { kind: 'conversation'; conversationId: string }
  | { kind: 'text'; text: string }
  | { kind: 'status'; state: string; tool?: string }
  | { kind: 'error'; message: string }
  | { kind: 'done'; stopReason: string };

/** `<baseUrl>/apps/<app>/agent/<agent>` (names percent-encoded). */
export function agentUrl(endpoint: AgentEndpoint): string {
  return `${endpoint.baseUrl.replace(/\/+$/, '')}/apps/${encodeURIComponent(endpoint.appId)}/agent/${encodeURIComponent(endpoint.agent)}`;
}

/** Classify one decoded response line (null for lines this client does not know). */
export function classifyLine(value: unknown): AgentStreamLine | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const v = value as Record<string, any>;
  if (messageKind(v)) return { kind: 'a2ui', message: v };
  switch (v.type) {
    case 'conversation':
      return typeof v.conversationId === 'string' ? { kind: 'conversation', conversationId: v.conversationId } : null;
    case 'text':
      return { kind: 'text', text: typeof v.text === 'string' ? v.text : String(v.text ?? '') };
    case 'status':
      return { kind: 'status', state: String(v.state ?? 'working'), ...(typeof v.tool === 'string' ? { tool: v.tool } : {}) };
    case 'error':
      return { kind: 'error', message: typeof v.message === 'string' ? v.message : 'the agent failed' };
    case 'done':
      return { kind: 'done', stopReason: typeof v.stopReason === 'string' ? v.stopReason : 'end_turn' };
  }
  return null;
}

/**
 * Newline-delimited JSON decoding across arbitrary chunk boundaries. Blank
 * lines are skipped; a line that is not JSON is reported and skipped.
 */
export class NdjsonDecoder {
  private buffer = '';

  constructor(private readonly onBadLine?: (line: string) => void) {}

  /** Feed a chunk; returns the complete values it finished. */
  push(chunk: string): unknown[] {
    this.buffer += chunk;
    const out: unknown[] = [];
    let i: number;
    while ((i = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.substring(0, i);
      this.buffer = this.buffer.substring(i + 1);
      this.decode(line, out);
    }
    return out;
  }

  /** The stream ended: decode a final unterminated line. */
  end(): unknown[] {
    const out: unknown[] = [];
    const rest = this.buffer;
    this.buffer = '';
    this.decode(rest, out);
    return out;
  }

  private decode(raw: string, out: unknown[]): void {
    const line = raw.replace(/\r$/, '').trim();
    if (!line) return;
    try {
      out.push(JSON.parse(line));
    } catch {
      this.onBadLine?.(line);
    }
  }
}

export interface AgentStreamSink {
  onLine(line: AgentStreamLine): void;
  /** Transport-level failure (no connection, HTTP error, unparseable line). */
  onError(message: string): void;
  /** The response ended (after any error). */
  onClose(): void;
}

/** Start one agent turn; returns a canceller. */
export function openAgentStream(endpoint: AgentEndpoint, body: AgentRequestBody, sink: AgentStreamSink): () => void {
  const host = platform();
  if (!host.fetchStream) {
    sink.onError('this host cannot stream HTTP responses');
    sink.onClose();
    return () => {};
  }
  const decoder = new NdjsonDecoder(() => sink.onError('the agent sent an unreadable line'));
  let closed = false;
  const deliver = (values: unknown[]) => {
    for (const v of values) {
      const line = classifyLine(v);
      if (line) sink.onLine(line);
    }
  };
  const close = () => {
    if (closed) return;
    closed = true;
    sink.onClose();
  };
  const request: FetchRequest = {
    url: agentUrl(endpoint),
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/x-ndjson', ...(endpoint.headers ?? {}) },
    body: JSON.stringify(body),
    timeoutMs: endpoint.timeoutMs ?? 300000,
  };
  const handlers: StreamHandlers = {
    onChunk: (text) => {
      if (!closed) deliver(decoder.push(text));
    },
    onDone: () => {
      if (closed) return;
      deliver(decoder.end());
      close();
    },
    onError: (message) => {
      if (closed) return;
      deliver(decoder.end());
      sink.onError(message || 'the agent could not be reached');
      close();
    },
  };
  const cancel = host.fetchStream(request, handlers);
  return () => {
    closed = true;
    cancel();
  };
}
