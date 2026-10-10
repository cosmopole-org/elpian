/**
 * The default widget set — the same type names `ElpianEngine._registerDefaultWidgets`
 * registers in Flutter (Flutter DSL widgets, Scene3D, animation widgets, HTML
 * elements) plus the Next.js navigation widgets that `NextjsBridge` adds, and
 * the A2UI surface widget (`A2UISurface` / `a2ui-surface`).
 */
import type { ElpianEngine } from '../engine/engine.js';
import { a2uiWidgets } from '../a2ui/elpian.js';
import { animationWidgets } from './animation.js';
import { flutterWidgets } from './flutter.js';
import { htmlWidgets } from './html.js';
import { nextjsWidgets } from './nextjs.js';

export function registerDefaultWidgets(engine: ElpianEngine): void {
  engine.registerWidgets(flutterWidgets);
  engine.registerWidgets(animationWidgets);
  engine.registerWidgets(htmlWidgets);
  engine.registerWidgets(nextjsWidgets);
  engine.registerWidgets(a2uiWidgets);
}
