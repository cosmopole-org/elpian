# 08 — The widget & element catalog

`ElpianEngine` registers **161 tags** in `_registerDefaultWidgets()`
(`lib/src/core/elpian_engine.dart`). A node's `type` must be one of them (or a
tag you registered yourself). An unregistered type renders nothing.

Two naming families coexist and are freely mixable in one tree:

- **`PascalCase`** — Flutter widgets (`Container`, `Column`, `AnimatedOpacity`).
- **`lowercase`** — HTML elements (`div`, `h1`, `button`, `table`).

Choose per taste; HTML tags map onto Flutter widgets underneath, and both accept
the same `style` / `className` / `events` fields.

---

## Layout

| Tag | Notes |
|---|---|
| `Container` | props: `width`, `height`, `padding`, `margin`, `alignment`, `decoration` |
| `Column`, `Row` | Honour CSS `justifyContent`, `alignItems`, `gap`, `flexWrap` |
| `Stack`, `Positioned`, `IndexedStack` | Overlay layout |
| `Expanded`, `Flexible`, `Spacer` | Flex children |
| `Center`, `Align`, `Padding`, `SizedBox` | Simple wrappers |
| `Wrap` | Flow layout |
| `AspectRatio`, `FractionallySizedBox`, `FittedBox` | Sizing |
| `ConstrainedBox`, `LimitedBox`, `OverflowBox` | Constraint control |
| `Baseline`, `RotatedBox`, `DecoratedBox`, `ClipRRect` | Misc |

**`Column`/`Row` implement real CSS flex semantics**, not just Flutter's:

- `gap` inserts `SizedBox` separators between children.
- `flexWrap: 'wrap' | 'wrap-reverse'` switches the implementation to a `Wrap`
  (vertical for `Column`), with `wrap-reverse` flipping `verticalDirection`.
- `justifyContent` → `MainAxisAlignment`, `alignItems` → `CrossAxisAlignment`,
  accepting both CSS spellings (`flex-start`/`start`, `flex-end`/`end`) and
  `space-between` / `space-around` / `space-evenly`.

## Scrolling

`ListView`, `GridView`.

## Text & media

`Text` (props: `text` or `data`, `textAlign`, `maxLines`, `overflow`,
`softWrap`), `Image`, `Icon`.

## Controls

| Tag | Key props |
|---|---|
| `Button` | `text`; falls back to the first child if present |
| `TextField` | `hint` |
| `Checkbox`, `Radio`, `Switch`, `Slider` | value/state props |
| `Chip`, `Badge`, `Tooltip` | `text`-ish |
| `CircularProgressIndicator`, `LinearProgressIndicator` | |
| `Divider`, `VerticalDivider` | |

> **`Button` dispatches both `click` and `tap`.** Its `onPressed` fires
> `dispatchClick(elementId)` *and* an explicit `tap` event, "so that handlers
> registered under either name are triggered". Its element id is `node.key`, or
> a synthesised `element_<hashCode>` if you gave no key — **always set `key` on
> a `Button`** if you want stable identity.
>
> `Button` also consumes some style itself (background, foreground, padding,
> border radius, elevation from `boxShadow`) and only applies `margin`,
> `opacity` and `width`/`height` afterwards. Other style properties may not
> reach it.

## Interaction

`InkWell`, `GestureDetector`, `Dismissible`, `Draggable`, `DragTarget`,
`Opacity`, `Transform`, `Hero`.

## App structure

`Scaffold`, `AppBar`, `Card`, `Scope`.

`Scope` is not visual — it is a re-render boundary. See
[`07-ui-model.md`](07-ui-model.md).

## Animation (22 tags)

**Implicit** — animate on prop change:
`AnimatedContainer`, `AnimatedOpacity`, `AnimatedCrossFade`, `AnimatedSwitcher`,
`AnimatedAlign`, `AnimatedPadding`, `AnimatedPositioned`, `AnimatedScale`,
`AnimatedRotation`, `AnimatedSlide`, `AnimatedSize`,
`AnimatedDefaultTextStyle`, `AnimatedGradient`.

