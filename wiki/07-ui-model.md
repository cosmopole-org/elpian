# 07 — The UI model: nodes, props, events, rendering

The VM has no widget concept. A guest produces **JSON**, and the Flutter host
(`ElpianEngine`) turns it into a real widget tree. This chapter is the contract
between the two. Get it right and everything else follows.

## The node shape

```json
{
  "type": "button",
  "key": "submit-btn",
  "props": { "text": "Save", "className": "primary lg" },
  "style": { "padding": "12", "backgroundColor": "#2196F3" },
  "events": { "click": "onSave" },
  "children": []
}
```

| Field | Type | Meaning |
|---|---|---|
| `type` | string | **Required.** A registered tag — see [`08-widgets.md`](08-widgets.md) |
| `props` | object | Widget properties (`text`, `src`, `className`, widget-specific keys) |
| `style` | object | Inline CSS — see [`09-styling.md`](09-styling.md) |
| `events` | object | **`eventName → VM function name`** — see below |
| `children` | array | Child nodes, recursively |
| `key` | string | Stable identity; also used as the CSS `#id` selector |

`ElpianNode.fromJson` (`lib/src/models/elpian_node.dart`) parses exactly this.
A top-level `style` is folded into `props['style']` if props does not already
have one, so both spellings work for styling.

---

## `props` vs `events` — the single most important rule

> **Event handlers live in a top-level `events` map, keyed by the lowercase
> event name. They are NOT props.**

```json
✅ { "type": "button", "props": { "text": "Go" }, "events": { "click": "go" } }
❌ { "type": "button", "props": { "text": "Go", "onClick": "go" } }
```

The engine reads handlers only from `json['events']`:

```dart
events: json['events'] as Map<String, dynamic>?,
```

Nothing anywhere in `elpian_ui` maps `props.onClick` → `events.click`. And
`EventEnabledWidget` returns the child **unwrapped** when `events` is null or
empty:

```dart
if (widget.node.events == null || widget.node.events!.isEmpty) {
  return result;                     // no GestureDetector is attached at all
}
```

So the failure mode of getting this wrong is not "the handler is dropped later"
— **no gesture detector is ever attached**, the tap is never captured, and the
button silently does nothing while looking perfectly fine.

The generated SDK's `el()` handles the split for you, converting any `on*` string
prop into an `events` entry (`onClick` → `events.click`). If you write your own
node builder, you must do the same.

---

## The render loop

```
guest                          host (ElpianVmWidget)
  │                                 │
  │ render(view())                  │
  │  → askHost("render", json)      │
  ├────────────────────────────────▶│ HostHandler.onRender(viewJson, scopeKey)
  │                                 │   setState(() => _applyRenderUpdate(…))
  │                                 │   ElpianEngine builds the widget tree
  │                                 │
  │        ┌── user taps a button ──┤ EventDispatcher fires
  │        │                        │ node.events['click'] → "increment"
  │◀───────┴────────────────────────┤ callFunctionWithInput("increment", eventJson)
  │ increment() { … render(view()) }│
```

Four properties of this loop:

1. **Nothing is reactive.** Mutating a variable does not redraw. You call
   `render()` yourself.
2. **A render is a full tree**, not a diff. You rebuild the JSON from your state
   every time. (Scoped renders, below, bound the *application* of that tree.)
3. **Handlers run in a separate turn.** The click is a fresh
   `callFunctionWithInput`, not a continuation of the render that drew the
   button.
4. **State lives in module-level variables** in the guest, persisting for the
   life of the VM instance.

### Handler signatures

The host calls your handler **with the event JSON as input**:

```dart
final payload = jsonEncode(_toTypedVmValue(_eventToJson(event)));
await runtimeVm.callFunctionWithInput(handler, payload);
```

If that throws, it retries with no argument:

```dart
try { await runtimeVm.callFunction(handler); } catch (…) { debugPrint(…); }
```

So both of these work:

```ts
function increment() { … }                 // extra arg ignored
function onInput(event) { … }              // receives the event object
```

The event object's shape is in [`10-events.md`](10-events.md).

---

## Scoped rendering — partial updates

Re-emitting the whole tree on every keystroke is wasteful. `Scope` nodes create
**independent re-render boundaries** (`lib/src/vm/scoped_components.dart`,
`lib/src/vm/scope_patch.dart`).

```dart
Map<String, dynamic> scopedComponent(String key, Map<String, dynamic> component)
// → { "type": "Scope", "key": "<key>__scope", "props": {}, "children": [component] }
```

A scoped render targets an inner key; `ScopePatch` then bumps only that
wrapper's render token, leaving sibling component widgets cached and untouched.

`_applyRenderUpdate` is **bounded** — a scoped render whose key is not present
in the current tree is *not* allowed to fall back to replacing the whole view:

