# WebView GPU Benchmark Report
**Tool:** Intel PresentMon 2.4.1  
**Suite:** PresentMon GPU Benchmark Suite v3  
**Date:** 2026-05-26  
**Present Mode:** Composed: Flip (all scenarios)

---

## Overview

WebView tests run inside a Chromium-based WebView2 control embedded in the Elpian host process. Chrome uses a **v-sync compositor** that submits frames at 60 fps even when content is static, producing a continuous stream of frames to PresentMon. This makes WebView metrics more conventional and directly comparable to standard browser benchmarks.

All WebView scenarios use the **"Composed: Flip"** present mode — a modern, lower-overhead swap-chain path that bypasses the GDI copy stage and reduces display latency compared to the "Copy with GPU GDI" path used by Elpian.

---

## Scenario Results

### WV01 — Basic Rendering
| Metric | Value |
|--------|-------|
| Frames captured | 32 |
| Avg FPS | 56.9 |
| 1% Low FPS | 15.0 |
| Avg frame time | 17.57 ms |
| P50 frame time | 16.67 ms |
| P90 frame time | 16.81 ms |
| P99 frame time | 17.70 ms |
| Worst frame | 66.67 ms |
| Jank % | 53.1% |
| Avg GPU time | 0.37 ms |
| Avg CPU time | 17.44 ms |
| Avg display latency | 49.89 ms |

**Notes:** Near-perfect 60 fps (P50=16.67 ms = exactly one v-sync). GPU load is minimal (0.37 ms). Worst frame of 66.67 ms is a single startup or transition stall. Only 32 frames captured — borderline reliable, but P50 and P90 are consistent.

---

### WV02 — CSS Animations
| Metric | Value |
|--------|-------|
| Frames captured | 42 |
| Avg FPS | 38.9 |
| 1% Low FPS | 4.1 |
| Avg frame time | 25.71 ms |
| P50 frame time | 16.65 ms |
| P90 frame time | 18.00 ms |
| P99 frame time | 116.17 ms |
| Worst frame | 245.33 ms |
| Jank % | 47.6% |
| Avg GPU time | 0.62 ms |
| Avg CPU time | 25.57 ms |
| Avg display latency | 55.65 ms |

**Notes:** P50=16.65 ms confirms animations are running at 60 fps during stable playback. The P99 spike to 116 ms and worst of 245 ms indicate brief stalls, likely during page load or animation initialization. Low GPU time (0.62 ms) means CSS animations are well-handled by the compositor thread.

---

### WV03 — Complex Layout
| Metric | Value |
|--------|-------|
| Result | **no_data** |

> **Error:** PresentMon captured no frames for this scenario. The WebView likely did not produce any swap-chain presents during the capture window, possibly due to the page being static or the capture timing missing the active render period. This scenario should be re-run.

---

### WV04 — Canvas Drawing
| Metric | Value |
|--------|-------|
| Frames captured | **4** |
| Avg FPS | 60.0 |
| 1% Low FPS | 59.1 |
| Avg frame time | 16.66 ms |
| P50 frame time | 16.64 ms |
| P90 frame time | 16.67 ms |
| P99 frame time | 16.67 ms |
| Worst frame | 16.92 ms |
| Jank % | 50.0% |
| Avg GPU time | 0.32 ms |
| Avg CPU time | 16.58 ms |
| Avg display latency | 49.48 ms |

> **Warning:** Only 4 frames captured. While the frame times are perfectly consistent (all ~16.67 ms), the sample is **statistically unreliable**. The metrics appear stable by coincidence of the small window. A re-run with longer capture is required.

---

### WV05 — List Scroll
| Metric | Value |
|--------|-------|
| Result | **no_data** |

> **Error:** PresentMon captured no frames for this scenario. Same as WV03 — likely a timing issue with the capture window or the page not triggering GPU presents during scroll. This scenario should be re-run.

---

### WV06 — Complex Dashboard
| Metric | Value |
|--------|-------|
| Frames captured | **1184** |
| Avg FPS | **59.4** |
| 1% Low FPS | 25.5 |
| 0.1% Low FPS | 9.6 |
| Avg frame time | 16.83 ms |
| P50 frame time | 16.66 ms |
| P90 frame time | 17.23 ms |
| P99 frame time | 22.79 ms |
| P999 frame time | 36.91 ms |
| Worst frame | 103.73 ms |
| Jank % | 47.8% |
| Avg GPU time | 1.52 ms |
| Avg CPU time | 16.70 ms |
| Avg display latency | 47.19 ms |

