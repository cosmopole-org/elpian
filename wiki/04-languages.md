# 04 — Guest languages: TypeScript, JavaScript, Dart

Elpian executes bytecode. Getting there from a source language is the job of the
**front-ends**. Anything a front-end cannot lower is a **build error**, not a
runtime surprise:

```
client: JavaScript is outside the Elpian subset
```

There are two paths into the VM, and one alternative runtime that bypasses the
compiler entirely.

| Path | Front-end | Used by |
|---|---|---|
| TypeScript / JavaScript | `oxc` (type-strip) → `js2elpian` | the `elpian` CLI — the primary path |
| Dart subset | `dart2elpian` → JS subset → `js2elpian` | Flutter-style guest logic |
| Real JavaScript | none — QuickJS engine | `ElpianRuntime.quickJs`, outside the bytecode/governance path |

---

## TypeScript

TypeScript is the CLI's default authoring language. It is handled in two stages
(`cli/rust/main.rs`, `transpile_typescript`):

1. **`oxc` parses and transforms it.** `SourceType::from_path` picks the dialect
   from the extension, a `SemanticBuilder` runs (with `with_enum_eval(true)`),
   and `Transformer` with `TransformOptions::default()` emits plain JS. This is
   a real TypeScript front-end, so the *type-level* language is fully supported:
   interfaces, type aliases, generics, unions, `as`, enums, parameter
   properties, decorated syntax — all erased or lowered here.
2. **`js2elpian` compiles the resulting JavaScript.** This is where the real
   limits live.

Recognised extensions (`resolve_source`): `.ts`, `.tsx`, `.js`, and directory
imports resolving to `index.ts`.

Build failures are reported per stage, so you can tell which one rejected you:

```
TypeScript parse failed in <file>: <diagnostic with source snippet>
TypeScript semantics failed in <file>
TypeScript transform failed in <file>
```

**Types are erased, not checked at the VM.** `let count: number = 0` becomes
`let count = 0`. There is no runtime type enforcement — annotate for your own
benefit, but do not rely on them for validation.

---

## JavaScript — the `js2elpian` supported surface

This is the authoritative list. From `rust/crates/js2elpian/src/lib.rs`.

### Operators — the full tower

```
??  ||  &&  |  ^  &  ==  ===  !=  !==  <  <=  >  >=  <<  >>  >>>
+  -  *  /  %  **
unary: !  -  +  ~  typeof  void  delete
instanceof, in
optional chaining: ?.  (member, index, and call)
```

All assignment forms: `= += -= *= /= %= **= &= |= ^= <<= >>= >>>= &&= ||= ??=`
and `++` / `--`.

Notes:
- `**` lowers to the VM's `^`; `===`→`==`, `!==`→`!=` (the VM's `==` is already
  strict).
- Bitwise and shift operators lower to universal builtins with **JS 32-bit
  semantics** — the operators themselves never reach the VM.
- `??`, `&&`, `||` are the VM's native short-circuit opcodes.
- `typeof`/`void`/`delete` lower to a `__typeof` prelude function built on
  `__isType`.

### Statements

- `let` / `const` / `var`, **including destructuring**
- `function` declarations
- `class` — fields, methods, `extends`/`super`, statics
- `if` / `else`, `while`, `do`/`while`, C-style `for`, **`for-of`**, **`for-in`**
- `switch` / `case` / `default` (default desugars to an if-chain), `break`,
  `continue`, `return`
- `throw`, and `try` / `catch` / `finally` over the VM's neutral exception opcode

### Expressions

Numbers, strings, template literals (`` `a${x}b` `` → the VM's native `template`
node), booleans, identifiers, array and object literals, member access
(`a.b` / `a[i]`), calls, spread, arrow functions and function expressions.

### How classes and closures are actually implemented

Worth knowing, because it explains some behaviour:

- **Classes lower to factory functions** whose methods are closures over a
  `this` object. There is no new opcode. `new C(...)` and a bare `C(...)` both
  construct.
- **Arrow / function expressions are lifted.** The VM has no function-literal
  *expression* opcode — a function value only enters scope via a
  `functionDefinition` *statement*. So each arrow is desugared into a synthetic,
  uniquely-named hoisted definition, and the expression site becomes an
  identifier referencing it. The lifted definition runs in place, so it closes
  over exactly the locals lexically in scope — a fresh `let` per loop iteration
  *is* captured independently.
