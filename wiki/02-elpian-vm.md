# 02 — The Elpian VM

The VM (`rust/`, crate `elpian-vm`) is a **pure executor**. Its own description:

> Ingests Elpian AST JSON / bytecode (produced by front-end crates such as
> js2elpian / dart2elpian) and executes it, yielding host calls to the embedding
> runtime.

It has no notion of any source language, and no notion of UI. You rarely touch
it directly — you write TypeScript — but its semantics determine what your code
*means*.

## Pipeline

```
TS source ──oxc──▶ JS ──js2elpian::compile_js_to_ast──▶ Elpian AST JSON
                       ──js2elpian::compile_js_to_bytecode──▶ bytecode (Vec<u8>)
                                                              │
                       DecodedProgram::decode ◀───────────────┘
                                │
                                ▼  addressable op list
                          executor.rs  ──▶ run + suspend on askHost
```

Two properties worth knowing:

- The front-end runs **ahead of time**. The deployed app loads bytecode; there
  is no parser in the runtime. (`.elpian.js` is shipped too, but purely as a
  readable/debug artifact — the browser never parses it.)
- The executor **decodes bytecode once** at construction into an addressable op
  list (`rust/src/sdk/program.rs`). A program that re-runs its render path every
  frame pays decode cost only once — the file's own comment notes that
  re-decoding "dominated the per-frame cost" before this change.

## Two ingestion formats

| Format | File | Built by | Loaded with |
|---|---|---|---|
| AST JSON | `client.elpian.ast.json` | `compile_js_to_ast` | `create_vm_from_ast` |
| Bytecode | `client.elpian.bc` | `compile_js_to_bytecode` | `create_vm_from_bytecode` |

The CLI's `mode` config (`js` \| `bytecode` \| `both`) decides which get built;
`both` is the default and the manifest then declares `"format": "bytecode"`.
Bytecode is smaller and skips a JSON parse at load. There is also
`create_vm_from_code(machine_id, code)` which compiles JS **inside** the VM —
convenient for embedding, but it means shipping a compiler and source.

## The typed value envelope

Every value crossing the FFI/WASM boundary is wrapped:

```json
{ "type": "<type_name>", "data": { "value": <actual_value> } }
```

| Type | ID | Example |
|---|---|---|
| `null` | 0 | (empty Val) |
| `i16` | 1 | `{"type":"i16","data":{"value":42}}` |
| `i32` | 2 | `{"type":"i32","data":{"value":100000}}` |
| `i64` | 3 | `{"type":"i64","data":{"value":9999999999}}` |
| `f32` | 4 | `{"type":"f32","data":{"value":3.14}}` |
| `f64` | 5 | `{"type":"f64","data":{"value":3.141592653589793}}` |
| `bool` | 6 | `{"type":"bool","data":{"value":true}}` |
| `string` | 7 | `{"type":"string","data":{"value":"hello"}}` |
| `object` | 8 | `{"type":"object","data":{"value":{"k":{…}}}}` |
| `array` | 9 | `{"type":"array","data":{"value":[…]}}` |
| `function` | 10 | internal only |
| `host_call_pending` | 253 | internal — the VM is paused |
| `native_func` | 255 | internal — the `askHost` marker |

Containers are **recursively typed** — each member of an object or array is
itself an envelope:

```json
{ "type": "object", "data": { "value": {
    "name": { "type": "string", "data": { "value": "Alice" } },
    "age":  { "type": "i16",    "data": { "value": 30 } }
} } }
```

You normally never hand-write this. The host does it for you when it delivers an
event payload (`_toTypedVmValue` in `elpian_vm_widget.dart`), and the guest gets
ordinary values. You *do* need to know it when writing a **custom host handler**
— your reply must be a typed envelope. See [`12-host-apis.md`](12-host-apis.md).

## `askHost` — the one seam

```ts
declare function askHost(name: string, payload: unknown): unknown;
```

This is the *only* way a guest affects the outside world. Everything else — the
SDK's `render()`, timers, DOM calls, canvas commands — is a wrapper over it.

**VM → host** message:

```json
{ "machineId": "vm-001", "apiName": "render", "payload": "<stringified value>" }
```

**Host → VM** reply must be a typed envelope:

```json
{ "type": "string", "data": { "value": "ok" } }
```

For a void reply, hosts conventionally send `{"type":"i16","data":{"value":0}}`.

An API name the host does not handle leaves the VM suspended. The HTTP server
treats that as a hard error: an unhandled host call from a server-side program
returns **HTTP 501** with the host-call data as the body. This is why the server
template's functions must be synchronous and side-effect-free.

## Run states and traps

`rust/src/api.rs` exposes lifecycle and introspection:

```rust
pub fn run_state(machine_id: &str) -> Option<RunState>;
pub fn trap_reason(machine_id: &str) -> Option<String>;
pub fn vm_is_processing(machine_id: &str) -> bool;
pub fn pause_vm(machine_id: &str) -> bool;
pub fn clear_pause(machine_id: &str) -> bool;
pub fn resume_execution(machine_id: String) -> VmExecResult;
pub fn terminate_vm(machine_id: &str) -> bool;
pub fn destroy_vm(machine_id: String) -> bool;
```

