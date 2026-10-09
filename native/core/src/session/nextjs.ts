/**
 * A server-driven page — the port of `NextjsServerWidget`, `NextjsBridge`'s
 * envelope handling, `NextjsAuthConfig` / token stores and
 * `ClientCompRouting` (flutter/lib/src/integrations/*.dart).
 *
 * It loads render envelopes from a Next.js (or any Elpian-speaking) server,
 * keeps the previous screen painted while the next route loads, resolves
 * `clientComp` nodes onto persistent QuickJS VMs (each re-rendering only its
 * own scope), runs page scripts (`jsCode` / `vmAstJson`), routes UI events to
 * the right VM, handles `NextjsLink` / `NextjsForm` navigation and
 * submission, server navigation directives, auth token capture, refresh and
 * retry, and the `fetch` / `submit` / `navigate` / `mountFragment` host APIs.
 */
import { M3 } from '../css/color.js';
import type { ElpianEvent } from '../events/events.js';
import { HostHandler } from '../host/host-handler.js';
import { VmTimerHostApi } from '../host/timers.js';
import { platform, type FetchRequest } from '../platform/platform.js';
import { w } from '../render/object.js';
import { ScopeContract, ScopePatch } from '../scope/scope.js';
import { isMap, stableKey, type JsonMap } from '../util/json.js';
import { allHostApiNames, timerApiNames } from '../vm/host-api-catalog.js';
import { ElpianVm, QuickJsVm, type HostCallHandler, type VmRuntimeClient } from '../vm/runtime.js';
import { ElpianSurface, loadingIndicator, type SurfaceOptions } from './surface.js';

// ============================================================================
// Envelope
// ============================================================================

export interface NextjsRenderEnvelope {
  component: JsonMap;
  stylesheet?: JsonMap | null;
  meta?: JsonMap | null;
  navigation?: JsonMap | null;
  clientComponents?: JsonMap | null;
  jsCode?: string | null;
  vmAstJson?: string | null;
  jsEntryFunction?: string | null;
}

export function envelopeFromJson(json: JsonMap): NextjsRenderEnvelope {
  if (!isMap(json.component)) throw new Error('Next.js payload must contain a "component" object that matches Elpian JSON.');
  const obj = (k: string) => {
    const v = json[k];
    if (v != null && !isMap(v)) throw new Error(`"${k}" must be a JSON object when provided.`);
    return (v as JsonMap) ?? null;
  };
  const str = (k: string) => {
    const v = json[k];
    if (v != null && typeof v !== 'string') throw new Error(`"${k}" must be a string when provided.`);
    return (v as string) ?? null;
  };
  return {
    component: json.component,
    stylesheet: obj('stylesheet'),
    meta: obj('meta'),
    navigation: obj('navigation'),
    clientComponents: obj('clientComponents'),
    jsCode: str('jsCode'),
    vmAstJson: str('vmAstJson'),
    jsEntryFunction: str('jsEntryFunction'),
  };
}

export function buildRouteRequest(route: string, props?: JsonMap | null, context?: JsonMap | null): JsonMap {
  return { route, ...(props ? { props } : {}), ...(context ? { context } : {}) };
}

// ============================================================================
// Auth
// ============================================================================

export interface NextjsTokenStore {
  readonly accessToken: string | null;
  readonly refreshToken: string | null;
  readonly hasSession: boolean;
  ensureReady(): Promise<void>;
  save(tokens: { access?: string | null; refresh?: string | null }): void;
  clear(): void;
}

export class InMemoryTokenStore implements NextjsTokenStore {
  private access: string | null = null;
  private refresh: string | null = null;
  get accessToken() {
    return this.access;
  }
  get refreshToken() {
    return this.refresh;
  }
  get hasSession() {
    return !!this.access;
  }
  async ensureReady(): Promise<void> {}
  save(t: { access?: string | null; refresh?: string | null }): void {
    if (t.access != null) this.access = t.access;
    if (t.refresh != null) this.refresh = t.refresh;
  }
  clear(): void {
    this.access = null;
    this.refresh = null;
  }
}

/** Persisted through the platform's key-value storage (SharedPreferences / UserDefaults / localStorage). */
export class PlatformTokenStore implements NextjsTokenStore {
  private access: string | null = null;
  private refresh: string | null = null;
  private ready: Promise<void> | null = null;
  constructor(readonly namespace = 'elpian') {}
  private get accessKey() {
    return `${this.namespace}_access_token`;
  }
  private get refreshKey() {
    return `${this.namespace}_refresh_token`;
  }
  get accessToken() {
    return this.access;
  }
  get refreshToken() {
    return this.refresh;
  }
  get hasSession() {
    return !!this.access;
  }
  ensureReady(): Promise<void> {
    return (this.ready ??= (async () => {
      try {
        const p = platform();
        this.access = p.storageGet?.(this.accessKey) ?? null;
        this.refresh = p.storageGet?.(this.refreshKey) ?? null;
      } catch {
        // Persistence unavailable: degrade to in-memory.
      }
    })());
  }
  save(t: { access?: string | null; refresh?: string | null }): void {
    const p = platform();
    if (t.access != null) {
      this.access = t.access;
      p.storageSet?.(this.accessKey, t.access);
    }
    if (t.refresh != null) {
      this.refresh = t.refresh;
      p.storageSet?.(this.refreshKey, t.refresh);
    }
  }
  clear(): void {
    const p = platform();
    this.access = null;
    this.refresh = null;
    p.storageSet?.(this.accessKey, null);
    p.storageSet?.(this.refreshKey, null);
  }
}

