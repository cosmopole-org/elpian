/**
 * The HTML elements — one builder per file in flutter/lib/src/html_widgets,
 * lowered to the same composition (default margins, sizes and colours are the
 * Flutter engine's), with the elements Flutter leaves as placeholders made
 * real: tables lay out rows and cells, forms collect and submit their fields,
 * `details` expands, `picture` honours its `source` media queries, image maps
 * are clickable, `datalist` feeds input suggestions, `sub`/`sup` shift the
 * baseline.
 *
 * Inline content — a `p`/`span`/heading/`li`/`a` whose children are text-level
 * elements — becomes one paragraph of styled spans that wraps across element
 * boundaries, as HTML does.
 */
import { Colors, M3, scaleAlpha, type Color } from '../css/color.js';
import { mediaMatches } from '../css/stylesheet.js';
import { cssEnvironment } from '../css/environment.js';
import type { CSSStyle } from '../css/style.js';
import {
  borderAll,
  insetsAll,
  insetsSymmetric,
  radiusAll,
  type EdgeInsets,
} from '../css/types.js';
import { CSSParser } from '../css/parser.js';
import { textOf, type ElpianNode } from '../model/node.js';
import { w, type W } from '../render/object.js';
import { Decoration as Deco, mergeTextStyle, toSpec, type TextStyle } from '../render/text-style.js';
import type { ViewEvent } from '../render/view.js';
import { areaContains, type AreaSpec } from '../render/layout/imagemap.js';
import { commandFromJson, normalizeCommand } from '../canvas/store.js';
import { toNumber } from '../util/json.js';
import type { BuildContext, WidgetBuilder } from './context.js';
import { buttonOuter, buttonPressed, dispatchEvent, flutterWidgets, icon, materialButton } from './flutter.js';
import {
  SHRINK,
  applyStyle,
  center,
  column,
  container,
  createTextStyle,
  decorated,
  expanded,
  padding,
  row,
  sizedBox,
  text,
  textOptionsFromStyle,
} from './style.js';

const num = toNumber;

// ============================================================================
// Inline formatting
// ============================================================================

/** Default text styles of text-level elements. */
const INLINE_DEFAULTS: Record<string, TextStyle> = {
  span: {},
  strong: { fontWeight: 700 },
  b: { fontWeight: 700 },
  em: { italic: true },
  i: { italic: true },
  cite: { italic: true },
  var: { italic: true },
  dfn: { italic: true },
  u: { decoration: Deco.underline },
  ins: { decoration: Deco.underline },
  s: { decoration: Deco.lineThrough },
  del: { decoration: Deco.lineThrough },
  strike: { decoration: Deco.lineThrough },
  code: { fontFamily: 'monospace', background: 0xfff5f5f5 },
  kbd: { fontFamily: 'monospace', background: 0xffeeeeee },
  samp: { fontFamily: 'monospace' },
  tt: { fontFamily: 'monospace' },
  mark: { background: 0xffffff00 },
  small: { fontSize: 12 },
  sub: { fontSize: 10, baselineShift: 3 },
  sup: { fontSize: 10, baselineShift: -6 },
  abbr: { decoration: Deco.underline },
  a: { color: Colors.blue, decoration: Deco.underline },
  q: {},
  time: {},
  data: {},
  label: { fontWeight: 500 },
};

const INLINE_TAGS = new Set([...Object.keys(INLINE_DEFAULTS), 'br', '#text']);

interface SpanInput {
  text: string;
  style?: TextStyle | null;
  link?: string | null;
}

/**
 * The spans of an inline subtree, or null when it contains something that is
 * not text-level (a box, an image, a control, an element with its own events
 * other than a link).
 */
function inlineSpans(node: ElpianNode, inherited: TextStyle, ctx: BuildContext, depth = 0): SpanInput[] | null {
  if (depth > 12) return null;
  if (node.type === '#text') return [{ text: String(node.props.text ?? ''), style: inherited }];
  if (node.type === 'br') return [{ text: '\n', style: inherited }];
  if (!INLINE_TAGS.has(node.type)) return null;
  const s = node.style;
  if (s && (s.display === 'block' || s.display === 'flex' || s.display === 'grid' || s.position === 'absolute' || s.position === 'fixed')) return null;
  if (s && (s.width != null || s.height != null || s.border || s.borderRadius || s.boxShadow || s.transform)) return null;
  if (s?.display === 'none') return [];
  const events = node.events ? Object.keys(node.events) : [];
  const isLink = node.type === 'a' && events.every((e) => e === 'click' || e === 'tap');
  if (events.length && !isLink) return null;
  const own = mergeTextStyle(mergeTextStyle(inherited, INLINE_DEFAULTS[node.type] ?? {}), createTextStyle(s));
  if (s?.backgroundColor != null) own.background = s.backgroundColor;
  const link = node.type === 'a' ? String(node.props.href ?? '#') : null;
  const out: SpanInput[] = [];
  const t = textOf(node);
  if (t) out.push({ text: node.type === 'q' ? `“${t}”` : t, style: own, link });
  for (const child of node.children) {
    const childSpans = inlineSpans(child, own, ctx, depth + 1);
    if (!childSpans) return null;
    for (const span of childSpans) out.push(link && !span.link ? { ...span, link } : span);
  }
  return out;
}

/** A paragraph from an element's text and inline children, or null if not inline. */
function richText(node: ElpianNode, style: TextStyle, ctx: BuildContext, opts: Record<string, any> = {}): W | null {
  if (node.children.length === 0) return null;
  const spans: SpanInput[] = [];
  const t = textOf(node);
  if (t) spans.push({ text: t, style: {} });
  for (const child of node.children) {
    const childSpans = inlineSpans(child, {}, ctx);
    if (!childSpans) return null;
    spans.push(...childSpans);
  }
  return w('text', {
    spans,
    style,
    ...opts,
    onLink: (href: string) => openLink(ctx, href, null),
  });
}

function openLink(ctx: BuildContext, href: string, node: ElpianNode | null): void {
  if (node?.events?.click || node?.events?.tap) {
    dispatchEvent(ctx, 'click');
  }
  if (!href || href === '#') return;
  const host = ctx.engine.host;
  if (/^(https?:|mailto:|tel:|sms:|geo:)/i.test(href) || !host.navigate) {
    host.openUrl?.(href);
  } else {
    host.navigate(href, false);
  }
}

// ============================================================================
// Layout: HtmlDiv
// ============================================================================

function childStyle(node: ElpianNode): CSSStyle | null {
  let n = node;
  while (n.type === 'Scope' && n.children.length === 1) n = n.children[0];
  return n.style;
}

function stretchChild(child: W): W {
  if (child.t === 'flexible' && child.c && child.c[0]) {
    return { ...child, c: [w('fill', { width: true }, child.c[0])] };
  }
  return w('fill', { width: true }, child);
}

function unflex(child: W): W {
  return child.t === 'flexible' && child.c && child.c[0] ? child.c[0] : child;
}

/** `_buildColumn`: stretch children without an explicit width (CSS block flow). */
function buildColumn(node: ElpianNode, children: W[], gap: number, mainAxisAlignment: string, mainAxisSize: 'max' | 'min', flowNodes: ElpianNode[]): W {
  const alignItems = node.style?.alignItems;
  const canStretch = alignItems == null && flowNodes.length === children.length;
  if (!canStretch) {
    return w('flex', { direction: 'column', mainAxisAlignment, crossAxisAlignment: crossOf(alignItems), mainAxisSize, gap, reverse: node.style?.flexDirection === 'column-reverse' }, children);
  }
  const laid = children.map((child, i) => (childStyle(flowNodes[i])?.width == null && childStyle(flowNodes[i])?.widthFactor == null ? stretchChild(child) : child));
  return w('flex', { direction: 'column', mainAxisAlignment, crossAxisAlignment: 'start', mainAxisSize, gap, reverse: node.style?.flexDirection === 'column-reverse' }, laid);
}

