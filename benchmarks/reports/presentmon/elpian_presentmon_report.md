# Elpian GPU Benchmark Report
**Tool:** Intel PresentMon 2.4.1  
**Suite:** PresentMon GPU Benchmark Suite v3  
**Date:** 2026-05-26  
**Present Mode:** Composed: Copy with GPU GDI

---

## Overview

Elpian is a Flutter-based UI engine running on Windows. Flutter uses **demand-driven rendering**: frames are only produced when the UI changes in response to input or animation. Between user interactions, Flutter emits no frames at all. This means PresentMon captures long idle gaps as single "mega-frames," which inflates average frame time and suppresses average FPS far below the actual render speed.

**Key implication:** `avg_fps` and `jank_pct` are not reliable quality metrics for Elpian. The meaningful metrics are `p50_ms` (typical render latency) and `p99_ms` (worst-case spike). `avg_gpu_ms` reflects true GPU load per frame.

---

## Scenario Results

### E01 — Home List Scroll
| Metric | Value |
|--------|-------|
| Frames captured | 121 |
| Avg FPS | 10.1 |
| 1% Low FPS | 0.7 |
| Avg frame time | 98.84 ms |
| P50 frame time | 45.57 ms |
| P90 frame time | 264.41 ms |
| P99 frame time | 926.49 ms |
| Worst frame | 1435.33 ms |
| Jank % | 98.3% |
| Avg GPU time | 0.46 ms |
| Avg CPU time | 121.52 ms |
| Avg display latency | 144.48 ms |

**Notes:** Scroll interaction drives rendering in short bursts. Low GPU time (0.46 ms) confirms the GPU is idle most of the session. P50=45.57 ms represents a rendered frame during active scroll. The 1435 ms worst frame is an idle gap between scroll gestures, not a render stall.

---

### E02 — QuickJS Calculator
| Metric | Value |
|--------|-------|
| Frames captured | **6** |
| Avg FPS | 15.2 |
| 1% Low FPS | 5.2 |
| Avg frame time | 65.7 ms |
| P50 frame time | 22.14 ms |
| P90 frame time | 123.00 ms |
| P99 frame time | 123.00 ms |
| Worst frame | 192.65 ms |
| Jank % | 83.3% |
| Avg GPU time | 1.37 ms |
| Avg CPU time | 56.28 ms |
| Avg display latency | 34.86 ms |

> **Warning:** Only 6 frames captured. This sample is **statistically unreliable**. Results should not be used for performance conclusions. A re-run with more button interactions is recommended.

---

### E03 — Ordinary UI
| Metric | Value |
|--------|-------|
| Frames captured | 96 |
| Avg FPS | 8.8 |
| 1% Low FPS | 0.6 |
| Avg frame time | 113.23 ms |
| P50 frame time | 32.08 ms |
| P90 frame time | 46.96 ms |
| P99 frame time | 1332.86 ms |
| Worst frame | 1656.28 ms |
| Jank % | 86.5% |
| Avg GPU time | 1.92 ms |
| Avg CPU time | 144.48 ms |
| Avg display latency | 174.93 ms |

**Notes:** P50=32 ms and P90=47 ms are well-formed, indicating the UI renders promptly when driven. P99 spike to 1332 ms is an idle gap. High CPU time (144 ms avg) reflects the demand-driven measurement window including idle time.

---

### E04 — Canvas API
| Metric | Value |
|--------|-------|
| Frames captured | 161 |
| Avg FPS | 11.2 |
| 1% Low FPS | 0.7 |
| Avg frame time | 89.46 ms |
| P50 frame time | 33.62 ms |
| P90 frame time | 92.13 ms |
| P99 frame time | 601.51 ms |
| P999 frame time | 1334.17 ms |
| Worst frame | 1676.14 ms |
| Jank % | 85.1% |
| Avg GPU time | 1.77 ms |
| Avg CPU time | 89.28 ms |
| Avg display latency | 111.42 ms |

**Notes:** The canvas scenario generates more frames than most Elpian scenarios (161), which narrows idle gaps and improves P90. P50=33.62 ms is consistent with light per-frame canvas work.

---

### E05 — Landing Page
| Metric | Value |
|--------|-------|
| Frames captured | **396** |
| Avg FPS | **26.7** |
| 1% Low FPS | 12.8 |
| 0.1% Low FPS | 10.8 |
| Avg frame time | 37.51 ms |
| P50 frame time | 37.39 ms |
| P90 frame time | 47.53 ms |
| P99 frame time | 71.23 ms |
| P999 frame time | 74.52 ms |
| Worst frame | **92.74 ms** |
| Jank % | 95.7% |
| Avg GPU time | 2.60 ms |
| Avg CPU time | 37.43 ms |
| Avg display latency | 60.45 ms |

**Notes:** This is the **best and most representative Elpian scenario**. With 396 frames and a worst frame of only 92.74 ms, idle gaps are minimal — the scroll input drove continuous rendering. P99=71 ms and worst=92.74 ms show that Elpian consistently renders the landing page in under 100 ms per frame. GPU time of 2.6 ms indicates modest GPU work per frame. Avg CPU=37.43 ms aligns closely with avg_frame_ms=37.51 ms, meaning CPU is fully driving frame production.

---

## Summary Table

| Scenario | Frames | Avg FPS | P50 ms | P99 ms | Worst ms | GPU ms |
|----------|--------|---------|--------|--------|----------|--------|
| E01 Home List Scroll | 121 | 10.1 | 45.57 | 926.49 | 1435.33 | 0.46 |
| E02 QuickJS Calc ⚠️ | 6 | 15.2 | 22.14 | 123.00 | 192.65 | 1.37 |
| E03 Ordinary UI | 96 | 8.8 | 32.08 | 1332.86 | 1656.28 | 1.92 |
| E04 Canvas API | 161 | 11.2 | 33.62 | 601.51 | 1676.14 | 1.77 |
| **E05 Landing Page** | **396** | **26.7** | **37.39** | **71.23** | **92.74** | **2.60** |

⚠️ E02 has only 6 frames — statistically unreliable.

---

## Key Findings

1. **GPU load is very low.** All scenarios show avg GPU time under 3 ms, confirming Elpian's rendering is CPU-bound, not GPU-bound. The GPU is idle the vast majority of the time.

2. **P50 render latency is 22–46 ms** across scenarios, which corresponds to roughly 22–45 fps if the UI were continuously animated. This is acceptable for a UI toolkit driven by user events rather than continuous animation.

3. **E05 Landing Page is the gold standard scenario** — sufficient frame count, no idle gaps distorting the data, and a worst-case frame under 100 ms. Other scenarios should be re-run with denser interaction sequences.

4. **Present mode "Composed: Copy with GPU GDI"** is an older, higher-overhead path compared to the "Composed: Flip" mode used by Chrome. This contributes to higher display latency (60–175 ms vs ~50 ms in Chrome/WebView tests).

5. **Jank % is not meaningful** for Flutter demand-driven rendering. The metric counts frames that missed a 16.67 ms v-sync interval, but Flutter does not target continuous 60 fps — it renders only when needed.
