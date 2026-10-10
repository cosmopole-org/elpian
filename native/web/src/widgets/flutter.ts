/**
 * The Flutter-DSL widgets (`Container`, `Text`, `Column`, `Card`, `Slider` …)
 * — one builder per file in flutter/lib/src/widgets, lowered to the same
 * widget composition. Material visuals follow Flutter's Material 3 defaults.
 *
 * Where the Flutter builder is a placeholder (Dismissible's no-op callback,
 * Draggable/DragTarget without events, Scaffold ignoring its AppBar,
 * GestureDetector/InkWell swallowing taps), the native builder implements the
 * behaviour the widget is named for and reports it to the guest as events.
 */
import { Colors, M3, alphaOf, scaleAlpha, withOpacity, type Color } from '../css/color.js';
import { identity, rotationZ, scaling } from '../css/matrix.js';
import { CSSParser } from '../css/parser.js';
import type { CSSStyle } from '../css/style.js';
import { insetsAll, insetsSymmetric, radiusAll, type Alignment } from '../css/types.js';
import { makeEvent } from '../events/events.js';
import { textOf, type ElpianNode } from '../model/node.js';
import { w, type W } from '../render/object.js';
import { BODY_LARGE, LABEL_LARGE, TITLE_LARGE, toSpec, type TextStyle } from '../render/text-style.js';
import type { ViewEvent } from '../render/view.js';
import { commandFromJson, normalizeCommand } from '../canvas/store.js';
import { toNumber } from '../util/json.js';
import type { BuildContext, WidgetBuilder } from './context.js';
import { iconCodepoint } from './icons.js';
import {
  SHRINK,
  align,
  applyStyle,
  center,
  column,
  container,
  createTextStyle,
  decorated,
  decorationFromStyle,
  elevationShadows,
  expanded,
  padding,
  row,
  sizedBox,
  text,
  textOptionsFromStyle,
} from './style.js';

function first(children: W[]): W | null {
  return children[0] ?? null;
}

function num(v: unknown): number | null {
  return toNumber(v);
}

/** Dispatch an Elpian event from a builder-level interaction. */
export function dispatchEvent(ctx: BuildContext, type: string, extra: Record<string, any> = {}): void {
  const { engine, elementId } = ctx;
  if (type === 'change') engine.services.events.dispatchChange(elementId, extra.value);
  else if (type === 'input') engine.services.events.dispatchInput(elementId, extra.value);
  else if (type === 'submit') engine.services.events.dispatchSubmit(elementId, extra.data ?? {});
  else if (type === 'click') engine.services.events.dispatchClick(elementId, extra.position);
  else {
    const typeName = (
      { tap: 'tap', focus: 'focus', blur: 'blur', keydown: 'keyDown', keyup: 'keyUp', dismissed: 'custom', drop: 'drop' } as Record<string, any>
    )[type] ?? 'custom';
    engine.services.events.dispatchEvent(makeEvent(type, typeName, elementId, extra), elementId);
  }
}

// ----------------------------------------------------------------------------
// Material helpers
// ----------------------------------------------------------------------------

export interface ButtonOptions {
  child: W;
  style: CSSStyle | null | undefined;
  onPressed: (() => void) | null;
  variant?: 'elevated' | 'filled' | 'text' | 'outlined';
  semanticsLabel?: string | null;
}

/** An `ElevatedButton` (Material 3): stadium shape, 40 px tall in a 48 px tap target. */
export function materialButton(opts: ButtonOptions): W {
  const s = opts.style ?? {};
  const enabled = opts.onPressed != null;
  const variant = opts.variant ?? 'elevated';
  const hasBg = s.backgroundColor != null || s.gradient != null;
  let bg: Color | null = s.backgroundColor ?? (variant === 'elevated' ? M3.surfaceContainerLow : variant === 'filled' ? M3.primary : null);
  let fg: Color = s.color ?? (variant === 'filled' || hasBg ? Colors.white : M3.primary);
  if (!enabled) {
    bg = bg != null ? withOpacity(M3.onSurface, 0.12) : null;
    fg = withOpacity(M3.onSurface, 0.38);
  }
  const elevation = s.boxShadow && s.boxShadow.length ? s.boxShadow[0].blur / 2 : variant === 'elevated' && enabled ? 1 : 0;
  const decoration = {
    color: bg,
    gradients: s.gradient ? [s.gradient] : null,
    radius: s.borderRadius ?? null,
    radiusPercent: s.borderRadius ? null : radiusAll(50),
    shadows: s.boxShadow && s.boxShadow.length ? s.boxShadow : elevationShadows(elevation),
    border: variant === 'outlined' ? { top: side(M3.outline), right: side(M3.outline), bottom: side(M3.outline), left: side(M3.outline) } : s.border ?? null,
  };
  const pad = s.padding ?? insetsSymmetric(0, 24);
  let content: W = w('defaultTextStyle', { style: { ...LABEL_LARGE, color: fg } }, align({ x: 0, y: 0 }, opts.child, { widthFactor: 1, heightFactor: 1 }));
  content = padding(pad, content);
  content = w('constrained', { minWidth: 64, minHeight: 40 }, content);
  content = w('decorated', { decoration }, content);
  content = w(
    'gesture',
    {
      gestures: enabled ? ['tap'] : [],
      ripple: enabled ? scaleAlpha(fg, 0.12) : null,
      cursor: enabled ? 'pointer' : 'default',
      role: 'button',
      semanticsLabel: opts.semanticsLabel ?? null,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'tap') opts.onPressed?.();
      },
    },
    content,
  );
  // MaterialTapTargetSize.padded: 48 px tall interactive area.
  return padding({ top: 4, right: 0, bottom: 4, left: 0 }, content);
}

