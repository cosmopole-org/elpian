/**
 * Lowering: an A2UI surface → an Elpian node tree (the same JSON a mini app
 * renders), built from Elpian's existing widgets with Material 3 visuals, so
 * agent UI and static Elpian UI mix freely.
 *
 * | A2UI           | Elpian nodes                                                   |
 * |----------------|----------------------------------------------------------------|
 * | Text           | `Text` (typography per variant); Markdown → `p` + inline spans  |
 * | Image          | `Image` sized per variant (`ClipRRect` for avatars)             |
 * | Icon           | `Icon` (Material name) or an SVG-path `Image`                  |
 * | Video / Audio  | `video` / `audio` with controls                                |
 * | Row / Column   | `Row` / `Column` (justify → justifyContent, align → alignItems; `weight` → `Expanded`) |
 * | List           | `ListView` (vertical or horizontal scroll)                     |
 * | Card           | `Card`                                                         |
 * | Tabs           | tab header row + the selected child (state kept per surface)    |
 * | Modal          | the trigger; when open, a barrier + dialog over the surface     |
 * | Divider        | `Divider` / a vertical rule                                    |
 * | Button         | `Button` (default / primary / borderless; disabled by checks)   |
 * | TextField      | label + `TextField` (+ check error text)                       |
 * | CheckBox       | `Checkbox` + label                                              |
 * | ChoicePicker   | radio / checkbox list or chips, optional filter field          |
 * | Slider         | label + value + `Slider`                                        |
 * | DateTimeInput  | label + date / time / datetime `TextField`                     |
 *
 * Interactions are closures in the nodes' `events` (Elpian calls function
 * handlers directly); they write the data model (two-way binding), dispatch
 * actions, or change UI-local state through [LoweringHooks]. Nothing here
 * touches the DOM — the output is plain node JSON for any Elpian engine.
 */
import type { A2UIComponent, A2UISurfaceModel } from './processor.js';
import { evaluateChecks, isBinding, type DataContext } from './context.js';
import { A2UIError } from './errors.js';
import { stringifyValue } from './functions.js';
import { isPlainText, parseMarkdown, plainText, type MarkdownBlock, type MarkdownInline } from './markdown.js';

type Node = Record<string, any>;

export interface LoweringHooks {
  /** Two-way binding: write [value] at the absolute [path]. */
  write(surfaceId: string, path: string, value: unknown): void;
  /** An interactive component fired its `action` (resolved in [scope]). */
  action(surfaceId: string, componentId: string, action: unknown, scope: string): void;
  /** UI-local state changed (tab, modal, filter…): render again. */
  invalidate(): void;
  /** Evaluation problems (unknown function, bad template…). */
  error?(error: A2UIError): void;
}

/** UI-local state that survives re-lowering (selected tab, open modal, filter text, touched fields). */
export class A2UIUiState {
  private readonly values = new Map<string, unknown>();

  get<T>(key: string, fallback: T): T {
    return this.values.has(key) ? (this.values.get(key) as T) : fallback;
  }

  set(key: string, value: unknown): void {
    this.values.set(key, value);
  }

  /** Drop the state of one surface (after `deleteSurface`). */
  clearSurface(prefix: string): void {
    for (const k of [...this.values.keys()]) if (k.startsWith(prefix)) this.values.delete(k);
  }
}

export interface LoweringOptions {
  hooks: LoweringHooks;
  state: A2UIUiState;
  /** Prefix for node keys (element ids) — unique per embedding widget. */
  keyPrefix?: string;
  /** Show `agentDisplayName` / `iconUrl` above the surface (default true). */
  showAttribution?: boolean;
  /** Lower every deferred subtree too — closed modals, hidden tabs (previews, tests). */
  expandAll?: boolean;
}

export interface LoweringResult {
  node: Node;
  /** `componentId@scope` of every component lowered. */
  lowered: string[];
  /** Components rendered as an error placeholder (unknown type, cycle, depth). */
  placeholders: { id: string; reason: string }[];
}

/** The surface palette: Material 3 baseline with the theme's primary color. */
export interface A2UIPalette {
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onSurface: string;
  onSurfaceVariant: string;
  outline: string;
  outlineVariant: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  error: string;
}

export function paletteFor(theme: Record<string, unknown>): A2UIPalette {
  const primary = typeof theme.primaryColor === 'string' && /^#[0-9a-fA-F]{6}$/.test(theme.primaryColor) ? theme.primaryColor.toUpperCase() : '#6750A4';
  return {
    primary,
    onPrimary: luminance(primary) > 0.5 ? '#1D1B20' : '#FFFFFF',
    primaryContainer: mix(primary, '#FFFFFF', 0.82),
    onSurface: '#1D1B20',
    onSurfaceVariant: '#49454F',
    outline: '#79747E',
    outlineVariant: '#CAC4D0',
    surfaceContainer: '#F7F2FA',
    surfaceContainerHigh: '#ECE6F0',
    error: '#B3261E',
  };
}