function mainOf(v: string | null | undefined): string {
  switch ((v ?? '').toLowerCase()) {
    case 'center':
      return 'center';
    case 'flex-end':
    case 'end':
    case 'right':
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
}

function crossOf(v: string | null | undefined): string {
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
}

function wrapCrossOf(v: string | null | undefined): string {
  const c = crossOf(v);
  return c === 'center' || c === 'end' ? c : 'start';
}

function buildFlow(node: ElpianNode, children: W[], flowNodes: ElpianNode[]): W {
  const s = node.style;
  const display = s?.display;
  if (display === 'grid' || display === 'inline-grid') return buildGrid(node, children, flowNodes);
  const gap = s?.gap ?? s?.columnGap ?? 0;
  if (display === 'flex' || display === 'inline-flex') {
    const dir = s?.flexDirection ?? 'row';
    const isRow = dir === 'row' || dir === 'row-reverse';
    const wraps = s?.flexWrap === 'wrap' || s?.flexWrap === 'wrap-reverse';
    if (wraps) {
      return w(
        'wrap',
        {
          direction: isRow ? 'horizontal' : 'vertical',
          spacing: isRow ? s?.columnGap ?? gap : s?.rowGap ?? gap,
          runSpacing: isRow ? s?.rowGap ?? gap : s?.columnGap ?? gap,
          alignment: mainOf(s?.justifyContent),
          runAlignment: mainOf(s?.alignContent),
          crossAxisAlignment: wrapCrossOf(s?.alignItems),
          verticalDirection: s?.flexWrap === 'wrap-reverse' ? 'up' : 'down',
          reverse: dir.endsWith('reverse'),
        },
        children,
      );
    }
    if (isRow) {
      const flex = w(
        'flex',
        {
          direction: 'row',
          mainAxisAlignment: mainOf(s?.justifyContent),
          crossAxisAlignment: crossOf(s?.alignItems),
          mainAxisSize: 'max',
          gap: s?.columnGap ?? gap,
          reverse: dir === 'row-reverse',
          shrink: true,
        },
        children,
      );
      const hasFlex = flowNodes.some((c) => (childStyle(c)?.flex ?? childStyle(c)?.flexGrow) != null);
      // `_flexSafe`: an unbounded row with flex children takes its intrinsic width.
      return hasFlex ? w('intrinsicWidth', { onlyWhenUnbounded: true }, [flex]) : flex;
    }
    return buildColumn(node, children, s?.rowGap ?? gap, mainOf(s?.justifyContent), 'max', flowNodes);
  }
  if (children.length === 1) return unflex(children[0]);
  return buildColumn(node, children, s?.rowGap ?? gap, 'start', 'min', flowNodes);
}

function buildGrid(node: ElpianNode, children: W[], flowNodes: ElpianNode[]): W {
  const s = node.style ?? {};
  const base = s.gridGap ?? s.gap ?? 0;
  const items = children.map((child, i) => {
    const cs = childStyle(flowNodes[i]);
    const area = cs?.gridArea;
    return w(
      'gridItem',
      {
        column: cs?.gridColumn ?? (area && area.includes('/') ? area.split('/')[1] : null),
        row: cs?.gridRow ?? (area && area.includes('/') ? area.split('/')[0] : null),
        alignSelf: cs?.alignSelf ?? null,
      },
      unflex(child),
    );
  });
  return w(
    'grid',
    {
      columns: s.gridTemplateColumns ?? null,
      rows: s.gridTemplateRows ?? null,
      autoRows: s.gridAutoRows ?? null,
      columnGap: s.gridColumnGap ?? s.columnGap ?? base,
      rowGap: s.gridRowGap ?? s.rowGap ?? base,
      alignItems: s.alignItems ?? null,
    },
    items,
  );
}

function buildPositioned(node: ElpianNode, children: W[]): W | null {
  const nodes = node.children;
  if (nodes.length !== children.length) return null;
  const styles = nodes.map(childStyle);
  if (!styles.some((st) => st?.position === 'absolute' || st?.position === 'fixed')) return null;
  const flow: W[] = [];
  const flowNodes: ElpianNode[] = [];
  const positioned: number[] = [];
  styles.forEach((st, i) => {
    if (st?.position === 'absolute' || st?.position === 'fixed') positioned.push(i);
    else {
      flow.push(children[i]);
      flowNodes.push(nodes[i]);
    }
  });
  positioned.sort((a, b) => (styles[a]?.zIndex ?? 0) - (styles[b]?.zIndex ?? 0) || a - b);
  const stackChildren: W[] = [];
  if (flow.length) stackChildren.push(w('fill', { width: true }, buildFlow(node, flow, flowNodes)));
  for (const i of positioned) {
    const st = styles[i]!;
    const lr = st.left != null && st.right != null;
    const tb = st.top != null && st.bottom != null;
    stackChildren.push(
      w(
        'positioned',
        { top: st.top ?? null, left: st.left ?? null, right: st.right ?? null, bottom: st.bottom ?? null, width: lr ? null : st.width ?? null, height: tb ? null : st.height ?? null },
        unflex(children[i]),
      ),
    );
  }
  return w('stack', { alignment: { x: -1, y: -1 }, fit: 'loose', clip: true }, stackChildren);
}

/** `HtmlDiv.build` — the CSS box: block, flex, grid and positioned layouts. */
export function htmlDiv(node: ElpianNode, children: W[], ctx: BuildContext, opts: { fullWidth?: boolean } = {}): W {
  if (children.length === 0) {
    let empty: W = SHRINK;
    if (opts.fullWidth) empty = w('fill', { width: true }, empty);
    return applyStyle(empty, node.style, { layoutHandled: true }, ctx);
  }
  const positioned = buildPositioned(node, children);
  let body = positioned ?? buildFlow(node, children, node.children);
  if (opts.fullWidth) body = w('fill', { width: true }, body);
  return applyStyle(body, node.style, { layoutHandled: true }, ctx);
}

// ============================================================================
// Text-bearing elements
// ============================================================================

/** Merge element defaults *under* the author's style (author wins). */
function withDefaults(style: CSSStyle | null | undefined, defaults: CSSStyle): CSSStyle {
  const out: CSSStyle = { ...defaults };
  for (const [k, v] of Object.entries(style ?? {})) if (v != null) (out as any)[k] = v;
  return out;
}

function textElement(node: ElpianNode, ctx: BuildContext, defaults: CSSStyle, baseText: TextStyle = {}): W {
  const style = withDefaults(node.style, defaults);
  const ts = mergeTextStyle(baseText, createTextStyle(style));
  const opts = textOptionsFromStyle(style);
  const rich = richText(node, ts, ctx, opts);
  if (rich) return applyStyle(rich, style, {}, ctx);
  return applyStyle(text(textOf(node), ts, opts), style, {}, ctx);
}

/** A text element that may also hold block children (Column of text + children). */
function textWithChildren(node: ElpianNode, children: W[], ctx: BuildContext, defaults: CSSStyle, layout: 'column' | 'wrap'): W {
  const style = withDefaults(node.style, defaults);
  const ts = createTextStyle(style) ?? {};
  const opts = textOptionsFromStyle(style);
  if (children.length === 0) return applyStyle(text(textOf(node), ts, opts), style, {}, ctx);
  const rich = richText(node, ts, ctx, opts);
  if (rich) return applyStyle(rich, style, {}, ctx);
  const parts: W[] = [];
  const t = textOf(node);
  if (t) parts.push(text(t, ts, opts));
  parts.push(...children);
  const body =
    layout === 'column'
      ? column(parts, { crossAxisAlignment: 'start', mainAxisSize: 'min' })
      : w('wrap', { direction: 'horizontal', crossAxisAlignment: 'center' }, parts);
  return applyStyle(w('defaultTextStyle', { style: ts }, body), style, { layoutHandled: true }, ctx);
}

function heading(size: number, marginV: number): WidgetBuilder {
  return (node, children, ctx) =>
    textWithChildren(node, children, ctx, { fontSize: size, fontWeight: 700, margin: insetsSymmetric(marginV, 0) }, 'column');
}

const monoStyle = (bg: Color, pad: EdgeInsets, extra: CSSStyle = {}): CSSStyle => ({ fontFamily: 'monospace', backgroundColor: bg, padding: pad, ...extra });

/**
 * Flutter's text-level elements use `node.style ?? defaultStyle` (an author
 * style replaces the defaults wholesale) — kept for fidelity.
 */
function replaceDefaults(node: ElpianNode, ctx: BuildContext, defaults: CSSStyle, inline: TextStyle): W {
  const style = node.style ?? defaults;
  const ts = mergeTextStyle(node.style ? INLINE_DEFAULTS[node.type] ?? {} : inline, createTextStyle(style));
  const rich = richText(node, ts, ctx);
  return applyStyle(rich ?? text(textOf(node), ts, textOptionsFromStyle(style)), style, {}, ctx);
}

// ============================================================================
// Form controls
// ============================================================================

const DARK = {
  text: 0xfff7eedc,
  fill: 0xff0a1626,
  border: 0xff1c3450,
  focus: 0xffd6b36a,
  hint: 0xff6b7e92,
};

function datalistOptions(ctx: BuildContext, listId: string | null): string[] | null {
  if (!listId) return null;
  const list = ctx.engine.datalists.get(listId);
  return list && list.length ? [...list] : null;
}

function htmlInput(node: ElpianNode, children: W[], ctx: BuildContext): W {
  const type = String(node.props.type ?? 'text').toLowerCase();
  const name = node.props.name != null ? String(node.props.name) : null;
  const disabled = node.props.disabled === true || node.props.disabled === 'disabled';

  if (type === 'hidden') {
    ctx.engine.registerFormField(ctx.formId, name, () => node.props.value ?? '');
    return SHRINK;
  }

  if (type === 'checkbox') {
    const state = ctx.engine.stateFor(ctx.elementId, () => ({ checked: node.props.checked === true || node.props.checked === 'checked' }));
    ctx.engine.registerFormField(ctx.formId, name, () => (state.checked ? node.props.value ?? 'on' : null));
    const result = w('control', {
      kind: 'checkbox',
      focusId: node.props.id != null ? String(node.props.id) : null,
      view: { checked: state.checked, enabled: !disabled, colors: { fill: node.style?.color ?? M3.primary, check: M3.onPrimary, border: M3.onSurfaceVariant } },
      onEvent: (e: ViewEvent) => {
        if (e.type === 'change') {
          state.checked = !!e.value;
          dispatchEvent(ctx, 'change', { value: state.checked });
        }
      },
    });
    return applyStyle(result, node.style, {}, ctx);
  }

  if (type === 'radio') {
    const value = node.props.value;
    const group = node.props.groupValue;
    const checked = group !== undefined ? value === group : node.props.checked === true || node.props.checked === 'checked';
    ctx.engine.registerFormField(ctx.formId, name, () => (checked ? value : undefined));
    const result = w('control', {
      kind: 'radio',
      focusId: node.props.id != null ? String(node.props.id) : null,
      view: { checked, value: value ?? null, enabled: !disabled, colors: { fill: node.style?.color ?? M3.primary, border: M3.onSurfaceVariant } },
      controlled: true,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'change') dispatchEvent(ctx, 'change', { value });
      },
    });
    return applyStyle(result, node.style, {}, ctx);
  }

  if (type === 'range') {
    const min = num(node.props.min) ?? 0;
    const max = num(node.props.max) ?? 100;
    const state = ctx.engine.stateFor(ctx.elementId, () => ({ value: Math.max(min, Math.min(max, num(node.props.value) ?? (min + max) / 2)) }));
    ctx.engine.registerFormField(ctx.formId, name, () => state.value);
    const step = num(node.props.step) ?? 1;
    const result = w('control', {
      kind: 'slider',
      focusId: node.props.id != null ? String(node.props.id) : null,
      view: { value: state.value, min, max, step, enabled: !disabled, colors: { active: DARK.focus, inactive: DARK.border, thumb: DARK.focus } },
      onEvent: (e: ViewEvent) => {
        if (e.type === 'input' || e.type === 'change') {
          state.value = Number(e.value);
          dispatchEvent(ctx, e.type === 'input' ? 'input' : 'change', { value: state.value });
        }
      },
    });
    return applyStyle(result, node.style, {}, ctx);
  }

  if (type === 'submit' || type === 'button' || type === 'reset') {
    const label = String(node.props.value ?? node.props.text ?? (type === 'submit' ? 'Submit' : type === 'reset' ? 'Reset' : 'Button'));
    return htmlButtonLike(node, [text(label, { color: node.style?.color ?? (node.style?.backgroundColor != null ? Colors.white : M3.primary) })], ctx, type);
  }

  // Text-like inputs.
  const state = ctx.engine.stateFor(ctx.elementId, () => ({ value: node.props.value != null ? String(node.props.value) : '' }));
  ctx.engine.registerFormField(ctx.formId, name, () => (type === 'number' ? (state.value === '' ? null : Number(state.value)) : state.value));
  const s = node.style;
  const textColor = s?.color ?? DARK.text;
  const fontSize = s?.fontSize ?? 13;
  const ts: TextStyle = { color: textColor, fontSize, height: 1.3, letterSpacing: 0 };
  const result = w('control', {
    kind: 'textInput',
    focusId: node.props.id != null ? String(node.props.id) : null,
    lines: 1,
    padding: [10, 10, 10, 10],
    lineHeight: fontSize * 1.3,
    view: {
      value: state.value,
      placeholder: String(node.props.placeholder ?? ''),
      inputType: type,
      multiline: false,
      maxLength: num(node.props.maxLength ?? node.props.maxlength),
      enabled: !disabled,
      readOnly: node.props.readOnly === true || node.props.readonly != null,
      autofocus: node.props.autofocus === true || node.props.autofocus === 'autofocus',
      min: num(node.props.min) ?? undefined,
      max: num(node.props.max) ?? undefined,
      suggestions: datalistOptions(ctx, node.props.list != null ? String(node.props.list) : null),
      variant: 'outline',
      textStyle: toSpec(ts),
      hintStyle: toSpec({ ...ts, color: DARK.hint }),
      contentPadding: [10, 10, 10, 10],
      colors: { text: textColor, hint: DARK.hint, fill: s?.backgroundColor ?? DARK.fill, border: DARK.border, focusedBorder: DARK.focus, cursor: DARK.focus, radius: 8 as any },
    },
    onEvent: (e: ViewEvent) => {
      if (e.type === 'input' || e.type === 'change') {
        state.value = String(e.value ?? '');
        dispatchEvent(ctx, 'input', { value: state.value });
      } else if (e.type === 'submit') {
        dispatchEvent(ctx, 'submit');
        if (ctx.formId) ctx.engine.submitForm(ctx.formId);
      } else if (e.type === 'focus' || e.type === 'blur') {
        dispatchEvent(ctx, e.type);
        if (e.type === 'blur' && node.events?.change) dispatchEvent(ctx, 'change', { value: state.value });
      }
    },
  });
  return applyStyle(result, s, {}, ctx);
}

