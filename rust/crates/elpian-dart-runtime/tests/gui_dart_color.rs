#![cfg(feature = "dart")]
//! The one type the merge had to reconcile.
//!
//! `gui.dart` merged the engine transport with the widget layer, and each had a
//! `Color` that meant something different: four doubles matching Godot's, and a
//! packed 0xAARRGGBB int matching Flutter's. Both spellings are written all
//! over existing guests, so the merged type answers to both — the unnamed
//! constructor dispatches on arity.
//!
//! That is the kind of accommodation that works when written and quietly rots
//! later, so these drive it on the VM rather than reading the source.

use elpian_dart_runtime::{DartCapabilitySet, DartRuntime, ResourceMeter};
use serde_json::Value;

fn texts(frame: &Value) -> Vec<String> {
    frame["root"]["ops"]
        .as_array()
        .expect("ops array")
        .iter()
        .filter(|o| o["op"] == "drawParagraph")
        .map(|o| o["text"].as_str().unwrap_or("").to_string())
        .collect()
}

/// Render one app and return the text it painted.
fn render(app: &str) -> Vec<String> {
    let mut rt = DartRuntime::from_flutter_app(
        "color",
        app,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("app compiles");
    rt.run().expect("runs main/runApp");
    texts(&rt.render_frame(16_000).expect("frame"))
}

#[test]
fn both_color_spellings_build_the_same_color() {
    let out = render(
        r#"
import 'gui.dart';

class Probe extends StatelessWidget {
  const Probe();
  Widget build(BuildContext context) {
    // The Flutter spelling and the Godot spelling of the same colour.
    var packed = Color(0xFF2196F3);
    var channels = Color(33.0 / 255.0, 150.0 / 255.0, 243.0 / 255.0, 1.0);
    return Column(children: [
      Text('packed=${packed.value}'),
      Text('channels=${channels.value}'),
      Text('r=${packed.red()} g=${packed.green()} b=${packed.blue()} a=${packed.alpha()}'),
    ]);
  }
}
void main() => runApp(Probe());
"#,
    );

    let packed = out
        .iter()
        .find(|t| t.starts_with("packed="))
        .expect("packed");
    let channels = out
        .iter()
        .find(|t| t.starts_with("channels="))
        .expect("channels");

    // 0xFF2196F3 == 4280391411. Both constructors must land on it: the packed
    // one by carrying it, the channel one by rounding back to it.
    assert_eq!(packed, "packed=4280391411", "got {out:?}");
    assert_eq!(channels, "channels=4280391411", "got {out:?}");

    assert!(
        out.iter().any(|t| t == "r=33 g=150 b=243 a=255"),
        "the channel accessors should decompose the packed form: {out:?}"
    );
}

#[test]
fn a_colour_survives_the_round_trip_through_channels() {
    // `value` is stored, not recomputed, and the channels are doubles — so the
    // rounding has to be right in both directions or a colour drifts every time
    // it is copied. `withOpacity` is the copy an app actually makes.
    let out = render(
        r#"
import 'gui.dart';

class Probe extends StatelessWidget {
  const Probe();
  Widget build(BuildContext context) {
    var c = Color(0xFF2196F3);
    var same = Color(c.value);
    var faded = c.withOpacity(1.0);
    return Column(children: [
      Text('same=${same.value}'),
      Text('faded=${faded.value}'),
      Text('half=${c.withOpacity(0.5).alpha()}'),
    ]);
  }
}
void main() => runApp(Probe());
"#,
    );
    assert!(out.contains(&"same=4280391411".to_string()), "{out:?}");
    assert!(out.contains(&"faded=4280391411".to_string()), "{out:?}");
    assert!(out.contains(&"half=128".to_string()), "{out:?}");
}
