/**
 * One registry of the sessions a host app has open, addressed by surface id
 * and driven by JSON — the API every embedding speaks: the native bridge
 * (`__elpianCore`), the web custom element, and the Expo module.
 *
 * Session kinds:
 *   - `json`      — render Elpian JSON directly (setContent / patch).
 *   - `miniapp`   — a mini app on one of the three runtimes (ElpianVmWidget).
 *   - `superapp`  — a governed third-party mini app (MiniAppHost.launch + mount).
 *   - `stream`    — a view driven by pushed / streamed commands.
 *   - `nextjs`    — a server-driven page (NextjsServerWidget).
 *   - `server`    — a server-rendered component (ServerComponent).
 *
 * Events flow back through the `emit(surface, event, payload)` sink:
 *   ready, error, println, updateApp, routeChanged, scriptExecuted,
 *   scriptError, streamDone, command, sceneTap, callRefused, unservicedApi,
 *   result (async call results: `{requestId, ok, value | error}`).
 */
import { ElpianServerClient, ElpianNetPolicy, ServerComponentSession } from '../fullstack/server.js';
import { platform } from '../platform/platform.js';
import { ScopePatch } from '../scope/scope.js';
import { MiniAppSession } from '../session/miniapp.js';
import { NextjsSession, nextjsAuthConfig, InMemoryTokenStore, PlatformTokenStore } from '../session/nextjs.js';
import { StreamSession } from '../session/stream.js';
import { ElpianSurface, surfaceById } from '../session/surface.js';
import { MiniAppGrants, MiniAppHost, MiniAppManifests, type MiniAppGrant } from '../superapp/superapp.js';
import { deepMerge, isMap, type JsonMap } from '../util/json.js';
import { Limits, capabilityFromWireName, type ElpianCapability } from '../vm/governance.js';
import type { RuntimeKind } from '../vm/runtime.js';
import type { ViewEvent } from '../render/view.js';

export type EmitSink = (surface: string, event: string, payload: unknown) => void;

interface Entry {
  kind: string;
  surface: ElpianSurface;
  dispose(): Promise<void> | void;
  call(method: string, args: any[]): unknown | Promise<unknown>;
  viewportChanged(): void;
}

export class SessionRegistry {
  private readonly entries = new Map<string, Entry>();

  constructor(private readonly emit: EmitSink) {}

  has(surfaceId: string): boolean {
    return this.entries.has(surfaceId);
  }

  get(surfaceId: string): Entry | undefined {
    return this.entries.get(surfaceId);
  }