function htmlTextarea(node: ElpianNode, _children: W[], ctx: BuildContext): W {
  const state = ctx.engine.stateFor(ctx.elementId, () => ({ value: String(node.props.value ?? node.props.text ?? '') }));
  ctx.engine.registerFormField(ctx.formId, node.props.name != null ? String(node.props.name) : null, () => state.value);
  const lines = Math.max(1, num(node.props.rows) ?? 5);
  const ts: TextStyle = { fontSize: 16, height: 1.5, letterSpacing: 0.5, color: node.style?.color ?? M3.onSurface };
  const result = w('control', {
    kind: 'textInput',
    focusId: node.props.id != null ? String(node.props.id) : null,
    lines,
    padding: [16, 12, 16, 12],
    lineHeight: 24,
    view: {
      value: state.value,
      placeholder: String(node.props.placeholder ?? ''),
      inputType: 'multiline',
      multiline: true,
      maxLines: lines,
      minLines: lines,
      enabled: node.props.disabled == null,
      readOnly: node.props.readOnly === true || node.props.readonly != null,
      variant: 'outline',
      textStyle: toSpec(ts),
      hintStyle: toSpec({ ...ts, color: M3.onSurfaceVariant }),
      contentPadding: [16, 12, 16, 12],
      colors: { text: ts.color ?? M3.onSurface, hint: M3.onSurfaceVariant, border: M3.outline, focusedBorder: M3.primary, cursor: M3.primary, fill: null, radius: 4 as any },
    },
    onEvent: (e: ViewEvent) => {
      if (e.type === 'input' || e.type === 'change') {
        state.value = String(e.value ?? '');
        dispatchEvent(ctx, 'input', { value: state.value });
      } else if (e.type === 'submit') dispatchEvent(ctx, 'submit');
      else if (e.type === 'focus' || e.type === 'blur') dispatchEvent(ctx, e.type);
    },
  });
  return applyStyle(result, node.style, {}, ctx);
}

