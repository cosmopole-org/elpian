/**
 * Governance — ports of flutter/lib/src/vm/governance/{models,governor,
 * host_side_governor,elpian_governor}.dart. The wire format is the JSON
 * documented on rust/src/api/govern.rs.
 */
import { platform, hasPlatform } from '../platform/platform.js';
import { isMap } from '../util/json.js';
import { capabilityFor } from './host-api-catalog.js';
import type { ElpianVmBinding } from './bindings.js';

export class ElpianGovernanceException extends Error {
  constructor(
    readonly reason: string,
    readonly call: string | null = null,
  ) {
    super(call == null ? `ElpianGovernanceException: ${reason}` : `ElpianGovernanceException: ${call} failed: ${reason}`);
  }
}

export function decodeGovernanceReply(raw: string, call?: string): Record<string, any> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    throw new ElpianGovernanceException(`malformed reply: ${e}`, call ?? null);
  }
  if (!isMap(parsed)) throw new ElpianGovernanceException(`expected an object, got ${raw}`, call ?? null);
  if (typeof parsed.error === 'string') throw new ElpianGovernanceException(parsed.error, call ?? null);
  return parsed;
}

// ---------------------------------------------------------------------------
// Limits / usage
// ---------------------------------------------------------------------------

export interface ElpianLimits {
  maxInstructions?: number | null;
  maxInstructionsPerTurn?: number | null;
  maxMemoryBytes?: number | null;
  maxStorageBytes?: number | null;
  maxCallDepth?: number | null;
}

export const Limits = {
  unlimited: Object.freeze({}) as ElpianLimits,
  /** `ResourceLimits::sandboxed()`. */
  sandboxed: Object.freeze({
    maxInstructions: 50_000_000,
    maxInstructionsPerTurn: 5_000_000,
    maxMemoryBytes: 64 * 1024 * 1024,
    maxStorageBytes: 16 * 1024 * 1024,
    maxCallDepth: 1024,
  }) as ElpianLimits,
  toJson(l: ElpianLimits): Record<string, number | null> {
    return {
      maxInstructions: l.maxInstructions ?? null,
      maxInstructionsPerTurn: l.maxInstructionsPerTurn ?? null,
      maxMemoryBytes: l.maxMemoryBytes ?? null,
      maxStorageBytes: l.maxStorageBytes ?? null,
      maxCallDepth: l.maxCallDepth ?? null,
    };
  },
  fromJson(j: Record<string, any>): ElpianLimits {
    const n = (v: any) => (typeof v === 'number' ? v : null);
    return {
      maxInstructions: n(j.maxInstructions),
      maxInstructionsPerTurn: n(j.maxInstructionsPerTurn),
      maxMemoryBytes: n(j.maxMemoryBytes),
      maxStorageBytes: n(j.maxStorageBytes),
      maxCallDepth: n(j.maxCallDepth),
    };
  },
  /** The tighter of each axis (null = unbounded). */
  tightest(a: ElpianLimits, b: ElpianLimits): ElpianLimits {
    const t = (x?: number | null, y?: number | null) => (x == null ? y ?? null : y == null ? x : Math.min(x, y));
    return {
      maxInstructions: t(a.maxInstructions, b.maxInstructions),
      maxInstructionsPerTurn: t(a.maxInstructionsPerTurn, b.maxInstructionsPerTurn),
      maxMemoryBytes: t(a.maxMemoryBytes, b.maxMemoryBytes),
      maxStorageBytes: t(a.maxStorageBytes, b.maxStorageBytes),
      maxCallDepth: t(a.maxCallDepth, b.maxCallDepth),
    };
  },
};

export interface ElpianUsage {
  instructions: number;
  instructionsThisTurn: number;
  memoryBytes: number;
  peakMemoryBytes: number;
  storageBytes: number;
  callDepth: number;
  peakCallDepth: number;
}

export const ZERO_USAGE: ElpianUsage = Object.freeze({
  instructions: 0,
  instructionsThisTurn: 0,
  memoryBytes: 0,
  peakMemoryBytes: 0,
  storageBytes: 0,
  callDepth: 0,
  peakCallDepth: 0,
});