export interface NextjsAuthConfig {
  store: NextjsTokenStore;
  loginRoute: string;
  refreshRoute: string;
  bearerScheme: string;
}

export function nextjsAuthConfig(c: Partial<NextjsAuthConfig> = {}): NextjsAuthConfig {
  return { store: c.store ?? new PlatformTokenStore(), loginRoute: c.loginRoute ?? '/auth', refreshRoute: c.refreshRoute ?? '/auth/refresh', bearerScheme: c.bearerScheme ?? 'Bearer' };
}

// ============================================================================
// Client-component handler routing
// ============================================================================

export const ClientCompRouting = {
  separator: '::',
  namespaced(mountId: string, fn: string): string {
    return `${mountId}::${fn}`;
  },
  parse(handler: string): { mountId: string; fn: string } | null {
    const idx = handler.indexOf('::');
    if (idx <= 0) return null;
    return { mountId: handler.substring(0, idx), fn: handler.substring(idx + 2) };
  },
  /** Prefix every un-namespaced handler in [node] with [mountId] (in place). */
  namespaceHandlers(node: JsonMap, mountId: string): JsonMap {
    if (isMap(node.events)) {
      const ns: JsonMap = {};
      for (const [k, v] of Object.entries(node.events)) ns[k] = typeof v === 'string' && v && !v.includes('::') ? ClientCompRouting.namespaced(mountId, v) : v;
      node.events = ns;
    }
    if (Array.isArray(node.children)) for (const c of node.children) if (isMap(c)) ClientCompRouting.namespaceHandlers(c, mountId);
    return node;
  },
};

// ============================================================================
// Session
// ============================================================================

export type NextjsPayloadLoader = (route: string, opts: { props?: JsonMap | null; headers?: Record<string, string> | null }) => Promise<JsonMap>;

export interface NextjsSessionOptions {
  route: string;
  serverBaseUrl?: string | null;
  endpoint?: string | null;
  requestMode?: 'routePath' | 'apiEndpoint';
  loader?: NextjsPayloadLoader | null;
  props?: JsonMap | null;
  headers?: Record<string, string> | null;
  auth?: NextjsAuthConfig | null;
  timeoutMs?: number;
  onScriptExecuted?(result: { route: string; kind: 'js' | 'vmAst'; output: string }): void;
  onScriptError?(error: unknown): void;
  /** The route changed (for host back-stack / URL sync). */
  onRouteChanged?(route: string): void;
  /** A tap on a clickable Scene3D node not handled by the page VM. */
  onSceneTap?(props: JsonMap): void;
  surface?: SurfaceOptions;
}

interface LiveClientComp {
  mountId: string;
  vm: VmRuntimeClient;
  style: JsonMap | null;
  timer: VmTimerHostApi | null;
  latest: JsonMap | null;
  dirty: boolean;
}

const HOST_OK = '{"type":"i16","data":{"value":1}}';

export class NextjsSession {
  readonly surface: ElpianSurface;
  private currentRoute: string;
  private readonly history: string[] = [];
  private lastScriptSignature: string | null = null;
  private scriptRendered: JsonMap | null = null;
  private lastEnvelopeComponent: JsonMap | null = null;
  private previousComponent: JsonMap | null = null;
  private readonly clientComponentCache = new Map<string, JsonMap>();
  private pageVm: VmRuntimeClient | null = null;
  private pageTimers: VmTimerHostApi | null = null;
  private readonly liveComps = new Map<string, LiveClientComp>();
  private compSeq = 0;
  private loadGeneration = 0;
  private payload: JsonMap | null = null;
  private loadError: unknown = null;
  private loading = true;
  private lastStylesheetKey: string | null = null;
  private disposed = false;

  constructor(
    surfaceId: string,
    readonly options: NextjsSessionOptions,
  ) {
    if (!options.loader && !options.serverBaseUrl) throw new Error('Either provide loader or serverBaseUrl for automatic Next.js loading.');
    this.currentRoute = options.route;
    // Server-relative resources ("/icons/x.png") resolve against the server ORIGIN.
    const origin = originOf(options.serverBaseUrl ?? null);
    this.surface = new ElpianSurface(surfaceId, {
      ...(options.surface ?? {}),
      document: true,
      host: {
        ...(options.surface?.host ?? {}),
        navigate: (href, replace) => this.navigate(href, replace),
        submitForm: (action, values) => this.handleFormSubmit(action, values),
        sceneTap: (props) => void this.dispatchSceneTap(props),
        baseUrl: () => options.surface?.host?.baseUrl?.() ?? origin,
      },
    });
    this.surface.engine.services.events.onGlobalEvent((e) => void this.routeEvent(e));
    void this.load();
  }