function side(color: Color) {
  return { width: 1, color, style: 'solid' as const };
}

/** Wrap a material button with the style parts Flutter applies outside it. */
export function buttonOuter(result: W, style: CSSStyle | null | undefined): W {
  if (!style) return result;
  if (style.margin) result = padding(style.margin, result);
  if (style.opacity != null && style.opacity < 1) result = w('opacity', { opacity: style.opacity }, result);
  if (style.width != null || style.height != null) result = sizedBox(style.width ?? null, style.height ?? null, result);
  if (style.flex != null || style.flexGrow != null) result = w('flexible', { flex: style.flex ?? style.flexGrow, fit: 'tight' }, result);
  return result;
}

export function buttonPressed(ctx: BuildContext): () => void {
  return () => {
    // ElevatedButton.onPressed: click, then tap.
    dispatchEvent(ctx, 'click');
    dispatchEvent(ctx, 'tap');
  };
}

function iconGlyph(name: string, size: number, color: Color | null): W {
  const glyph = String.fromCodePoint(iconCodepoint(name));
  return sizedBox(
    size,
    size,
    center(text(glyph, { fontFamily: 'icons', fontSize: size, color: color ?? M3.onSurfaceVariant, height: 1, letterSpacing: 0, wordSpacing: 0, decoration: 0 }, { softWrap: false })),
  );
}

export function icon(name: string, size = 24, color: Color | null = null): W {
  return iconGlyph(name, size, color);
}

function parseAlignmentProp(v: unknown, fallback: Alignment): Alignment {
  return CSSParser.parseAlignment(v) ?? fallback;
}

// ----------------------------------------------------------------------------
// Builders
// ----------------------------------------------------------------------------

