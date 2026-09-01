import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'examples/canvas_example.dart';
import 'examples/enhanced_example.dart';
import 'examples/json_stylesheet_demo.dart';
import 'examples/landing_page_example.dart';
import 'examples/ordinary_example.dart';
import 'examples/quickjs_calculator_example.dart';
import 'examples/scene3d_example.dart';
import 'examples/showcase_example.dart';
import 'remote_elpian_app.dart';

void main() {
  runApp(const ElpianGameApp());
}

/// Entry point for the Elpian example deployment.
///
/// The main route opens a launcher for the bundled demos. 3D is rendered by an
/// embedded Godot 4 engine through the `Scene3D` widget.
class ElpianGameApp extends StatelessWidget {
  const ElpianGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kIsWeb ? 'Elpian 2D Examples' : 'Elpian Strike Force',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CC9F0),
          brightness: Brightness.dark,
        ),
      ),
      home: kIsWeb
          ? const RemoteElpianApp(fallback: TwoDimensionalExamplesPage())
          : const TpsLauncherPage(),
    );
  }
}

/// Web landing point for the lightweight 2D engine examples.
class TwoDimensionalExamplesPage extends StatelessWidget {
  const TwoDimensionalExamplesPage({super.key});

  static const _examples = <_ExampleEntry>[
    _ExampleEntry(
        'Landing page', 'Responsive JSON-driven product page', LandingPage.new),
    _ExampleEntry(
        'Widget gallery', 'Core Elpian 2D widgets', ElpianDemoPage.new),
    _ExampleEntry('Enhanced UI', 'Styling, layout, and interactions',
        EnhancedDemoPage.new),
    _ExampleEntry(
        'Canvas API', 'Programmatic 2D drawing commands', CanvasDemoPage.new),
    _ExampleEntry('JSON stylesheet', 'Selectors and stylesheet-driven UI',
        StylesheetDemoPage.new),
    _ExampleEntry('QuickJS calculator', 'Scripted 2D application',
        QuickJsCalculatorExamplePage.new),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Elpian 2D Examples'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172033),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: _examples.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final example = _examples[index];
          return Card(
            color: Colors.white,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE5F7FC),
                foregroundColor: const Color(0xFF087E9E),
                child: Text('${index + 1}'),
              ),
              title: Text(example.title),
              subtitle: Text(example.description),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => example.builder()),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ExampleEntry {
  final String title;
  final String description;
  final Widget Function() builder;

  const _ExampleEntry(this.title, this.description, this.builder);
}

/// Landing screen letting the player launch the TPS on either 3D backend.
class TpsLauncherPage extends StatelessWidget {
  const TpsLauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ELPIAN STRIKE FORCE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE6F0FF),
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Downtown · choose a 3D renderer',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8FA3BF), fontSize: 14),
                ),
                const SizedBox(height: 32),
                _LaunchButton(
                  label: 'Showcase — 2D GUI + Scene3D',
                  subtitle: 'The CLI showcase template, running as bytecode',
                  primary: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ShowcaseExample()),
                  ),
                ),
                const SizedBox(height: 16),
                _LaunchButton(
                  label: 'Scene3D — embedded Godot',
                  subtitle: 'Declarative DSL + the reflective controller',
                  primary: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const Scene3DExample()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _LaunchButton({
    required this.label,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4CC9F0);
    return Material(
      color: primary ? accent.withValues(alpha: 0.16) : const Color(0xFF0C121C),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: primary
                  ? accent.withValues(alpha: 0.7)
                  : const Color(0x33FFFFFF),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: primary
                      ? const Color(0xFFE6F0FF)
                      : const Color(0xFFC8D4E4),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style:
                    const TextStyle(color: Color(0xFF7E90A8), fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
