import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  runApp(const JsonStylesheetDemoApp());
}

class JsonStylesheetDemoApp extends StatelessWidget {
  const JsonStylesheetDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JSON Stylesheet Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const StylesheetDemoPage(),
    );
  }
}

class StylesheetDemoPage extends StatefulWidget {
  const StylesheetDemoPage({super.key});

  @override
  State<StylesheetDemoPage> createState() => _StylesheetDemoPageState();
}

class _StylesheetDemoPageState extends State<StylesheetDemoPage> {
  final ElpianEngine _engine = ElpianEngine();
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadStylesheets();
  }

  void _loadStylesheets() {
    // Load comprehensive JSON stylesheet
    final stylesheet = {
      'rules': [
        // Base styles
        {
          'selector': 'body',
          'styles': {
            'backgroundColor': '#F5F5F5',
            'padding': '20',
            'fontFamily': 'Roboto',
          }
        },
        
        // Typography
        {
          'selector': 'h1',
          'styles': {
            'fontSize': 32,
            'fontWeight': 'bold',
            'color': '#212121',
            'margin': '0 0 16 0',
          }
        },
        {
          'selector': 'h2',
          'styles': {
            'fontSize': 24,
            'fontWeight': 'bold',
            'color': '#424242',
            'margin': '16 0 12 0',
          }
        },
        {
          'selector': 'h3',
          'styles': {
            'fontSize': 20,
            'fontWeight': '600',
            'color': '#616161',
            'margin': '12 0 8 0',
          }
        },
        {
          'selector': 'p',
          'styles': {
            'fontSize': 16,
            'lineHeight': 1.5,
            'color': '#757575',
            'margin': '0 0 12 0',
          }
        },
        
        // Components - Cards
        {
          'selector': '.card',
          'styles': {
            'backgroundColor': '#FFFFFF',
            'padding': '20',
            'margin': '0 0 16 0',
            'borderRadius': 12,
            'boxShadow': [
              {
                'color': 'rgba(0,0,0,0.08)',
                'offset': {'x': 0, 'y': 2},
                'blur': 8,
                'spread': 0,
              }
            ],
          }
        },
        {
          'selector': '.card-elevated',
          'styles': {
            'backgroundColor': '#FFFFFF',
            'padding': '20',
            'margin': '0 0 16 0',
            'borderRadius': 12,
            'boxShadow': [
              {
                'color': 'rgba(0,0,0,0.15)',
                'offset': {'x': 0, 'y': 4},
                'blur': 12,
                'spread': 0,
              }
            ],
          }
        },
        
        // Buttons
        {
          'selector': '.btn',
          'styles': {
            'padding': '12 24',
            'borderRadius': 6,
            'fontWeight': '600',
            'cursor': 'pointer',
          }
        },
        {
          'selector': '.btn-primary',
          'styles': {
            'backgroundColor': '#2196F3',
            'color': '#FFFFFF',
            'padding': '12 24',
            'borderRadius': 6,
            'fontWeight': '600',
          }
        },
        {
          'selector': '.btn-secondary',
          'styles': {
            'backgroundColor': '#757575',
            'color': '#FFFFFF',
            'padding': '12 24',
            'borderRadius': 6,
            'fontWeight': '600',
          }
        },
        {
          'selector': '.btn-success',
          'styles': {
            'backgroundColor': '#4CAF50',
            'color': '#FFFFFF',
            'padding': '12 24',
            'borderRadius': 6,
            'fontWeight': '600',
          }
        },
        {
          'selector': '.btn-danger',
          'styles': {
            'backgroundColor': '#F44336',
            'color': '#FFFFFF',
            'padding': '12 24',
            'borderRadius': 6,
            'fontWeight': '600',
          }
        },
        
        // Layout helpers
        {
          'selector': '.container',
          'styles': {
            'padding': '20',
            'maxWidth': 1200,
          }
        },
        {
          'selector': '.flex-row',
          'styles': {
            'display': 'flex',
            'flexDirection': 'row',
            'gap': 16,
          }
        },
        {
          'selector': '.flex-column',
          'styles': {
            'display': 'flex',
            'flexDirection': 'column',
            'gap': 12,
          }
        },
        {
          'selector': '.flex-center',
          'styles': {
            'display': 'flex',
            'justifyContent': 'center',
            'alignItems': 'center',
          }
        },
        {
          'selector': '.flex-between',
          'styles': {
            'display': 'flex',
            'justifyContent': 'space-between',
            'alignItems': 'center',
          }
        },
        
        // Grid
        {
          'selector': '.grid',
          'styles': {
            'display': 'grid',
            'gridTemplateColumns': 'repeat(3, 1fr)',
            'gridGap': 16,
          }
        },
        {
          'selector': '.grid-2',
          'styles': {
            'display': 'grid',
            'gridTemplateColumns': 'repeat(2, 1fr)',
            'gridGap': 16,
          }
        },
        {
          'selector': '.grid-4',
          'styles': {
            'display': 'grid',
            'gridTemplateColumns': 'repeat(4, 1fr)',
            'gridGap': 16,
          }
        },
        
        // Spacing utilities
        {
          'selector': '.m-0',
          'styles': {'margin': '0'}
        },
        {
          'selector': '.m-1',
          'styles': {'margin': '8'}
        },
        {
          'selector': '.m-2',
          'styles': {'margin': '16'}
        },
        {
          'selector': '.m-3',
          'styles': {'margin': '24'}
        },
        {
          'selector': '.p-0',
          'styles': {'padding': '0'}
        },
        {
          'selector': '.p-1',
          'styles': {'padding': '8'}
        },
        {
          'selector': '.p-2',
          'styles': {'padding': '16'}
        },
        {
          'selector': '.p-3',
          'styles': {'padding': '24'}
        },
        
        // Text utilities
        {
          'selector': '.text-center',
          'styles': {'textAlign': 'center'}
        },
        {
          'selector': '.text-left',
          'styles': {'textAlign': 'left'}
        },
        {
          'selector': '.text-right',
          'styles': {'textAlign': 'right'}
        },
        {
          'selector': '.text-bold',
          'styles': {'fontWeight': 'bold'}
        },
        {
          'selector': '.text-italic',
          'styles': {'fontStyle': 'italic'}
        },
        
        // Color utilities
        {
          'selector': '.bg-primary',
          'styles': {'backgroundColor': '#2196F3'}
        },
        {
          'selector': '.bg-secondary',
          'styles': {'backgroundColor': '#757575'}
        },
        {
          'selector': '.bg-success',
          'styles': {'backgroundColor': '#4CAF50'}
        },
        {
          'selector': '.bg-danger',
          'styles': {'backgroundColor': '#F44336'}
        },
        {
          'selector': '.bg-warning',
          'styles': {'backgroundColor': '#FF9800'}
        },
        {
          'selector': '.text-primary',
          'styles': {'color': '#2196F3'}
        },
        {
          'selector': '.text-white',
          'styles': {'color': '#FFFFFF'}
        },
        
        // Borders
        {
          'selector': '.border',
          'styles': {
            'border': '1px solid #E0E0E0',
          }
        },
        {
          'selector': '.rounded',
          'styles': {'borderRadius': 8}
        },
        {
          'selector': '.rounded-lg',
          'styles': {'borderRadius': 16}
        },
        
        // Shadows
        {
          'selector': '.shadow-sm',
          'styles': {
            'boxShadow': [
              {
                'color': 'rgba(0,0,0,0.05)',
                'offset': {'x': 0, 'y': 1},
                'blur': 2,
              }
            ],
          }
        },
        {
          'selector': '.shadow',
          'styles': {
            'boxShadow': [
              {
                'color': 'rgba(0,0,0,0.1)',
                'offset': {'x': 0, 'y': 2},
                'blur': 4,
              }
            ],
          }
        },
        {
          'selector': '.shadow-lg',
          'styles': {
            'boxShadow': [
              {
                'color': 'rgba(0,0,0,0.15)',
                'offset': {'x': 0, 'y': 4},
                'blur': 8,
              }
            ],
          }
        },
      ],
      
      // Media queries for responsive design
      'mediaQueries': [
        {
          'query': 'min-width: 768',
          'rules': [
            {
              'selector': '.container',
              'styles': {'padding': '40'}
            },
            {
              'selector': 'h1',
              'styles': {'fontSize': 40}
            },
          ]
        },
        {
          'query': 'min-width: 1024',
          'rules': [
            {
              'selector': '.container',
              'styles': {'padding': '60'}
            },
          ]
        },
      ],
      
      // CSS Variables
      'variables': {
        'primary-color': '#2196F3',
        'secondary-color': '#757575',
        'success-color': '#4CAF50',
        'danger-color': '#F44336',
        'warning-color': '#FF9800',
        'spacing-unit': 8,
      },
    };

    _engine.loadStylesheet(stylesheet);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('JSON Stylesheet Demo'),
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
                icon: Icon(Icons.style),
                label: Text('Components'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.grid_on),
                label: Text('Grid Layout'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.palette),
                label: Text('Utilities'),
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
        return _buildComponentsTab();
      case 1:
        return _buildGridTab();
      case 2:
        return _buildUtilitiesTab();
      default:
        return const SizedBox();
    }
  }

  Widget _buildComponentsTab() {
    // All styles come from the JSON stylesheet
    final json = {
      'type': 'div',
      'props': {'className': 'container'},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Styled Components'},
        },
        {
          'type': 'p',
          'props': {'text': 'All styles defined in JSON stylesheet'},
        },
        
        // Cards
        {
          'type': 'h2',
          'props': {'text': 'Cards'},
        },
        {
          'type': 'div',
          'props': {'className': 'card'},
          'children': [
            {
              'type': 'h3',
              'props': {'text': 'Standard Card'},
            },
            {
              'type': 'p',
              'props': {'text': 'This card uses the .card class from the stylesheet'},
            },
          ],
        },
        {
          'type': 'div',
          'props': {'className': 'card-elevated'},
          'children': [
            {
              'type': 'h3',
              'props': {'text': 'Elevated Card'},
            },
            {
              'type': 'p',
              'props': {'text': 'This card has enhanced shadow elevation'},
            },
          ],
        },
        
        // Buttons
        {
          'type': 'h2',
          'props': {'text': 'Buttons'},
        },
        {
          'type': 'div',
          'props': {'className': 'flex-row'},
          'children': [
            {
              'type': 'Button',
              'props': {
                'text': 'Primary',
                'className': 'btn-primary',
              },
            },
            {
              'type': 'Button',
              'props': {
                'text': 'Secondary',
                'className': 'btn-secondary',
              },
            },
            {
              'type': 'Button',
              'props': {
                'text': 'Success',
                'className': 'btn-success',
              },
            },
            {
              'type': 'Button',
              'props': {
                'text': 'Danger',
                'className': 'btn-danger',
              },
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildGridTab() {
    final json = {
      'type': 'div',
      'props': {'className': 'container'},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Grid Layouts'},
        },
        
        {
          'type': 'h2',
          'props': {'text': '3-Column Grid'},
        },
        {
          'type': 'div',
          'props': {'className': 'grid'},
          'children': List.generate(6, (i) => {
            'type': 'div',
            'props': {'className': 'card text-center'},
            'children': [
              {
                'type': 'h3',
                'props': {'text': 'Item ${i + 1}'},
              },
              {
                'type': 'p',
                'props': {'text': 'Grid item content'},
              },
            ],
          }),
        },
        
        {
          'type': 'h2',
          'props': {'text': '2-Column Grid'},
        },
        {
          'type': 'div',
          'props': {'className': 'grid-2'},
          'children': List.generate(4, (i) => {
            'type': 'div',
            'props': {'className': 'card'},
            'children': [
              {
                'type': 'h3',
                'props': {'text': 'Column ${i + 1}'},
              },
            ],
          }),
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildUtilitiesTab() {
    final json = {
      'type': 'div',
      'props': {'className': 'container'},
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'Utility Classes'},
        },
        
        // Spacing
        {
          'type': 'h2',
          'props': {'text': 'Spacing'},
        },
        {
          'type': 'div',
          'props': {'className': 'flex-row'},
          'children': [
            {
              'type': 'div',
              'props': {'className': 'card p-1'},
              'children': [
                {'type': 'p', 'props': {'text': 'Padding 1'}},
              ],
            },
            {
              'type': 'div',
              'props': {'className': 'card p-2'},
              'children': [
                {'type': 'p', 'props': {'text': 'Padding 2'}},
              ],
            },
            {
              'type': 'div',
              'props': {'className': 'card p-3'},
              'children': [
                {'type': 'p', 'props': {'text': 'Padding 3'}},
              ],
            },
          ],
        },
        
        // Colors
        {
          'type': 'h2',
          'props': {'text': 'Colors'},
        },
        {
          'type': 'div',
          'props': {'className': 'flex-row'},
          'children': [
            {
              'type': 'div',
              'props': {'className': 'bg-primary p-2 rounded'},
              'children': [
                {'type': 'p', 'props': {'text': 'Primary', 'className': 'text-white'}},
              ],
            },
            {
              'type': 'div',
              'props': {'className': 'bg-success p-2 rounded'},
              'children': [
                {'type': 'p', 'props': {'text': 'Success', 'className': 'text-white'}},
              ],
            },
            {
              'type': 'div',
              'props': {'className': 'bg-danger p-2 rounded'},
              'children': [
                {'type': 'p', 'props': {'text': 'Danger', 'className': 'text-white'}},
              ],
            },
            {
              'type': 'div',
              'props': {'className': 'bg-warning p-2 rounded'},
              'children': [
                {'type': 'p', 'props': {'text': 'Warning', 'className': 'text-white'}},
              ],
            },
          ],
        },
        
        // Shadows
        {
          'type': 'h2',
          'props': {'text': 'Shadows'},
        },
        {
          'type': 'div',
          'props': {'className': 'flex-row'},
          'children': [
            {
              'type': 'div',
              'props': {'className': 'shadow-sm p-2 rounded'},
              'children': [
                {'type': 'p', 'props': {'text': 'Small Shadow'}},
              ],
            },
            {
              'type': 'div',
              'props': {'className': 'shadow p-2 rounded'},
              'children': [
                {'type': 'p', 'props': {'text': 'Medium Shadow'}},
              ],
            },
            {
              'type': 'div',
              'props': {'className': 'shadow-lg p-2 rounded'},
              'children': [
                {'type': 'p', 'props': {'text': 'Large Shadow'}},
              ],
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }
}
