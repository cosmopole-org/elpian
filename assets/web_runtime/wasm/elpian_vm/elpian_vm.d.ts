/* tslint:disable */
/* eslint-disable */

export function elpian_wasm_continue_execution(machine_id: string, input_json: string): string;

export function elpian_wasm_create_vm_from_ast(machine_id: string, ast_json: string): boolean;

export function elpian_wasm_create_vm_from_bytecode(machine_id: string, bytecode: Uint8Array): boolean;

export function elpian_wasm_create_vm_from_code(machine_id: string, code: string): boolean;

export function elpian_wasm_deliver_host_message(machine_id: string, message_json: string, cb_id: number): string;

export function elpian_wasm_destroy_vm(machine_id: string): boolean;

export function elpian_wasm_execute(machine_id: string): string;

export function elpian_wasm_execute_func(machine_id: string, name: string, cb_id: number): string;

export function elpian_wasm_execute_func_with_input(machine_id: string, name: string, input_json: string, cb_id: number): string;

export function elpian_wasm_init(): void;

export function elpian_wasm_validate_ast(ast_json: string): boolean;

export function elpian_wasm_vm_exists(machine_id: string): boolean;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly elpian_wasm_continue_execution: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_create_vm_from_ast: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_create_vm_from_bytecode: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_create_vm_from_code: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_deliver_host_message: (a: number, b: number, c: number, d: number, e: number) => [number, number];
    readonly elpian_wasm_destroy_vm: (a: number, b: number) => number;
    readonly elpian_wasm_execute: (a: number, b: number) => [number, number];
    readonly elpian_wasm_execute_func: (a: number, b: number, c: number, d: number, e: number) => [number, number];
    readonly elpian_wasm_execute_func_with_input: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => [number, number];
    readonly elpian_wasm_validate_ast: (a: number, b: number) => number;
    readonly elpian_wasm_vm_exists: (a: number, b: number) => number;
    readonly elpian_wasm_init: () => void;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
