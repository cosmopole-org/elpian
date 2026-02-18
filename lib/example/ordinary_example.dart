import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STAC Flutter UI Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const StacDemoPage(),
    );
  }
}

class StacDemoPage extends StatefulWidget {
  const StacDemoPage({super.key});

  @override
  State<StacDemoPage> createState() => _StacDemoPageState();
}

class _StacDemoPageState extends State<StacDemoPage> {
  final StacEngine _engine = StacEngine();
  int _selectedExample = 0;

  final List<Map<String, dynamic>> _examples = [
    {
      'name': 'Flutter Widgets',
      'json': {
        'type': 'Column',
        'style': {
          'padding': '16',
          'backgroundColor': '#F5F5F5',
        },
        'children': [
          {
            'type': 'Text',
            'props': {
              'text': 'Flutter STAC Demo',
            },
            'style': {
              'fontSize': 24,
              'fontWeight': 'bold',
              'color': '#2196F3',
              'margin': '0 0 16 0',
            },
          },
          {
            'type': 'Card',
            'style': {
              'margin': '8',
            },
            'children': [
              {
                'type': 'Container',
                'style': {
                  'padding': '16',
                },
                'children': [
                  {
                    'type': 'Text',
                    'props': {
                      'text': 'This is a card with custom styling',
                    },
                  },
                ],
              },
            ],
          },
          {
            'type': 'Row',
            'style': {
              'justifyContent': 'space-around',
              'margin': '16 0',
            },
            'children': [
              {
                'type': 'Button',
                'props': {
                  'text': 'Button 1',
                },
                'style': {
                  'backgroundColor': '#4CAF50',
                },
              },
              {
                'type': 'Button',
                'props': {
                  'text': 'Button 2',
                },
                'style': {
                  'backgroundColor': '#F44336',
                },
              },
            ],
          },
        ],
      },
    },
    {
      'name': 'HTML Elements',
      'json': {
        'type': 'div',
        'style': {
          'padding': '16',
        },
        'children': [
          {
            'type': 'h1',
            'props': {
              'text': 'HTML-like Elements',
            },
            'style': {
              'color': '#E91E63',
            },
          },
          {
            'type': 'p',
            'props': {
              'text': 'This is a paragraph element with custom styling.',
            },
            'style': {
              'fontSize': 16,
              'color': '#666',
            },
          },
          {
            'type': 'ul',
            'children': [
              {
                'type': 'li',
                'props': {
                  'text': 'List item 1',
                },
              },
              {
                'type': 'li',
                'props': {
                  'text': 'List item 2',
                },
              },
              {
                'type': 'li',
                'props': {
                  'text': 'List item 3',
                },
              },
            ],
          },
          {
            'type': 'button',
            'props': {
              'text': 'HTML Button',
            },
            'style': {
              'backgroundColor': '#9C27B0',
              'margin': '16 0',
            },
          },
        ],
      },
    },
    {
      'name': 'Mixed Content',
      'json': {
        'type': 'div',
        'style': {
          'padding': '20',
          'backgroundColor': '#FAFAFA',
        },
        'children': [
          {
            'type': 'header',
            'style': {
              'backgroundColor': '#3F51B5',
              'padding': '16',
              'margin': '0 0 16 0',
              'borderRadius': 8,
            },
            'children': [
              {
                'type': 'h2',
                'props': {
                  'text': 'Dashboard',
                },
                'style': {
                  'color': 'white',
                  'margin': '0',
                },
              },
            ],
          },
          {
            'type': 'section',
            'children': [
              {
                'type': 'h3',
                'props': {
                  'text': 'Statistics',
                },
              },
              {
                'type': 'Row',
                'style': {
                  'justifyContent': 'space-between',
                },
                'children': [
                  {
                    'type': 'Card',
                    'style': {
                      'flex': 1,
                      'margin': '8',
                      'backgroundColor': '#4CAF50',
                    },
                    'children': [
                      {
                        'type': 'Container',
                        'style': {
                          'padding': '16',
                        },
                        'children': [
                          {
                            'type': 'Text',
                            'props': {
                              'text': '1,234',
                            },
                            'style': {
                              'fontSize': 32,
                              'fontWeight': 'bold',
                              'color': 'white',
                            },
                          },
                          {
                            'type': 'Text',
                            'props': {
                              'text': 'Users',
                            },
                            'style': {
                              'color': 'white',
                            },
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'type': 'Card',
                    'style': {
                      'flex': 1,
                      'margin': '8',
                      'backgroundColor': '#2196F3',
                    },
                    'children': [
                      {
                        'type': 'Container',
                        'style': {
                          'padding': '16',
                        },
                        'children': [
                          {
                            'type': 'Text',
                            'props': {
                              'text': '567',
                            },
                            'style': {
                              'fontSize': 32,
                              'fontWeight': 'bold',
                              'color': 'white',
                            },
                          },
                          {
                            'type': 'Text',
                            'props': {
                              'text': 'Sales',
                            },
                            'style': {
                              'color': 'white',
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
          {
            'type': 'footer',
            'style': {
              'margin': '16 0 0 0',
              'padding': '16',
              'backgroundColor': '#E0E0E0',
              'borderRadius': 8,
            },
            'children': [
              {
                'type': 'p',
                'props': {
                  'text': '© 2024 STAC Flutter UI',
                },
                'style': {
                  'textAlign': 'center',
                  'margin': '0',
                },
              },
            ],
          },
        ],
      },
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('STAC Flutter UI Demo'),
      ),
      body: Row(
        children: [
          // Sidebar with examples
          Container(
            width: 200,
            color: Colors.grey[200],
            child: ListView.builder(
              itemCount: _examples.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_examples[index]['name'] as String),
                  selected: _selectedExample == index,
                  onTap: () {
                    setState(() {
                      _selectedExample = index;
                    });
                  },
                );
              },
            ),
          ),
          // Main content area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _engine.renderFromJson(_examples[_selectedExample]['json']),
            ),
          ),
        ],
      ),
    );
  }
}
