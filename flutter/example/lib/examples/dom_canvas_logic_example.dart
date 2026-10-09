import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

class DomCanvasLogicExamplePage extends StatelessWidget {
  const DomCanvasLogicExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DOM + Canvas Logic Examples'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'QuickJS'),
              Tab(text: 'Elpian VM AST'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _QuickJsDomCanvasDemo(),
            _VmAstDomCanvasDemo(),
          ],
        ),
      ),
    );
  }
}

class _QuickJsDomCanvasDemo extends StatefulWidget {
  const _QuickJsDomCanvasDemo();

  @override
  State<_QuickJsDomCanvasDemo> createState() => _QuickJsDomCanvasDemoState();
}

class _QuickJsDomCanvasDemoState extends State<_QuickJsDomCanvasDemo> {
  final _controller = ElpianVmController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Runs in ElpianRuntime.quickJs (native + web runtime bridge). '
            'Buttons call JS functions from Flutter to mutate DOM + Canvas host APIs.',
          ),
        ),
        Expanded(
          child: ElpianVmScope(
            controller: _controller,
            machineId: 'quickjs-dom-canvas-demo',
            runtime: ElpianRuntime.quickJs,
            code: _quickJsDomCanvasProgram,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _controller.callFunction('decrement'),
                  child: const Text('−'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _controller.callFunction('increment'),
                  child: const Text('+'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VmAstDomCanvasDemo extends StatefulWidget {
  const _VmAstDomCanvasDemo();

  @override
  State<_VmAstDomCanvasDemo> createState() => _VmAstDomCanvasDemoState();
}

class _VmAstDomCanvasDemoState extends State<_VmAstDomCanvasDemo> {
  final _controller = ElpianVmController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'AST VM uses host_call entries to manage DOM + Canvas state, then renders a Flutter DSL view.',
          ),
        ),
        Expanded(
          child: ElpianVmScope(
            controller: _controller,
            machineId: 'vm-ast-dom-canvas-demo',
            astJson: jsonEncode(_vmAstDomCanvasProgram()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _controller.callFunction('nextColor'),
              child: const Text('Next Color (from Flutter)'),
            ),
          ),
        ),
      ],
    );
  }
}

const String _quickJsDomCanvasProgram = r'''
let count = 0;
let colors = ['#4f46e5', '#059669', '#dc2626', '#d97706'];
let colorIndex = 0;

function typedValueOf(response) {
  try {
    const parsed = JSON.parse(response);
    if (parsed && parsed.data) return parsed.data.value;
  } catch (_) {}
  return null;
}

function buildDomCard() {
  askHost('dom.clear', '{}');
  askHost('dom.createElement', JSON.stringify({ tagName: 'div', id: 'rootCard' }));
  askHost('dom.setStyleObject', JSON.stringify({
    id: 'rootCard',
    styles: {
      padding: '14',
      backgroundColor: '#ffffff',
      borderRadius: '12',
      border: '1px solid #dbe2ff'
    }
  }));
  askHost('dom.createElement', JSON.stringify({ tagName: 'h3', id: 'title' }));
  askHost('dom.setTextContent', JSON.stringify({ id: 'title', text: 'QuickJS DOM API Card' }));
  askHost('dom.createElement', JSON.stringify({ tagName: 'p', id: 'desc' }));
  askHost('dom.setTextContent', JSON.stringify({ id: 'desc', text: `Counter: ${count} | Color: ${colors[colorIndex]}` }));
  askHost('dom.appendChild', JSON.stringify({ parentId: 'rootCard', childId: 'title' }));
  askHost('dom.appendChild', JSON.stringify({ parentId: 'rootCard', childId: 'desc' }));
  const rootResponse = askHost('dom.toJson', JSON.stringify({ id: 'rootCard' }));
  return typedValueOf(rootResponse) || { type: 'Text', props: { text: 'DOM unavailable' } };
}

function buildCanvasCommands() {
  askHost('canvas.clear', '{}');
  askHost('canvas.setFillStyle', JSON.stringify({ color: '#f8faff' }));
  askHost('canvas.fillRect', JSON.stringify({ x: 0, y: 0, width: 320, height: 160 }));
  askHost('canvas.setFillStyle', JSON.stringify({ color: colors[colorIndex] }));
  askHost('canvas.fillRect', JSON.stringify({ x: 20, y: 20, width: 40 + count * 20, height: 36 }));
  askHost('canvas.setStrokeStyle', JSON.stringify({ color: '#111827' }));
  askHost('canvas.setLineWidth', JSON.stringify({ width: 2 }));
  askHost('canvas.strokeRect', JSON.stringify({ x: 20, y: 20, width: 220, height: 36 }));
  askHost('canvas.fillText', JSON.stringify({ text: `count=${count}`, x: 20, y: 92 }));
  const response = askHost('canvas.getCommands', '{}');
  return typedValueOf(response) || [];
}

function renderNow() {
  askHost('render', JSON.stringify({
    type: 'Column',
    props: { style: { padding: '16', gap: '12', backgroundColor: '#eef2ff' } },
    children: [
      {
        type: 'Text',
        props: {
          text: 'QuickJS (works with quickjs_web_runtime.js on Flutter web)',
          style: { fontSize: '16', fontWeight: 'bold' }
        }
      },
      buildDomCard(),
      {
        type: 'Canvas',
        props: {
          width: 320,
          height: 160,
          commands: buildCanvasCommands()
        }
      }
    ]
  }));
}

function increment() {
  count += 1;
  colorIndex = (colorIndex + 1) % colors.length;
  renderNow();
}

function decrement() {
  count = Math.max(0, count - 1);
  colorIndex = (colorIndex + colors.length - 1) % colors.length;
  renderNow();
}

renderNow();
''';