export function usageFromJson(j: Record<string, any>): ElpianUsage {
  const n = (v: any) => (typeof v === 'number' ? Math.trunc(v) : 0);
  return {
    instructions: n(j.instructions),
    instructionsThisTurn: n(j.instructionsThisTurn),
    memoryBytes: n(j.memoryBytes),
    peakMemoryBytes: n(j.peakMemoryBytes),
    storageBytes: n(j.storageBytes),
    callDepth: n(j.callDepth),
    peakCallDepth: n(j.peakCallDepth),
  };
}

/** How much of [limits] [usage] consumed per axis (0..1); unbounded axes absent. */
export function pressureAgainst(usage: ElpianUsage, limits: ElpianLimits): Record<string, number> {
  const out: Record<string, number> = {};
  const add = (axis: string, used: number, max?: number | null) => {
    if (max != null && max > 0) out[axis] = used / max;
  };
  add('instructions', usage.instructions, limits.maxInstructions);
  add('instructionsPerTurn', usage.instructionsThisTurn, limits.maxInstructionsPerTurn);
  add('memory', usage.memoryBytes, limits.maxMemoryBytes);
  add('storage', usage.storageBytes, limits.maxStorageBytes);
  add('callDepth', usage.callDepth, limits.maxCallDepth);
  return out;
}

// ---------------------------------------------------------------------------
// Capabilities / lifecycle / tree
// ---------------------------------------------------------------------------

/** Wire names of `Capability::as_str`. */
export const CAPABILITIES = [
  'logging',
  'gpu',
  'module_import',
  'network',
  'storage',
  'clock',
  'randomness',
  'vm_manage',
  'dom',
  'canvas',
  'render',
  'timers',
  'environment',
  'tasks',
  'host_messaging',
  'surface',
  'server_call',
  'state',
  'other',
] as const;
export type ElpianCapability = (typeof CAPABILITIES)[number];

export function capabilityFromWireName(name: string): ElpianCapability | null {
  return (CAPABILITIES as readonly string[]).includes(name) ? (name as ElpianCapability) : null;
}

export class ElpianCapabilities {
  constructor(private readonly allowed: Partial<Record<ElpianCapability, boolean>>) {}
  static fromJson(json: Record<string, any>): ElpianCapabilities {
    const map: Partial<Record<ElpianCapability, boolean>> = {};
    for (const [k, v] of Object.entries(json)) {
      const cap = capabilityFromWireName(k);
      if (cap && typeof v === 'boolean') map[cap] = v;
    }
    return new ElpianCapabilities(map);
  }
  /** Unknown reads as denied — an unrecognised gate must never be a pass. */
  allows(c: ElpianCapability): boolean {
    return this.allowed[c] ?? false;
  }
  get granted(): ElpianCapability[] {
    return (Object.keys(this.allowed) as ElpianCapability[]).filter((k) => this.allowed[k]);
  }
  get denied(): ElpianCapability[] {
    return (Object.keys(this.allowed) as ElpianCapability[]).filter((k) => this.allowed[k] === false);
  }
  toJson(): Record<string, boolean> {
    return { ...(this.allowed as Record<string, boolean>) };
  }
}

export type ElpianRunState = 'running' | 'pause_requested' | 'paused' | 'terminate_requested' | 'terminated';

export interface ElpianVmState {
  state: ElpianRunState;
  trapReason: string | null;
  processing: boolean;
}

export function vmStateFromJson(j: Record<string, any>): ElpianVmState {
  const states: ElpianRunState[] = ['running', 'pause_requested', 'paused', 'terminate_requested', 'terminated'];
  const s = states.includes(j.state) ? (j.state as ElpianRunState) : 'terminated';
  const r = typeof j.trapReason === 'string' && j.trapReason ? j.trapReason : null;
  return { state: s, trapReason: r, processing: j.processing === true };
}

