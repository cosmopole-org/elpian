import 'package:elpian_ui/src/models/elpian_node.dart';
import 'package:elpian_ui/src/widgets/elpian_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elpian_ui/src/scope/scoped_components.dart';

void main() {
  test('example component helper gives every direct component its own scope',
      () {
    final tree = <String, dynamic>{
      'type': 'Column',
      'children': [
        {
          'type': 'Text',
          'props': {'text': 'header'}
        },
        {'type': 'Container', 'key': 'content'},
      ],
    };

    isolateComponentChildren(tree, 'demo');
    final children = tree['children'] as List;
    expect(children, hasLength(2));
    expect((children[0] as Map)['type'], 'Scope');
    expect((children[0] as Map)['key'], 'demo-component-0__scope');
    expect(((children[0] as Map)['children'] as List).single['key'],
        'demo-component-0');
    expect((children[1] as Map)['key'], 'content__scope');
    expect(((children[1] as Map)['children'] as List).single['key'], 'content');
  });

  testWidgets('changing one scope token rebuilds only that component',
      (tester) async {
    final harnessKey = GlobalKey<_ScopeHarnessState>();
    final builds = <String, int>{'left': 0, 'right': 0};

    await tester.pumpWidget(MaterialApp(
      home: _ScopeHarness(key: harnessKey, builds: builds),
    ));
    expect(builds, {'left': 1, 'right': 1});

    harnessKey.currentState!.rerenderLeft();
    await tester.pump();

    expect(builds['left'], 2,
        reason: 'the targeted scope must accept its new child');
    expect(builds['right'], 1,
        reason: 'the sibling scope must retain its cached child');
  });
}

class _ScopeHarness extends StatefulWidget {
  final Map<String, int> builds;

  const _ScopeHarness({super.key, required this.builds});

  @override
  State<_ScopeHarness> createState() => _ScopeHarnessState();
}

class _ScopeHarnessState extends State<_ScopeHarness> {
  int _leftToken = 0;

  void rerenderLeft() => setState(() => _leftToken++);

  @override
  Widget build(BuildContext context) {
    Widget probe(String name) => Builder(builder: (_) {
          widget.builds[name] = widget.builds[name]! + 1;
          return Text(name);
        });

    return Row(children: [
      ElpianScope.build(
        ElpianNode(type: 'Scope', props: {
          '__scopeRenderToken': _leftToken,
        }),
        [probe('left')],
      ),
      ElpianScope.build(
        const ElpianNode(type: 'Scope', props: {
          '__scopeRenderToken': 0,
        }),
        [probe('right')],
      ),
    ]);
  }
}
