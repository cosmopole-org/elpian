# Elpian vs WebView — Performance Comparison Report

**Date:** 2026-05-22  
**Sources:** `elpian_benchmark_report.md` · `webview_benchmark_report.md`

---

## Overview

This report compares the Elpian JSON-driven Flutter rendering pipeline against native browser (Chrome 148 / Blink) rendering across matched scenario pairs. Both suites ran headless on the same Windows 11 machine with GPU rasterisation disabled, so the numbers reflect CPU-side work only: JSON/DOM parsing, style computation, widget/element tree construction, and layout.

> **Scope caveat**: the two suites do not measure identical workloads. Elpian measures a Dart VM + Flutter widget tree pipeline; WebView measures V8 + Blink DOM pipeline. Direct numeric comparisons are directional, not apples-to-apples.

---

## Matched Scenario Pairs

### 1. Basic Rendering / Widget Build

| Metric | Elpian S1 (Basic JSON) | WebView WV01 (DOM Build) |
|--------|------------------------|--------------------------|
| Throughput | **2,918 FPS** | 2,058 builds/sec |
| Avg build | 0.34 ms | 0.49 ms |
| P99 | 1.17 ms | 3.70 ms |
| Jank | 0.3% | — |

**Elpian wins** on throughput (+42%) and P99 latency (+68%). Both are well within real-time budget. Elpian's Dart VM warm-up benefits are visible in the lower P99.

---

### 2. CSS / Style Parsing

| Metric | Elpian S7 (CSS Parse) | WebView WV01 (Style Mutations) |
|--------|-----------------------|-------------------------------|
| Throughput | **24,205 FPS** | 119,048 mutations/sec |
| Avg time | 0.04 ms | 0.008 ms |

**WebView wins** on style mutation throughput (~5×). This is expected: Blink's CSS engine operates directly on pre-compiled style sheets and uses JIT-specialised inline caches per property, while Elpian parses CSS from raw JSON strings on every call. Elpian's 24,205 FPS is still excellent in absolute terms.

---

### 3. Animation Throughput

| Metric | Elpian S3 (Animation Build) | WebView WV02 (CSS Animation) |
|--------|-----------------------------|------------------------------|
| FPS | **3,265 FPS** | 5,376 FPS |
| Avg frame | 0.31 ms | 0.19 ms |
| P99 | 2.17 ms | 0.60 ms |
| Jank | 0.0% | 0.0% |

**WebView wins** on animation throughput (+65%) and P99 (-72%). Blink's compositor-threaded animation pipeline processes rAF callbacks on a dedicated thread with GPU-assisted transform interpolation. Elpian's animation path reconstructs the full widget subtree from JSON each frame. Both have zero jank; the gap is in headroom.

---

### 4. Complex Layout

| Metric | Elpian S2 (Complex Dashboard) | WebView WV03 (Complex Layout) |
|--------|-------------------------------|-------------------------------|
| Throughput | **491 FPS** | 924 builds/sec |
| Avg build | 2.04 ms | 1.08 ms |
| P99 | 16.27 ms | — |

**WebView wins** on throughput (~2×) and average build time (~2×). For a 24-card / 437-node complex layout, Blink's incremental DOM construction is significantly faster than Elpian's full JSON → widget tree inflation. Elpian's P99 approaching the 16.67ms budget is a concern for complex screens.

---

### 5. List / Large Dataset

| Metric | Elpian S4 (Large List) | WebView WV05 (List Build) |
|--------|------------------------|---------------------------|
| Throughput | 320 FPS | **850 builds/sec** |
| Avg build | 3.12 ms | 1.18 ms |
| P99 | 23.08 ms | — |
| Jank | 2.0% | 0.0% |

**WebView wins** significantly (~2.7× throughput, ~2.6× lower avg). Large list construction is Elpian's weakest scenario: P99 at 23ms exceeds the 16.67ms budget and jank reaches 2%. Blink's DOM construction for 200 items is faster because element creation is a single C++ call with zero JSON parse overhead per item.

---

### 6. Re-render / DOM Update

| Metric | Elpian S6 (Rapid Re-render) | WebView WV05 (DOM Updates) |
|--------|-----------------------------|-----------------------------|
| Throughput | **705 FPS** | 10,352 updates/sec |
| Avg | 1.42 ms | 0.097 ms |
| P99 | 3.33 ms | 0.20 ms |
| Jank | 0.0% | 0.0% |

