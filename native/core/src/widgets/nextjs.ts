/**
 * Server-driven navigation widgets — ports of `NextjsBridge`'s `NextjsLink`
 * (`next-link`) and `NextjsForm` (`nextjs-form`) builders
 * (flutter/lib/src/integrations/nextjs_bridge.dart). Navigation and form
 * submission go through the engine host (`EngineHost.navigate` /
 * `EngineHost.submitForm`), which the Next.js session implements.
 */
import { scaleAlpha, withOpacity, type Color } from '../css/color.js';
import { CSSParser } from '../css/parser.js';
import type { CSSStyle } from '../css/style.js';
import { borderAll, insetsAll, insetsOnly, insetsSymmetric, radiusAll } from '../css/types.js';
import type { ElpianNode } from '../model/node.js';
import { w, type W } from '../render/object.js';
import { toSpec, type TextStyle } from '../render/text-style.js';
import type { ViewEvent } from '../render/view.js';
import { toNumber } from '../util/json.js';
import type { BuildContext, WidgetBuilder } from './context.js';
import { mainAxisAlignmentFromCss, crossAxisAlignmentFromCss } from '../render/layout/flex.js';
import { SHRINK, applyStyle, column, container, expanded, padding, row, sizedBox, text } from './style.js';

const GOLD: Color = 0xffd6b36a;
const FIELD_FILL: Color = 0xff0a1626;
const FIELD_BORDER: Color = 0xff1c3450;
const TEXT: Color = 0xfff7eedc;
const HINT: Color = 0xff6e8394;
const INK: Color = 0xff06122a;
const ERROR: Color = 0xffc0492f;

// ============================================================================
// NextjsLink
// ============================================================================

function linkChildStyle(child: ElpianNode): CSSStyle | null {
  if (child.style) return child.style;
  const inline = child.props.style;
  if (inline && typeof inline === 'object' && !Array.isArray(inline)) return CSSParser.parse(inline);
  return null;
}

function withGaps(children: W[], gap: number, horizontal: boolean): W[] {
  if (gap <= 0 || children.length <= 1) return children;
  const out: W[] = [];
  children.forEach((c, i) => {
    out.push(c);
    if (i < children.length - 1) out.push(sizedBox(horizontal ? gap : 0, horizontal ? 0 : gap));
  });
  return out;
}

function linkFlow(node: ElpianNode, flow: W[]): W {
  const s = node.style;
  const isColumn = s?.flexDirection === 'column' || s?.flexDirection === 'column-reverse';
  const children = withGaps(flow, s?.gap ?? 0, !isColumn);
  const opts = {
    mainAxisSize: 'min',
    mainAxisAlignment: mainAxisAlignmentFromCss(s?.justifyContent),
    crossAxisAlignment: s?.alignItems == null ? 'center' : crossAxisAlignmentFromCss(s?.alignItems),
  };
  return isColumn ? column(children, opts) : row(children, opts);
}

function layoutLinkChildren(node: ElpianNode, children: W[]): W {
  const aligned = node.children.length === children.length;
  const flow: W[] = [];
  const overlays: W[] = [];
  children.forEach((child, i) => {
    const cs = aligned ? linkChildStyle(node.children[i]) : null;
    if (cs && (cs.position === 'absolute' || cs.position === 'fixed')) {
      overlays.push(w('positioned', { top: cs.top ?? null, left: cs.left ?? null, right: cs.right ?? null, bottom: cs.bottom ?? null }, child));
    } else flow.push(child);
  });
  const base = flow.length === 0 ? SHRINK : flow.length === 1 ? flow[0] : linkFlow(node, flow);
  if (!overlays.length) return base;
  // Clip.none: badges poke past the button's rounded corners.
  return w('stack', { fit: 'loose', clip: false }, [base, ...overlays]);
}

