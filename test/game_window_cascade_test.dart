import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  test('game-window cascade: !important media override beats inline at 412w', () {
    final mgr = GlobalStylesheetManager()..clear();
    mgr.global.addRule('.game-window', {
      'position': 'absolute', 'top': 96, 'left': 24, 'width': 460,
      'maxWidth': '94vw', 'maxHeight': '82vh', 'overflowY': 'auto',
      'zIndex': 30, 'pointerEvents': 'auto',
    });
    final media = CSSStylesheet()
      ..addRule('.game-window', {
        'position': 'fixed !important', 'left': '0 !important', 'top': '0 !important',
        'right': '0 !important', 'bottom': '0 !important', 'width': '100% !important',
        'maxWidth': 'none !important', 'height': '100% !important',
        'maxHeight': 'none !important', 'borderRadius': '0 !important', 'zIndex': '60 !important',
      });
    mgr.addMediaQuery('(max-width: 820px)', media);

    final computed = mgr.getComputedStyleMap(
      tagName: 'div',
      classes: ['window', 'game-window'],
      inlineStyles: {'position': 'absolute', 'left': 24, 'top': 96},
      screenWidth: 412,
      screenHeight: 915,
    );
    // ignore: avoid_print
    print('COMPUTED@412 => $computed');

    expect(computed['position'], 'fixed');
    expect(computed['left'], '0');
    expect(computed['top'], '0');
    expect(computed['right'], '0');
    expect(computed['bottom'], '0');

    // Desktop (1366w): media must NOT match → inline drag offset wins.
    final desktop = mgr.getComputedStyleMap(
      tagName: 'div', classes: ['window', 'game-window'],
      inlineStyles: {'position': 'absolute', 'left': 24, 'top': 96},
      screenWidth: 1366, screenHeight: 900,
    );
    // ignore: avoid_print
    print('COMPUTED@1366 => $desktop');
    expect(desktop['position'], 'absolute');
    expect(desktop['left'], 24);
  });
}
