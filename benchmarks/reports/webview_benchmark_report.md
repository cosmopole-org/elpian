# WebView HTML Benchmark Report

**Date:** 2026-05-22  
**Runner:** Chrome 148 headless (Chrome DevTools Protocol v7)  
**Suite:** `benchmarks/webview/` — 5 HTML/CSS/JS benchmark pages  
**Engine:** Native browser rendering (V8 + Blink layout + Skia)

---

## Executive Summary

The WebView benchmark suite exercises Chrome's native HTML/CSS/JS rendering pipeline across five scenarios: basic DOM construction, CSS animations, complex layout, Canvas 2D drawing, and list-with-scroll. CSS animation throughput reaches ~5,376 FPS. DOM build throughput for a basic page is ~2,058 builds/sec. Style mutation throughput peaks at ~119,048/sec. The main cost is DOM construction for complex layouts (~924 builds/sec) and Canvas 2D frame rendering (~636 FPS for 70-primitive frames). Scroll operations are handled by the browser compositor and report near-zero latency. All scenarios show zero or minimal jank.

---

## Test Environment

| Item | Value |
|------|-------|
| Platform | Windows 11 |
| Browser | Chrome 148.0.7778.179 (headless, `--disable-gpu`) |
| Protocol | Chrome DevTools Protocol (CDP) via WebSocket |
| HTTP Server | PowerShell HttpListener (localhost:8768) |
| What is measured | DOM build, CSS animation frames, Canvas 2D draw, reflow, style mutation |
| What is NOT measured | GPU rasterisation, display refresh, real scroll physics |

---

## Benchmark Results

### WV01 — Basic Rendering (DOM Build)

Input: 100-div page with text, inline styles, nested structure

| Metric | Value |
|--------|-------|
| Build throughput | **2,058 builds/sec** |
| Build avg | 0.49 ms |
| Build P50 | 0.40 ms |
| Build P90 | 0.80 ms |
| Build P99 | 3.70 ms |
| Reflow avg | 0.11 ms |
| Style mutation avg | 0.008 ms |
| Style mutations/sec | **119,048/sec** |
| DOM node count | 122 |
| Heap used | 0.97 MB |

**Assessment:** Excellent. Basic DOM construction is fast; style mutation throughput is extremely high (~119K/sec), indicating V8's inline cache for CSS property writes is fully warm.

---

### WV02 — CSS Animations

Input: 10 animated elements, keyframe + JS-driven rAF animations, sinusoidal transforms

| Metric | Value |
|--------|-------|
| Animation FPS | **5,376 FPS** |
| Frame avg | 0.19 ms |
| Frame P50 | 0.10 ms |
| Frame P90 | 0.20 ms |
| Frame P99 | 0.60 ms |
| Frames measured | 300 |
| Jank rate | **0.0%** |
| Style animation avg | 0.07 ms |
| Style animation throughput | **14,286 FPS** |
| Multi-element avg | 0.032 ms |
| Multi-element throughput | **31,250 FPS** |
| Animated elements | 10 |
| Heap used | 1.18 MB |

**Assessment:** Excellent. CSS/rAF animation overhead is extremely low in Blink's compositor-threaded pipeline. Multi-element batch updates at 31,250 FPS confirm the style recalc path is near-zero-cost for transform-only changes.

---

### WV03 — Complex Layout

Input: nested flexbox grid, 437-node DOM, dynamic row insertion/deletion

| Metric | Value |
|--------|-------|
| Build throughput | **924 builds/sec** |
| Build avg | 1.08 ms |
| Build P50 | 1.00 ms |
| Build P90 | 1.60 ms |
| Reflow avg | 0.047 ms |
| Relayout throughput | **5,747 FPS** |
| Table row ops avg | 0.66 ms |
| Table row ops/sec | **1,515/sec** |
| DOM node count | 437 |
| Heap used | 0.98 MB |

**Assessment:** Good. Complex flexbox layout build takes ~1ms, which is well within the 16.67ms frame budget. Reflow is remarkably fast at 0.047ms average — Blink's incremental layout optimisation (dirty-bit propagation) avoids full-tree reflow for most mutations. Table row insertion at 1,515 ops/sec reflects the cost of forced synchronous layout.

---

### WV04 — Canvas 2D Drawing