interface Option {
  value: string;
  label: string;
  group?: string | null;
  disabled?: boolean;
}

function selectOptions(node: ElpianNode): Option[] {
  const out: Option[] = [];
  const raw = node.props.options;
  if (Array.isArray(raw)) {
    for (const o of raw) {
      if (o && typeof o === 'object') {
        const v = String(o.value ?? o.label ?? '');
        out.push({ value: v, label: String(o.label ?? v), group: o.group ?? null, disabled: o.disabled === true });
      } else if (o != null) out.push({ value: String(o), label: String(o) });
    }
  }
  if (out.length === 0) {
    const visit = (n: ElpianNode, group: string | null) => {
      for (const c of n.children) {
        if (c.type === 'option') {
          const v = String(c.props.value ?? c.props.text ?? '');
          out.push({ value: v, label: String(c.props.text ?? c.props.label ?? v), group, disabled: c.props.disabled != null && c.props.disabled !== false });
        } else if (c.type === 'optgroup') visit(c, String(c.props.label ?? ''));
      }
    };
    visit(node, null);
  }
  return out;
}

function htmlSelect(node: ElpianNode, _children: W[], ctx: BuildContext): W {
  const options = selectOptions(node);
  const selectedChild = node.children.find((c) => c.type === 'option' && (c.props.selected === true || c.props.selected === 'selected'));
  const state = ctx.engine.stateFor(ctx.elementId, () => ({
    value: node.props.value != null ? String(node.props.value) : selectedChild ? String(selectedChild.props.value ?? selectedChild.props.text ?? '') : null,
    lastProp: node.props.value != null ? String(node.props.value) : null,
  }));
  // didUpdateWidget: an incoming prop value change wins.
  const incoming = node.props.value != null ? String(node.props.value) : null;
  if (incoming != null && incoming !== state.lastProp) {
    state.value = incoming;
    state.lastProp = incoming;
  }
  const value = options.some((o) => o.value === state.value) ? state.value : options[0]?.value ?? null;
  ctx.engine.registerFormField(ctx.formId, node.props.name != null ? String(node.props.name) : null, () => value);
  const s = node.style;
  const ts: TextStyle = { color: s?.color ?? DARK.text, fontSize: s?.fontSize ?? 13, height: 1.3 };
  let result: W = w('control', {
    kind: 'select',
    focusId: node.props.id != null ? String(node.props.id) : null,
    padding: [0, 10, 0, 10],
    view: {
      value,
      options,
      enabled: node.props.disabled == null,
      textStyle: toSpec(ts),
      colors: { text: ts.color ?? DARK.text, fill: DARK.fill, icon: DARK.focus, menu: DARK.fill },
    },
    onEvent: (e: ViewEvent) => {
      if (e.type === 'change' && e.value != null) {
        state.value = String(e.value);
        dispatchEvent(ctx, 'change', { value: state.value });
        ctx.engine.host.invalidate?.();
      }
    },
  });
  result = container({
    child: result,
    padding: insetsSymmetric(0, 10),
    decoration: { color: DARK.fill, radius: radiusAll(8), border: borderAll({ width: 1, color: DARK.border, style: 'solid' }) },
  });
  return applyStyle(result, s, {}, ctx);
}

function htmlButtonLike(node: ElpianNode, children: W[], ctx: BuildContext, type?: string): W {
  const s = node.style;
  const label = String(node.props.text ?? 'Button');
  const fg = s?.color ?? (s?.backgroundColor != null ? Colors.white : M3.primary);
  const child = children[0] ?? text(label, { color: fg });
  const kind = type ?? String(node.props.type ?? (ctx.formId ? 'submit' : 'button')).toLowerCase();
  const disabled = node.props.disabled === true || node.props.disabled === 'disabled';
  const press = buttonPressed(ctx);
  const onPressed = disabled
    ? null
    : () => {
        press();
        if (kind === 'submit' && ctx.formId) ctx.engine.submitForm(ctx.formId);
        if (kind === 'reset' && ctx.formId) dispatchEvent(ctx, 'reset');
      };
  return buttonOuter(materialButton({ child, style: s, onPressed, semanticsLabel: label }), s);
}

// ============================================================================
// Media
// ============================================================================

function mediaSource(node: ElpianNode, ctx: BuildContext): string {
  const direct = node.props.src;
  if (direct) return ctx.engine.resolveUrl(String(direct));
  for (const c of node.children) if (c.type === 'source' && c.props.src) return ctx.engine.resolveUrl(String(c.props.src));
  return '';
}

function mediaElement(kind: 'video' | 'audio'): WidgetBuilder {
  return (node, _children, ctx) => {
    const src = mediaSource(node, ctx);
    const tracks = node.children
      .filter((c) => c.type === 'track' && c.props.src)
      .map((c) => ({
        src: ctx.engine.resolveUrl(String(c.props.src)),
        kind: String(c.props.kind ?? 'subtitles'),
        srclang: c.props.srclang != null ? String(c.props.srclang) : null,
        label: c.props.label != null ? String(c.props.label) : null,
        default: c.props.default === true || c.props.default === 'default',
      }));
    if (!src) {
      const msg = kind === 'video' ? 'video src is required' : 'audio src is required';
      return applyStyle(
        kind === 'video'
          ? decorated({ color: Colors.black }, center(text(msg, { color: Colors.white70 })))
          : row([padding(insetsAll(16), icon('audiotrack', 24)), text(msg)], { mainAxisSize: 'min' }),
        node.style,
        {},
        ctx,
      );
    }
    const result = w('media', {
      kind,
      src,
      autoplay: node.props.autoplay === true || node.props.autoplay === 'autoplay',
      loop: node.props.loop === true || node.props.loop === 'loop',
      muted: node.props.muted === true || node.props.muted === 'muted',
      controls: node.props.controls !== false,
      poster: node.props.poster ? ctx.engine.resolveUrl(String(node.props.poster)) : null,
      tracks: tracks.length ? tracks : null,
      width: kind === 'video' ? node.style?.width ?? num(node.props.width) : node.style?.width ?? null,
      height: kind === 'video' ? node.style?.height ?? num(node.props.height) : null,
      fit: node.style?.objectFit ?? 'contain',
      onEvent: (e: ViewEvent) => {
        if (['play', 'pause', 'ended', 'timeupdate', 'load', 'error', 'volumechange', 'seeked'].includes(e.type)) {
          dispatchEvent(ctx, e.type === 'load' ? 'loadedmetadata' : e.type, { value: e.value });
          if (e.type === 'load') dispatchEvent(ctx, 'load', { value: e.value });
        }
      },
    });
    return applyStyle(result, node.style, { }, ctx);
  };
}