export const isDead = (s: ElpianVmState) => s.state === 'terminated' || s.state === 'terminate_requested';
export const isTrapped = (s: ElpianVmState) => !!s.trapReason;

export interface ElpianVmTree {
  parent: string | null;
  children: string[];
  subtree: string[];
}

export function treeFromJson(j: Record<string, any>): ElpianVmTree {
  const list = (v: any) => (Array.isArray(v) ? v.map(String) : []);
  return { parent: typeof j.parent === 'string' ? j.parent : null, children: list(j.children), subtree: list(j.subtree) };
}

export interface ElpianBudgetViolation {
  machineId: string;
  axis: string;
  destroyed: string[];
}

export interface ElpianVmSnapshot {
  machineId: string;
  state: ElpianVmState;
  limits: ElpianLimits;
  usage: ElpianUsage;
  subtreeUsage: ElpianUsage;
  localCapabilities: ElpianCapabilities;
  effectiveCapabilities: ElpianCapabilities;
  tree: ElpianVmTree;
}

export function snapshotFromJson(j: Record<string, any>): ElpianVmSnapshot {
  const m = (v: any) => (isMap(v) ? v : {});
  return {
    machineId: String(j.machineId ?? ''),
    state: vmStateFromJson(m(j.state)),
    limits: Limits.fromJson(m(j.limits)),
    usage: usageFromJson(m(j.usage)),
    subtreeUsage: usageFromJson(m(j.subtreeUsage)),
    localCapabilities: ElpianCapabilities.fromJson(m(j.localCapabilities)),
    effectiveCapabilities: ElpianCapabilities.fromJson(m(j.effectiveCapabilities)),
    tree: treeFromJson(m(j.tree)),
  };
}

// ---------------------------------------------------------------------------
// Governor interfaces
// ---------------------------------------------------------------------------

export interface GovernanceSupport {
  capabilities: boolean;
  instructionBudget: boolean;
  memoryBudget: boolean;
  storageBudget: boolean;
  lifecycle: boolean;
  hierarchy: boolean;
}

export const FULL_SUPPORT: GovernanceSupport = Object.freeze({ capabilities: true, instructionBudget: true, memoryBudget: true, storageBudget: true, lifecycle: true, hierarchy: true });
export const NO_SUPPORT: GovernanceSupport = Object.freeze({ capabilities: false, instructionBudget: false, memoryBudget: false, storageBudget: false, lifecycle: false, hierarchy: false });
export const canSandboxUntrustedCode = (s: GovernanceSupport) => s.capabilities && s.instructionBudget;

export interface VmGovernor {
  readonly governanceSupport: GovernanceSupport;
  setLimits(limits: ElpianLimits): Promise<void>;
  getLimits(): Promise<ElpianLimits>;
  usage(): Promise<ElpianUsage>;
  subtreeUsage(): Promise<ElpianUsage>;
  setCapability(capability: ElpianCapability, allowed: boolean): Promise<void>;
  sandbox(granted: Iterable<ElpianCapability>): Promise<void>;
  localCapabilities(): Promise<ElpianCapabilities>;
  effectiveCapabilities(): Promise<ElpianCapabilities>;
  allowsApi(apiName: string): Promise<boolean>;
  state(): Promise<ElpianVmState>;
  pause(): Promise<void>;
  resumeExecution(): Promise<void>;
  terminate(): Promise<void>;
}

export interface VmTreeGovernor {
  adopt(parentId: string, childId: string): Promise<void>;
  tree(machineId: string): Promise<ElpianVmTree>;
  pauseTree(machineId: string): Promise<string[]>;
  terminateTree(machineId: string): Promise<string[]>;
  destroyTree(machineId: string): Promise<string[]>;
  enforceTreeBudgets(): Promise<ElpianBudgetViolation[]>;
  snapshot(machineId: string): Promise<ElpianVmSnapshot>;
}

// ---------------------------------------------------------------------------
// HostSideGovernor — QuickJS / WASM
// ---------------------------------------------------------------------------

/**
 * Governance enforced at the host-call seam, for the backends that give the
 * host no other one (QuickJS, WASM).
 */
