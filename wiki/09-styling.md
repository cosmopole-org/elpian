# 09 — The styling system

Elpian ships a real CSS engine in Dart: **201 style properties** on `CSSStyle`
(`lib/src/models/css_style.dart`), a parser (`lib/src/css/css_parser.dart`,
1200 lines), a stylesheet manager with cascade and `!important`, JSON
stylesheets, CSS variables, media queries and keyframes.

## Three ways to apply style, in cascade order

```json
{
  "type": "div",
  "key": "hero",                              // → #hero
  "props": { "className": "card elevated" },  // → .card, .elevated
  "style": { "padding": "24" }                // → inline (highest priority)
}
```

The engine computes the result with:

```dart
_stylesheetManager.getComputedStyleMap(
  tagName: …, id: node.key, classes: …, inlineStyles: …);
```

so tag selectors, `#id`, `.class` and inline styles all participate, and
`!important` wins across all three.

`className` accepts a **space-separated string or an array of strings**.

## Property names

Both spellings are accepted throughout — use whichever suits your source
language:

```json
{ "backgroundColor": "#2196F3" }     // camelCase
{ "background-color": "#2196F3" }    // kebab-case
```

## Units

| Unit | Resolution |
|---|---|
| unitless / `px` | logical pixels |
| `%` | percentage of the parent's content box |
| `vw` / `vh` | `n / 100 * viewport width|height` |

Percentage sizing is **not** baked into a pixel value at parse time. `CSSStyle`
carries `widthFactor` / `heightFactor` alongside pixel `width`/`height`, and the
comment explains why:

> CSS resolves `%` against the *parent's* content box, so these are applied at
> layout time via a `FractionallySizedBox` rather than baked into a pixel value
> (which would wrongly resolve against the viewport). The pixel width/height
> above are still populated (viewport-resolved) and used as a fallback only when
> the parent's matching axis is unbounded.

## The property surface

### Box model & sizing
`width` `height` `minWidth` `maxWidth` `minHeight` `maxHeight`
`padding` (+ `paddingTop/Right/Bottom/Left`)
`margin` (+ `marginTop/Right/Bottom/Left`)
`boxSizing` `objectFit` `objectPosition` `aspectRatio`

`aspectRatio` is a width/height ratio (`16/9` → 1.777…) that "lets a box derive
one axis from the other so media (3D scenes, images) keep their shape across
screen sizes instead of squashing".

### Positioning
`position` (`relative` `absolute` `fixed` `sticky`) `top` `right` `bottom`
`left` `zIndex`

### Display, flex & overflow
`display` (`flex` `block` `inline` `inline-block` `grid` `none`)
`flexDirection` (`row` `column` `row-reverse` `column-reverse`)
`justifyContent` `alignItems` `alignContent` `alignSelf`
`flex` `flexGrow` `flexShrink` `flexBasis` `flexWrap` `order`
`gap` `rowGap` `columnGap`
`overflow` `overflowX` `overflowY`

### Grid
`gridTemplateColumns` `gridTemplateRows` `gridTemplateAreas`
`gridAutoColumns` `gridAutoRows` `gridAutoFlow`
`gridGap` `gridColumnGap` `gridRowGap`
`gridColumn` `gridRow` `gridArea` `justifyItems` `justifySelf`

### Background
`backgroundColor` `backgroundImage` `backgroundSize` `backgroundPosition`
`backgroundRepeat` `backgroundAttachment` `backgroundClip` `backgroundOrigin`
`gradient` `gradientColors` `gradientStops`

### Border & outline
`border` `borderRadius` `borderColor` `borderWidth` `borderStyle`
`borderTop/Right/Bottom/Left`
`borderTopLeftRadius` `borderTopRightRadius` `borderBottomLeftRadius`
`borderBottomRightRadius`
`outlineColor` `outlineWidth` `outlineStyle` `outlineOffset`

### Text
`color` `fontSize` `fontWeight` `fontStyle` `fontFamily`
`letterSpacing` `wordSpacing` `lineHeight` `textAlign`
`textDecoration` `textDecorationColor` `textDecorationStyle`
`textDecorationThickness` `textOverflow` `textTransform`
`whiteSpace` `textBaseline` `verticalAlign` `writingMode` `textOrientation`

### Shadow
`boxShadow` `textShadow` `dropShadow`

### Transform
`transform` `rotate` `rotateX` `rotateY` `rotateZ`
`scale` `scaleX` `scaleY` `translate` `translateX` `translateY`
`skewX` `skewY` `transformOrigin` `transformStyle`
`perspective` `perspectiveOrigin` `backfaceVisibility`

### Visibility & interaction
`opacity` `visible` `visibility`
`cursor` `pointerEvents` `userSelect` `touchAction`

### Clipping & filters
`clipBehavior` `clipPath` `shape`
`blur` `brightness` `contrast` `grayscale` `hueRotate` `invert` `saturate`
`sepia` `backdropColor` `backdropBlur`

### Transition & animation
`transitionDuration` `transitionCurve` `transitionProperty` `transitionDelay`
`animationName` `animationDuration` `animationTimingFunction` `animationDelay`
`animationIterationCount` `animationDirection` `animationFillMode`
`animationPlayState`

