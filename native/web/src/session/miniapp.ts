/**
 * One running mini app on one surface — the port of `ElpianVmWidget`
 * (flutter/lib/src/vm/elpian_vm_widget.dart).
 *
 * It creates the selected runtime, wires every host API (render, DOM,
 * canvas, env, timers, plus host-supplied handlers), runs the program and its
 * entry function, routes UI events to the guest functions named in each
 * node's `events`, applies bounded scope patches, and keeps the guest's host
 * environment (viewport, safe area, page, platform) in sync.
 */
import { AGENT_API_NAMES } from '../a2ui/elpian.js';
import type { ElpianEngine } from '../engine/engine.js';
import { eventToJson, type ElpianEvent } from '../events/events.js';
import { HostHandler } from '../host/host-handler.js';
import { VmTimerHostApi } from '../host/timers.js';
import { platform } from '../platform/platform.js';
import { ScopePatch } from '../scope/scope.js';
import type { JsonMap } from '../util/json.js';
import { toTypedVmValue } from '../util/typed.js';
import { allHostApiNames, timerApiNames } from '../vm/host-api-catalog.js';
import { ElpianVm, QuickJsVm, WasmVm, initializeRuntime, type HostCallHandler, type RuntimeKind, type VmRuntimeClient } from '../vm/runtime.js';
import { ElpianSurface, loadingIndicator, messageBox, type SurfaceOptions } from './surface.js';

export interface MiniAppOptions {
  machineId: string;
  runtime?: RuntimeKind;
  /** Elpian source, JS source (QuickJS) or the WASM config JSON. */
  code?: string | null;
  astJson?: string | null;
  /** Elpian VM bytecode, base64. */
  bytecodeBase64?: string | null;
  stylesheet?: JsonMap | string | null;
  entryFunction?: string | null;
  entryInput?: string | null;
  hostHandlers?: Record<string, HostCallHandler>;
  /** Extra host-environment fields merged into `env.get`. */
  hostEnvironment?: JsonMap;
  onPrintln?(message: string): void;
  onUpdateApp?(data: JsonMap): void;
  onError?(message: string): void;
  /** Consulted before every host call (HostHandler.onAuthorize). */
  onAuthorize?(apiName: string): boolean;
  onCallRefused?(apiName: string): void;
  onUnservicedApi?(apiName: string, advertised: boolean): void;
  /** Called once the program and entry function have run. */
  onReady?(): void;
  /** Hide Flutter's default loading spinner / error box. */
  showDefaultStates?: boolean;
  surface?: SurfaceOptions;
  /** A runtime already created (MiniAppHost.mount); the session then neither creates nor disposes it. */
  runtimeClient?: VmRuntimeClient;
}

export class MiniAppSession {
  readonly surface: ElpianSurface;
  private runtimeVm: VmRuntimeClient | null = null;
  private timers: VmTimerHostApi | null = null;
  private currentView: JsonMap | null = null;
  private envData: JsonMap = {};
  private envDigest: string | null = null;
  private disposed = false;
  private loading = true;
  private errorMessage: string | null = null;

  constructor(
    surfaceId: string,
    readonly options: MiniAppOptions,
  ) {
    this.surface = new ElpianSurface(surfaceId, options.surface);
    if (options.stylesheet) this.engine.loadStylesheet(options.stylesheet);
    this.showState();
  }

  get engine(): ElpianEngine {
    return this.surface.engine;
  }

  get runtime(): VmRuntimeClient | null {
    return this.runtimeVm;
  }

  get error(): string | null {
    return this.errorMessage;
  }

  get isLoading(): boolean {
    return this.loading;
  }

  get view(): JsonMap | null {
    return this.currentView;
  }