export class HostSideGovernor implements VmGovernor {
  private limits: ElpianLimits = Limits.unlimited;
  private currentUsage: ElpianUsage = { ...ZERO_USAGE };
  private runState: ElpianRunState = 'running';
  private reason: string | null = null;
  private readonly caps = new Map<ElpianCapability, boolean>();
  private defaultAllow = true;

  constructor(
    readonly machineId: string,
    private readonly enforcesInstructions: boolean,
    private readonly hooks: { onTerminate?: () => void; onPause?: () => void; onResume?: () => void } = {},
  ) {}

  get governanceSupport(): GovernanceSupport {
    return { capabilities: true, instructionBudget: this.enforcesInstructions, memoryBudget: false, storageBudget: false, lifecycle: true, hierarchy: false };
  }

  get trapReason(): string | null {
    return this.reason;
  }

  /** Gate and meter one host call; returns the refusal reason or null. */
  checkAndCharge(apiName: string, bytes = 0): string | null {
    if (this.runState !== 'running') return `instance is ${this.runState}`;
    const capability = capabilityFromWireName(capabilityFor(apiName)) ?? 'other';
    if (!this.allows(capability)) return `capability ${capability} is denied`;
    const next = this.currentUsage.instructions + 1;
    const max = this.limits.maxInstructions;
    if (max != null && next > max) {
      this.trap(`host-call limit exceeded (${max})`);
      return this.reason;
    }
    const nextBytes = this.currentUsage.storageBytes + bytes;
    const maxBytes = this.limits.maxStorageBytes;
    if (maxBytes != null && nextBytes > maxBytes) {
      this.trap(`host-byte limit exceeded (${maxBytes})`);
      return this.reason;
    }
    this.currentUsage = { ...this.currentUsage, instructions: next, instructionsThisTurn: this.currentUsage.instructionsThisTurn + 1, storageBytes: nextBytes };
    return null;
  }

  chargeInstructions(steps: number): void {
    this.currentUsage = {
      ...this.currentUsage,
      instructions: this.currentUsage.instructions + steps,
      instructionsThisTurn: this.currentUsage.instructionsThisTurn + steps,
    };
    const max = this.limits.maxInstructions;
    if (max != null && this.currentUsage.instructions > max) this.trap(`instruction limit exceeded (${max})`);
  }

  beginTurn(): void {
    this.currentUsage = { ...this.currentUsage, instructionsThisTurn: 0 };
  }

  private trap(reason: string): void {
    this.reason ??= reason;
    this.runState = 'terminated';
    this.hooks.onTerminate?.();
  }

  private allows(c: ElpianCapability): boolean {
    return this.caps.get(c) ?? this.defaultAllow;
  }

  async setLimits(limits: ElpianLimits): Promise<void> {
    this.limits = { ...limits };
  }
  async getLimits(): Promise<ElpianLimits> {
    return { ...this.limits };
  }
  async usage(): Promise<ElpianUsage> {
    return { ...this.currentUsage };
  }
  async subtreeUsage(): Promise<ElpianUsage> {
    return { ...this.currentUsage };
  }
  async setCapability(capability: ElpianCapability, allowed: boolean): Promise<void> {
    this.caps.set(capability, allowed);
  }
  async sandbox(granted: Iterable<ElpianCapability>): Promise<void> {
    this.caps.clear();
    this.defaultAllow = false;
    for (const c of granted) this.caps.set(c, true);
  }
  async localCapabilities(): Promise<ElpianCapabilities> {
    const out: Partial<Record<ElpianCapability, boolean>> = {};
    for (const c of CAPABILITIES) out[c] = this.allows(c);
    return new ElpianCapabilities(out);
  }
  effectiveCapabilities(): Promise<ElpianCapabilities> {
    return this.localCapabilities();
  }
  async allowsApi(apiName: string): Promise<boolean> {
    return this.allows(capabilityFromWireName(capabilityFor(apiName)) ?? 'other');
  }
  async state(): Promise<ElpianVmState> {
    return { state: this.runState, trapReason: this.reason, processing: false };
  }
  async pause(): Promise<void> {
    if (this.runState === 'running') {
      this.runState = 'paused';
      this.hooks.onPause?.();
    }
  }
  async resumeExecution(): Promise<void> {
    if (this.runState === 'paused') {
      this.runState = 'running';
      this.hooks.onResume?.();
    }
  }
  async terminate(): Promise<void> {
    this.runState = 'terminated';
    this.hooks.onTerminate?.();
  }
}

