import 'dart:async';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

/// Embedded Godot 3D through the `Scene3D` widget.
///
/// Shows both halves of the API:
///   * the **declarative** JSON DSL builds the starting world;
///   * the **imperative** controller drives it afterwards with the full
///     reflective Godot API.
///
/// Where no Godot engine is present (web, desktop, or a build without the
/// `elpian_godot` plugin) the widget draws its placeholder and everything else
/// on this screen still works.
class Scene3DExample extends StatefulWidget {
  const Scene3DExample({super.key});

  @override
  State<Scene3DExample> createState() => _Scene3DExampleState();
}

class _Scene3DExampleState extends State<Scene3DExample> {
  final GodotSceneController _controller = GodotSceneController();
  Timer? _spin;
  double _angle = 0;
  bool _lightsOn = true;

  /// The starting world, declaratively.
  static const Map<String, Object?> _scene = {
    'environment': {'bg': '#0d1117', 'ambient': '#8894b0', 'ambientEnergy': 0.7},
    'camera': {'position': [0, 3, 9], 'rotation': [-15, 0, 0], 'fov': 55},
    'lights': [
      {
        'type': 'directional',
        'id': 'key',
        'energy': 1.4,
        'shadow': true,
        'rotation': [-50, -30, 0],
      },
    ],
    'nodes': [
      {
        'type': 'node',
        'id': 'pivot',
        'children': [
          {
            'type': 'mesh',
            'id': 'ring',
            'shape': 'torus',
            'innerRadius': 1.1,
            'outerRadius': 1.8,
            'color': '#6699ff',
            'metallic': 0.4,
            'roughness': 0.25,
            'position': [0, 1.2, 0],
          },
          {
            'type': 'mesh',
            'id': 'core',
            'shape': 'sphere',
            'radius': 0.7,
            'color': '#ffb347',
            'emission': '#ff8800',
            'emissionEnergy': 1.5,
            'position': [0, 1.2, 0],
          },
        ],
      },
      {
        'type': 'mesh',
        'id': 'floor',
        'shape': 'plane',
        'width': 14,
        'depth': 14,
        'color': '#151b24',
        'roughness': 0.9,
      },
    ],
  };

  @override
  void initState() {
    super.initState();
    // Drive the world imperatively once it exists. One op per tick, batched
    // into the frame's single crossing.
    _spin = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final pivot = _controller.node('pivot');
      if (pivot == null) return;
      _angle = (_angle + 0.8) % 360;
      pivot.set('rotation_degrees', Vector3(0, _angle, 0));
    });
  }

  @override
  void dispose() {
    _spin?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _toggleLights() {
    final key = _controller.node('key');
    if (key == null) return;
    setState(() => _lightsOn = !_lightsOn);
    key.set('light_energy', GFloat(_lightsOn ? 1.4 : 0.15));
  }

  /// Anything the DSL does not express is one `create` away — the bridge is
  /// reflective, so any ClassDB class works.
  void _addCrate() {
    final godot = _controller.godot;
    godot.beginBatch();
    final crate = godot.g3.mesh('box', options: {
      'size': 0.6,
      'color': const GodotColor(0.55, 0.8, 0.6, 1),
      'roughness': 0.5,
      'position': [
        (_angle % 7) - 3.5,
        3.0,
        ((_angle * 1.7) % 5) - 2.5,
      ],
    });
    godot.mount(crate);
    godot.endBatch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F16),
      appBar: AppBar(
        title: const Text('Scene3D — embedded Godot'),
        backgroundColor: const Color(0xFF121822),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Scene3D(
              controller: _controller,
              initialScene: _scene,
              onReady: (scene) => debugPrint(
                'scene ready: ${scene.nodesById.keys.join(', ')}',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton.icon(
                  onPressed: _toggleLights,
                  icon: Icon(_lightsOn ? Icons.light_mode : Icons.dark_mode),
                  label: Text(_lightsOn ? 'Dim key light' : 'Raise key light'),
                ),
                OutlinedButton.icon(
                  onPressed: _addCrate,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Drop a crate'),
                ),
              ],
            ),
          ),
          if (!_controller.isLive)
            const Padding(
              padding: EdgeInsets.only(bottom: 16, left: 16, right: 16),
              child: Text(
                'No Godot engine on this platform — the scene above is a '
                'placeholder, but every op is still recorded. Add the '
                'elpian_godot plugin for a live engine.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
