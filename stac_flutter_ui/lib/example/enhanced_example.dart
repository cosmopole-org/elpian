import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

void main() {
  runApp(const EnhancedStacApp());
}

class EnhancedStacApp extends StatelessWidget {
  const EnhancedStacApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enhanced STAC Flutter UI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EnhancedDemoPage(),
    );
  }
}

class EnhancedDemoPage extends StatefulWidget {
  const EnhancedDemoPage({super.key});

  @override
  State<EnhancedDemoPage> createState() => _EnhancedDemoPageState();
}

class _EnhancedDemoPageState extends State<EnhancedDemoPage> {
  final StacEngine _engine = StacEngine();
  final StacDOM _dom = StacDOM();
  final CSSStylesheet _stylesheet = CSSStylesheet();
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _setupStylesheet();
    _setupDOMExample();
  }

  void _setupStylesheet() {
    // Add global CSS rules
    _stylesheet.parseCSS('''
      .card {
        padding: 16px;
        margin: 8px;
        background-color: #FFFFFF;
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      }
      
      .primary-button {
        background-color: #2196F3;
        color: white;
        padding: 12px 24px;
        border-radius: 4px;
      }
      
      .text-center {
        text-align: center;
      }
      
      h1 {
        font-size: 32px;
        font-weight: bold;
        color: #333333;
      }
      
      .container {
        padding: 20px;
        background-color: #F5F5F5;
      }
    ''');
  }

  void _setupDOMExample() {
    // Create elements using DOM API
    final container = _dom.createElement('div', id: 'main-container', classes: ['container']);
    
    final title = _dom.createElement('h1');
    title.textContent = 'DOM API Example';
    title.addClass('text-center');
    
    final card1 = _dom.createElement('div', classes: ['card']);
    card1.setStyle('background-color', '#E3F2FD');
    
    final cardText = _dom.createElement('p');
    cardText.textContent = 'This card was created using the DOM API';
    
    card1.appendChild(cardText);
    container.appendChild(title);
    container.appendChild(card1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Enhanced STAC Flutter UI'),
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
                icon: Icon(Icons.widgets),
                label: Text('New Widgets'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.html),
                label: Text('HTML5 Elements'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.code),
                label: Text('DOM API'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.style),
                label: Text('CSS Grid/Flex'),
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
        return _buildNewWidgetsTab();
      case 1:
        return _buildHTML5Tab();
      case 2:
        return _buildDOMAPITab();
      case 3:
        return _buildCSSGridFlexTab();
      default:
        return const SizedBox();
    }
  }

  Widget _buildNewWidgetsTab() {
    final json = {
      'type': 'Column',
      'style': {
        'gap': 16,
      },
      'children': [
        {
          'type': 'Text',
          'props': {'text': 'New Flutter Widgets'},
          'style': {
            'fontSize': 24,
            'fontWeight': 'bold',
          },
        },
        {
          'type': 'Wrap',
          'style': {
            'gap': 8,
          },
          'children': [
            {
              'type': 'Chip',
              'props': {'label': 'Chip 1'},
              'style': {'backgroundColor': '#E3F2FD'},
            },
            {
              'type': 'Chip',
              'props': {'label': 'Chip 2'},
              'style': {'backgroundColor': '#F3E5F5'},
            },
            {
              'type': 'Chip',
              'props': {'label': 'Chip 3'},
              'style': {'backgroundColor': '#E8F5E9'},
            },
          ],
        },
        {
          'type': 'Card',
          'style': {
            'padding': '16',
            'margin': '8 0',
          },
          'children': [
            {
              'type': 'CircularProgressIndicator',
              'props': {'value': 0.7},
            },
          ],
        },
        {
          'type': 'AnimatedContainer',
          'style': {
            'width': 200,
            'height': 100,
            'backgroundColor': '#2196F3',
            'borderRadius': 12,
            'padding': '16',
          },
          'children': [
            {
              'type': 'Text',
              'props': {'text': 'Animated Container'},
              'style': {'color': 'white'},
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildHTML5Tab() {
    final json = {
      'type': 'div',
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'HTML5 Elements Demo'},
        },
        {
          'type': 'figure',
          'children': [
            {
              'type': 'img',
              'props': {'alt': 'Placeholder'},
              'style': {
                'width': 300,
                'height': 200,
                'backgroundColor': '#E0E0E0',
              },
            },
            {
              'type': 'figcaption',
              'props': {'text': 'Figure caption text'},
            },
          ],
        },
        {
          'type': 'p',
          'children': [
            {
              'type': 'mark',
              'props': {'text': 'Highlighted text'},
            },
            {
              'type': 'span',
              'props': {'text': ' and '},
            },
            {
              'type': 'del',
              'props': {'text': 'deleted text'},
            },
            {
              'type': 'span',
              'props': {'text': ' with '},
            },
            {
              'type': 'ins',
              'props': {'text': 'inserted text'},
            },
          ],
        },
        {
          'type': 'progress',
          'props': {'value': 0.6, 'max': 1.0},
          'style': {'margin': '16 0'},
        },
        {
          'type': 'details',
          'children': [
            {
              'type': 'summary',
              'props': {'text': 'Click to expand'},
            },
            {
              'type': 'p',
              'props': {'text': 'Hidden content revealed!'},
            },
          ],
        },
        {
          'type': 'kbd',
          'props': {'text': 'Ctrl + C'},
          'style': {'margin': '16 0'},
        },
      ],
    };

    return _engine.renderFromJson(json);
  }

  Widget _buildDOMAPITab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DOM API Demonstration',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            // Example: Create and manipulate elements
            final newCard = _dom.createElement('div', classes: ['card']);
            newCard.setStyle('background-color', '#FFF3E0');
            newCard.textContent = 'Dynamically created card';
            
            setState(() {});
          },
          child: const Text('Create New Element'),
        ),
        const SizedBox(height: 16),
        Text('Total elements in DOM: ${_dom.allElements.length}'),
        const SizedBox(height: 16),
        const Text(
          'DOM API Features:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('• getElementById(), getElementsByClassName()'),
        const Text('• querySelector(), querySelectorAll()'),
        const Text('• createElement(), appendChild()'),
        const Text('• setAttribute(), setStyle()'),
        const Text('• addClass(), removeClass(), toggleClass()'),
        const Text('• addEventListener(), dispatchEvent()'),
        const Text('• insertBefore(), removeChild(), replaceChild()'),
      ],
    );
  }

  Widget _buildCSSGridFlexTab() {
    final json = {
      'type': 'div',
      'style': {
        'padding': '20',
      },
      'children': [
        {
          'type': 'h1',
          'props': {'text': 'CSS Flexbox & Grid Demo'},
        },
        {
          'type': 'h2',
          'props': {'text': 'Flexbox Layout'},
          'style': {'margin': '16 0 8 0'},
        },
        {
          'type': 'div',
          'style': {
            'display': 'flex',
            'flexDirection': 'row',
            'justifyContent': 'space-between',
            'gap': 16,
            'padding': '16',
            'backgroundColor': '#F5F5F5',
            'borderRadius': 8,
          },
          'children': [
            {
              'type': 'div',
              'style': {
                'flex': 1,
                'padding': '16',
                'backgroundColor': '#E3F2FD',
                'borderRadius': 4,
              },
              'children': [
                {
                  'type': 'p',
                  'props': {'text': 'Flex Item 1'},
                },
              ],
            },
            {
              'type': 'div',
              'style': {
                'flex': 2,
                'padding': '16',
                'backgroundColor': '#F3E5F5',
                'borderRadius': 4,
              },
              'children': [
                {
                  'type': 'p',
                  'props': {'text': 'Flex Item 2 (flex: 2)'},
                },
              ],
            },
            {
              'type': 'div',
              'style': {
                'flex': 1,
                'padding': '16',
                'backgroundColor': '#E8F5E9',
                'borderRadius': 4,
              },
              'children': [
                {
                  'type': 'p',
                  'props': {'text': 'Flex Item 3'},
                },
              ],
            },
          ],
        },
        {
          'type': 'h2',
          'props': {'text': 'Transform & Animation'},
          'style': {'margin': '24 0 8 0'},
        },
        {
          'type': 'div',
          'style': {
            'display': 'flex',
            'gap': 16,
          },
          'children': [
            {
              'type': 'div',
              'style': {
                'width': 100,
                'height': 100,
                'backgroundColor': '#2196F3',
                'rotate': 45,
                'borderRadius': 8,
              },
            },
            {
              'type': 'div',
              'style': {
                'width': 100,
                'height': 100,
                'backgroundColor': '#4CAF50',
                'scale': 1.2,
                'borderRadius': 8,
              },
            },
            {
              'type': 'div',
              'style': {
                'width': 100,
                'height': 100,
                'backgroundColor': '#FF9800',
                'opacity': 0.5,
                'borderRadius': 8,
              },
            },
          ],
        },
      ],
    };

    return _engine.renderFromJson(json);
  }
}
