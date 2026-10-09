/**
 * The context a widget builder receives while lowering one Elpian node.
 */
import type { ElementFacts } from '../css/stylesheet.js';
import type { ElpianNode } from '../model/node.js';
import type { W } from '../render/object.js';
import type { ElpianEngine } from '../engine/engine.js';

export interface BuildContext {
  engine: ElpianEngine;
  /** Event-dispatch id of the nearest ancestor element (for bubbling). */
  parentId: string | null;
  /** Ancestors nearest-first, for descendant/child CSS selectors. */
  ancestors: ElementFacts[];
  /** Stable structural path of this node (used to derive element ids). */
  path: string;
  /** The element id this node dispatches events as. */
  elementId: string;
  /** Enclosing `form` element id, for submit collection. */
  formId: string | null;
}

/** A widget builder: Elpian node + lowered children → widget descriptor. */
export type WidgetBuilder = (node: ElpianNode, children: W[], ctx: BuildContext) => W;
