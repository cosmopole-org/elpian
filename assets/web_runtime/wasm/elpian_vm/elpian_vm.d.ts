/* tslint:disable */
/* eslint-disable */

export function elpian_bevy_wasm_create_scene(scene_id: string, json: string, width: number, height: number): boolean;

export function elpian_bevy_wasm_destroy_scene(scene_id: string): boolean;

export function elpian_bevy_wasm_get_elapsed_time(scene_id: string): number;

/**
 * Returns the rendered frame metadata as a JSON string.
 * Format: {"width": N, "height": N, "frameCount": N, "pixelCount": N}
 * Use `elpian_bevy_wasm_get_frame_bytes` to get the raw pixel data.
 * Uses an atomic snapshot to avoid inconsistent data.
 */
export function elpian_bevy_wasm_get_frame(scene_id: string): string;

/**
 * Get raw pixel bytes as a Vec<u8> for direct typed array access in JS.
 */
export function elpian_bevy_wasm_get_frame_bytes(scene_id: string): Uint8Array;

export function elpian_bevy_wasm_get_frame_count(scene_id: string): bigint;

export function elpian_bevy_wasm_init(): void;

export function elpian_bevy_wasm_render_frame(scene_id: string, delta_time: number): boolean;

export function elpian_bevy_wasm_resize_scene(scene_id: string, width: number, height: number): boolean;

export function elpian_bevy_wasm_scene_exists(scene_id: string): boolean;

export function elpian_bevy_wasm_send_input(scene_id: string, input_json: string): boolean;

export function elpian_bevy_wasm_update_scene(scene_id: string, json: string): boolean;

export function elpian_wasm_continue_execution(machine_id: string, input_json: string): string;

export function elpian_wasm_create_vm_from_ast(machine_id: string, ast_json: string): boolean;

export function elpian_wasm_create_vm_from_code(machine_id: string, code: string): boolean;

export function elpian_wasm_destroy_vm(machine_id: string): boolean;

export function elpian_wasm_execute(machine_id: string): string;

export function elpian_wasm_execute_func(machine_id: string, func_name: string, cb_id: number): string;

export function elpian_wasm_execute_func_with_input(machine_id: string, func_name: string, input_json: string, cb_id: number): string;

export function elpian_wasm_init(): void;

export function elpian_wasm_validate_ast(ast_json: string): boolean;

export function elpian_wasm_vm_exists(machine_id: string): boolean;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly elpian_free_string: (a: number) => void;
    readonly elpian_init: () => void;
    readonly elpian_create_vm_from_ast: (a: number, b: number) => number;
    readonly elpian_create_vm_from_code: (a: number, b: number) => number;
    readonly elpian_validate_ast: (a: number) => number;
    readonly elpian_execute: (a: number) => number;
    readonly elpian_execute_func: (a: number, b: number, c: bigint) => number;
    readonly elpian_execute_func_with_input: (a: number, b: number, c: number, d: bigint) => number;
    readonly elpian_continue_execution: (a: number, b: number) => number;
    readonly elpian_destroy_vm: (a: number) => number;
    readonly elpian_vm_exists: (a: number) => number;
    readonly elpian_bevy_init: () => void;
    readonly elpian_bevy_create_scene: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_bevy_update_scene: (a: number, b: number) => number;
    readonly elpian_bevy_render_frame: (a: number, b: number) => number;
    readonly elpian_bevy_resize_scene: (a: number, b: number, c: number) => number;
    readonly elpian_bevy_get_frame_ptr: (a: number) => number;
    readonly elpian_bevy_get_frame_json: (a: number) => number;
    readonly elpian_bevy_get_frame_size: (a: number) => number;
    readonly elpian_bevy_get_scene_dimensions: (a: number) => bigint;
    readonly elpian_bevy_send_input: (a: number, b: number) => number;
    readonly elpian_bevy_destroy_scene: (a: number) => number;
    readonly elpian_bevy_scene_exists: (a: number) => number;
    readonly elpian_bevy_get_elapsed_time: (a: number) => number;
    readonly elpian_bevy_get_frame_count: (a: number) => bigint;
    readonly elpian_bevy_wasm_init: () => void;
    readonly elpian_bevy_wasm_create_scene: (a: number, b: number, c: number, d: number, e: number, f: number) => number;
    readonly elpian_bevy_wasm_update_scene: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_bevy_wasm_render_frame: (a: number, b: number, c: number) => number;
    readonly elpian_bevy_wasm_resize_scene: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_bevy_wasm_get_frame: (a: number, b: number) => [number, number];
    readonly elpian_bevy_wasm_get_frame_bytes: (a: number, b: number) => [number, number];
    readonly elpian_bevy_wasm_send_input: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_bevy_wasm_destroy_scene: (a: number, b: number) => number;
    readonly elpian_bevy_wasm_scene_exists: (a: number, b: number) => number;
    readonly elpian_bevy_wasm_get_elapsed_time: (a: number, b: number) => number;
    readonly elpian_bevy_wasm_get_frame_count: (a: number, b: number) => bigint;
    readonly elpian_wasm_init: () => void;
    readonly elpian_wasm_create_vm_from_ast: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_create_vm_from_code: (a: number, b: number, c: number, d: number) => number;
    readonly elpian_wasm_validate_ast: (a: number, b: number) => number;
    readonly elpian_wasm_execute: (a: number, b: number) => [number, number];
    readonly elpian_wasm_execute_func: (a: number, b: number, c: number, d: number, e: number) => [number, number];
    readonly elpian_wasm_execute_func_with_input: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => [number, number];
    readonly elpian_wasm_continue_execution: (a: number, b: number, c: number, d: number) => [number, number];
    readonly elpian_wasm_destroy_vm: (a: number, b: number) => number;
    readonly elpian_wasm_vm_exists: (a: number, b: number) => number;
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
