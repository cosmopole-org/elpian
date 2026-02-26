/* @ts-self-types="./elpian_vm.d.ts" */

//#region exports

/**
 * @param {string} scene_id
 * @param {string} json
 * @param {number} width
 * @param {number} height
 * @returns {boolean}
 */
export function elpian_bevy_wasm_create_scene(scene_id, json, width, height) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    _assertNum(width);
    _assertNum(height);
    const ret = wasm.elpian_bevy_wasm_create_scene(ptr0, len0, ptr1, len1, width, height);
    return ret !== 0;
}

/**
 * @param {string} scene_id
 * @returns {boolean}
 */
export function elpian_bevy_wasm_destroy_scene(scene_id) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_destroy_scene(ptr0, len0);
    return ret !== 0;
}

/**
 * @param {string} scene_id
 * @returns {number}
 */
export function elpian_bevy_wasm_get_elapsed_time(scene_id) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_get_elapsed_time(ptr0, len0);
    return ret;
}

/**
 * Returns the rendered frame metadata as a JSON string.
 * Format: {"width": N, "height": N, "frameCount": N, "pixelCount": N}
 * Use `elpian_bevy_wasm_get_frame_bytes` to get the raw pixel data.
 * Uses an atomic snapshot to avoid inconsistent data.
 * @param {string} scene_id
 * @returns {string}
 */
export function elpian_bevy_wasm_get_frame(scene_id) {
    let deferred2_0;
    let deferred2_1;
    try {
        const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.elpian_bevy_wasm_get_frame(ptr0, len0);
        deferred2_0 = ret[0];
        deferred2_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred2_0, deferred2_1, 1);
    }
}

/**
 * Get raw pixel bytes as a Vec<u8> for direct typed array access in JS.
 * @param {string} scene_id
 * @returns {Uint8Array}
 */
export function elpian_bevy_wasm_get_frame_bytes(scene_id) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_get_frame_bytes(ptr0, len0);
    var v2 = getArrayU8FromWasm0(ret[0], ret[1]).slice();
    wasm.__wbindgen_free(ret[0], ret[1] * 1, 1);
    return v2;
}

/**
 * @param {string} scene_id
 * @returns {bigint}
 */
export function elpian_bevy_wasm_get_frame_count(scene_id) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_get_frame_count(ptr0, len0);
    return BigInt.asUintN(64, ret);
}

export function elpian_bevy_wasm_init() {
    wasm.elpian_bevy_wasm_init();
}

/**
 * @param {string} scene_id
 * @param {number} delta_time
 * @returns {boolean}
 */
export function elpian_bevy_wasm_render_frame(scene_id, delta_time) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_render_frame(ptr0, len0, delta_time);
    return ret !== 0;
}

/**
 * @param {string} scene_id
 * @param {number} width
 * @param {number} height
 * @returns {boolean}
 */
export function elpian_bevy_wasm_resize_scene(scene_id, width, height) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    _assertNum(width);
    _assertNum(height);
    const ret = wasm.elpian_bevy_wasm_resize_scene(ptr0, len0, width, height);
    return ret !== 0;
}

/**
 * @param {string} scene_id
 * @returns {boolean}
 */
export function elpian_bevy_wasm_scene_exists(scene_id) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_scene_exists(ptr0, len0);
    return ret !== 0;
}

/**
 * @param {string} scene_id
 * @param {string} input_json
 * @returns {boolean}
 */
export function elpian_bevy_wasm_send_input(scene_id, input_json) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(input_json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_send_input(ptr0, len0, ptr1, len1);
    return ret !== 0;
}

/**
 * @param {string} scene_id
 * @param {string} json
 * @returns {boolean}
 */