function looksLike(kind: 'image' | 'video' | 'audio', type: string, src: string): boolean {
  const s = src.toLowerCase().split('?')[0];
  if (kind === 'image') return type.startsWith('image/') || /\.(png|jpe?g|gif|webp|svg|bmp|avif)$/.test(s);
  if (kind === 'video') return type.startsWith('video/') || /\.(mp4|webm|mov|m3u8|mkv|ogv)$/.test(s);
  return type.startsWith('audio/') || /\.(mp3|wav|ogg|aac|m4a|flac|opus)$/.test(s);
}

function webContent(node: ElpianNode, ctx: BuildContext, src: string, label: string): W {
  if (!src && !node.props.srcdoc) {
    return applyStyle(center(text(`${label} source is required`)), node.style, {}, ctx);
  }
  const result = w('web', {
    src: src ? ctx.engine.resolveUrl(src) : null,
    html: node.props.srcdoc ? String(node.props.srcdoc) : null,
    width: node.style?.width ?? num(node.props.width),
    height: node.style?.height ?? num(node.props.height),
    onEvent: (e: ViewEvent) => {
      if (e.type === 'load' || e.type === 'error') dispatchEvent(ctx, e.type, { value: e.value });
    },
  });
  return applyStyle(result, node.style, {}, ctx);
}

function embedTyped(node: ElpianNode, children: W[], ctx: BuildContext, src: string): W {
  const type = String(node.props.type ?? '').toLowerCase();
  const withSrc: ElpianNode = { ...node, props: { ...node.props, src } };
  if (looksLike('image', type, src)) return htmlImg(withSrc, children, ctx);
  if (looksLike('video', type, src)) return mediaElement('video')(withSrc, children, ctx);
  if (looksLike('audio', type, src)) return mediaElement('audio')(withSrc, children, ctx);
  return webContent(withSrc, ctx, src, node.type);
}

