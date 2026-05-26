import 'dart:math' as math;

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark helpers
// ─────────────────────────────────────────────────────────────────────────────

class BenchmarkResult {
  BenchmarkResult({
    required this.scenario,
    required this.fps,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.p50Ms,
    required this.p90Ms,
    required this.p99Ms,
    required this.jankRate,
    required this.totalFrames,
    required this.worstFrameMs,
    required this.firstFrameMs,
    required this.durationMs,
  });

  final String scenario;
  final double fps;
  final double avgBuildMs;
  final double avgRasterMs;
  final double p50Ms;
  final double p90Ms;
  final double p99Ms;
  final double jankRate;
  final int totalFrames;
  final double worstFrameMs;
  final double firstFrameMs;
  final int durationMs;

  Map<String, dynamic> toJson() => {
        'scenario': scenario,
        'fps': fps,
        'avg_build_ms': avgBuildMs,
        'avg_raster_ms': avgRasterMs,
        'p50_ms': p50Ms,
        'p90_ms': p90Ms,
        'p99_ms': p99Ms,
        'jank_rate_pct': jankRate,
        'total_frames': totalFrames,
        'worst_frame_ms': worstFrameMs,
        'first_frame_ms': firstFrameMs,
        'duration_ms': durationMs,
      };

  @override
  String toString() {
    final buf = StringBuffer();
    buf.writeln('  Scenario       : $scenario');
    buf.writeln('  FPS            : ${fps.toStringAsFixed(1)}');
    buf.writeln('  Avg build      : ${avgBuildMs.toStringAsFixed(2)} ms');
    buf.writeln('  Avg raster     : ${avgRasterMs.toStringAsFixed(2)} ms');
    buf.writeln('  P50 / P90 / P99: '
        '${p50Ms.toStringAsFixed(2)} / '
        '${p90Ms.toStringAsFixed(2)} / '
        '${p99Ms.toStringAsFixed(2)} ms');
    buf.writeln('  Jank rate      : ${jankRate.toStringAsFixed(1)} %');
    buf.writeln('  Worst frame    : ${worstFrameMs.toStringAsFixed(2)} ms');
    buf.writeln('  First frame    : ${firstFrameMs.toStringAsFixed(2)} ms');
    buf.writeln('  Total frames   : $totalFrames over ${durationMs} ms');
    return buf.toString();
  }
}

BenchmarkResult _analyse(
  String scenario,
  List<FrameTiming> timings,
  double firstFrameMs,
  int durationMs,
) {
  if (timings.isEmpty) {
    return BenchmarkResult(
      scenario: scenario,
      fps: 0,
      avgBuildMs: 0,
      avgRasterMs: 0,
      p50Ms: 0,
      p90Ms: 0,
      p99Ms: 0,
      jankRate: 0,
      totalFrames: 0,
      worstFrameMs: 0,
      firstFrameMs: firstFrameMs,
      durationMs: durationMs,
    );
  }

  final buildUs = timings.map((t) => t.buildDuration.inMicroseconds.toDouble()).toList()..sort();
  final rasterUs = timings.map((t) => t.rasterDuration.inMicroseconds.toDouble()).toList();
  final totalUs = timings.map((t) => t.totalSpan.inMicroseconds.toDouble()).toList()..sort();

  final avgBuildMs = buildUs.reduce((a, b) => a + b) / buildUs.length / 1000.0;
  final avgRasterMs = rasterUs.reduce((a, b) => a + b) / rasterUs.length / 1000.0;

  double percentile(List<double> sorted, double p) {
    final idx = ((sorted.length - 1) * p / 100).round().clamp(0, sorted.length - 1);
    return sorted[idx] / 1000.0;
  }

  final p50 = percentile(totalUs, 50);
  final p90 = percentile(totalUs, 90);
  final p99 = percentile(totalUs, 99);
  final worst = totalUs.last / 1000.0;
  final jankFrames = totalUs.where((t) => t > 16667).length;
  final jankRate = jankFrames / totalUs.length * 100.0;
  final fps = durationMs > 0 ? timings.length / (durationMs / 1000.0) : 0.0;

  return BenchmarkResult(
    scenario: scenario,
    fps: fps,
    avgBuildMs: avgBuildMs,
    avgRasterMs: avgRasterMs,
    p50Ms: p50,
    p90Ms: p90,
    p99Ms: p99,
    jankRate: jankRate,
    totalFrames: timings.length,
    worstFrameMs: worst,
    firstFrameMs: firstFrameMs,
    durationMs: durationMs,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON payloads used across scenarios
// ─────────────────────────────────────────────────────────────────────────────

final Map<String, dynamic> _simpleJson = {
  'type': 'Column',
  'style': {'padding': '16', 'backgroundColor': '#F5F5F5'},
  'children': [
    {
      'type': 'Text',
      'props': {'text': 'Elpian Benchmark'},
      'style': {'fontSize': 24, 'fontWeight': 'bold', 'color': '#2196F3'},
    },
    {
      'type': 'Card',
      'style': {'margin': '8'},
      'children': [
        {
          'type': 'Container',
          'style': {'padding': '16'},
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Card content inside an Elpian widget'},
            },
          ],
        },
      ],
    },
    {
      'type': 'Row',
      'style': {'justifyContent': 'space-around', 'margin': '16 0'},
      'children': [
        {'type': 'Button', 'props': {'text': 'Action A'}, 'style': {'backgroundColor': '#4CAF50'}},
        {'type': 'Button', 'props': {'text': 'Action B'}, 'style': {'backgroundColor': '#F44336'}},
        {'type': 'Button', 'props': {'text': 'Action C'}, 'style': {'backgroundColor': '#2196F3'}},
      ],
    },
  ],
};

