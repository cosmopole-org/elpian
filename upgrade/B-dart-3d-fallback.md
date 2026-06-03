# B — Dart 3D fallback renderer optimizations

**Risk:** Low · **Verifiable here:** ⚠️ inspection only (no Flutter SDK) · **Effort:** 1 day

> Cannot be compiled in the cloud container. Keep changes mechanical and review by
> inspection; verify with `flutter test`/`flutter run --profile` on a real machine.
> Add pure-Dart unit tests for math where feasible (run via `flutter test` locally).

## Objective
Cut per-frame allocations and over-repaint in the pure-Dart software 3D renderer used
when native FFI is unavailable (and on web fallback).

## Files & targets
- `lib/src/scene3d/renderer.dart`
  - `:98` `new ui.Path()` per triangle → **reuse one `Path` + `path.reset()`**.
  - `:77-78` `screenTris`/`screenParticles` rebuilt per frame → **reuse pooled lists**
    (clear, don't reallocate; pre-size with capacity).
  - `:232-240` per-triangle clip vertex/color lists → **fixed-size stack buffers** (max ~10).
  - `:361` `math.pow(nDotH, shininess)` → integer-exponent multiply when shininess is
    near-integer, or precomputed power LUT.
- `lib/src/scene3d/core.dart`
  - `:259-271` `Mat4*Mat4` allocates `Float64List(16)` → **cache view-projection** per frame;
    cache per-node world transform; invalidate only when TRS changes.
  - `:1132-1135` particle `removeAt` O(n) → **swap-and-pop** (`list[i]=list.removeLast()`).
  - `:1150` `_spawnParticle` allocates → **object pool** of `Particle`, reset fields on reuse.
- `lib/src/scene3d/game_scene_widget.dart`
  - `:264` `shouldRepaint => true` and `:153-164` ticker `setState(() {})` → switch the
    `CustomPaint` to a `repaint:` `Listenable` (a `ChangeNotifier`/`ValueNotifier` the ticker
    bumps) so only the painter repaints — no widget-subtree rebuild. Keep `RepaintBoundary`.
- `lib/src/bevy/dart_scene_renderer.dart` (888 lines, duplicate renderer) — mirror the
  same Path-reuse / pooling / matrix-cache fixes. Consider de-duplicating against
  `scene3d` later (separate refactor; out of scope for the perf pass).

## Implementation notes
- **Path reuse pattern:**
  ```dart
  final _path = ui.Path();
  // per triangle:
  _path.reset();
  _path..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..close();
  canvas.drawPath(_path, triPaint);
  ```
- **Repaint via Listenable (kills empty setState):**
  ```dart
  final _repaint = ValueNotifier<int>(0);
  void _onTick(Duration e){ _renderer.advanceTime(dt); _repaint.value++; }
  // build(): RepaintBoundary(child: CustomPaint(painter: _Painter(_renderer, repaint:_repaint)))
  // painter: _Painter(this.r,{required Listenable repaint}):super(repaint:repaint);
  //          shouldRepaint(old)=> false;  // repaint Listenable drives it
  ```
- Matrix cache: store `Mat4? _cachedWorld` + a dirty flag on `SceneNode`; recompute only
  when position/rotation/scale setters mark dirty.

## Cross-platform notes
- Pure Flutter/Dart; identical on all 6 platforms incl. web. No native deps.

## Verification (on a real machine)
- [ ] `flutter analyze` clean.
- [ ] `flutter test` — add unit tests for: swap-and-pop preserves set membership; matrix
      cache equals fresh compute; particle pool reuse resets all fields.
- [ ] `flutter run --profile` a 3D demo; compare frame times / GC in DevTools timeline.
- [ ] Visual parity check (no rendering regressions) on at least mobile + web + desktop.

## Rollback
Each fix is independent; revert per-fix. No API changes.