function rgb(hex: string): [number, number, number] {
  const n = parseInt(hex.substring(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function luminance(hex: string): number {
  const [r, g, b] = rgb(hex).map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function mix(a: string, b: string, t: number): string {
  const x = rgb(a);
  const y = rgb(b);
  return '#' + x.map((c, i) => Math.round(c + (y[i] - c) * t).toString(16).padStart(2, '0')).join('').toUpperCase();
}

/** Leaf-margin strategy: visual leaves carry the spacing, containers none. */
const LEAF_MARGIN = 4;
const MAX_DEPTH = 64;

const TEXT_VARIANTS: Record<string, Record<string, unknown>> = {
  h1: { fontSize: 40, fontWeight: 600, lineHeight: 1.2 },
  h2: { fontSize: 32, fontWeight: 600, lineHeight: 1.25 },
  h3: { fontSize: 28, fontWeight: 600, lineHeight: 1.28 },
  h4: { fontSize: 24, fontWeight: 600, lineHeight: 1.33 },
  h5: { fontSize: 20, fontWeight: 600, lineHeight: 1.4 },
  caption: { fontSize: 13, lineHeight: 1.35 },
  body: { fontSize: 16, lineHeight: 1.5 },
};

/** A2UI icon names → Material icon names where the snake_case form differs. */
const ICON_ALIASES: Record<string, string> = {
  favoriteOff: 'favorite_border',
  starOff: 'star_border',
  play: 'play_arrow',
  rewind: 'fast_rewind',
};

/** The Material icon name for an A2UI icon name (`accountCircle` → `account_circle`). */
export function materialIconName(name: string): string {
  return ICON_ALIASES[name] ?? name.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
}

const JUSTIFY: Record<string, string> = {
  start: 'flex-start',
  center: 'center',
  end: 'flex-end',
  spaceBetween: 'space-between',
  spaceAround: 'space-around',
  spaceEvenly: 'space-evenly',
  stretch: 'flex-start',
};

const ALIGN: Record<string, string> = { start: 'flex-start', center: 'center', end: 'flex-end', stretch: 'stretch' };

interface Ctx {
  dc: DataContext;
  scope: string;
  depth: number;
  stack: string[];
  /** The A2UI type of the parent (for `weight`). */
  parent: string | null;
  /** Inside a button: no leaf margins, icons take the button's content color. */
  contentColor: string | null;
  /** Modal trigger: a press opens the modal instead of firing the action. */
  interceptPress: (() => void) | null;
}

function el(type: string, props: Node = {}, children: Node[] = [], extra: { key?: string; events?: Record<string, unknown> } = {}): Node {
  const node: Node = { type, props, children };
  if (extra.key) node.key = extra.key;
  if (extra.events && Object.keys(extra.events).length) node.events = extra.events;
  return node;
}

function textNode(text: string, style: Node = {}, key?: string): Node {
  return el('Text', { text, style }, [], { key });
}

/** Stop an internal event from bubbling into the embedding app's handlers. */
function handled(e: any): void {
  if (e && typeof e === 'object') e.propagationStopped = true;
}

/** Lower [surface] to an Elpian node tree. */
export function lowerSurface(surface: A2UISurfaceModel, options: LoweringOptions): LoweringResult {
  return new Lowerer(surface, options).run();
}

class Lowerer {
  readonly palette: A2UIPalette;
  readonly prefix: string;
  readonly lowered: string[] = [];
  readonly placeholders: { id: string; reason: string }[] = [];
  readonly overlays: Node[] = [];

  constructor(
    readonly surface: A2UISurfaceModel,
    readonly options: LoweringOptions,
  ) {
    this.palette = paletteFor(surface.theme);
    this.prefix = `${options.keyPrefix ?? 'a2ui'}:${surface.id}`;
  }

  get hooks(): LoweringHooks {
    return this.options.hooks;
  }

  private stateKey(key: string, what: string): string {
    return `${key}#${what}`;
  }

  run(): LoweringResult {
    const surface = this.surface;
    const parts: Node[] = [];
    const header = this.options.showAttribution === false ? null : this.attribution();
    if (header) parts.push(header);
    if (surface.isReady) {
      const ctx: Ctx = { dc: surface.context('/'), scope: '/', depth: 0, stack: [], parent: null, contentColor: null, interceptPress: null };
      parts.push(this.child('root', ctx));
    }
    let node: Node = el('Column', { style: { alignItems: 'stretch', justifyContent: 'flex-start', color: this.palette.onSurface } }, parts, { key: this.prefix });
    if (this.overlays.length) {
      node = el('ConstrainedBox', { style: { minHeight: 420 } }, [el('Stack', { style: { alignment: 'top left' } }, [node, ...this.overlays])]);
    }
    return { node, lowered: this.lowered, placeholders: this.placeholders };
  }

  private attribution(): Node | null {
    const theme = this.surface.theme;
    const name = typeof theme.agentDisplayName === 'string' ? theme.agentDisplayName : '';
    const icon = typeof theme.iconUrl === 'string' && /^https?:|^data:image\//i.test(theme.iconUrl) ? theme.iconUrl : '';
    if (!name && !icon) return null;
    const row: Node[] = [];
    if (icon) row.push(el('ClipRRect', { style: { borderRadius: 10 } }, [el('Image', { src: icon, fit: 'cover', alt: name, style: { width: 20, height: 20 } })]));
    if (name) row.push(textNode(name, { fontSize: 12, fontWeight: 500, color: this.palette.onSurfaceVariant, margin: '0 0 0 8' }));
    return el('Row', { style: { alignItems: 'center', padding: '4 4 8 4' } }, row, { key: `${this.prefix}/attribution` });
  }

  private keyFor(id: string, ctx: Ctx): string {
    return ctx.scope === '/' ? `${this.prefix}:${id}` : `${this.prefix}:${id}@${ctx.scope}`;
  }

  private report = (e: A2UIError) => this.hooks.error?.(new A2UIError(e.category, e.message, { surfaceId: this.surface.id, path: e.path }));

  private eval<T>(ctx: Ctx, fn: () => T, fallback: T): T {
    return ctx.dc.safe(fn, fallback, this.report);
  }

  private str(ctx: Ctx, v: unknown): string {
    return v === undefined ? '' : this.eval(ctx, () => ctx.dc.string(v), '');
  }

  private placeholder(id: string, reason: string, key: string): Node {
    this.placeholders.push({ id, reason });
    return el('Container', { style: { padding: 8, margin: LEAF_MARGIN, backgroundColor: '#FDECEA', borderRadius: 8 } }, [textNode(reason, { fontSize: 13, color: this.palette.error })], { key });
  }

  /** Lower the component [id] (a child reference) in [ctx]. */
  child(id: string, ctx: Ctx): Node {
    const component = this.surface.components.get(id);
    const key = this.keyFor(id, ctx);
    if (!component) return el('SizedBox', { width: 0, height: 0 }, [], { key }); // not arrived yet (progressive rendering)
    const marker = `${id}@${ctx.scope}`;
    if (ctx.stack.includes(marker)) return this.placeholder(id, `Circular reference to "${id}"`, key);
    if (ctx.depth >= MAX_DEPTH) return this.placeholder(id, 'Component tree too deep', key);
    this.lowered.push(marker);
    const inner: Ctx = { ...ctx, depth: ctx.depth + 1, stack: [...ctx.stack, marker] };
    let node = this.component(component, key, inner);
    const weight = typeof component.weight === 'number' ? component.weight : null;
    if (weight != null && weight > 0 && (ctx.parent === 'Row' || ctx.parent === 'Column')) {
      node = el('Expanded', { flex: weight }, [node]);
    } else if (ctx.parent === 'Row' && ['Text', 'Column', 'Row', 'List', 'Card', 'TextField', 'ChoicePicker', 'Slider', 'DateTimeInput'].includes(component.component)) {
      // A row shrinks text and nested layouts to its width (CSS flex-shrink).
      node = el('Flexible', { flex: 1, fit: 'loose' }, [node]);
    }
    return node;
  }

  private children(component: A2UIComponent, ctx: Ctx): Node[] {
    const spec = component.children;
    const out: Node[] = [];
    const childCtx: Ctx = { ...ctx, parent: component.component, interceptPress: null };
    if (Array.isArray(spec)) {
      for (const id of spec) if (typeof id === 'string') out.push(this.child(id, childCtx));
    } else if (spec && typeof spec === 'object' && typeof (spec as any).componentId === 'string' && typeof (spec as any).path === 'string') {
      const template = (spec as any).componentId as string;
      const base = ctx.dc.resolvePath((spec as any).path);
      const items = this.eval(ctx, () => ctx.dc.model.get(base), undefined);
      const join = (k: string | number) => (base === '/' ? `/${k}` : `${base}/${k}`);
      const keys: (string | number)[] = Array.isArray(items) ? items.map((_, i) => i) : items && typeof items === 'object' ? Object.keys(items) : [];
      for (const k of keys) {
        const scope = join(k);
        out.push(this.child(template, { ...childCtx, dc: ctx.dc.child(scope), scope }));
      }
    }
    return out;
  }

  private component(c: A2UIComponent, key: string, ctx: Ctx): Node {
    switch (c.component) {
      case 'Text':
        return this.text(c, key, ctx);
      case 'Image':
        return this.image(c, key, ctx);
      case 'Icon':
        return this.icon(c, key, ctx);
      case 'Video':
        return el('video', { src: this.str(ctx, c.url), controls: true, style: { height: 220, margin: LEAF_MARGIN, objectFit: 'contain' } }, [], { key });
      case 'AudioPlayer': {
        const description = this.str(ctx, c.description);
        const parts: Node[] = [];
        if (description) parts.push(textNode(description, { fontSize: 14, color: this.palette.onSurfaceVariant }));
        parts.push(el('audio', { src: this.str(ctx, c.url), controls: true, style: { height: 54 } }, [], { key: `${key}/audio` }));
        return el('Column', { style: { alignItems: 'stretch', margin: LEAF_MARGIN } }, parts, { key });
      }
      case 'Row':
      case 'Column':
        return this.flex(c, key, ctx);
      case 'List':
        return this.list(c, key, ctx);
      case 'Card':
        return el(
          'Card',
          { elevation: 1, style: { padding: 16, margin: LEAF_MARGIN, borderRadius: 12, backgroundColor: '#FFFFFF', borderColor: this.palette.outlineVariant, borderWidth: 1 } },
          typeof c.child === 'string' ? [this.child(c.child, { ...ctx, parent: 'Card', interceptPress: null })] : [],
          { key },
        );
      case 'Tabs':
        return this.tabs(c, key, ctx);
      case 'Modal':
        return this.modal(c, key, ctx);
      case 'Divider':
        return c.axis === 'vertical'
          ? el('Container', { style: { width: 1, minHeight: 24, margin: '0 8', backgroundColor: this.palette.outlineVariant } }, [], { key })
          : el('Divider', { style: { height: 17, borderColor: this.palette.outlineVariant } }, [], { key });
      case 'Button':
        return this.button(c, key, ctx);
      case 'TextField':
        return this.textField(c, key, ctx);
      case 'CheckBox':
        return this.checkBox(c, key, ctx);
      case 'ChoicePicker':
        return this.choicePicker(c, key, ctx);
      case 'Slider':
        return this.slider(c, key, ctx);
      case 'DateTimeInput':
        return this.dateTime(c, key, ctx);
      default:
        return this.placeholder(c.id, `Unknown component: ${c.component}`, key);
    }
  }

  // --------------------------------------------------------------------------
  // Display
  // --------------------------------------------------------------------------

  private textStyle(variant: string, ctx: Ctx): Node {
    const base = { ...(TEXT_VARIANTS[variant] ?? TEXT_VARIANTS.body) };
    if (variant === 'caption') base.color = this.palette.onSurfaceVariant;
    if (ctx.contentColor) base.color = ctx.contentColor;
    return base;
  }

  private text(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const value = this.str(ctx, c.text);
    const variant = typeof c.variant === 'string' && TEXT_VARIANTS[c.variant] ? c.variant : 'body';
    const margin = ctx.contentColor ? 0 : LEAF_MARGIN;
    const blocks = parseMarkdown(value);
    if (blocks.length === 0) return textNode('', { ...this.textStyle(variant, ctx), margin }, key);
    if (isPlainText(blocks)) return textNode(plainText(blocks), { ...this.textStyle(variant, ctx), margin }, key);
    const lowered = blocks.map((b, i) => this.markdownBlock(b, variant, ctx, `${key}/md${i}`));
    if (lowered.length === 1) {
      lowered[0].key = key;
      lowered[0].props.style.margin = margin;
      return lowered[0];
    }
    return el('Column', { style: { alignItems: 'flex-start', margin } }, lowered, { key });
  }

  private markdownBlock(block: MarkdownBlock, variant: string, ctx: Ctx, key: string): Node {
    let style = this.textStyle(variant, ctx);
    let prefix = '';
    if (block.type === 'heading' && variant === 'body') style = { ...this.textStyle(`h${Math.min(5, block.level)}`, ctx) };
    if (block.type === 'bullet') prefix = '•  ';
    if (block.type === 'ordered') prefix = `${block.number}.  `;
    const inlines: MarkdownInline[] = prefix ? [{ text: prefix }, ...block.inlines] : block.inlines;
    const spans = inlines.map((i) => this.inline(i));
    return el('p', { style: { ...style, margin: 0, padding: block.type === 'bullet' || block.type === 'ordered' ? '0 0 0 8' : 0 } }, spans, { key });
  }

  private inline(i: MarkdownInline): Node {
    const style: Node = {};
    if (i.bold) style.fontWeight = 700;
    if (i.italic) style.fontStyle = 'italic';
    if (i.strike) style.textDecoration = 'line-through';
    if (i.code) {
      style.fontFamily = 'monospace';
      style.backgroundColor = '#F1EDF4';
    }
    if (i.href && /^https?:\/\//i.test(i.href)) {
      return el('a', { href: i.href, target: '_blank', text: i.text, style: { ...style, color: this.palette.primary } });
    }
    return el('span', { text: i.text, style });
  }

  private image(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const src = this.str(ctx, c.url);
    const variant = typeof c.variant === 'string' ? c.variant : 'mediumFeature';
    const alt = this.accessibilityLabel(c, ctx) ?? this.str(ctx, c.description);
    const fitProp = typeof c.fit === 'string' ? c.fit : variant === 'icon' ? 'contain' : 'cover';
    const sizes: Record<string, Node> = {
      icon: { width: 24, height: 24 },
      avatar: { width: 40, height: 40 },
      smallFeature: { width: 100, height: 100 },
      mediumFeature: { height: 200, maxWidth: 300 },
      largeFeature: { height: 320 },
      header: { height: 200 },
    };
    const size = sizes[variant] ?? sizes.mediumFeature;
    const image = el('Image', { src, fit: fitProp, alt, style: { ...size } }, [], { key: `${key}/img` });
    const radius = variant === 'avatar' ? 20 : variant === 'icon' ? 0 : 8;
    return el('Container', { style: { margin: variant === 'header' ? 0 : LEAF_MARGIN } }, [radius ? el('ClipRRect', { style: { borderRadius: radius } }, [image]) : image], { key });
  }

  private icon(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const name = this.eval(ctx, () => ctx.dc.evaluate(c.name), undefined as unknown);
    const color = ctx.contentColor ?? this.palette.onSurfaceVariant;
    const margin = ctx.contentColor ? 0 : LEAF_MARGIN;
    if (name && typeof name === 'object' && typeof (name as any).svgPath === 'string') {
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="${color}" d="${String((name as any).svgPath).replace(/"/g, '')}"/></svg>`;
      return el('Image', { src: `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`, fit: 'contain', alt: this.accessibilityLabel(c, ctx) ?? '', style: { width: 24, height: 24, margin } }, [], { key });
    }
    return el('Icon', { icon: materialIconName(stringifyValue(name) || 'help'), size: 24, style: { color, margin } }, [], { key });
  }

  // --------------------------------------------------------------------------
  // Layout
  // --------------------------------------------------------------------------

  private flex(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const justify = typeof c.justify === 'string' ? c.justify : 'start';
    const align = typeof c.align === 'string' ? c.align : 'stretch';
    let children = this.children(c, ctx);
    if (justify === 'stretch') children = children.map((n) => (n.type === 'Expanded' || n.type === 'Flexible' ? n : el('Expanded', { flex: 1 }, [n])));
    return el(c.component, { style: { justifyContent: JUSTIFY[justify] ?? 'flex-start', alignItems: ALIGN[align] ?? 'stretch' } }, children, { key });
  }

  private list(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const horizontal = c.direction === 'horizontal';
    const align = typeof c.align === 'string' ? c.align : 'stretch';
    let children = this.children({ ...c, component: horizontal ? 'Row' : 'Column' } as A2UIComponent, ctx).map((n) =>
      n.type === 'Flexible' ? n.children[0] : n,
    );
    if (horizontal) children = children.map((n) => el('ConstrainedBox', { style: { maxWidth: 320 } }, [n]));
    const inner = el(horizontal ? 'Row' : 'Column', { style: { alignItems: ALIGN[align] ?? 'stretch' } }, children);
    return el('ListView', { scrollDirection: horizontal ? 'horizontal' : 'vertical' }, horizontal ? children : [inner], { key });
  }

  private tabs(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const tabs = Array.isArray(c.tabs) ? (c.tabs as any[]).filter((t) => t && typeof t === 'object') : [];
    const sk = this.stateKey(key, 'tab');
    const selected = Math.min(this.options.state.get(sk, 0), Math.max(0, tabs.length - 1));
    const p = this.palette;
    const headers = tabs.map((t, i) => {
      const active = i === selected;
      return el(
        'Container',
        { style: { padding: '12 16 0 16', cursor: 'pointer' } },
        [
          el('Column', { style: { alignItems: 'stretch' } }, [
            textNode(this.str(ctx, t.title), { fontSize: 14, fontWeight: 600, color: active ? p.primary : p.onSurfaceVariant, textAlign: 'center' }),
            el('Container', { style: { height: 3, margin: '10 0 0 0', backgroundColor: active ? p.primary : 'transparent', borderRadius: '3 3 0 0' } }),
          ]),
        ],
        {
          key: `${key}/tab${i}`,
          events: {
            click: (e: unknown) => {
              handled(e);
              this.options.state.set(sk, i);
              this.hooks.invalidate();
            },
          },
        },
      );
    });
    const childCtx: Ctx = { ...ctx, parent: 'Tabs', interceptPress: null };
    const bodies: Node[] = [];
    tabs.forEach((t, i) => {
      if (typeof t.child !== 'string') return;
      if (i === selected) bodies.push(this.child(t.child, childCtx));
      else if (this.options.expandAll) this.child(t.child, childCtx);
    });
    return el(
      'Column',
      { style: { alignItems: 'stretch' } },
      [el('Row', { style: { alignItems: 'flex-end', justifyContent: 'flex-start' } }, headers), el('Divider', { style: { height: 1, borderColor: p.outlineVariant } }), ...bodies],
      { key },
    );
  }

  private modal(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const sk = this.stateKey(key, 'open');
    const open = this.options.state.get(sk, false);
    const setOpen = (v: boolean) => {
      this.options.state.set(sk, v);
      this.hooks.invalidate();
    };
    let trigger: Node = el('SizedBox', { width: 0, height: 0 });
    if (typeof c.trigger === 'string') {
      const target = this.surface.components.get(c.trigger);
      trigger = this.child(c.trigger, { ...ctx, parent: 'Modal', interceptPress: () => setOpen(true) });
      if (target && target.component !== 'Button') {
        trigger = el('GestureDetector', {}, [trigger], {
          key: `${key}/trigger`,
          events: {
            click: (e: unknown) => {
              handled(e);
              setOpen(true);
            },
          },
        });
      }
    }
    if ((open || this.options.expandAll) && typeof c.content === 'string') {
      const content = this.child(c.content, { ...ctx, parent: 'Modal', interceptPress: null });
      if (open) this.overlays.push(this.dialog(key, content, () => setOpen(false)));
    }
    return el('Column', { style: { alignItems: 'flex-start' } }, [trigger], { key });
  }

  private dialog(key: string, content: Node, close: () => void): Node {
    const p = this.palette;
    const closeButton = el('Container', { style: { padding: 8, borderRadius: 20, cursor: 'pointer' } }, [el('Icon', { icon: 'close', size: 24, style: { color: p.onSurfaceVariant } })], {
      key: `${key}/close`,
      events: {
        click: (e: unknown) => {
          handled(e);
          close();
        },
      },
    });
    const panel = el(
      'Container',
      { style: { backgroundColor: p.surfaceContainerHigh, borderRadius: 28, padding: '8 16 24 24', maxWidth: 560, margin: 24, boxShadow: '0 8px 24px rgba(0,0,0,0.25)' } },
      [el('Column', { style: { alignItems: 'stretch' } }, [el('Row', { style: { justifyContent: 'flex-end' } }, [closeButton]), content])],
      {
        key: `${key}/dialog`,
        // Taps inside the dialog stay inside (the barrier closes on outside taps).
        events: { click: (e: unknown) => handled(e) },
      },
    );
    const barrier = el('Container', { style: { backgroundColor: 'rgba(0,0,0,0.4)' } }, [el('Center', {}, [panel])], {
      key: `${key}/barrier`,
      events: {
        click: (e: unknown) => {
          handled(e);
          close();
        },
      },
    });
    return el('Positioned', { style: { top: 0, left: 0, right: 0, bottom: 0 } }, [barrier]);
  }

  // --------------------------------------------------------------------------
  // Inputs
  // --------------------------------------------------------------------------

  private accessibilityLabel(c: A2UIComponent, ctx: Ctx): string | null {
    const a = c.accessibility as Record<string, unknown> | undefined;
    if (a && typeof a === 'object' && a.label !== undefined) {
      const s = this.str(ctx, a.label);
      if (s) return s;
    }
    return null;
  }

  /** Bind an input: the absolute path its value writes to, or a UI-state slot for literals. */
  private binding(value: unknown, ctx: Ctx, key: string): { read: (fallback: unknown) => unknown; write: (v: unknown) => void } {
    const path = isBinding(value) ? ctx.dc.resolvePath(value.path) : null;
    const local = this.stateKey(key, 'value');
    return {
      read: (fallback) => (path ? this.eval(ctx, () => ctx.dc.model.get(path), undefined) : this.options.state.get(local, fallback)),
      write: (v) => {
        if (path) this.hooks.write(this.surface.id, path, v);
        else {
          this.options.state.set(local, v);
          this.hooks.invalidate();
        }
      },
    };
  }

  private checks(c: A2UIComponent, ctx: Ctx): string[] {
    return evaluateChecks(c.checks, ctx.dc, this.report);
  }

  private label(text: string, color?: string): Node {
    return textNode(text, { fontSize: 12, fontWeight: 500, color: color ?? this.palette.onSurfaceVariant, margin: '0 0 2 0' });
  }

  private errorText(messages: string[]): Node[] {
    return messages.length ? [textNode(messages[0], { fontSize: 12, color: this.palette.error, margin: '4 0 0 0' })] : [];
  }

  private touched(key: string): boolean {
    return this.options.state.get(this.stateKey(key, 'touched'), false);
  }

  private touch(key: string): void {
    this.options.state.set(this.stateKey(key, 'touched'), true);
  }

  private button(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const variant = typeof c.variant === 'string' ? c.variant : 'default';
    const p = this.palette;
    const failures = this.checks(c, ctx);
    const press = ctx.interceptPress;
    const enabled = press != null || failures.length === 0;
    const contentColor = variant === 'primary' ? p.onPrimary : p.primary;
    const child = typeof c.child === 'string' ? this.child(c.child, { ...ctx, parent: 'Button', contentColor, interceptPress: null }) : textNode('');
    const childComponent = typeof c.child === 'string' ? this.surface.components.get(c.child) : undefined;
    const label = this.accessibilityLabel(c, ctx) ?? (childComponent?.component === 'Text' ? plainText(parseMarkdown(this.str(ctx, childComponent.text))) : '') ?? '';
    const style: Node =
      variant === 'primary'
        ? { backgroundColor: p.primary, color: p.onPrimary, margin: LEAF_MARGIN }
        : variant === 'borderless'
          ? { backgroundColor: 'transparent', color: p.primary, boxShadow: '0 0 0 0 rgba(0,0,0,0)', padding: '0 12', margin: LEAF_MARGIN }
          : { backgroundColor: p.surfaceContainer, color: p.primary, border: `1px solid ${p.outlineVariant}`, margin: LEAF_MARGIN };
    const events = enabled
      ? {
          click: (e: unknown) => {
            handled(e);
            if (press) press();
            else this.hooks.action(this.surface.id, c.id, c.action, ctx.scope);
          },
        }
      : undefined;
    return el('Button', { text: label || 'Button', disabled: !enabled, style }, [child], { key, events });
  }

  private textField(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const variant = typeof c.variant === 'string' ? c.variant : 'shortText';
    const label = this.str(ctx, c.label);
    const bind = this.binding(c.value, ctx, key);
    const raw = bind.read(isBinding(c.value) ? undefined : this.str(ctx, c.value));
    const value = stringifyValue(raw);
    let failures = this.checks(c, ctx);
    if (typeof c.validationRegexp === 'string' && value !== '') {
      let ok = true;
      try {
        ok = new RegExp(c.validationRegexp).test(value);
      } catch {
        ok = true;
      }
      if (!ok) failures = [...failures, 'Invalid format'];
    }
    const showErrors = failures.length > 0 && (this.touched(key) || value !== '');
    const p = this.palette;
    const field = el(
      'TextField',
      {
        value,
        hint: this.accessibilityLabel(c, ctx) && !label ? this.accessibilityLabel(c, ctx) : '',
        obscureText: variant === 'obscured',
        multiline: variant === 'longText',
        maxLines: variant === 'longText' ? 4 : 1,
        keyboardType: variant === 'number' ? 'number' : 'text',
        style: { color: p.onSurface },
      },
      [],
      {
        key: `${key}/input`,
        events: {
          input: (e: any) => {
            handled(e);
            this.touch(key);
            bind.write(String(e?.value ?? ''));
          },
        },
      },
    );
    return el('Column', { style: { alignItems: 'stretch', margin: LEAF_MARGIN } }, [...(label ? [this.label(label, showErrors ? p.error : undefined)] : []), field, ...this.errorText(showErrors ? failures : [])], { key });
  }

  private checkBox(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const bind = this.binding(c.value, ctx, key);
    const checked = isBinding(c.value) ? bind.read(false) === true : bind.read(this.eval(ctx, () => ctx.dc.boolean(c.value), false)) === true;
    const toggle = (v: boolean) => {
      this.touch(key);
      bind.write(v);
    };
    const failures = this.checks(c, ctx);
    const showErrors = failures.length > 0 && this.touched(key);
    const box = el('Checkbox', { value: checked, style: { color: this.palette.primary } }, [], {
      key: `${key}/box`,
      events: {
        change: (e: any) => {
          handled(e);
          toggle(!!e?.value);
        },
      },
    });
    const label = el('Container', { style: { cursor: 'pointer', padding: '0 4' } }, [textNode(this.str(ctx, c.label), { fontSize: 16 })], {
      key: `${key}/label`,
      events: {
        click: (e: unknown) => {
          handled(e);
          toggle(!checked);
        },
      },
    });
    const row = el('Row', { style: { alignItems: 'center' } }, [box, el('Flexible', { flex: 1, fit: 'loose' }, [label])]);
    return el('Column', { style: { alignItems: 'stretch', margin: LEAF_MARGIN } }, [row, ...this.errorText(showErrors ? failures : [])], { key });
  }

  private choicePicker(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const p = this.palette;
    const multiple = c.variant === 'multipleSelection';
    const chips = c.displayStyle === 'chips';
    const bind = this.binding(c.value, ctx, key);
    const current = bind.read(isBinding(c.value) ? undefined : this.eval(ctx, () => ctx.dc.stringList(c.value), []));
    const selected = Array.isArray(current) ? current.map((x) => stringifyValue(x)) : typeof current === 'string' && current ? [current] : [];
    const options = (Array.isArray(c.options) ? (c.options as any[]) : [])
      .filter((o) => o && typeof o === 'object' && typeof o.value === 'string')
      .map((o) => ({ value: o.value as string, label: this.str(ctx, o.label) || (o.value as string) }));
    const filterKey = this.stateKey(key, 'filter');
    const filter = c.filterable === true ? this.options.state.get<string>(filterKey, '') : ('' as string);
    const visible = filter ? options.filter((o) => o.label.toLowerCase().includes(filter.toLowerCase())) : options;
    const choose = (value: string) => {
      this.touch(key);
      if (multiple) bind.write(selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value]);
      else bind.write([value]);
    };
    const parts: Node[] = [];
    const label = this.str(ctx, c.label);
    if (label) parts.push(this.label(label));
    if (c.filterable === true) {
      parts.push(
        el('TextField', { value: filter, hint: 'Filter options', style: { color: p.onSurface } }, [], {
          key: `${key}/filter`,
          events: {
            input: (e: any) => {
              handled(e);
              this.options.state.set(filterKey, String(e?.value ?? ''));
              this.hooks.invalidate();
            },
          },
        }),
      );
    }
    if (chips) {
      const items = visible.map((o) => {
        const on = selected.includes(o.value);
        const content: Node[] = [];
        if (on) content.push(el('Icon', { icon: 'check', size: 18, style: { color: p.primary, margin: '0 6 0 0' } }));
        content.push(textNode(o.label, { fontSize: 14, fontWeight: 500, color: on ? p.onSurface : p.onSurfaceVariant }));
        return el(
          'Container',
          { style: { padding: '6 14', margin: 4, borderRadius: 8, border: `1px solid ${on ? p.primary : p.outline}`, backgroundColor: on ? p.primaryContainer : 'transparent', cursor: 'pointer' } },
          [el('Row', { style: { alignItems: 'center' } }, content)],
          {
            key: `${key}/opt/${o.value}`,
            events: {
              click: (e: unknown) => {
                handled(e);
                choose(o.value);
              },
            },
          },
        );
      });
      parts.push(el('Wrap', { style: { gap: 0 } }, items));
    } else {
      for (const o of visible) {
        const on = selected.includes(o.value);
        const control = multiple
          ? el('Checkbox', { value: on, style: { color: p.primary } }, [], {
              key: `${key}/opt/${o.value}`,
              events: {
                change: (e: unknown) => {
                  handled(e);
                  choose(o.value);
                },
              },
            })
          : el('Radio', { value: o.value, groupValue: selected[0] ?? null, style: { color: p.primary } }, [], {
              key: `${key}/opt/${o.value}`,
              events: {
                change: (e: unknown) => {
                  handled(e);
                  choose(o.value);
                },
              },
            });
        const text = el('Container', { style: { cursor: 'pointer', padding: '0 4' } }, [textNode(o.label, { fontSize: 16 })], {
          key: `${key}/optlabel/${o.value}`,
          events: {
            click: (e: unknown) => {
              handled(e);
              choose(o.value);
            },
          },
        });
        parts.push(el('Row', { style: { alignItems: 'center' } }, [control, el('Flexible', { flex: 1, fit: 'loose' }, [text])]));
      }
    }
    const failures = this.checks(c, ctx);
    parts.push(...this.errorText(failures.length && this.touched(key) ? failures : []));
    return el('Column', { style: { alignItems: 'stretch', margin: LEAF_MARGIN } }, parts, { key });
  }

  private slider(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const p = this.palette;
    const min = typeof c.min === 'number' ? c.min : 0;
    const max = typeof c.max === 'number' && c.max > min ? c.max : min + 100;
    const bind = this.binding(c.value, ctx, key);
    const raw = bind.read(isBinding(c.value) ? undefined : this.eval(ctx, () => ctx.dc.number(c.value), min));
    const n = typeof raw === 'number' ? raw : typeof raw === 'string' && raw.trim() !== '' && Number.isFinite(Number(raw)) ? Number(raw) : min;
    const value = Math.max(min, Math.min(max, n));
    const label = this.str(ctx, c.label);
    const shown = Number.isInteger(value) ? String(value) : value.toFixed(Math.abs(max - min) <= 1 ? 2 : 1);
    const header = el('Row', { style: { alignItems: 'center', justifyContent: 'space-between' } }, [
      el('Flexible', { flex: 1, fit: 'loose' }, [textNode(label, { fontSize: 14, color: p.onSurfaceVariant })]),
      textNode(shown, { fontSize: 14, fontWeight: 600, color: p.onSurface }),
    ]);
    const slider = el('Slider', { min, max, value, style: { color: p.primary } }, [], {
      key: `${key}/slider`,
      events: {
        change: (e: any) => {
          handled(e);
          const v = Number(e?.value);
          if (Number.isFinite(v)) bind.write(v);
        },
      },
    });
    const failures = this.checks(c, ctx);
    return el('Column', { style: { alignItems: 'stretch', margin: LEAF_MARGIN } }, [header, slider, ...this.errorText(failures)], { key });
  }

  private dateTime(c: A2UIComponent, key: string, ctx: Ctx): Node {
    const p = this.palette;
    const enableDate = c.enableDate === true;
    const enableTime = c.enableTime === true;
    const mode: 'date' | 'time' | 'datetime-local' = enableDate && enableTime ? 'datetime-local' : enableTime ? 'time' : enableDate ? 'date' : 'datetime-local';
    const bind = this.binding(c.value, ctx, key);
    const iso = stringifyValue(bind.read(isBinding(c.value) ? undefined : this.str(ctx, c.value)));
    const label = this.str(ctx, c.label);
    const field = el(
      'TextField',
      {
        value: isoToInput(iso, mode),
        keyboardType: mode,
        min: c.min !== undefined ? isoToInput(this.str(ctx, c.min), mode) || null : null,
        max: c.max !== undefined ? isoToInput(this.str(ctx, c.max), mode) || null : null,
        style: { color: p.onSurface },
      },
      [],
      {
        key: `${key}/input`,
        events: {
          input: (e: any) => {
            handled(e);
            this.touch(key);
            bind.write(inputToIso(String(e?.value ?? ''), mode));
          },
        },
      },
    );
    const failures = this.checks(c, ctx);
    return el('Column', { style: { alignItems: 'stretch', margin: LEAF_MARGIN } }, [...(label ? [this.label(label)] : []), field, ...this.errorText(failures.length && this.touched(key) ? failures : [])], { key });
  }
}

const pad2 = (n: number) => String(n).padStart(2, '0');

/** ISO 8601 (model) → the value a native date / time / datetime-local input shows. */
export function isoToInput(iso: string, mode: 'date' | 'time' | 'datetime-local'): string {
  if (!iso) return '';
  const s = iso.trim();
  const time = /^(\d{2}):(\d{2})/.exec(s);
  if (mode === 'time' && time) return `${time[1]}:${time[2]}`;
  const dateOnly = /^(\d{4}-\d{2}-\d{2})$/.exec(s);
  if (dateOnly) return mode === 'time' ? '' : mode === 'date' ? dateOnly[1] : `${dateOnly[1]}T00:00`;
  const local = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$/.exec(s);
  let d: Date | null = null;
  if (local) {
    if (mode === 'date') return local[1];
    if (mode === 'time') return `${local[2]}:${local[3]}`;
    return `${local[1]}T${local[2]}:${local[3]}`;
  }
  const parsed = new Date(s);
  if (!Number.isNaN(parsed.getTime())) d = parsed;
  if (!d) return '';
  const date = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  const t = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  return mode === 'date' ? date : mode === 'time' ? t : `${date}T${t}`;
}

/** A native input's value → ISO 8601 for the data model. */
export function inputToIso(value: string, mode: 'date' | 'time' | 'datetime-local'): string {
  const v = value.trim();
  if (!v) return '';
  if (mode === 'time') return /^\d{2}:\d{2}$/.test(v) ? `${v}:00` : v;
  if (mode === 'datetime-local') return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(v) ? `${v}:00` : v;
  return v;
}