const nextjsLink: WidgetBuilder = (node, children, ctx) => {
  const href = node.props.href != null ? String(node.props.href) : null;
  const replace = node.props.replace === true;
  const label = node.props.text != null ? String(node.props.text) : href ?? 'Navigate';
  const s = node.style;
  const ariaLabel = node.props.ariaLabel != null ? String(node.props.ariaLabel) : null;
  const isButtonLike = s != null && (s.backgroundColor != null || s.gradient != null || s.border != null || s.borderColor != null || s.padding != null);

  const content = children.length
    ? layoutLinkChildren(node, children)
    : text(
        label,
        {
          color: s?.color ?? GOLD,
          fontSize: s?.fontSize ?? undefined,
          fontWeight: s?.fontWeight ?? (isButtonLike ? 700 : undefined),
          letterSpacing: s?.letterSpacing ?? undefined,
        },
        { textAlign: s?.textAlign ?? (isButtonLike ? 'center' : 'start') },
      );

  const styled = applyStyle(content, s, { applyFlex: false }, ctx);
  let tappable = w(
    'gesture',
    {
      gestures: href != null ? ['tap'] : [],
      opaque: true,
      cursor: href != null ? 'pointer' : 'default',
      role: ariaLabel ? 'button' : 'link',
      semanticsLabel: ariaLabel,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'tap' && href != null) ctx.engine.host.navigate?.(href, replace);
      },
    },
    styled,
  );
  const flex = s?.flex ?? s?.flexGrow;
  if (flex != null) tappable = w('flexible', { flex, fit: 'tight' }, sizedBox(Number.POSITIVE_INFINITY, null, tappable));
  return tappable;
};

// ============================================================================
// NextjsForm
// ============================================================================

interface FieldOption {
  value: string;
  label: string;
}

function optionsOf(f: Record<string, any>): FieldOption[] {
  const out: FieldOption[] = [];
  if (Array.isArray(f.options)) {
    for (const o of f.options) {
      if (o && typeof o === 'object') {
        const v = String(o.value ?? o.label ?? '');
        out.push({ value: v, label: String(o.label ?? v) });
      } else if (o != null) out.push({ value: String(o), label: String(o) });
    }
  }
  if (!out.length) {
    for (const part of String(f.placeholder ?? '').split(',')) {
      const v = part.trim();
      if (v) out.push({ value: v, label: v });
    }
  }
  return out;
}

function numProp(f: Record<string, any>, key: string, fallback: number): number {
  return toNumber(f[key]) ?? fallback;
}

function fmtRange(v: number): string {
  return v === Math.round(v) ? String(Math.round(v)) : String(v);
}

const isTextLike = (type: string) => type !== 'hidden' && type !== 'select' && type !== 'checkbox' && type !== 'range';

interface FormState {
  values: Record<string, string>;
  busy: boolean;
  error: string | null;
}

function fieldBox(child: W, pad = insetsSymmetric(4, 8)): W {
  return container({ child, padding: pad, decoration: { color: FIELD_FILL, radius: radiusAll(10), border: borderAll({ width: 1, color: FIELD_BORDER, style: 'solid' }) } });
}

