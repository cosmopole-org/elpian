/**
 * The reconciler keeps render objects alive across renders — a port of
 * Flutter's `Element.updateChildren`: children are matched by type + key,
 * first from the top, then from the bottom, then through the keyed middle.
 * A matched object receives the new configuration (keeping its animation
 * controllers, scroll offset, input text…); unmatched ones are detached.
 */
import { deepEqual } from '../util/json.js';
import {
  RenderAnimatedConstrained,
  RenderAnimatedCrossFade,
  RenderAnimatedDecorated,
  RenderAnimatedDefaultTextStyle,
  RenderAnimatedAlign,
  RenderAnimatedGradient,
  RenderAnimatedOpacity,
  RenderAnimatedPadding,
  RenderAnimatedPositioned,
  RenderAnimatedSize,
  RenderAnimatedSwitcher,
  RenderAnimatedTransform,
  RenderHero,
  RenderKeyframes,
  RenderShimmer,
  RenderStaggerItem,
  RenderStaggered,
  RenderSwitcherSlot,
  RenderTransition,
} from './animated.js';
import {
  RenderAlign,
  RenderAspectRatio,
  RenderBaseline,
  RenderConstrainedBox,
  RenderFittedBox,
  RenderFittedContent,
  RenderFractional,
  RenderIndexedStack,
  RenderIntrinsicHeight,
  RenderIntrinsicWidth,
  RenderLimitedBox,
  RenderOffstage,
  RenderOverflowBox,
  RenderPadding,
  RenderRotatedBox,
  RenderSafeArea,
  RenderFillAxis,
} from './layout/basic.js';
import { RenderFlex, RenderFlexible } from './layout/flex.js';
import { RenderGrid, RenderGridItem } from './layout/grid.js';
import { RenderImageMap } from './layout/imagemap.js';
import { RenderScroll } from './layout/scroll.js';
import { RenderPositioned, RenderStack } from './layout/stack.js';
import { RenderTable, RenderTableCell, RenderTableRow } from './layout/table.js';
import { RenderWrap } from './layout/wrap.js';
import { RenderObject, RenderProxy, type W } from './object.js';
import type { RenderOwner } from './owner.js';
import {
  RenderClip,
  RenderDecoratedBox,
  RenderDefaultTextStyle,
  RenderFilter,
  RenderIgnorePointer,
  RenderOpacity,
  RenderShaderMask,
  RenderTransform,
  RenderVisibility,
} from './paint/box.js';
import { RenderCanvas, RenderControl, RenderGesture, RenderImage, RenderMedia, RenderScene3D, RenderWeb } from './paint/leaves.js';
import { RenderText } from './paint/text.js';

type Factory = () => RenderObject;

const factories: Record<string, Factory> = {
  proxy: () => new RenderProxy(),
  padding: () => new RenderPadding(),
  safeArea: () => new RenderSafeArea(),
  fill: () => new RenderFillAxis(),
  constrained: () => new RenderConstrainedBox(),
  align: () => new RenderAlign(),
  aspectRatio: () => new RenderAspectRatio(),
  fractional: () => new RenderFractional(),
  limited: () => new RenderLimitedBox(),
  overflowBox: () => new RenderOverflowBox(),
  fitted: () => new RenderFittedBox(),
  fittedContent: () => new RenderFittedContent(),
  baseline: () => new RenderBaseline(),
  rotatedBox: () => new RenderRotatedBox(),
  intrinsicWidth: () => new RenderIntrinsicWidth(),
  intrinsicHeight: () => new RenderIntrinsicHeight(),
  offstage: () => new RenderOffstage(),
  indexedStack: () => new RenderIndexedStack(),
  flex: () => new RenderFlex(),
  flexible: () => new RenderFlexible(),
  wrap: () => new RenderWrap(),
  stack: () => new RenderStack(),
  positioned: () => new RenderPositioned(),
  grid: () => new RenderGrid(),
  imageMap: () => new RenderImageMap(),
  gridItem: () => new RenderGridItem(),
  scroll: () => new RenderScroll(),
  table: () => new RenderTable(),
  tableRow: () => new RenderTableRow(),
  tableCell: () => new RenderTableCell(),
  decorated: () => new RenderDecoratedBox(),
  opacity: () => new RenderOpacity(),
  transform: () => new RenderTransform(),
  clip: () => new RenderClip(),
  ignorePointer: () => new RenderIgnorePointer(),
  visibility: () => new RenderVisibility(),
  filter: () => new RenderFilter(),
  shaderMask: () => new RenderShaderMask(),
  defaultTextStyle: () => new RenderDefaultTextStyle(),
  text: () => new RenderText(),
  image: () => new RenderImage(),
  control: () => new RenderControl(),
  canvas: () => new RenderCanvas(),
  scene3d: () => new RenderScene3D(),
  media: () => new RenderMedia(),
  web: () => new RenderWeb(),
  gesture: () => new RenderGesture(),
  // animated
  animatedPadding: () => new RenderAnimatedPadding(),
  animatedAlign: () => new RenderAnimatedAlign(),
  animatedOpacity: () => new RenderAnimatedOpacity(),
  animatedTransform: () => new RenderAnimatedTransform(),
  animatedConstrained: () => new RenderAnimatedConstrained(),
  animatedDecorated: () => new RenderAnimatedDecorated(),
  animatedPositioned: () => new RenderAnimatedPositioned(),
  animatedDefaultTextStyle: () => new RenderAnimatedDefaultTextStyle(),
  animatedSize: () => new RenderAnimatedSize(),
  animatedCrossFade: () => new RenderAnimatedCrossFade(),
  animatedSwitcher: () => new RenderAnimatedSwitcher(),
  switcherSlot: () => new RenderSwitcherSlot(),
  transition: () => new RenderTransition(),
  staggered: () => new RenderStaggered(),
  staggerItem: () => new RenderStaggerItem(),
  shimmer: () => new RenderShimmer(),
  animatedGradient: () => new RenderAnimatedGradient(),
  keyframes: () => new RenderKeyframes(),
  hero: () => new RenderHero(),
};