export const flutterWidgets: Record<string, WidgetBuilder> = {
  Container(node, children, ctx) {
    let child: W | null = null;
    if (children.length === 1) child = children[0];
    else if (children.length > 1) child = column(children, { crossAxisAlignment: 'start', mainAxisSize: 'min' });
    const p = node.props;
    const decoration = p.decoration && typeof p.decoration === 'object' ? decorationFromStyle(CSSParser.parse(p.decoration), ctx) : null;
    let result = container({
      child,
      width: num(p.width),
      height: num(p.height),
      padding: CSSParser.parseEdgeInsets(p.padding),
      margin: CSSParser.parseEdgeInsets(p.margin),
      alignment: CSSParser.parseAlignment(p.alignment),
      decoration,
    });
    return applyStyle(result, node.style, {}, ctx);
  },

  Text(node, _children, ctx) {
    const value = textOf(node);
    const style = createTextStyle(node.style);
    const opts: Record<string, any> = { ...textOptionsFromStyle(node.style) };
    if (typeof node.props.textAlign === 'string') opts.align = node.props.textAlign;
    if (num(node.props.maxLines) != null) opts.maxLines = num(node.props.maxLines);
    if (typeof node.props.overflow === 'string') opts.overflow = node.props.overflow;
    if (typeof node.props.softWrap === 'boolean') opts.softWrap = node.props.softWrap;
    if (node.props.selectable === true) opts.selectable = true;
    return applyStyle(text(value, style, opts), node.style, {}, ctx);
  },

  Button(node, children, ctx) {
    const label = String(node.props.text ?? 'Button');
    const s = node.style;
    const fg = s?.color ?? (s?.backgroundColor != null ? Colors.white : M3.primary);
    const child = first(children) ?? text(label, { color: fg });
    const enabled = node.props.disabled !== true && node.props.enabled !== false;
    return buttonOuter(materialButton({ child, style: s, onPressed: enabled ? buttonPressed(ctx) : null, semanticsLabel: label }), s);
  },

  Image(node, _children, ctx) {
    const raw = String(node.props.src ?? '');
    const fit = typeof node.props.fit === 'string' ? node.props.fit : 'contain';
    const src = ctx.engine.resolveUrl(raw);
    const result = w('image', {
      src,
      fit,
      width: node.style?.width ?? num(node.props.width),
      height: node.style?.height ?? num(node.props.height),
      alt: node.props.alt ?? null,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'load' || e.type === 'error') dispatchEvent(ctx, e.type, { value: e.value });
      },
    });
    return applyStyle(result, node.style, {}, ctx);
  },

  Column(node, children, ctx) {
    return applyStyle(flexOrWrap('column', node.style, children), node.style, {}, ctx);
  },

  Row(node, children, ctx) {
    return applyStyle(flexOrWrap('row', node.style, children), node.style, {}, ctx);
  },

  Stack(node, children, ctx) {
    const alignment = node.style?.alignment ?? { x: 0, y: 0 };
    return applyStyle(w('stack', { alignment, fit: 'loose' }, children), node.style, {}, ctx);
  },

  Positioned(node, children) {
    const s = node.style ?? {};
    return w(
      'positioned',
      { top: s.top ?? null, right: s.right ?? null, bottom: s.bottom ?? null, left: s.left ?? null, width: s.width ?? null, height: s.height ?? null },
      first(children) ?? container({}),
    );
  },

  Expanded(node, children) {
    return w('flexible', { flex: num(node.props.flex) ?? 1, fit: 'tight' }, first(children) ?? container({}));
  },

  Flexible(node, children) {
    return w('flexible', { flex: num(node.props.flex) ?? 1, fit: node.props.fit === 'tight' ? 'tight' : 'loose' }, first(children) ?? container({}));
  },

  Center(node, children, ctx) {
    return applyStyle(center(first(children) ?? container({})), node.style, {}, ctx);
  },

  Padding(node, children) {
    return padding(node.style?.padding ?? insetsAll(8), first(children) ?? container({}), node.style?.paddingPercent);
  },

  Align(node, children) {
    return align(node.style?.alignment ?? { x: 0, y: 0 }, first(children) ?? container({}));
  },

  SizedBox(node, children) {
    return sizedBox(node.style?.width ?? num(node.props.width), node.style?.height ?? num(node.props.height), first(children));
  },

  ListView(node, children, ctx) {
    const scrollable = node.props.scrollable !== false;
    const horizontal = node.props.scrollDirection === 'horizontal';
    const list = w('flex', { direction: horizontal ? 'row' : 'column', crossAxisAlignment: horizontal ? 'start' : 'stretch', mainAxisSize: 'min' }, children);
    const result = w('scroll', { axis: horizontal ? 'horizontal' : 'vertical', enabled: scrollable }, list);
    return applyStyle(result, node.style, {}, ctx);
  },

  GridView(node, children, ctx) {
    const count = Math.max(1, num(node.props.crossAxisCount) ?? 2);
    const spacing = num(node.props.crossAxisSpacing) ?? 0;
    const mainSpacing = num(node.props.mainAxisSpacing) ?? 0;
    const ratio = num(node.props.childAspectRatio) ?? 1;
    const grid = w(
      'grid',
      { columns: `repeat(${count}, 1fr)`, columnGap: spacing, rowGap: mainSpacing, alignItems: 'stretch' },
      children.map((c) => w('aspectRatio', { aspectRatio: ratio }, c)),
    );
    return applyStyle(w('scroll', { axis: 'vertical', enabled: node.props.scrollable !== false }, grid), node.style, {}, ctx);
  },

  TextField(node, _children, ctx) {
    const incoming = node.props.value != null ? String(node.props.value) : null;
    const state = ctx.engine.stateFor(ctx.elementId, () => ({ value: incoming ?? '', lastProp: incoming }));
    // didUpdateWidget: a changed `value` prop (e.g. a bound model update) wins.
    if (incoming !== state.lastProp) {
      if (incoming != null) state.value = incoming;
      state.lastProp = incoming;
    }
    const s = node.style;
    const textStyle: TextStyle = { ...BODY_LARGE, ...(createTextStyle(s) ?? {}) };
    const lines = Math.max(1, num(node.props.maxLines) ?? 1);
    const result = w('control', {
      kind: 'textInput',
      lines: node.props.multiline ? Math.max(lines, 3) : lines,
      padding: [12, 0, 12, 0],
      view: {
        value: state.value,
        placeholder: String(node.props.hint ?? node.props.placeholder ?? ''),
        inputType: node.props.obscureText ? 'password' : node.props.keyboardType ?? 'text',
        multiline: lines > 1 || !!node.props.multiline,
        maxLines: lines,
        maxLength: num(node.props.maxLength),
        enabled: node.props.enabled !== false,
        readOnly: node.props.readOnly === true,
        autofocus: node.props.autofocus === true,
        min: node.props.min ?? undefined,
        max: node.props.max ?? undefined,
        variant: 'underline',
        textStyle: toSpec(textStyle),
        hintStyle: toSpec({ ...textStyle, color: M3.onSurfaceVariant }),
        contentPadding: [12, 0, 12, 0],
        colors: { text: textStyle.color ?? M3.onSurface, hint: M3.onSurfaceVariant, border: M3.onSurfaceVariant, focusedBorder: M3.primary, cursor: M3.primary, fill: null },
      },
      onEvent: (e: ViewEvent) => {
        if (e.type === 'input' || e.type === 'change') {
          state.value = String(e.value ?? '');
          dispatchEvent(ctx, 'input', { value: state.value });
        } else if (e.type === 'submit') dispatchEvent(ctx, 'submit');
        else if (e.type === 'focus' || e.type === 'blur') dispatchEvent(ctx, e.type);
      },
    });
    return applyStyle(result, s, {}, ctx);
  },

  Checkbox(node, _children, ctx) {
    const value = node.props.value === true;
    return w('control', {
      kind: 'checkbox',
      view: { checked: value, enabled: node.props.enabled !== false, colors: { fill: node.style?.color ?? M3.primary, check: M3.onPrimary, border: M3.onSurfaceVariant } },
      controlled: true,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'change') dispatchEvent(ctx, 'change', { value: !!e.value });
      },
    });
  },

  Radio(node, _children, ctx) {
    const value = node.props.value;
    const group = node.props.groupValue;
    return w('control', {
      kind: 'radio',
      view: { checked: value === group && value !== undefined, value: value ?? null, colors: { fill: node.style?.color ?? M3.primary, border: M3.onSurfaceVariant } },
      controlled: true,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'change') dispatchEvent(ctx, 'change', { value });
      },
    });
  },

  Switch(node, _children, ctx) {
    const value = node.props.value === true;
    return w('control', {
      kind: 'switch',
      view: {
        checked: value,
        enabled: node.props.enabled !== false,
        colors: { trackOn: node.style?.color ?? M3.primary, thumbOn: M3.onPrimary, trackOff: M3.surfaceContainerHighest, thumbOff: M3.outline, outline: M3.outline },
      },
      controlled: true,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'change') dispatchEvent(ctx, 'change', { value: !!e.value });
      },
    });
  },

  Slider(node, _children, ctx) {
    const min = num(node.props.min) ?? 0;
    const max = num(node.props.max) ?? 1;
    const value = Math.max(min, Math.min(max, num(node.props.value) ?? 0.5));
    const divisions = num(node.props.divisions);
    return w('control', {
      kind: 'slider',
      view: {
        value,
        min,
        max,
        step: divisions && divisions > 0 ? (max - min) / divisions : null,
        enabled: node.props.enabled !== false,
        colors: { active: node.style?.color ?? M3.primary, inactive: M3.secondaryContainer, thumb: node.style?.color ?? M3.primary },
      },
      controlled: true,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'change' || e.type === 'input') dispatchEvent(ctx, 'change', { value: Number(e.value) });
      },
    });
  },

  Icon(node, _children, ctx) {
    const name = String(node.props.icon ?? 'star');
    const size = node.style?.fontSize ?? num(node.props.size) ?? 24;
    return applyStyle(icon(name, size, node.style?.color ?? null), node.style, {}, ctx);
  },

  Card(node, children, ctx) {
    const s = node.style ?? {};
    let child: W = children.length === 0 ? SHRINK : children.length === 1 ? children[0] : column(children);
    const elevation = s.boxShadow && s.boxShadow.length ? s.boxShadow[0].blur / 2 : num(node.props.elevation) ?? 1;
    if (s.padding) child = padding(s.padding, child);
    const border = s.borderColor != null ? { width: s.borderWidth ?? 1, color: s.borderColor, style: 'solid' as const } : null;
    const radius = s.borderRadius ?? radiusAll(12);
    let result: W = w('clip', { radius }, child);
    result = decorated(
      {
        color: s.backgroundColor ?? M3.surfaceContainerLow,
        radius,
        shadows: elevationShadows(elevation),
        border: border ? { top: border, right: border, bottom: border, left: border } : null,
      },
      result,
    );
    result = padding(insetsAll(4), result);
    const external: CSSStyle = {
      width: s.width,
      height: s.height,
      minWidth: s.minWidth,
      maxWidth: s.maxWidth,
      minHeight: s.minHeight,
      maxHeight: s.maxHeight,
      margin: s.margin,
      opacity: s.opacity,
      flex: s.flex,
      transform: s.transform,
      rotate: s.rotate,
      scale: s.scale,
      alignment: s.alignment,
      visible: s.visible,
    };
    for (const k of Object.keys(external) as (keyof CSSStyle)[]) if (external[k] == null) delete external[k];
    return applyStyle(result, external, {}, ctx);
  },

  Scaffold(node, children, ctx) {
    let appBar: W | null = null;
    let fab: W | null = null;
    let bottom: W | null = null;
    const body: W[] = [];
    node.children.forEach((child, i) => {
      const slot = child.props.slot;
      if (child.type === 'AppBar' || slot === 'appBar') appBar = children[i];
      else if (slot === 'floatingActionButton' || child.type === 'FloatingActionButton') fab = children[i];
      else if (slot === 'bottomNavigationBar' || slot === 'bottomBar') bottom = children[i];
      else body.push(children[i]);
    });
    const bodyW = body.length ? body[body.length - 1] : SHRINK;
    const columnChildren: W[] = [];
    if (appBar) columnChildren.push(appBar);
    columnChildren.push(expanded(w('align', { alignment: { x: -1, y: -1 } }, bodyW)));
    if (bottom) columnChildren.push(bottom);
    let result: W = w('flex', { direction: 'column', crossAxisAlignment: 'stretch', mainAxisSize: 'max' }, columnChildren);
    if (fab) {
      result = w('stack', { alignment: { x: -1, y: -1 }, fit: 'expand' }, [result, w('positioned', { right: 16, bottom: 16 + (bottom ? 80 : 0) }, fab)]);
    }
    result = decorated({ color: node.style?.backgroundColor ?? M3.surface }, w('defaultTextStyle', { style: {} }, result));
    return result;
  },

  AppBar(node, children, ctx) {
    const title = String(node.props.title ?? '');
    const s = node.style ?? {};
    const fg = s.color ?? M3.onSurface;
    const row1: W[] = [];
    const leading = node.children.findIndex((c) => c.props.slot === 'leading');
    if (leading >= 0) row1.push(padding({ top: 0, right: 0, bottom: 0, left: 4 }, sizedBox(48, 48, center(children[leading]))));
    row1.push(expanded(padding({ top: 0, right: 16, bottom: 0, left: 16 }, text(title, { ...TITLE_LARGE, color: fg }, { maxLines: 1, overflow: 'ellipsis', softWrap: false }))));
    node.children.forEach((c, i) => {
      if (i !== leading && c.props.slot !== 'title') row1.push(children[i]);
    });
    let bar: W = sizedBox(null, s.height ?? 64, w('flex', { direction: 'row', crossAxisAlignment: 'center', mainAxisSize: 'max' }, row1));
    // A primary AppBar extends under the status bar (MediaQuery padding top).
    if (node.props.primary !== false) bar = w('safeArea', { top: true }, bar);
    return decorated({ color: s.backgroundColor ?? M3.surface, shadows: num(node.props.elevation) ? elevationShadows(num(node.props.elevation)!) : null }, w('defaultTextStyle', { style: { color: fg } }, bar));
  },

  Wrap(node, children, ctx) {
    const s = node.style;
    const result = w('wrap', { direction: 'horizontal', spacing: s?.gap ?? 8, runSpacing: s?.rowGap ?? 8, alignment: 'start' }, children);
    return applyStyle(result, s, {}, ctx);
  },

  InkWell(node, children, ctx) {
    const child = first(children) ?? container({});
    const result = w('gesture', { gestures: ['tap'], ripple: scaleAlpha(node.style?.color ?? M3.onSurface, 0.12), cursor: 'pointer', onEvent: () => {} }, child);
    return applyStyle(result, node.style, {}, ctx);
  },

  GestureDetector(_node, children) {
    // Events on the node are recognised by the engine's gesture region.
    return w('proxy', {}, first(children) ?? container({}));
  },

  Opacity(node, children) {
    const opacity = node.style?.opacity ?? num(node.props.opacity) ?? 1;
    return w('opacity', { opacity }, first(children) ?? container({}));
  },

  Transform(node, children) {
    let m = node.style?.transform ?? identity();
    if (node.style?.rotate != null) m = rotationZ((node.style.rotate * Math.PI) / 180);
    if (node.style?.scale != null) m = scaling(node.style.scale, node.style.scale, 1);
    return w('transform', { transform: m, alignment: { x: 0, y: 0 } }, first(children) ?? container({}));
  },

  ClipRRect(node, children) {
    return w('clip', { radius: node.style?.borderRadius ?? radiusAll(8) }, first(children) ?? container({}));
  },

  ConstrainedBox(node, children) {
    const s = node.style ?? {};
    return w('constrained', { minWidth: s.minWidth ?? 0, maxWidth: s.maxWidth ?? null, minHeight: s.minHeight ?? 0, maxHeight: s.maxHeight ?? null }, first(children) ?? container({}));
  },

  AspectRatio(node, children) {
    return w('aspectRatio', { aspectRatio: num(node.props.aspectRatio) ?? node.style?.aspectRatio ?? 1 }, first(children) ?? container({}));
  },

  FractionallySizedBox(node, children) {
    return w(
      'fractional',
      { widthFactor: num(node.props.widthFactor), heightFactor: num(node.props.heightFactor), alignment: node.style?.alignment ?? { x: 0, y: 0 } },
      first(children),
    );
  },

  FittedBox(node, children) {
    const fit = typeof node.props.fit === 'string' ? node.props.fit : 'contain';
    return w('fitted', { fit, alignment: node.style?.alignment ?? { x: 0, y: 0 } }, w('fittedContent', {}, first(children) ?? container({})));
  },

  LimitedBox(node, children) {
    return w('limited', { maxWidth: node.style?.maxWidth ?? null, maxHeight: node.style?.maxHeight ?? null }, first(children) ?? container({}));
  },

  OverflowBox(node, children) {
    const s = node.style ?? {};
    return w(
      'overflowBox',
      { alignment: s.alignment ?? { x: 0, y: 0 }, minWidth: s.minWidth ?? null, maxWidth: s.maxWidth ?? null, minHeight: s.minHeight ?? null, maxHeight: s.maxHeight ?? null },
      first(children) ?? container({}),
    );
  },

  Baseline(node, children) {
    return w('baseline', { baseline: num(node.props.baseline) ?? 0 }, first(children) ?? container({}));
  },

  Spacer(node) {
    return w('flexible', { flex: num(node.props.flex) ?? 1, fit: 'tight' }, SHRINK);
  },

  Divider(node) {
    const s = node.style ?? {};
    const thickness = s.borderWidth ?? 1;
    const height = s.height ?? 16;
    const indent = num(node.props.indent) ?? 0;
    const endIndent = num(node.props.endIndent) ?? 0;
    return sizedBox(
      null,
      height,
      center(padding({ top: 0, right: endIndent, bottom: 0, left: indent }, container({ height: thickness, decoration: { color: s.borderColor ?? s.color ?? M3.outlineVariant } }))),
    );
  },

  VerticalDivider(node) {
    const s = node.style ?? {};
    const thickness = s.borderWidth ?? 1;
    const width = s.width ?? 16;
    return sizedBox(width, null, center(container({ width: thickness, decoration: { color: s.borderColor ?? s.color ?? M3.outlineVariant } })));
  },

  CircularProgressIndicator(node) {
    const value = num(node.props.value);
    return w('control', {
      kind: 'progress',
      view: {
        variant: 'circular',
        value,
        strokeWidth: node.style?.borderWidth ?? 4,
        colors: { indicator: node.style?.color ?? M3.primary, track: node.style?.backgroundColor ?? null },
      },
    });
  },

  LinearProgressIndicator(node) {
    const value = num(node.props.value);
    return w('control', {
      kind: 'progress',
      view: {
        variant: 'linear',
        value,
        strokeWidth: num(node.props.minHeight) ?? 4,
        colors: { indicator: node.style?.color ?? M3.primary, track: node.style?.backgroundColor ?? M3.secondaryContainer },
      },
    });
  },

  Tooltip(node, children) {
    return w('gesture', { gestures: ['longpress', 'hover'], tooltip: String(node.props.message ?? ''), onEvent: () => {} }, first(children) ?? container({}));
  },

  Badge(node, children) {
    const label = node.props.label != null ? String(node.props.label) : '';
    const child = first(children) ?? container({});
    const s = node.style ?? {};
    const pill: W =
      label === ''
        ? container({ width: 6, height: 6, decoration: { color: s.backgroundColor ?? M3.error, shape: 'circle' } })
        : container({
            minWidth: 16,
            height: 16,
            padding: insetsSymmetric(0, 4),
            alignment: { x: 0, y: 0 },
            decoration: { color: s.backgroundColor ?? M3.error, radius: radiusAll(8) },
            child: text(label, { fontSize: 11, fontWeight: 500, letterSpacing: 0.5, height: 16 / 11, color: s.color ?? Colors.white }, { softWrap: false }),
          });
    return w('stack', { alignment: { x: -1, y: -1 }, fit: 'loose' }, [child, w('positioned', { top: label === '' ? 0 : -4, right: label === '' ? 0 : -4 }, pill)]);
  },

  Chip(node, children) {
    const label = String(node.props.label ?? '');
    const s = node.style ?? {};
    const content: W[] = [];
    const avatar = node.children.findIndex((c) => c.props.slot === 'avatar');
    if (avatar >= 0) content.push(padding({ top: 0, right: 8, bottom: 0, left: 0 }, sizedBox(18, 18, children[avatar])));
    content.push(text(label, { ...LABEL_LARGE, color: s.color ?? M3.onSurfaceVariant }, { softWrap: false }));
    return padding(
      insetsSymmetric(8, 0),
      container({
        minHeight: 32,
        padding: insetsSymmetric(6, 16),
        alignment: null,
        decoration: { color: s.backgroundColor ?? null, radius: s.borderRadius ?? radiusAll(8), border: { top: side(M3.outlineVariant), right: side(M3.outlineVariant), bottom: side(M3.outlineVariant), left: side(M3.outlineVariant) } },
        child: w('flex', { direction: 'row', crossAxisAlignment: 'center', mainAxisSize: 'min' }, content),
      }),
    );
  },

  Dismissible(node, children, ctx) {
    const state = ctx.engine.stateFor(ctx.elementId, () => ({ dismissed: false }));
    const child = first(children) ?? container({});
    if (state.dismissed) return SHRINK;
    return w('gesture', {
      gestures: ['dismiss'],
      dismissDirection: String(node.props.direction ?? 'horizontal'),
      onEvent: (e: ViewEvent) => {
        if (e.type === 'dismissed') {
          state.dismissed = true;
          dispatchEvent(ctx, 'dismissed', { data: { direction: e.direction ?? null } });
          if (node.events?.dismiss) dispatchEvent(ctx, 'dismiss', { data: { direction: e.direction ?? null } });
          ctx.engine.host.invalidate?.();
        }
      },
    }, child);
  },

  Draggable(node, children, ctx) {
    const child = first(children) ?? container({});
    return w('gesture', {
      gestures: ['draggable'],
      dragData: node.props.data ?? null,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'dragstart') dispatchEvent(ctx, 'dragstart', { data: { data: node.props.data ?? null } });
        else if (e.type === 'dragupdate') ctx.engine.dragOver(ctx.elementId, e, node.props.data ?? null);
        else if (e.type === 'dragend' || e.type === 'drop') ctx.engine.dropAt(ctx.elementId, e, node.props.data ?? null);
      },
    }, child);
  },

  DragTarget(node, children, ctx) {
    const child = first(children) ?? container({});
    return w('gesture', { gestures: [], dragTargetId: ctx.elementId, onEvent: () => {} }, child, `dt:${ctx.elementId}`);
  },

  Hero(node, children) {
    return w('hero', { tag: node.props.tag ?? 'hero' }, first(children) ?? container({}));
  },

  IndexedStack(node, children) {
    return w('indexedStack', { index: num(node.props.index) ?? 0, alignment: parseAlignmentProp(node.props.alignment, { x: -1, y: -1 }) }, children);
  },

  RotatedBox(node, children) {
    return w('rotatedBox', { quarterTurns: num(node.props.quarterTurns) ?? 0 }, first(children) ?? container({}));
  },

  DecoratedBox(node, children, ctx) {
    const s = node.style ?? {};
    const d = decorationFromStyle(s, ctx);
    return decorated(d, first(children) ?? container({}));
  },

  Scope(_node, children) {
    if (children.length === 0) return SHRINK;
    if (children.length === 1) return children[0];
    return column(children);
  },

  Canvas(node, _children, ctx) {
    const raw = Array.isArray(node.props.commands) ? node.props.commands : [];
    const commands = raw.filter((c: any) => c && typeof c === 'object').map((c: any) => normalizeCommand(commandFromJson(c)));
    const bg = CSSParser.parseColor(node.props.backgroundColor) ?? node.style?.backgroundColor ?? null;
    return w('canvas', {
      width: num(node.props.width) ?? node.style?.width ?? null,
      height: num(node.props.height) ?? node.style?.height ?? null,
      background: bg,
      commands,
      onEvent: (e: ViewEvent) => ctx.engine.handleGesture(ctx.elementId, node, e),
    });
  },

  CachedCanvas(node, _children, ctx) {
    const id = String(node.props.contextId ?? node.props.id ?? '');
    if (!id) return SHRINK;
    const store = ctx.engine.services.canvasContexts;
    const c = store.get(ctx.engine.services.scopeId(id)) ?? store.get(id);
    const width = num(node.props.width) ?? node.style?.width ?? null;
    const height = num(node.props.height) ?? node.style?.height ?? null;
    if (!c) return SHRINK;
    if (width != null && height != null) c.setSize(width, height);
    const bg = CSSParser.parseColor(node.props.backgroundColor) ?? node.style?.backgroundColor ?? null;
    return w('canvas', {
      width: width ?? c.width,
      height: height ?? c.height,
      background: bg,
      context: { id: c.id, version: c.version, generation: c.generation, commands: c.commands },
    });
  },

  Scene3D(node, children, ctx) {
    return scene3d(node, children, ctx);
  },
  scene3d(node, children, ctx) {
    return scene3d(node, children, ctx);
  },

  MathExpression(node, _children, ctx) {
    return mathExpression(node, ctx);
  },
  Math(node, _children, ctx) {
    return mathExpression(node, ctx);
  },
};

