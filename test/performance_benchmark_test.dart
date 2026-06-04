// Elpian UI — Performance Benchmark Suite
// Run with: flutter test test/performance_benchmark_test.dart -v
// No device / chromedriver required — uses the Dart VM test runner.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JSON payloads
// ─────────────────────────────────────────────────────────────────────────────

const _kColors = [
  '#4CAF50', '#2196F3', '#F44336', '#FF9800',
  '#9C27B0', '#00BCD4', '#E91E63', '#607D8B',
];

final Map<String, dynamic> _simpleJson = {
  'type': 'Column',
  'style': {'padding': '16', 'backgroundColor': '#F5F5F5'},
  'children': [
    {'type': 'Text', 'props': {'text': 'Elpian Benchmark'}, 'style': {'fontSize': 24, 'fontWeight': 'bold', 'color': '#2196F3'}},
    {'type': 'Card', 'style': {'margin': '8'}, 'children': [
      {'type': 'Container', 'style': {'padding': '16'}, 'children': [
        {'type': 'Text', 'props': {'text': 'Card content'}}
      ]}
    ]},
    {'type': 'Row', 'style': {'justifyContent': 'space-around', 'margin': '16 0'}, 'children': [
      {'type': 'Button', 'props': {'text': 'A'}, 'style': {'backgroundColor': '#4CAF50'}},
      {'type': 'Button', 'props': {'text': 'B'}, 'style': {'backgroundColor': '#F44336'}},
      {'type': 'Button', 'props': {'text': 'C'}, 'style': {'backgroundColor': '#2196F3'}},
    ]},
  ],
};

Map<String, dynamic> _dashboardJson(int cards) => {
  'type': 'div',
  'style': {'padding': '20', 'backgroundColor': '#FAFAFA'},
  'children': [
    {'type': 'header', 'style': {'backgroundColor': '#3F51B5', 'padding': '16', 'borderRadius': 8}, 'children': [
      {'type': 'h2', 'props': {'text': 'Dashboard'}, 'style': {'color': 'white'}},
    ]},
    {'type': 'Row', 'style': {'justifyContent': 'space-between', 'flexWrap': 'wrap'}, 'children': [
      for (int i = 0; i < cards; i++)
        {'type': 'Card', 'style': {'margin': '8', 'backgroundColor': _kColors[i % _kColors.length], 'width': 140}, 'children': [
          {'type': 'Container', 'style': {'padding': '16'}, 'children': [
            {'type': 'Text', 'props': {'text': '${(i + 1) * 123}'}, 'style': {'fontSize': 28, 'fontWeight': 'bold', 'color': 'white'}},
            {'type': 'Text', 'props': {'text': 'Metric ${i + 1}'}, 'style': {'color': 'white', 'fontSize': 14}},
          ]},
        ]},
    ]},
  ],
};

Map<String, dynamic> _animatedJson(int tick) => {
  'type': 'Column',
  'style': {'padding': '8', 'backgroundColor': '#1A1A2E'},
  'children': [
    for (int i = 0; i < 10; i++)
      {'type': 'AnimatedContainer', 'style': {
        'width': 200.0 + math.sin(tick * 0.1 + i) * 80.0,
        'height': 40.0,
        'backgroundColor': _kColors[i % _kColors.length],
        'borderRadius': 8.0,
        'margin': '4',
        'duration': 200,
      }, 'children': [
        {'type': 'Text', 'props': {'text': 'Animated ${i + 1}'}, 'style': {'color': 'white', 'fontSize': 12}},
      ]},
  ],
};

