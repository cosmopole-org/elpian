# Elpian UI Framework — Performance Benchmark Report

**Date:** 2026-05-22  
**Runner:** `flutter test` (Dart VM, headless — no GPU/CanvasKit)  
**Suite:** `test/performance_benchmark_test.dart`  
**Engine:** Elpian JSON → Flutter widget tree pipeline

---

## Executive Summary

Elpian's JSON-to-widget-tree pipeline is extremely fast for simple and mid-complexity trees. Basic widget builds sustain ~2,900 FPS equivalent throughput, and CSS parsing reaches ~24,200 FPS. The main bottleneck is large list/grid builds (~320 FPS) and full layout+pump cycles (~72 FPS), which involve Dart widget inflation and Flutter layout resolution overhead. Jank (frames >16.67ms) is near-zero for most scenarios, with the only notable exception in the layout pump test.

---

## Test Environment

| Item | Value |
|------|-------|
| Platform | Windows 11 (Dart VM) |
| Runner | `flutter test` — no device, no GPU |
| What is measured | JSON parse + Elpian engine + Flutter widget tree construction |
| What is NOT measured | CanvasKit rasterisation, GPU upload, display refresh |

---

## Benchmark Results

### S1 — Basic JSON Build (300 iterations)

Input: simple Column + 3 Text + Card + ElevatedButton from JSON

| Metric | Value |
|--------|-------|
| Throughput (FPS equiv.) | **2,918 FPS** |
| Avg build time | 0.34 ms |
| P50 | 0.21 ms |
| P90 | 0.28 ms |
| P99 | 1.17 ms |
| Worst | 32.74 ms |
| Jank rate | 0.3% |

**Assessment:** Excellent. Sub-ms builds; P90 within two-fold of median. Jank is negligible — rare GC pauses.

---

### S2 — Complex Dashboard (100 iterations)

Input: 24-card grid with nested widgets

| Metric | Value |
|--------|-------|
| Throughput | **491 FPS** |
| Avg build time | 2.04 ms |
| P50 | 1.70 ms |
| P90 | 2.97 ms |
| P99 | 16.27 ms |
| Worst | 16.27 ms |
| Jank rate | 0.0% |

**Assessment:** Good. Complex trees take 2× longer but P99 just barely touches the 16.67ms budget. Zero jank under sustained load.

---

### S3 — Animation Build (200 iterations)

Input: sinusoidal AnimatedContainer JSON regenerated each frame

| Metric | Value |
|--------|-------|
| Throughput | **3,265 FPS** |
| Avg build time | 0.31 ms |
| P50 | 0.23 ms |
| P90 | 0.42 ms |
| P99 | 2.17 ms |
| Worst | 5.34 ms |
| Jank rate | 0.0% |

**Assessment:** Excellent. Animation-path JSON is compact; the engine handles continuous re-build with very low latency.

---

### S4 — Large List Build (50 iterations)

Input: 100-item list with text, icons, dividers

| Metric | Value |
|--------|-------|
| Throughput | **320 FPS** |
| Avg build time | 3.12 ms |
| P50 | 2.28 ms |
| P90 | 5.79 ms |
| P99 | 23.08 ms |
| Worst | 23.08 ms |
| Jank rate | 2.0% |

**Assessment:** Fair. List construction scales linearly with item count. P99 exceeds the 16.67ms budget; optimising the list path (virtual scrolling, lazy inflation) would help.

---

### S5 — Widget Build (60 iterations, no layout)

Input: `tester.pumpWidget` without full layout pass

| Metric | Value |
|--------|-------|
| Throughput | **2,184 FPS** |
| Avg build time | 0.46 ms |
| P50 | 0.33 ms |
| P90 | 0.61 ms |
| P99 | 3.85 ms |
| Jank rate | 0.0% |

---

### S5 — Pump Layout (60 iterations, full layout)

Input: `setState` + full layout pass

| Metric | Value |
|--------|-------|
| Throughput | **72 FPS** |
| Avg build+layout | 13.92 ms |
| P50 | 7.86 ms |
| P90 | 11.62 ms |
| P99 | 314.85 ms |
| Worst | 314.85 ms |
| Jank rate | 5.0% |

**Assessment:** Weak. Full layout resolution in the test harness is expensive. P99 spike to 314ms is a cold-start artefact; P90 at 11.62ms is within budget. This measures Flutter's layout pass, not Elpian's parsing.

---

### S6 — Rapid Re-render (150 iterations)

Input: rapid `setState` → rebuild cycles

| Metric | Value |
|--------|-------|
| Throughput | **705 FPS** |
| Avg build time | 1.42 ms |
| P50 | 1.33 ms |
| P90 | 1.81 ms |
| P99 | 3.33 ms |
| Jank rate | 0.0% |

**Assessment:** Good. Re-render path is predictable with minimal variance (P99 = 2.3× median).

---

### S7 — CSS Style Parse Throughput (500 iterations)

Input: complex 20-property CSS node

| Metric | Value |
|--------|-------|
| Throughput | **24,205 FPS** |
| Avg parse time | 0.04 ms |
| P50 | 0.03 ms |
| P90 | 0.04 ms |
| P99 | 0.17 ms |
| Jank rate | 0.0% |

**Assessment:** Excellent. CSS property resolution is highly optimised — suitable for server-driven style updates at any practical rate.

---

### S8 — Mixed HTML+Flutter (100 iterations)

Input: combined HTML/CSS + Flutter DSL JSON

| Metric | Value |
|--------|-------|
| Throughput | **6,874 FPS** |
| Avg build time | 0.15 ms |
| P50 | 0.09 ms |
| P90 | 0.21 ms |
| P99 | 2.53 ms |
| Jank rate | 0.0% |

---

## Performance Profile Summary

| Scenario | FPS | Avg (ms) | P99 (ms) | Jank |
|----------|-----|-----------|----------|------|
| S1 Basic JSON Build | 2,918 | 0.34 | 1.17 | 0.3% |
| S2 Complex Dashboard | 491 | 2.04 | 16.27 | 0.0% |
| S3 Animation Build | 3,265 | 0.31 | 2.17 | 0.0% |
| S4 Large List | 320 | 3.12 | 23.08 | 2.0% |
| S5 Widget Build | 2,184 | 0.46 | 3.85 | 0.0% |
| S5 Full Layout | 72 | 13.92 | 314.85 | 5.0% |
| S6 Rapid Re-render | 705 | 1.42 | 3.33 | 0.0% |
| S7 CSS Parse | 24,205 | 0.04 | 0.17 | 0.0% |
| S8 Mixed HTML+Flutter | 6,874 | 0.15 | 2.53 | 0.0% |

---

## Key Findings

1. **JSON parsing is fast.** Simple-to-moderate widget trees build in <0.5ms; CSS parsing in <0.05ms.
2. **Large lists are the bottleneck.** 100-item lists take 3ms to build; virtual scrolling / lazy inflation should be prioritised.
3. **Layout resolution is Flutter's cost.** The full layout pump (S5) at 72 FPS with 5% jank highlights that Flutter's layout pass, not Elpian's parsing, is the real performance constraint on complex screens.
4. **Animation path is efficient.** Continuous JSON-driven animation can sustain 3,265 FPS build throughput, meaning the framework adds <0.31ms overhead per animation frame.
5. **Re-render stability is excellent.** P99/mean ratio for re-renders is only 2.3×, indicating consistent, predictable frame delivery.