**Explicit transitions** — driven by a controller:
`FadeTransition`, `SlideTransition`, `ScaleTransition`, `RotationTransition`,
`SizeTransition`, `TweenAnimationBuilder`, `StaggeredAnimation`.

**Effects:** `Shimmer`, `Pulse`.

## Canvas & 3D

| Tag | Renderer |
|---|---|
| `Canvas`, `CachedCanvas` | 2D command list — [`11-canvas-and-3d.md`](11-canvas-and-3d.md) |
| `Scene3D`, `scene3d` | Embedded Godot 4 — [`11-canvas-and-3d.md`](11-canvas-and-3d.md) |

## Math

`MathExpression`, `Math` — rendered mathematical expressions.

---

## HTML elements

**Document structure** — `div`, `span`, `section`, `article`, `header`,
`footer`, `nav`, `aside`, `main`

**Typography** — `h1` `h2` `h3` `h4` `h5` `h6`, `p`, `strong`, `em`, `mark`,
`small`, `del`, `ins`, `sub`, `sup`, `abbr`, `cite`, `kbd`, `samp`, `var`,
`code`, `pre`, `blockquote`, `br`, `hr`, `time`, `data`

**Lists** — `ul`, `ol`, `li`

**Tables** — `table`, `tr`, `td`, `th`

**Forms** — `form`, `input`, `button`, `select`, `option`, `optgroup`,
`textarea`, `label`, `fieldset`, `legend`, `datalist`, `output`, `progress`,
`meter`

**Media** — `img`, `picture`, `source`, `figure`, `figcaption`, `video`,
`audio`, `track`, `canvas`, `iframe`, `embed`, `object`, `param`, `map`, `area`

**Interactive** — `a`, `details`, `summary`, `dialog`

### Common HTML props

| Tag | Props |
|---|---|
| `img` | `src`, `alt` |
| `input` | `type`, `value`, `placeholder`, `checked`, `groupValue` |
| `a` | `href` |
| text tags | `text` (or a text child) |

---

## Registering your own widget

From Dart, before handing the engine to `ElpianVmWidget`:

```dart
final engine = ElpianEngine();

engine.registerWidget('Sparkline', (node, children) {
  final points = (node.props['points'] as List?)?.cast<num>() ?? const [];
  return CustomPaint(painter: SparklinePainter(points), child: SizedBox(
    width: node.style?.width ?? 120, height: node.style?.height ?? 32));
});

// or in bulk
engine.registerWidgets({ 'Foo': Foo.build, 'Bar': Bar.build });
```

Then in the guest:

```ts
el('Sparkline', { points: [1, 4, 2, 8, 5] }, [])
```

The builder signature is
`Widget Function(ElpianNode node, List<Widget> children)` — children are already
built. `WidgetRegistry.unregister(type)` removes one.

---

## Picking a tag

| You want | Use |
|---|---|
| A styled box | `div` or `Container` |
| Vertical/horizontal stack with CSS flex | `Column` / `Row` (or `div` with `display: flex`) |
| Text | `p` / `h1`…`h6` / `span`, or `Text` |
| A tappable control | `button` / `Button`, or any node with `events.click` |
| A form field | `input` / `textarea` / `select`, or `TextField` |
| A scrolling list | `ListView`, or `ul` inside a scrolling parent |
| Custom drawing | `Canvas` |
| 3D | `Scene3D` (embedded Godot) |
| An isolated update region | `Scope` |

> Exhaustive per-widget prop lists are not duplicated here — they live in
> `lib/src/widgets/*.dart` and `lib/src/html_widgets/*.dart`, one small file per
> tag. Each is a single `static Widget build(ElpianNode node, List<Widget> children)`
> that reads `node.props[...]` and `node.style`; reading the file for the tag you
> need takes seconds and is always current.