  get route(): string {
    return this.currentRoute;
  }
  get canGoBack(): boolean {
    return this.history.length > 0;
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  navigate(route: string, replace = false): void {
    if (this.currentRoute === route && !replace) return;
    void this.disposePageVm();
    if (!replace) this.history.push(this.currentRoute);
    this.currentRoute = route;
    this.beginReload();
  }

  back(): boolean {
    if (!this.history.length) return false;
    void this.disposePageVm();
    this.currentRoute = this.history.pop()!;
    this.beginReload();
    return true;
  }

  refresh(): void {
    void this.disposePageVm();
    this.beginReload();
  }

  private beginReload(): void {
    // Keep the screen just rendered as the loading backdrop.
    this.previousComponent = this.scriptRendered ?? this.lastEnvelopeComponent ?? this.previousComponent;
    this.scriptRendered = null;
    this.lastEnvelopeComponent = null;
    this.lastScriptSignature = null;
    this.options.onRouteChanged?.(this.currentRoute);
    void this.load();
  }

  private applyServerNavigation(nav: JsonMap | null | undefined): void {
    if (!nav || !Object.keys(nav).length) return;
    if (nav.back === true) {
      microtask(() => this.back());
      return;
    }
    if (nav.refresh === true) {
      microtask(() => this.refresh());
      return;
    }
    const to = nav.redirectTo != null ? String(nav.redirectTo) : '';
    if (to) {
      const replace = nav.replace === true;
      if (to !== this.currentRoute || replace) microtask(() => this.navigate(to, replace));
    }
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  private async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    this.loading = true;
    this.loadError = null;
    this.paint();
    try {
      const payload = await this.loadPayload();
      if (generation !== this.loadGeneration || this.disposed) return;
      this.payload = payload;
      this.loading = false;
      this.onPayload();
    } catch (e) {
      if (generation !== this.loadGeneration || this.disposed) return;
      this.loading = false;
      this.loadError = e;
      this.paint();
    }
  }

  private async loadPayload(): Promise<JsonMap> {
    await this.disposeClientComps();
    this.compSeq = 0;
    await this.options.auth?.store.ensureReady();
    const loader = this.options.loader ?? ((r, o) => this.httpLoader(r, o));
    let payload = await loader(this.currentRoute, { props: this.options.props, headers: this.options.headers });
    this.captureAuth(payload);
    const auth = this.options.auth;
    if (auth && !this.options.loader) {
      const nav = payload.navigation;
      if (isMap(nav) && String(nav.redirectTo ?? '') === auth.loginRoute && auth.store.refreshToken) {
        if (await this.tryRefresh()) {
          payload = await this.httpLoader(this.currentRoute, { props: this.options.props, headers: this.options.headers });
          this.captureAuth(payload);
        }
      }
    }
    const envelope = envelopeFromJson(payload);
    const component = await this.resolveClientComponentNodes(envelope.component, envelope.clientComponents ?? null);
    return { ...payload, component };
  }

  private onPayload(): void {
    const payload = this.payload;
    if (!payload) return;
    let envelope: NextjsRenderEnvelope;
    try {
      envelope = envelopeFromJson(payload);
    } catch (e) {
      this.loadError = e;
      this.paint();
      return;
    }
    this.lastEnvelopeComponent = envelope.component;
    this.triggerScriptExecution(envelope);
    this.applyServerNavigation(envelope.navigation);
    if (envelope.stylesheet) {
      const key = stableKey(envelope.stylesheet);
      if (key !== this.lastStylesheetKey) {
        this.lastStylesheetKey = key;
        this.surface.engine.loadStylesheet(envelope.stylesheet);
      }
    }
    this.paint();
  }

  /** Put the current state on the surface (FutureBuilder.build). */
  private paint(): void {
    if (this.disposed) return;
    const s = this.surface;
    if (this.loading) {
      const fallback = this.previousComponent;
      if (fallback) {
        // The previous screen with a thin progress bar on top.
        s.decorate = (content) =>
          w('stack', { fit: 'loose' }, [
            content,
            w('positioned', { top: 0, left: 0, right: 0 }, w('control', { kind: 'progress', view: { variant: 'linear', value: null, strokeWidth: 2, colors: { indicator: M3.primary, track: M3.secondaryContainer } } })),
          ]);
        s.setContent(fallback);
      } else {
        s.decorate = null;
        s.setOverlay(loadingIndicator());
      }
      return;
    }
    s.decorate = null;
    if (this.loadError != null) {
      s.setOverlay(
        w('align', { alignment: { x: 0, y: 0 } }, w('text', { text: `Next.js payload error on "${this.currentRoute}": ${errorText(this.loadError)}`, align: 'center' })),
      );
      return;
    }
    if (!this.payload) {
      s.setOverlay(w('align', { alignment: { x: 0, y: 0 } }, w('text', { text: 'Next.js payload was empty.' })));
      return;
    }
    this.foldClientCompRenders();
    s.setContent(this.scriptRendered ?? this.lastEnvelopeComponent);
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  private buildUrl(route: string): string {
    const base = (this.options.serverBaseUrl ?? '').replace(/\/+$/, '');
    if (route.startsWith('http://') || route.startsWith('https://')) return route;
    if (!route || route === '/') return base;
    return `${base}${route.startsWith('/') ? route : `/${route}`}`;
  }

  private authHeaders(): Record<string, string> {
    const a = this.options.auth;
    const t = a?.store.accessToken;
    return t ? { authorization: `${a!.bearerScheme} ${t}` } : {};
  }

  private async request(req: FetchRequest): Promise<{ status: number; body: string }> {
    const fetch = platform().fetch;
    if (!fetch) throw new Error('This platform provides no HTTP client.');
    return fetch({ timeoutMs: this.options.timeoutMs ?? 120000, ...req });
  }

  private async httpLoader(route: string, o: { props?: JsonMap | null; headers?: Record<string, string> | null }): Promise<JsonMap> {
    if (!this.options.serverBaseUrl) throw new Error('serverBaseUrl is required when no custom loader is provided.');
    if ((this.options.requestMode ?? 'routePath') === 'routePath') {
      const url = this.buildUrl(route);
      const res = await this.request({
        url,
        method: 'GET',
        headers: {
          accept: 'application/vnd.elpian+json, application/json',
          'x-elpian-route': route,
          ...(o.props && Object.keys(o.props).length ? { 'x-elpian-props': JSON.stringify(o.props) } : {}),
          ...this.authHeaders(),
          ...(o.headers ?? {}),
        },
      });
      if (res.status < 200 || res.status >= 300) throw new Error(`Next.js route ${url} returned HTTP ${res.status}: ${res.body}`);
      const decoded = JSON.parse(res.body);
      if (!isMap(decoded)) throw new Error('Next.js route response must decode to a JSON object.');
      return decoded;
    }
    const url = this.buildUrl(this.options.endpoint ?? '/api/elpian-render');
    const res = await this.request({
      url,
      method: 'POST',
      headers: { 'content-type': 'application/json', ...this.authHeaders(), ...(o.headers ?? {}) },
      body: JSON.stringify(buildRouteRequest(route, o.props)),
    });
    if (res.status < 200 || res.status >= 300) throw new Error(`Next.js endpoint ${url} returned HTTP ${res.status}: ${res.body}`);
    const decoded = JSON.parse(res.body);
    if (!isMap(decoded)) throw new Error('Next.js payload must decode to a JSON object.');
    return decoded;
  }

  private async postJson(route: string, body: unknown): Promise<JsonMap> {
    const res = await this.request({
      url: this.buildUrl(route),
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/vnd.elpian+json, application/json',
        'x-elpian-route': route,
        ...this.authHeaders(),
        ...(this.options.headers ?? {}),
      },
      body: JSON.stringify(body ?? null),
    });
    const decoded = JSON.parse(res.body);
    if (!isMap(decoded)) throw new Error('Action response must decode to a JSON object.');
    return decoded;
  }

  private captureAuth(envelope: JsonMap): void {
    const a = this.options.auth;
    if (!a || !isMap(envelope.meta)) return;
    const meta = envelope.meta;
    if (meta.clearAuth === true) {
      a.store.clear();
      return;
    }
    if ('auth' in meta) {
      if (isMap(meta.auth)) a.store.save({ access: meta.auth.accessToken != null ? String(meta.auth.accessToken) : null, refresh: meta.auth.refreshToken != null ? String(meta.auth.refreshToken) : null });
      else if (meta.auth == null) a.store.clear();
    }
  }

  private async tryRefresh(): Promise<boolean> {
    const a = this.options.auth;
    const rt = a?.store.refreshToken;
    if (!a || !rt) return false;
    try {
      const env = await this.postJson(a.refreshRoute, { refreshToken: rt });
      const auth = isMap(env.meta) ? env.meta.auth : null;
      if (isMap(auth) && auth.accessToken != null) {
        a.store.save({ access: String(auth.accessToken), refresh: auth.refreshToken != null ? String(auth.refreshToken) : null });
        return true;
      }
    } catch {
      /* fall through */
    }
    a.store.clear();
    return false;
  }

  private async handleFormSubmit(action: string, values: Record<string, any>): Promise<string | null> {
    try {
      const env = await this.postJson(action, values);
      this.captureAuth(env);
      if (isMap(env.navigation) && Object.keys(env.navigation).length) {
        this.applyServerNavigation(env.navigation);
        return null;
      }
      const inline = firstText(env.component);
      if (inline != null) return inline;
      if (isMap(env.component)) this.setScriptRendered(env.component);
      return null;
    } catch (e) {
      return `Request failed: ${errorText(e)}`;
    }
  }

  // ---------------------------------------------------------------------------
  // Client components
  // ---------------------------------------------------------------------------

  private async resolveClientComponentNodes(node: JsonMap, packed: JsonMap | null): Promise<JsonMap> {
    const type = String(node.type ?? '');
    if (type === 'clientComp' || type === 'client-component') {
      return (await this.resolveClientComponentNode(node, packed)) ?? { type: 'Text', props: { text: 'Failed to execute client component jsCode' } };
    }
    if (Array.isArray(node.children)) {
      const children: unknown[] = [];
      for (const c of node.children) children.push(isMap(c) ? await this.resolveClientComponentNodes(c, packed) : c);
      return { ...node, children };
    }
    return node;
  }

  private async resolveClientComponentNode(node: JsonMap, packed: JsonMap | null): Promise<JsonMap | null> {
    const props: JsonMap = isMap(node.props) ? { ...node.props } : {};
    let jsCode: string | null = node.jsCode != null ? String(node.jsCode) : props.jsCode != null ? String(props.jsCode) : null;
    let entry = String(node.jsEntryFunction ?? props.jsEntryFunction ?? 'MainComponent');
    if (!jsCode) {
      const p = this.findPackedScript(node, props, packed);
      jsCode = p?.jsCode ?? null;
      entry = p?.jsEntryFunction ?? entry;
    }
    if (!jsCode && this.options.serverBaseUrl) {
      const f = await this.fetchClientComponentScript(node, props);
      jsCode = f?.jsCode ?? null;
      entry = f?.jsEntryFunction ?? entry;
    }
    if (!jsCode) return null;
    return this.mountClientComponent(jsCode, entry, props, node.style);
  }

  private async mountClientComponent(jsCode: string, entryFunction: string, props: JsonMap, style: unknown): Promise<JsonMap | null> {
    const mountId = `cc${this.compSeq++}`;
    const machineId = `nextjs-${mountId}-${Date.now()}${Math.floor(Math.random() * 1000)}`;
    let vm: QuickJsVm;
    try {
      vm = await QuickJsVm.fromCode(machineId, jsCode);
    } catch (e) {
      platform().log('warn', `NextjsSession: clientComp "${mountId}" create failed: ${e}`);
      return null;
    }
    const record: LiveClientComp = { mountId, vm, style: isMap(style) ? style : null, timer: null, latest: null, dirty: false };
    this.liveComps.set(mountId, record);

    let resolveFirst: () => void = () => {};
    let firstDone = false;
    const firstRender = new Promise<void>((r) => (resolveFirst = r));
    const handler = new HostHandler(this.surface.engine.services, {
      onRender: (view) => {
        record.latest = ClientCompRouting.namespaceHandlers(view, mountId);
        if (!firstDone) {
          firstDone = true;
          resolveFirst();
        } else {
          record.dirty = true;
          this.paint();
        }
      },
      onPrintln: (m) => platform().log('info', `NextjsSession[${mountId}]: ${m}`),
    });
    record.timer = new VmTimerHostApi(
      async (fn, input) => {
        if (input == null) await vm.callFunction(fn);
        else await vm.callFunctionWithInput(fn, input);
      },
      (m) => platform().log('warn', `NextjsSession[${mountId} timer]: ${m}`),
    );
    vm.registerHostHandlers(this.hostHandlers(handler, record.timer, () => record.vm));
    try {
      await vm.run();
      await vm.callFunctionWithInput(entryFunction, JSON.stringify(props));
      let timeout: number | null = null;
      await Promise.race([
        firstRender,
        new Promise<void>((r) => {
          timeout = platform().setTimeout(() => {
            platform().log('warn', `NextjsSession: clientComp "${mountId}" first render timed out`);
            r();
          }, 3000);
        }),
      ]);
      if (timeout != null) platform().clearTimeout(timeout);
    } catch (e) {
      platform().log('warn', `NextjsSession: clientComp "${mountId}" exec failed: ${e}`);
      this.liveComps.delete(mountId);
      await disposeComp(record);
      return null;
    }
    record.dirty = false;
    return { type: ScopeContract.type, key: `${mountId}__scope`, props: {}, children: [this.compContent(record)] };
  }

  private compContent(record: LiveClientComp): JsonMap {
    const node: JsonMap = { ...(record.latest ?? { type: 'div' }), key: record.mountId };
    if (record.style) node.style = isMap(node.style) ? { ...record.style, ...node.style } : record.style;
    return node;
  }

  private foldClientCompRenders(): void {
    if (!this.liveComps.size) return;
    const tree = this.scriptRendered ?? this.lastEnvelopeComponent;
    if (!tree) return;
    let any = false;
    for (const r of this.liveComps.values()) {
      if (!r.dirty || !r.latest) continue;
      if (ScopePatch.replaceByKey(tree, r.mountId, this.compContent(r))) {
        r.dirty = false;
        any = true;
      }
    }
    if (any) this.scriptRendered = tree;
  }

  private async disposeClientComps(): Promise<void> {
    const comps = [...this.liveComps.values()];
    this.liveComps.clear();
    for (const c of comps) await disposeComp(c);
  }

  private findPackedScript(node: JsonMap, props: JsonMap, packed: JsonMap | null): { jsCode: string; jsEntryFunction: string } | null {
    if (!packed || !Object.keys(packed).length) return null;
    for (const key of lookupKeys(node, props)) {
      const p = normalizePacked(packed[key]);
      if (p) return p;
    }
    const values = Object.values(packed);
    return values.length === 1 ? normalizePacked(values[0]) : null;
  }

  private async fetchClientComponentScript(node: JsonMap, props: JsonMap): Promise<{ jsCode: string; jsEntryFunction: string } | null> {
    const keys = lookupKeys(node, props);
    for (const k of keys) {
      const c = this.clientComponentCache.get(k);
      const p = c ? normalizePacked(c) : null;
      if (p) return p;
    }
    try {
      const res = await this.request({
        url: this.buildUrl(this.options.endpoint ?? '/api/elpian-client-component'),
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'application/json', ...this.authHeaders(), ...(this.options.headers ?? {}) },
        body: JSON.stringify({ route: this.currentRoute, lookupKeys: keys, componentNode: node }),
      });
      if (res.status < 200 || res.status >= 300) return null;
      const decoded = JSON.parse(res.body);
      if (!isMap(decoded)) return null;
      if (isMap(decoded.clientComponents)) {
        for (const [k, v] of Object.entries(decoded.clientComponents)) {
          if (isMap(v)) this.clientComponentCache.set(k, { ...v });
          else if (typeof v === 'string') this.clientComponentCache.set(k, { jsCode: v });
        }
      }
      const direct = normalizePacked(decoded);
      if (direct) {
        for (const k of keys) this.clientComponentCache.set(k, { ...direct });
        return direct;
      }
      for (const k of keys) {
        const c = this.clientComponentCache.get(k);
        const p = c ? normalizePacked(c) : null;
        if (p) return p;
      }
    } catch {
      /* resolved inline or not at all */
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Page scripts
  // ---------------------------------------------------------------------------

  private triggerScriptExecution(envelope: NextjsRenderEnvelope): void {
    if (!envelope.jsCode && !envelope.vmAstJson) return;
    const signature = `${this.currentRoute}|${envelope.jsEntryFunction ?? 'MainComponent'}|${envelope.jsCode ?? ''}|${envelope.vmAstJson ?? ''}`;
    if (this.lastScriptSignature === signature) return;
    this.lastScriptSignature = signature;
    void this.executeEnvelopeScripts(envelope);
  }

  private async executeEnvelopeScripts(envelope: NextjsRenderEnvelope): Promise<void> {
    try {
      if (envelope.jsCode) await this.runPageScript(envelope.jsCode, envelope.jsEntryFunction ?? 'MainComponent');
      if (envelope.vmAstJson) {
        await ElpianVm.initialize();
        const vm = await ElpianVm.fromAst(`nextjs-ast-${Date.now()}`, envelope.vmAstJson);
        if (!vm) throw new Error('Failed to create Elpian VM from AST payload.');
        vm.registerHostHandler('render', (_api, payload) => {
          this.setScriptRendered(decodeRenderPayload(payload));
          return HOST_OK;
        });
        try {
          const output = await vm.run();
          this.setScriptRendered(decodeRenderPayload(output));
          this.options.onScriptExecuted?.({ route: this.currentRoute, kind: 'vmAst', output });
        } finally {
          await vm.dispose();
        }
      }
    } catch (e) {
      this.options.onScriptError?.(e);
      platform().log('warn', `NextjsSession script execution error: ${e}`);
    }
  }

  private async runPageScript(jsCode: string, entryFunction: string): Promise<void> {
    await this.disposePageVm();
    const vm = await QuickJsVm.fromCode(`nextjs-page-${Date.now()}`, jsCode);
    this.pageVm = vm;
    const handler = new HostHandler(this.surface.engine.services, {
      onRender: (view, scopeKey) => this.applyClientRender(view, scopeKey),
      onPrintln: (m) => platform().log('info', `NextjsSession[page]: ${m}`),
    });
    this.pageTimers = new VmTimerHostApi(
      async (fn, input) => {
        if (!this.pageVm) return;
        if (input == null) await vm.callFunction(fn);
        else await vm.callFunctionWithInput(fn, input);
      },
      (m) => platform().log('warn', `NextjsSession[page timer]: ${m}`),
    );
    vm.registerHostHandlers(this.hostHandlers(handler, this.pageTimers, () => this.pageVm));
    await vm.run();
    if (entryFunction) {
      const initial = await vm.callFunction(entryFunction);
      // Only a returned component tree seeds the render (pollers return null).
      const seeded = decodeRenderPayload(initial);
      if (seeded && seeded.type != null && this.scriptRendered == null) this.setScriptRendered(seeded);
    }
    this.options.onScriptExecuted?.({ route: this.currentRoute, kind: 'js', output: '' });
  }

  private hostHandlers(handler: HostHandler, timers: VmTimerHostApi, vm: () => VmRuntimeClient | null): Record<string, HostCallHandler> {
    const out: Record<string, HostCallHandler> = {};
    for (const api of allHostApiNames) out[api] = (n, p) => handler.handleHostCall(n, p);
    for (const api of timerApiNames) out[api] = (n, p) => timers.handle(n, p);
    // Async work is started and acknowledged at once: guests call askHost
    // synchronously and receive results through their onData/onResult callbacks.
    out.fetch = (_n, p) => {
      void this.hostFetch(vm(), p);
      return HOST_OK;
    };
    out.submit = (_n, p) => {
      void this.hostSubmit(vm(), p);
      return HOST_OK;
    };
    out.navigate = (_n, p) => this.hostNavigate(p);
    out.mountFragment = (_n, p) => {
      void this.hostMountFragment(vm(), p);
      return HOST_OK;
    };
    return out;
  }

  private async hostFetch(vm: VmRuntimeClient | null, payload: string): Promise<void> {
    try {
      const args = firstArgMap(payload);
      const route = args.route != null ? String(args.route) : '';
      if (!route) return;
      const loader = this.options.loader ?? ((r, o) => this.httpLoader(r, o));
      const envelope = await loader(route, { headers: this.options.headers });
      const onData = args.onData != null ? String(args.onData) : '';
      if (onData && vm) await vm.callFunctionWithInput(onData, JSON.stringify(envelope));
    } catch (e) {
      platform().log('warn', `NextjsSession[fetch]: ${e}`);
    }
  }

  private async hostSubmit(vm: VmRuntimeClient | null, payload: string): Promise<void> {
    try {
      const args = firstArgMap(payload);
      const route = args.route != null ? String(args.route) : '';
      if (!route) return;
      const env = await this.postJson(route, args.body);
      this.captureAuth(env);
      if (isMap(env.navigation) && Object.keys(env.navigation).length) this.applyServerNavigation(env.navigation);
      const onResult = args.onResult != null ? String(args.onResult) : '';
      if (onResult && vm) await vm.callFunctionWithInput(onResult, JSON.stringify(env));
    } catch (e) {
      platform().log('warn', `NextjsSession[submit]: ${e}`);
    }
  }

  private async hostMountFragment(vm: VmRuntimeClient | null, payload: string): Promise<void> {
    try {
      const args = firstArgMap(payload);
      const route = args.route != null ? String(args.route) : '';
      if (!route) return;
      const scopeKey = args.scopeKey != null ? String(args.scopeKey) : null;
      const loader = this.options.loader ?? ((r, o) => this.httpLoader(r, o));
      const envelope = await loader(route, { headers: this.options.headers });
      this.captureAuth(envelope);
      if (isMap(envelope.navigation) && Object.keys(envelope.navigation).length) this.applyServerNavigation(envelope.navigation);
      if (isMap(envelope.component)) {
        const resolved = await this.resolveClientComponentNodes(envelope.component, isMap(envelope.clientComponents) ? envelope.clientComponents : null);
        this.applyClientRender(resolved, scopeKey);
      }
      const onData = args.onData != null ? String(args.onData) : '';
      if (onData && vm) await vm.callFunctionWithInput(onData, JSON.stringify(envelope));
    } catch (e) {
      platform().log('warn', `NextjsSession[mountFragment]: ${e}`);
    }
  }

  private hostNavigate(payload: string): string {
    try {
      const nav = firstArgMap(payload);
      if (Object.keys(nav).length) this.applyServerNavigation(nav);
    } catch (e) {
      platform().log('warn', `NextjsSession[page navigate]: ${e}`);
    }
    return HOST_OK;
  }

  private applyClientRender(view: JsonMap, scopeKey: string | null): void {
    if (this.disposed) return;
    const key = ScopePatch.normalizeKey(scopeKey);
    if (key == null) {
      this.setScriptRendered(view);
      return;
    }
    const next = ScopePatch.applyBounded(this.scriptRendered ?? this.lastEnvelopeComponent, view, key);
    if (next == null) {
      platform().log('debug', `NextjsSession: scoped render targeted missing scope "${key}"; keeping current screen.`);
      return;
    }
    this.setScriptRendered(next);
  }

  private setScriptRendered(component: JsonMap | null): void {
    if (!component || this.disposed) return;
    this.scriptRendered = component;
    if (!this.loading) this.paint();
  }

  private async disposePageVm(): Promise<void> {
    this.pageTimers?.dispose();
    this.pageTimers = null;
    const vm = this.pageVm;
    this.pageVm = null;
    if (vm) {
      try {
        await vm.dispose();
      } catch {
        /* best effort */
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  private async routeEvent(event: ElpianEvent): Promise<void> {
    const nodeId = event.currentTarget;
    if (!nodeId) return;
    const handler = this.surface.engine.services.events.getNode(nodeId)?.events?.[event.type];
    if (typeof handler !== 'string' || !handler) return;
    // `<mountId>::<fn>` belongs to a live client component; otherwise the page VM.
    const r = ClientCompRouting.parse(handler);
    const vm = r ? this.liveComps.get(r.mountId)?.vm ?? null : this.pageVm;
    const fn = r?.fn ?? handler;
    if (!vm) return;
    const input: JsonMap = { type: event.type };
    if (event.position) {
      input.x = event.position.x;
      input.y = event.position.y;
    } else if (event.value !== undefined) input.value = event.value;
    try {
      await vm.callFunctionWithInput(fn, JSON.stringify(input));
    } catch {
      try {
        await vm.callFunction(fn);
      } catch (e) {
        platform().log('warn', `NextjsSession: event handler "${handler}" failed: ${e}`);
      }
    }
  }

  private async dispatchSceneTap(props: JsonMap): Promise<void> {
    if (this.options.onSceneTap) {
      this.options.onSceneTap(props);
      return;
    }
    const vm = this.pageVm;
    if (vm) {
      try {
        await vm.callFunctionWithInput('__onSceneTap', JSON.stringify(props));
        return;
      } catch {
        /* fall through to navigation */
      }
    }
    const href = props.panelHref;
    if (typeof href === 'string' && href) this.navigate(href);
  }

  viewportChanged(): void {
    this.surface.viewportChanged();
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    this.loadGeneration++;
    await this.disposePageVm();
    await this.disposeClientComps();
    this.surface.dispose();
  }
}

async function disposeComp(c: LiveClientComp): Promise<void> {
  c.timer?.dispose();
  c.timer = null;
  try {
    await c.vm.dispose();
  } catch {
    /* best effort */
  }
}

function lookupKeys(node: JsonMap, props: JsonMap): string[] {
  const fields = ['clientComponentKey', 'componentKey', 'componentId', 'id', 'name', 'path', 'componentPath', 'module'];
  const keys = new Set<string>();
  for (const src of [node, props]) {
    for (const f of fields) {
      const t = src[f] != null ? String(src[f]).trim() : '';
      if (t) keys.add(t);
    }
  }
  if (!keys.size) keys.add(`anon-${hashString(stableKey(node))}-${hashString(stableKey(props))}`);
  return [...keys];
}

function hashString(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

function normalizePacked(raw: unknown): { jsCode: string; jsEntryFunction: string } | null {
  if (typeof raw === 'string' && raw.trim()) return { jsCode: raw.trim(), jsEntryFunction: 'MainComponent' };
  if (isMap(raw)) {
    const js = raw.jsCode != null ? String(raw.jsCode) : '';
    if (!js.trim()) return null;
    const entry = raw.jsEntryFunction != null ? String(raw.jsEntryFunction) : '';
    return { jsCode: js, jsEntryFunction: entry || 'MainComponent' };
  }
  return null;
}

function decodeRenderPayload(payload: string): JsonMap | null {
  try {
    const d = JSON.parse(payload);
    if (isMap(d)) return isMap(d.component) ? d.component : d;
  } catch {
    /* plain string */
  }
  return null;
}

function firstArgMap(payload: string): JsonMap {
  let parsed: any;
  try {
    parsed = JSON.parse(payload);
  } catch {
    return {};
  }
  if (Array.isArray(parsed) && parsed.length) parsed = parsed[0];
  if (typeof parsed === 'string') {
    try {
      parsed = JSON.parse(parsed);
    } catch {
      return {};
    }
  }
  return isMap(parsed) ? parsed : {};
}

function firstText(node: unknown): string | null {
  if (!isMap(node)) return null;
  if (isMap(node.props) && typeof node.props.text === 'string') {
    const t = node.props.text;
    if (t.trim().length > 2 && !t.includes('✕')) return t;
  }
  if (Array.isArray(node.children)) {
    for (const c of node.children) {
      const r = firstText(c);
      if (r != null) return r;
    }
  }
  return null;
}

function originOf(url: string | null): string | null {
  if (!url) return null;
  const m = /^([a-zA-Z][\w+.-]*:\/\/[^/?#]+)/.exec(url);
  return m ? m[1] : null;
}

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** `scheduleMicrotask` — via a resolved promise (not every embedded engine has `queueMicrotask`). */
function microtask(fn: () => void): void {
  void Promise.resolve().then(fn);
}
