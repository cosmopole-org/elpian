import 'package:flutter/material.dart';

import 'examples/bevy_scene_example.dart';
import 'examples/canvas_example.dart';
import 'examples/dom_canvas_logic_example.dart';
import 'examples/enhanced_example.dart';
import 'examples/game_scene_example.dart';
import 'examples/json_stylesheet_demo.dart';
import 'examples/landing_page_example.dart';
import 'examples/ordinary_example.dart';
import 'examples/quickjs_calculator_example.dart';
import 'examples/quickjs_example.dart';
import 'examples/quickjs_whiteboard_example.dart';
import 'examples/vm_example.dart';

void main() {
  runApp(const ElpianExamplesApp());
}

class ElpianExamplesApp extends StatelessWidget {
  const ElpianExamplesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian Examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      ),
      home: const ElpianExamplesHome(),
    );
  }
}

class ElpianExamplesHome extends StatelessWidget {
  const ElpianExamplesHome({super.key});

  @override
  Widget build(BuildContext context) {
    final demos = <_DemoEntry>[
      _DemoEntry(
        title: 'QuickJS Calculator',
        subtitle: 'Expression evaluator powered by QuickJS.',
        pageBuilder: (_) => const QuickJsCalculatorExamplePage(),
      ),
      _DemoEntry(
        title: 'QuickJS Whiteboard',
        subtitle: 'Canvas-style drawing controlled with QuickJS.',
        pageBuilder: (_) => const QuickJsWhiteboardExamplePage(),
      ),
      _DemoEntry(
        title: 'QuickJS Runtime',
        subtitle: 'Counter, clock, and host data runtime demos.',
        pageBuilder: (_) => const QuickJsExamplePage(),
      ),
      _DemoEntry(
        title: 'AST VM',
        subtitle: 'Sandboxed VM examples with host calls.',
        pageBuilder: (_) => const VmExamplePage(),
      ),
      _DemoEntry(
        title: 'DOM + Canvas Logic',
        subtitle: 'Combined DOM and canvas host API contracts.',
        pageBuilder: (_) => const DomCanvasLogicExamplePage(),
      ),
      _DemoEntry(
        title: 'Ordinary UI',
        subtitle: 'Core Elpian JSON rendering baseline demo.',
        pageBuilder: (_) => const ElpianDemoPage(),
      ),
      _DemoEntry(
        title: 'Enhanced UI',
        subtitle: 'Extended widgets and richer interactions.',
        pageBuilder: (_) => const EnhancedDemoPage(),
      ),
      _DemoEntry(
        title: 'Canvas API',
        subtitle: '2D drawing primitives and commands showcase.',
        pageBuilder: (_) => const CanvasDemoPage(),
      ),
      _DemoEntry(
        title: 'JSON Stylesheet',
        subtitle: 'Stylesheet-driven rendering with reusable rules.',
        pageBuilder: (_) => const StylesheetDemoPage(),
      ),
      _DemoEntry(
        title: 'Bevy Scene',
        subtitle: 'Standalone Bevy 3D scene renderer integration.',
        pageBuilder: (_) => const BevySceneExample(),
      ),
      _DemoEntry(
        title: 'Bevy + JSON GUI',
        subtitle: '3D scene embedded in Elpian JSON UI.',
        pageBuilder: (_) => BevySceneJsonGuiExample(),
      ),
      _DemoEntry(
        title: 'Pure Dart 3D Scene',
        subtitle: 'Game scene rendered via pure Dart 3D engine.',
        pageBuilder: (_) => const GameSceneExample(),
      ),
      _DemoEntry(
        title: 'Landing Page',
        subtitle: 'Large JSON page rendering and style composition.',
        pageBuilder: (_) => const LandingPage(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Elpian UI Examples'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: demos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final demo = demos[index];
          return Card(
            child: ListTile(
              title: Text(demo.title),
              subtitle: Text(demo.subtitle),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: demo.pageBuilder,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DemoEntry {
  const _DemoEntry({
    required this.title,
    required this.subtitle,
    required this.pageBuilder,
  });

  final String title;
  final String subtitle;
  final WidgetBuilder pageBuilder;
}