/** A governor that refuses to pretend: every tightening call throws. */
export class UnenforcedGovernor implements VmGovernor {
  constructor(readonly reason: string) {}
  readonly governanceSupport = NO_SUPPORT;
  private unavailable(call: string): never {
    throw new ElpianGovernanceException(this.reason, call);
  }
  async setLimits(): Promise<void> {
    this.unavailable('setLimits');
  }
  async getLimits(): Promise<ElpianLimits> {
    return Limits.unlimited;
  }
  async usage(): Promise<ElpianUsage> {
    return { ...ZERO_USAGE };
  }
  async subtreeUsage(): Promise<ElpianUsage> {
    return { ...ZERO_USAGE };
  }
  async setCapability(): Promise<void> {
    this.unavailable('setCapability');
  }
  async sandbox(): Promise<void> {
    this.unavailable('sandbox');
  }
  async localCapabilities(): Promise<ElpianCapabilities> {
    return new ElpianCapabilities({});
  }
  async effectiveCapabilities(): Promise<ElpianCapabilities> {
    return new ElpianCapabilities({});
  }
  async allowsApi(): Promise<boolean> {
    return false;
  }
  async state(): Promise<ElpianVmState> {
    return { state: 'terminated', trapReason: null, processing: false };
  }
  async pause(): Promise<void> {}
  async resumeExecution(): Promise<void> {}
  async terminate(): Promise<void> {}
}

// ---------------------------------------------------------------------------
// Elpian VM governance (runtime-enforced)
// ---------------------------------------------------------------------------

function binding(): ElpianVmBinding | null {
  return hasPlatform() ? platform().elpianVm ?? null : null;
}

async function govCall(symbol: string, args: (string | number | boolean)[]): Promise<string> {
  const b = binding();
  if (!b || !b.isAvailable()) {
    throw new ElpianGovernanceException(`the Elpian runtime is not available${b?.lastError() ? `: ${b.lastError()}` : ''}`, symbol);
  }
  const raw = await b.governance(symbol, args);
  if (raw == null) throw new ElpianGovernanceException(`the loaded runtime does not export ${symbol} — rebuild it`, symbol);
  return raw;
}

const obj = async (symbol: string, args: (string | number | boolean)[]) => decodeGovernanceReply(await govCall(symbol, args), symbol);

async function list(symbol: string, args: (string | number | boolean)[]): Promise<any[]> {
  const raw = await govCall(symbol, args);
  let decoded: unknown;
  try {
    decoded = JSON.parse(raw);
  } catch (e) {
    throw new ElpianGovernanceException(`malformed reply: ${e}`, symbol);
  }
  if (Array.isArray(decoded)) return decoded;
  if (isMap(decoded) && typeof decoded.error === 'string') throw new ElpianGovernanceException(decoded.error, symbol);
  throw new ElpianGovernanceException(`expected an array, got ${raw}`, symbol);
}

let governanceProbe: boolean | null = null;

/** Whether the loaded runtime carries the governance surface (probed once). */
export async function elpianGovernanceAvailable(): Promise<boolean> {
  if (governanceProbe != null) return governanceProbe;
  const b = binding();
  if (!b || !b.isAvailable()) return false;
  try {
    governanceProbe = (await b.governance('elpian_usage', ['__elpian_probe__'])) != null;
  } catch {
    governanceProbe = false;
  }
  return governanceProbe;
}

export class ElpianVmGovernor implements VmGovernor {
  constructor(readonly machineId: string) {}

