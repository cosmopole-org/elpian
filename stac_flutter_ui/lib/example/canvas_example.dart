import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';
import 'dart:math' as math;

void main() {
  runApp(const CanvasAPIDemoApp());
}

class CanvasAPIDemoApp extends StatelessWidget {
  const CanvasAPIDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canvas API Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const CanvasDemoPage(),
    );
  }
}

class CanvasDemoPage extends StatefulWidget {
  const CanvasDemoPage({super.key});

  @override
  State<CanvasDemoPage> createState() => _CanvasDemoPageState();
}

class _CanvasDemoPageState extends State<CanvasDemoPage> {
  final StacEngine _engine = StacEngine();
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Canvas API Demo'),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedTab,
            onDestinationSelected: (index) {
              setState(() {
                _selectedTab = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.category),
                label: Text('Shapes'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.timeline),
                label: Text('Paths'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.text_fields),
                label: Text('Text'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.gradient),
                label: Text('Gradients'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.transform),
                label: Text('Transforms'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _buildSelectedTab(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedTab() {
    switch (_selectedTab) {
      case 0:
        return _buildShapesTab();
      case 1:
        return _buildPathsTab();
      case 2:
        return _buildTextTab();
      case 3:
        return _buildGradientsTab();
      case 4:
        return _buildTransformsTab();
      default:
        return const SizedBox();
    }
  }

  Widget _buildShapesTab() {
    final json = {
      'type': 'Column',
      'style': {'gap': 16},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Basic Shapes'},
        },
        
        // Rectangles
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Rectangles'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  // Filled rectangle
                  .fillStyle('#FF5722')
                  .fillRect(20, 20, 100, 80)
                  // Stroked rectangle
                  .strokeStyle('#2196F3')
                  .lineWidth(3)
                  .strokeRect(140, 20, 100, 80)
                  // Rounded rectangle
                  .fillStyle('#4CAF50')
                  .beginPath()
                  .roundRect(260, 20, 100, 80, 10)
                  .fill()
                  .build(),
              },
            },
          ],
        },
        
        // Circles
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Circles & Ellipses'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  // Filled circle
                  .fillStyle('#9C27B0')
                  .fillCircle(70, 100, 50)
                  // Stroked circle
                  .strokeStyle('#FF9800')
                  .lineWidth(4)
                  .strokeCircle(200, 100, 50)
                  // Ellipse
                  .fillStyle('#00BCD4')
                  .beginPath()
                  .ellipse(330, 100, 60, 40)
                  .fill()
                  .build(),
              },
            },
          ],
        },
        
        // Complex shapes using builder
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Stars & Polygons'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': [
                  ...CanvasPresets.star(
                    100, 100, 60,
                    points: 5,
                    fillColor: '#FFD700',
                    strokeColor: '#FF6B00',
                  ),
                  ...CanvasPresets.polygon(
                    250, 100, 60,
                    sides: 6,
                    fillColor: '#FF4081',
                  ),
                ],
              },
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildPathsTab() {
    final json = {
      'type': 'Column',
      'style': {'gap': 16},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Paths & Curves'},
        },
        
        // Bezier curves
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Bezier Curves'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  .strokeStyle('#2196F3')
                  .lineWidth(3)
                  .beginPath()
                  .moveTo(50, 100)
                  .bezierCurveTo(100, 20, 150, 180, 200, 100)
                  .stroke()
                  // Quadratic curve
                  .strokeStyle('#4CAF50')
                  .beginPath()
                  .moveTo(220, 100)
                  .quadraticCurveTo(280, 20, 340, 100)
                  .stroke()
                  .build(),
              },
            },
          ],
        },
        
        // Arcs
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Arcs'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  .strokeStyle('#FF5722')
                  .lineWidth(4)
                  .beginPath()
                  .arc(100, 100, 60, 0, math.pi)
                  .stroke()
                  .strokeStyle('#9C27B0')
                  .beginPath()
                  .arc(250, 100, 60, 0, math.pi * 1.5)
                  .stroke()
                  .build(),
              },
            },
          ],
        },
        
        // Custom path
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Custom Path'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  .fillStyle('#FF9800')
                  .strokeStyle('#E65100')
                  .lineWidth(3)
                  .beginPath()
                  .moveTo(200, 50)
                  .lineTo(250, 150)
                  .lineTo(150, 150)
                  .closePath()
                  .fill()
                  .stroke()
                  .build(),
              },
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildTextTab() {
    final json = {
      'type': 'Column',
      'style': {'gap': 16},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Text Rendering'},
        },
        
        {
          'type': 'Canvas',
          'props': {
            'width': 400.0,
            'height': 300.0,
            'commands': CanvasBuilder()
              // Regular text
              .fillStyle('#212121')
              .font('24px Arial')
              .fillText('Hello Canvas!', 50, 50)
              // Large bold text
              .font('bold 32px Arial')
              .fillStyle('#2196F3')
              .fillText('Large Text', 50, 100)
              // Italic text
              .font('italic 20px Arial')
              .fillStyle('#4CAF50')
              .fillText('Italic Text', 50, 150)
              // Stroke text
              .strokeStyle('#FF5722')
              .lineWidth(2)
              .font('bold 28px Arial')
              .strokeText('Outlined', 50, 200)
              // Combined fill and stroke
              .fillStyle('#FFD700')
              .strokeStyle('#FF6B00')
              .font('bold 30px Arial')
              .fillText('Combined', 50, 250)
              .strokeText('Combined', 50, 250)
              .build(),
          },
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildGradientsTab() {
    final json = {
      'type': 'Column',
      'style': {'gap': 16},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Gradients'},
        },
        
        // Linear gradient
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Linear Gradient'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 150.0,
                'commands': CanvasBuilder()
                  .createLinearGradient(
                    'grad1',
                    50, 75, 350, 75,
                    ['#FF6B6B', '#4ECDC4', '#45B7D1'],
                  )
                  .fillGradient('grad1')
                  .fillRect(50, 25, 300, 100)
                  .build(),
              },
            },
          ],
        },
        
        // Radial gradient
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Radial Gradient'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  .createRadialGradient(
                    'grad2',
                    200, 100, 80,
                    ['#FF0844', '#FFB199', '#FFED8F'],
                  )
                  .fillGradient('grad2')
                  .fillCircle(200, 100, 80)
                  .build(),
              },
            },
          ],
        },
        
        // Multiple gradients
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Multiple Gradients'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  // First gradient
                  .createLinearGradient(
                    'g1',
                    50, 50, 150, 150,
                    ['#667eea', '#764ba2'],
                  )
                  .fillGradient('g1')
                  .fillRect(50, 50, 100, 100)
                  // Second gradient
                  .createLinearGradient(
                    'g2',
                    200, 50, 300, 150,
                    ['#f093fb', '#f5576c'],
                  )
                  .fillGradient('g2')
                  .fillRect(200, 50, 100, 100)
                  .build(),
              },
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildTransformsTab() {
    final json = {
      'type': 'Column',
      'style': {'gap': 16},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Transformations'},
        },
        
        // Translation
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Translation'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 150.0,
                'commands': CanvasBuilder()
                  .fillStyle('#2196F3')
                  .fillRect(50, 50, 60, 60)
                  .save()
                  .translate(100, 0)
                  .fillStyle('#4CAF50')
                  .fillRect(50, 50, 60, 60)
                  .restore()
                  .save()
                  .translate(200, 0)
                  .fillStyle('#FF9800')
                  .fillRect(50, 50, 60, 60)
                  .restore()
                  .build(),
              },
            },
          ],
        },
        
        // Rotation
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Rotation'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  .save()
                  .translate(100, 100)
                  .fillStyle('#FF5722')
                  .fillRect(-30, -30, 60, 60)
                  .restore()
                  .save()
                  .translate(250, 100)
                  .rotate(math.pi / 4)
                  .fillStyle('#9C27B0')
                  .fillRect(-30, -30, 60, 60)
                  .restore()
                  .build(),
              },
            },
          ],
        },
        
        // Scaling
        {
          'type': 'div',
          'children': [
            {
              'type': 'h2',
              'props': {'text': 'Scaling'},
            },
            {
              'type': 'Canvas',
              'props': {
                'width': 400.0,
                'height': 200.0,
                'commands': CanvasBuilder()
                  .fillStyle('#00BCD4')
                  .fillRect(50, 50, 40, 40)
                  .save()
                  .translate(150, 50)
                  .scale(1.5, 1.5)
                  .fillStyle('#E91E63')
                  .fillRect(0, 0, 40, 40)
                  .restore()
                  .save()
                  .translate(280, 50)
                  .scale(2, 2)
                  .fillStyle('#3F51B5')
                  .fillRect(0, 0, 40, 40)
                  .restore()
                  .build(),
              },
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }
}