Map<String, dynamic> _complexDashboardJson(int cardCount) => {
      'type': 'div',
      'style': {'padding': '20', 'backgroundColor': '#FAFAFA'},
      'children': [
        {
          'type': 'header',
          'style': {
            'backgroundColor': '#3F51B5',
            'padding': '16',
            'margin': '0 0 16 0',
            'borderRadius': 8,
          },
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Dashboard'},
              'style': {'color': 'white'},
            },
          ],
        },
        {
          'type': 'section',
          'children': [
            {
              'type': 'h3',
              'props': {'text': 'Statistics'},
            },
            {
              'type': 'Row',
              'style': {'justifyContent': 'space-between', 'flexWrap': 'wrap'},
              'children': List.generate(
                cardCount,
                (i) => {
                  'type': 'Card',
                  'style': {
                    'margin': '8',
                    'backgroundColor': _cardColors[i % _cardColors.length],
                    'width': 140,
                  },
                  'children': [
                    {
                      'type': 'Container',
                      'style': {'padding': '16'},
                      'children': [
                        {
                          'type': 'Text',
                          'props': {'text': '${(i + 1) * 123}'},
                          'style': {'fontSize': 28, 'fontWeight': 'bold', 'color': 'white'},
                        },
                        {
                          'type': 'Text',
                          'props': {'text': 'Metric ${i + 1}'},
                          'style': {'color': 'white', 'fontSize': 14},
                        },
                      ],
                    },
                  ],
                },
              ),
            },
          ],
        },
      ],
    };

const _cardColors = [
  '#4CAF50', '#2196F3', '#F44336', '#FF9800',
  '#9C27B0', '#00BCD4', '#E91E63', '#607D8B',
];

Map<String, dynamic> _animatedJson(int index) => {
      'type': 'Column',
      'style': {'padding': '8', 'backgroundColor': '#1A1A2E'},
      'children': List.generate(
        10,
        (i) => {
          'type': 'AnimatedContainer',
          'style': {
            'width': 200.0 + math.sin(index * 0.1 + i) * 80.0,
            'height': 40.0,
            'backgroundColor': _animColors[i % _animColors.length],
            'borderRadius': 8.0,
            'margin': '4',
            'duration': 200,
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Animated item ${i + 1}'},
              'style': {'color': 'white', 'fontSize': 12},
            },
          ],
        },
      ),
    };

const _animColors = [
  '#E91E63', '#9C27B0', '#3F51B5', '#2196F3',
  '#00BCD4', '#4CAF50', '#FF9800', '#F44336',
  '#795548', '#607D8B',
];

