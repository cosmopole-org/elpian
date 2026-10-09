/**
 * Hosting third-party mini apps — ports of flutter/lib/src/superapp/
 * {mini_app,mini_app_host}.dart: manifests, grants, the resolved policy, the
 * host-call gate, nested mini apps and metering. `MiniAppHost.mount` adds
 * what the Flutter host does by embedding a widget: rendering the app on a
 * native surface with the policy enforced on every host call.
 */
import { ElpianServices } from '../engine/engine.js';
import { HostHandler, type RenderHostCallback } from '../host/host-handler.js';
import { MiniAppSession, type MiniAppOptions } from '../session/miniapp.js';
import { isMap, type JsonMap } from '../util/json.js';
import { capabilityFor } from '../vm/host-api-catalog.js';
import {
  CAPABILITIES,
  Limits,
  capabilityFromWireName,
  pressureAgainst,
  type ElpianCapability,
  type ElpianLimits,
  type ElpianUsage,
  type VmGovernor,
} from '../vm/governance.js';
import { ElpianVm, QuickJsVm, WasmVm, type RuntimeKind, type VmRuntimeClient } from '../vm/runtime.js';

export interface MiniAppManifest {
  id: string;
  name: string;
  version: string;
  entrypoint: string;
  runtime: RuntimeKind;
  requestedCapabilities: Set<ElpianCapability>;
  requestedLimits: ElpianLimits | null;
  allowsChildren: boolean;
  metadata: JsonMap;
}

export const MiniAppManifests = {
  create(m: Partial<MiniAppManifest> & { id: string; name: string }): MiniAppManifest {
    return {
      version: '0.0.0',
      entrypoint: 'main',
      runtime: 'elpian',
      requestedCapabilities: new Set(),
      requestedLimits: null,
      allowsChildren: false,
      metadata: {},
      ...m,
    };
  },
  fromJson(json: JsonMap): MiniAppManifest {
    const caps = new Set<ElpianCapability>();
    // Unknown capability names are dropped: that can only narrow the request.
    for (const raw of Array.isArray(json.requestedCapabilities) ? json.requestedCapabilities : []) {
      const c = capabilityFromWireName(String(raw));
      if (c) caps.add(c);
    }
    const runtime: RuntimeKind = json.runtime === 'quickJs' || json.runtime === 'quickjs' ? 'quickjs' : json.runtime === 'wasm' ? 'wasm' : 'elpian';
    return {
      id: typeof json.id === 'string' ? json.id : '',
      name: typeof json.name === 'string' ? json.name : typeof json.id === 'string' ? json.id : 'Untitled',
      version: typeof json.version === 'string' ? json.version : '0.0.0',
      entrypoint: typeof json.entrypoint === 'string' ? json.entrypoint : 'main',
      runtime,
      requestedCapabilities: caps,
      requestedLimits: isMap(json.requestedLimits) ? Limits.fromJson(json.requestedLimits) : null,
      allowsChildren: json.allowsChildren === true,
      metadata: isMap(json.metadata) ? json.metadata : {},
    };
  },
  toJson(m: MiniAppManifest): JsonMap {
    return {
      id: m.id,
      name: m.name,
      version: m.version,
      entrypoint: m.entrypoint,
      runtime: m.runtime === 'quickjs' ? 'quickJs' : m.runtime,
      requestedCapabilities: [...m.requestedCapabilities],
      ...(m.requestedLimits ? { requestedLimits: Limits.toJson(m.requestedLimits) } : {}),
      allowsChildren: m.allowsChildren,
      ...(Object.keys(m.metadata).length ? { metadata: m.metadata } : {}),
    };
  },
  validate(m: MiniAppManifest): string | null {
    if (!m.id) return 'a mini app must declare an id';
    // `::` namespaces resources; allowing it would let one app forge another's.
    if (m.id.includes('::')) return 'a mini app id may not contain "::"';
    if (!m.entrypoint) return 'a mini app must declare an entrypoint';
    return null;
  },
};

export interface MiniAppGrant {
  capabilities: Set<ElpianCapability>;
  limits: ElpianLimits;
  mayHostChildren: boolean;
  allowedApis: Set<string> | null;
}