**WebView wins** dramatically on individual DOM update latency. A targeted `element.textContent = x` in the browser costs ~0.1ms; Elpian's `setState` + full widget rebuild costs ~1.4ms because the framework re-evaluates the full JSON tree. This is the largest relative gap across all scenarios.

---

### 7. Canvas / Custom Drawing

| Metric | Elpian S3* (no direct match) | WebView WV04 (Canvas 2D, 70 prim/frame) |
|--------|------------------------------|-----------------------------------------|
| Throughput | — | **636 FPS** |
| Avg frame | — | 1.57 ms |
| Jank | — | 0.2% |

Elpian does not have a direct Canvas-equivalent benchmark in this suite. Elpian uses Flutter's `CustomPainter` / `Canvas` API which routes through Skia similarly to WebView's Canvas 2D. A future Elpian canvas benchmark would be a meaningful addition.

---

## Head-to-Head Summary

| Domain | Winner | Margin |
|--------|--------|--------|
| Basic build throughput | **Elpian** | +42% |
| Basic build P99 | **Elpian** | −68% (lower) |
| CSS/style mutations | **WebView** | ~5× faster |
| Animation FPS | **WebView** | +65% |
| Animation P99 | **WebView** | −72% (lower) |
| Complex layout throughput | **WebView** | ~2× faster |
| Large list throughput | **WebView** | ~2.7× faster |
| Large list P99 | **WebView** | below budget vs Elpian 23ms |
| DOM update latency | **WebView** | ~15× lower avg |
| Jank (animation) | Tied | 0.0% both |
| Jank (large list) | **WebView** | 0% vs 2% |

---

## Architectural Analysis

### Where Elpian leads

- **Cold-start JSON builds** — Elpian's Dart VM pipeline parses a compact JSON blob and inflates a typed widget tree without touching the DOM. For simple-to-moderate trees this is marginally faster than V8 parsing HTML + building a DOM, because Elpian's JSON schema is purpose-built.
- **P99 predictability for simple builds** — Elpian's P99 (1.17ms) beats WebView (3.70ms) for basic widgets, meaning GC spikes are less frequent in the Dart VM for small, short-lived widget objects.

### Where WebView leads

- **Incremental mutation** — Blink separates construction from mutation. A targeted `.style.transform =` call costs ~0.01ms; Elpian always rebuilds the full JSON subtree, costing ~1–3ms.
- **Compositor-thread animations** — CSS/rAF animations in Chrome run on a dedicated compositor thread, bypassing the main thread entirely for transform/opacity. Elpian builds JSON widget trees on the main Dart isolate every frame.
- **Large list construction** — C++ DOM node allocation in V8 is ~3× faster than Dart object allocation + JSON parse + widget inflation for list items.
- **Reflow efficiency** — Blink's dirty-region propagation means only changed nodes reflow; Elpian re-lays out the full subtree on `setState`.

### Strategic implications for Elpian

1. **Virtual/lazy list inflation** is the highest-impact optimisation. Elpian's 2% jank and 23ms P99 for 100-item lists is the only scenario that actively degrades user experience.
2. **Incremental widget diffing** (analogous to React's virtual DOM diffing) would bring re-render latency from ~1.4ms toward the ~0.1ms WebView level.
3. **CSS parse caching** — Elpian's CSS throughput (24,205 FPS) is already excellent, but caching parsed style maps by content hash would eliminate repeated parses for static styles.
4. **Animation: compositor offload** — For transform/opacity animations driven by continuous JSON, Elpian could cache the Flutter `Tween` and only update the target value rather than rebuilding the full `AnimatedContainer` widget tree each frame.

---

## Conclusion

Elpian's JSON-to-widget pipeline is competitive for basic and moderate widget trees, matching or exceeding native DOM construction for simple cases. The framework's natural advantage is its compact, typed schema and warm Dart VM — visible in lower P99 for basic builds.

Native browser rendering leads in animation throughput, large-list construction, and incremental DOM mutation — all areas where Blink's architectural investment in compositor threads, incremental dirty-tracking, and native C++ element allocation pays dividends.

Elpian's roadmap priorities, in order of user-visible impact:
1. **Lazy list inflation / virtual scroll** (fixes 2% jank, brings P99 under budget)
2. **Widget-tree diffing** (reduces re-render cost from ~1.4ms to near-zero for stable subtrees)
3. **Animation compositing** (brings animation FPS on par with WebView for transform-only animations)