  /** Open a session of [kind] on [surfaceId] (closing any session already there). */
  async open(kind: string, surfaceId: string, options: JsonMap): Promise<void> {
    await this.close(surfaceId);
    const emit = (event: string, payload: unknown = null) => this.emit(surfaceId, event, payload);
    const surfaceOpts = {
      document: options.document === true,
      host: {
        openUrl: (url: string) => platform().openUrl?.(url),
        sceneTap: (props: Record<string, any>) => emit('sceneTap', props),
        baseUrl: () => (typeof options.baseUrl === 'string' ? options.baseUrl : null),
        navigate: (href: string, replace: boolean) => emit('navigate', { href, replace }),
      },
    };
    let entry: Entry;
    switch (kind) {
      case 'json': {
        const surface = new ElpianSurface(surfaceId, surfaceOpts);
        if (options.stylesheet) surface.engine.loadStylesheet(options.stylesheet);
        if (isMap(options.view)) surface.setContent(options.view);
        entry = {
          kind,
          surface,
          dispose: () => surface.dispose(),
          viewportChanged: () => surface.viewportChanged(),
          call: (method, args) => {
            switch (method) {
              case 'setContent':
                surface.setContent(isMap(args[0]) ? args[0] : null);
                return null;
              case 'patch': {
                // A scoped render, bounded like the VM's.
                const next = ScopePatch.applyBounded(surface.currentContent, args[0], args[1] ?? null);
                if (next) surface.setContent(next);
                return next != null;
              }
              case 'merge':
                surface.setContent(deepMerge(surface.currentContent ?? {}, args[0] ?? {}));
                return null;
              case 'loadStylesheet':
                surface.engine.loadStylesheet(args[0]);
                surface.scheduleRender();
                return null;
              case 'clearStylesheets':
                surface.engine.clearStylesheets();
                surface.scheduleRender();
                return null;
            }
            throw new Error(`json session has no method ${method}`);
          },
        };
        break;
      }
      case 'miniapp': {
        const session = new MiniAppSession(surfaceId, {
          machineId: String(options.machineId ?? surfaceId),
          runtime: runtimeOf(options.runtime),
          code: options.code ?? null,
          astJson: options.astJson ?? (isMap(options.ast) ? JSON.stringify(options.ast) : null),
          bytecodeBase64: options.bytecodeBase64 ?? null,
          stylesheet: options.stylesheet ?? null,
          entryFunction: options.entryFunction ?? null,
          entryInput: options.entryInput != null ? (typeof options.entryInput === 'string' ? options.entryInput : JSON.stringify(options.entryInput)) : null,
          hostEnvironment: isMap(options.hostEnvironment) ? options.hostEnvironment : undefined,
          showDefaultStates: options.showDefaultStates !== false,
          onPrintln: (m) => emit('println', m),
          onUpdateApp: (d) => emit('updateApp', d),
          onError: (m) => emit('error', m),
          onReady: () => emit('ready'),
          onCallRefused: (api) => emit('callRefused', api),
          onUnservicedApi: (api, advertised) => emit('unservicedApi', { api, advertised }),
          surface: surfaceOpts,
        });
        entry = {
          kind,
          surface: session.surface,
          dispose: () => session.dispose(),
          viewportChanged: () => session.viewportChanged(),
          call: (method, args) => {
            switch (method) {
              case 'callFunction':
                return session.callFunction(String(args[0]), args[1] == null ? null : typeof args[1] === 'string' ? args[1] : JSON.stringify(args[1]));
              case 'usage':
                return session.runtime?.governor.usage();
              case 'state':
                return session.runtime?.governor.state();
              case 'pause':
                return session.runtime?.governor.pause();
              case 'resume':
                return session.runtime?.governor.resumeExecution();
              case 'terminate':
                return session.runtime?.governor.terminate();
              case 'setLimits':
                return session.runtime?.governor.setLimits(Limits.fromJson(args[0] ?? {}));
              case 'sandbox':
                return session.runtime?.governor.sandbox(capsOf(args[0]));
              case 'view':
                return session.view;
            }
            throw new Error(`miniapp session has no method ${method}`);
          },
        };
        void session.start();
        break;
      }
      case 'superapp': {
        const manifest = MiniAppManifests.fromJson(isMap(options.manifest) ? options.manifest : {});
        const grant = grantOf(options.grant);
        const host = await MiniAppHost.launch({ manifest, grant, source: String(options.source ?? '') }).catch((e) => {
          emit('error', String(e instanceof Error ? e.message : e));
          return null;
        });
        if (!host) return;
        const session = await host.mount(surfaceId, {
          stylesheet: options.stylesheet ?? null,
          entryInput: options.entryInput != null ? (typeof options.entryInput === 'string' ? options.entryInput : JSON.stringify(options.entryInput)) : null,
          showDefaultStates: options.showDefaultStates !== false,
          onPrintln: (m) => emit('println', m),
          onUpdateApp: (d) => emit('updateApp', d),
          onError: (m) => emit('error', m),
          onReady: () => emit('ready', { denied: [...host.policy.deniedRequests] }),
          onCallRefused: (api) => emit('callRefused', api),
          onUnservicedApi: (api, advertised) => emit('unservicedApi', { api, advertised }),
          surface: surfaceOpts,
        });
        entry = {
          kind,
          surface: session.surface,
          dispose: () => host.dispose(),
          viewportChanged: () => session.viewportChanged(),
          call: async (method, args) => {
            switch (method) {
              case 'callFunction':
                return session.callFunction(String(args[0]), args[1] == null ? null : typeof args[1] === 'string' ? args[1] : JSON.stringify(args[1]));
              case 'usage':
                return host.usage();
              case 'branchUsage':
                return host.branchUsage();
              case 'pressure':
                return host.pressure();
              case 'policy':
                return { capabilities: [...host.policy.capabilities], denied: [...host.policy.deniedRequests], limits: host.policy.limits, mayHostChildren: host.policy.mayHostChildren };
              case 'spawnChild': {
                const child = await host.spawnChild({ manifest: MiniAppManifests.fromJson(args[0] ?? {}), source: String(args[1] ?? ''), grant: args[2] ? grantOf(args[2]) : null });
                return { machineId: child.machineId };
              }
              case 'pause':
                return host.governor.pause();
              case 'resume':
                return host.governor.resumeExecution();
              case 'terminate':
                return host.governor.terminate();
            }
            throw new Error(`superapp session has no method ${method}`);
          },
        };
        break;
      }
      case 'stream': {
        const session = new StreamSession(surfaceId, {
          initialStylesheet: isMap(options.initialStylesheet) ? options.initialStylesheet : null,
          defaultAnimationDurationMs: typeof options.defaultAnimationDurationMs === 'number' ? options.defaultAnimationDurationMs : undefined,
          defaultAnimationCurve: typeof options.defaultAnimationCurve === 'string' ? options.defaultAnimationCurve : undefined,
          onCommand: (c) => emit('command', c),
          onStreamDone: () => emit('streamDone'),
          onError: (m) => emit('error', m),
          surface: surfaceOpts,
        });
        if (isMap(options.request)) session.connect(options.request as any);
        entry = {
          kind,
          surface: session.surface,
          dispose: () => session.dispose(),
          viewportChanged: () => session.surface.viewportChanged(),
          call: (method, args) => {
            switch (method) {
              case 'push':
                session.push(args[0]);
                return null;
              case 'error':
                session.error(args[0]);
                return null;
              case 'done':
                session.done();
                return null;
              case 'connect':
                session.connect(args[0]);
                return null;
            }
            throw new Error(`stream session has no method ${method}`);
          },
        };
        break;
      }
      case 'nextjs': {
        const auth = isMap(options.auth)
          ? nextjsAuthConfig({
              store: options.auth.persist === false ? new InMemoryTokenStore() : new PlatformTokenStore(String(options.auth.namespace ?? 'elpian')),
              loginRoute: options.auth.loginRoute,
              refreshRoute: options.auth.refreshRoute,
              bearerScheme: options.auth.bearerScheme,
            })
          : null;
        const session = new NextjsSession(surfaceId, {
          route: String(options.route ?? '/'),
          serverBaseUrl: options.serverBaseUrl ?? null,
          endpoint: options.endpoint ?? null,
          requestMode: options.requestMode === 'apiEndpoint' ? 'apiEndpoint' : 'routePath',
          props: isMap(options.props) ? options.props : null,
          headers: isMap(options.headers) ? (options.headers as Record<string, string>) : null,
          auth,
          timeoutMs: typeof options.timeoutMs === 'number' ? options.timeoutMs : undefined,
          onScriptExecuted: (r) => emit('scriptExecuted', r),
          onScriptError: (e) => emit('scriptError', String(e)),
          onRouteChanged: (route) => emit('routeChanged', route),
          onSceneTap: options.handleSceneTaps === true ? (p) => emit('sceneTap', p) : undefined,
          surface: { ...surfaceOpts, host: { ...surfaceOpts.host, navigate: undefined } as any },
        });
        entry = {
          kind,
          surface: session.surface,
          dispose: () => session.dispose(),
          viewportChanged: () => session.viewportChanged(),
          call: (method, args) => {
            switch (method) {
              case 'navigate':
                session.navigate(String(args[0]), args[1] === true);
                return null;
              case 'back':
                return session.back();
              case 'refresh':
                session.refresh();
                return null;
              case 'route':
                return session.route;
              case 'canGoBack':
                return session.canGoBack;
            }
            throw new Error(`nextjs session has no method ${method}`);
          },
        };
        break;
      }
      case 'server': {
        const client = new ElpianServerClient(
          String(options.baseUrl ?? ''),
          String(options.appId ?? ''),
          ElpianNetPolicy.fromManifest(options.netPolicy),
          options.authorization != null ? String(options.authorization) : null,
          typeof options.timeoutMs === 'number' ? options.timeoutMs : 15000,
        );
        const session = new ServerComponentSession(surfaceId, {
          client,
          name: String(options.name ?? ''),
          args: isMap(options.args) ? options.args : {},
          nativeIslands: isMap(options.nativeIslands) ? (options.nativeIslands as Record<string, string>) : undefined,
          revalidateMs: typeof options.revalidateMs === 'number' ? options.revalidateMs : null,
          surface: surfaceOpts,
        });
        entry = {
          kind,
          surface: session.surface,
          dispose: () => {
            session.dispose();
            client.close();
          },
          viewportChanged: () => session.surface.viewportChanged(),
          call: (method, args) => {
            switch (method) {
              case 'update':
                session.update(args[0] ?? {});
                return null;
              case 'refresh':
                return session.fetch();
              case 'callAction':
                return client.callAction(String(args[0]), args[1] ?? {});
              case 'unresolvedIslands':
                return session.unresolvedIslands();
            }
            throw new Error(`server session has no method ${method}`);
          },
        };
        break;
      }
      default:
        throw new Error(`unknown session kind "${kind}"`);
    }
    this.entries.set(surfaceId, entry);
  }

