# Elpian vs WebView — GPU Benchmark Comparison
**Tool:** Intel PresentMon 2.4.1  
**Date:** 2026-05-26

---

## Methodology Note

These two renderers operate fundamentally differently and cannot be compared directly on most PresentMon metrics:

| Property | Elpian (Flutter) | WebView (Chromium) |
|----------|------------------|--------------------|
| Frame submission | Demand-driven (on input only) | Continuous v-sync at 60 Hz |
| Present mode | Composed: Copy with GPU GDI | Composed: Flip |
| Meaningful FPS metric | P50 frame time | Avg FPS / P50 |
| Jank % meaning | Reflects idle gaps, not missed frames | Reflects actual frame timing |

**Use P50 and P99 for cross-renderer comparisons, not avg_fps or jank%.**

---

## Head-to-Head: Best Scenarios

Comparing Elpian's best scenario (E05 Landing Page, 396 frames) against WebView's two reliable scenarios (WV06 and WV07, 1100+ frames each):

| Metric | E05 Elpian Landing Page | WV06 WebView Dashboard | WV07 WebView Animations |
|--------|------------------------|------------------------|------------------------|
| Frames | 396 | 1184 | 1117 |
| Avg FPS | 26.7 | **59.4** | **57.7** |
| P50 ms | 37.39 | **16.66** | **16.66** |
| P90 ms | 47.53 | **17.23** | **16.97** |
| P99 ms | 71.23 | **22.79** | **22.48** |
| Worst ms | **92.74** | 103.73 | 298.09 |
| Avg GPU ms | **2.60** | 1.52 | 1.59 |
| Avg latency ms | 60.45 | **47.19** | **49.16** |
| Present mode | Copy+GDI | **Flip** | **Flip** |

---

## Analysis

### Frame Rate
WebView delivers a consistent **~60 fps** (P50=16.66 ms) while Elpian peaks at **~27 fps** (P50=37.39 ms) in its best scenario. Under active animation or continuous scroll, Elpian would likely approach 26–28 fps. This is a **2.2x throughput gap** in favor of WebView.

### Worst-Case Latency
Elpian's worst-case frame in E05 is **92.74 ms** — better than WV06 (103.73 ms) and far better than WV07 (298.09 ms). When Elpian is actively rendering, it does not exhibit the long tail outliers that Chromium's GC and V8 runtime introduce.

### GPU Usage
Both renderers are GPU-light in these scenarios. Elpian uses 2.6 ms/frame vs WebView's 1.52–1.59 ms/frame — a marginal difference given the different frame rates. Elpian's higher per-frame GPU time partly compensates for fewer frames per second (more work per frame interval).

### Display Latency
WebView has ~13 ms lower display latency (47–49 ms vs 60 ms). This is largely explained by the present mode difference: "Composed: Flip" skips the GDI copy stage that "Copy with GPU GDI" requires, saving one composition step.

---

## Root Cause: Present Mode

The single largest architectural gap is the **present mode**:

- **Elpian — "Composed: Copy with GPU GDI"**: Flutter's Windows backend uses an older DXGI path that copies the rendered frame through a GDI surface before presenting. This adds latency and prevents triple-buffering.
- **WebView — "Composed: Flip"**: Chromium uses DXGI flip swap-chain semantics, allowing the GPU to flip ownership of surfaces directly to the compositor without a copy. This is the correct modern path for low-latency rendering.

Migrating Elpian's Flutter Windows backend from GDI copy to DXGI flip would recover most of the display latency gap and potentially improve frame rate.

---

## Summary

| Aspect | Winner | Margin |
|--------|--------|--------|
| Sustained FPS | WebView | 2.2x (60 vs 27 fps) |
| Worst-case frame | Elpian | Elpian: 93 ms, WebView: 298 ms (WV07) |
| Display latency | WebView | ~13 ms lower |
| GPU efficiency | WebView | Marginal |
| Present mode | WebView | Flip > Copy+GDI |

WebView wins on sustained throughput and display latency due to Chromium's mature compositor and DXGI Flip integration. Elpian's tail latency is competitive when actively driven, but the demand-driven model and GDI copy present path limit its peak frame rate. The most impactful fix for Elpian would be adopting DXGI flip swap-chains on the Flutter Windows embedding layer.
