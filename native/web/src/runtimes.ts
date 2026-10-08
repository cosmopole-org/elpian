/**
 * The sandboxes in the browser:
 *
 *  - Elpian VM — the wasm-bindgen build of rust/crates/elpian-vm
 *    (`elpian_wasm_*`), loaded on first use.
 *  - QuickJS guests — quickjs-emscripten (RELEASE_SYNC), one context per mini
 *    app, isolated from the page; `__elpianHostCall` is the only way out.
 *  - WASM guests — the browser's WebAssembly, every function import bound to
 *    the core's host-call dispatcher.
 */
import type { ElpianVmBinding, JsSandbox, JsSandboxFactory, WasmEngine, WasmImportHandler, WasmInstanceHandle } from '@elpian/native-core';
import { base64Decode } from '@elpian/native-core';

export interface RuntimeAssets {
  /** URL of `elpian_vm.js` (wasm-bindgen glue; the .wasm sits next to it). */
  elpianVmModule: string;
  /** URL of the vendored `quickjs-emscripten.mjs` and its `.wasm`. */
  quickJsModule: string;
  quickJsWasm: string;
}

// ---------------------------------------------------------------------------
// Elpian VM
// ---------------------------------------------------------------------------

export class WebElpianVm implements ElpianVmBinding {
  private mod: Record<string, any> | null = null;
  private loading: Promise<void> | null = null;
  private error: string | null = null;

  constructor(private readonly moduleUrl: string) {}

  isAvailable(): boolean {
    // Before init() the module is not loaded yet; report available unless a
    // load has already failed, so sessions call init() and find out.
    return this.mod != null || (this.loading == null && this.error == null) || this.loading != null;
  }

  lastError(): string | null {
    return this.error;
  }

  init(): Promise<void> {
    return (this.loading ??= (async () => {
      try {
        const m = await import(/* @vite-ignore */ this.moduleUrl);
        await m.default();
        m.elpian_wasm_init?.();
        this.mod = m;
      } catch (e) {
        this.error = `Elpian VM wasm module failed to load from ${this.moduleUrl}: ${e}`;
        throw new Error(this.error);
      }
    })());
  }

  private fn(name: string): (...args: any[]) => any {
    const f = this.mod?.[name];
    if (typeof f !== 'function') throw new Error(`the loaded Elpian VM does not export ${name}`);
    return f;
  }

  createFromAst(id: string, ast: string): boolean {
    return !!this.fn('elpian_wasm_create_vm_from_ast')(id, ast);
  }
  createFromCode(id: string, code: string): boolean {
    return !!this.fn('elpian_wasm_create_vm_from_code')(id, code);
  }
  createFromBytecode(id: string, b64: string): boolean {
    return !!this.fn('elpian_wasm_create_vm_from_bytecode')(id, base64Decode(b64));
  }
  validateAst(ast: string): boolean {
    return !!this.fn('elpian_wasm_validate_ast')(ast);
  }
  execute(id: string): string {
    return String(this.fn('elpian_wasm_execute')(id));
  }
  executeFunc(id: string, fn: string, cb: number): string {
    return String(this.fn('elpian_wasm_execute_func')(id, fn, cb));
  }
  executeFuncWithInput(id: string, fn: string, input: string, cb: number): string {
    return String(this.fn('elpian_wasm_execute_func_with_input')(id, fn, input, cb));
  }
  continueExecution(id: string, input: string): string {
    return String(this.fn('elpian_wasm_continue_execution')(id, input));
  }
  deliverHostMessage(id: string, msg: string, cb: number): string {
    return String(this.fn('elpian_wasm_deliver_host_message')(id, msg, cb));
  }
  destroy(id: string): boolean {
    return !!this.mod && !!this.fn('elpian_wasm_destroy_vm')(id);
  }
  exists(id: string): boolean {
    return !!this.mod && !!this.fn('elpian_wasm_vm_exists')(id);
  }
  governance(symbol: string, args: (string | number | boolean)[]): string | null {
    const name = symbol.startsWith('elpian_wasm_') ? symbol : symbol.replace(/^elpian_/, 'elpian_wasm_');
    const f = this.mod?.[name];
    if (typeof f !== 'function') return null;
    // `elpian_set_capability`'s flag is a bool on the wasm build.
    const wasmArgs = name === 'elpian_wasm_set_capability' && args.length > 2 ? [args[0], args[1], args[2] === true || args[2] === 1] : args;
    return String(f(...wasmArgs));
  }
}

