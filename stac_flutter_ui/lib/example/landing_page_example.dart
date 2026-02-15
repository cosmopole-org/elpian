import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';
import 'package:stac_flutter_ui/example/bevy_scene_example.dart';
void main() {
  runApp(const LandingPageApp());
}

class LandingPageApp extends StatelessWidget {
  const LandingPageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STAC Flutter UI - Landing Page',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BevySceneExample(),
    );
  }
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final StacEngine _engine = StacEngine();
  Widget? _renderedPage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLandingPage();
  }

  Future<void> _loadLandingPage() async {
    try {
      final jsonString = await rootBundle.loadString(
        'lib/example/landing_page.json',
      );
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      setState(() {
        _renderedPage = _engine.renderFromJson(json);
        _error = null;
      });
    } catch (e) {
      // Fallback: use inline JSON definition
      setState(() {
        _renderedPage = _engine.renderFromJson(_buildInlineLandingPage());
        _error = null;
      });
    }
  }

  Map<String, dynamic> _buildInlineLandingPage() {
    return {
      'type': 'div',
      'key': 'landing-root',
      'style': {
        'backgroundColor': '#0F172A',
      },
      'children': [
        // Header
        {
          'type': 'header',
          'style': {
            'backgroundColor': 'rgba(15,23,42,0.95)',
            'padding': '16 24',
            'display': 'flex',
            'flexDirection': 'row',
            'justifyContent': 'space-between',
            'alignItems': 'center',
          },
          'children': [
            {
              'type': 'div',
              'style': {
                'display': 'flex',
                'flexDirection': 'row',
                'alignItems': 'center',
                'gap': 12,
              },
              'children': [
                {
                  'type': 'Icon',
                  'props': {'icon': 'rocket_launch'},
                  'style': {'fontSize': 28, 'color': '#818CF8'},
                },
                {
                  'type': 'span',
                  'props': {'text': 'Elpian'},
                  'style': {
                    'color': 'white',
                    'fontSize': 22,
                    'fontWeight': 'bold',
                    'letterSpacing': 1.2,
                  },
                },
              ],
            },
            {
              'type': 'nav',
              'style': {
                'gap': 32,
                'justifyContent': 'center',
                'alignItems': 'center',
              },
              'children': [
                {'type': 'a', 'props': {'text': 'Features', 'href': '#features'}, 'style': {'color': '#94A3B8', 'fontSize': 14}},
                {'type': 'a', 'props': {'text': 'Pricing', 'href': '#pricing'}, 'style': {'color': '#94A3B8', 'fontSize': 14}},
                {'type': 'a', 'props': {'text': 'Docs', 'href': '#docs'}, 'style': {'color': '#94A3B8', 'fontSize': 14}},
                {'type': 'a', 'props': {'text': 'Blog', 'href': '#blog'}, 'style': {'color': '#94A3B8', 'fontSize': 14}},
              ],
            },
            {
              'type': 'div',
              'style': {'display': 'flex', 'flexDirection': 'row', 'gap': 12, 'alignItems': 'center'},
              'children': [
                {'type': 'Button', 'props': {'text': 'Sign In'}, 'style': {'backgroundColor': 'rgba(255,255,255,0.08)', 'color': '#E2E8F0', 'padding': '8 20', 'borderRadius': 8}},
                {'type': 'Button', 'props': {'text': 'Get Started'}, 'style': {'backgroundColor': '#6366F1', 'color': 'white', 'padding': '8 20', 'borderRadius': 8}},
              ],
            },
          ],
        },
        // Hero Section
        {
          'type': 'section',
          'style': {'padding': '80 24 60 24'},
          'children': [
            {
              'type': 'h1',
              'props': {'text': 'Build Beautiful UIs From JSON & HTML'},
              'style': {'color': 'white', 'fontSize': 48, 'fontWeight': 'bold', 'textAlign': 'center', 'margin': '0 0 24 0', 'letterSpacing': -1.2},
            },
            {
              'type': 'p',
              'props': {'text': 'A high-performance Flutter rendering engine that transforms JSON definitions and HTML+CSS into native Flutter widgets.'},
              'style': {'color': '#94A3B8', 'fontSize': 18, 'textAlign': 'center', 'lineHeight': 1.6, 'margin': '0 0 40 0'},
            },
            {
              'type': 'div',
              'style': {'display': 'flex', 'flexDirection': 'row', 'gap': 16, 'justifyContent': 'center'},
              'children': [
                {'type': 'Button', 'props': {'text': 'Start Building Free'}, 'style': {'backgroundColor': '#6366F1', 'color': 'white', 'padding': '14 32', 'borderRadius': 10}},
                {'type': 'Button', 'props': {'text': 'View Docs'}, 'style': {'backgroundColor': 'rgba(255,255,255,0.06)', 'color': '#E2E8F0', 'padding': '14 32', 'borderRadius': 10}},
              ],
            },
          ],
        },
        // Stats
        {
          'type': 'section',
          'style': {'padding': '40 24', 'backgroundColor': '#1E293B'},
          'children': [
            {
              'type': 'Row',
              'style': {'justifyContent': 'space-evenly'},
              'children': [
                {
                  'type': 'Container',
                  'style': {'padding': '20'},
                  'children': [
                    {'type': 'Text', 'props': {'text': '76+'}, 'style': {'fontSize': 42, 'fontWeight': 'bold', 'color': '#818CF8'}},
                    {'type': 'Text', 'props': {'text': 'Widgets'}, 'style': {'fontSize': 14, 'color': '#94A3B8'}},
                  ],
                },
                {
                  'type': 'Container',
                  'style': {'padding': '20'},
                  'children': [
                    {'type': 'Text', 'props': {'text': '150+'}, 'style': {'fontSize': 42, 'fontWeight': 'bold', 'color': '#34D399'}},
                    {'type': 'Text', 'props': {'text': 'CSS Props'}, 'style': {'fontSize': 14, 'color': '#94A3B8'}},
                  ],
                },
                {
                  'type': 'Container',
                  'style': {'padding': '20'},
                  'children': [
                    {'type': 'Text', 'props': {'text': '40+'}, 'style': {'fontSize': 42, 'fontWeight': 'bold', 'color': '#FBBF24'}},
                    {'type': 'Text', 'props': {'text': 'Events'}, 'style': {'fontSize': 14, 'color': '#94A3B8'}},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _renderedPage != null
              ? SingleChildScrollView(child: _renderedPage!)
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