Map<String, dynamic> _listJson(int n) => {
  'type': 'Column',
  'style': {'backgroundColor': '#FFFFFF'},
  'children': [
    for (int i = 0; i < n; i++)
      {'type': 'div', 'style': {'padding': '12', 'backgroundColor': i.isEven ? '#FFF' : '#F5F5F5'}, 'children': [
        {'type': 'Row', 'style': {'justifyContent': 'space-between'}, 'children': [
          {'type': 'Column', 'children': [
            {'type': 'Text', 'props': {'text': 'Item ${i + 1}'}, 'style': {'fontWeight': 'bold'}},
            {'type': 'Text', 'props': {'text': 'Subtitle ${i + 1}'}, 'style': {'color': '#666', 'fontSize': 13}},
          ]},
          {'type': 'Container', 'style': {'backgroundColor': _kColors[i % _kColors.length], 'borderRadius': 12, 'padding': '4 8'}, 'children': [
            {'type': 'Text', 'props': {'text': '${i % 5 + 1}'}, 'style': {'color': 'white', 'fontSize': 12}},
          ]},
        ]},
      ]},
  ],
};

// ─────────────────────────────────────────────────────────────────────────────
// Statistics helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Stats {
  _Stats(List<double> raw) {
    assert(raw.isNotEmpty);
    sorted = List.of(raw)..sort();
    avg = sorted.reduce((a, b) => a + b) / sorted.length;
    p50 = sorted[(sorted.length * 0.50).round().clamp(0, sorted.length - 1)];
    p90 = sorted[(sorted.length * 0.90).round().clamp(0, sorted.length - 1)];
    p99 = sorted[(sorted.length * 0.99).round().clamp(0, sorted.length - 1)];
    worst = sorted.last;
    jankPct = sorted.where((t) => t > 16.67).length / sorted.length * 100;
    fps = 1000 / avg;
  }

  late List<double> sorted;
  late double avg, p50, p90, p99, worst, jankPct, fps;

  String get fpsStr   => fps.toStringAsFixed(1);
  String get avgStr   => avg.toStringAsFixed(2);
  String get p50Str   => p50.toStringAsFixed(2);
  String get p90Str   => p90.toStringAsFixed(2);
  String get p99Str   => p99.toStringAsFixed(2);
  String get worstStr => worst.toStringAsFixed(2);
  String get jankStr  => jankPct.toStringAsFixed(1);

  void print_(String label) {
    // ignore: avoid_print
    printLine(label);
    printLine('  FPS (theoretical)  : $fpsStr');
    printLine('  Avg build time     : $avgStr ms');
    printLine('  P50 / P90 / P99    : $p50Str / $p90Str / $p99Str ms');
    printLine('  Worst build        : $worstStr ms');
    printLine('  Jank rate (>16.7ms): $jankStr %');
    printLine('  Sample count       : ${sorted.length}');
  }

  Map<String, dynamic> toJson(String scenario) => {
    'scenario': scenario,
    'fps': double.parse(fpsStr),
    'avg_build_ms': double.parse(avgStr),
    'p50_ms': double.parse(p50Str),
    'p90_ms': double.parse(p90Str),
    'p99_ms': double.parse(p99Str),
    'worst_frame_ms': double.parse(worstStr),
    'jank_rate_pct': double.parse(jankStr),
    'total_frames': sorted.length,
  };
}

// ignore: avoid_print
void printLine(String s) => print(s);