export const MiniAppGrants = {
  /** Render-only: no network, storage, clock, randomness or nested apps. */
  get untrusted(): MiniAppGrant {
    return { capabilities: new Set<ElpianCapability>(['render', 'dom', 'canvas', 'surface', 'logging']), limits: Limits.sandboxed, mayHostChildren: false, allowedApis: null };
  },
  get trusted(): MiniAppGrant {
    return { capabilities: new Set<ElpianCapability>(CAPABILITIES), limits: Limits.unlimited, mayHostChildren: true, allowedApis: null };
  },
};

export class MiniAppPolicy {
  private constructor(
    readonly manifest: MiniAppManifest,
    readonly grant: MiniAppGrant,
    readonly capabilities: Set<ElpianCapability>,
    readonly limits: ElpianLimits,
    readonly mayHostChildren: boolean,
    readonly deniedRequests: Set<ElpianCapability>,
  ) {}

  static resolve(manifest: MiniAppManifest, grant: MiniAppGrant): MiniAppPolicy {
    const requested = manifest.requestedCapabilities.size === 0 ? grant.capabilities : manifest.requestedCapabilities;
    const allowed = new Set([...requested].filter((c) => grant.capabilities.has(c)));
    const denied = new Set([...requested].filter((c) => !grant.capabilities.has(c)));
    return new MiniAppPolicy(
      manifest,
      grant,
      allowed,
      MiniAppPolicy.tightest(manifest.requestedLimits, grant.limits),
      manifest.allowsChildren && grant.mayHostChildren && allowed.has('vm_manage'),
      denied,
    );
  }

  allowsApi(apiName: string, capability: ElpianCapability): boolean {
    if (!this.capabilities.has(capability)) return false;
    return this.grant.allowedApis == null || this.grant.allowedApis.has(apiName);
  }

  static tightest(a: ElpianLimits | null, b: ElpianLimits): ElpianLimits {
    return a == null ? b : Limits.tightest(a, b);
  }
}

export class MiniAppException extends Error {
  constructor(
    readonly appId: string,
    readonly reason: string,
  ) {
    super(`MiniAppException(${appId}): ${reason}`);
  }
}

export interface MountOptions extends Omit<MiniAppOptions, 'machineId' | 'runtime' | 'code' | 'astJson' | 'bytecodeBase64' | 'runtimeClient' | 'onAuthorize'> {}

export class MiniAppHost {
  readonly engineServices: ElpianServices;
  readonly machineId: string;
  private readonly kids: MiniAppHost[] = [];
  private disposed = false;
  private sessions: MiniAppSession[] = [];

  private constructor(
    readonly policy: MiniAppPolicy,
    readonly runtime: VmRuntimeClient,
    readonly parent: MiniAppHost | null,
  ) {
    this.machineId = runtime.machineId;
    this.engineServices = new ElpianServices(this.machineId);
  }

  get id(): string {
    return this.policy.manifest.id;
  }
  get governor(): VmGovernor {
    return this.runtime.governor;
  }
  get children(): readonly MiniAppHost[] {
    return [...this.kids];
  }
  get isDisposed(): boolean {
    return this.disposed;
  }

  static async launch(opts: { manifest: MiniAppManifest; grant: MiniAppGrant; source: string; parent?: MiniAppHost | null; machineIdOverride?: string | null }): Promise<MiniAppHost> {
    const { manifest, grant, source } = opts;
    const parent = opts.parent ?? null;
    const invalid = MiniAppManifests.validate(manifest);
    if (invalid) throw new MiniAppException(manifest.id, invalid);
    const policy = MiniAppPolicy.resolve(manifest, grant);
    const machineId = opts.machineIdOverride ?? (parent == null ? manifest.id : `${parent.machineId}.${manifest.id}`);
    const runtime = await startRuntime(manifest, source, machineId);
    const host = new MiniAppHost(policy, runtime, parent);
    // Adopt first: the child's effective capabilities are clipped to its
    // ancestors, so the grants applied next can only narrow further.
    if (parent) await ElpianVm.treeGovernor.adopt(parent.machineId, machineId);
    await host.governor.sandbox(policy.capabilities);
    await host.governor.setLimits(policy.limits);
    return host;
  }