/** Register an additional render-object type (host extensions, islands). */
export function registerRenderObject(type: string, factory: Factory): void {
  factories[type] = factory;
}

function canUpdate(ro: RenderObject, w: W): boolean {
  return ro.type === w.t && ro.key === (w.k ?? null);
}

/** Compare props ignoring function identity (closures are rebuilt every render). */
export function propsEqual(a: Record<string, any>, b: Record<string, any>): boolean {
  const ka = Object.keys(a).filter((k) => typeof a[k] !== 'function');
  const kb = Object.keys(b).filter((k) => typeof b[k] !== 'function');
  if (ka.length !== kb.length) return false;
  for (const k of ka) if (!deepEqual(a[k], b[k])) return false;
  return true;
}

export function createRenderObject(w: W, owner: RenderOwner, parent: RenderObject | null): RenderObject {
  const factory = factories[w.t];
  if (!factory) throw new Error(`Elpian: unknown render object type "${w.t}"`);
  const ro = factory();
  ro.type = w.t;
  ro.key = w.k ?? null;
  ro.parent = parent;
  ro.init(w.p);
  ro.attach(owner);
  reconcileChildren(ro, w.c ?? [], owner);
  return ro;
}

export function updateRenderObject(ro: RenderObject, w: W, owner: RenderOwner): RenderObject {
  if (propsEqual(ro.props, w.p)) {
    // Same configuration: refresh closures only, no relayout.
    for (const [k, v] of Object.entries(w.p)) if (typeof v === 'function') ro.props[k] = v;
  } else {
    ro.update(w.p);
  }
  reconcileChildren(ro, w.c ?? [], owner);
  return ro;
}

/** Reconcile [root] against [w]; returns the (possibly new) root object. */
export function reconcileRoot(root: RenderObject | null, w: W, owner: RenderOwner): RenderObject {
  if (root && canUpdate(root, w)) return updateRenderObject(root, w, owner);
  root?.detach();
  return createRenderObject(w, owner, null);
}

function detachChild(ro: RenderObject): void {
  ro.detach();
  ro.parent = null;
}

export function reconcileChildren(parent: RenderObject, ws: W[], owner: RenderOwner): void {
  if (parent instanceof RenderAnimatedSwitcher) {
    reconcileSwitcher(parent, ws, owner);
    return;
  }
  const old = parent.children;
  if (old.length === 0 && ws.length === 0) return;
  const result: RenderObject[] = new Array(ws.length);
  let oldTop = 0;
  let newTop = 0;
  let oldBottom = old.length - 1;
  let newBottom = ws.length - 1;

  while (oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldTop], ws[newTop])) {
    result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner);
    oldTop++;
    newTop++;
  }
  while (oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldBottom], ws[newBottom])) {
    oldBottom--;
    newBottom--;
  }
  const keyed = new Map<string, RenderObject>();
  for (let i = oldTop; i <= oldBottom; i++) {
    const o = old[i];
    if (o.key != null) keyed.set(o.type + '\u0000' + o.key, o);
    else detachChild(o);
  }
  while (newTop <= newBottom) {
    const w = ws[newTop];
    let match: RenderObject | undefined;
    if (w.k != null) {
      const id = w.t + '\u0000' + w.k;
      match = keyed.get(id);
      if (match) keyed.delete(id);
    }
    result[newTop] = match ? updateRenderObject(match, w, owner) : createRenderObject(w, owner, parent);
    newTop++;
  }
  newBottom = ws.length - 1;
  oldBottom = old.length - 1;
  while (oldTop <= oldBottom && newTop <= newBottom) {
    result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner);
    oldTop++;
    newTop++;
  }
  for (const o of keyed.values()) detachChild(o);

  let changed = result.length !== old.length;
  for (let i = 0; i < result.length && !changed; i++) if (result[i] !== old[i]) changed = true;
  for (const r of result) r.parent = parent;
  parent.children = result;
  if (changed) parent.markNeedsLayout();
}

function reconcileSwitcher(parent: RenderAnimatedSwitcher, ws: W[], owner: RenderOwner): void {
  const current = parent.children.filter((c) => !parent.outgoing.has(c));
  const active = current[current.length - 1] ?? null;
  for (const extra of current.slice(0, -1)) {
    detachChild(extra);
    parent.children = parent.children.filter((c) => c !== extra);
  }
  if (ws.length === 0) {
    if (active) parent.childRemoved(active);
    parent.markNeedsLayout();
    return;
  }
  const w = ws[ws.length - 1];
  if (active && canUpdate(active, w)) {
    updateRenderObject(active, w, owner);
    return;
  }
  const fresh = createRenderObject(w, owner, parent);
  parent.children = [...parent.children.filter((c) => parent.outgoing.has(c)), fresh];
  if (active && parent.isMounted) parent.childReplaced(active, fresh);
  else if (active) detachChild(active);
  parent.markNeedsLayout();
}
