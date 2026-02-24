import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ElpianAstVmApp());
}

class ElpianAstVmApp extends StatelessWidget {
  const ElpianAstVmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian AST VM Examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const ElpianAstVmExamplesPage(),
    );
  }
}

class ElpianAstVmExamplesPage extends StatelessWidget {
  const ElpianAstVmExamplesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Elpian AST VM Examples'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Tap (0 args)'),
              Tab(text: 'Tap Payload'),
              Tab(text: 'Input Event'),
              Tab(text: 'Scoped Rerender'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AstVmExampleFrame(
              machineId: 'ast-main-zero-arg-tap',
              description:
                  'Tap the card. Handler has zero params and rerenders from VM state.',
              programFactory: _zeroArgTapProgram,
            ),
            _AstVmExampleFrame(
              machineId: 'ast-main-tap-payload',
              description:
                  'Tap the card. Handler reads event.type and event.currentTarget from payload.',
              programFactory: _tapPayloadProgram,
            ),
            _AstVmExampleFrame(
              machineId: 'ast-main-input-event',
              description:
                  'Type in the input. VM receives input event payload and rerenders text.',
              programFactory: _inputEventProgram,
            ),
            _AstVmExampleFrame(
              machineId: 'ast-main-scope-rerender',
              description:
                  'Tap counter card. VM rerenders only the Scope subtree using scope key.',
              programFactory: _scopeRerenderProgram,
            ),
          ],
        ),
      ),
    );
  }
}

class _AstVmExampleFrame extends StatelessWidget {
  final String machineId;
  final String description;
  final Map<String, dynamic> Function() programFactory;