function flexOrWrap(direction: 'row' | 'column', style: CSSStyle | null | undefined, children: W[]): W {
  const gap = style?.gap ?? 0;
  const wraps = style?.flexWrap === 'wrap' || style?.flexWrap === 'wrap-reverse';
  const main = style?.justifyContent;
  const cross = style?.alignItems;
  const mainMap = (v: string | null | undefined) => {
    switch ((v ?? '').toLowerCase()) {
      case 'center':
        return 'center';
      case 'flex-end':
      case 'end':
        return 'end';
      case 'space-between':
        return 'spaceBetween';
      case 'space-around':
        return 'spaceAround';
      case 'space-evenly':
        return 'spaceEvenly';
      default:
        return 'start';
    }
  };
  const crossMap = (v: string | null | undefined) => {
    switch ((v ?? '').toLowerCase()) {
      case 'center':
        return 'center';
      case 'flex-end':
      case 'end':
        return 'end';
      case 'stretch':
        return 'stretch';
      case 'baseline':
        return 'baseline';
      default:
        return 'start';
    }
  };
  if (wraps) {
    return w('wrap', {
      direction: direction === 'row' ? 'horizontal' : 'vertical',
      spacing: gap,
      runSpacing: gap,
      alignment: mainMap(main),
      crossAxisAlignment: crossMap(cross) === 'stretch' || crossMap(cross) === 'baseline' ? 'start' : crossMap(cross),
      verticalDirection: style?.flexWrap === 'wrap-reverse' ? 'up' : 'down',
    }, children);
  }
  return w('flex', { direction, mainAxisAlignment: mainMap(main), crossAxisAlignment: crossMap(cross), mainAxisSize: 'max', gap }, children);
}

