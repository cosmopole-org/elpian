import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

void main() {
  runApp(const BevySceneDemoApp());
}

class BevySceneDemoApp extends StatelessWidget {
  const BevySceneDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian Bevy 3D Scene',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BevyScenePage(),
    );
  }
}

class BevyScenePage extends StatefulWidget {
  const BevyScenePage({super.key});

  @override
  State<BevyScenePage> createState() => _BevyScenePageState();
}

class _BevyScenePageState extends State<BevyScenePage> {
  String? _sceneJson;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadScene();
  }

  Future<void> _loadScene() async {
    try {
      final json = await rootBundle.loadString('lib/example/bevy_scene.json');
      // Validate JSON parses correctly
      jsonDecode(json);
      setState(() {
        _sceneJson = json;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load scene: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF141420),
        title: const Text('Elpian Bevy 3D Scene'),
      ),
      backgroundColor: const Color(0xFF141420),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.red, fontSize: 16),
        ),
      );
    }

    if (_sceneJson == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(320.0, 1280.0);
          final height = constraints.maxHeight.clamp(240.0, 960.0);
          return BevySceneWidget(
            sceneJson: _sceneJson!,
            width: width,
            height: height,
            fps: 60,
            interactive: true,
            backgroundColor: const Color(0xFF141420),
            fit: BoxFit.contain,
          );
        },
      ),
    );
  }
}