  get governanceSupport(): GovernanceSupport {
    const b = binding();
    return b && b.isAvailable() && governanceProbe !== false ? FULL_SUPPORT : NO_SUPPORT;
  }

  async setLimits(limits: ElpianLimits): Promise<void> {
    await obj('elpian_set_limits', [this.machineId, JSON.stringify(Limits.toJson(limits))]);
  }
  async getLimits(): Promise<ElpianLimits> {
    return Limits.fromJson(await obj('elpian_limits', [this.machineId]));
  }
  async usage(): Promise<ElpianUsage> {
    return usageFromJson(await obj('elpian_usage', [this.machineId]));
  }
  async subtreeUsage(): Promise<ElpianUsage> {
    return usageFromJson(await obj('elpian_subtree_usage', [this.machineId]));
  }
  async chargeStorage(deltaBytes: number): Promise<void> {
    await obj('elpian_charge_storage', [this.machineId, deltaBytes]);
  }
  async setCapability(capability: ElpianCapability, allowed: boolean): Promise<void> {
    await obj('elpian_set_capability', [this.machineId, capability, allowed ? 1 : 0]);
  }
  async setCapabilities(changes: Partial<Record<ElpianCapability, boolean>>): Promise<void> {
    await obj('elpian_set_capabilities', [this.machineId, JSON.stringify(changes)]);
  }
  async sandbox(granted: Iterable<ElpianCapability>): Promise<void> {
    await obj('elpian_sandbox_capabilities', [this.machineId, JSON.stringify([...granted])]);
  }
  async localCapabilities(): Promise<ElpianCapabilities> {
    return ElpianCapabilities.fromJson(await obj('elpian_local_capabilities', [this.machineId]));
  }
  async effectiveCapabilities(): Promise<ElpianCapabilities> {
    return ElpianCapabilities.fromJson(await obj('elpian_effective_capabilities', [this.machineId]));
  }
  async allowsApi(apiName: string): Promise<boolean> {
    return (await obj('elpian_capability_allows', [this.machineId, apiName])).allowed === true;
  }
  async state(): Promise<ElpianVmState> {
    return vmStateFromJson(await obj('elpian_state', [this.machineId]));
  }
  async pause(): Promise<void> {
    await obj('elpian_pause', [this.machineId]);
  }
  async resumeExecution(): Promise<void> {
    await obj('elpian_resume', [this.machineId]);
  }
  async terminate(): Promise<void> {
    await obj('elpian_terminate', [this.machineId]);
  }
}

export class ElpianTreeGovernor implements VmTreeGovernor {
  get isAvailable(): boolean {
    const b = binding();
    return !!b && b.isAvailable();
  }
  async adopt(parentId: string, childId: string): Promise<void> {
    await obj('elpian_adopt', [parentId, childId]);
  }
  async tree(machineId: string): Promise<ElpianVmTree> {
    return treeFromJson(await obj('elpian_tree', [machineId]));
  }
  private affected(reply: Record<string, any>): string[] {
    return Array.isArray(reply.affected) ? reply.affected.map(String) : [];
  }
  async pauseTree(machineId: string): Promise<string[]> {
    return this.affected(await obj('elpian_pause_tree', [machineId]));
  }
  async terminateTree(machineId: string): Promise<string[]> {
    return this.affected(await obj('elpian_terminate_tree', [machineId]));
  }
  async destroyTree(machineId: string): Promise<string[]> {
    return this.affected(await obj('elpian_destroy_tree', [machineId]));
  }
  async enforceTreeBudgets(): Promise<ElpianBudgetViolation[]> {
    return (await list('elpian_enforce_tree_budgets', []))
      .filter(isMap)
      .map((j) => ({ machineId: String(j.machineId ?? ''), axis: String(j.axis ?? 'unknown'), destroyed: Array.isArray(j.destroyed) ? j.destroyed.map(String) : [] }));
  }
  async snapshot(machineId: string): Promise<ElpianVmSnapshot> {
    return snapshotFromJson(await obj('elpian_snapshot', [machineId]));
  }
}