Map<String, dynamic> _canvasJson() => {
      'type': 'Canvas',
      'style': {'width': 400, 'height': 300},
      'props': {
        'commands': [
          {'type': 'fillStyle', 'value': '#1A1A2E'},
          {'type': 'fillRect', 'x': 0, 'y': 0, 'width': 400, 'height': 300},
          ...List.generate(20, (i) {
            final x = (i * 20) % 400;
            final y = (i * 15) % 300;
            return [
              {'type': 'beginPath'},
              {'type': 'arc', 'x': x, 'y': y, 'radius': 15, 'startAngle': 0, 'endAngle': 6.28},
              {'type': 'fillStyle', 'value': _animColors[i % _animColors.length]},
              {'type': 'fill'},
              {'type': 'beginPath'},
              {'type': 'moveTo', 'x': x, 'y': y},
              {'type': 'lineTo', 'x': x + 30, 'y': y + 30},
              {'type': 'strokeStyle', 'value': 'white'},
              {'type': 'lineWidth', 'value': 2},
              {'type': 'stroke'},
            ];
          }).expand((e) => e),
          {'type': 'font', 'value': 'bold 18px sans-serif'},
          {'type': 'fillStyle', 'value': 'white'},
          {'type': 'fillText', 'text': 'Canvas Benchmark', 'x': 120, 'y': 280},
        ],
      },
    };

Map<String, dynamic> _listJson(int count) => {
      'type': 'Column',
      'style': {'backgroundColor': '#FFFFFF'},
      'children': List.generate(
        count,
        (i) => {
          'type': 'div',
          'style': {
            'padding': '12',
            'borderBottom': '1px solid #E0E0E0',
            'backgroundColor': i.isEven ? '#FFFFFF' : '#F5F5F5',
          },
          'children': [
            {
              'type': 'Row',
              'style': {'justifyContent': 'space-between', 'alignItems': 'center'},
              'children': [
                {
                  'type': 'Column',
                  'children': [
                    {
                      'type': 'Text',
                      'props': {'text': 'List Item ${i + 1}'},
                      'style': {'fontWeight': 'bold', 'fontSize': 16},
                    },
                    {
                      'type': 'Text',
                      'props': {'text': 'Subtitle for item number ${i + 1}'},
                      'style': {'color': '#666', 'fontSize': 13},
                    },
                  ],
                },
                {
                  'type': 'Badge',
                  'props': {'label': '${i % 5 + 1}'},
                  'style': {
                    'backgroundColor': _cardColors[i % _cardColors.length],
                    'color': 'white',
                    'borderRadius': 12,
                    'padding': '4 8',
                  },
                },
              ],
            },
          ],
        },
      ),
    };

