/* tslint:disable */
/* eslint-disable */

export function elpian_wasm_adopt(parent_id: string, child_id: string): string;

export function elpian_wasm_capability_allows(machine_id: string, api_name: string): string;

export function elpian_wasm_charge_storage(machine_id: string, delta: number): string;

export function elpian_wasm_continue_execution(machine_id: string, input_json: string): string;

export function elpian_wasm_create_vm_from_ast(machine_id: string, ast_json: string): boolean;

export function elpian_wasm_create_vm_from_bytecode(machine_id: string, bytecode: Uint8Array): boolean;

export function elpian_wasm_create_vm_from_code(machine_id: string, code: string): boolean;

export function elpian_wasm_deliver_host_message(machine_id: string, message_json: string, cb_id: number): string;

export function elpian_wasm_destroy_tree(machine_id: string): string;

export function elpian_wasm_destroy_vm(machine_id: string): boolean;

export function elpian_wasm_effective_capabilities(machine_id: string): string;

export function elpian_wasm_enforce_tree_budgets(): string;

export function elpian_wasm_execute(machine_id: string): string;

export function elpian_wasm_execute_func(machine_id: string, name: string, cb_id: number): string;

export function elpian_wasm_execute_func_with_input(machine_id: string, name: string, input_json: string, cb_id: number): string;

export function elpian_wasm_init(): void;

export function elpian_wasm_limits(machine_id: string): string;

export function elpian_wasm_local_capabilities(machine_id: string): string;

export function elpian_wasm_pause(machine_id: string): string;

export function elpian_wasm_pause_tree(machine_id: string): string;

export function elpian_wasm_resume(machine_id: string): string;

export function elpian_wasm_sandbox_capabilities(machine_id: string, granted_json: string): string;

export function elpian_wasm_set_capabilities(machine_id: string, caps_json: string): string;

export function elpian_wasm_set_capability(machine_id: string, capability: string, allowed: boolean): string;

export function elpian_wasm_set_limits(machine_id: string, limits_json: string): string;

export function elpian_wasm_snapshot(machine_id: string): string;

export function elpian_wasm_state(machine_id: string): string;

export function elpian_wasm_subtree_usage(machine_id: string): string;

export function elpian_wasm_terminate(machine_id: string): string;

export function elpian_wasm_terminate_tree(machine_id: string): string;

export function elpian_wasm_tree(machine_id: string): string;

export function elpian_wasm_usage(machine_id: string): string;

export function elpian_wasm_validate_ast(ast_json: string): boolean;

export function elpian_wasm_vm_exists(machine_id: string): boolean;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly elpian_wasm_adopt: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_capability_allows: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_charge_storage: (a: number, b: number, c: number) => [number, number];
    readonly elpian_wasm_continue_execution: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_create_vm_from_ast: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_create_vm_from_bytecode: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_create_vm_from_code: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_deliver_host_message: (a: number, b: number, c: number, d: number, e: number) => [number, number];
    readonly elpian_wasm_destroy_tree: (a: number, b: number) => [number, number];
    readonly elpian_wasm_destroy_vm: (a: number, b: number) => number;
    readonly elpian_wasm_effective_capabilities: (a: number, b: number) => [number, number];
    readonly elpian_wasm_enforce_tree_budgets: () => [number, number];
    readonly elpian_wasm_execute: (a: number, b: number) => [number, number];
    readonly elpian_wasm_execute_func: (a: number, b: number, c: number, d: number, e: number) => [number, number];
    readonly elpian_wasm_execute_func_with_input: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => [number, number];
    readonly elpian_wasm_limits: (a: number, b: number) => [number, number];
    readonly elpian_wasm_local_capabilities: (a: number, b: number) => [number, number];
    readonly elpian_wasm_pause: (a: number, b: number) => [number, number];
    readonly elpian_wasm_pause_tree: (a: number, b: number) => [number, number];
    readonly elpian_wasm_resume: (a: number, b: number) => [number, number];
    readonly elpian_wasm_sandbox_capabilities: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_set_capabilities: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_set_capability: (a: number, b: number, c: number, d: number, e: number) => [number, number];
    readonly elpian_wasm_set_limits: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_snapshot: (a: number, b: number) => [number, number];
    readonly elpian_wasm_state: (a: number, b: number) => [number, number];
    readonly elpian_wasm_subtree_usage: (a: number, b: number) => [number, number];
    readonly elpian_wasm_terminate: (a: number, b: number) => [number, number];
    readonly elpian_wasm_terminate_tree: (a: number, b: number) => [number, number];
    readonly elpian_wasm_tree: (a: number, b: number) => [number, number];
    readonly elpian_wasm_usage: (a: number, b: number) => [number, number];
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