A **trap** is a controlled termination — never a Rust panic. Resource overruns
([`03-governance.md`](03-governance.md)) become traps carrying a machine-readable
kind (`instructions`, `instructions_per_turn`, `memory`, `storage`,
`call_depth`), readable through `trap_reason`.

`pause_vm` is cooperative: it stops the instance between turns; `clear_pause`
then `resume_execution` restarts it.

## The VM's public API (Rust)

Creation and execution:

```rust
init_vm_system();
create_vm_from_ast(machine_id: String, ast_json: String) -> bool;
create_vm_from_bytecode(machine_id: String, bytecode: Vec<u8>) -> bool;
create_vm_from_code(machine_id: String, code: String) -> bool;   // compiles JS in-VM
validate_ast(ast_json: String) -> bool;
compile_code_to_info(code: String) -> String;                    // diagnostics

execute_vm(machine_id: String) -> VmExecResult;                  // run top level
execute_vm_func(machine_id, func_name, cb_id) -> VmExecResult;
execute_vm_func_with_input(machine_id, func_name, input_json, cb_id) -> VmExecResult;
deliver_host_message(machine_id, message_json, cb_id) -> VmExecResult;
continue_execution(machine_id: String, input_json: String) -> VmExecResult;

vm_exists(machine_id: String) -> bool;
destroy_vm(machine_id: String) -> bool;
```

`VmExecResult` carries `has_host_call`, `host_call_data`, and `result_value`.
The embedder's loop is: execute → if `has_host_call`, service it → `continue_execution`
→ repeat.

Governance calls are listed in [`03-governance.md`](03-governance.md).

## The universal stdlib

`rust/src/sdk/stdlib/mod.rs` binds ~200 builtins available to **every** front-end,
so JS and Dart guests get identical behaviour. They are global functions, not
methods on a prototype chain (though the JS front-end maps common method
spellings onto them — `arr.includes(x)` → `contains`, `arr.filter(f)` → `where`).

**Math / numeric**
`abs acos acosh asin asinh atan atan2 atanh cbrt ceil clamp cos cosh degrees exp
expm1 factorial floor fract gcd hypot isEven isFinite isNaN isNegative isOdd lcm
ln log log10 log2 max mean min pow radians random remainder round seedRandom sign
sin sinh sqrt sum tan tanh trunc intDiv` plus constants `E INF LN10 LN2 NAN PI
SQRT2 TAU`.

**Bitwise** (32-bit JS semantics) `bitAnd bitNot bitOr bitXor shl shr ushr
toInt32 toUint32`.

**String** `charAt codeUnitAt codeUnits chr ord concat contains endsWith indexOf
lastIndexOf join lower upper padStart padEnd repeat replace replaceFirst split
startsWith substring trim trimStart trimEnd toRadix parseRadix toStringAsFixed
base64Encode base64Decode utf8Encode utf8Decode`.

**List** `at clear concat contains extend fill first flatten indexOf insert last
length pop push pushAll remove removeAt reverse reversed setAt shift shuffle skip
slice sort splice take toSet unshift range`.

**Map / object** `delKey entries get has hasValue keys merge putIfAbsent setKey
values field setField`.

**Type / reflection** `bool int num str toString toDouble typeOf classOf class
isInstance isNull isNotEmpty compareTo tryNum method parentMethod superMethod new`.

**JSON** `jsonParse jsonStringify`.

**Internal** `__setIndex` (deep assignment lowering), `cell cellGet cellSet`
(closure boxing), `emit`.

## Value semantics you must internalize

- **Absent reads yield null.** A missing argument, an absent object member, an
  absent map key, an out-of-range list index all read as `null`.
- **`0` is falsy but is not null.** `if (x)` is false for `0`; `x == null` is
  false for `0`.
- **Ints and floats are distinct tags.** `i16/i32/i64` vs `f32/f64`. A host API
  expecting an integer will misbehave if handed a float. Dart's `int`/`double`
  distinction maps directly; JS numbers are classified at the boundary.
- **No `async`/`await`, no Promises, no generators.** The VM is a pausing
  interpreter, not an event loop. Use the timer host APIs
  (`setTimeout`/`setInterval`) and callback style. See
  [`04-languages.md`](04-languages.md).

## Embedding surfaces

| Surface | File | Target |
|---|---|---|
| Native FFI | `rust/src/api/ffi.rs` | Android, iOS, macOS, Linux, Windows (via `rust_builder/`) |
| WASM | `rust/src/api/wasm.rs` | Web (`wasm-bindgen`) |
| HTTP server | `rust/src/bin/elpian-server.rs` | Server-side VMs, one per request |

On the Flutter side these are selected by conditional import in
`lib/elpian_ui.dart`:

```dart
export 'src/vm/frb_generated/api.dart'
    if (dart.library.js_interop) 'src/vm/frb_generated/api_web.dart'
    show ElpianVmApi;
```

## Deeper reference

[`15-ast-reference.md`](15-ast-reference.md) is the complete AST and API
reference: every expression node, every statement node, the operator table, the
full host-call protocol, and worked end-to-end examples. Read it when you need to
emit or debug Elpian AST JSON directly.