  async call(surfaceId: string, method: string, args: any[]): Promise<unknown> {
    const e = this.entries.get(surfaceId);
    if (!e) throw new Error(`no session on surface "${surfaceId}"`);
    return await e.call(method, args);
  }

  dispatchViewEvent(surfaceId: string, event: ViewEvent): void {
    surfaceById(surfaceId)?.dispatchViewEvent(event);
  }

  viewportChanged(surfaceId: string): void {
    const e = this.entries.get(surfaceId);
    if (e) e.viewportChanged();
    else surfaceById(surfaceId)?.viewportChanged();
  }

  /** An image finished loading: every surface showing it relayouts. */
  imageLoaded(src: string, width: number, height: number): void {
    for (const e of this.entries.values()) e.surface.imageLoaded(src, width, height);
  }

  /** Fonts loaded / changed: re-measure text everywhere. */
  invalidateText(): void {
    for (const e of this.entries.values()) {
      e.surface.invalidateText();
      e.surface.scheduleRender();
    }
  }

  async close(surfaceId: string): Promise<void> {
    const e = this.entries.get(surfaceId);
    if (!e) return;
    this.entries.delete(surfaceId);
    await e.dispose();
  }

  async closeAll(): Promise<void> {
    for (const id of [...this.entries.keys()]) await this.close(id);
  }
}

function runtimeOf(v: unknown): RuntimeKind {
  return v === 'quickjs' || v === 'quickJs' ? 'quickjs' : v === 'wasm' ? 'wasm' : 'elpian';
}

function capsOf(v: unknown): Set<ElpianCapability> {
  const out = new Set<ElpianCapability>();
  if (Array.isArray(v)) for (const x of v) {
    const c = capabilityFromWireName(String(x));
    if (c) out.add(c);
  }
  return out;
}

function grantOf(v: unknown): MiniAppGrant {
  if (v === 'trusted') return MiniAppGrants.trusted;
  if (!isMap(v)) return MiniAppGrants.untrusted;
  const base = v.base === 'trusted' ? MiniAppGrants.trusted : MiniAppGrants.untrusted;
  return {
    capabilities: Array.isArray(v.capabilities) ? capsOf(v.capabilities) : base.capabilities,
    limits: isMap(v.limits) ? Limits.fromJson(v.limits) : base.limits,
    mayHostChildren: typeof v.mayHostChildren === 'boolean' ? v.mayHostChildren : base.mayHostChildren,
    allowedApis: Array.isArray(v.allowedApis) ? new Set(v.allowedApis.map(String)) : base.allowedApis,
  };
}
