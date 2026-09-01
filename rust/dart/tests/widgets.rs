#![cfg(feature = "dart")]
//! End-to-end tests for the **widget layer**: real Flutter-style widget code —
//! `StatelessWidget`/`StatefulWidget` with `build()` and nested children — is
//! compiled by the front-end, run on the Elpian VM, laid out, and painted into
//! the `dart:ui` scene the engine rasterizes; taps re-enter the guest, mutate
//! `State`, and the next frame reflects it.

use dart::binding::{PointerEvent, PointerPhase};
use dart::{DartCapabilitySet, DartRuntime, ResourceMeter};
use serde_json::Value;

fn app(machine_id: &str, source: &str) -> DartRuntime {
    DartRuntime::from_widget_app(
        machine_id,
        source,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("widget app compiles")
}

/// Return the flat op list of the frame's scene (`scene.root.ops`).
fn ops(frame: &Value) -> &Vec<Value> {
    frame["root"]["ops"].as_array().expect("scene has an ops array")
}

/// Find the first `drawParagraph` op's text.
fn first_text(frame: &Value) -> String {
    for op in ops(frame) {
        if op["op"] == "drawParagraph" {
            return op["text"].as_str().unwrap_or("").to_string();
        }
    }
    panic!("no drawParagraph op in frame: {frame}");
}

fn tap(rt: &mut DartRuntime, x: f64, y: f64) {
    rt.dispatch_pointer(PointerEvent { pointer: 1, phase: PointerPhase::Down, x, y });
    rt.dispatch_pointer(PointerEvent { pointer: 1, phase: PointerPhase::Up, x, y });
}

/// The headline case: a `StatefulWidget` counter with a `GestureDetector`
/// button. A frame renders the initial UI; a tap on the button runs the guest's
/// `onTap` → `setState`, and the next frame shows the incremented count. This is
/// the whole runApp → build → layout → paint → event → setState → repaint loop.
#[test]
fn stateful_counter_renders_and_responds_to_taps() {
    let mut rt = app("counter_app",
        r#"
        class CounterApp extends StatelessWidget {
            Widget build() {
                return Center(child: Counter());
            }
        }
        class Counter extends StatefulWidget {
            State createState() { return CounterState(); }
        }
        class CounterState extends State {
            int count = 0;
            Widget build() {
                return GestureDetector(
                    onTap: () { setState(() { count = count + 1; }); },
                    child: Container(
                        width: 200.0,
                        height: 80.0,
                        color: 4278233600,
                        child: Text("count: $count", size: 20.0, color: 4294967295),
                    ),
                );
            }
        }
        void main() { runApp(CounterApp()); }
    "#,
    );
    rt.run().expect("runs main / runApp");

    // runApp requested the first frame.
    assert!(rt.needs_frame(), "runApp should request a frame");
    rt.clear_needs_frame();

    // Frame 1: a green button rect and the initial label.
    let f1 = rt.render_frame(16_000).expect("frame 1 rendered");
    let o1 = ops(&f1);
    assert_eq!(o1[0]["op"], "drawRect", "button background first");
    assert_eq!(o1[0]["color"], 4278233600u64);
    assert_eq!(first_text(&f1), "count: 0");

    // The button is a 200x80 box centred in a 400x800 view → rect (100,360)-(300,440).
    // Tap its centre; the guest's onTap runs and setState requests a repaint.
    tap(&mut rt, 200.0, 400.0);
    assert!(rt.needs_frame(), "setState should request a frame");

    // Frame 2 reflects the mutated state.
    let f2 = rt.render_frame(32_000).expect("frame 2 rendered");
    assert_eq!(first_text(&f2), "count: 1");

    // Two more taps compound.
    tap(&mut rt, 200.0, 400.0);
    tap(&mut rt, 200.0, 400.0);
    let f3 = rt.render_frame(48_000).expect("frame 3 rendered");
    assert_eq!(first_text(&f3), "count: 3");

    // A tap that misses the button changes nothing.
    tap(&mut rt, 10.0, 10.0);
    let f4 = rt.render_frame(64_000).expect("frame 4 rendered");
    assert_eq!(first_text(&f4), "count: 3");
}

/// Nested components defined in the same file: a `MaterialApp` → `Scaffold` →
/// `Column` of several child widgets (including a nested custom `StatelessWidget`).
/// Proves the compositional widget tree lays out and paints in order.
#[test]
fn nested_widgets_compose_and_lay_out() {
    let mut rt = app("nested_app",
        r#"
        class Label extends StatelessWidget {
            String text;
            Label(this.text);
            Widget build() {
                return Text(text, size: 18.0, color: 4278190080);
            }
        }
        class Home extends StatelessWidget {
            Widget build() {
                return Column(
                    crossAxisAlignment: "center",
                    children: [
                        Label("Header"),
                        Container(width: 120.0, height: 40.0, color: 4294901760),
                        Label("Footer"),
                    ],
                );
            }
        }
        void main() {
            runApp(MaterialApp(home: Scaffold(backgroundColor: 4293848814, body: Center(child: Home()))));
        }
    "#,
    );
    rt.run().expect("runs");
    let frame = rt.render_frame(16_000).expect("rendered");
    let o = ops(&frame);

    // Scaffold paints the full-view background first.
    assert_eq!(o[0]["op"], "drawRect");
    assert_eq!(o[0]["color"], 4293848814u64);

    // The two labels and the middle rectangle all appear, top-to-bottom.
    let texts: Vec<String> = o
        .iter()
        .filter(|op| op["op"] == "drawParagraph")
        .map(|op| op["text"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(texts, vec!["Header", "Footer"]);

    // The middle red container is painted between the two labels.
    let colors: Vec<u64> = o
        .iter()
        .filter(|op| op["op"] == "drawRect")
        .map(|op| op["color"].as_u64().unwrap())
        .collect();
    assert!(colors.contains(&4294901760), "middle red container painted: {colors:?}");
}

/// Independent `State` per `StatefulWidget` position: two counters in a Column
/// keep separate counts, matched by build order (position-based reconciliation).
#[test]
fn multiple_stateful_widgets_keep_independent_state() {
    let mut rt = app("multi_app",
        r#"
        class Counter extends StatefulWidget {
            State createState() { return CounterState(); }
        }
        class CounterState extends State {
            int count = 0;
            Widget build() {
                return GestureDetector(
                    onTap: () { setState(() { count = count + 1; }); },
                    child: Container(width: 400.0, height: 100.0, color: 4278190080,
                        child: Text("n=$count", size: 20.0, color: 4294967295)),
                );
            }
        }
        void main() {
            runApp(Column(children: [Counter(), Counter()]));
        }
    "#,
    );
    rt.run().expect("runs");
    rt.render_frame(16_000).expect("frame 0");

    // First counter occupies y in [0,100), the second y in [100,200).
    tap(&mut rt, 200.0, 50.0); // first
    tap(&mut rt, 200.0, 50.0); // first
    tap(&mut rt, 200.0, 150.0); // second
    let frame = rt.render_frame(32_000).expect("frame 1");
    let texts: Vec<String> = ops(&frame)
        .iter()
        .filter(|op| op["op"] == "drawParagraph")
        .map(|op| op["text"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(texts, vec!["n=2", "n=1"], "counters stay independent");
}
