import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

/// VM AST-based interactive sandbox demos.
class VmExamplePage extends StatelessWidget {
  const VmExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Elpian VM AST Sandboxes'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Counter'),
              Tab(text: 'Theme'),
              Tab(text: 'Message'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CounterAstSandbox(),
            _ThemeAstSandbox(),
            _MessageAstSandbox(),
          ],
        ),
      ),
    );
  }
}

class _CounterAstSandbox extends StatefulWidget {
  const _CounterAstSandbox();

  @override
  State<_CounterAstSandbox> createState() => _CounterAstSandboxState();
}

class _CounterAstSandboxState extends State<_CounterAstSandbox> {
  final _controller = ElpianVmController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ElpianVmScope(
            controller: _controller,
            machineId: 'vm-ast-counter',
            astJson: jsonEncode(_counterProgram()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _controller.callFunction('decrement'),
                  child: const Text('− Decrement'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _controller.callFunction('increment'),
                  child: const Text('+ Increment'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeAstSandbox extends StatefulWidget {
  const _ThemeAstSandbox();

  @override
  State<_ThemeAstSandbox> createState() => _ThemeAstSandboxState();
}

class _ThemeAstSandboxState extends State<_ThemeAstSandbox> {
  final _controller = ElpianVmController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ElpianVmScope(
            controller: _controller,
            machineId: 'vm-ast-theme',
            astJson: jsonEncode(_themeProgram()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _controller.callFunction('toggleTheme'),
              icon: const Icon(Icons.dark_mode),
              label: const Text('Toggle Theme in VM State'),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageAstSandbox extends StatefulWidget {
  const _MessageAstSandbox();

  @override
  State<_MessageAstSandbox> createState() => _MessageAstSandboxState();
}

class _MessageAstSandboxState extends State<_MessageAstSandbox> {
  final _controller = ElpianVmController();
  final _textController = TextEditingController(text: 'Hello from Flutter');

  Future<void> _sendMessage() async {
    final typedInput = jsonEncode({
      'type': 'string',
      'data': {'value': _textController.text},
    });
    await _controller.callFunction('setMessage', input: typedInput);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ElpianVmScope(
            controller: _controller,
            machineId: 'vm-ast-message',
            astJson: jsonEncode(_messageProgram()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: 'New VM message',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _sendMessage,
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}

Map<String, dynamic> _counterProgram() => {
      'type': 'program',
      'body': [
        _def('count', _i16(0)),
        _fn('buildView', [], [
          _return(_obj({
            'type': _str('Column'),
            'props': _obj({
              'style': _obj({
                'padding': _str('20'),
                'backgroundColor': _str('#f6f8ff'),
              }),
            }),
            'children': _arr([
              _obj({
                'type': _str('Text'),
                'props': _obj({
                  'text': _str('Interactive Counter (AST Program)'),
                  'style': _obj({
                    'fontSize': _str('20'),
                    'fontWeight': _str('bold'),
                  }),
                }),
              }),
              _obj({
                'type': _str('SizedBox'),
                'props': _obj({
                  'style': _obj({'height': _str('12')}),
                }),
              }),
              _obj({
                'type': _str('Text'),
                'props': _obj({
                  'text': _plus(_str('Count: '), _id('count')),
                  'style': _obj({
                    'fontSize': _str('26'),
                    'color': _str('#3f51b5'),
                    'fontWeight': _str('700'),
                  }),
                }),
              }),
            ]),
          })),
        ]),
        _fn('renderNow', [], [
          _host('render', [_callExpr('buildView', [])]),
        ]),
        _fn('increment', [], [
          _assign('count', _plus(_id('count'), _i16(1))),
          _callStmt('renderNow', []),
        ]),
        _fn('decrement', [], [
          _assign('count', _plus(_id('count'), _i16(-1))),
          _callStmt('renderNow', []),
        ]),
        _callStmt('renderNow', []),
      ],
    };

Map<String, dynamic> _themeProgram() => {
      'type': 'program',
      'body': [
        _def('isDark', _bool(false)),
        _fn('buildView', [], [
          _def('bg', _str('#ffffff')),
          _def('fg', _str('#263238')),
          _if(
            _id('isDark'),
            [
              _assign('bg', _str('#1e293b')),
              _assign('fg', _str('#f8fafc')),
            ],
            [
              _assign('bg', _str('#ffffff')),
              _assign('fg', _str('#1f2937')),
            ],
          ),
          _return(_obj({
            'type': _str('Container'),
            'props': _obj({
              'style': _obj({
                'padding': _str('20'),
                'backgroundColor': _id('bg'),
                'borderRadius': _str('12'),
              }),
            }),
            'children': _arr([
              _obj({
                'type': _str('Text'),
                'props': _obj({
                  'text': _str('Theme demo from VM AST state'),
                  'style': _obj({
                    'fontSize': _str('18'),
                    'fontWeight': _str('bold'),
                    'color': _id('fg'),
                  }),
                }),
              }),
              _obj({
                'type': _str('SizedBox'),
                'props': _obj({'style': _obj({'height': _str('8')})}),
              }),
              _obj({
                'type': _str('Text'),
                'props': _obj({
                  'text': _plus(_str('Current mode: '), _id('isDark')),
                  'style': _obj({'fontSize': _str('15'), 'color': _id('fg')}),
                }),
              }),
            ]),
          })),
        ]),
        _fn('renderNow', [], [_host('render', [_callExpr('buildView', [])])]),
        _fn('toggleTheme', [], [
          _assign('isDark', _not(_id('isDark'))),
          _callStmt('renderNow', []),
        ]),
        _callStmt('renderNow', []),
      ],
    };

Map<String, dynamic> _messageProgram() => {
      'type': 'program',
      'body': [
        _def('message', _str('Waiting for Flutter input...')),
        _fn('view', [], [
          _return(_obj({
            'type': _str('Column'),
            'props': _obj({
              'style': _obj({
                'padding': _str('20'),
                'backgroundColor': _str('#f5fff5'),
              }),
            }),
            'children': _arr([
              _obj({
                'type': _str('Text'),
                'props': _obj({
                  'text': _str('Send typed VM input from Flutter'),
                  'style': _obj({
                    'fontSize': _str('18'),
                    'fontWeight': _str('bold'),
                    'color': _str('#1b5e20'),
                  }),
                }),
              }),
              _obj({
                'type': _str('SizedBox'),
                'props': _obj({'style': _obj({'height': _str('10')})}),
              }),
              _obj({
                'type': _str('Text'),
                'props': _obj({
                  'text': _id('message'),
                  'style': _obj({'fontSize': _str('16'), 'color': _str('#2e7d32')}),
                }),
              }),
            ]),
          })),
        ]),
        _fn('renderNow', [], [_host('render', [_callExpr('view', [])])]),
        _fn('setMessage', ['nextMessage'], [
          _assign('message', _id('nextMessage')),
          _callStmt('renderNow', []),
        ]),
        _callStmt('renderNow', []),
      ],
    };

Map<String, dynamic> _id(String name) => {
      'type': 'identifier',
      'data': {'name': name},
    };
Map<String, dynamic> _str(String value) => {
      'type': 'string',
      'data': {'value': value},
    };
Map<String, dynamic> _i16(int value) => {
      'type': 'i16',
      'data': {'value': value},
    };
Map<String, dynamic> _bool(bool value) => {
      'type': 'bool',
      'data': {'value': value},
    };
Map<String, dynamic> _arr(List<Map<String, dynamic>> value) => {
      'type': 'array',
      'data': {'value': value},
    };
Map<String, dynamic> _obj(Map<String, dynamic> value) => {
      'type': 'object',
      'data': {'value': value},
    };
Map<String, dynamic> _plus(Map<String, dynamic> a, Map<String, dynamic> b) => {
      'type': 'arithmetic',
      'data': {'operation': '+', 'operand1': a, 'operand2': b},
    };
Map<String, dynamic> _not(Map<String, dynamic> value) => {
      'type': 'not',
      'data': {'value': value},
    };
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
Map<String, dynamic> _callStmt(String name, List<Map<String, dynamic>> args) =>
    _callExpr(name, args);
Map<String, dynamic> _fn(
  String name,
  List<String> params,
  List<Map<String, dynamic>> body,
) => {
      'type': 'functionDefinition',
      'data': {'name': name, 'params': params, 'body': body},
    };
Map<String, dynamic> _return(Map<String, dynamic> value) => {
      'type': 'returnOperation',
      'data': {'value': value},
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
