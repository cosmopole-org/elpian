/**
 * Full-stack mini apps — ports of flutter/lib/src/fullstack/{server_client,
 * server_component}.dart: a mini app calling its own server functions
 * (`server.call`, `server.render`), brokered client networking (`net.fetch`
 * through the host's proxy under an `ElpianNetPolicy`), streamed components,
 * and server-rendered components with islands.
 *
 * Islands are either lowering functions (props + server-rendered children →
 * widget) or host-registered native components (Android View / UIView / DOM
 * element / React Native component) rendered through the `native` view kind.
 */
import type { WidgetBuilder } from '../widgets/context.js';
import { w, type W } from '../render/object.js';
import { platform } from '../platform/platform.js';
import { isMap, stableKey, type JsonMap } from '../util/json.js';
import { ElpianSurface, loadingIndicator, type SurfaceOptions } from '../session/surface.js';
import { StreamSession, type StreamSessionOptions } from '../session/stream.js';

export class ElpianNetPolicy {
  private constructor(
    readonly mode: 'closed' | 'open' | 'brokered',
    readonly allowlist: readonly string[],
  ) {}
  static readonly closed = new ElpianNetPolicy('closed', []);
  static readonly open = new ElpianNetPolicy('open', []);
  static brokered(allowlist: string[]): ElpianNetPolicy {
    return new ElpianNetPolicy('brokered', [...allowlist]);
  }
  static fromManifest(value: unknown): ElpianNetPolicy {
    if (value === 'open') return ElpianNetPolicy.open;
    if (isMap(value)) return ElpianNetPolicy.brokered(Array.isArray(value.allow) ? value.allow.filter((x: unknown): x is string => typeof x === 'string') : []);
    return ElpianNetPolicy.closed;
  }
  allows(url: string): boolean {
    if (this.mode === 'closed') return false;
    if (this.mode === 'open') return true;
    const host = hostOf(url);
    if (!host) return false;
    return this.allowlist.some((e) => matches(e.toLowerCase(), host.toLowerCase()));
  }
}

function matches(entry: string, host: string): boolean {
  if (entry.startsWith('*.')) {
    const suffix = entry.substring(2);
    return host !== suffix && host.length > suffix.length && host.endsWith(suffix) && host[host.length - suffix.length - 1] === '.';
  }
  return host === entry;
}