function scene3d(node: ElpianNode, children: W[], ctx: BuildContext): W {
  const p = node.props;
  const raw = p.initialScene ?? p.scene ?? p.world;
  const json = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : Array.isArray(raw) ? { nodes: raw } : null;
  const controller = ctx.engine.sceneFor(ctx.elementId, json);
  const placeholder = first(children) ?? scenePlaceholder();
  const clickable = p.clickable === true;
  return w(
    'scene3d',
    {
      surfaceId: controller.godot.surfaceId,
      live: controller.isLive,
      width: num(p.width) ?? node.style?.width ?? null,
      height: num(p.height) ?? node.style?.height ?? null,
      clickable,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'tap' && clickable) ctx.engine.host.sceneTap?.({ ...p });
      },
    },
    placeholder,
  );
}

/** `_Scene3DPlaceholder`: a quiet gradient panel with an AR icon and a caption. */
function scenePlaceholder(): W {
  return decorated(
    { gradients: [{ kind: 'linear', colors: [0xff10141d, 0xff1a2233], begin: { x: -1, y: -1 }, end: { x: 1, y: 1 } }] },
    center(
      column(
        [icon('view_in_ar', 36, Colors.white24), sizedBox(null, 8), text('3D unavailable on this platform', { color: Colors.white38, fontSize: 12 })],
        { mainAxisSize: 'min', crossAxisAlignment: 'center' },
      ),
    ),
  );
}