// ─────────────────────────────────────────────────────────────────────────────
// The benchmark suite
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  final allResults = <Map<String, dynamic>>[];

  // ── S1: Basic JSON Build Throughput ───────────────────────────────────────
  test('S1: Basic JSON Build Throughput', () {
    final engine = ElpianEngine();
    const N = 300;
    final times = <double>[];

    for (int i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(_simpleJson);
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }

    final stats = _Stats(times);
    stats.print_('[BENCH] S1_BasicJsonBuild');
    allResults.add(stats.toJson('S1_BasicJsonBuild'));
  });

  // ── S2: Complex Dashboard Build ────────────────────────────────────────────
  test('S2: Complex Dashboard Build', () {
    final engine = ElpianEngine();
    const N = 100;
    final times = <double>[];

    for (int i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(_dashboardJson(24));
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }

    final stats = _Stats(times);
    stats.print_('[BENCH] S2_ComplexDashboard');
    allResults.add(stats.toJson('S2_ComplexDashboard'));
  });

  // ── S3: Animation JSON Build (sinusoidal updates) ─────────────────────────
  test('S3: Animation JSON Build Throughput', () {
    final engine = ElpianEngine();
    const N = 200;
    final times = <double>[];

    for (int i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(_animatedJson(i));
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }

    final stats = _Stats(times);
    stats.print_('[BENCH] S3_AnimationBuild');
    allResults.add(stats.toJson('S3_AnimationBuild'));
  });

  // ── S4: Large List Build ──────────────────────────────────────────────────
  test('S4: Large List Build (100 items)', () {
    final engine = ElpianEngine();
    const N = 50;
    final times = <double>[];

    for (int i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(_listJson(100));
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }

    final stats = _Stats(times);
    stats.print_('[BENCH] S4_ListBuild');
    allResults.add(stats.toJson('S4_ListBuild'));
  });

  // ── S5: Widget Pump + Layout (WidgetTester) ────────────────────────────────
  testWidgets('S5: Widget Pump Performance', (tester) async {
    // The dashboard lays out a non-wrapping Row of fixed-width cards that
    // exceeds the default 800x600 test viewport; flutter_test treats the
    // resulting overflow as an error. This is a throughput benchmark, not a
    // layout test, so give it a surface large enough to lay out cleanly.
    await tester.binding.setSurfaceSize(const Size(2400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = ElpianEngine();
    const N = 60;
    final buildTimes = <double>[];
    final pumpTimes  = <double>[];

    for (int i = 0; i < N; i++) {
      // Build time
      var sw = Stopwatch()..start();
      final widget = engine.renderFromJson(i < N ~/ 2 ? _simpleJson : _dashboardJson(8));
      sw.stop();
      buildTimes.add(sw.elapsedMicroseconds / 1000.0);

      // Pump time (layout + paint in test renderer)
      sw = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: widget))),
      );
      sw.stop();
      pumpTimes.add(sw.elapsedMicroseconds / 1000.0);
    }

    final buildStats = _Stats(buildTimes);
    final pumpStats  = _Stats(pumpTimes);

    buildStats.print_('[BENCH] S5_WidgetBuild (no layout)');
    pumpStats.print_('[BENCH] S5_PumpLayout (build+layout)');

    allResults.add(buildStats.toJson('S5_WidgetBuild'));
    allResults.add(pumpStats.toJson('S5_PumpLayout'));
  });

  // ── S6: Rapid Re-render (setState simulation) ─────────────────────────────
  testWidgets('S6: Rapid Re-render Storm', (tester) async {
    final engine = ElpianEngine();
    int counter = 0;
    const N = 150;
    final pumpTimes = <double>[];
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
                  {'type': 'Text', 'props': {'text': 'Counter: $counter'}, 'style': {'fontSize': 32}},
                  {'type': 'Container', 'style': {
                    'width': 20.0 + (counter % 100) * 2.0,
                    'height': 24.0,
                    'backgroundColor': _kColors[counter % _kColors.length],
                  }},
                ],
              };
              return engine.renderFromJson(payload);
            },
          ),
        ),
      ),
    );

    for (int i = 0; i < N; i++) {
      counter = i;
      final sw = Stopwatch()..start();
      setStateRef(() {});
      await tester.pump(Duration.zero);
      sw.stop();
      pumpTimes.add(sw.elapsedMicroseconds / 1000.0);
    }

    final stats = _Stats(pumpTimes);
    stats.print_('[BENCH] S6_RapidRerender');
    allResults.add(stats.toJson('S6_RapidRerender'));
  });

  // ── S7: CSS Parsing Throughput ─────────────────────────────────────────────
  test('S7: CSS Style Parse Throughput', () {
    const N = 500;
    final times = <double>[];

    final complexStyle = {
      'padding': '16 24 16 24',
      'margin': '8 0',
      'backgroundColor': '#3F51B5',
      'color': 'white',
      'fontSize': 18,
      'fontWeight': 'bold',
      'borderRadius': 8,
      'display': 'flex',
      'flexDirection': 'row',
      'justifyContent': 'space-between',
      'alignItems': 'center',
      'width': 300,
      'height': 60,
      'border': '2px solid rgba(255,255,255,0.3)',
      'boxShadow': '0 4px 8px rgba(0,0,0,0.2)',
      'textDecoration': 'none',
      'letterSpacing': 1,
      'lineHeight': 1.5,
      'opacity': 0.95,
    };

    final engine = ElpianEngine();
    for (int i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson({
        'type': 'Container',
        'style': complexStyle,
        'children': [
          {'type': 'Text', 'props': {'text': 'Styled Node $i'}, 'style': complexStyle},
        ],
      });
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }

    final stats = _Stats(times);
    stats.print_('[BENCH] S7_CSSParseThroughput');
    allResults.add(stats.toJson('S7_CSSParseThroughput'));
  });

  // ── S8: Mixed HTML+Flutter Widget Build ────────────────────────────────────
  test('S8: Mixed HTML+Flutter Widget Build', () {
    final engine = ElpianEngine();
    const N = 100;
    final times = <double>[];

    final mixedJson = {
      'type': 'div',
      'style': {'padding': '20', 'backgroundColor': '#FAFAFA'},
      'children': [
        {'type': 'h1', 'props': {'text': 'Mixed Rendering'}, 'style': {'color': '#E91E63'}},
        {'type': 'Column', 'children': [
          {'type': 'Card', 'style': {'margin': '8'}, 'children': [
            {'type': 'p', 'props': {'text': 'Paragraph inside a Flutter Card'}, 'style': {'fontSize': 14}},
          ]},
          {'type': 'ul', 'children': [
            for (int i = 0; i < 10; i++)
              {'type': 'li', 'props': {'text': 'Mixed item $i'}},
          ]},
        ]},
        {'type': 'Row', 'style': {'justifyContent': 'space-between'}, 'children': [
          {'type': 'button', 'props': {'text': 'HTML btn'}, 'style': {'backgroundColor': '#9C27B0'}},
          {'type': 'Button', 'props': {'text': 'Flutter btn'}, 'style': {'backgroundColor': '#2196F3'}},
        ]},
      ],
    };

    for (int i = 0; i < N; i++) {
      final sw = Stopwatch()..start();
      engine.renderFromJson(mixedJson);
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }

    final stats = _Stats(times);
    stats.print_('[BENCH] S8_MixedHtmlFlutter');
    allResults.add(stats.toJson('S8_MixedHtmlFlutter'));
  });

  // ── Summary + JSON output ─────────────────────────────────────────────────
  test('SUMMARY: Print results and write JSON', () {
    printLine('\n╔══════════════════════════════════════════════════════════════════╗');
    printLine('║           ELPIAN PERFORMANCE BENCHMARK — SUMMARY                ║');
    printLine('╠══════════════════════════════════════════════════════════════════╣');
    printLine('║  Scenario                  │  FPS   │ Avg(ms) │ Jank%  │ P99   ║');
    printLine('╠══════════════════════════════════════════════════════════════════╣');
    for (final r in allResults) {
      final s = r['scenario'].toString().padRight(26);
      final f = r['fps'].toString().padLeft(6);
      final a = r['avg_build_ms'].toString().padLeft(7);
      final j = r['jank_rate_pct'].toString().padLeft(6);
      final p = r['p99_ms'].toString().padLeft(5);
      printLine('║  $s │ $f │ $a │ $j │ $p ║');
    }
    printLine('╚══════════════════════════════════════════════════════════════════╝');

    // Write JSON output to benchmarks/reports/
    final outDir = Directory('benchmarks/reports');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outFile = File('benchmarks/reports/elpian_results.json');
    final report = {
      'suite': 'Elpian UI Performance Benchmarks',
      'runner': 'flutter test (Dart VM)',
      'timestamp': DateTime.now().toIso8601String(),
      'benchmarks': allResults,
    };
    outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    printLine('\n[BENCH] Results written to ${outFile.path}');
  });
}