```dart
final next = ScopePatch.applyBounded(_currentViewJson, incomingViewJson, scopeKey);
if (next == null) {
  debugPrint('scoped render targeted missing scope "$scopeKey"; keeping current view');
  return;
}
```

`isolateComponentChildren(root, namespace)` wraps each direct child of a
component root in a keyed `Scope` automatically, giving every child its own
boundary.

Use `Scope` when one part of a screen updates far more often than the rest — a
list that streams, a form field, a game HUD over a static scene.

---

## Styling hooks on a node

Three ways to style, cascading in this order (see
[`09-styling.md`](09-styling.md)):

```json
{
  "type": "div",
  "key": "hero",                              // → the #hero selector
  "props": { "className": "card elevated" },  // → the .card and .elevated selectors
  "style": { "padding": "24" }                // → inline, highest priority
}
```

`className` accepts a space-separated string **or** an array of strings. The
engine computes the cascade via
`_stylesheetManager.getComputedStyleMap(tagName:, id:, classes:, inlineStyles:)`,
so `!important` priority works across all three.

---

## Special-case behaviour worth knowing

The engine detects **viewport-locked roots** and skips document scrolling for
them. A root counts as viewport-locked if its fully-cascaded style has
`position: fixed`, or a height containing `vh` or equal to `100%`, **or** if its
subtree contains a 3D scene node within 6 levels:

```dart
static const _sceneTypes = {
  'Scene3D', 'scene3d',
};
```

The rationale is in the source: a screen embedding a 3D scene is a full-bleed
stage, never a scrolling document — scenes cannot be measured for intrinsic
height, so document-scrolling one would break its `flex`/`100%` fill.

Otherwise the root is wrapped in a `SingleChildScrollView` + `ConstrainedBox`
with `minHeight` from the incoming constraints.

---

## Embedding: `ElpianVmWidget`

The Flutter side of the contract (`lib/src/vm/elpian_vm_widget.dart`):

```dart
ElpianVmWidget.fromBytecode({
  required String machineId,
  required Uint8List bytecode,
  ElpianRuntime runtime = ElpianRuntime.elpian,
  ElpianEngine? engine,
  Map<String, dynamic>? stylesheet,
  Widget? loadingWidget,
  Widget Function(String error)? errorBuilder,
  void Function(String message)? onPrintln,
  void Function(Map<String, dynamic> data)? onUpdateApp,
  Map<String, HostCallHandler>? hostHandlers,
  String? entryFunction,
  String? entryInput,
});
```

Four constructors: `ElpianVmWidget(...)` (generic), `.fromAst(astJson:)`,
`.fromCode(code:)` (compiles JS in-VM), `.fromBytecode(bytecode:)`.

| Parameter | Use |
|---|---|
| `machineId` | Unique VM id — also the key for governance calls |
| `engine` | Supply your own `ElpianEngine` to pre-register custom widgets |
| `stylesheet` | A JSON stylesheet loaded before first render |
| `hostHandlers` | Custom `askHost` APIs — see [`12-host-apis.md`](12-host-apis.md) |
| `entryFunction` / `entryInput` | Call a named function after load instead of just running the top level |
| `onPrintln` | Receives `println` output |
| `onUpdateApp` | Receives `updateApp` payloads; re-runs `entryFunction` if set |

Driving the VM from Dart:

```dart
Future<String> callVmFunction(String funcName, {String? input});
```

---

## A complete minimal client program

```ts
import { el, render } from '@elpian/sdk';

type Todo = { id: number; text: string; done: boolean };
let todos: Todo[] = [];
let draft: string = '';
let nextId: number = 1;

function view() {
  return el('div', { className: 'app', style: { padding: '24' } }, [
    el('h1', { text: 'Todos' }, []),
    el('input', { value: draft, placeholder: 'What needs doing?',
                  onInput: 'onDraft' }, []),
    el('button', { text: 'Add', onClick: 'add' }, []),
    el('ul', {}, todos.map(function (t) {
      return el('li', { text: (t.done ? '✔ ' : '') + t.text,
                        onClick: 'toggle' + t.id }, []);
    })),
  ]);
}

function onDraft(event) { draft = event.data.value; }
function add() {
  if (draft.length === 0) { return; }
  todos.push({ id: nextId, text: draft, done: false });
  nextId = nextId + 1;
  draft = '';
  render(view());
}

render(view());
```

> Note the `'toggle' + t.id` handler naming: because handlers are **names, not
> closures**, a per-item handler needs either a distinct named function per item
> or — better — a single handler that reads the target's identity out of the
> event (`event.currentTarget`, or a `key` you set on the node). See
> [`10-events.md`](10-events.md).
