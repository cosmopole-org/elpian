/**
 * The live environment CSS values resolve against: the viewport (for `%`,
 * `vw`, `vh`, `vmin`, `vmax`, `calc()`), the safe-area insets (for `env()`)
 * and the root font size (for `rem`).
 *
 * Mirrors `CSSParser.viewportOverride` / `_safeAreaInsets` in Flutter. Each
 * session sets it before resolving styles; it is process-wide because the
 * parser is shared, exactly as in the Flutter engine.
 */
import type { EdgeInsets } from './types.js';

export interface CssEnvironment {
  viewportWidth: number;
  viewportHeight: number;
  safeArea: EdgeInsets;
  rootFontSize: number;
  devicePixelRatio: number;
}

const env: CssEnvironment = {
  viewportWidth: 1280,
  viewportHeight: 800,
  safeArea: { top: 0, right: 0, bottom: 0, left: 0 },
  rootFontSize: 16,
  devicePixelRatio: 1,
};

let generation = 0;

export function cssEnvironment(): Readonly<CssEnvironment> {
  return env;
}

/** Bumped whenever the environment changes, invalidating viewport-relative caches. */
export function cssEnvironmentGeneration(): number {
  return generation;
}

export function updateCssEnvironment(next: Partial<CssEnvironment>): boolean {
  let changed = false;
  for (const key of Object.keys(next) as (keyof CssEnvironment)[]) {
    const value = next[key];
    if (value === undefined) continue;
    if (key === 'safeArea') {
      const s = value as EdgeInsets;
      const c = env.safeArea;
      if (s.top !== c.top || s.right !== c.right || s.bottom !== c.bottom || s.left !== c.left) {
        env.safeArea = { ...s };
        changed = true;
      }
    } else if ((env as any)[key] !== value) {
      (env as any)[key] = value;
      changed = true;
    }
  }
  if (changed) generation++;
  return changed;
}