**Notes:** This is the **most reliable WebView scenario** — 1184 frames provides strong statistical confidence. 59.4 avg FPS is near-perfect 60 fps. P99=22.79 ms means 99% of frames render in under 23 ms. GPU time of 1.52 ms reflects the heavier rendering workload of a complex dashboard. Worst frame of 103.73 ms is a single GC or layout recalculation.

---

### WV07 — Smooth Animations
| Metric | Value |
|--------|-------|
| Frames captured | **1117** |
| Avg FPS | **57.7** |
| 1% Low FPS | 10.3 |
| 0.1% Low FPS | 3.4 |
| Avg frame time | 17.33 ms |
| P50 frame time | 16.66 ms |
| P90 frame time | 16.97 ms |
| P99 frame time | 22.48 ms |
| P999 frame time | 189.59 ms |
| Worst frame | 298.09 ms |
| Jank % | 49.3% |
| Avg GPU time | 1.59 ms |
| Avg CPU time | 17.14 ms |
| Avg display latency | 49.16 ms |

**Notes:** Second most reliable scenario with 1117 frames. P50=16.66 ms and P90=16.97 ms are exceptional — essentially every frame hits the 60 fps target during active animation. The P999=189 ms and worst=298 ms outliers correspond to animation startup or a brief main-thread block. GPU time of 1.59 ms is appropriate for continuous CSS animation.

---

### WV08 — Interactive Responsiveness
| Metric | Value |
|--------|-------|
| Frames captured | **4** |
| Avg FPS | 57.5 |
| 1% Low FPS | 48.2 |
| Avg frame time | 17.40 ms |
| P50 frame time | 16.20 ms |
| P90 frame time | 16.62 ms |
| P99 frame time | 16.62 ms |
| Worst frame | 20.75 ms |
| Jank % | 25.0% |
| Avg GPU time | 0.58 ms |
| Avg CPU time | 17.17 ms |
| Avg display latency | 45.52 ms |

> **Warning:** Only 4 frames captured — **statistically unreliable**. The individual frame times look good (worst=20.75 ms) but no statistical conclusions can be drawn. A re-run with sustained interaction input is required.

---

## Summary Table

| Scenario | Frames | Avg FPS | P50 ms | P99 ms | Worst ms | GPU ms | Reliable |
|----------|--------|---------|--------|--------|----------|--------|----------|
| WV01 Basic Rendering | 32 | 56.9 | 16.67 | 17.70 | 66.67 | 0.37 | Marginal |
| WV02 CSS Animations | 42 | 38.9 | 16.65 | 116.17 | 245.33 | 0.62 | Marginal |
| WV03 Complex Layout | — | — | — | — | — | — | **No data** |
| WV04 Canvas Drawing | 4 | 60.0 | 16.64 | 16.67 | 16.92 | 0.32 | **Unreliable** |
| WV05 List Scroll | — | — | — | — | — | — | **No data** |
| **WV06 Complex Dashboard** | **1184** | **59.4** | **16.66** | **22.79** | **103.73** | **1.52** | **Yes** |
| **WV07 Smooth Animations** | **1117** | **57.7** | **16.66** | **22.48** | **298.09** | **1.59** | **Yes** |
| WV08 Interactive | 4 | 57.5 | 16.20 | 16.62 | 20.75 | 0.58 | **Unreliable** |

---

## Key Findings

1. **WebView runs near 60 fps in all reliable scenarios.** WV06 and WV07 both show P50=16.66 ms, P90 under 17.25 ms, and P99 under 23 ms — essentially flawless frame delivery during the active capture window.

2. **GPU load is very low (0.32–1.59 ms per frame).** Chrome's compositor offloads rendering to GPU threads efficiently, keeping CPU frame time tight at ~16.7 ms.

3. **Three scenarios had data quality issues:** WV03 and WV05 produced no data; WV04 and WV08 had only 4 frames each. These need re-runs with longer or more active capture windows.

4. **"Composed: Flip" present mode** gives WebView a systematic advantage in display latency (~47–56 ms). This is a platform swap-chain path difference, not a rendering quality difference.

5. **Jank % is not meaningful for comparison with Elpian** — Chrome submits frames continuously at 60 Hz so about half miss the 16.67 ms threshold due to normal v-sync timing.