- **Closures capture by reference.** A post-parse transform boxes locals that a
  nested closure mutates into one-element cells, so `arr.forEach(x => sum += x)`
  propagates correctly.
  An arrow nested inside an arrow captures the outer arrow's parameter too:
  `items.map((it) => () => it)` works, as do arbitrarily deep chains
  (`(a) => (b) => (c) => a + b + c`). A concise arrow body does not pass through
  `parse_statement`, where lifts are normally drained, so `finish_arrow` drains
  its own — otherwise the inner definition would escape the outer arrow and lose
  its parameter.
- **Deep assignment is lowered.** A simple target (`x`, `a.b`, `a[i]`) uses the
  native `assignment` opcode; a nested or computed target (`a.b.c`, `a[i].x`)
  becomes a `__setIndex(base, key, value)` builtin call.

### Method and static-namespace mapping

JS core-member spellings map to the VM's universal stdlib at **compile time**:

| You write | VM builtin |
|---|---|
| `arr.includes(x)` | `contains` |
| `arr.filter(f)` | `where` |
| `arr.some(f)` | `any` |
| `s.replace(a, b)` | `replaceFirst` |
| `s.toLowerCase()` | `lower` |

The static namespaces `Math`, `JSON`, `Object`, `Number`, `Array`, `console` and
the globals `parseInt` / `parseFloat` resolve to builtins. Higher-order
Array/Map methods run as guest prelude functions.

### NOT supported — this is the part that bites

Two different failure modes, and the second is far more dangerous.

#### Rejected at build time (loud, safe)

- ❌ **`async` / `await` / Promises.** The VM is a pausing interpreter, not an
  event loop: there is no Promise, no microtask queue, and no opcode to suspend
  on one. Both statement and expression positions are rejected:

  ```
  elpian: server: "js: `async` functions are not supported — the Elpian VM has no
  event loop; use the timer host APIs (setTimeout/setInterval) and callback style instead"
  ```

  Use the timer host APIs and callback style
  ([`12-host-apis.md`](12-host-apis.md)).

  > Historically these compiled *successfully* and produced a program that
  > trapped the VM on first call — and on `elpian-server` that trap poisoned a
  > global lock, killing the process for every later request. Both halves are
  > now fixed: `js2elpian` rejects the construct, and `api.rs` recovers poisoned
  > locks. If you are on an older toolchain, treat `async` as forbidden.

- ❌ **Generators** (`function*`, `yield`) →
  `js: expected identifier, found Punct("*")`.
- ❌ **Anonymous `export default function () { … }`** → `javascript parse error`.
- ❌ Prototype manipulation, `Proxy`, `Reflect`, `Symbol`, getters/setters,
  tagged templates, labelled break/continue, `with`, `eval`.

#### Compiles, then fails at runtime (silent, dangerous)

- ❌ The DOM, `window`, `fetch`, `XMLHttpRequest`, `localStorage`. These do not
  exist in the VM; they compile to undefined identifiers and fail — or silently
  read as null — at run time. Reach the host through `askHost` instead.

#### Actually fine, despite appearances

- ✅ **Named `export default function name() { … }`** works. The export-stripping
  regexes do not match it, so `export default` survives into the bundle, but
  `js2elpian` tolerates the leading tokens and the function is callable under its
  declared name. `export default 42;` also compiles.
- ⚠️ **`export { a as b }`** is stripped wholesale by the export-list regex, so
  the alias `b` never exists. Only the original name `a` is reachable.

---

## The bundler — how modules actually work

`bundle_module` in the CLI does **textual concatenation**, not real ES modules:

1. Match `import` statements with a regex (must be at line start:
   `import … from '…';` or `import '…';`).
2. Resolve and recursively bundle each dependency **first** (depth-first,
   deduplicated by canonical path).
3. Transpile this file, **delete the import lines**, and strip `export`
   keywords.
4. Append the result to one flat source string.

Consequences you must design around:

- **One flat scope.** Every module's top-level names share a namespace.
  Two modules that both define `helper` will collide. Prefix your top-level
  names, or keep modules few and deliberate.
- **Named imports are not bindings.** `import { el } from '@elpian/sdk'` does not
  create a local alias — it guarantees the SDK's source is present *above* yours,
  and `el` resolves as a global. Renaming (`import { el as e }`) will not work.
