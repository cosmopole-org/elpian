#![cfg(feature = "dart")]
//! End-to-end test of the imported `flutter.dart` library: the realistic
//! `demo_app.dart` (MaterialApp/Scaffold/AppBar/Card/Row/Column/ElevatedButton/
//! StatefulWidget) compiles, lays out, paints a scene, and responds to taps.

use dart::binding::{PointerEvent, PointerPhase};
use dart::{DartCapabilitySet, DartRuntime, ResourceMeter};
use serde_json::Value;

const DEMO: &str = include_str!("../flutter/demo_app.dart");

fn ops(frame: &Value) -> &Vec<Value> {
    frame["root"]["ops"].as_array().expect("ops array")
}
fn texts(frame: &Value) -> Vec<String> {
    ops(frame).iter().filter(|o| o["op"] == "drawParagraph")
        .map(|o| o["text"].as_str().unwrap().to_string()).collect()
}
fn tap(rt: &mut DartRuntime, x: f64, y: f64) {
    rt.dispatch_pointer(PointerEvent { pointer: 1, phase: PointerPhase::Down, x, y });
    rt.dispatch_pointer(PointerEvent { pointer: 1, phase: PointerPhase::Up, x, y });
}

#[test]
fn demo_app_renders_and_is_interactive() {
    let mut rt = DartRuntime::from_flutter_app(
        "demo", DEMO, DartCapabilitySet::full(), ResourceMeter::unbounded(),
    ).expect("demo_app.dart (importing flutter.dart) compiles");
    rt.run().expect("runs main/runApp");
    assert!(rt.needs_frame(), "runApp schedules a frame");

    let f0 = rt.render_frame(16_000).expect("frame 0");
    let t0 = texts(&f0);
    // The app chrome + initial state are all present.
    assert!(t0.contains(&"Elpian Dashboard".to_string()), "app bar title: {t0:?}");
    assert!(t0.contains(&"COUNTER".to_string()), "counter card label: {t0:?}");
    assert!(t0.contains(&"0".to_string()), "counter starts at 0: {t0:?}");
    // The counter value plus the three derived stat chips (value, double,
    // square) are all "0" at start.
    assert_eq!(t0.iter().filter(|s| *s == "0").count(), 4, "counter + 3 chips = 0: {t0:?}");

    // A green "+" ElevatedButton sits in the counter card. Find where by scanning;
    // instead of guessing pixels, tap the known green button color region: the
    // buttons are in a spaceEvenly Row inside a centered card. Tap the right half
    // (the "+" button) a few times by locating its green rect.
    let plus = green_button_center(&f0, true);
    for _ in 0..3 {
        tap(&mut rt, plus.0, plus.1);
    }
    let f1 = rt.render_frame(32_000).expect("frame 1");
    let t1 = texts(&f1);
    assert!(t1.contains(&"3".to_string()), "counter -> 3 after 3 taps: {t1:?}");
    assert!(t1.contains(&"6".to_string()), "double -> 6: {t1:?}");
    assert!(t1.contains(&"9".to_string()), "square -> 9: {t1:?}");

    // The red "–" button decrements (floored at 0).
    let minus = green_button_center(&f1, false);
    tap(&mut rt, minus.0, minus.1);
    let f2 = rt.render_frame(48_000).expect("frame 2");
    assert!(texts(&f2).contains(&"2".to_string()), "counter -> 2 after a decrement");
}

/// Find the center of the increment (green) or decrement (red) button rect in a
/// frame by its fill color.
fn green_button_center(frame: &Value, plus: bool) -> (f64, f64) {
    let want = if plus { 4283215696u64 } else { 4294198070u64 }; // Colors.green / Colors.red
    for o in ops(frame) {
        if o["op"] == "drawRect" && o["color"].as_u64() == Some(want) {
            let r = o["rect"].as_array().unwrap();
            let (l, t, rr, b) = (r[0].as_f64().unwrap(), r[1].as_f64().unwrap(),
                                 r[2].as_f64().unwrap(), r[3].as_f64().unwrap());
            return ((l + rr) / 2.0, (t + b) / 2.0);
        }
    }
    panic!("no {} button rect found", if plus { "green" } else { "red" });
}
