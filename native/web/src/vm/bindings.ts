/**
 * The sandboxes the web platform provides to the core: the Elpian VM's
 * wasm-bindgen build (`elpian_wasm_*`), quickjs-emscripten for JS guests
 * (as the Flutter web build), and the browser's WebAssembly for WASM guests.
 * The core owns every runtime's protocol (host-call loop, `askHost` bridge,
 * WASM memory ABI, governance); the engines are the platform's.
 *
 * Calls may complete synchronously or return a promise; the core awaits both.
 */

export type MaybePromise<T> = T | Promise<T>;

/** The Elpian VM C ABI, one method per export the Flutter FFI layer binds. */
export interface ElpianVmBinding {
  /** Whether the runtime library is loaded. */
  isAvailable(): boolean;
  /** The last load/call error, for diagnostics (`ElpianVmApi.lastError`). */
  lastError(): string | null;
  init(): MaybePromise<void>;
  createFromAst(machineId: string, astJson: string): MaybePromise<boolean>;
  createFromCode(machineId: string, code: string): MaybePromise<boolean>;
  /** Bytecode as base64 (the bridges are string-typed). */
  createFromBytecode(machineId: string, bytecodeBase64: string): MaybePromise<boolean>;
  validateAst(astJson: string): MaybePromise<boolean>;
  /** Each returns the `VmExecResult` JSON (`hasHostCall`, `hostCallData`, `resultValue`). */
  execute(machineId: string): MaybePromise<string>;
  executeFunc(machineId: string, funcName: string, cbId: number): MaybePromise<string>;
  executeFuncWithInput(machineId: string, funcName: string, inputJson: string, cbId: number): MaybePromise<string>;
  continueExecution(machineId: string, inputJson: string): MaybePromise<string>;
  deliverHostMessage(machineId: string, messageJson: string, cbId: number): MaybePromise<string>;
  destroy(machineId: string): MaybePromise<boolean>;
  exists(machineId: string): MaybePromise<boolean>;
  /**
   * A governance export by its C name (`elpian_usage`, `elpian_set_limits`, …;
   * the web binding maps it to `elpian_wasm_*`). Returns the raw JSON reply,
   * or null when the loaded runtime does not export it.
   */
  governance(symbol: string, args: (string | number | boolean)[]): MaybePromise<string | null>;
}

/** One isolated guest JS engine. */
export interface JsSandbox {
  /**
   * Install the host bridge: the sandbox defines a synchronous
   * `__elpianHostCall(apiName, payloadJson)` global that calls [handler] and
   * returns its string reply.
   */
  setHostCallHandler(handler: (apiName: string, payload: string) => string): void;
  /** Evaluate [code]; returns the completion value stringified (flutter_js `stringResult`). */
  evaluate(code: string): MaybePromise<string>;
  dispose(): void;
}

export interface JsSandboxFactory {
  create(machineId: string): MaybePromise<JsSandbox>;
}

/** Imported-function callback: numbers in, numbers out. */
export type WasmImportHandler = (module: string, name: string, args: number[]) => number[];

export interface WasmInstanceHandle {
  hasExport(name: string): boolean;
  call(exportName: string, args: number[]): number[];
  memoryLength(memoryExport: string): number;
  /** Bytes as base64 on bridged platforms is handled by the binding; the core sees bytes. */
  memoryRead(memoryExport: string, ptr: number, length: number): Uint8Array;
  memoryWrite(memoryExport: string, ptr: number, bytes: Uint8Array): void;
  dispose(): void;
}

export interface WasmEngine {
  /**
   * Compile and instantiate [bytes]. Every function import is bound to
   * [onImport]; the instance is returned once its start function has run.
   */
  instantiate(bytes: Uint8Array, onImport: WasmImportHandler): MaybePromise<WasmInstanceHandle>;
}

/** The sandbox engines a platform offers (absent ones make that runtime unavailable). */
export interface RuntimeBindings {
  elpianVm?: ElpianVmBinding;
  jsSandbox?: JsSandboxFactory;
  wasm?: WasmEngine;
}
