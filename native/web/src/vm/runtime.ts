/**
 * The three guest runtimes behind one client interface — ports of
 * `VmRuntimeClient`, `ElpianVm`, `QuickJsVm` and `WasmVm`
 * (flutter/lib/src/vm/*.dart). The protocols live here; the engines are the
 * platform's (see bindings.ts).
 */
import { platform } from '../platform/platform.js';
import { base64Decode, utf8Decode, utf8Encode } from '../util/bytes.js';
import { isMap } from '../util/json.js';
import { NULL_RESPONSE, OK_RESPONSE } from '../util/typed.js';
import type { ElpianVmBinding, JsSandbox, WasmInstanceHandle } from './bindings.js';
import { ElpianTreeGovernor, ElpianVmGovernor, HostSideGovernor, type VmGovernor } from './governance.js';

export type HostCallHandler = (apiName: string, payload: string) => string | Promise<string>;

export type RuntimeKind = 'elpian' | 'quickjs' | 'wasm';

export interface VmRuntimeClient {
  readonly machineId: string;
  readonly governor: VmGovernor;
  registerHostHandler(apiName: string, handler: HostCallHandler): void;
  registerHostHandlers(handlers: Record<string, HostCallHandler>): void;
  setDefaultHostHandler(handler: HostCallHandler): void;
  setGlobalHostData(data: Record<string, any>): Promise<void>;
  run(): Promise<string>;
  callFunction(funcName: string): Promise<string>;
  callFunctionWithInput(funcName: string, inputJson: string): Promise<string>;
  dispose(): Promise<void>;
}

interface VmExecResult {
  hasHostCall: boolean;
  hostCallData: string;
  resultValue: string;
}

function parseExecResult(raw: string): VmExecResult {
  try {
    const j = JSON.parse(raw);
    return {
      hasHostCall: j?.hasHostCall === true,
      hostCallData: typeof j?.hostCallData === 'string' ? j.hostCallData : '',
      resultValue: typeof j?.resultValue === 'string' ? j.resultValue : '',
    };
  } catch {
    return { hasHostCall: false, hostCallData: '', resultValue: '' };
  }
}

function errorResult(reason: string): string {
  return JSON.stringify({ hasHostCall: false, hostCallData: '', resultValue: JSON.stringify({ error: reason }) });
}

function log(message: string): void {
  try {
    platform().log('debug', message);
  } catch {
    /* no platform yet */
  }
}

/** Shared registry/fallback behaviour of every client. */
abstract class BaseClient {
  protected readonly hostHandlers = new Map<string, HostCallHandler>();
  protected defaultHostHandler: HostCallHandler | null = null;
  protected globalHostData: Record<string, any> = {};

  constructor(readonly machineId: string) {}

  registerHostHandler(apiName: string, handler: HostCallHandler): void {
    this.hostHandlers.set(apiName, handler);
  }
  registerHostHandlers(handlers: Record<string, HostCallHandler>): void {
    for (const [k, v] of Object.entries(handlers)) this.hostHandlers.set(k, v);
  }
  setDefaultHostHandler(handler: HostCallHandler): void {
    this.defaultHostHandler = handler;
  }

  /** The built-ins every runtime answers when no handler is registered. */
  protected builtin(label: string, apiName: string, payload: string): string {
    switch (apiName) {
      case 'println':
        log(`${label}[${this.machineId}]: ${payload}`);
        return OK_RESPONSE;
      case 'env.get':
        return JSON.stringify({ type: 'object', data: { value: this.globalHostData } });
      case 'stringify':
        return JSON.stringify({ type: 'string', data: { value: payload } });
      default:
        log(`${label}: Unhandled host call: ${apiName}`);
        return OK_RESPONSE;
    }
  }
}

// ============================================================================
// Elpian VM
// ============================================================================

export class ElpianVm extends BaseClient implements VmRuntimeClient {
  private cbCounter = 0;
  private running = false;
  readonly governor: ElpianVmGovernor;
  static readonly treeGovernor = new ElpianTreeGovernor();

  constructor(machineId: string) {
    super(machineId);
    this.governor = new ElpianVmGovernor(machineId);
  }

  static binding(): ElpianVmBinding | null {
    return platform().elpianVm ?? null;
  }

  static get isRuntimeAvailable(): boolean {
    return ElpianVm.binding()?.isAvailable() ?? false;
  }