function hostOf(url: string): string | null {
  const m = /^[a-zA-Z][\w+.-]*:\/\/(?:[^@/?#]*@)?(\[[^\]]+\]|[^:/?#]+)/.exec(url);
  return m ? m[1] : null;
}

export interface ServerCallResult {
  result?: unknown;
  error?: string | null;
}
export interface ServerRenderResult {
  payload?: JsonMap | null;
  error?: string | null;
}

export class ElpianServerClient {
  readonly timeoutMs: number;
  private closed = false;
  private readonly cancels = new Set<() => void>();

  constructor(
    readonly baseUrl: string,
    readonly appId: string,
    readonly netPolicy: ElpianNetPolicy = ElpianNetPolicy.closed,
    readonly authorization: string | null = null,
    timeoutMs = 15000,
  ) {
    this.timeoutMs = timeoutMs;
  }

  /** Host handlers for a mini app runtime: `server.call`, `server.render`, `net.fetch`. */
  get hostHandlers(): Record<string, (api: string, payload: string) => Promise<string>> {
    return {
      'server.call': (_a, p) => this.invoke(p, false),
      'server.render': (_a, p) => this.invoke(p, true),
      'net.fetch': (_a, p) => this.clientFetch(p),
    };
  }

  private headers(): Record<string, string> {
    return { 'content-type': 'application/json', ...(this.authorization ? { authorization: this.authorization } : {}) };
  }

  private async post(url: string, body: unknown): Promise<{ status: number; body: string }> {
    const fetch = platform().fetch;
    if (!fetch) throw new Error('no HTTP client');
    return fetch({ url, method: 'POST', headers: this.headers(), body: JSON.stringify(body), timeoutMs: this.timeoutMs });
  }

  private async invoke(payload: string, render: boolean): Promise<string> {
    const args = positional(payload);
    const name = args[0];
    if (typeof name !== 'string' || !name) return 'null';
    const body = args.length > 1 ? args[1] : {};
    const path = render ? 'render' : 'fn';
    // Percent-encoded so a guest-chosen name cannot change the path's shape.
    const url = `${this.baseUrl}/apps/${encodeURIComponent(this.appId)}/${path}/${encodeURIComponent(name)}`;
    try {
      const res = await this.post(url, body);
      if (res.status !== 200) return typedError(errorMessage(res.body) ?? 'the call failed');
      const decoded = JSON.parse(res.body);
      if (isMap(decoded) && decoded.ok === true) return JSON.stringify(decoded.result ?? null);
      return typedError(errorMessage(res.body) ?? 'the call failed');
    } catch (e) {
      const text = String(e);
      if (/timed? ?out/i.test(text)) return typedError('the server did not answer in time');
      if (/network|connect|resolve|unreachable/i.test(text)) return typedError('the server could not be reached');
      platform().log('warn', `ElpianServerClient: ${this.appId}/${path} failed: ${e}`);
      return typedError('the call failed');
    }
  }

  private async clientFetch(payload: string): Promise<string> {
    const url = positional(payload)[0];
    if (typeof url !== 'string') return 'null';
    // Refused locally without a round trip; the server would refuse it too.
    if (!this.netPolicy.allows(url)) return typedError('the request was not permitted');
    // Allowed requests still go through the host's broker (one policy, one audit trail).
    try {
      const res = await this.post(`${this.baseUrl}/apps/${this.appId}/proxy`, { url });
      if (res.status !== 200) return typedError('the request was not permitted');
      const decoded = JSON.parse(res.body);
      if (isMap(decoded) && decoded.ok === true) return JSON.stringify(decoded.result ?? null);
    } catch {
      /* fall through */
    }
    return typedError('the request was not permitted');
  }

  async renderComponent(name: string, args: JsonMap): Promise<ServerRenderResult> {
    const raw = await this.invoke(JSON.stringify([name, args]), true);
    try {
      const d = JSON.parse(raw);
      if (isMap(d) && d.error != null) return { error: isMap(d.error) ? String(d.error.message ?? 'the call failed') : String(d.error) };
      if (isMap(d)) return { payload: d };
    } catch {
      /* fall through */
    }
    return { error: 'the server returned no payload' };
  }

  async callAction(name: string, args: JsonMap): Promise<ServerCallResult> {
    const raw = await this.invoke(JSON.stringify([name, args]), false);
    try {
      const d = JSON.parse(raw);
      if (isMap(d) && d.error != null) return { error: isMap(d.error) ? String(d.error.message ?? 'the call failed') : String(d.error) };
      return { result: d };
    } catch {
      return { error: 'the call failed' };
    }
  }

  /**
   * Stream a component: newline-delimited frames, each a stream command
   * (`{"action":"error"}` frames surface as errors). Returns a canceller.
   */
  streamComponent(name: string, args: JsonMap, sink: { onFrame(frame: unknown): void; onError(message: string): void; onDone(): void }): () => void {
    const fetchStream = platform().fetchStream;
    if (!fetchStream || this.closed) {
      sink.onError('the stream could not be opened');
      sink.onDone();
      return () => {};
    }
    let buffer = '';
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      this.cancels.delete(cancel);
      sink.onDone();
    };
    const emit = (line: string) => {
      try {
        const d = JSON.parse(line);
        if (isMap(d) && d.action === 'error') sink.onError(String(d.message ?? 'the stream failed'));
        else sink.onFrame(d);
      } catch {
        // A bad line is skipped; the stream keeps going.
        platform().log('debug', `ElpianServerClient: ${this.appId} dropped an unparseable stream line`);
      }
    };
    const cancelStream = fetchStream(
      { url: `${this.baseUrl}/apps/${encodeURIComponent(this.appId)}/stream/${encodeURIComponent(name)}`, method: 'POST', headers: this.headers(), body: JSON.stringify(args), timeoutMs: this.timeoutMs },
      {
        onChunk: (text) => {
          // Chunk boundaries fall anywhere, including mid-line.
          buffer += text;
          let i: number;
          while ((i = buffer.indexOf('\n')) >= 0) {
            const line = buffer.substring(0, i).trim();
            buffer = buffer.substring(i + 1);
            if (line) emit(line);
          }
        },
        onDone: () => {
          const tail = buffer.trim();
          if (tail) emit(tail);
          finish();
        },
        onError: (m) => {
          sink.onError(/time/i.test(m) ? 'the stream timed out' : /status|HTTP/i.test(m) ? 'the stream could not be opened' : 'the stream failed');
          finish();
        },
      },
    );
    const cancel = () => {
      cancelStream();
      finish();
    };
    this.cancels.add(cancel);
    return cancel;
  }

  /** Show a streamed component on a surface (ElpianStreamWidget over streamComponent). */
  mountStream(surfaceId: string, name: string, args: JsonMap, options: StreamSessionOptions = {}): StreamSession {
    const session = new StreamSession(surfaceId, options);
    const cancel = this.streamComponent(name, args, { onFrame: (f) => session.push(f), onError: (m) => session.error(m), onDone: () => session.done() });
    const dispose = session.dispose.bind(session);
    session.dispose = () => {
      cancel();
      dispose();
    };
    return session;
  }

  close(): void {
    this.closed = true;
    for (const c of [...this.cancels]) c();
  }
}

function positional(payload: string): any[] {
  try {
    const d = JSON.parse(payload);
    return Array.isArray(d) ? d : [d];
  } catch {
    return [];
  }
}

function errorMessage(body: string): string | null {
  try {
    const d = JSON.parse(body);
    if (isMap(d) && typeof d.error === 'string') return d.error;
  } catch {
    /* ignore */
  }
  return null;
}

function typedError(message: string): string {
  return JSON.stringify({ error: { code: 'unavailable', message } });
}

// ============================================================================
// ServerComponent
// ============================================================================

/** Builds an island from its props; server-rendered children arrive as `#children`. */
export type IslandBuilder = (props: JsonMap & { '#children'?: W[] }) => W;

export interface ServerComponentOptions {
  client: ElpianServerClient;
  name: string;
  args?: JsonMap;
  /** Lowering-function islands. */
  islandBuilders?: Record<string, IslandBuilder>;
  /** Islands rendered by host-registered native components, by island name → component name. */
  nativeIslands?: Record<string, string>;
  /** Re-fetch interval (ms). */
  revalidateMs?: number | null;
  pending?: W | null;
  errorBuilder?: (message: string) => W;
  surface?: SurfaceOptions;
}

export class ServerComponentSession {
  readonly surface: ElpianSurface;
  private payload: JsonMap | null = null;
  private error: string | null = null;
  private loading = true;
  private generation = 0;
  private timer: number | null = null;
  private disposed = false;
  private stylesheetKey: string | null = null;

  constructor(
    surfaceId: string,
    private options: ServerComponentOptions,
  ) {
    this.surface = new ElpianSurface(surfaceId, options.surface);
    this.registerIslands();
    void this.fetch();
    this.scheduleRevalidation();
  }

  private registerIslands(): void {
    const engine = this.surface.engine;
    for (const [name, build] of Object.entries(this.options.islandBuilders ?? {})) {
      const builder: WidgetBuilder = (node, children) => build({ ...node.props, ...(children.length ? { '#children': children } : {}) });
      engine.registerWidget(name, builder);
    }
    for (const [name, component] of Object.entries(this.options.nativeIslands ?? {})) {
      engine.registerWidget(name, (node, children) =>
        w('native', { component, componentProps: { ...node.props }, width: node.style?.width ?? null, height: node.style?.height ?? null, onEvent: () => {} }, children),
      );
    }
  }

  /** Change name/args/revalidation (didUpdateWidget). */
  update(next: Partial<Omit<ServerComponentOptions, 'client' | 'surface'>>): void {
    const prev = this.options;
    this.options = { ...prev, ...next };
    this.registerIslands();
    if ((next.name != null && next.name !== prev.name) || (next.args != null && !sameArgs(prev.args ?? {}, next.args))) void this.fetch();
    if (next.revalidateMs !== undefined && next.revalidateMs !== prev.revalidateMs) this.scheduleRevalidation();
  }

  private scheduleRevalidation(): void {
    if (this.timer != null) platform().clearTimeout(this.timer);
    this.timer = null;
    const interval = this.options.revalidateMs;
    if (!interval || interval <= 0) return;
    const tick = () => {
      if (this.disposed) return;
      this.timer = platform().setTimeout(tick, interval);
      void this.fetch();
    };
    this.timer = platform().setTimeout(tick, interval);
  }

  async fetch(): Promise<void> {
    const gen = ++this.generation;
    // Only the first fetch shows the pending state; revalidation keeps the screen.
    if (this.payload == null) {
      this.loading = true;
      this.paint();
    }
    const result = await this.options.client.renderComponent(this.options.name, this.options.args ?? {});
    if (this.disposed || gen !== this.generation) return;
    this.loading = false;
    if (result.error != null) this.error = result.error;
    // A failed revalidation keeps content that is already showing.
    else {
      this.error = null;
      this.payload = result.payload ?? null;
    }
    this.paint();
  }

  /** Islands the payload declares that no builder handles. */
  unresolvedIslands(): string[] {
    const declared = this.payload?.clientComponents;
    if (!isMap(declared)) return [];
    return Object.keys(declared).filter((k) => !(k in (this.options.islandBuilders ?? {})) && !(k in (this.options.nativeIslands ?? {})));
  }

  private paint(): void {
    if (this.disposed) return;
    const s = this.surface;
    const errorBox = (m: string) => this.options.errorBuilder?.(m) ?? w('padding', { padding: { top: 12, right: 12, bottom: 12, left: 12 } }, w('text', { text: m, style: { color: 0xffb3261e } }));
    const payload = this.payload;
    if (!payload) {
      if (this.error != null) s.setOverlay(errorBox(this.error));
      else if (this.loading) s.setOverlay(this.options.pending ?? loadingIndicator());
      else s.setContent(null);
      return;
    }
    if (!isMap(payload.component)) {
      s.setOverlay(errorBox('the server component returned no component tree'));
      return;
    }
    if (isMap(payload.stylesheet)) {
      const key = stableKey(payload.stylesheet);
      if (key !== this.stylesheetKey) {
        this.stylesheetKey = key;
        s.engine.loadStylesheet(payload.stylesheet);
      }
    }
    s.setContent(payload.component);
  }

  dispose(): void {
    this.disposed = true;
    if (this.timer != null) platform().clearTimeout(this.timer);
    this.surface.dispose();
  }
}

function sameArgs(a: JsonMap, b: JsonMap): boolean {
  const ka = Object.keys(a);
  if (ka.length !== Object.keys(b).length) return false;
  return ka.every((k) => b[k] === a[k]);
}
