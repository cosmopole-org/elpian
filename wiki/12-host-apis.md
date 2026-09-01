# 12 — Host APIs: the `askHost` catalog and custom handlers

`askHost(apiName, payload)` is the guest's only door to the outside world. This
chapter lists what is behind it and how to add your own.

```ts
declare function askHost(name: string, payload: unknown): unknown;
```

The allowlist lives in `lib/src/vm/host_api_catalog.dart` — **107 names** across
four families. An API name not registered leaves the VM suspended.

---

## Core (5)

| Name | Purpose |
|---|---|
| `render` | Hand a UI tree to the host — the main event |
| `println` | Print a message; surfaced via `onPrintln` |
| `stringify` | Convert a value to its string representation |
| `updateApp` | Update app state / trigger a re-render; surfaced via `onUpdateApp` |
| `env.get` | Read the host environment (viewport, platform, base URL, …) |

`render` is what the SDK wraps:

```ts
export function render(node: ElpianNode): void { askHost('render', JSON.stringify(node)); }
```

It accepts an optional scope key for partial updates — see
[`07-ui-model.md`](07-ui-model.md).

**`console.log` lowers to `askHost("log", …)`** via the front-end. On the
client the host services it; **on the HTTP server it does not**, and an
unserviced host call returns HTTP 501. Do not log from server-template code.

## Timers (4)

| Name | Signature |
|---|---|
| `setTimeout` | `[functionName, delayMs]` → handle |
| `setInterval` | `[functionName, periodMs]` → handle |
| `clearTimeout` | `[handle]` |
| `clearInterval` | `[handle]` |

This is the **replacement for `async`/`await`**, which the subset does not
support. The timer fires by calling a named VM function, exactly like an event
handler:

```dart
invoke: (funcName, inputJson) async {
  if (inputJson == null) await runtimeVm.callFunction(funcName);
  else                   await runtimeVm.callFunctionWithInput(funcName, inputJson);
}
```

```ts
let ticks: number = 0;
function tick() { ticks = ticks + 1; render(view()); }
askHost('setInterval', ['tick', 1000]);
```

## DOM (30)

A retained element tree the guest can query and mutate, independent of the
render tree (`lib/src/core/dom_api.dart`).

**Query** — `dom.getElementById` `dom.getElementsByClassName`
`dom.getElementsByTagName` `dom.querySelector` `dom.querySelectorAll`
`dom.getAllElements`

**Tree** — `dom.createElement` `dom.removeElement` `dom.clear`
`dom.appendChild` `dom.insertBefore` `dom.removeChild` `dom.replaceChild`

**Content** — `dom.setTextContent` `dom.setInnerHtml`

**Attributes** — `dom.setAttribute` `dom.getAttribute` `dom.removeAttribute`
`dom.hasAttribute`

**Style** — `dom.setStyle` `dom.getStyle` `dom.setStyleObject`

**Classes** — `dom.addClass` `dom.removeClass` `dom.hasClass` `dom.toggleClass`

**Events** — `dom.addEventListener` `dom.removeEventListener`
`dom.dispatchEvent`

**Serialisation** — `dom.toJson`

```ts
const el = askHost('dom.createElement', { tagName: 'div', id: 'panel', classes: ['card'] });
askHost('dom.setTextContent', { id: 'panel', text: 'Hello' });
askHost('dom.addClass', { id: 'panel', className: 'visible' });
```

## Canvas (68)

Listed in full in [`11-canvas-and-3d.md`](11-canvas-and-3d.md).

---

## Capability gating

Every API name maps to a capability by prefix
([`03-governance.md`](03-governance.md)):

| Prefix | Capability |
|---|---|
| `log` | `Logging` |
| `gpu.` | `Gpu` |
| `net.` | `Network` |
| `fs.` | `Storage` |
| `time.` | `Clock` |
| `random.` | `Randomness` |
| `vm.` | `VmManage` (except `vm.import` → `ModuleImport`) |
| everything else | `Other` |

**A disabled capability short-circuits to a typed null** rather than suspending
or throwing. Write guest code that tolerates a null result from a host call.

