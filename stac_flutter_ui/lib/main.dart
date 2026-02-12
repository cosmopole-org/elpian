import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

void main() {
  runApp(const EventSystemDemoApp());
}

class EventSystemDemoApp extends StatelessWidget {
  const EventSystemDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STAC Event System Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EventDemoPage(),
    );
  }
}

class EventDemoPage extends StatefulWidget {
  const EventDemoPage({super.key});

  @override
  State<EventDemoPage> createState() => _EventDemoPageState();
}

class _EventDemoPageState extends State<EventDemoPage> {
  final StacEngine _engine = StacEngine();
  final List<String> _eventLog = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _setupGlobalEventHandler();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setupGlobalEventHandler() {
    // Setup global event handler to receive ALL events
    _engine.setGlobalEventHandler((event) {
      setState(() {
        final eventInfo = _formatEvent(event);
        _eventLog.insert(0, eventInfo);
        
        // Keep only last 50 events
        if (_eventLog.length > 50) {
          _eventLog.removeLast();
        }
      });
      
      // Auto-scroll to top
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatEvent(StacEvent event) {
    final time = event.timestamp.toString().substring(11, 19);
    final target = event.target ?? 'unknown';
    final currentTarget = event.currentTarget ?? 'unknown';
    final phase = event.phase.toString().split('.').last;
    
    String details = '[$time] ${event.type.toUpperCase()} - Target: $target';
    
    if (target != currentTarget) {
      details += ' (Current: $currentTarget)';
    }
    
    details += ' [Phase: $phase]';
    
    // Add event-specific details
    if (event is StacPointerEvent) {
      details += ' | Pos: (${event.position.dx.toStringAsFixed(0)}, ${event.position.dy.toStringAsFixed(0)})';
    } else if (event is StacInputEvent) {
      details += ' | Value: ${event.value}';
    } else if (event is StacKeyboardEvent) {
      details += ' | Key: ${event.key}';
    } else if (event is StacGestureEvent) {
      if (event.scale != 1.0) {
        details += ' | Scale: ${event.scale.toStringAsFixed(2)}';
      }
      if (event.rotation != 0.0) {
        details += ' | Rotation: ${event.rotation.toStringAsFixed(2)}';
      }
    }
    
    return details;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Event System Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(() {
                _eventLog.clear();
              });
            },
            tooltip: 'Clear Log',
          ),
        ],
      ),
      body: Row(
        children: [
          // Interactive UI Section
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _buildInteractiveUI(),
            ),
          ),
          
          // Event Log Section
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: Border(
                  left: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[700]!, width: 1),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.event, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Event Log',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _eventLog.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _eventLog[index],
                            style: TextStyle(
                              color: Colors.green[300],
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveUI() {
    final json = {
      'type': 'Column',
      'key': 'root',
      'style': {
        'gap': 16,
      },
      'events': {
        'click': (event) => debugPrint('Root container clicked'),
      },
      'children': [
        {
          'type': 'Text',
          'props': {
            'text': 'Interactive Event System Demo',
          },
          'style': {
            'fontSize': 28,
            'fontWeight': 'bold',
            'margin': '0 0 16 0',
          },
        },
        
        // Click Events Section
        {
          'type': 'Card',
          'key': 'click-card',
          'style': {
            'padding': '16',
            'margin': '8 0',
          },
          'events': {
            'click': (event) {
              // Card click event (will bubble)
            },
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Click Events'},
              'style': {
                'fontSize': 20,
                'fontWeight': 'bold',
                'margin': '0 0 12 0',
              },
            },
            {
              'type': 'Row',
              'style': {
                'justifyContent': 'space-around',
                'gap': 8,
              },
              'children': [
                {
                  'type': 'Button',
                  'key': 'btn-click',
                  'props': {'text': 'Click Me'},
                  'style': {
                    'backgroundColor': '#2196F3',
                    'padding': '12 24',
                  },
                  'events': {
                    'click': (event) {
                      // Simple click event
                    },
                  },
                },
                {
                  'type': 'Button',
                  'key': 'btn-double',
                  'props': {'text': 'Double Click'},
                  'style': {
                    'backgroundColor': '#4CAF50',
                    'padding': '12 24',
                  },
                  'events': {
                    'doubletap': (event) {
                      // Double click event
                    },
                  },
                },
                {
                  'type': 'Button',
                  'key': 'btn-long',
                  'props': {'text': 'Long Press'},
                  'style': {
                    'backgroundColor': '#FF9800',
                    'padding': '12 24',
                  },
                  'events': {
                    'longpress': (event) {
                      // Long press event
                    },
                  },
                },
              ],
            },
          ],
        },
        
        // Drag Events Section
        {
          'type': 'Card',
          'key': 'drag-card',
          'style': {
            'padding': '16',
            'margin': '8 0',
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Drag Events'},
              'style': {
                'fontSize': 20,
                'fontWeight': 'bold',
                'margin': '0 0 12 0',
              },
            },
            {
              'type': 'div',
              'key': 'draggable-box',
              'style': {
                'width': 150,
                'height': 150,
                'backgroundColor': '#E91E63',
                'borderRadius': 12,
                'display': 'flex',
                'justifyContent': 'center',
                'alignItems': 'center',
              },
              'events': {
                'dragstart': (event) {},
                'drag': (event) {},
                'dragend': (event) {},
              },
              'children': [
                {
                  'type': 'Text',
                  'props': {'text': 'Drag Me!'},
                  'style': {
                    'color': 'white',
                    'fontWeight': 'bold',
                  },
                },
              ],
            },
          ],
        },
        
        // Swipe Gestures Section
        {
          'type': 'Card',
          'key': 'swipe-card',
          'style': {
            'padding': '16',
            'margin': '8 0',
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Swipe Gestures'},
              'style': {
                'fontSize': 20,
                'fontWeight': 'bold',
                'margin': '0 0 12 0',
              },
            },
            {
              'type': 'div',
              'key': 'swipe-area',
              'style': {
                'width': 300,
                'height': 150,
                'backgroundColor': '#9C27B0',
                'borderRadius': 12,
                'display': 'flex',
                'justifyContent': 'center',
                'alignItems': 'center',
              },
              'events': {
                'swipeleft': (event) {},
                'swiperight': (event) {},
                'swipeup': (event) {},
                'swipedown': (event) {},
              },
              'children': [
                {
                  'type': 'Text',
                  'props': {'text': 'Swipe in any direction'},
                  'style': {
                    'color': 'white',
                    'textAlign': 'center',
                  },
                },
              ],
            },
          ],
        },
        
        // Hover Events Section
        {
          'type': 'Card',
          'key': 'hover-card',
          'style': {
            'padding': '16',
            'margin': '8 0',
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Hover Events'},
              'style': {
                'fontSize': 20,
                'fontWeight': 'bold',
                'margin': '0 0 12 0',
              },
            },
            {
              'type': 'Row',
              'style': {
                'gap': 16,
              },
              'children': [
                {
                  'type': 'div',
                  'key': 'hover-box-1',
                  'style': {
                    'width': 100,
                    'height': 100,
                    'backgroundColor': '#00BCD4',
                    'borderRadius': 8,
                  },
                  'events': {
                    'pointerenter': (event) {},
                    'pointerexit': (event) {},
                  },
                },
                {
                  'type': 'div',
                  'key': 'hover-box-2',
                  'style': {
                    'width': 100,
                    'height': 100,
                    'backgroundColor': '#009688',
                    'borderRadius': 8,
                  },
                  'events': {
                    'pointerenter': (event) {},
                    'pointerexit': (event) {},
                    'pointerhover': (event) {},
                  },
                },
              ],
            },
          ],
        },
        
