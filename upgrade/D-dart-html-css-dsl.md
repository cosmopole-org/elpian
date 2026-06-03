# D — HTML / CSS / Flutter-DSL pipeline optimizations

**Risk:** Med · **Verifiable here:** ⚠️ inspection only · **Effort:** 2–3 days · **ROI:** Highest on the Flutter UI side

> No Flutter SDK in container. This is the largest Flutter-side win (CSS is re-parsed on
> every build; the whole tree rebuilds each update). Land incrementally; verify locally.

## Objective
Stop re-parsing CSS every build, stop the double style-parse, enable widget reuse via
const + stable keys, and add image decode caching.

## D1 — CSS parse + computed-style caching (CRITICAL)
Files: `lib/src/css/css_parser.dart`, `lib/src/css/stylesheet.dart`, `lib/src/css/json_stylesheet_parser.dart`.
- [ ] Memoize `CSSParser.parse(Map)` result keyed by a stable hash of the style map
      (cache `CSSStyle`). Today it runs regex color/gradient/shadow parsing per element per build
      (`css_parser.dart:177-229`, `:459-497`, `:526-560`).
- [ ] Cache `GlobalStylesheetManager.getComputedStyle(tag,id,classes)` results keyed by
      `(tag, id, sortedClasses)` — currently linear map lookups + re-parse every call
      (`stylesheet.dart:103-136`), no memoization (`:246-312`).
- [ ] Pre-parse stylesheet rules **once at load** (in `json_stylesheet_parser.dart`), storing
      `CSSStyle` (not raw maps), so builds read parsed objects.
- [ ] Make named-color and font-weight maps `const`/`static final` (`css_parser.dart:669`, `:343`).
- [ ] Add an LRU bound to the caches to avoid unbounded growth on highly dynamic styles.

## D2 — Kill the double parse on merge (CRITICAL, quick)
File: `lib/src/core/elpian_engine.dart:266-276` (+ `_styleToMap` `:327-370`).
- [ ] When merging stylesheet + inline styles, **merge the two maps then call `CSSParser.parse`
      once** instead of CSSStyle→Map→merge→CSSStyle (which parses twice). Or merge two cached
      `CSSStyle` objects via a `CSSStyle.merge(other)` that copies non-null fields — no re-parse.

## D3 — Immutability + const + keys (enables Flutter subtree skipping)
Files: `lib/src/models/css_style.dart`, `lib/src/html_widgets/*`, `lib/src/core/elpian_engine.dart`.
- [ ] Add `@immutable` to `CSSStyle`, ensure all fields `final`, implement `==`/`hashCode`
      (`css_style.dart:251` already has a const ctor) → enables caching + const widgets.
- [ ] Give nodes **stable keys** (`ObjectKey`/`ValueKey` from node id) consistently, not only for
      event-enabled widgets (`elpian_engine.dart:302-317`), so Flutter can diff/reuse subtrees
      even though Elpian rebuilds the widget objects.
- [ ] Convert frequently-used HTML builders to `const`-capable `StatelessWidget`s where inputs allow.

## D4 — Layout/widget micro-fixes
Files: `lib/src/html_widgets/html_div.dart`, `html_span.dart`, `html_p.dart`, `lib/src/css/css_properties.dart`.
- [ ] `_addGap` (`html_div.dart:80-93`) rebuilds a list + `SizedBox` each build → cache the
      gapped children when `gap` + children identity unchanged, or use flex `spacing`.
- [ ] Use `Text` directly when there are no inline children instead of wrapping in `Wrap`
      (`html_span.dart`, `html_p.dart`).
- [ ] Only wrap in `Opacity`/`Transform`/`ClipRRect` when value ≠ identity
      (`css_properties.dart:12-36`) — skip default-wrapping. Avoid `Container` double-wrap
      (`html_div.dart:71` + `CSSProperties.applyStyle`).
- [ ] Cache `TextStyle` by property tuple (`css_properties.dart:164-179`).
- [ ] Large collections: ensure `ListView.builder`/`GridView.builder` (lazy) rather than eager
      children (check `lib/src/widgets/elpian_list_view.dart`, `elpian_grid_view.dart`).

## D5 — Image decode caching
Files: `lib/src/html_widgets/html_img.dart:10-12`, `lib/src/widgets/elpian_image.dart:10-12`.
- [ ] Add `cacheWidth`/`cacheHeight` (from layout/style) to `Image.network`/`Image.asset`, and/or
      wrap providers in `ResizeImage` so images decode at display size, not full res.
- [ ] Consider a fade-in / error placeholder; ensure src changes don't force needless re-decode.

## D6 — Animated widgets stop per-frame allocation
Files: `lib/src/widgets/elpian_shimmer.dart:74-89`, `elpian_animated_gradient.dart:62-88`.
- [ ] Precompute gradient stop lists once; tween scalar values rather than rebuilding
      `LinearGradient`/`List.generate` every frame inside `AnimatedBuilder`.

## D7 — (Stretch) widget diffing
File: `lib/src/core/elpian_engine.dart:236-320`.
- [ ] Currently the whole tree is rebuilt each `render`. With stable keys (D3), Flutter's
      element reconciliation already skips unchanged subtrees cheaply. A full Elpian-side
      virtual-DOM diff is a larger project — note it but prefer keys+const first.

## Cross-platform notes
- All pure Flutter; identical on all 6 platforms incl. web. No native deps.
- Verify `==`/`hashCode` on `CSSStyle` is correct (cache-key correctness) — a bad hashCode
  causes stale styles. Unit-test it.

## Verification (real machine)
- [ ] `flutter analyze`; `flutter test` incl. new tests for CSSStyle equality/merge + cache hits.
- [ ] `flutter run --profile` the landing-page / list-scroll examples; compare build+raster times
      and allocations in DevTools vs baseline (`benchmarks/reports/presentmon` has prior numbers).
- [ ] Visual regression sweep across web + mobile + desktop.

## Rollback
Each of D1–D6 is independent; revert per-item. Watch CSSStyle equality if D3 lands.
