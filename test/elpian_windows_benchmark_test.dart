// Elpian Windows Performance Benchmark Suite
// Run with: flutter test test/elpian_windows_benchmark_test.dart -v
// Uses the real ElpianEngine — no simulation, no Future.delayed stubs.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── shared JSON payloads ────────────────────────────────────────────────────

const _kColors = [
  '#667eea', '#764ba2', '#f093fb', '#4facfe',
  '#00f2fe', '#43e97b', '#fa709a', '#fee140',
];

Map<String, dynamic> _dashboardJson(int cards) => {
  'type': 'Column',
  'style': {'padding': '20', 'backgroundColor': '#f0f2f5'},
  'children': [
    {
      'type': 'Container',
      'style': {
        'backgroundColor': '#667eea',
        'padding': '24',
        'borderRadius': '12',
        'marginBottom': '24',
      },
      'children': [
        {
          'type': 'Text',
          'props': {'text': 'Performance Dashboard'},
          'style': {'fontSize': 28, 'fontWeight': 'bold', 'color': '#ffffff'},
        },
      ],
    },
    {
      'type': 'Row',
      'style': {'justifyContent': 'space-between', 'flexWrap': 'wrap'},
      'children': List.generate(
        cards,
        (i) => {
          'type': 'Card',
          'style': {'borderRadius': '12', 'padding': '20', 'margin': '8'},
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Metric ${i + 1}'},
              'style': {'fontSize': 16, 'fontWeight': '600'},
            },
            {
              'type': 'Text',
              'props': {'text': '${(i + 1) * 1237}'},
              'style': {
                'fontSize': 32,
                'fontWeight': '700',
                'color': _kColors[i % _kColors.length],
              },
            },
            {
              'type': 'LinearProgressIndicator',
              'props': {'value': (i + 1) / cards},
            },
          ],
        },
      ),
    },
  ],
};

Map<String, dynamic> _animJson(int tick) => {
  'type': 'Row',
  'style': {'flexWrap': 'wrap', 'backgroundColor': '#1A1A2E'},
  'children': List.generate(
    12,
    (i) => {
      'type': 'AnimatedContainer',
      'style': {
        'width': 100.0 + math.sin(tick * 0.05 + i) * 40.0,
        'height': 80.0,
        'backgroundColor': _kColors[i % _kColors.length],
        'borderRadius': 12.0,
        'margin': '4',
        'duration': 200, // milliseconds integer — valid JSON
      },
      'children': [
        {
          'type': 'Text',
          'props': {'text': 'Anim ${i + 1}'},
          'style': {'color': '#ffffff', 'fontSize': 12},
        },
      ],
    },
  ),
};

Map<String, dynamic> _inputJson(int i) => {
  'type': 'Column',
  'children': [
    {
      'type': 'TextField',
      'props': {'value': 'Input $i ${'x' * (i % 40)}'},
      'style': {'marginBottom': '16'},
    },
    {
      'type': 'Text',
      'props': {'text': 'Processed: ${i * 15} chars'},
      'style': {'fontSize': 14, 'color': '#666'},
    },
  ],
};

Map<String, dynamic> _listJson(int n) => {
  'type': 'Column',
  'style': {'backgroundColor': '#ffffff'},
  'children': List.generate(
    n,
    (i) => {
      'type': 'div',
      'style': {
        'padding': '12',
        'backgroundColor': i.isEven ? '#ffffff' : '#f5f5f5',
        'borderBottom': '1px solid #e0e0e0',
      },
      'children': [
        {
          'type': 'Text',
          'props': {'text': 'Item ${i + 1} — subtitle text for list entry'},
          'style': {'fontSize': 14},
        },
      ],
    },
  ),
};

// ─── stats helper ────────────────────────────────────────────────────────────

class _Stats {
  _Stats(List<double> raw) {
    sorted = List.of(raw)..sort();
    avg   = sorted.reduce((a, b) => a + b) / sorted.length;
    p50   = sorted[(sorted.length * 0.50).round().clamp(0, sorted.length - 1)];
    p90   = sorted[(sorted.length * 0.90).round().clamp(0, sorted.length - 1)];
    p99   = sorted[(sorted.length * 0.99).round().clamp(0, sorted.length - 1)];
    worst = sorted.last;
    jankPct = sorted.where((t) => t > 16.67).length / sorted.length * 100;
    fps     = 1000.0 / avg;
  }

  late List<double> sorted;
  late double avg, p50, p90, p99, worst, jankPct, fps;

