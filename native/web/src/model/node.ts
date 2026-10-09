/**
 * `ElpianNode` — one element of a mini app's view tree, as the guest sends it:
 *
 * ```json
 * { "type": "div", "key": "card", "props": { "className": "x", "style": {…} },
 *   "events": { "click": "onCardClick" }, "children": [ … ] }
 * ```
 *
 * A top-level `style` is folded into `props.style`, as in Flutter's
 * `ElpianNode.fromJson`. [style] holds the resolved cascade once the engine
 * has computed it.
 */
import type { CSSStyle } from '../css/style.js';
import { isMap, type JsonMap } from '../util/json.js';

export interface ElpianNode {
  type: string;
  props: JsonMap;
  children: ElpianNode[];
  key: string | null;
  events: Record<string, any> | null;
  style: CSSStyle | null;
}

export function nodeFromJson(json: JsonMap): ElpianNode {
  const props: JsonMap = isMap(json.props) ? { ...json.props } : {};
  if (json.style != null && props.style == null) props.style = json.style;
  // Elpian JSON sometimes carries `className`/`text` at the top level.
  for (const k of ['className', 'class', 'text', 'id']) {
    if (json[k] != null && props[k] == null) props[k] = json[k];
  }
  if (props.class != null && props.className == null) props.className = props.class;
  const rawChildren = Array.isArray(json.children) ? json.children : [];
  const children: ElpianNode[] = [];
  for (const child of rawChildren) {
    if (isMap(child)) children.push(nodeFromJson(child));
    else if (typeof child === 'string' || typeof child === 'number') {
      // Bare text children: an implicit text node.
      children.push({ type: '#text', props: { text: String(child) }, children: [], key: null, events: null, style: null });
    }
  }
  return {
    type: String(json.type ?? 'div'),
    props,
    children,
    key: json.key != null ? String(json.key) : null,
    events: isMap(json.events) ? json.events : null,
    style: null,
  };
}

export function nodeToJson(node: ElpianNode): JsonMap {
  return {
    type: node.type,
    props: node.props,
    children: node.children.map(nodeToJson),
    ...(node.key != null ? { key: node.key } : {}),
    ...(node.events != null ? { events: node.events } : {}),
  };
}

export function copyNode(node: ElpianNode, patch: Partial<ElpianNode>): ElpianNode {
  return { ...node, ...patch };
}

/** The classes of a node (`className` as a string or a list). */
export function classesOf(node: ElpianNode): string[] | null {
  const cn = node.props.className;
  if (typeof cn === 'string') return cn.split(/\s+/).filter((c) => c !== '');
  if (Array.isArray(cn)) return cn.map((c) => String(c));
  return null;
}

/** The text a node carries (`props.text` / `props.data`). */
export function textOf(node: ElpianNode): string {
  const t = node.props.text ?? node.props.data;
  return t == null ? '' : String(t);
}