  static get lastApiError(): string | null {
    return ElpianVm.binding()?.lastError() ?? 'no Elpian VM binding on this platform';
  }

  static async initialize(): Promise<void> {
    await ElpianVm.binding()?.init();
  }

  private static require(): ElpianVmBinding {
    const b = ElpianVm.binding();
    if (!b || !b.isAvailable()) throw new Error(`Elpian VM runtime unavailable: ${ElpianVm.lastApiError}`);
    return b;
  }

  static async fromAst(machineId: string, astJson: string): Promise<ElpianVm | null> {
    return (await ElpianVm.require().createFromAst(machineId, astJson)) ? new ElpianVm(machineId) : null;
  }
  static async fromCode(machineId: string, code: string): Promise<ElpianVm | null> {
    return (await ElpianVm.require().createFromCode(machineId, code)) ? new ElpianVm(machineId) : null;
  }
  /** [bytecode] as base64. */
  static async fromBytecode(machineId: string, bytecodeBase64: string): Promise<ElpianVm | null> {
    return (await ElpianVm.require().createFromBytecode(machineId, bytecodeBase64)) ? new ElpianVm(machineId) : null;
  }
  static async validateAst(astJson: string): Promise<boolean> {
    return (await ElpianVm.binding()?.validateAst(astJson)) ?? false;
  }

  get isRunning(): boolean {
    return this.running;
  }

  async setGlobalHostData(data: Record<string, any>): Promise<void> {
    this.globalHostData = { ...data };
  }

  async run(): Promise<string> {
    this.running = true;
    try {
      const b = ElpianVm.binding();
      return await this.loop(b ? await b.execute(this.machineId) : errorResult('native_lib_not_loaded'));
    } finally {
      this.running = false;
    }
  }

  async callFunction(funcName: string): Promise<string> {
    this.running = true;
    const cb = ++this.cbCounter;
    try {
      const b = ElpianVm.binding();
      return await this.loop(b ? await b.executeFunc(this.machineId, funcName, cb) : errorResult('native_lib_not_loaded'));
    } finally {
      this.running = false;
    }
  }

  async callFunctionWithInput(funcName: string, inputJson: string): Promise<string> {
    this.running = true;
    const cb = ++this.cbCounter;
    try {
      const b = ElpianVm.binding();
      return await this.loop(b ? await b.executeFuncWithInput(this.machineId, funcName, inputJson, cb) : errorResult('native_lib_not_loaded'));
    } finally {
      this.running = false;
    }
  }

  async deliverHostMessage(messageJson: string): Promise<string> {
    const cb = ++this.cbCounter;
    const b = ElpianVm.binding();
    return this.loop(b ? await b.deliverHostMessage(this.machineId, messageJson, cb) : errorResult('native_lib_not_loaded'));
  }

  /** hasHostCall → handle → continueExecution, until the VM yields a value. */
  private async loop(raw: string): Promise<string> {
    let result = parseExecResult(raw);
    const b = ElpianVm.binding();
    while (result.hasHostCall && b) {
      let apiName = '';
      let payload = '';
      try {
        const data = JSON.parse(result.hostCallData);
        apiName = String(data.apiName ?? '');
        // Typed JSON payloads (Victor) and pre-serialised ones (legacy VM).
        payload = typeof data.payload === 'string' ? data.payload : JSON.stringify(data.payload ?? null);
      } catch (e) {
        log(`ElpianVm: malformed host call: ${e}`);
      }
      let response: string;
      try {
        response = await this.handle(apiName, payload);
      } catch (e) {
        log(`ElpianVm: Host call error for ${apiName}: ${e}`);
        response = JSON.stringify({ type: 'string', data: { value: `error: ${e}` } });
      }
      result = parseExecResult(await b.continueExecution(this.machineId, response));
    }
    return result.resultValue;
  }

  private async handle(apiName: string, payload: string): Promise<string> {
    const h = this.hostHandlers.get(apiName) ?? this.defaultHostHandler;
    if (h) return await h(apiName, payload);
    return this.builtin('ElpianVm', apiName, payload);
  }

  async dispose(): Promise<void> {
    await ElpianVm.binding()?.destroy(this.machineId);
  }
}

// ============================================================================
// QuickJS (JS guest sandbox)
// ============================================================================

