# C — Canvas 2D API optimizations

**Risk:** Low · **Verifiable here:** ⚠️ inspection only · **Effort:** 0.5–1 day

> No Flutter SDK in container. Mechanical changes; verify locally with `flutter test` +
> the canvas example. Some are pure-logic and unit-testable.

## Objective
Eliminate per-draw allocations and an unnecessary expensive `saveLayer`, and remove
dead shadow code paths in the command-replay Canvas API.

## Files & targets — `lib/src/canvas/canvas_api.dart`
- **Text (`:541-573`)**: `TextPainter`+`TextSpan`+`TextStyle` allocated per `fillText`, and
  the font string is parsed every call.
  - [ ] Cache the parsed `TextStyle` keyed by the font string; only re-parse on font change.
  - [ ] Optionally cache a `TextPainter` keyed by (text, style) for repeated identical labels.
- **Paint getters (`:645-660`)**: `_getFillPaint`/`_getStrokePaint` mutate shared state paints
  and call `Color.withOpacity` every draw (new `Color` each time).
  - [ ] Precompute the opacity-adjusted color only when `globalAlpha` or base color changes
        (cache last (color, alpha)→Color). Avoid mutating a shared paint across concurrent
        draws — prefer returning a configured reusable paint per role.
- **`clearRect` (`:391-402`)**: uses `saveLayer(..., BlendMode.clear)` + inline `Paint`.
  - [ ] Replace with a single `drawRect` using a **static** `Paint()..blendMode=BlendMode.clear`
        (no `saveLayer` → avoids an offscreen layer). Validate transparency result matches.
- **`CanvasState.copy()` (`:170-193`)**: deep clone (2 `Paint` + `List`+`Matrix4`) per `save`.
  - [ ] Make copies lazy / shallow where safe; only clone fields that can mutate after save.
- **Dead shadow state (`:61-64`, `:133-136`)**: `setShadow*` commands + `CanvasState` fields exist
  but no draw path uses them.
  - [ ] Decide: **implement** shadows (`Paint..maskFilter = MaskFilter.blur` + offset draw) OR
        **remove** the dead enum/state. Implementing adds a feature; removing reduces confusion.
        Recommend implementing behind the existing command since the API advertises it.

## Keep as-is (already good)
- `lib/src/canvas/canvas_context_store.dart` — `ui.Picture` cache + correct disposal (`:68,91,122`).
- `lib/src/widgets/elpian_cached_canvas.dart` — version-notifier `shouldRepaint` (`:108-112`).

## Cross-platform notes
- Pure Flutter; works on all 6 platforms incl. web. `BlendMode.clear` on `drawRect` behaves
  consistently under Impeller and the web canvas backend — verify visually on web.

## Verification (real machine)
- [ ] `flutter analyze` clean; `flutter test`.
- [ ] Unit-test the font-string→TextStyle parser cache (pure logic).
- [ ] Run canvas example (whiteboard/Canvas API demo from README) — visual parity for text,
      transparency (clearRect), and shadows; check DevTools for reduced allocations.

## Rollback
Per-change revert; no API changes (unless you choose to implement shadows, which is additive).