// ─────────────────────────────────────────────────────────────────────────────
// Actual test entry point
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final List<BenchmarkResult> allResults = [];

  // ── Scenario 1: Basic JSON Rendering ──────────────────────────────────────
  testWidgets('S1: Basic JSON Rendering', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    final engine = ElpianEngine();
    final sw = Stopwatch()..start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: engine.renderFromJson(_simpleJson)),
        ),
      ),
    );

    final firstFrameMs = sw.elapsedMilliseconds.toDouble();
    final startMs = sw.elapsedMilliseconds;
    timings.clear();

    await tester.pump(const Duration(seconds: 4));
    sw.stop();

    final durationMs = sw.elapsedMilliseconds - startMs;
    SchedulerBinding.instance.removeTimingsCallback(timings.addAll);

    final result = _analyse('S1_BasicRendering', timings, firstFrameMs, durationMs);
    allResults.add(result);
    debugPrint('[BENCH] $result');
  });

  // ── Scenario 2: Complex Dashboard Layout ─────────────────────────────────
  testWidgets('S2: Complex Dashboard Layout', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    final engine = ElpianEngine();
    final sw = Stopwatch()..start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: engine.renderFromJson(_complexDashboardJson(24)),
          ),
        ),
      ),
    );

    final firstFrameMs = sw.elapsedMilliseconds.toDouble();
    final startMs = sw.elapsedMilliseconds;
    timings.clear();

    await tester.pump(const Duration(seconds: 4));
    sw.stop();

    final durationMs = sw.elapsedMilliseconds - startMs;
    SchedulerBinding.instance.removeTimingsCallback(timings.addAll);

    final result = _analyse('S2_ComplexDashboard', timings, firstFrameMs, durationMs);
    allResults.add(result);
    debugPrint('[BENCH] $result');
  });

  // ── Scenario 3: Animation Smoothness ─────────────────────────────────────
  testWidgets('S3: Animation Smoothness', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    final engine = ElpianEngine();
    int frameIndex = 0;
    final sw = Stopwatch()..start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: engine.renderFromJson(_animatedJson(frameIndex)),
              );
            },
          ),
        ),
      ),
    );

    final firstFrameMs = sw.elapsedMilliseconds.toDouble();
    final startMs = sw.elapsedMilliseconds;
    timings.clear();

    // Drive 120 animation frames
    for (int i = 0; i < 120; i++) {
      frameIndex = i;
      await tester.pump(const Duration(milliseconds: 16));
    }

    sw.stop();
    final durationMs = sw.elapsedMilliseconds - startMs;
    SchedulerBinding.instance.removeTimingsCallback(timings.addAll);

    final result = _analyse('S3_AnimationSmoothness', timings, firstFrameMs, durationMs);
    allResults.add(result);
    debugPrint('[BENCH] $result');
  });

  // ── Scenario 4: Canvas Drawing ────────────────────────────────────────────
  testWidgets('S4: Canvas Drawing', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    final engine = ElpianEngine();
    final sw = Stopwatch()..start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: engine.renderFromJson(_canvasJson())),
        ),
      ),
    );

    final firstFrameMs = sw.elapsedMilliseconds.toDouble();
    final startMs = sw.elapsedMilliseconds;
    timings.clear();

    await tester.pump(const Duration(seconds: 4));
    sw.stop();

    final durationMs = sw.elapsedMilliseconds - startMs;
    SchedulerBinding.instance.removeTimingsCallback(timings.addAll);

    final result = _analyse('S4_CanvasDrawing', timings, firstFrameMs, durationMs);
    allResults.add(result);
    debugPrint('[BENCH] $result');
  });

  // ── Scenario 5: Long List Scroll ──────────────────────────────────────────
  testWidgets('S5: Long List Scroll', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    final engine = ElpianEngine();
    final sw = Stopwatch()..start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: engine.renderFromJson(_listJson(100))),
        ),
      ),
    );

    final firstFrameMs = sw.elapsedMilliseconds.toDouble();
    final startMs = sw.elapsedMilliseconds;
    timings.clear();

    // Simulate scroll gestures
    final scrollFinder = find.byType(SingleChildScrollView);
    for (int i = 0; i < 20; i++) {
      await tester.drag(scrollFinder, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (int i = 0; i < 20; i++) {
      await tester.drag(scrollFinder, const Offset(0, 200));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(seconds: 1));

    sw.stop();
    final durationMs = sw.elapsedMilliseconds - startMs;
    SchedulerBinding.instance.removeTimingsCallback(timings.addAll);

    final result = _analyse('S5_ListScroll', timings, firstFrameMs, durationMs);
    allResults.add(result);
    debugPrint('[BENCH] $result');
  });

  // ── Scenario 6: Widget Build Throughput ───────────────────────────────────
  testWidgets('S6: Widget Build Throughput', (tester) async {
    final engine = ElpianEngine();
    const iterations = 100;
    final buildTimesMs = <double>[];

    for (int i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      final payload = i.isEven ? _simpleJson : _complexDashboardJson(8);
      engine.renderFromJson(payload);
      sw.stop();
      buildTimesMs.add(sw.elapsedMicroseconds / 1000.0);
    }

    buildTimesMs.sort();
    final avg = buildTimesMs.reduce((a, b) => a + b) / buildTimesMs.length;
    final p50 = buildTimesMs[(buildTimesMs.length * 0.50).round().clamp(0, buildTimesMs.length - 1)];
    final p90 = buildTimesMs[(buildTimesMs.length * 0.90).round().clamp(0, buildTimesMs.length - 1)];
    final p99 = buildTimesMs[(buildTimesMs.length * 0.99).round().clamp(0, buildTimesMs.length - 1)];
    final throughput = 1000.0 / avg;

    debugPrint('[BENCH-S6] Widget Build Throughput');
    debugPrint('  Avg build time : ${avg.toStringAsFixed(3)} ms');
    debugPrint('  P50 / P90 / P99: '
        '${p50.toStringAsFixed(3)} / ${p90.toStringAsFixed(3)} / ${p99.toStringAsFixed(3)} ms');
    debugPrint('  Throughput     : ${throughput.toStringAsFixed(1)} builds/sec');
    debugPrint('  Iterations     : $iterations');

    allResults.add(BenchmarkResult(
      scenario: 'S6_BuildThroughput',
      fps: throughput,
      avgBuildMs: avg,
      avgRasterMs: 0,
      p50Ms: p50,
      p90Ms: p90,
      p99Ms: p99,
      jankRate: buildTimesMs.where((t) => t > 16.67).length / iterations * 100,
      totalFrames: iterations,
      worstFrameMs: buildTimesMs.last,
      firstFrameMs: buildTimesMs.first,
      durationMs: (avg * iterations).round(),
    ));
  });

  // ── Scenario 7: Rapid State Updates (re-render storm) ────────────────────
  testWidgets('S7: Rapid Re-render Storm', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);

    final engine = ElpianEngine();
    int counter = 0;
    final sw = Stopwatch()..start();
    late void Function(void Function()) setStateRef;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setStateRef = setState;
              final payload = {
                'type': 'Column',
                'style': {'padding': '16'},
                'children': [
                  {
                    'type': 'Text',
                    'props': {'text': 'Counter: $counter'},
                    'style': {'fontSize': 32, 'fontWeight': 'bold'},
                  },
                  {
                    'type': 'Text',
                    'props': {'text': 'Updates: $counter / 200'},
                    'style': {'fontSize': 16, 'color': '#666'},
                  },
                  {
                    'type': 'Container',
                    'style': {
                      'width': 20.0 + (counter % 100) * 2.0,
                      'height': 24.0,
                      'backgroundColor': _cardColors[counter % _cardColors.length],
                      'borderRadius': 4,
                      'margin': '8 0',
                    },
                  },
                ],
              };
              return SingleChildScrollView(child: engine.renderFromJson(payload));
            },
          ),
        ),
      ),
    );

    final firstFrameMs = sw.elapsedMilliseconds.toDouble();
    final startMs = sw.elapsedMilliseconds;
    timings.clear();

    for (int i = 0; i < 200; i++) {
      counter = i;
      setStateRef(() {});
      await tester.pump(const Duration(milliseconds: 8));
    }

    sw.stop();
    final durationMs = sw.elapsedMilliseconds - startMs;
    SchedulerBinding.instance.removeTimingsCallback(timings.addAll);

    final result = _analyse('S7_RapidRerender', timings, firstFrameMs, durationMs);
    allResults.add(result);
    debugPrint('[BENCH] $result');
  });

  // ── Summary ───────────────────────────────────────────────────────────────
  testWidgets('Summary: Print all results as JSON', (tester) async {
    final jsonLines = allResults.map((r) => r.toJson().toString()).join(',\n  ');
    debugPrint('[BENCH-RESULTS-JSON][\n  $jsonLines\n]');

    // Also print a human-readable table
    debugPrint('\n╔══════════════════════════════════════════════════╗');
    debugPrint('║      ELPIAN BENCHMARK RESULTS SUMMARY           ║');
    debugPrint('╠══════════════════════════════════════════════════╣');
    for (final r in allResults) {
      debugPrint('  ${r.scenario.padRight(25)} FPS: ${r.fps.toStringAsFixed(1).padLeft(6)} '
          '| Avg: ${r.avgBuildMs.toStringAsFixed(2).padLeft(6)} ms '
          '| Jank: ${r.jankRate.toStringAsFixed(1).padLeft(5)} %');
    }
    debugPrint('╚══════════════════════════════════════════════════╝');

    binding.reportData = {
      'benchmarks': allResults.map((r) => r.toJson()).toList(),
    };
  });
}