  /** A HostHandler whose every call passes this app's policy first. */
  createHostHandler(cb: { onRender?: RenderHostCallback; onUpdateApp?: (d: JsonMap) => void; onPrintln?: (m: string) => void; onGetEnvironment?: () => JsonMap; onCallRefused?: (api: string) => void } = {}): HostHandler {
    return new HostHandler(this.engineServices, { ...cb, onAuthorize: (api) => this.authorizes(api) });
  }

  authorizes(apiName: string): boolean {
    const capability = capabilityFromWireName(capabilityFor(apiName)) ?? 'other';
    return this.policy.allowsApi(apiName, capability);
  }

  /**
   * Render this mini app on the platform surface [surfaceId]: runs the
   * program and its manifest entrypoint, with this app's policy gating every
   * host call.
   */
  async mount(surfaceId: string, options: MountOptions = {}): Promise<MiniAppSession> {
    if (this.disposed) throw new MiniAppException(this.id, 'cannot mount a disposed app');
    const session = new MiniAppSession(surfaceId, {
      ...options,
      machineId: this.machineId,
      runtime: this.policy.manifest.runtime,
      runtimeClient: this.runtime,
      entryFunction: options.entryFunction ?? this.policy.manifest.entrypoint,
      onAuthorize: (api) => this.authorizes(api),
      surface: { ...(options.surface ?? {}), services: this.engineServices },
    });
    this.sessions.push(session);
    await session.start();
    return session;
  }

  async spawnChild(opts: { manifest: MiniAppManifest; source: string; grant?: MiniAppGrant | null }): Promise<MiniAppHost> {
    if (this.disposed) throw new MiniAppException(this.id, 'cannot spawn a child from a disposed app');
    if (!this.policy.mayHostChildren) {
      throw new MiniAppException(
        this.id,
        'this mini app is not permitted to host children — it needs `allowsChildren` in its manifest, `mayHostChildren` in its grant, and the vm_manage capability',
      );
    }
    const child = await MiniAppHost.launch({ manifest: opts.manifest, grant: this.narrow(opts.grant ?? null), source: opts.source, parent: this });
    this.kids.push(child);
    return child;
  }

  private narrow(requested: MiniAppGrant | null): MiniAppGrant {
    const p = this.policy;
    const base: MiniAppGrant = requested ?? { capabilities: p.capabilities, limits: p.limits, mayHostChildren: p.mayHostChildren, allowedApis: p.grant.allowedApis };
    return {
      capabilities: new Set([...base.capabilities].filter((c) => p.capabilities.has(c))),
      limits: MiniAppPolicy.tightest(base.limits, p.limits),
      mayHostChildren: base.mayHostChildren && p.mayHostChildren,
      allowedApis: intersectApis(base.allowedApis, p.grant.allowedApis),
    };
  }

  usage(): Promise<ElpianUsage> {
    return this.governor.usage();
  }
  branchUsage(): Promise<ElpianUsage> {
    return this.governor.subtreeUsage();
  }
  async pressure(): Promise<Record<string, number>> {
    return pressureAgainst(await this.branchUsage(), this.policy.limits);
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    for (const child of [...this.kids]) await child.dispose();
    this.kids.length = 0;
    for (const s of this.sessions) await s.dispose();
    this.sessions = [];
    try {
      await this.runtime.dispose();
    } finally {
      this.engineServices.dispose();
    }
  }
}

async function startRuntime(manifest: MiniAppManifest, source: string, machineId: string): Promise<VmRuntimeClient> {
  switch (manifest.runtime) {
    case 'elpian': {
      await ElpianVm.initialize();
      const vm = await ElpianVm.fromCode(machineId, source);
      if (!vm) throw new MiniAppException(manifest.id, `the Elpian runtime could not start it: ${ElpianVm.lastApiError}`);
      return vm;
    }
    case 'quickjs':
      return QuickJsVm.fromCode(machineId, source);
    case 'wasm':
      return WasmVm.fromCode(machineId, source);
  }
}

function intersectApis(a: Set<string> | null, b: Set<string> | null): Set<string> | null {
  if (a == null) return b;
  if (b == null) return a;
  return new Set([...a].filter((x) => b.has(x)));
}