- **Order is dependency-first**, so a module can call into anything it imports.
- **Circular imports** are silently deduplicated by the `seen` set — the second
  visit is skipped, which may leave a name undefined at call time.

### Package resolution

Bare specifiers resolve through `.elpian/packages`, populated by
`elpian run install`:

```
import { el } from '@elpian/sdk'
  → package name  '@elpian/sdk'   (scoped: first two path segments)
  → <root>/.elpian/packages/@elpian/sdk/          (a symlink)
  → read elpian.package.json → { "entry": "index.ts" }
  → resolve entry (or the subpath after the package name)
```

`elpian run install` reads `elpian.json`, validates each package's
`elpian.package.json` (its `name` must match the dependency key and its `entry`
must exist), creates the symlink, and writes `.elpian/elpian.lock.json`.
There are no npm manifests, no `node_modules`, no lifecycle scripts.

---

## Dart — the `dart2elpian` subset

`dart2elpian` lowers a **Dart subset to the JS subset**, which `js2elpian` then
compiles. It is purely a *language* layer — runtime intrinsics still go through
`askHost`.

**Supported:**

- Top-level function declarations and statements; typed or `var`/`final` locals
  (types are parsed and erased).
- **Classes** — fields with initialisers, constructors including `this.x`
  initialising formals, methods, `extends`/`super`, instantiation
  `ClassName(args)`, member access, `this`. Bare field/method references inside
  methods resolve to `this.member`, including inherited members.
- **Control flow** — `if`/`else`, `while`, `do`/`while`, C-style `for`,
  **`for-in`** (lowered to `while`), `switch`/`case`/`default`, `break`,
  `continue`, `return`, blocks.
- **Exceptions** — `throw` / `rethrow`, `try` / `on T` / `catch (e[, st])` /
  `finally`. The `on Type` filter and stack-trace binding are **erased**; a
  native builtin error is a catchable `{ name, message }`.
- **Expressions** — literals including **hex integers** (`0xFF2196F3` for
  colours), calls, list literals, indexing, assignment and compound assignment
  (`+= -= *= /= %= &= |= ^= <<= >>= >>>=` and `??=`), `++`/`--`, ternary, the
  full binary tower including `~/`, unary `! - ~`, the null-assertion `x!`
  (erased), null-aware `obj?.member`, and **cascades** `target..a()..b = c`.
- **String interpolation** — `"$x"`, `"${expr}"` lowered to concatenation.
- **Closures** — `(a) => expr`, `(a) { body }`, and arrow bodies for
  function/method declarations (`int f() => expr;`). With the VM's higher-order
  Iterable methods (`map`/`where`/`fold`/`reduce`/`any`/`every`/`firstWhere`/
  `expand`/`takeWhile`/`sort`/…) this runs real functional Dart. Closures capture
  **by reference** for mutated captured locals.
- `print(x)` lowers to `askHost("log", [x])`.
- `~/` and the bitwise/shift operators lower to the VM's universal builtins.
- **`main()` is auto-invoked** if present.

**Not supported:** `async`/`await`/`Future`/`Stream`, mixins, extensions,
generics with runtime reification, named/optional parameters beyond the basics,
`part`/`library`, the Dart core library beyond what maps to the universal stdlib.

> Note: `dart2elpian` is vendored at `rust/crates/dart2elpian/` but is **not wired into
> the `elpian` CLI**. The CLI compiles TypeScript/JavaScript only. Use the crate
> directly if you need the Dart path.

---

## The QuickJS escape hatch

`ElpianRuntime.quickJs` (`lib/src/vm/quickjs_vm*.dart`) runs a real QuickJS
engine instead of the Elpian bytecode VM. Use it when you genuinely need JS
semantics the subset does not cover.

**What you give up:** the bytecode pipeline, and the governance layer described
in [`03-governance.md`](03-governance.md) — capabilities, resource meters and the
VM tree are properties of the Elpian VM, not of QuickJS. Do not use it for
untrusted code.

---

## Choosing

- **Writing an app with the CLI?** TypeScript. It is the default, best-covered
  path, and the templates are TS.
- **Porting Flutter-shaped logic?** Dart, via `dart2elpian`, invoked yourself.
- **Need `async`, or a library that requires full JS?** QuickJS runtime — and
  accept that it is unsandboxed.