const nextjsForm: WidgetBuilder = (node, _children, ctx) => {
  const action = String(node.props.action ?? '');
  const submitLabel = String(node.props.submitLabel ?? 'Submit');
  const fields: Record<string, any>[] = Array.isArray(node.props.fields) ? node.props.fields.filter((f: unknown) => f && typeof f === 'object') : [];

  const state = ctx.engine.stateFor<FormState>(ctx.elementId, () => {
    const values: Record<string, string> = {};
    for (const f of fields) {
      const name = String(f.name ?? '');
      if (!name) continue;
      const type = String(f.type ?? '');
      const value = f.value != null ? String(f.value) : '';
      if (type === 'select') {
        const options = optionsOf(f);
        values[name] = options.some((o) => o.value === value) ? value : options[0]?.value ?? value;
      } else if (type === 'checkbox') {
        values[name] = value === 'true' || value === 'on' ? 'true' : 'false';
      } else if (type === 'range') {
        const min = numProp(f, 'min', 0);
        const max = numProp(f, 'max', 100);
        const parsed = toNumber(value);
        values[name] = fmtRange(max > min ? Math.min(max, Math.max(min, parsed ?? min)) : min);
      } else values[name] = value; // text-like and hidden
    }
    return { values, busy: false, error: null };
  });

  const update = (patch: Partial<FormState>) => {
    Object.assign(state, patch);
    ctx.engine.host.invalidate?.();
  };

  const submit = async () => {
    const handler = ctx.engine.host.submitForm;
    if (!handler || state.busy) return;
    update({ busy: true, error: null });
    let error: string | null = null;
    try {
      error = await handler(action, { ...state.values });
    } catch (e) {
      error = `Request failed: ${e}`;
    }
    update({ busy: false, error });
  };

  const labelOf = (label: string) => padding(insetsOnly({ bottom: 4 }), text(label, { color: HINT, fontSize: 11, fontWeight: 600 }));
  const items: W[] = [];

  for (const f of fields) {
    const name = String(f.name ?? '');
    if (!name) continue;
    const type = String(f.type ?? '');
    if (type === 'hidden') continue;
    const label = f.label != null ? String(f.label) : null;
    let control: W;

    if (type === 'select') {
      const options = optionsOf(f);
      const current = options.some((o) => o.value === state.values[name]) ? state.values[name] : options[0]?.value ?? null;
      const ts: TextStyle = { color: TEXT, fontSize: 14 };
      control = container({
        padding: insetsSymmetric(4, 10),
        decoration: { color: FIELD_FILL, radius: radiusAll(10), border: borderAll({ width: 1, color: FIELD_BORDER, style: 'solid' }) },
        child: w('control', {
          kind: 'select',
          view: {
            value: current,
            options: options.map((o) => ({ value: o.value, label: o.label, group: null, disabled: false })),
            placeholder: String(f.placeholder ?? name),
            enabled: !state.busy,
            textStyle: toSpec(ts),
            hintStyle: toSpec({ ...ts, color: HINT }),
            colors: { text: TEXT, fill: FIELD_FILL, icon: GOLD, menu: FIELD_FILL, hint: HINT },
          },
          onEvent: (e: ViewEvent) => {
            if (e.type === 'change') update({ values: { ...state.values, [name]: String(e.value ?? current ?? '') } });
          },
        }),
      });
    } else if (type === 'checkbox') {
      const checked = state.values[name] === 'true';
      const toggle = (v: boolean) => update({ values: { ...state.values, [name]: v ? 'true' : 'false' } });
      control = w(
        'gesture',
        {
          gestures: state.busy ? [] : ['tap'],
          ripple: scaleAlpha(GOLD, 0.12),
          rippleRadius: 10,
          cursor: state.busy ? 'default' : 'pointer',
          onEvent: (e: ViewEvent) => {
            if (e.type === 'tap') toggle(!checked);
          },
        },
        fieldBox(
          row(
            [
              w('control', {
                kind: 'checkbox',
                view: { checked, enabled: !state.busy, colors: { fill: GOLD, check: INK, border: HINT } },
                controlled: true,
                onEvent: (e: ViewEvent) => {
                  if (e.type === 'change') toggle(e.value === true);
                },
              }),
              w('flexible', { flex: 1, fit: 'loose' }, text(String(f.placeholder ?? label ?? name), { color: TEXT, fontSize: 13 })),
            ],
            { mainAxisSize: 'min' },
          ),
        ),
      );
    } else if (type === 'range') {
      const min = numProp(f, 'min', 0);
      const max = numProp(f, 'max', 100);
      const step = numProp(f, 'step', 1);
      const hasRoom = max > min;
      const current = hasRoom ? Math.min(max, Math.max(min, toNumber(state.values[name]) ?? min)) : min;
      const slider = hasRoom
        ? w('control', {
            kind: 'slider',
            view: {
              value: current,
              min,
              max,
              step: step > 0 ? step : null,
              enabled: !state.busy,
              trackHeight: 3,
              colors: { active: GOLD, inactive: FIELD_BORDER, thumb: GOLD, overlay: withOpacity(GOLD, 0.15) },
            },
            controlled: true,
            onEvent: (e: ViewEvent) => {
              if (e.type === 'change' || e.type === 'input') update({ values: { ...state.values, [name]: fmtRange(Number(e.value)) } });
            },
          })
        : padding(insetsSymmetric(8, 0), text(String(f.placeholder ?? 'No range available'), { color: HINT, fontSize: 13 }));
      control = fieldBox(
        row([expanded(slider), sizedBox(6, null), text(state.values[name] ?? fmtRange(current), { color: GOLD, fontSize: 13, fontWeight: 700 })]),
        insetsSymmetric(6, 10),
      );
    } else {
      const multiline = type === 'textarea';
      const ts: TextStyle = { color: TEXT, fontSize: 14, height: 1.3 };
      control = w('control', {
        kind: 'textInput',
        lines: multiline ? 3 : 1,
        maxLines: multiline ? 4 : 1,
        padding: [12, 12, 12, 12],
        lineHeight: 14 * 1.3,
        view: {
          value: state.values[name] ?? '',
          placeholder: String(f.placeholder ?? name),
          inputType: type === 'password' ? 'password' : type === 'number' ? 'number' : 'text',
          allowedPattern: type === 'number' ? '[0-9.\\-]' : undefined,
          multiline,
          enabled: true,
          variant: 'outline',
          textStyle: toSpec(ts),
          hintStyle: toSpec({ ...ts, color: HINT }),
          contentPadding: [12, 12, 12, 12],
          colors: { text: TEXT, hint: HINT, fill: FIELD_FILL, border: FIELD_BORDER, focusedBorder: GOLD, focusedBorderWidth: 1.5 as any, cursor: GOLD, radius: 10 as any },
        },
        onEvent: (e: ViewEvent) => {
          if (e.type === 'input' || e.type === 'change') state.values = { ...state.values, [name]: String(e.value ?? '') };
          else if (e.type === 'submit' && !multiline && !state.busy) void submit();
        },
      });
    }

    items.push(padding(insetsOnly({ bottom: 12 }), column([...(label ? [labelOf(label)] : []), control], { crossAxisAlignment: 'start', mainAxisSize: 'min' })));
  }

  if (state.error) items.push(padding(insetsOnly({ bottom: 8 }), text(state.error, { color: ERROR, fontSize: 13 })));

  const buttonChild = state.busy
    ? sizedBox(16, 16, w('control', { kind: 'progress', view: { variant: 'circular', value: null, strokeWidth: 2, colors: { indicator: INK, track: null } } }))
    : text(submitLabel, { fontWeight: 700, letterSpacing: 0.3, color: INK, fontSize: 14 });
  const button = w(
    'gesture',
    {
      gestures: state.busy ? [] : ['tap'],
      ripple: scaleAlpha(INK, 0.12),
      cursor: state.busy ? 'default' : 'pointer',
      role: 'button',
      semanticsLabel: submitLabel,
      onEvent: (e: ViewEvent) => {
        if (e.type === 'tap') void submit();
      },
    },
    container({
      padding: insetsSymmetric(14, 16),
      alignment: { x: 0, y: 0 },
      decoration: { color: state.busy ? withOpacity(GOLD, 0.5) : GOLD, radius: radiusAll(10), shadows: [] },
      child: buttonChild,
    }),
  );
  items.push(sizedBox(Number.POSITIVE_INFINITY, null, w('constrained', { minHeight: 40 }, button)));
  void insetsAll;
  return column(items, { mainAxisSize: 'min' });
};

export const nextjsWidgets: Record<string, WidgetBuilder> = {
  NextjsLink: nextjsLink,
  'next-link': nextjsLink,
  NextjsForm: nextjsForm,
  'nextjs-form': nextjsForm,
};