  const _AstVmExampleFrame({
    required this.machineId,
    required this.description,
    required this.programFactory,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ElpianVmWidget.fromAst(
                machineId: machineId,
                astJson: jsonEncode(programFactory()),
                onPrintln: (msg) => debugPrint('[$machineId] $msg'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _zeroArgTapProgram() => {
      'type': 'program',
      'body': [
        _def('count', _i16(0)),
        _fn('buildView', [], [
          _return(
            _obj({
              'type': _str('Column'),
              'props': _obj({
                'style': _obj({'padding': _str('18'), 'gap': _str('12')}),
              }),
              'children': _arr([
                _obj({
                  'type': _str('Text'),
                  'props': _obj({
                    'text': _str('Zero-arg event handler'),
                    'style': _obj(
                        {'fontSize': _str('18'), 'fontWeight': _str('bold')}),
                  }),
                }),
                _obj({
                  'type': _str('Container'),
                  'key': _str('zero_arg_tap_card'),
                  'props': _obj({
                    'style': _obj({
                      'padding': _str('14'),
                      'borderRadius': _str('10'),
                      'backgroundColor': _str('#ecfeff'),
                    }),
                  }),
                  'events': _obj({'tap': _str('increment')}),
                  'children': _arr([
                    _obj({
                      'type': _str('Text'),
                      'props': _obj({
                        'text': _plus(_str('Tap Count: '), _id('count')),
                        'style': _obj(
                            {'fontSize': _str('20'), 'color': _str('#0f766e')}),
                      }),
                    }),
                    _obj({
                      'type': _str('Text'),
                      'props':
                          _obj({'text': _str('Tap anywhere on this card')}),
                    }),
                  ]),
                }),
              ]),
            }),
          ),
        ]),
        _fn('renderNow', [], [
          _host('render', [_callExpr('buildView', [])])
        ]),
        _fn('increment', [
          'event'
        ], [
          _assign('count', _plus(_id('count'), _i16(1))),
          _callStmt('renderNow', []),
        ]),
        _callStmt('renderNow', []),
      ],
    };

Map<String, dynamic> _tapPayloadProgram() => {
      'type': 'program',
      'body': [
        _def('count', _i16(0)),
        _def('lastType', _str('none')),
        _def('lastTarget', _str('none')),
        _fn('buildView', [], [
          _return(
            _obj({
              'type': _str('Column'),
              'props': _obj({
                'style': _obj({'padding': _str('18'), 'gap': _str('10')}),
              }),
              'children': _arr([
                _obj({
                  'type': _str('Text'),
                  'props': _obj({
                    'text': _str('Tap payload handler'),
                    'style': _obj(
                        {'fontSize': _str('18'), 'fontWeight': _str('bold')}),
                  }),
                }),
                _obj({
                  'type': _str('Container'),
                  'key': _str('payload_tap_card'),
                  'props': _obj({
                    'style': _obj({
                      'padding': _str('14'),
                      'borderRadius': _str('10'),
                      'backgroundColor': _str('#eff6ff'),
                    }),
                  }),
                  'events': _obj({'tap': _str('handleTap')}),
                  'children': _arr([
                    _obj({
                      'type': _str('Text'),
                      'props':
                          _obj({'text': _plus(_str('Count: '), _id('count'))}),
                    }),
                    _obj({
                      'type': _str('Text'),
                      'props': _obj({
                        'text': _plus(_str('Last type: '), _id('lastType'))
                      }),
                    }),
                    _obj({
                      'type': _str('Text'),
                      'props': _obj({
                        'text': _plus(_str('Last target: '), _id('lastTarget')),
                      }),
                    }),
                  ]),
                }),
              ]),
            }),
          ),
        ]),
        _fn('renderNow', [], [
          _host('render', [_callExpr('buildView', [])])
        ]),
        _fn('handleTap', [
          'event'
        ], [
          _assign('count', _plus(_id('count'), _i16(1))),
          _assign('lastType', _index(_id('event'), _str('type'))),
          _assign('lastTarget', _index(_id('event'), _str('currentTarget'))),
          _callStmt('renderNow', []),
        ]),
        _callStmt('renderNow', []),
      ],
    };

Map<String, dynamic> _inputEventProgram() => {
      'type': 'program',
      'body': [
        _def('textValue', _str('Type in the field below')),
        _fn('buildView', [], [
          _return(
            _obj({
              'type': _str('Column'),
              'props': _obj({
                'style': _obj({'padding': _str('18'), 'gap': _str('10')}),
              }),
              'children': _arr([
                _obj({
                  'type': _str('Text'),
                  'props': _obj({
                    'text': _str('Input event -> VM state'),
                    'style': _obj(
                        {'fontSize': _str('18'), 'fontWeight': _str('bold')}),
                  }),
                }),
                _obj({
                  'type': _str('TextField'),
                  'key': _str('main_input_field'),
                  'props': _obj({'hint': _str('Type something...')}),
                  'events': _obj({'input': _str('onInput')}),
                }),
                _obj({
                  'type': _str('Container'),
                  'props': _obj({
                    'style': _obj({
                      'padding': _str('12'),
                      'borderRadius': _str('10'),
                      'backgroundColor': _str('#f0fdf4'),
                    }),
                  }),
                  'children': _arr([
                    _obj({
                      'type': _str('Text'),
                      'props': _obj({
                        'text':
                            _plus(_str('Current VM text: '), _id('textValue')),
                      }),
                    }),
                  ]),
                }),
              ]),
            }),
          ),
        ]),
        _fn('renderNow', [], [
          _host('render', [_callExpr('buildView', [])])
        ]),
        _fn('onInput', [
          'event'
        ], [
          _assign('textValue', _index(_id('event'), _str('value'))),
          _callStmt('renderNow', []),
        ]),
        _callStmt('renderNow', []),
      ],
    };

Map<String, dynamic> _scopeRerenderProgram() => {
      'type': 'program',
      'body': [
        _def('count', _i16(0)),
        _fn('counterCard', [], [
          _return(
            _obj({
              'type': _str('Container'),
              'key': _str('scope_counter_card'),
              'props': _obj({
                'style': _obj({
                  'padding': _str('14'),
                  'borderRadius': _str('10'),
                  'backgroundColor': _str('#fff7ed'),
                }),
              }),
              'events': _obj({'tap': _str('incrementScope')}),
              'children': _arr([
                _obj({
                  'type': _str('Text'),
                  'props': _obj({
                    'text': _str('Scoped rerender card (tap me)'),
                    'style': _obj({'fontWeight': _str('bold')}),
                  }),
                }),
                _obj({
                  'type': _str('Text'),
                  'props': _obj({
                    'text': _plus(_str('Count: '), _id('count')),
                    'style': _obj(
                        {'fontSize': _str('20'), 'color': _str('#c2410c')}),
                  }),
                }),
              ]),
            }),
          ),
        ]),
        _fn('scopeNode', [], [
          _return(
            _obj({
              'type': _str('Scope'),
              'key': _str('counter_scope'),
              'children': _arr([
                _callExpr('counterCard', []),
              ]),
            }),
          ),
        ]),
        _fn('fullView', [], [
          _return(
            _obj({
              'type': _str('Column'),
              'props': _obj({
                'style': _obj({'padding': _str('18'), 'gap': _str('10')}),
              }),
              'children': _arr([
                _obj({
                  'type': _str('Text'),
                  'props': _obj({
                    'text': _str('Scope rerender demo'),
                    'style': _obj(
                        {'fontSize': _str('18'), 'fontWeight': _str('bold')}),
                  }),
                }),
                _callExpr('scopeNode', []),
                _obj({
                  'type': _str('Text'),
                  'props': _obj({
                    'text': _str('Footer stays stable while scope updates')
                  }),
                }),
              ]),
            }),
          ),
        ]),
        _fn('renderAll', [], [
          _host('render', [_callExpr('fullView', [])])
        ]),
        _fn('renderScopeOnly', [], [
          _host('render', [_callExpr('scopeNode', []), _str('counter_scope')]),
        ]),
        _fn('incrementScope', [
          'event'
        ], [
          _assign('count', _plus(_id('count'), _i16(1))),
          _callStmt('renderScopeOnly', []),
        ]),
        _callStmt('renderAll', []),
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

Map<String, dynamic> _arr(List<Map<String, dynamic>> value) => {
      'type': 'array',
      'data': {'value': value},
    };

Map<String, dynamic> _obj(Map<String, dynamic> value) => {
      'type': 'object',
      'data': {'value': value},
    };

Map<String, dynamic> _plus(
        Map<String, dynamic> left, Map<String, dynamic> right) =>
    {
      'type': 'arithmetic',
      'data': {
        'operation': '+',
        'operand1': left,
        'operand2': right,
      },
    };

Map<String, dynamic> _index(
        Map<String, dynamic> target, Map<String, dynamic> key) =>
    {
      'type': 'indexer',
      'data': {
        'target': target,
        'index': key,
      },
    };

Map<String, dynamic> _def(String name, Map<String, dynamic> rightSide) => {
      'type': 'definition',
      'data': {
        'leftSide': _id(name),
        'rightSide': rightSide,
      },
    };

Map<String, dynamic> _assign(String name, Map<String, dynamic> rightSide) => {
      'type': 'assignment',
      'data': {
        'leftSide': _id(name),
        'rightSide': rightSide,
      },
    };

Map<String, dynamic> _fn(
  String name,
  List<String> params,
  List<Map<String, dynamic>> body,
) =>
    {
      'type': 'functionDefinition',
      'data': {
        'name': name,
        'params': params,
        'body': body,
      },
    };

Map<String, dynamic> _callExpr(String name, List<Map<String, dynamic>> args) =>
    {
      'type': 'functionCall',
      'data': {
        'callee': _id(name),
        'args': args,
      },
    };

Map<String, dynamic> _callStmt(String name, List<Map<String, dynamic>> args) =>
    _callExpr(name, args);

Map<String, dynamic> _host(String name, List<Map<String, dynamic>> args) => {
      'type': 'host_call',
      'data': {
        'name': name,
        'args': args,
      },
    };

Map<String, dynamic> _return(Map<String, dynamic> value) => {
      'type': 'returnOperation',
      'data': {'value': value},
    };