---

## Writing a custom host handler

The signature (`lib/src/vm/elpian_vm.dart`):

```dart
/// The VM sandbox calls host functions via `askHost(apiName, payload)`.
/// This callback receives the API name and JSON payload, and should
/// return a JSON response in the typed value format:
/// `{"type": "string", "data": {"value": "hello"}}`
typedef HostCallHandler = FutureOr<String> Function(String apiName, String payload);
```

Pass a map of them to the widget:

```dart
ElpianVmWidget.fromBytecode(
  machineId: 'app',
  bytecode: bytes,
  hostHandlers: {
    'app.fetch': (name, payload) async {
      final args = jsonDecode(payload) as List;
      final res  = await http.get(Uri.parse(args.first as String));
      return jsonEncode({
        'type': 'string',
        'data': { 'value': res.body },
      });
    },
    'app.saveSetting': (name, payload) async {
      final args = jsonDecode(payload) as Map<String, dynamic>;
      await prefs.setString(args['key'] as String, args['value'] as String);
      return jsonEncode({ 'type': 'bool', 'data': { 'value': true } });
    },
  },
);
```

Your handlers are merged **after** the built-ins, so they can also override a
default:

```dart
final hostHandlers = <String, HostCallHandler>{
  for (final apiName in VmHostApiCatalog.allHostApiNames)
    apiName: (name, payload) => hostHandler.handleHostCall(name, payload),
  ...timerHandlers,
  ...?widget.hostHandlers,          // ← yours wins
};
runtimeVm.registerHostHandlers(hostHandlers);
```

Call it from the guest:

```ts
const body = askHost('app.fetch', ['https://example.com/data.json']);
const data = JSON.parse(body as string);
```

### Rules for handlers

1. **Return a typed envelope.** `{"type": …, "data": {"value": …}}`. A void reply
   is conventionally `{"type":"i16","data":{"value":0}}`.
2. **Async is fine** — the return type is `FutureOr<String>`. The VM stays
   suspended until you resolve.
3. **Never throw.** An exception leaves the VM suspended. Catch and return an
   error-shaped value instead; the built-in handlers do exactly this
   (`debugPrint` + `_makeResponse('i16', 0)`).
4. **Name it in a family** if you want capability gating for free. `app.*` maps
   to `Other`; `net.*` maps to `Network` and can be revoked centrally.
5. **The payload is a stringified value**, not necessarily JSON of your
   arguments — check `_normalizedArgs` / `_asHostArgs` in
   `lib/src/vm/host_handler.dart` for how the built-ins normalise it.

---

## The host environment (`env.get`)

The host publishes an environment object the guest can read: viewport size,
platform, base URL, media-query state. `ElpianVmWidget` keeps it in sync —
`_updateHostEnvironmentCache` recomputes it on `didChangeDependencies` and
pushes it to the runtime when its digest changes, so a rotation or resize is
visible to the guest without a re-render.

```ts
const env = askHost('env.get', []);
```

---

## Driving the VM from Dart

The other direction — the host calling into the guest:

```dart
Future<String> callVmFunction(String funcName, {String? input});
```

and, at the Rust level:

```rust
execute_vm(machine_id)                                  // run the top level
execute_vm_func(machine_id, func_name, cb_id)
execute_vm_func_with_input(machine_id, func_name, input_json, cb_id)
deliver_host_message(machine_id, message_json, cb_id)   // push a message in
continue_execution(machine_id, input_json)              // resume after a host call
```

The embedder's loop is always: **execute → if `has_host_call`, service it →
`continue_execution` → repeat.**

---

## Integrations

`lib/src/integrations/` contains two prebuilt embeddings worth reading as
worked examples of the host side:

- **`nextjs_bridge.dart` / `nextjs_server_widget.dart`** — server-driven
  rendering with the same scope-patch model as the VM widget. See
  `NEXTJS_INTEGRATION.md`.
- **`client_comp_routing.dart`** — client component routing, and a second
  place where `node['events']` is read.