/** The guest-side `askHost` — byte-for-byte the bootstrap `QuickJsVm` installs. */
export const ASK_HOST_BOOTSTRAP = `
globalThis.askHost = function(apiName) {
  var args = Array.prototype.slice.call(arguments, 1);
  var payload = '';
  if (args.length === 1) {
    payload = args[0];
  } else if (args.length > 1) {
    payload = args;
  }
  var encoded = typeof payload === 'string' ? payload : JSON.stringify(payload);
  return __elpianHostCall(String(apiName), encoded === undefined ? 'null' : encoded);
};
`;

export class QuickJsVm extends BaseClient implements VmRuntimeClient {
  private sandbox: JsSandbox | null = null;
  private bootCode: string | null = null;
  private disposed = false;
  readonly governor: HostSideGovernor;

  constructor(machineId: string) {
    super(machineId);
    this.governor = new HostSideGovernor(machineId, false, { onTerminate: () => void this.dispose() });
  }

  static get isRuntimeAvailable(): boolean {
    return platform().jsSandbox != null;
  }

  static async fromCode(machineId: string, code: string): Promise<QuickJsVm> {
    const factory = platform().jsSandbox;
    if (!factory) throw new Error('QuickJS runtime unavailable: the platform provides no JS sandbox');
    const vm = new QuickJsVm(machineId);
    vm.sandbox = await factory.create(machineId);
    vm.sandbox.setHostCallHandler((api, payload) => vm.dispatchHostCall(api, payload));
    await vm.sandbox.evaluate(ASK_HOST_BOOTSTRAP);
    vm.bootCode = code;
    return vm;
  }

  static async fromAst(): Promise<QuickJsVm> {
    throw new Error('QuickJS runtime expects JavaScript source in `code`; AST JSON is only supported by the Elpian runtime.');
  }

  async setGlobalHostData(data: Record<string, any>): Promise<void> {
    this.globalHostData = { ...data };
    if (!this.sandbox) return;
    const encoded = JSON.stringify(JSON.stringify(this.globalHostData));
    await this.sandbox.evaluate(`(function() {
  var __env = JSON.parse(${encoded});
  globalThis.__ELPIAN_HOST_ENV__ = __env;
  globalThis.ELPIAN_HOST_ENV = __env;
  globalThis.getElpianHostEnv = function() { return globalThis.__ELPIAN_HOST_ENV__; };
})();`);
  }

  async runCode(code: string): Promise<string> {
    if (!this.sandbox || this.disposed) return '';
    this.governor.beginTurn();
    return await this.sandbox.evaluate(code);
  }

  async run(): Promise<string> {
    if (!this.bootCode) return '';
    return this.runCode(this.bootCode);
  }

  async callFunction(funcName: string): Promise<string> {
    return this.runCode(`${funcName}();`);
  }

  async callFunctionWithInput(funcName: string, inputJson: string): Promise<string> {
    return this.runCode(`${funcName}(JSON.parse(${JSON.stringify(inputJson)}));`);
  }

  /** The capability gate: every QuickJS host call crosses here. */
  private dispatchHostCall(apiName: string, payload: string): string {
    const refusal = this.governor.checkAndCharge(apiName, payload.length);
    if (refusal != null) {
      log(`QuickJs[${this.machineId}]: ${apiName} refused — ${refusal}`);
      return NULL_RESPONSE;
    }
    const h = this.hostHandlers.get(apiName) ?? this.defaultHostHandler;
    if (h) {
      const r = h(apiName, payload);
      // Guests call askHost synchronously; an async handler's reply cannot
      // reach them (same contract as flutter_js `sendMessage`).
      return typeof r === 'string' ? r : OK_RESPONSE;
    }
    return this.builtin('QuickJsVm', apiName, payload);
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    this.sandbox?.dispose();
    this.sandbox = null;
  }
}

// ============================================================================
// WASM
// ============================================================================

interface WasmVmExports {
  memory: string;
  alloc: string;
  dealloc: string;
  run: string;
  callFunction: string;
  callFunctionWithInput: string;
  getResultPtr: string;
  getResultLen: string;
}

interface WasmVmConfig {
  wasmBase64: string | null;
  wasmAssetPath: string | null;
  exports: WasmVmExports;
}

