import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

void main() {
  runApp(const BevySceneDemoApp());
}

/// Inline scene JSON used when asset loading fails (e.g. on web/GitHub Pages).
const String _fallbackSceneJson = '''
{
  "world": [
    {
      "type": "environment",
      "ambient_light": {"r": 0.4, "g": 0.4, "b": 0.5, "a": 1.0},
      "ambient_intensity": 0.3
    },
    {
      "type": "camera",
      "camera_type": "Perspective",
      "fov": 60.0,
      "near": 0.1,
      "far": 1000.0,
      "transform": {
        "position": {"x": 3.0, "y": 4.0, "z": 8.0},
        "rotation": {"x": -20.0, "y": 15.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "color": {"r": 1.0, "g": 0.95, "b": 0.9, "a": 1.0},
      "intensity": 1.2,
      "transform": {
        "position": {"x": 5.0, "y": 10.0, "z": 5.0},
        "rotation": {"x": -45.0, "y": 30.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": {"r": 0.3, "g": 0.5, "b": 1.0, "a": 1.0},
      "intensity": 0.8,
      "transform": {
        "position": {"x": -3.0, "y": 3.0, "z": 2.0}
      }
    },
    {
      "type": "mesh3d",
      "mesh": "Cube",
      "material": {
        "base_color": {"r": 0.8, "g": 0.2, "b": 0.2, "a": 1.0},
        "metallic": 0.3,
        "roughness": 0.5
      },
      "transform": {
        "position": {"x": 0.0, "y": 1.0, "z": 0.0},
        "rotation": {"x": 0.0, "y": 45.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
        "duration": 4.0,
        "looping": true,
        "easing": "Linear"
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"shape": "Sphere", "radius": 0.8, "subdivisions": 16},
      "material": {
        "base_color": {"r": 0.2, "g": 0.6, "b": 0.9, "a": 1.0},
        "metallic": 0.8,
        "roughness": 0.2
      },
      "transform": {
        "position": {"x": 3.0, "y": 1.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Bounce", "height": 1.5},
        "duration": 2.0,
        "looping": true,
        "easing": "EaseInOut"
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"shape": "Cylinder", "radius": 0.4, "height": 2.0},
      "material": {
        "base_color": {"r": 0.2, "g": 0.8, "b": 0.3, "a": 1.0},
        "metallic": 0.1,
        "roughness": 0.8
      },
      "transform": {
        "position": {"x": -3.0, "y": 1.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Pulse", "min_scale": 0.8, "max_scale": 1.2},
        "duration": 1.5,
        "looping": true,
        "easing": "EaseInOut"
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"shape": "Plane", "size": 20.0},
      "material": {
        "base_color": {"r": 0.3, "g": 0.3, "b": 0.35, "a": 1.0},
        "metallic": 0.0,
        "roughness": 0.9
      },
      "transform": {
        "position": {"x": 0.0, "y": 0.0, "z": 0.0}
      }
    },
    {
      "type": "group",
      "transform": {
        "position": {"x": 0.0, "y": 0.0, "z": -5.0}
      },
      "children": [
        {
          "type": "mesh3d",
          "mesh": {"shape": "Torus", "radius": 1.0, "tube_radius": 0.3},
          "material": {
            "base_color": {"r": 0.9, "g": 0.6, "b": 0.1, "a": 1.0},
            "metallic": 0.6,
            "roughness": 0.3
          },
          "transform": {
            "position": {"x": 0.0, "y": 2.0, "z": 0.0}
          },
          "animation": {
            "animation_type": {"type": "Rotate", "axis": {"x": 1.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
            "duration": 6.0,
            "looping": true,
            "easing": "Linear"
          }
        }
      ]
    }
  ]
}
''';

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
  String _sceneJson = _fallbackSceneJson;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadScene();
  }

  Future<void> _loadScene() async {
    try {
      final json = await rootBundle.loadString('lib/example/bevy_scene.json');
      jsonDecode(json); // validate
      if (mounted) {
        setState(() {
          _sceneJson = json;
          _loaded = true;
        });
      }
    } catch (_) {
      // Asset loading failed; use the inline fallback scene
      if (mounted) {
        setState(() {
          _loaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141420),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return BevySceneWidget(
            sceneJson: _sceneJson,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
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