Map<String, dynamic> _vmAstDomCanvasProgram() => {
      'type': 'program',
      'body': [
        _def('colorToggle', _bool(false)),
        _fn('renderNow', [], [
          _def('activeColor', _str('#f97316')),
          _if(
            _id('colorToggle'),
            [_assign('activeColor', _str('#0ea5e9'))],
            [_assign('activeColor', _str('#f97316'))],
          ),
          _host('dom.clear', [_obj({})]),
          _host('dom.createElement', [
            _obj({'tagName': _str('div'), 'id': _str('vmCard')}),
          ]),
          _host('dom.createElement', [
            _obj({'tagName': _str('p'), 'id': _str('vmText')}),
          ]),
          _host('dom.setTextContent', [
            _obj({
              'id': _str('vmText'),
              'text': _plus(_str('AST colorToggle: '), _id('colorToggle')),
            }),
          ]),
          _host('dom.appendChild', [
            _obj({'parentId': _str('vmCard'), 'childId': _str('vmText')}),
          ]),
          _host('canvas.clear', [_obj({})]),
          _host('canvas.setFillStyle', [
            _obj({'color': _id('activeColor')}),
          ]),
          _host('canvas.fillRect', [
            _obj({'x': _i16(20), 'y': _i16(20), 'width': _i16(180), 'height': _i16(50)}),
          ]),
          _host('render', [
            _obj({
              'type': _str('Column'),
              'props': _obj({'style': _obj({'padding': _str('16'), 'gap': _str('10')})}),
              'children': _arr([
                _obj({
                  'type': _str('Text'),
                  'props': _obj({'text': _str('Elpian VM AST controls DOM + Canvas host APIs')}),
                }),
                _obj({
                  'type': _str('Container'),
                  'props': _obj({
                    'style': _obj({
                      'padding': _str('12'),
                      'backgroundColor': _str('#ffffff'),
                      'borderRadius': _str('10'),
                    }),
                  }),
                  'children': _arr([
                    _obj({
                      'type': _str('Text'),
                      'props': _obj({'text': _plus(_str('DOM mirror: '), _id('colorToggle'))}),
                    }),
                  ]),
                }),
                _obj({
                  'type': _str('Canvas'),
                  'props': _obj({
                    'width': _i16(320),
                    'height': _i16(120),
                    'commands': _arr([
                      _obj({
                        'type': _str('setFillStyle'),
                        'params': _obj({'color': _id('activeColor')}),
                      }),
                      _obj({
                        'type': _str('fillRect'),
                        'params': _obj({
                          'x': _i16(20),
                          'y': _i16(20),
                          'width': _i16(180),
                          'height': _i16(50),
                        }),
                      }),
                    ]),
                  }),
                }),
              ]),
            }),
          ]),
        ]),
        _fn('nextColor', [], [
          _assign('colorToggle', _not(_id('colorToggle'))),
          _callStmt('renderNow', []),
        ]),
        _callStmt('renderNow', []),
      ],
    };

Map<String, dynamic> _id(String name) => {'type': 'identifier', 'data': {'name': name}};
Map<String, dynamic> _str(String value) => {'type': 'string', 'data': {'value': value}};
Map<String, dynamic> _i16(int value) => {'type': 'i16', 'data': {'value': value}};
Map<String, dynamic> _bool(bool value) => {'type': 'bool', 'data': {'value': value}};
Map<String, dynamic> _arr(List<Map<String, dynamic>> value) => {'type': 'array', 'data': {'value': value}};
Map<String, dynamic> _obj(Map<String, dynamic> value) => {'type': 'object', 'data': {'value': value}};
Map<String, dynamic> _plus(Map<String, dynamic> a, Map<String, dynamic> b) => {
      'type': 'arithmetic',
      'data': {'operation': '+', 'operand1': a, 'operand2': b},
    };
Map<String, dynamic> _not(Map<String, dynamic> value) => {'type': 'not', 'data': {'value': value}};
Map<String, dynamic> _def(String name, Map<String, dynamic> right) => {
      'type': 'definition',
      'data': {'leftSide': _id(name), 'rightSide': right},
    };
Map<String, dynamic> _assign(String name, Map<String, dynamic> right) => {
      'type': 'assignment',
      'data': {'leftSide': _id(name), 'rightSide': right},
    };
Map<String, dynamic> _callExpr(String name, List<Map<String, dynamic>> args) => {
      'type': 'functionCall',
      'data': {'callee': _id(name), 'args': args},
    };
Map<String, dynamic> _callStmt(String name, List<Map<String, dynamic>> args) => _callExpr(name, args);
Map<String, dynamic> _fn(String name, List<String> params, List<Map<String, dynamic>> body) => {
      'type': 'functionDefinition',
      'data': {'name': name, 'params': params, 'body': body},
    };
Map<String, dynamic> _host(String name, List<Map<String, dynamic>> args) => {
      'type': 'host_call',
      'data': {'name': name, 'args': args},
    };
Map<String, dynamic> _if(
  Map<String, dynamic> condition,
  List<Map<String, dynamic>> body,
  List<Map<String, dynamic>> elseBody,
) => {
      'type': 'ifStmt',
      'data': {
        'condition': condition,
        'body': body,
        'elseStmt': {
          'data': {'body': elseBody},
        },
      },
    };