function parseWasmConfig(source: string): WasmVmConfig {
  const raw = JSON.parse(source);
  if (!isMap(raw)) throw new Error('WASM runtime config must be a JSON object.');
  const e = isMap(raw.exports) ? raw.exports : {};
  const s = (v: any, d: string) => (v == null ? d : String(v));
  return {
    wasmBase64: raw.wasmBase64 != null ? String(raw.wasmBase64) : null,
    wasmAssetPath: raw.wasmAssetPath != null ? String(raw.wasmAssetPath) : null,
    exports: {
      memory: s(e.memory, 'memory'),
      alloc: s(e.alloc, 'alloc'),
      dealloc: s(e.dealloc, 'dealloc'),
      run: s(e.run, 'run'),
      callFunction: s(e.callFunction, 'call_function'),
      callFunctionWithInput: s(e.callFunctionWithInput, 'call_function_with_input'),
      getResultPtr: s(e.getResultPtr, 'get_result_ptr'),
      getResultLen: s(e.getResultLen, 'get_result_len'),
    },
  };
}

export class WasmVm extends BaseClient implements VmRuntimeClient {
  private instance: WasmInstanceHandle | null = null;
  private config: WasmVmConfig | null = null;
  private bootCode: string | null = null;
  readonly governor: HostSideGovernor;

  constructor(machineId: string) {
    super(machineId);
    this.governor = new HostSideGovernor(machineId, true, { onTerminate: () => void this.dispose() });
  }

  static get isRuntimeAvailable(): boolean {
    return platform().wasm != null;
  }

  static async fromCode(machineId: string, code: string): Promise<WasmVm> {
    const vm = new WasmVm(machineId);
    vm.bootCode = code;
    return vm;
  }

  static async fromAst(): Promise<WasmVm> {
    throw new Error('WASM runtime expects JSON runtime config in `code`.');
  }

  async setGlobalHostData(data: Record<string, any>): Promise<void> {
    this.globalHostData = { ...data };
  }

  async run(): Promise<string> {
    if (!this.bootCode) return '';
    await this.ensureLoaded(this.bootCode);
    this.governor.beginTurn();
    this.require(this.config!.exports.run, []);
    return this.readResult();
  }

  async callFunction(funcName: string): Promise<string> {
    this.assertLoaded();
    this.governor.beginTurn();
    const fn = this.writeString(funcName);
    try {
      this.require(this.config!.exports.callFunction, [fn.ptr, fn.length]);
      return this.readResult();
    } finally {
      this.dealloc(fn);
    }
  }

  async callFunctionWithInput(funcName: string, inputJson: string): Promise<string> {
    this.assertLoaded();
    this.governor.beginTurn();
    const fn = this.writeString(funcName);
    const input = this.writeString(inputJson);
    try {
      this.require(this.config!.exports.callFunctionWithInput, [fn.ptr, fn.length, input.ptr, input.length]);
      return this.readResult();
    } finally {
      this.dealloc(fn);
      this.dealloc(input);
    }
  }

  private async ensureLoaded(configJson: string): Promise<void> {
    if (this.instance) return;
    const engine = platform().wasm;
    if (!engine) throw new Error('WASM runtime unavailable: the platform provides no WebAssembly engine');
    const config = parseWasmConfig(configJson);
    const bytes = await loadWasmBytes(config);
    this.config = config;
    this.instance = await engine.instantiate(bytes, (_module, name, args) => this.onImport(name, args));
    if (!this.instance.hasExport(config.exports.memory)) throw new Error(`WASM memory export not found: ${config.exports.memory}`);
  }

  private onImport(name: string, args: number[]): number[] {
    if (name !== 'elpian_host_call' || args.length < 6 || !this.instance) return [0];
    const [apiPtr, apiLen, payloadPtr, payloadLen, outPtr, outCap] = args.map((a) => Math.trunc(Number(a)));
    const apiName = this.readString(apiPtr, apiLen);
    const payload = this.readString(payloadPtr, payloadLen);
    return [this.writeInto(this.dispatchHostCall(apiName, payload), outPtr, outCap)];
  }

  private dispatchHostCall(apiName: string, payload: string): string {
    const refusal = this.governor.checkAndCharge(apiName, payload.length);
    if (refusal != null) {
      log(`WasmVm[${this.machineId}]: ${apiName} refused — ${refusal}`);
      return NULL_RESPONSE;
    }
    const h = this.hostHandlers.get(apiName) ?? this.defaultHostHandler;
    if (h) {
      const r = h(apiName, payload);
      return typeof r === 'string' ? r : OK_RESPONSE;
    }
    return this.builtin('WasmVm', apiName, payload);
  }