// ---------------------------------------------------------------------------
// QuickJS
// ---------------------------------------------------------------------------

export class WebQuickJs implements JsSandboxFactory {
  private module: Promise<any> | null = null;

  constructor(
    private readonly moduleUrl: string,
    private readonly wasmUrl: string,
  ) {}

  private load(): Promise<any> {
    return (this.module ??= (async () => {
      const mod = await import(/* @vite-ignore */ this.moduleUrl);
      const res = await fetch(this.wasmUrl);
      if (!res.ok) throw new Error(`QuickJS wasm: HTTP ${res.status} from ${this.wasmUrl}`);
      const wasmBinary = await res.arrayBuffer();
      const variant = mod.newVariant(mod.RELEASE_SYNC, { wasmBinary });
      return mod.newQuickJSWASMModule(variant);
    })());
  }

  async create(_machineId: string): Promise<JsSandbox> {
    const qjs = await this.load();
    const ctx = qjs.newContext();
    let handler: (api: string, payload: string) => string = () => '{"type":"i16","data":{"value":0}}';
    const hostCall = ctx.newFunction('__elpianHostCall', (apiH: any, payloadH: any) => {
      try {
        const api = String(ctx.dump(apiH) ?? '');
        const payload = String(ctx.dump(payloadH) ?? '');
        return ctx.newString(handler(api, payload));
      } catch {
        return ctx.newString('{"type":"null","data":{"value":null}}');
      }
    });
    ctx.setProp(ctx.global, '__elpianHostCall', hostCall);
    hostCall.dispose();
    // Microtasks the guest queues (promises) run after each evaluation.
    const runJobs = () => {
      try {
        ctx.runtime.executePendingJobs();
      } catch {
        /* a failing job is the guest's problem */
      }
    };
    let disposed = false;
    return {
      setHostCallHandler(h) {
        handler = h;
      },
      evaluate(code: string): string {
        if (disposed) return '';
        const result = ctx.evalCode(code);
        if (result.error) {
          const err = ctx.dump(result.error);
          result.error.dispose();
          runJobs();
          throw new Error(`QuickJS eval error: ${typeof err === 'object' ? JSON.stringify(err) : String(err)}`);
        }
        const value = ctx.dump(result.value);
        result.value.dispose();
        runJobs();
        return typeof value === 'string' ? value : value === undefined ? 'undefined' : JSON.stringify(value);
      },
      dispose() {
        if (disposed) return;
        disposed = true;
        ctx.dispose();
      },
    };
  }
}

// ---------------------------------------------------------------------------
// WebAssembly
// ---------------------------------------------------------------------------

export class WebWasmEngine implements WasmEngine {
  async instantiate(bytes: Uint8Array, onImport: WasmImportHandler): Promise<WasmInstanceHandle> {
    const module = await WebAssembly.compile(bytes as BufferSource);
    const imports: Record<string, Record<string, any>> = {};
    for (const imp of WebAssembly.Module.imports(module)) {
      if (imp.kind !== 'function') continue;
      (imports[imp.module] ??= {})[imp.name] = (...args: (number | bigint)[]) => {
        const out = onImport(imp.module, imp.name, args.map((a) => Number(a)));
        return out.length ? out[0] : undefined;
      };
    }
    const instance = await WebAssembly.instantiate(module, imports);
    const exports = instance.exports as Record<string, any>;
    const memory = (name: string): WebAssembly.Memory => {
      const m = exports[name];
      if (m instanceof WebAssembly.Memory) return m;
      const any = Object.values(exports).find((v) => v instanceof WebAssembly.Memory);
      if (!any) throw new Error(`WASM memory export not found: ${name}`);
      return any as WebAssembly.Memory;
    };
    return {
      hasExport: (name) => name in exports,
      call(name, args) {
        const f = exports[name];
        if (typeof f !== 'function') throw new Error(`WASM function export not found: ${name}`);
        const r = f(...args);
        if (r === undefined) return [];
        return Array.isArray(r) ? r.map(Number) : [Number(r)];
      },
      memoryLength: (name) => memory(name).buffer.byteLength,
      memoryRead: (name, ptr, len) => new Uint8Array(memory(name).buffer, ptr, len).slice(),
      memoryWrite: (name, ptr, data) => new Uint8Array(memory(name).buffer, ptr, data.length).set(data),
      dispose() {
        /* garbage collected */
      },
    };
  }
}
