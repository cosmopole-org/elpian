/// Example demonstrating the BevySceneWidget integrated with the JSON GUI renderer.
///
/// Shows how to:
/// 1. Embed a 3D scene in a Flutter widget tree
/// 2. Define scenes using JSON (compatible with the Bevy renderer schema)
/// 3. Combine 2D UI overlays with 3D scene rendering
/// 4. Use the ElpianEngine to render mixed 2D/3D interfaces from JSON
library;

import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// Example 3D scene JSON compatible with both the Bevy renderer and Flutter bridge.
const String exampleSceneJson = '''
{
  "world": [
    {
      "type": "environment",
      "ambient_light": {"r": 0.4, "g": 0.4, "b": 0.5, "a": 1.0},
      "ambient_intensity": 0.3,
      "fog_enabled": true,
      "fog_color": {"r": 0.1, "g": 0.1, "b": 0.15, "a": 1.0},
      "fog_distance": 50.0
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
    }
  ]
}
''';

/// Example: Standalone BevySceneWidget usage
class BevySceneExample extends StatelessWidget {
  const BevySceneExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bevy 3D Scene')),
      body: Center(
        child: BevySceneWidget(
          sceneJson: exampleSceneJson,
          width: 800,
          height: 600,
          fps: 60,
          interactive: true,
          backgroundColor: const Color(0xFF141420),
        ),
      ),
    );
  }
}

/// Example: BevySceneWidget used via JSON GUI renderer (ElpianEngine)
class BevySceneJsonGuiExample extends StatelessWidget {
  BevySceneJsonGuiExample({super.key});

  final ElpianEngine engine = ElpianEngine();

  /// JSON GUI definition that includes a 3D scene alongside 2D UI elements.
  /// This demonstrates full compatibility with the existing JSON GUI system.
  static final Map<String, dynamic> mixedUiJson = {
    "type": "Column",
    "children": [
      {
        "type": "Container",
        "props": {
          "style": {
            "padding": "16",
            "backgroundColor": "rgba(20,20,30,1.0)",
          },
        },
        "children": [
          {
            "type": "Text",
            "props": {
              "text": "3D Scene with JSON GUI Overlay",
              "style": {
                "fontSize": 24,
                "color": "rgba(255,255,255,1.0)",
                "fontWeight": "bold",
              },
            },
          },
        ],
      },
      {
        "type": "BevyScene",
        "props": {
          "width": 800,
          "height": 500,
          "fps": 60,
          "interactive": true,
          "scene": {
            "world": [
              {
                "type": "camera",
                "camera_type": "Perspective",
                "transform": {
                  "position": {"x": 0, "y": 5, "z": 10},
                  "rotation": {"x": -20, "y": 0, "z": 0},
                },
              },
              {
                "type": "light",
                "light_type": "Directional",
                "intensity": 1.0,
                "transform": {
                  "rotation": {"x": -45, "y": 30, "z": 0},
                },
              },
              {
                "type": "mesh3d",
                "mesh": "Cube",
                "material": {
                  "base_color": {"r": 0.9, "g": 0.3, "b": 0.1},
                  "roughness": 0.4,
                },
                "transform": {
                  "position": {"x": 0, "y": 1, "z": 0},
                },
                "animation": {
                  "animation_type": {
                    "type": "Rotate",
                    "axis": {"x": 0, "y": 1, "z": 0},
                    "degrees": 360,
                  },
                  "duration": 3.0,
                  "looping": true,
                },
              },
            ],
          },
        },
      },
      {
        "type": "Row",
        "props": {
          "style": {
            "padding": "12",
            "justifyContent": "spaceEvenly",
            "backgroundColor": "rgba(30,30,40,1.0)",
          },
        },
        "children": [
          {
            "type": "Button",
            "props": {
              "text": "Reset Camera",
              "style": {"backgroundColor": "rgba(60,60,80,1.0)"},
            },
          },
          {
            "type": "Button",
            "props": {
              "text": "Toggle Animation",
              "style": {"backgroundColor": "rgba(60,60,80,1.0)"},
            },
          },
        ],
      },
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JSON GUI + 3D Scene')),
      body: engine.renderFromJson(mixedUiJson),
    );
  }
}