  private require(name: string, args: number[]): number[] {
    if (!this.instance) throw new Error('WASM instance is not loaded.');
    if (!this.instance.hasExport(name)) throw new Error(`WASM function export not found: ${name}`);
    return this.instance.call(name, args);
  }

  private writeString(text: string): { ptr: number; length: number } {
    const bytes = utf8Encode(text);
    const ptr = Math.trunc(Number(this.require(this.config!.exports.alloc, [bytes.length])[0] ?? 0));
    if (ptr <= 0) throw new Error(`WASM alloc returned invalid pointer for length ${bytes.length}.`);
    const mem = this.config!.exports.memory;
    if (ptr + bytes.length > this.instance!.memoryLength(mem)) throw new Error(`WASM memory write out of range (ptr=${ptr} len=${bytes.length}).`);
    this.instance!.memoryWrite(mem, ptr, bytes);
    return { ptr, length: bytes.length };
  }

  private writeInto(text: string, ptr: number, capacity: number): number {
    if (capacity <= 0) return 0;
    const bytes = utf8Encode(text);
    const length = Math.min(bytes.length, capacity);
    const mem = this.config!.exports.memory;
    if (ptr < 0 || ptr + length > this.instance!.memoryLength(mem)) return 0;
    this.instance!.memoryWrite(mem, ptr, bytes.subarray(0, length));
    return length;
  }

  private readString(ptr: number, len: number): string {
    if (len <= 0) return '';
    const mem = this.config!.exports.memory;
    if (ptr < 0 || ptr + len > this.instance!.memoryLength(mem)) return '';
    return utf8Decode(this.instance!.memoryRead(mem, ptr, len));
  }

  private readResult(): string {
    const ptr = Math.trunc(Number(this.require(this.config!.exports.getResultPtr, [])[0] ?? 0));
    const len = Math.trunc(Number(this.require(this.config!.exports.getResultLen, [])[0] ?? 0));
    if (ptr <= 0 || len <= 0) return '';
    return this.readString(ptr, len);
  }

  private dealloc(text: { ptr: number; length: number }): void {
    const name = this.config?.exports.dealloc;
    if (!name || !this.instance || !this.instance.hasExport(name)) return;
    this.instance.call(name, [text.ptr, text.length]);
  }

  private assertLoaded(): void {
    if (!this.instance || !this.config) throw new Error('WASM runtime is not initialized. Call run() first.');
  }

  async dispose(): Promise<void> {
    this.instance?.dispose();
    this.instance = null;
    this.config = null;
  }
}

async function loadWasmBytes(config: WasmVmConfig): Promise<Uint8Array> {
  if (config.wasmBase64) return base64Decode(config.wasmBase64);
  if (!config.wasmAssetPath) throw new Error('WASM config must provide either `wasmBase64` or `wasmAssetPath`.');
  const load = platform().loadAsset;
  if (!load) throw new Error('This platform cannot load bundled assets.');
  return base64Decode(await load(config.wasmAssetPath, 'base64'));
}

// ============================================================================
// Factory
// ============================================================================

export function isRuntimeAvailable(kind: RuntimeKind): boolean {
  switch (kind) {
    case 'elpian':
      return ElpianVm.isRuntimeAvailable;
    case 'quickjs':
      return QuickJsVm.isRuntimeAvailable;
    case 'wasm':
      return WasmVm.isRuntimeAvailable;
  }
}

export async function initializeRuntime(kind: RuntimeKind): Promise<void> {
  if (kind === 'elpian') await ElpianVm.initialize();
}

/**
 * Create a client from source the way `ElpianVmWidget` does: `code` (JS for
 * QuickJS, the JSON config for WASM, Elpian source for the VM) or an AST.
 */
export async function createRuntime(kind: RuntimeKind, machineId: string, source: { code?: string | null; astJson?: string | null; bytecodeBase64?: string | null }): Promise<VmRuntimeClient | null> {
  switch (kind) {
    case 'elpian':
      if (source.bytecodeBase64) return ElpianVm.fromBytecode(machineId, source.bytecodeBase64);
      if (source.astJson) return ElpianVm.fromAst(machineId, source.astJson);
      if (source.code != null) return ElpianVm.fromCode(machineId, source.code);
      return null;
    case 'quickjs':
      if (source.code == null) return QuickJsVm.fromAst();
      return QuickJsVm.fromCode(machineId, source.code);
    case 'wasm':
      if (source.code == null) return WasmVm.fromAst();
      return WasmVm.fromCode(machineId, source.code);
  }
}