export function elpian_bevy_wasm_update_scene(scene_id, json) {
    const ptr0 = passStringToWasm0(scene_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_bevy_wasm_update_scene(ptr0, len0, ptr1, len1);
    return ret !== 0;
}

/**
 * @param {string} machine_id
 * @param {string} input_json
 * @returns {string}
 */
export function elpian_wasm_continue_execution(machine_id, input_json) {
    let deferred3_0;
    let deferred3_1;
    try {
        const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(input_json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.elpian_wasm_continue_execution(ptr0, len0, ptr1, len1);
        deferred3_0 = ret[0];
        deferred3_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
    }
}

/**
 * @param {string} machine_id
 * @param {string} ast_json
 * @returns {boolean}
 */
export function elpian_wasm_create_vm_from_ast(machine_id, ast_json) {
    const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(ast_json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_wasm_create_vm_from_ast(ptr0, len0, ptr1, len1);
    return ret !== 0;
}

/**
 * @param {string} machine_id
 * @param {string} code
 * @returns {boolean}
 */
export function elpian_wasm_create_vm_from_code(machine_id, code) {
    const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(code, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_wasm_create_vm_from_code(ptr0, len0, ptr1, len1);
    return ret !== 0;
}

/**
 * @param {string} machine_id
 * @returns {boolean}
 */
export function elpian_wasm_destroy_vm(machine_id) {
    const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_wasm_destroy_vm(ptr0, len0);
    return ret !== 0;
}

/**
 * @param {string} machine_id
 * @returns {string}
 */
export function elpian_wasm_execute(machine_id) {
    let deferred2_0;
    let deferred2_1;
    try {
        const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.elpian_wasm_execute(ptr0, len0);
        deferred2_0 = ret[0];
        deferred2_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred2_0, deferred2_1, 1);
    }
}

/**
 * @param {string} machine_id
 * @param {string} func_name
 * @param {number} cb_id
 * @returns {string}
 */
export function elpian_wasm_execute_func(machine_id, func_name, cb_id) {
    let deferred3_0;
    let deferred3_1;
    try {
        const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(func_name, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        _assertNum(cb_id);
        const ret = wasm.elpian_wasm_execute_func(ptr0, len0, ptr1, len1, cb_id);
        deferred3_0 = ret[0];
        deferred3_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
    }
}

/**
 * @param {string} machine_id
 * @param {string} func_name
 * @param {string} input_json
 * @param {number} cb_id
 * @returns {string}
 */
export function elpian_wasm_execute_func_with_input(machine_id, func_name, input_json, cb_id) {
    let deferred4_0;
    let deferred4_1;
    try {
        const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(func_name, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ptr2 = passStringToWasm0(input_json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len2 = WASM_VECTOR_LEN;
        _assertNum(cb_id);
        const ret = wasm.elpian_wasm_execute_func_with_input(ptr0, len0, ptr1, len1, ptr2, len2, cb_id);
        deferred4_0 = ret[0];
        deferred4_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred4_0, deferred4_1, 1);
    }
}

export function elpian_wasm_init() {
    wasm.elpian_wasm_init();
}

/**
 * @param {string} ast_json
 * @returns {boolean}
 */
export function elpian_wasm_validate_ast(ast_json) {
    const ptr0 = passStringToWasm0(ast_json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_wasm_validate_ast(ptr0, len0);
    return ret !== 0;
}

/**
 * @param {string} machine_id
 * @returns {boolean}
 */
export function elpian_wasm_vm_exists(machine_id) {
    const ptr0 = passStringToWasm0(machine_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.elpian_wasm_vm_exists(ptr0, len0);
    return ret !== 0;
}

//#endregion

//#region wasm imports

function __wbg_get_imports() {
    const import0 = {
        __proto__: null,
        __wbg___wbindgen_throw_be289d5034ed271b: function(arg0, arg1) {
            throw new Error(getStringFromWasm0(arg0, arg1));
        },
        __wbindgen_init_externref_table: function() {
            const table = wasm.__wbindgen_externrefs;
            const offset = table.grow(4);
            table.set(0, undefined);
            table.set(offset + 0, undefined);
            table.set(offset + 1, null);
            table.set(offset + 2, true);
            table.set(offset + 3, false);
        },
    };
    return {
        __proto__: null,
        "./elpian_vm_bg.js": import0,
    };
}


//#endregion

//#region intrinsics
function _assertNum(n) {
    if (typeof(n) !== 'number') throw new Error(`expected a number argument, found ${typeof(n)}`);
}

function getArrayU8FromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    return getUint8ArrayMemory0().subarray(ptr / 1, ptr / 1 + len);
}

function getStringFromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    return decodeText(ptr, len);
}

let cachedUint8ArrayMemory0 = null;
function getUint8ArrayMemory0() {
    if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
        cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
    }
    return cachedUint8ArrayMemory0;
}

function passStringToWasm0(arg, malloc, realloc) {
    if (typeof(arg) !== 'string') throw new Error(`expected a string argument, found ${typeof(arg)}`);
    if (realloc === undefined) {
        const buf = cachedTextEncoder.encode(arg);
        const ptr = malloc(buf.length, 1) >>> 0;
        getUint8ArrayMemory0().subarray(ptr, ptr + buf.length).set(buf);
        WASM_VECTOR_LEN = buf.length;
        return ptr;
    }

    let len = arg.length;
    let ptr = malloc(len, 1) >>> 0;

    const mem = getUint8ArrayMemory0();

    let offset = 0;

    for (; offset < len; offset++) {
        const code = arg.charCodeAt(offset);
        if (code > 0x7F) break;
        mem[ptr + offset] = code;
    }
    if (offset !== len) {
        if (offset !== 0) {
            arg = arg.slice(offset);
        }
        ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
        const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
        const ret = cachedTextEncoder.encodeInto(arg, view);
        if (ret.read !== arg.length) throw new Error('failed to pass whole string');
        offset += ret.written;
        ptr = realloc(ptr, len, offset, 1) >>> 0;
    }

    WASM_VECTOR_LEN = offset;
    return ptr;
}

let cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
cachedTextDecoder.decode();
const MAX_SAFARI_DECODE_BYTES = 2146435072;
let numBytesDecoded = 0;
function decodeText(ptr, len) {
    numBytesDecoded += len;
    if (numBytesDecoded >= MAX_SAFARI_DECODE_BYTES) {
        cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
        cachedTextDecoder.decode();
        numBytesDecoded = len;
    }
    return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
}

const cachedTextEncoder = new TextEncoder();

if (!('encodeInto' in cachedTextEncoder)) {
    cachedTextEncoder.encodeInto = function (arg, view) {
        const buf = cachedTextEncoder.encode(arg);
        view.set(buf);
        return {
            read: arg.length,
            written: buf.length
        };
    };
}

let WASM_VECTOR_LEN = 0;


//#endregion

//#region wasm loading
let wasmModule, wasm;
function __wbg_finalize_init(instance, module) {
    wasm = instance.exports;
    wasmModule = module;
    cachedUint8ArrayMemory0 = null;
    wasm.__wbindgen_start();
    return wasm;
}

async function __wbg_load(module, imports) {
    if (typeof Response === 'function' && module instanceof Response) {
        if (typeof WebAssembly.instantiateStreaming === 'function') {
            try {
                return await WebAssembly.instantiateStreaming(module, imports);
            } catch (e) {
                const validResponse = module.ok && expectedResponseType(module.type);

                if (validResponse && module.headers.get('Content-Type') !== 'application/wasm') {
                    console.warn("`WebAssembly.instantiateStreaming` failed because your server does not serve Wasm with `application/wasm` MIME type. Falling back to `WebAssembly.instantiate` which is slower. Original error:\n", e);

                } else { throw e; }
            }
        }

        const bytes = await module.arrayBuffer();
        return await WebAssembly.instantiate(bytes, imports);
    } else {
        const instance = await WebAssembly.instantiate(module, imports);

        if (instance instanceof WebAssembly.Instance) {
            return { instance, module };
        } else {
            return instance;
        }
    }

    function expectedResponseType(type) {
        switch (type) {
            case 'basic': case 'cors': case 'default': return true;
        }
        return false;
    }
}

function initSync(module) {
    if (wasm !== undefined) return wasm;


    if (module !== undefined) {
        if (Object.getPrototypeOf(module) === Object.prototype) {
            ({module} = module)
        } else {
            console.warn('using deprecated parameters for `initSync()`; pass a single object instead')
        }
    }

    const imports = __wbg_get_imports();
    if (!(module instanceof WebAssembly.Module)) {
        module = new WebAssembly.Module(module);
    }
    const instance = new WebAssembly.Instance(module, imports);
    return __wbg_finalize_init(instance, module);
}

async function __wbg_init(module_or_path) {
    if (wasm !== undefined) return wasm;


    if (module_or_path !== undefined) {
        if (Object.getPrototypeOf(module_or_path) === Object.prototype) {
            ({module_or_path} = module_or_path)
        } else {
            console.warn('using deprecated parameters for the initialization function; pass a single object instead')
        }
    }

    if (module_or_path === undefined) {
        module_or_path = new URL('elpian_vm_bg.wasm', import.meta.url);
    }
    const imports = __wbg_get_imports();

    if (typeof module_or_path === 'string' || (typeof Request === 'function' && module_or_path instanceof Request) || (typeof URL === 'function' && module_or_path instanceof URL)) {
        module_or_path = fetch(module_or_path);
    }

    const { instance, module } = await __wbg_load(await module_or_path, imports);

    return __wbg_finalize_init(instance, module);
}

export { initSync, __wbg_init as default };
//#endregion
export { wasm as __wasm }