  /** Create the runtime, wire the host APIs, run the program and the entry function. */
  async start(): Promise<void> {
    const o = this.options;
    const kind = o.runtime ?? 'elpian';
    try {
      let vm: VmRuntimeClient | null = o.runtimeClient ?? null;
      if (vm) {
        // Provided by the host: already created and governed.
      } else if (kind === 'elpian') {
        await initializeRuntime(kind);
        if (o.bytecodeBase64) vm = await ElpianVm.fromBytecode(o.machineId, o.bytecodeBase64);
        else if (o.code != null) vm = await ElpianVm.fromCode(o.machineId, o.code);
        else if (o.astJson != null) vm = await ElpianVm.fromAst(o.machineId, o.astJson);
        if (!vm) {
          const detail = ElpianVm.lastApiError;
          return this.fail(detail ? `Failed to create VM: ${detail}` : 'Failed to create VM');
        }
      } else if (kind === 'quickjs') {
        await initializeRuntime(kind);
        if (o.code == null) return this.fail('QuickJS runtime requires `code` (JavaScript source).');
        vm = await QuickJsVm.fromCode(o.machineId, o.code);
      } else {
        if (o.code == null) return this.fail('WASM runtime requires `code` (WASM config JSON).');
        vm = await WasmVm.fromCode(o.machineId, o.code);
      }
      if (this.disposed) {
        if (!o.runtimeClient) await vm.dispose();
        return;
      }
      this.runtimeVm = vm;

      // Every UI event goes to the guest function named in node.events.
      this.engine.services.events.onGlobalEvent((event) => void this.routeEventToVm(event));

      const handler = new HostHandler(this.engine.services, {
        onRender: (view, scopeKey) => this.applyRender(view, scopeKey),
        onUpdateApp: (data) => {
          o.onUpdateApp?.(data);
          if (o.entryFunction) void this.callEntryFunction();
        },
        onPrintln: o.onPrintln ?? ((m) => platform().log('info', `[${o.machineId}] ${m}`)),
        onGetEnvironment: () => this.envData,
        onAuthorize: o.onAuthorize,
        onCallRefused: o.onCallRefused,
        onUnservicedApi: o.onUnservicedApi,
        log: (m) => platform().log('debug', m),
      });

      this.timers?.dispose();
      const runtimeVm = vm;
      this.timers = new VmTimerHostApi(
        async (fn, input) => {
          if (this.disposed) return;
          if (input == null) await runtimeVm.callFunction(fn);
          else await runtimeVm.callFunctionWithInput(fn, input);
        },
        (m) => platform().log('warn', `ElpianMiniApp: ${m}`),
      );

      const handlers: Record<string, HostCallHandler> = {};
      for (const api of allHostApiNames) handlers[api] = (name, payload) => handler.handleHostCall(name, payload);
      // The agent APIs, also while the generated catalog does not list them yet.
      for (const api of AGENT_API_NAMES) handlers[api] = (name, payload) => handler.handleHostCall(name, payload);
      for (const api of timerApiNames) handlers[api] = (name, payload) => this.timers!.handle(name, payload);
      Object.assign(handlers, o.hostHandlers ?? {});
      vm.registerHostHandlers(handlers);
      await this.syncHostEnvironment(true);

      await vm.run();
      if (o.entryFunction) await this.callEntryFunction();
      this.loading = false;
      this.showState();
      o.onReady?.();
    } catch (e) {
      this.fail(String(e instanceof Error ? e.message : e));
    }
  }

  private fail(message: string): void {
    this.errorMessage = message;
    this.loading = false;
    this.options.onError?.(message);
    this.showState();
  }

  private showState(): void {
    if (this.disposed) return;
    const defaults = this.options.showDefaultStates ?? true;
    if (this.errorMessage != null) {
      this.surface.setOverlay(defaults ? messageBox(`VM Error: ${this.errorMessage}`, 0xfff44336) : null);
      return;
    }
    if (this.loading && this.currentView == null) {
      this.surface.setOverlay(defaults ? loadingIndicator() : null);
      return;
    }
    this.surface.setContent(this.currentView);
  }

  private applyRender(view: JsonMap, scopeKey: string | null): void {
    // Bounded scope patch: a scoped render whose key is missing is dropped.
    const next = ScopePatch.applyBounded(this.currentView, view, scopeKey);
    if (next == null) {
      platform().log('debug', `ElpianMiniApp: scoped render targeted missing scope "${scopeKey}"; keeping current view.`);
      return;
    }
    this.currentView = next;
    if (this.errorMessage == null) this.surface.setContent(next);
    void this.syncHostEnvironment(false);
  }

