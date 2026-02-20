import 'package:elpian_ui/example/bevy_scene_example.dart';
import 'package:elpian_ui/example/canvas_example.dart';
import 'package:elpian_ui/example/enhanced_example.dart';
import 'package:elpian_ui/example/game_scene_example.dart';
import 'package:elpian_ui/example/json_stylesheet_demo.dart';
import 'package:elpian_ui/example/landing_page_example.dart';
import 'package:elpian_ui/example/ordinary_example.dart';
import 'package:elpian_ui/example/vm_example.dart';
import 'package:flutter/material.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ExamplesHomePage(),
    );
  }
}

class ExamplesHomePage extends StatelessWidget {
  const ExamplesHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Elpian Examples Hub'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Scenes'),
              Tab(text: 'UI'),
              Tab(text: 'VM'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTabList(context, _sceneExamples()),
            _buildTabList(context, _uiExamples()),
            _buildTabList(context, _vmExamples()),
          ],
        ),
      ),
    );
  }

  Widget _buildTabList(BuildContext context, List<_ExampleEntry> entries) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: entries,
            ),
          ),
        ),
      ],
    );
  }

  List<_ExampleEntry> _sceneExamples() => [
        _ExampleEntry(
          title: 'Landing Page (JSON)',
          subtitle: 'Renders lib/example/landing_page.json',
          pageBuilder: () => const LandingPage(),
        ),
        _ExampleEntry(
          title: '3D Game Scene',
          subtitle: 'Large animated fantasy-style scene',
          pageBuilder: () => const GameSceneExample(),
        ),
        _ExampleEntry(
          title: 'Bevy Scene Widget',
          subtitle: 'Standalone Bevy 3D scene widget',
          pageBuilder: () => const BevySceneExample(),
        ),
        _ExampleEntry(
          title: 'Bevy + JSON GUI',
          subtitle: 'Mixed 2D overlay + 3D scene',
          pageBuilder: () => BevySceneJsonGuiExample(),
        ),
      ];

  List<_ExampleEntry> _uiExamples() => [
        _ExampleEntry(
          title: 'Ordinary Example',
          subtitle: 'Core JSON/HTML rendering examples',
          pageBuilder: () => const ElpianDemoPage(),
        ),
        _ExampleEntry(
          title: 'Enhanced Example',
          subtitle: 'Extended component and animation showcase',
          pageBuilder: () => const EnhancedDemoPage(),
        ),
        _ExampleEntry(
          title: 'JSON Stylesheet Demo',
          subtitle: 'Demonstrates stylesheet parser and usage',
          pageBuilder: () => const StylesheetDemoPage(),
        ),
        _ExampleEntry(
          title: 'Canvas API Demo',
          subtitle: 'Canvas shapes, paths, gradients, transforms',
          pageBuilder: () => const CanvasDemoPage(),
        ),
      ];

  List<_ExampleEntry> _vmExamples() => [
        _ExampleEntry(
          title: 'AST VM Sandboxes',
          subtitle: 'Interactive VM demos built from AST JSON programs',
          pageBuilder: () => const VmExamplePage(),
        ),
      ];
}

class _ExampleEntry extends StatelessWidget {
  const _ExampleEntry({
    required this.title,
    required this.subtitle,
    required this.pageBuilder,
  });

  final String title;
  final String subtitle;
  final Widget Function() pageBuilder;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => pageBuilder()),
        );
      },
    );
  }
}