  void report(String label) {
    // ignore: avoid_print
    print('\n╔══ $label');
    // ignore: avoid_print
    print('║ FPS equiv : ${fps.toStringAsFixed(1)}');
    // ignore: avoid_print
    print('║ Avg       : ${avg.toStringAsFixed(3)} ms');
    // ignore: avoid_print
    print('║ P50/P90/P99: ${p50.toStringAsFixed(2)} / ${p90.toStringAsFixed(2)} / ${p99.toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print('║ Worst     : ${worst.toStringAsFixed(2)} ms   Jank: ${jankPct.toStringAsFixed(1)} %');
    // ignore: avoid_print
    print('╚══════════════════════════════════════════════════════════════');
  }

  Map<String, dynamic> toJson(String scenario) => {
    'scenario'      : scenario,
    'fps'           : double.parse(fps.toStringAsFixed(1)),
    'avg_build_ms'  : double.parse(avg.toStringAsFixed(3)),
    'p50_ms'        : double.parse(p50.toStringAsFixed(2)),
    'p90_ms'        : double.parse(p90.toStringAsFixed(2)),
    'p99_ms'        : double.parse(p99.toStringAsFixed(2)),
    'worst_frame_ms': double.parse(worst.toStringAsFixed(2)),
    'jank_rate_pct' : double.parse(jankPct.toStringAsFixed(1)),
    'total_frames'  : sorted.length,
  };
}

// ─── test suite ──────────────────────────────────────────────────────────────

void main() {
  final engine   = ElpianEngine();
  final allResults = <Map<String, dynamic>>[];

  // S1 — Complex Dashboard Build (24 cards)
  test('S1: Complex Dashboard Build', () {
    const N = 100;
    final times = <double>[];
    for (var i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(_dashboardJson(24));
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
    final s = _Stats(times);
    s.report('S1 – Complex Dashboard Build (24 cards, $N iters)');
    allResults.add(s.toJson('S1_ComplexDashboard'));
    expect(s.avg, lessThan(50));
  });

  // S2 — Animation Build Throughput (12 items, 150 frames)
  test('S2: Animation Build Throughput', () {
    const N = 150;
    final times = <double>[];
    for (var i = 0; i < N; i++) {
        final sw = Stopwatch()..start();
      engine.renderFromJson(_animJson(i));
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
    final s = _Stats(times);
    s.report('S2 – Animation Build (12 animated items, $N iters)');
    allResults.add(s.toJson('S2_AnimationBuild'));
    expect(s.fps, greaterThan(30));
  });

  // S3 — Interactive Input Simulation (200 renders)
  test('S3: Interactive Input Simulation', () {
    const N = 200;
    final times = <double>[];
    for (var i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(_inputJson(i));
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
    final s = _Stats(times);
    s.report('S3 – Interactive Input Simulation ($N iters)');
    allResults.add(s.toJson('S3_InteractiveInput'));
    expect(s.avg, lessThan(10));
  });

  // S4 — Scroll / Large List Build (200 items, 100 builds)
  test('S4: Scroll Performance (List Build)', () {
    const N = 100;
    const itemCount = 200;
    final times = <double>[];
    for (var i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(_listJson(itemCount));
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
    final s = _Stats(times);
    s.report('S4 – Scroll/List Build ($itemCount items, $N iters)');
    allResults.add(s.toJson('S4_ScrollPerformance'));
    expect(s.avg, lessThan(50));
  });

  // S5 — JSON Parse / CSS Throughput (500 complex nodes)
  test('S5: JSON Parse Throughput', () {
    const N = 500;
    final times = <double>[];
    final style = {
      'padding': '16 24',
      'backgroundColor': '#667eea',
      'color': 'white',
      'fontSize': 18,
      'fontWeight': 'bold',
      'borderRadius': 8,
      'display': 'flex',
      'justifyContent': 'space-between',
      'width': 300,
      'height': 60,
    };
    for (var i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson({
        'type': 'Container',
        'style': style,
        'children': [
          {'type': 'Text', 'props': {'text': 'Node $i'}, 'style': style},
        ],
      });
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
    final s = _Stats(times);
    s.report('S5 – JSON/CSS Parse Throughput ($N iters)');
    allResults.add(s.toJson('S5_JSONParseThroughput'));
    expect(s.fps, greaterThan(1000));
  });

  // S6 — Memory baseline (1000-node tree construction)
  test('S6: Memory Efficiency (1000-node tree)', () {
    const N = 20;
    final times = <double>[];
    final largePayload = {
      'type': 'Column',
      'children': List.generate(
        1000,
        (i) => {'type': 'Text', 'props': {'text': 'Item $i'}, 'style': {'color': _kColors[i % _kColors.length]}},
      ),
    };
    for (var i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(largePayload);
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
    final s = _Stats(times);
    s.report('S6 – Memory / 1000-node tree ($N iters)');
    allResults.add(s.toJson('S6_MemoryEfficiency'));
  });

  // Summary + JSON write
  test('SUMMARY: Write JSON results', () {
    // ignore: avoid_print
    print('\n╔══════════════════════════════════════════════════════════════╗');
    // ignore: avoid_print
    print('║       ELPIAN WINDOWS BENCHMARK — SUMMARY                    ║');
    // ignore: avoid_print
    print('╠══════════════════════════════════════════════════════════════╣');
    for (final r in allResults) {
      final s = r['scenario'].toString().padRight(26);
      final f = r['fps'].toString().padLeft(8);
      final a = r['avg_build_ms'].toString().padLeft(7);
      final j = r['jank_rate_pct'].toString().padLeft(5);
      // ignore: avoid_print
      print('║  $s │ $f fps │ $a ms │ jank $j % ║');
    }
    // ignore: avoid_print
    print('╚══════════════════════════════════════════════════════════════╝');

    final outDir  = Directory('benchmarks/reports');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outFile = File('benchmarks/reports/elpian_windows_results.json');
    outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'suite'     : 'Elpian Windows Benchmark',
      'runner'    : 'flutter test (Dart VM, real ElpianEngine)',
      'timestamp' : DateTime.now().toIso8601String(),
      'benchmarks': allResults,
    }));
    // ignore: avoid_print
    print('[BENCH] Results written to ${outFile.path}');
  });
}
