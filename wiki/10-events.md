# 10 — The event system

40+ event types, three propagation phases, tree-aware dispatch, and a bridge
that turns a tap into a VM function call. Sources: `lib/src/core/event_system.dart`,
`event_dispatcher.dart`, `event_enabled_widget.dart`, and the routing in
`lib/src/vm/elpian_vm_widget.dart`. Narrative reference: `EVENT_SYSTEM.md`.

## Declaring a handler

Handlers live in the node's top-level **`events`** map, keyed by the lowercase
event name, valued by a **VM function name** (a string):

```json
{ "type": "button", "props": { "text": "Save" }, "events": { "click": "onSave" } }
```

Through the SDK's `el()`, write it as an `on*` prop and let the SDK do the split:

```ts
el('button', { text: 'Save', onClick: 'onSave' }, [])
// → props: { text: 'Save' },  events: { click: 'onSave' }
```

### Closures

`on*` also accepts a **closure**, which is what the generated SDK's templates
use:

```ts
el('button', { key: 'inc', text: '+1', onClick: () => { count++; render(view()); } }, [])
```

This matters most in a list, where a closure captures the item and a named
handler cannot:

```ts
items.map((item) => el('li', { text: item, onClick: () => { picked = item; render(view()); } }, []))
```

**The wire format is unchanged** — `events` values are still strings, because
`render()` serialises with `JSON.stringify`, which silently drops function
values. The SDK bridges the gap: a node carrying a closure is given a stable
`key`, its closures are stored in a registry on the guest side, and the wire gets
the name of one dispatcher, `__elpianEvent`. When the host fires the event it
calls that dispatcher, which looks the closure back up by `currentTarget` (the
element id, which *is* the node's key) and the event type.

So both forms work, and they interoperate:

| Form | Emitted `events` value |
|---|---|
| `onClick: 'increment'` | `"increment"` — the host calls that VM function |
| `onClick: () => …` | `"__elpianEvent"` — the SDK dispatches to the closure |

A node with a closure **must** have a key; the SDK assigns a positional one
(`__el0`, `__el1`, …) when you do not, and resets the counter on each `render()`
so the keys stay stable across renders.

---

## The full event catalogue

### Mouse / touch
`click` · `doubleClick` · `longPress` · `tap` · `tapDown` · `tapUp` · `tapCancel`

### Pointer
`pointerDown` · `pointerUp` · `pointerMove` · `pointerEnter` · `pointerExit` ·
`pointerHover` · `pointerCancel`

### Drag
`dragStart` · `drag` · `dragEnd` · `dragEnter` · `dragLeave` · `dragOver` · `drop`

### Focus
`focus` · `blur` · `focusIn` · `focusOut`

### Input
`input` · `change` · `submit`

### Keyboard
`keyDown` · `keyUp` · `keyPress`

### Gesture
`swipeLeft` · `swipeRight` · `swipeUp` · `swipeDown` ·
`pinchStart` · `pinchUpdate` · `pinchEnd` ·
`scaleStart` · `scaleUpdate` · `scaleEnd` ·
`rotateStart` · `rotateUpdate` · `rotateEnd`

### Other
`scroll` · `resize` · `load` · `unload` · `custom`

---

## How a tap becomes a VM call

```
1. EventEnabledWidget.build
     if (node.events == null || node.events!.isEmpty) return child;   ← unwrapped!
     wraps in GestureDetector when events contains any of:
       click, tap, doubletap, longpress, tapdown, tapup, tapcancel, drag, …

2. GestureDetector.onTap fires
     if (events.containsKey('tap'))   dispatch ElpianEvent(type: 'tap', …)
     if (events.containsKey('click')) dispatch click

3. EventDispatcher propagates through the node tree (capture → target → bubble)

4. ElpianVmWidget._routeEventToVm(event)
     nodeId  = event.currentTarget
     node    = _engine.eventDispatcher.getNode(nodeId)
     handler = node?.events?[event.type]
     if (handler is! String || handler.isEmpty) return;              ← dropped

5. payload = jsonEncode(_toTypedVmValue(_eventToJson(event)))
   await runtimeVm.callFunctionWithInput(handler, payload)
   // on throw, retry: await runtimeVm.callFunction(handler)
```

Step 1 is the one that surprises people: **with no `events` map, no gesture
detector is attached at all.** The tap is not captured, so nothing downstream
ever runs. A button that renders perfectly but ignores clicks almost always means
the handler ended up in `props` instead of `events`.

`Button` is a special case — it dispatches **both** `click` and `tap` from its
`onPressed` so handlers registered under either name fire.

---

## The event payload your handler receives

Every handler is called with the event as its argument (and retried with no
argument if that throws, so zero-parameter handlers are fine).

Base fields, present on every event:

```ts
{
  type: string,          // "click"
  eventType: string,     // the ElpianEventType enum name
  target: string,        // element id where it originated
  currentTarget: string, // element id the handler is attached to
  timestamp: string,     // ISO-8601
  phase: string,         // "capturing" | "atTarget" | "bubbling"
  data: any              // event-specific payload
}
```

Extra fields by event class:

**Pointer events** — `position {x,y}`, `localPosition {x,y}`, `delta {x,y}`,
`buttons`, `pressure`, `distance`, `pointerId`

**Keyboard events** — `key`, `keyCode`, `altKey`, `ctrlKey`, `shiftKey`,
`metaKey`

**Input events** — `value`, `inputType`

**Gesture events** — `velocity {x,y}`, `scale`, `rotation`, `focalPoint {x,y}`

Example:

```ts
function onDraft(event) {
  draft = event.value;              // ElpianInputEvent
}

function onCanvasDrag(event) {
  brushX = event.localPosition.x;   // ElpianPointerEvent
  brushY = event.localPosition.y;
  render(view());
}
```

---

## Identifying *which* element fired

Because handlers are names rather than closures, a list of items cannot capture
`item.id` in the handler. Two working patterns:

**1. Read the id from the event (preferred).** Set a stable `key` on each node;
it becomes the element id, and arrives as `event.currentTarget`.

```ts
function view() {
  return el('ul', {}, todos.map(function (t) {
    return el('li', { key: 'todo-' + t.id, text: t.text, onClick: 'toggle' }, []);
  }));
}

function toggle(event) {
  const id = parseInt(event.currentTarget.slice('todo-'.length));
  for (let i = 0; i < todos.length; i++) {
    if (todos[i].id === id) { todos[i].done = !todos[i].done; }
  }
  render(view());
}
```

**2. A handler per item.** Only viable for small fixed sets — each name must be
a real top-level function, so you cannot generate them dynamically.

---

## Propagation and phases

Events travel **capturing → at target → bubbling**, so a parent can handle a
child's click:

```json
{ "type": "div", "events": { "click": "onListClick" },
  "children": [ { "type": "li", "props": { "text": "One" } } ] }
```

This is **event delegation** — one handler on the container, `event.target`
telling you which child was hit. It is the efficient pattern for long lists.

Control methods on the event object: `stopPropagation()`, `preventDefault()`,
`stopImmediatePropagation()`.

## The event bus and utilities

Beyond node-attached handlers, the system provides:

- **Event bus** — global broadcast, subscribe to a type anywhere.
- **Global handler** — `engine.setGlobalEventHandler((event) { … })`. This is
  exactly what `ElpianVmWidget` installs to route everything into the VM:
  ```dart
  _engine.setGlobalEventHandler((event) { _routeEventToVm(event); });
  ```
- **Debounce / throttle** helpers for high-frequency events (`pointerMove`,
  `scroll`, `input`).

---

## Timers, not `async`

There is no `async`/`await` in the guest. Deferred work uses the timer host APIs
(`lib/src/vm/timer_host_api.dart`), which call back into the VM by function name:

```ts
askHost('setTimeout', ['tick', 1000]);
askHost('setInterval', ['frame', 16]);
askHost('clearInterval', [handle]);
```

`VmTimerHostApi` invokes them exactly like an event handler:

```dart
invoke: (funcName, inputJson) async {
  if (inputJson == null) await runtimeVm.callFunction(funcName);
  else                   await runtimeVm.callFunctionWithInput(funcName, inputJson);
}
```

See [`12-host-apis.md`](12-host-apis.md).

---

## Gotchas

1. **Handler in `props` instead of `events`** — renders fine, never fires. The
   number-one event bug.
2. **Event name case** — the map is keyed lowercase (`click`, not `Click` or
   `onClick`). The SDK lowercases for you (`onDoubleClick` → `doubleclick`);
   check the catalogue above for the exact spelling the dispatcher uses.
3. **No stable `key`** → the element id is a synthesised `element_<hashCode>`
   that changes across rebuilds. Always set `key` on interactive nodes.
4. **Handlers run in a later turn.** Do not expect a handler to have run by the
   next line after the render that drew it.
5. **A handler that throws is retried without arguments**, then swallowed with a
   `debugPrint`. If nothing happens and no error surfaces, check the Flutter
   console for `ElpianVmWidget: Error calling event handler "…"`.

---

## Best practices

1. **Use Event Delegation** - For handling many similar elements
2. **Stop Propagation Wisely** - Only when necessary
3. **Debounce/Throttle** - For high-frequency events (scroll, resize, input)
4. **Clean Up Listeners** - Remove listeners when elements are destroyed
5. **Use Type-Safe Events** - Check event types before accessing properties
6. **Log Selectively** - Use global handler for debugging, not production
7. **Prevent Default Carefully** - Only when you need to override default behavior

## Performance

- Avoid adding too many event listeners
- Use event delegation for repeated elements
- Throttle/debounce high-frequency events
- Remove unused event listeners
- Use passive listeners when possible

*(Carried over from the root `EVENT_SYSTEM.md`, now removed.)*
