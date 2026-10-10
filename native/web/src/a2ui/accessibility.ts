/**
 * The accessibility semantics of an A2UI surface: per component its role,
 * label, description and state, from the component's `accessibility`
 * attributes or inferred from its visible content (a button's child text, an
 * input's label, an image's description). Engines apply these to their
 * native semantics (the web lowering sets button labels and image alt text);
 * the conformance `accessibility_check` cases read this tree directly.
 */
import { isBinding } from './context.js';
import { plainText, parseMarkdown } from './markdown.js';
import type { A2UIComponent, A2UISurfaceModel } from './processor.js';

export interface A2UIAccessibilityNode {
  id: string;
  role: string;
  label?: string;
  description?: string;
  checked?: boolean;
  live?: string;
  hidden?: boolean;
  /** For bound attributes: the data path each one reads (`label`, `description`, `hidden`, `live`). */
  bindings?: Record<string, string>;
}

const ROLES: Record<string, string> = {
  Text: 'text',
  Image: 'img',
  Icon: 'img',
  Video: 'video',
  AudioPlayer: 'audio',
  Row: 'group',
  Column: 'group',
  List: 'list',
  Card: 'group',
  Tabs: 'tablist',
  Modal: 'dialog',
  Divider: 'separator',
  Button: 'button',
  TextField: 'textbox',
  CheckBox: 'checkbox',
  Slider: 'slider',
  DateTimeInput: 'textbox',
};

export function accessibilityRole(c: A2UIComponent): string {
  if (c.component === 'ChoicePicker') return c.variant === 'multipleSelection' ? 'group' : 'radiogroup';
  return ROLES[c.component] ?? 'generic';
}

/** Semantics for one component (in the surface's root data scope). */
export function describeAccessibility(surface: A2UISurfaceModel, c: A2UIComponent, scope = '/'): A2UIAccessibilityNode {
  const ctx = surface.context(scope);
  const text = (v: unknown) => ctx.safe(() => plainText(parseMarkdown(ctx.string(v))), '');
  const node: A2UIAccessibilityNode = { id: c.id, role: accessibilityRole(c) };
  const bindings: Record<string, string> = {};
  const a = c.accessibility && typeof c.accessibility === 'object' ? (c.accessibility as Record<string, unknown>) : {};
  for (const attr of ['label', 'description', 'live', 'hidden']) {
    const v = a[attr];
    if (v === undefined) continue;
    if (isBinding(v)) bindings[attr] = ctx.resolvePath(v.path);
    const value = ctx.safe(() => ctx.evaluate(v), undefined);
    if (attr === 'hidden') {
      if (value !== undefined) node.hidden = value === true;
    } else if (value !== undefined && value !== null && value !== '') {
      (node as any)[attr] = String(value);
    }
  }
  if (node.label === undefined && bindings.label === undefined) {
    let inferred = '';
    if (c.component === 'Button') {
      const child = typeof c.child === 'string' ? surface.components.get(c.child) : undefined;
      if (child?.component === 'Text') inferred = text(child.text);
      else if (typeof (c as any).title === 'string') inferred = (c as any).title;
    } else if (['TextField', 'CheckBox', 'ChoicePicker', 'Slider', 'DateTimeInput'].includes(c.component)) inferred = text(c.label);
    else if (c.component === 'Image') inferred = text(c.description);
    else if (c.component === 'Text') inferred = text(c.text);
    if (inferred) node.label = inferred;
  }
  if (c.component === 'CheckBox') node.checked = ctx.safe(() => ctx.boolean(c.value), false);
  if (Object.keys(bindings).length) node.bindings = bindings;
  return node;
}

/** Semantics of every component of [surface], by component id. */
export function accessibilityTree(surface: A2UISurfaceModel): Record<string, A2UIAccessibilityNode> {
  const out: Record<string, A2UIAccessibilityNode> = {};
  for (const c of surface.components.values()) out[c.id] = describeAccessibility(surface, c);
  return out;
}