function htmlImg(node: ElpianNode, _children: W[], ctx: BuildContext): W {
  const rawSrc = String(node.props.src ?? '');
  const src = ctx.engine.resolveUrl(chooseSrcset(node, rawSrc));
  const s = node.style;
  const img = w('image', {
    src,
    fit: s?.objectFit ?? (s?.width != null && s?.height != null ? 'fill' : 'contain'),
    alignment: s?.objectPosition ?? null,
    width: s?.width ?? num(node.props.width),
    height: s?.height ?? num(node.props.height),
    alt: node.props.alt != null ? String(node.props.alt) : null,
    onEvent: (e: ViewEvent) => {
      if (e.type === 'load' || e.type === 'error') dispatchEvent(ctx, e.type, { value: e.value });
    },
  });
  let result: W = img;
  const usemap = typeof node.props.usemap === 'string' ? node.props.usemap.replace(/^#/, '') : null;
  const areas = usemap ? ctx.engine.imageMaps.get(usemap) : null;
  if (areas && areas.length) {
    const specs: AreaSpec[] = [];
    const regions: W[] = [];
    areas.forEach((area, i) => {
      const shape = String(area.props.shape ?? 'rect').toLowerCase();
      const coords = String(area.props.coords ?? '').split(',').map((c) => parseFloat(c)).filter((n) => Number.isFinite(n));
      const spec: AreaSpec = { shape: shape === 'circ' || shape === 'circle' ? 'circle' : shape === 'poly' || shape === 'polygon' ? 'poly' : shape === 'default' ? 'default' : 'rect', coords };
      specs.push(spec);
      const href = area.props.href != null ? String(area.props.href) : null;
      const areaId = area.key ?? `${ctx.elementId}/area${i}`;
      regions.push(
        w('gesture', {
          gestures: ['tap'],
          cursor: 'pointer',
          tooltip: area.props.title ?? area.props.alt ?? null,
          semanticsLabel: area.props.alt ?? null,
          onEvent: (e: ViewEvent, ro: any) => {
            if (e.type !== 'tap') return;
            // Precise hit test in natural image pixels.
            const map = ro?.parent;
            const sx = map?.scale?.x ?? 1;
            const sy = map?.scale?.y ?? 1;
            const px = ((e.localX ?? 0) + (ro?.offset?.x ?? 0)) / sx;
            const py = ((e.localY ?? 0) + (ro?.offset?.y ?? 0)) / sy;
            if (!areaContains(spec, px, py)) return;
            if (area.events) {
              ctx.engine.services.events.registerNode(areaId, area, ctx.elementId);
              ctx.engine.handleGesture(areaId, area, { ...e, type: 'tap' });
            }
            if (href) openLink(ctx, href, null);
          },
        }),
      );
    });
    result = w('imageMap', { src, areas: specs }, [img, ...regions]);
  }
  return applyStyle(result, s, {}, ctx);
}

/** `srcset` with `w` descriptors: the smallest candidate covering the viewport × dpr. */
function chooseSrcset(node: ElpianNode, fallback: string): string {
  const srcset = node.props.srcset ?? node.props.srcSet;
  if (typeof srcset !== 'string' || srcset.trim() === '') return fallback;
  const env = cssEnvironment();
  const target = env.viewportWidth * env.devicePixelRatio;
  const candidates = srcset
    .split(',')
    .map((part) => part.trim().split(/\s+/))
    .filter((p) => p[0])
    .map(([url, desc]) => {
      const d = desc ?? '1x';
      return { url, w: d.endsWith('w') ? parseFloat(d) : null, x: d.endsWith('x') ? parseFloat(d) : null };
    });
  const byWidth = candidates.filter((c) => c.w != null).sort((a, b) => a.w! - b.w!);
  if (byWidth.length) return (byWidth.find((c) => c.w! >= target) ?? byWidth[byWidth.length - 1]).url;
  const byDensity = candidates.filter((c) => c.x != null).sort((a, b) => a.x! - b.x!);
  if (byDensity.length) return (byDensity.find((c) => c.x! >= env.devicePixelRatio) ?? byDensity[byDensity.length - 1]).url;
  return fallback;
}

// ============================================================================
// Tables
// ============================================================================

function tableCell(node: ElpianNode, children: W[], ctx: BuildContext, header: boolean): W {
  const t = textOf(node);
  const base: TextStyle = header ? { fontWeight: 700 } : {};
  let child: W;
  if (children.length === 1) child = children[0];
  else if (children.length > 1) {
    child = richText(node, mergeTextStyle(base, createTextStyle(node.style)), ctx) ?? column(children, { crossAxisAlignment: 'start', mainAxisSize: 'min' });
  } else child = text(t, mergeTextStyle(base, createTextStyle(node.style)), textOptionsFromStyle(node.style));
  if (header && node.style?.textAlign == null) child = center(child);
  const style = withDefaults(node.style, { padding: insetsAll(8) });
  const boxed = applyStyle(child, style, {}, ctx);
  const va = String(node.style?.verticalAlign ?? node.props.valign ?? 'middle');
  return w('tableCell', { colSpan: num(node.props.colspan ?? node.props.colSpan) ?? 1, rowSpan: num(node.props.rowspan ?? node.props.rowSpan) ?? 1, verticalAlign: va === 'top' ? 'top' : va === 'bottom' ? 'bottom' : 'middle', width: num(node.props.width) }, boxed);
}

function tableRow(node: ElpianNode, children: W[]): W {
  const cells = children.map((c) => (c.t === 'tableCell' ? c : w('tableCell', {}, c)));
  return w('tableRow', { decorated: node.style?.backgroundColor != null, background: node.style?.backgroundColor ?? null }, cells);
}

function htmlTable(node: ElpianNode, children: W[], ctx: BuildContext): W {
  const rows: W[] = [];
  let caption: W | null = null;
  node.children.forEach((child, i) => {
    const wc = children[i];
    if (child.type === 'caption') caption = wc;
    else if (['thead', 'tbody', 'tfoot'].includes(child.type)) {
      // Row groups are flattened; their rows were lowered as the group's children.
      for (const r of wc.c ?? []) rows.push(r);
    } else if (child.type === 'tr') rows.push(wc);
    else if (child.type === 'colgroup' || child.type === 'col') {
      // Column hints are read through cell widths.
    } else rows.push(w('tableRow', {}, [w('tableCell', {}, wc)]));
  });
  const collapse = node.style?.borderCollapse === 'collapse';
  const table = w(
    'table',
    {
      collapse,
      borderSpacing: collapse ? 0 : node.style?.borderSpacing ?? num(node.props.cellspacing) ?? 2,
      caption: 'top',
      fullWidth: node.style?.width != null || node.style?.widthFactor != null,
    },
    caption ? [caption, ...rows] : rows,
  );
  // Flutter's Table(border: TableBorder.all()) draws grid lines; a bordered table keeps them.
  const bordered = node.props.border != null && node.props.border !== '0';
  const result = bordered ? decorated({ border: borderAll({ width: 1, color: Colors.black, style: 'solid' }) }, table) : table;
  return applyStyle(result, node.style, {}, ctx);
}

// ============================================================================
// Lists, details, dialog, misc
// ============================================================================

function listItem(node: ElpianNode, children: W[], ctx: BuildContext, marker: string): W {
  const ts = createTextStyle(node.style);
  const rich = richText(node, ts ?? {}, ctx);
  const content = rich ?? (children.length === 1 ? children[0] : children.length > 1 ? column(children, { crossAxisAlignment: 'start', mainAxisSize: 'min' }) : text(textOf(node), ts));
  const result = w('flex', { direction: 'row', crossAxisAlignment: 'start', mainAxisSize: 'max' }, [text(marker, ts), expanded(content)]);
  return applyStyle(result, node.style, {}, ctx);
}

function detailsElement(node: ElpianNode, children: W[], ctx: BuildContext): W {
  const state = ctx.engine.stateFor(ctx.elementId, () => ({ open: node.props.open === true || node.props.open === 'open' }));
  const summaryIndex = node.children.findIndex((c) => c.type === 'summary');
  const summary = summaryIndex >= 0 ? children[summaryIndex] : text('Details', { fontWeight: 600 });
  const body = children.filter((_, i) => i !== summaryIndex);
  const header = w(
    'gesture',
    {
      gestures: ['tap'],
      ripple: scaleAlpha(M3.onSurface, 0.08),
      cursor: 'pointer',
      role: 'button',
      onEvent: (e: ViewEvent) => {
        if (e.type !== 'tap') return;
        state.open = !state.open;
        dispatchEvent(ctx, 'toggle', { data: { open: state.open } });
        ctx.engine.host.invalidate?.();
      },
    },
    padding(insetsSymmetric(8, 0), row([expanded(summary), w('animatedTransform', { turns: state.open ? 0.5 : 0, duration: 200, curve: 'easeInOut', alignment: { x: 0, y: 0 } }, icon('expand_more', 24))], { mainAxisSize: 'max' })),
  );
  const content = w('animatedSize', { duration: 200, curve: 'easeInOut', alignment: { x: -1, y: -1 } }, state.open ? column(body, { crossAxisAlignment: 'start', mainAxisSize: 'min' }) : SHRINK);
  return applyStyle(column([header, content], { crossAxisAlignment: 'stretch', mainAxisSize: 'min' }), node.style, {}, ctx);
}

function dialogElement(node: ElpianNode, children: W[], ctx: BuildContext): W {
  if (node.props.open === false || node.props.open === 'false') return SHRINK;
  const content = padding(insetsAll(24), column(children, { crossAxisAlignment: 'start', mainAxisSize: 'min' }));
  const card = decorated(
    { color: node.style?.backgroundColor ?? 0xffece6f0, radius: node.style?.borderRadius ?? radiusAll(28), shadows: [{ dx: 0, dy: 3, blur: 5, spread: -1, color: 0x33000000 }, { dx: 0, dy: 6, blur: 10, spread: 0, color: 0x24000000 }, { dx: 0, dy: 1, blur: 18, spread: 0, color: 0x1f000000 }] },
    w('constrained', { minWidth: 280, maxWidth: 560 }, content),
  );
  const inset = padding({ top: 24, right: 40, bottom: 24, left: 40 }, card);
  return applyStyle(center(inset), withDefaults(node.style, {}), {}, ctx);
}

function progressElement(node: ElpianNode, meter: boolean): W {
  const value = num(node.props.value);
  const min = num(node.props.min) ?? 0;
  const max = num(node.props.max) ?? 1;
  let fraction: number | null;
  if (meter) fraction = ((value ?? 0.5) - min) / (max - min || 1);
  else fraction = value != null ? value / (max || 1) : null;
  let indicator: Color = node.style?.color ?? (meter ? Colors.green : M3.primary);
  if (meter) {
    const low = num(node.props.low);
    const high = num(node.props.high);
    const v = value ?? 0.5;
    if ((low != null && v < low) || (high != null && v > high)) indicator = node.style?.color ?? Colors.amber;
  }
  return w('control', {
    kind: 'progress',
    focusId: node.props.id != null ? String(node.props.id) : null,
    width: node.style?.width ?? null,
    view: {
      variant: 'linear',
      value: fraction == null ? null : Math.max(0, Math.min(1, fraction)),
      strokeWidth: node.style?.height ?? 4,
      colors: { indicator, track: node.style?.backgroundColor ?? 0xffeeeeee },
    },
  });
}

/** `<picture>`: the first `<source>` whose media matches, applied to the inner `<img>`. */
function pictureElement(node: ElpianNode, children: W[], ctx: BuildContext): W {
  const env = cssEnvironment();
  const source = node.children.find(
    (c) => c.type === 'source' && (c.props.srcset || c.props.srcSet || c.props.src) && (!c.props.media || mediaMatches(String(c.props.media), env.viewportWidth, env.viewportHeight)),
  );
  const imgIndex = node.children.findIndex((c) => c.type === 'img');
  if (imgIndex >= 0) {
    const img = node.children[imgIndex];
    if (source) {
      const srcset = String(source.props.srcset ?? source.props.srcSet ?? source.props.src);
      const first = srcset.split(',')[0].trim().split(/\s+/)[0];
      const swapped: ElpianNode = { ...img, props: { ...img.props, src: first, srcset: srcset.includes(',') ? srcset : img.props.srcset } };
      return applyStyle(htmlImg(swapped, [], { ...ctx, elementId: `${ctx.elementId}/img` }), node.style, {}, ctx);
    }
    return applyStyle(children[imgIndex], node.style, {}, ctx);
  }
  const fallback = children.find((c) => c.t !== 'constrained') ?? children[0] ?? SHRINK;
  return applyStyle(fallback, node.style, {}, ctx);
}

const hidden: WidgetBuilder = () => SHRINK;

// ============================================================================
// Registry
// ============================================================================

export const htmlWidgets: Record<string, WidgetBuilder> = {
  div: (node, children, ctx) => htmlDiv(node, children, ctx),
  section: (node, children, ctx) => htmlDiv(node, children, ctx),
  article: (node, children, ctx) => htmlDiv(node, children, ctx),
  aside: (node, children, ctx) => htmlDiv(node, children, ctx),
  main: (node, children, ctx) => htmlDiv(node, children, ctx),
  header: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),
  footer: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),
  body: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),
  html: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),

  span(node, children, ctx) {
    const s = node.style;
    const ts = createTextStyle(s) ?? {};
    const opts: Record<string, any> = { overflow: s?.textOverflow ?? undefined };
    if (s?.whiteSpace === 'nowrap') {
      opts.maxLines = 1;
      opts.softWrap = false;
    }
    if (children.length === 0) return applyStyle(text(textOf(node), ts, opts), s, {}, ctx);
    const rich = richText(node, ts, ctx, opts);
    if (rich) return applyStyle(rich, s, {}, ctx);
    const parts: W[] = [];
    const t = textOf(node);
    if (t) parts.push(text(t, ts, opts));
    parts.push(...children);
    return applyStyle(w('wrap', { direction: 'horizontal', crossAxisAlignment: 'center' }, parts), s, { layoutHandled: true }, ctx);
  },

  p: (node, children, ctx) => textWithChildren(node, children, ctx, { margin: insetsSymmetric(8, 0) }, 'wrap'),
  h1: heading(32, 16),
  h2: heading(28, 14),
  h3: heading(24, 12),
  h4: heading(20, 10),
  h5: heading(16, 8),
  h6: heading(14, 6),

  a(node, children, ctx) {
    const href = String(node.props.href ?? '#');
    const style = withDefaults(node.style, { color: Colors.blue, textDecoration: { underline: true, overline: false, lineThrough: false } });
    const ts = createTextStyle(style) ?? {};
    let content: W;
    const rich = richText(node, ts, ctx);
    if (rich) content = rich;
    else if (children.length) {
      const parts: W[] = [];
      const t = textOf(node);
      if (t) parts.push(text(t, ts));
      parts.push(...children);
      content = w('wrap', { direction: 'horizontal', crossAxisAlignment: 'center' }, parts);
    } else content = text(textOf(node), ts);
    const link = w(
      'gesture',
      {
        gestures: ['tap'],
        cursor: 'pointer',
        role: 'link',
        semanticsLabel: node.props.title ?? null,
        onEvent: (e: ViewEvent) => {
          if (e.type === 'tap') {
            const target = String(node.props.target ?? '');
            if (target === '_blank' && /^https?:/i.test(href)) ctx.engine.host.openUrl?.(href);
            else openLink(ctx, href, node);
          }
        },
      },
      content,
    );
    return applyStyle(link, style, {}, ctx);
  },

  button: (node, children, ctx) => htmlButtonLike(node, children, ctx),
  input: htmlInput,
  textarea: htmlTextarea,
  select: htmlSelect,
  option: (node) => text(String(node.props.text ?? node.props.label ?? '')),
  optgroup(node, children, ctx) {
    const label = String(node.props.label ?? '');
    return applyStyle(column([text(label, { fontWeight: 700 }), ...children], { crossAxisAlignment: 'start', mainAxisSize: 'max' }), node.style, {}, ctx);
  },
  datalist: hidden,
  label(node, children, ctx) {
    const ts: TextStyle = { fontWeight: 500, ...(createTextStyle(node.style) ?? {}) };
    const rich = richText(node, ts, ctx);
    let result = rich ?? (children.length ? row([text(textOf(node), ts), ...children], { mainAxisSize: 'min' }) : text(textOf(node), ts));
    const forId = node.props.for ?? node.props.htmlFor;
    if (forId) {
      result = w('gesture', { gestures: ['tap'], cursor: 'pointer', onEvent: () => ctx.engine.focusElement(String(forId)) }, result);
    }
    return applyStyle(result, node.style, {}, ctx);
  },
  form(node, children, ctx) {
    return applyStyle(column(children, { crossAxisAlignment: 'start', mainAxisSize: 'max' }), node.style, {}, ctx);
  },
  fieldset(node, children, ctx) {
    const box = container({
      padding: insetsAll(16),
      decoration: { border: borderAll({ width: 1, color: Colors.grey, style: 'solid' }), radius: radiusAll(4) },
      child: column(children, { crossAxisAlignment: 'start', mainAxisSize: 'max' }),
    });
    return applyStyle(box, node.style, {}, ctx);
  },
  legend(node, _children, ctx) {
    return applyStyle(text(textOf(node), { fontWeight: 700 }), node.style, {}, ctx);
  },
  output(node, _children, ctx) {
    const box = container({
      padding: insetsAll(8),
      decoration: { border: borderAll({ width: 1, color: Colors.grey, style: 'solid' }), radius: radiusAll(4) },
      child: text(textOf(node), createTextStyle(node.style)),
    });
    return applyStyle(box, node.style, {}, ctx);
  },

  img: htmlImg,
  picture: pictureElement,
  source: hidden,
  track: hidden,
  param: hidden,
  map: hidden,
  area: hidden,
  video: mediaElement('video'),
  audio: mediaElement('audio'),
  iframe: (node, _children, ctx) => webContent(node, ctx, String(node.props.src ?? ''), 'iframe'),
  embed: (node, children, ctx) => embedTyped(node, children, ctx, String(node.props.src ?? '')),
  object(node, children, ctx) {
    const data = String(node.props.data ?? '');
    // `<param>` children become query parameters of the embedded content.
    const params = node.children.filter((c) => c.type === 'param' && c.props.name);
    let src = data;
    if (params.length && data && !looksLike('image', String(node.props.type ?? ''), data)) {
      const q = params.map((p) => `${encodeURIComponent(String(p.props.name))}=${encodeURIComponent(String(p.props.value ?? ''))}`).join('&');
      src = data + (data.includes('?') ? '&' : '?') + q;
    }
    return embedTyped(node, children, ctx, src);
  },
  canvas(node, children, ctx) {
    const raw = Array.isArray(node.props.commands) ? node.props.commands : [];
    const commands = raw.filter((c: any) => c && typeof c === 'object').map((c: any) => normalizeCommand(commandFromJson(c)));
    const contextId = node.props.contextId;
    if (contextId) return applyStyle(flutterWidgets.CachedCanvas(node, children, ctx), node.style, {}, ctx);
    const result = w('canvas', {
      width: num(node.props.width) ?? node.style?.width ?? null,
      height: num(node.props.height) ?? node.style?.height ?? null,
      background: CSSParser.parseColor(node.props.backgroundColor) ?? node.style?.backgroundColor ?? null,
      commands,
      onEvent: (e: ViewEvent) => ctx.engine.handleGesture(ctx.elementId, node, e),
    });
    return applyStyle(result, node.style, {}, ctx);
  },

  ul(node, children, ctx) {
    const items = children.map((c, i) => (node.children[i].type === 'li' ? c : listItemWrap(c, '• ')));
    return applyStyle(column(items, { crossAxisAlignment: 'start', mainAxisSize: 'max' }), node.style, {}, ctx);
  },
  ol(node, children, ctx) {
    const start = num(node.props.start) ?? 1;
    const items = children.map((c, i) => {
      const li = node.children[i];
      const marker = `${start + i}. `;
      // Flutter renders `ol` items as Row(Text('n. '), Expanded(li)); an li's own bullet is replaced.
      if (li.type === 'li') return listItem(li, (c.c ?? []) as W[], { ...ctx, elementId: `${ctx.elementId}/${i}` }, marker);
      return listItemWrap(c, marker);
    });
    return applyStyle(column(items, { crossAxisAlignment: 'start', mainAxisSize: 'max' }), node.style, {}, ctx);
  },
  li: (node, children, ctx) => listItem(node, children, ctx, '• '),

  table: htmlTable,
  thead: (_node, children) => w('proxy', {}, children),
  tbody: (_node, children) => w('proxy', {}, children),
  tfoot: (_node, children) => w('proxy', {}, children),
  caption: (node, children, ctx) => textWithChildren(node, children, ctx, { textAlign: 'center', padding: insetsSymmetric(4, 0) }, 'column'),
  colgroup: hidden,
  col: hidden,
  tr: (node, children) => tableRow(node, children),
  td: (node, children, ctx) => tableCell(node, children, ctx, false),
  th: (node, children, ctx) => tableCell(node, children, ctx, true),

  strong: (node, _c, ctx) => textElement(node, ctx, { fontWeight: 700 }),
  b: (node, _c, ctx) => textElement(node, ctx, { fontWeight: 700 }),
  em: (node, _c, ctx) => textElement(node, ctx, { fontStyle: 'italic' }),
  i: (node, _c, ctx) => textElement(node, ctx, { fontStyle: 'italic' }),
  u: (node, _c, ctx) => textElement(node, ctx, { textDecoration: { underline: true, overline: false, lineThrough: false } }),
  s: (node, _c, ctx) => textElement(node, ctx, { textDecoration: { underline: false, overline: false, lineThrough: true } }),
  q: (node, _c, ctx) => applyStyle(text(`“${textOf(node)}”`, createTextStyle(node.style)), node.style, {}, ctx),
  code: (node, _c, ctx) => replaceDefaults(node, ctx, monoStyle(0xfff5f5f5, insetsSymmetric(2, 4)), INLINE_DEFAULTS.code),
  pre(node, _children, ctx) {
    const style = node.style ?? monoStyle(0xfff5f5f5, insetsAll(8));
    const ts = createTextStyle(style) ?? {};
    const body = w('scroll', { axis: 'horizontal' }, text(textOf(node), { fontFamily: 'monospace', ...ts }, { softWrap: false }));
    return applyStyle(body, style, {}, ctx);
  },
  kbd: (node, _c, ctx) => replaceDefaults(node, ctx, monoStyle(0xffeeeeee, insetsAll(4), { borderRadius: radiusAll(3) }), INLINE_DEFAULTS.kbd),
  samp: (node, _c, ctx) => replaceDefaults(node, ctx, { fontFamily: 'monospace' }, INLINE_DEFAULTS.samp),
  var: (node, _c, ctx) => replaceDefaults(node, ctx, { fontStyle: 'italic' }, INLINE_DEFAULTS.var),
  cite: (node, _c, ctx) => replaceDefaults(node, ctx, { fontStyle: 'italic' }, INLINE_DEFAULTS.cite),
  mark: (node, _c, ctx) => replaceDefaults(node, ctx, { backgroundColor: 0xffffff00, padding: insetsSymmetric(2, 4) }, INLINE_DEFAULTS.mark),
  del: (node, _c, ctx) => replaceDefaults(node, ctx, { textDecoration: { underline: false, overline: false, lineThrough: true } }, INLINE_DEFAULTS.del),
  ins: (node, _c, ctx) => replaceDefaults(node, ctx, { textDecoration: { underline: true, overline: false, lineThrough: false } }, INLINE_DEFAULTS.ins),
  small: (node, _c, ctx) => replaceDefaults(node, ctx, { fontSize: 12 }, INLINE_DEFAULTS.small),
  sub(node, _c, ctx) {
    const style = node.style ?? { fontSize: 10 };
    const ts = mergeTextStyle({ baselineShift: 3 }, createTextStyle(style));
    return w('padding', { padding: { top: 4, right: 0, bottom: 0, left: 0 } }, text(textOf(node), ts));
  },
  sup(node, _c, ctx) {
    const style = node.style ?? { fontSize: 10 };
    const ts = mergeTextStyle({ baselineShift: -6 }, createTextStyle(style));
    return w('padding', { padding: { top: 0, right: 0, bottom: 4, left: 0 } }, text(textOf(node), ts));
  },
  abbr(node, _c, ctx) {
    const result = w('gesture', { gestures: ['longpress', 'hover'], tooltip: String(node.props.title ?? ''), onEvent: () => {} }, text(textOf(node), { decoration: Deco.underline, ...(createTextStyle(node.style) ?? {}) }));
    return applyStyle(result, node.style, {}, ctx);
  },
  time: (node, _c, ctx) => applyStyle(text(textOf(node), createTextStyle(node.style)), node.style, {}, ctx),
  data: (node, _c, ctx) => applyStyle(text(textOf(node), createTextStyle(node.style)), node.style, {}, ctx),
  blockquote(node, children, ctx) {
    const child = children.length === 1 ? children[0] : children.length > 1 ? column(children, { crossAxisAlignment: 'start', mainAxisSize: 'min' }) : text(textOf(node), createTextStyle(node.style));
    const box = container({ padding: insetsAll(16), decoration: { border: { top: none(), right: none(), bottom: none(), left: { width: 4, color: Colors.grey, style: 'solid' } } }, child });
    const style = node.style ?? { padding: insetsAll(16), margin: insetsSymmetric(8, 0), borderColor: Colors.grey, borderWidth: 4 };
    return applyStyle(box, { ...style, padding: undefined, border: undefined, borderColor: undefined, borderWidth: undefined }, {}, ctx);
  },
  hr(node, _c, ctx) {
    return applyStyle(flutterWidgets.Divider({ ...node, style: null }, [], ctx), node.style, {}, ctx);
  },
  br: () => sizedBox(null, 16),
  figure(node, children, ctx) {
    return applyStyle(column(children, { crossAxisAlignment: 'start', mainAxisSize: 'min' }), node.style, {}, ctx);
  },
  figcaption: (node, _c, ctx) => replaceDefaults(node, ctx, { fontStyle: 'italic', color: Colors.grey, fontSize: 14 }, { italic: true, color: Colors.grey, fontSize: 14 }),
  details: detailsElement,
  summary: (node, children, ctx) => textWithChildren(node, children, ctx, { fontWeight: 700 }, 'wrap'),
  dialog: dialogElement,
  progress: (node) => progressElement(node, false),
  meter: (node) => progressElement(node, true),
  nav(node, children, ctx) {
    const s = node.style;
    const result = w(
      'flex',
      { direction: 'row', mainAxisAlignment: mainOf(s?.justifyContent ?? 'space-around'), crossAxisAlignment: crossOf(s?.alignItems), mainAxisSize: 'max', gap: s?.gap ?? 0, shrink: true },
      children,
    );
    return applyStyle(result, s, { layoutHandled: true }, ctx);
  },
};

function none() {
  return { width: 0, color: Colors.black, style: 'none' as const };
}

function listItemWrap(child: W, marker: string): W {
  return w('flex', { direction: 'row', crossAxisAlignment: 'start', mainAxisSize: 'max' }, [text(marker), expanded(child)]);
}