  private async routeEventToVm(event: ElpianEvent): Promise<void> {
    const vm = this.runtimeVm;
    if (!vm || this.disposed) return;
    const nodeId = event.currentTarget;
    if (!nodeId) return;
    const handler = this.engine.services.events.getNode(nodeId)?.events?.[event.type];
    if (typeof handler !== 'string' || !handler) return;
    // Typed JSON input so every runtime decodes event arguments the same way.
    const payload = JSON.stringify(toTypedVmValue(eventToJson(event)));
    try {
      await vm.callFunctionWithInput(handler, payload);
    } catch (e) {
      try {
        await vm.callFunction(handler);
      } catch (fallback) {
        platform().log('warn', `ElpianMiniApp: Error calling event handler "${handler}": ${e}; fallback failed: ${fallback}`);
      }
    }
  }

  private async callEntryFunction(): Promise<void> {
    const vm = this.runtimeVm;
    const fn = this.options.entryFunction;
    if (!vm || !fn) return;
    try {
      if (this.options.entryInput != null) await vm.callFunctionWithInput(fn, this.options.entryInput);
      else await vm.callFunction(fn);
    } catch (e) {
      platform().log('warn', `ElpianMiniApp: Error calling ${fn}: ${e}`);
    }
  }

  /** Call a guest function (ElpianVmController.callFunction). */
  async callFunction(funcName: string, input?: string | null): Promise<string> {
    const vm = this.runtimeVm;
    if (!vm) return '';
    return input != null ? vm.callFunctionWithInput(funcName, input) : vm.callFunction(funcName);
  }

  /** The platform reports a viewport / safe-area / theme change. */
  viewportChanged(): void {
    this.surface.viewportChanged();
    void this.syncHostEnvironment(true);
  }

  private async syncHostEnvironment(force: boolean): Promise<void> {
    const next = this.buildHostEnvironment();
    const digest = JSON.stringify(next);
    const changed = digest !== this.envDigest;
    if (changed) {
      this.envDigest = digest;
      this.envData = next;
    }
    if (!this.runtimeVm || (!changed && !force)) return;
    try {
      await this.runtimeVm.setGlobalHostData(this.envData);
    } catch (e) {
      platform().log('warn', `ElpianMiniApp: failed to sync host env: ${e}`);
    }
  }

  private buildHostEnvironment(): JsonMap {
    const vp = platform().viewport(this.surface.id);
    const href = vp.href ?? '';
    let page: JsonMap = { href, scheme: '', host: '', port: null, path: '', query: '', queryParameters: {}, fragment: '' };
    const m = /^([a-zA-Z][\w+.-]*):(?:\/\/([^/?#:]*)(?::(\d+))?)?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/.exec(href);
    if (m) {
      const query = m[5] ?? '';
      const params: Record<string, string> = {};
      for (const part of query.split('&')) {
        if (!part) continue;
        const i = part.indexOf('=');
        const k = decodeURIComponentSafe(i < 0 ? part : part.substring(0, i));
        params[k] = decodeURIComponentSafe(i < 0 ? '' : part.substring(i + 1));
      }
      page = { href, scheme: m[1], host: m[2] ?? '', port: m[3] != null ? Number(m[3]) : null, path: m[4] ?? '', query, queryParameters: params, fragment: m[6] ?? '' };
    }
    return {
      machineId: this.options.machineId,
      runtime: runtimeName(this.options.runtime ?? 'elpian'),
      viewport: {
        width: vp.width,
        height: vp.height,
        devicePixelRatio: vp.devicePixelRatio,
        orientation: vp.width >= vp.height ? 'landscape' : 'portrait',
      },
      screen: { physicalWidth: vp.width * vp.devicePixelRatio, physicalHeight: vp.height * vp.devicePixelRatio },
      safeArea: { ...vp.safeArea },
      page,
      platform: { isWeb: vp.isWeb, defaultTargetPlatform: vp.platform, locale: vp.locale },
      ...(this.options.hostEnvironment ?? {}),
    };
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    this.timers?.dispose();
    this.timers = null;
    const vm = this.runtimeVm;
    this.runtimeVm = null;
    this.surface.dispose();
    if (!this.options.runtimeClient) await vm?.dispose();
  }
}

/** `ElpianRuntime.name` in Dart. */
function runtimeName(kind: RuntimeKind): string {
  return kind === 'quickjs' ? 'quickJs' : kind;
}

function decodeURIComponentSafe(s: string): string {
  try {
    return decodeURIComponent(s.replace(/\+/g, ' '));
  } catch {
    return s;
  }
}