        // Tap Events Section
        {
          'type': 'Card',
          'key': 'tap-card',
          'style': {
            'padding': '16',
            'margin': '8 0',
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Detailed Tap Events'},
              'style': {
                'fontSize': 20,
                'fontWeight': 'bold',
                'margin': '0 0 12 0',
              },
            },
            {
              'type': 'div',
              'key': 'tap-area',
              'style': {
                'width': 200,
                'height': 200,
                'backgroundColor': '#3F51B5',
                'borderRadius': 12,
                'display': 'flex',
                'justifyContent': 'center',
                'alignItems': 'center',
              },
              'events': {
                'tapdown': (event) {},
                'tapup': (event) {},
                'tap': (event) {},
                'tapcancel': (event) {},
              },
              'children': [
                {
                  'type': 'Text',
                  'props': {'text': 'Tap Here\n(watch event phases)'},
                  'style': {
                    'color': 'white',
                    'textAlign': 'center',
                  },
                },
              ],
            },
          ],
        },
        
        // Event Bubbling Demo
        {
          'type': 'Card',
          'key': 'bubbling-card',
          'style': {
            'padding': '16',
            'margin': '8 0',
            'backgroundColor': '#FFF3E0',
          },
          'events': {
            'click': (event) {
              // Parent card click - will receive bubbled events
            },
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Event Bubbling Demo'},
              'style': {
                'fontSize': 20,
                'fontWeight': 'bold',
                'margin': '0 0 12 0',
              },
            },
            {
              'type': 'Text',
              'props': {'text': 'Click the inner box and watch events bubble through parent, grandparent...'},
              'style': {
                'fontSize': 14,
                'color': '#666',
                'margin': '0 0 12 0',
              },
            },
            {
              'type': 'div',
              'key': 'outer-box',
              'style': {
                'padding': '20',
                'backgroundColor': '#FFEB3B',
                'borderRadius': 8,
              },
              'events': {
                'click': (event) {
                  // Outer box - will see bubbled events
                },
              },
              'children': [
                {
                  'type': 'div',
                  'key': 'middle-box',
                  'style': {
                    'padding': '20',
                    'backgroundColor': '#FFC107',
                    'borderRadius': 8,
                  },
                  'events': {
                    'click': (event) {
                      // Middle box - will see bubbled events
                    },
                  },
                  'children': [
                    {
                      'type': 'div',
                      'key': 'inner-box',
                      'style': {
                        'padding': '20',
                        'backgroundColor': '#FF9800',
                        'borderRadius': 8,
                        'display': 'flex',
                        'justifyContent': 'center',
                        'alignItems': 'center',
                      },
                      'events': {
                        'click': (event) {
                          // Inner box - event originates here
                        },
                      },
                      'children': [
                        {
                          'type': 'Text',
                          'props': {'text': 'Click Me (Inner)'},
                          'style': {
                            'color': 'white',
                            'fontWeight': 'bold',
                          },
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }
}
