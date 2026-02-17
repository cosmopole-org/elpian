/// Feature-rich 3D game scene example using the pure-Dart 3D engine.
///
/// Demonstrates: multiple mesh types, animations, materials with textures,
/// particle systems, orbit camera, sky gradient, fog, groups, and physics.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/src/scene3d/game_scene_widget.dart';

/// A rich 3D game scene showcasing all engine features.
const String gameSceneJson = '''
{
  "world": [
    {
      "type": "environment",
      "ambient_light": {"r": 0.35, "g": 0.35, "b": 0.45},
      "ambient_intensity": 0.25,
      "sky_color_top": {"r": 0.15, "g": 0.25, "b": 0.55},
      "sky_color_bottom": {"r": 0.6, "g": 0.7, "b": 0.9},
      "fog_type": "linear",
      "fog_color": {"r": 0.5, "g": 0.55, "b": 0.7},
      "fog_near": 15.0,
      "fog_distance": 60.0
    },
    {
      "type": "camera",
      "camera_type": "Perspective",
      "fov": 55.0,
      "near": 0.1,
      "far": 200.0,
      "transform": {
        "position": {"x": 6.0, "y": 5.0, "z": 12.0},
        "rotation": {"x": -18.0, "y": 20.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "color": {"r": 1.0, "g": 0.95, "b": 0.85},
      "intensity": 1.3,
      "transform": {
        "rotation": {"x": -50.0, "y": 35.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": {"r": 1.0, "g": 0.6, "b": 0.2},
      "intensity": 1.5,
      "range": 12.0,
      "transform": {
        "position": {"x": 0.0, "y": 4.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": {"r": 0.3, "g": 0.5, "b": 1.0},
      "intensity": 0.8,
      "range": 15.0,
      "transform": {
        "position": {"x": -5.0, "y": 3.0, "z": 4.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "ground",
      "mesh": {"shape": "Plane", "size": 30.0},
      "material": {
        "base_color": {"r": 0.25, "g": 0.3, "b": 0.2},
        "roughness": 0.95,
        "metallic": 0.0,
        "texture": "checkerboard",
        "texture_color2": {"r": 0.2, "g": 0.25, "b": 0.18},
        "texture_scale": 4.0
      },
      "transform": {
        "position": {"x": 0.0, "y": 0.0, "z": 0.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "crystal_tower",
      "mesh": {"shape": "Cylinder", "radius": 0.3, "height": 4.0, "segments": 6},
      "material": {
        "base_color": {"r": 0.4, "g": 0.7, "b": 0.9, "a": 0.85},
        "metallic": 0.9,
        "roughness": 0.1,
        "emissive": {"r": 0.1, "g": 0.2, "b": 0.4},
        "emissive_strength": 2.0,
        "alpha_mode": "blend"
      },
      "transform": {
        "position": {"x": 0.0, "y": 2.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
        "duration": 8.0,
        "looping": true,
        "easing": "Linear"
      }
    },

    {
      "type": "mesh3d",
      "name": "floating_sphere",
      "mesh": {"shape": "Sphere", "radius": 0.7, "subdivisions": 20},
      "material": {
        "base_color": {"r": 0.9, "g": 0.3, "b": 0.15},
        "metallic": 0.7,
        "roughness": 0.2,
        "emissive": {"r": 0.3, "g": 0.05, "b": 0.0},
        "emissive_strength": 1.5
      },
      "transform": {
        "position": {"x": 0.0, "y": 5.5, "z": 0.0}
      },
      "animation": [
        {
          "animation_type": {"type": "Bounce", "height": 0.8},
          "duration": 3.0,
          "looping": true,
          "easing": "EaseInOut"
        },
        {
          "animation_type": {"type": "Rotate", "axis": {"x": 0.3, "y": 1.0, "z": 0.1}, "degrees": 360.0},
          "duration": 5.0,
          "looping": true,
          "easing": "Linear"
        }
      ]
    },

    {
      "type": "group",
      "name": "stone_ring",
      "transform": {
        "position": {"x": 0.0, "y": 0.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
        "duration": 20.0,
        "looping": true,
        "easing": "Linear"
      },
      "children": [
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.5, "b": 0.55},
            "roughness": 0.8,
            "metallic": 0.1
          },
          "transform": {
            "position": {"x": 5.0, "y": 0.75, "z": 0.0},
            "scale": {"x": 0.8, "y": 1.5, "z": 0.8}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.55, "g": 0.5, "b": 0.5},
            "roughness": 0.85,
            "metallic": 0.05
          },
          "transform": {
            "position": {"x": -5.0, "y": 0.6, "z": 0.0},
            "scale": {"x": 0.7, "y": 1.2, "z": 0.7}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.52, "b": 0.5},
            "roughness": 0.82,
            "metallic": 0.08
          },
          "transform": {
            "position": {"x": 0.0, "y": 0.9, "z": 5.0},
            "scale": {"x": 0.9, "y": 1.8, "z": 0.9}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.48, "g": 0.48, "b": 0.52},
            "roughness": 0.9,
            "metallic": 0.05
          },
          "transform": {
            "position": {"x": 0.0, "y": 0.5, "z": -5.0},
            "scale": {"x": 0.6, "y": 1.0, "z": 0.6}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.52, "g": 0.5, "b": 0.48},
            "roughness": 0.87,
            "metallic": 0.06
          },
          "transform": {
            "position": {"x": 3.54, "y": 0.65, "z": 3.54},
            "scale": {"x": 0.75, "y": 1.3, "z": 0.75}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.48, "b": 0.52},
            "roughness": 0.88,
            "metallic": 0.07
          },
          "transform": {
            "position": {"x": -3.54, "y": 0.7, "z": -3.54},
            "scale": {"x": 0.7, "y": 1.4, "z": 0.7}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.53, "g": 0.51, "b": 0.5},
            "roughness": 0.83,
            "metallic": 0.09
          },
          "transform": {
            "position": {"x": 3.54, "y": 0.55, "z": -3.54},
            "scale": {"x": 0.65, "y": 1.1, "z": 0.65}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.53, "b": 0.51},
            "roughness": 0.86,
            "metallic": 0.04
          },
          "transform": {
            "position": {"x": -3.54, "y": 0.8, "z": 3.54},
            "scale": {"x": 0.85, "y": 1.6, "z": 0.85}
          }
        }
      ]
    },

    {
      "type": "mesh3d",
      "name": "torus_portal",
      "mesh": {"shape": "Torus", "major_radius": 2.0, "tube_radius": 0.15, "radial_segments": 24, "tubular_segments": 32},
      "material": {
        "base_color": {"r": 0.8, "g": 0.7, "b": 0.2},
        "metallic": 0.95,
        "roughness": 0.1,
        "emissive": {"r": 0.3, "g": 0.25, "b": 0.05},
        "emissive_strength": 1.0
      },
      "transform": {
        "position": {"x": -6.0, "y": 3.0, "z": -2.0},
        "rotation": {"x": 90.0, "y": 0.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 0.0, "z": 1.0}, "degrees": 360.0},
        "duration": 6.0,
        "looping": true,
        "easing": "Linear"
      }
    },

    {
      "type": "mesh3d",
      "name": "pyramid_ancient",
      "mesh": {"shape": "Pyramid", "base": 3.0, "height": 2.5},
      "material": {
        "base_color": {"r": 0.7, "g": 0.6, "b": 0.4},
        "roughness": 0.7,
        "metallic": 0.05,
        "texture": "noise",
        "texture_scale": 3.0
      },
      "transform": {
        "position": {"x": 7.0, "y": 0.0, "z": -5.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "capsule_pod",
      "mesh": {"shape": "Capsule", "radius": 0.5, "height": 1.2, "segments": 16},
      "material": {
        "base_color": {"r": 0.2, "g": 0.8, "b": 0.4},
        "metallic": 0.6,
        "roughness": 0.3
      },
      "transform": {
        "position": {"x": -4.0, "y": 1.5, "z": 5.0}
      },
      "animation": {
        "animation_type": {"type": "Pulse", "min_scale": 0.85, "max_scale": 1.15},
        "duration": 2.5,
        "looping": true,
        "easing": "Sine"
      }
    },

    {
      "type": "mesh3d",
      "name": "wedge_ramp",
      "mesh": {"shape": "Wedge", "width": 2.0, "height": 1.5, "depth": 3.0},
      "material": {
        "base_color": {"r": 0.6, "g": 0.35, "b": 0.2},
        "roughness": 0.6,
        "metallic": 0.15,
        "texture": "stripes",
        "texture_color2": {"r": 0.5, "g": 0.3, "b": 0.15},
        "texture_scale": 2.0
      },
      "transform": {
        "position": {"x": 5.0, "y": 0.0, "z": 6.0},
        "rotation": {"x": 0.0, "y": -30.0, "z": 0.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "icosphere_gem",
      "mesh": {"shape": "IcoSphere", "radius": 0.6, "subdivisions": 3},
      "material": {
        "base_color": {"r": 0.3, "g": 0.1, "b": 0.8},
        "metallic": 1.0,
        "roughness": 0.05,
        "emissive": {"r": 0.1, "g": 0.0, "b": 0.3},
        "emissive_strength": 2.0
      },
      "transform": {
        "position": {"x": -7.0, "y": 2.0, "z": -6.0}
      },
      "animation": [
        {
          "animation_type": {"type": "Bounce", "height": 1.0},
          "duration": 2.0,
          "looping": true,
          "easing": "Bounce"
        },
        {
          "animation_type": {"type": "Rotate", "axis": {"x": 1.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
          "duration": 3.0,
          "looping": true,
          "easing": "Linear"
        }
      ]
    },

    {
      "type": "mesh3d",
      "name": "wireframe_sphere",
      "mesh": {"shape": "Sphere", "radius": 1.5, "subdivisions": 8},
      "material": {
        "base_color": {"r": 0.0, "g": 1.0, "b": 0.5, "a": 0.6},
        "wireframe": true,
        "unlit": true,
        "alpha_mode": "blend"
      },
      "transform": {
        "position": {"x": 0.0, "y": 5.5, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.2, "y": 1.0, "z": 0.3}, "degrees": 360.0},
        "duration": 12.0,
        "looping": true,
        "easing": "Linear"
      }
    },

    {
      "type": "mesh3d",
      "name": "cone_spire",
      "mesh": {"shape": "Cone", "radius": 0.6, "height": 3.0, "segments": 12},
      "material": {
        "base_color": {"r": 0.7, "g": 0.2, "b": 0.5},
        "metallic": 0.4,
        "roughness": 0.4
      },
      "transform": {
        "position": {"x": 8.0, "y": 0.0, "z": 3.0}
      }
    },

    {
      "type": "particles",
      "name": "fire_particles",
      "transform": {
        "position": {"x": 0.0, "y": 4.2, "z": 0.0}
      },
      "emitter": {
        "shape": "point",
        "emit_rate": 30,
        "lifetime": 1.5,
        "start_color": {"r": 1.0, "g": 0.8, "b": 0.2},
        "end_color": {"r": 1.0, "g": 0.2, "b": 0.0},
        "start_size": 0.15,
        "end_size": 0.02,
        "start_alpha": 0.9,
        "end_alpha": 0.0,
        "gravity": {"x": 0.0, "y": 1.5, "z": 0.0},
        "spread": 25.0,
        "speed": 1.5,
        "speed_variance": 0.5,
        "max_particles": 100
      }
    },

    {
      "type": "particles",
      "name": "sparkle_ring",
      "transform": {
        "position": {"x": -6.0, "y": 3.0, "z": -2.0}
      },
      "emitter": {
        "shape": "ring",
        "emit_rate": 15,
        "lifetime": 2.0,
        "start_color": {"r": 1.0, "g": 0.9, "b": 0.5},
        "end_color": {"r": 0.5, "g": 0.3, "b": 1.0},
        "start_size": 0.08,
        "end_size": 0.0,
        "start_alpha": 1.0,
        "end_alpha": 0.0,
        "gravity": {"x": 0.0, "y": 0.5, "z": 0.0},
        "spread": 60.0,
        "speed": 0.8,
        "max_particles": 60
      }
    }
  ]
}
''';

/// Standalone example page.
class GameSceneExample extends StatelessWidget {
  const GameSceneExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141420),
      appBar: AppBar(
        title: const Text('3D Game Scene'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Center(
        child: GameSceneWidget(
          sceneJson: gameSceneJson,
          fps: 60,
          interactive: true,
          backgroundColor: const Color(0xFF141420),
        ),
      ),
    );
  }
}
