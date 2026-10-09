/**
 * Scoped re-rendering — ports of flutter/lib/src/scope/{scope_contract,
 * scope_patch,scoped_components}.dart. `render(view, scopeKey)` replaces only
 * the subtree keyed [scopeKey] in the current tree; `Scope` nodes above it get
 * a fresh render token so they rebuild while untouched siblings keep their
 * state.
 */
import { isMap, type JsonMap } from '../util/json.js';

export const ScopeContract = {
  type: 'Scope',
  renderTokenProp: '__scopeRenderToken',
  wrapperKeySuffix: '__scope',
  isScopeNode(node: unknown): boolean {
    return isMap(node) && String(node.type) === 'Scope';
  },
} as const;

let tokenCounter = 0;

export const ScopePatch = {
  normalizeKey(scopeKey: string | null | undefined): string | null {
    if (scopeKey == null) return null;
    const k = String(scopeKey).trim();
    return k === '' || k === 'null' ? null : k;
  },

  ensureKey(json: JsonMap, key: string): JsonMap {
    if (json.key != null && String(json.key) !== '') return json;
    return { ...json, key };
  },

  markRerender(json: JsonMap): JsonMap {
    markTokensInPlace(json);
    return json;
  },

  replaceByKey(tree: JsonMap, targetKey: string, replacement: JsonMap): boolean {
    return replace(tree, targetKey, replacement, []);
  },

  /** Patch [tree]; falls back to the whole [view] when the key is absent. */
  apply(tree: JsonMap | null, view: JsonMap, scopeKey: string | null): JsonMap {
    const key = ScopePatch.normalizeKey(scopeKey);
    if (key == null || tree == null) return ScopePatch.markRerender(view);
    const replacement = ScopePatch.markRerender(ScopePatch.ensureKey(view, key));
    return ScopePatch.replaceByKey(tree, key, replacement) ? tree : view;
  },

  /** Like [apply], but returns null (drop) when the key is absent. */
  applyBounded(tree: JsonMap | null, view: JsonMap, scopeKey: string | null): JsonMap | null {
    const key = ScopePatch.normalizeKey(scopeKey);
    if (key == null || tree == null) return ScopePatch.markRerender(view);
    const replacement = ScopePatch.markRerender(ScopePatch.ensureKey(view, key));
    return ScopePatch.replaceByKey(tree, key, replacement) ? tree : null;
  },
};

function replace(node: JsonMap, targetKey: string, replacement: JsonMap, scopeAncestors: JsonMap[]): boolean {
  if (node.key != null && String(node.key) === targetKey) {
    for (const k of Object.keys(node)) delete node[k];
    Object.assign(node, replacement);
    markNodes(scopeAncestors);
    return true;
  }
  const isScope = ScopeContract.isScopeNode(node);
  if (isScope) scopeAncestors.push(node);
  const children = node.children;
  if (Array.isArray(children)) {
    for (const child of children) {
      if (!isMap(child)) continue;
      if (replace(child, targetKey, replacement, scopeAncestors)) {
        if (isScope) scopeAncestors.pop();
        return true;
      }
    }
  }
  if (isScope) scopeAncestors.pop();
  return false;
}

function markNodes(scopeNodes: JsonMap[]): void {
  for (const n of scopeNodes) n.props = { ...(isMap(n.props) ? n.props : {}), [ScopeContract.renderTokenProp]: ++tokenCounter };
}

function markTokensInPlace(node: unknown): void {
  if (!isMap(node)) return;
  if (ScopeContract.isScopeNode(node)) node.props = { ...(isMap(node.props) ? node.props : {}), [ScopeContract.renderTokenProp]: ++tokenCounter };
  if (Array.isArray(node.children)) for (const c of node.children) markTokensInPlace(c);
}

/** Wrap each child of [root] in its own `Scope` so it can re-render alone. */
export function isolateComponentChildren(root: JsonMap, namespace: string): JsonMap {
  if (!Array.isArray(root.children)) return root;
  root.children = root.children.map((c: unknown, i: number) => isolateChild(c, namespace, i));
  return root;
}

export function scopedComponent(key: string, component: JsonMap): JsonMap {
  const target = { ...component };
  target.key = target.key != null && String(target.key) !== '' ? target.key : key;
  return { type: ScopeContract.type, key: `${key}${ScopeContract.wrapperKeySuffix}`, props: {}, children: [target] };
}

function isolateChild(child: unknown, namespace: string, index: number): unknown {
  if (!isMap(child)) return child;
  const component = { ...child };
  if (component.type === ScopeContract.type) return component;
  const explicit = component.key != null ? String(component.key) : '';
  return scopedComponent(explicit !== '' ? explicit : `${namespace}-component-${index}`, component);
}
