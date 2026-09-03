#![cfg(feature = "dart")]
//! The layers `gui.dart` adds beyond the two libraries it merged.
//!
//! `gui.js` carries a widget registry, a component model, Scene3D and Canvas
//! controllers, a theme and a `GUI` namespace. The Dart side had none of that:
//! it had an engine transport and a widget library, and nothing on top. These
//! drive the parts that can run here — Canvas and the theme — on the VM.
//!
//! `Scene3DController` is not exercised here and cannot be: it drives Godot
//! nodes through `GD`, and this runtime services `dart:ui`, not `godot.op`.
//! It is compiled by `guest_sdk.rs` and its shape mirrors the JavaScript twin
//! that `gui_sdk.rs` does drive; that is weaker coverage than the rest of this
//! file and worth saying so rather than implying otherwise.

use elpian_dart_runtime::{DartCapabilitySet, DartRuntime, ResourceMeter};
use serde_json::Value;

fn frame(app: &str) -> Value {
    let mut rt = DartRuntime::from_flutter_app(
        "gui",
        app,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("app compiles");
    rt.run().expect("runs main/runApp");
    rt.render_frame(16_000).expect("frame")
}

fn ops(f: &Value) -> Vec<String> {
    f["root"]["ops"]
        .as_array()
        .expect("ops")
        .iter()
        .map(|o| o["op"].as_str().unwrap_or("").to_string())
        .collect()
}

#[test]
fn the_canvas_widget_paints_what_its_painter_draws() {
    let f = frame(
        r#"
import 'gui.dart';

class Chart extends StatelessWidget {
  const Chart();
  Widget build(BuildContext context) {
    return Canvas(width: 200.0, height: 80.0, painter: (c) {
      c.rect(0.0, 0.0, 200.0, 80.0, Color(0xFF11202B));
      c.circle(40.0, 40.0, 12.0, Color(0xFF52C0AE));
      c.line(0.0, 80.0, 200.0, 0.0, Color(0xFFE0725A), 2.0);
      c.text(8.0, 16.0, 'hi', Color(0xFFDEE7E3), 12.0);
    });
  }
}
void main() => runApp(Chart());
"#,
    );
    let got = ops(&f);
    for want in ["drawRect", "drawCircle", "drawPath", "drawParagraph"] {
        assert!(
            got.contains(&want.to_string()),
            "the painter's {want} never reached the scene: {got:?}"
        );
    }
}

#[test]
fn canvas_drawing_is_offset_into_the_widgets_own_box() {
    // The controller takes canvas-local coordinates and adds the widget's
    // offset. If it did not, every canvas would paint at the top-left of the
    // window regardless of where it was laid out — which looks fine in a
    // full-screen test and wrong in every real layout.
    let f = frame(
        r#"
import 'gui.dart';

class Shifted extends StatelessWidget {
  const Shifted();
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(30.0),
      child: Canvas(width: 50.0, height: 50.0, painter: (c) {
        c.rect(0.0, 0.0, 10.0, 10.0, Color(0xFF52C0AE));
      }),
    );
  }
}
void main() => runApp(Shifted());
"#,
    );
    let rect = f["root"]["ops"]
        .as_array()
        .expect("ops")
        .iter()
        .find(|o| o["op"] == "drawRect")
        .expect("a rect was painted");
    let r = rect["rect"].as_array().expect("rect corners");
    assert_eq!(
        (r[0].as_f64(), r[1].as_f64()),
        (Some(30.0), Some(30.0)),
        "canvas-local (0,0) should land at the widget's offset: {rect}"
    );
}

#[test]
fn the_theme_is_shared_and_replaceable() {
    let f = frame(
        r#"
import 'gui.dart';

class Probe extends StatelessWidget {
  const Probe();
  Widget build(BuildContext context) {
    var dark = GUI.theme();
    GUI.useTheme(GuiTheme.light());
    var light = GUI.theme();
    return Column(children: [
      Text('dark=${dark.surface.value}'),
      Text('light=${light.surface.value}'),
      Text('touch=${light.minTouch}'),
    ]);
  }
}
void main() => runApp(Probe());
"#,
    );
    let texts: Vec<String> = f["root"]["ops"]
        .as_array()
        .expect("ops")
        .iter()
        .filter(|o| o["op"] == "drawParagraph")
        .map(|o| o["text"].as_str().unwrap_or("").to_string())
        .collect();

    // 0xFF0D1413 dark surface, 0xFFF6F8F7 light surface.
    assert!(texts.contains(&"dark=4279047187".to_string()), "{texts:?}");
    assert!(texts.contains(&"light=4294375671".to_string()), "{texts:?}");
    assert!(
        texts.iter().any(|t| t.starts_with("touch=48")),
        "the token set should carry the 48dp touch target: {texts:?}"
    );
}