### Advanced animation (Elpian extensions)
`animateOnBuild` `staggerDelay` `staggerChildren`
`animationFrom` `animationTo`
`slideBegin`/`slideEnd`, `scaleBegin`/`scaleEnd`, `rotationBegin`/`rotationEnd`,
`fadeBegin`/`fadeEnd`, `colorBegin`/`colorEnd`,
`paddingBegin`/`paddingEnd`, `alignmentBegin`/`alignmentEnd`
`shimmerBaseColor` `shimmerHighlightColor`
`animationAutoReverse` `animationRepeat` `keyframes`

These drive the `Animated*` / `*Transition` / `Shimmer` / `Pulse` widgets
declaratively — you set begin/end values in `style` rather than wiring a
controller.

---

## JSON stylesheets

A complete stylesheet is expressible as JSON — rules, media queries, variables
and keyframes (`lib/src/css/json_stylesheet_parser.dart`, `JSON_STYLESHEET.md`).

```json
{
  "variables": { "primary-color": "#2196F3", "space": 16 },
  "rules": [
    { "selector": ".card",
      "styles": { "padding": "16", "backgroundColor": "#FFFFFF", "borderRadius": 8 } },
    { "selector": ".card:hover",
      "styles": { "boxShadow": "0 4px 12px rgba(0,0,0,0.15)" } },
    { "selector": "#hero",
      "styles": { "height": "100vh", "display": "flex" } }
  ],
  "mediaQueries": [
    { "query": "min-width: 768",
      "rules": [ { "selector": ".card", "styles": { "padding": "24" } } ] }
  ],
  "keyframes": [
    { "name": "fadeIn",
      "frames": [ { "offset": 0, "styles": { "opacity": 0 } },
                  { "offset": 1, "styles": { "opacity": 1 } } ] }
  ]
}
```

### Loading

Pass it to the widget:

```dart
ElpianVmWidget.fromBytecode(
  machineId: 'app',
  bytecode: bytes,
  stylesheet: mySheetJson,
);
```

or load it into an engine directly:

```dart
final engine = ElpianEngine();
engine.loadStylesheet({ 'rules': [ … ] });
```

### Building one programmatically

```dart
final sheet = JsonStylesheetBuilder()
  .addRule('.card',   { 'padding': '16', 'backgroundColor': '#FFF', 'borderRadius': 8 })
  .addRule('.button', { 'backgroundColor': '#2196F3', 'color': '#FFFFFF' });
```

`StylePresets` provides pre-built patterns: `flexCenter`, `card`, `button`,
`grid`, `elevation`.

---

## Media queries

Responsive rules are evaluated against the live `MediaQuery`. `ElpianVmWidget`
tracks viewport changes and rebuilds the host environment cache when they
change, so a `min-width` rule flips on rotation or resize without a guest
re-render.

```json
{ "mediaQueries": [
    { "query": "max-width: 600",  "rules": [ … ] },
    { "query": "min-width: 1200", "rules": [ … ] }
] }
```

## CSS variables

```json
{ "variables": { "brand": "#2196F3" },
  "rules": [ { "selector": ".btn", "styles": { "backgroundColor": "var(--brand)" } } ] }
```

---

## Styling from a guest program

Inline, through the SDK's `el()`:

```ts
el('div', {
  className: 'card',
  style: {
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
    padding: '24',
    backgroundColor: '#101820',
    borderRadius: 12,
    boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
  },
}, children)
```

Values may be numbers or strings; the parser accepts both (`padding: 24` and
`padding: '24'` are equivalent). Colours accept `#RGB`, `#RRGGBB`, `#AARRGGBB`,
`rgb()`, `rgba()` and named colours.

## Gotchas

- **`Button` handles part of its own style.** Background, foreground, padding,
  border radius and elevation are consumed by its `ButtonStyle`; only `margin`,
  `opacity` and `width`/`height` are applied around it afterwards. Other
  properties may not land — wrap it in a styled `div`/`Container` instead.
- **`display: flex` on a `div` is honoured**, but `Column`/`Row` are the direct
  route and read the same flex properties.
- **`%` needs a bounded parent.** With an unbounded parent axis the pixel
  fallback (viewport-resolved) is used, which is usually not what you meant.
- **A subtree containing a 3D scene is treated as viewport-locked** and will not
  document-scroll — see [`07-ui-model.md`](07-ui-model.md).

---

## Converting CSS to JSON

Use the built-in converter:

```dart
final cssText = '''
  .card {
    padding: 16px;
    background-color: #FFFFFF;
  }
  
  h1 {
    font-size: 32px;
  }
''';

final jsonStylesheet = JsonStylesheetParser.cssToJson(cssText);
engine.loadStylesheet(jsonStylesheet);
```

This comprehensive JSON stylesheet system makes it easy to build consistent, maintainable, and responsive UIs entirely from JSON!

## Stylesheet best practices

1. **Use Semantic Class Names** - `.card`, `.button`, `.header`
2. **Create Utility Classes** - `.m-2`, `.p-3`, `.text-center`
3. **Leverage Variables** - Define colors and spacing once
4. **Use Media Queries** - Build responsive designs
5. **Combine Classes** - `className: "card shadow rounded"`
6. **Separate Concerns** - Keep styles in stylesheet, structure in UI JSON

*(Carried over from the root `JSON_STYLESHEET.md`, now removed.)*