// ----------------------------------------------------------------------------
// MathExpression
// ----------------------------------------------------------------------------

const MATH_SYMBOLS: [RegExp, string][] = [
  ['alpha', 'α'], ['beta', 'β'], ['gamma', 'γ'], ['delta', 'δ'], ['theta', 'θ'], ['lambda', 'λ'], ['mu', 'μ'],
  ['pi', 'π'], ['sigma', 'σ'], ['phi', 'φ'], ['omega', 'ω'], ['sum', '∑'], ['prod', '∏'], ['int', '∫'],
  ['infty', '∞'], ['sqrt', '√'], ['neq', '≠'], ['leq', '≤'], ['geq', '≥'], ['approx', '≈'], ['times', '×'],
  ['cdot', '·'], ['pm', '±'], ['to', '→'], ['leftarrow', '←'], ['Rightarrow', '⇒'], ['forall', '∀'],
  ['exists', '∃'], ['in', '∈'], ['notin', '∉'], ['subset', '⊂'], ['subseteq', '⊆'], ['cup', '∪'], ['cap', '∩'],
].map(([name, sym]) => [new RegExp('\\\\' + name, 'g'), sym] as [RegExp, string]);

const SUPER: Record<string, string> = { '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', n: 'ⁿ', i: 'ⁱ' };
const SUB: Record<string, string> = { '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎' };
const BLOCKED = ['write', 'input', 'include', 'openout', 'read', 'catcode', 'usepackage', 'newcommand', 'renewcommand', 'def', 'csname', 'every', 'special'];