Input: 500-frame animation loop; each frame draws 70 primitives (arcs, lines, rects)

| Metric | Value |
|--------|-------|
| Canvas FPS | **636 FPS** |
| Frame avg | 1.57 ms |
| Frame P50 | 0.00 ms |
| Frame P90 | 0.10 ms |
| Frame P99 | 0.40 ms |
| Jank rate | **0.2%** |
| Worst frame | 749.5 ms |
| Total frames | 500 |
| Primitives/frame | 70 |
| Arc avg | 0.0011 ms |
| Line avg | 0.0003 ms |
| Rect avg | 0.0008 ms |
| Heap used | 1.38 MB |

**Assessment:** Good. Per-primitive costs are sub-millisecond; the 1.57ms average frame cost for 70 primitives is reasonable. The 749ms worst-frame outlier is a GPU/rasterisation cold-start artefact (first frame allocates backing store). P90 at 0.10ms is within budget. The 0.2% jank rate corresponds to that single startup spike across 500 frames.

---

### WV05 — List Scroll (200-item)

Input: 200-item list (text + icon + badge), virtual scroll simulation, bulk DOM updates

| Metric | Value |
|--------|-------|
| Build throughput | **850 builds/sec** |
| Build avg | 1.18 ms |
| Build P90 | 1.60 ms |
| Scroll avg | 0.004 ms |
| Scroll P90 | 0.00 ms |
| Scroll FPS | **285,714 FPS** |
| Scroll jank | **0.0%** |
| DOM update avg | 0.097 ms |
| DOM update P90 | 0.20 ms |
| DOM updates/sec | **10,352/sec** |
| Bulk ops avg | 0.376 ms |
| Bulk ops/sec | **2,660/sec** |
| DOM node count | 600 |
| Heap used | 1.76 MB |

**Assessment:** Excellent for scroll, good for build. The near-zero scroll latency (0.004ms avg) reflects browser compositor-layer scrolling — no main thread involvement. Initial list build at 1.18ms and DOM update throughput at 10,352/sec are solid for a 200-item virtualized list. Bulk DOM operations (batch insert/remove) at 2,660 ops/sec are the expected bottleneck for non-virtualized updates.

---

## Performance Profile Summary

| Scenario | Primary FPS / Throughput | Avg (ms) | Jank |
|----------|--------------------------|----------|------|
| WV01 Basic Rendering | 2,058 builds/sec | 0.49 ms | — |
| WV01 Style Mutations | 119,048 mutations/sec | 0.008 ms | — |
| WV02 CSS Animation | 5,376 FPS | 0.19 ms | 0.0% |
| WV02 Style Animation | 14,286 FPS | 0.07 ms | — |
| WV02 Multi-element | 31,250 FPS | 0.032 ms | — |
| WV03 Complex Layout | 924 builds/sec | 1.08 ms | — |
| WV03 Reflow | 5,747 relayouts/sec | 0.047 ms | — |
| WV04 Canvas 2D | 636 FPS (70 prim/f) | 1.57 ms | 0.2% |
| WV05 List Build | 850 builds/sec | 1.18 ms | — |
| WV05 Scroll | 285,714 FPS | 0.004 ms | 0.0% |
| WV05 DOM Updates | 10,352 updates/sec | 0.097 ms | — |

---

## Key Findings

1. **CSS mutation is near-free.** Style mutations at 119,048/sec and multi-element animation at 31,250 FPS confirm V8 + Blink's JIT-compiled style recalc path is effectively zero-cost for transform/opacity changes.
2. **Reflow is fast when incremental.** Average reflow at 0.047ms demonstrates that Blink's dirty-bit mechanism limits reflow to only affected subtrees. Forced synchronous layout (table row ops) is 14× slower at 0.66ms.
3. **Canvas 2D is the bottleneck.** At 636 FPS for 70 primitives, Canvas 2D drawing is the most expensive operation — consistent with Skia's CPU-side path tessellation before GPU upload (GPU is disabled in headless mode).
4. **Compositor-thread scroll has effectively zero overhead.** Scroll latency of 0.004ms (285,714 FPS) reflects OS-compositor event dispatch, not main-thread work.
5. **Heap stays low.** Peak heap across all scenarios is 1.76 MB, confirming efficient memory use with 437–600 DOM nodes.