export function sanitizeMath(input: string): { value: string; sanitized: boolean } {
  let expression = input.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ' ').trim();
  if (expression.length > 4096) expression = expression.substring(0, 4096);
  let sanitized = false;
  for (const cmd of BLOCKED) {
    const re = new RegExp('\\\\' + cmd, 'gi');
    if (re.test(expression)) sanitized = true;
    expression = expression.replace(new RegExp('\\\\' + cmd, 'gi'), '\\text{blocked}');
  }
  return { value: expression, sanitized };
}

export function renderMathToUnicode(expression: string): string {
  let out = expression;
  const frac = /\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/;
  for (let i = 0; i < 24 && frac.test(out); i++) out = out.replace(new RegExp(frac.source, 'g'), (_m, a, b) => `(${a})/(${b})`);
  for (const [re, sym] of MATH_SYMBOLS) out = out.replace(re, sym);
  const mapScript = (value: string, map: Record<string, string>) => [...value].map((c) => map[c] ?? c).join('');
  out = out.replace(/\^\{([^{}]+)\}|\^([A-Za-z0-9+\-=()])/g, (_m, a, b) => mapScript(a ?? b ?? '', SUPER));
  out = out.replace(/_\{([^{}]+)\}|_([A-Za-z0-9+\-=()])/g, (_m, a, b) => mapScript(a ?? b ?? '', SUB));
  out = out.replace(/\\left|\\right/g, '').replace(/\\text\{([^{}]*)\}/g, '$1').replace(/[{}]/g, '');
  return out.trim();
}

function mathExpression(node: ElpianNode, ctx: BuildContext): W {
  const raw = String(node.props.expression ?? node.props.latex ?? node.props.text ?? node.props.data ?? '');
  const sanitized = sanitizeMath(raw);
  const rendered = renderMathToUnicode(sanitized.value);
  const style: TextStyle = node.style ? createTextStyle(node.style) ?? {} : { fontSize: 18 };
  let result: W;
  if (rendered.trim() === '') {
    result = text('Math expression is required', style);
  } else {
    const parts: W[] = [w('scroll', { axis: 'horizontal' }, text(rendered, style, { selectable: true, softWrap: false }))];
    if (sanitized.sanitized) {
      parts.push(padding({ top: 4, right: 0, bottom: 0, left: 0 }, text('Unsafe commands were sanitized from the expression.', { fontSize: 11, color: Colors.orange })));
    }
    result = column(parts, { crossAxisAlignment: 'start', mainAxisSize: 'min' });
  }
  return applyStyle(result, node.style, {}, ctx);
}

export { alphaOf };
