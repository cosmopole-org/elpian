#![cfg(feature = "dart")]
//! End-to-end tests: real guest code runs on the Elpian VM and drives the
//! `dart:*` foundational libraries through the governed host seam.

use dart::binding::{PointerEvent, PointerPhase};
use dart::bundle::{BundleLoader, CodeBundle, HmacSha256Scheme};
use dart::{DartCapability, DartCapabilitySet, DartRuntime, ResourceMeter};

/// A `dart:typed_data` round-trip driven entirely from guest code: allocate a
/// ByteData, write an Int32, read it back, and emit the result. This exercises
/// the full loop — guest `askHost` → envelope parse → governance → library →
/// resume with reply → guest observes the value.
#[test]
fn guest_drives_typed_data_roundtrip() {
    let code = r#"
        var buf = askHost("dart:typed_data/ByteData.alloc", [8]);
        askHost("dart:typed_data/ByteData.setInt32", [buf, 0, 1234567, true]);
        var v = askHost("dart:typed_data/ByteData.getInt32", [buf, 0, true]);
        askHost("test.emit", [v]);
    "#;
    let mut rt = DartRuntime::from_js(
        "td_test",
        code,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(rt.emitted(), &[serde_json::json!(1234567)]);
}

/// A `dart:ui` recording driven from guest code, composed into a scene tree.
#[test]
fn guest_records_a_ui_scene() {
    let code = r#"
        askHost("dart:ui/PictureRecorder.beginRecording", []);
        askHost("dart:ui/Canvas.drawRect", [0.0, 0.0, 100.0, 50.0, 4294901760]);
        var pic = askHost("dart:ui/PictureRecorder.endRecording", []);
        var scene = askHost("dart:ui/Picture.toScene", [pic]);
        askHost("test.emit", [scene]);
    "#;
    let mut rt = DartRuntime::from_js(
        "ui_test",
        code,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    let scene = &rt.emitted()[0];
    assert_eq!(scene["root"]["ops"][0]["op"], "drawRect");
    assert_eq!(scene["root"]["ops"][0]["color"], 4294901760u64);
}

/// Guest uses `dart:math` (seeded Random) and `dart:core` (DateTime.now with a
/// pinned clock) end-to-end, proving the core/math wiring and determinism.
#[test]
fn guest_uses_core_and_math() {
    let code = r#"
        var rng = askHost("dart:math/Random", [42]);
        var a = askHost("dart:math/Random.nextInt", [rng, 1000]);
        var now = askHost("dart:core/DateTime.now", []);
        askHost("test.emit", [a]);
        askHost("test.emit", [now]);
    "#;
    let mut rt = DartRuntime::from_js(
        "core_test",
        code,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles")
    .with_fixed_clock(1_700_000_000_000);
    rt.run().expect("runs");
    // Seed 42 is deterministic; assert the value is in range and the clock pinned.
    let a = rt.emitted()[0].as_i64().unwrap();
    assert!((0..1000).contains(&a));
    assert_eq!(rt.emitted()[1], serde_json::json!(1_700_000_000_000i64));
}

/// Phase 3: real **Dart source** compiled by the front-end and executed on the
/// VM end-to-end. Exercises typed locals, a C-style `for` (lowered to `while`),
/// `~/`, a function call, string interpolation, and reaching the host bridge.
#[test]
fn runs_real_dart_source() {
    let dart = r#"
        int sumTo(int n) {
            int total = 0;
            for (int i = 1; i <= n; i = i + 1) {
                total = total + i;
            }
            return total;
        }
        void main() {
            int s = sumTo(10);
            int half = s ~/ 2;
            askHost("test.emit", ["sum=$s half=$half"]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "dart_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("dart compiles");
    rt.run().expect("runs");
    // 1+..+10 = 55; 55 ~/ 2 = 27.
    assert_eq!(rt.emitted(), &[serde_json::json!("sum=55 half=27")]);
}

/// The async event loop drives real guest callbacks in Dart's exact order:
/// microtasks before timers, with nested scheduling handled correctly. The guest
/// routes scheduled callbacks through `__dartDispatch`, exactly as generated Dart
/// glue would.
#[test]
fn event_loop_runs_callbacks_in_dart_order() {
    let code = r#"
        function __dartDispatch(a) {
            var id = a[0];
            askHost("test.emit", ["cb" + id]);
            // callback 3 (a microtask) schedules a further microtask, cb 4,
            // which must still run before the already-scheduled timer cb 2.
            if (id == 3) { askHost("dart:async/scheduleMicrotask", [4]); }
        }
        askHost("dart:async/scheduleMicrotask", [1]);
        askHost("dart:async/Timer", [2, 10]);
        askHost("dart:async/scheduleMicrotask", [3]);
    "#;
    let mut rt = DartRuntime::from_js(
        "async_test",
        code,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    let order: Vec<String> = rt
        .emitted()
        .iter()
        .map(|v| v.as_str().unwrap().to_string())
        .collect();
    // 1 and 3 (microtasks) first; 3 schedules 4 which still precedes the timer 2.
    assert_eq!(order, vec!["cb1", "cb3", "cb4", "cb2"]);
}

/// Governance: with the `Painting` capability revoked, a `dart:ui` call is
/// denied by the governor and the guest receives a thrown-error envelope rather
/// than reaching the library.
#[test]
fn revoked_capability_denies_the_call() {
    let code = r#"
        var r = askHost("dart:ui/PictureRecorder.beginRecording", []);
        askHost("test.emit", [r]);
    "#;
    let mut caps = DartCapabilitySet::full();
    caps.revoke(DartCapability::Painting);
    let mut rt = DartRuntime::from_js("denied_test", code, caps, ResourceMeter::unbounded())
        .expect("compiles");
    rt.run().expect("runs");
    let reply = &rt.emitted()[0];
    assert!(
        reply.get("__dart_error__").is_some(),
        "expected a thrown-error envelope, got {reply}"
    );
    assert_eq!(rt.denied().len(), 1);
    assert!(rt.denied()[0].contains("dart:ui"));
}

/// Governance: the resource meter bounds a guest that floods the host, even if
/// it stays within the VM's instruction budget.
#[test]
fn resource_meter_bounds_host_calls() {
    let code = r#"
        var i = 0;
        while (i < 100) {
            askHost("dart:typed_data/ByteData.alloc", [4]);
            i = i + 1;
        }
        askHost("test.emit", ["done"]);
    "#;
    // Cap host calls at 5; the guest tries ~100.
    let meter = ResourceMeter::new(Some(5), None);
    let mut rt = DartRuntime::from_js(
        "meter_test",
        code,
        DartCapabilitySet::full(),
        meter,
    )
    .expect("compiles");
    rt.run().expect("runs");
    // Once the ceiling is hit, subsequent dart: calls are denied.
    assert!(!rt.denied().is_empty(), "meter should have denied calls");
}

/// Phase 5: the framework binding end-to-end. A Dart guest defines pointer and
/// frame handlers; the runtime delivers a tap and drives a frame, and the guest
/// renders a scene the host collects — exactly the engine <-> framework loop.
#[test]
fn binding_delivers_events_and_collects_a_frame() {
    let dart = r#"
        var taps = 0;
        void onPointerEvent(e) {
            taps = taps + 1;
            askHost("test.emit", ["tap$taps"]);
        }
        void onDrawFrame() {
            askHost("dart:ui/PictureRecorder.beginRecording", []);
            askHost("dart:ui/Canvas.drawRect", [0.0, 0.0, 10.0, 10.0, 4278190080]);
            var pic = askHost("dart:ui/PictureRecorder.endRecording", []);
            var scene = askHost("dart:ui/Picture.toScene", [pic]);
            askHost("dart:ui/FlutterView.render", [scene]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "binding_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("dart compiles");
    rt.run().expect("defines handlers");

    // Deliver two taps.
    rt.dispatch_pointer(PointerEvent { pointer: 1, phase: PointerPhase::Down, x: 5.0, y: 5.0 });
    rt.dispatch_pointer(PointerEvent { pointer: 1, phase: PointerPhase::Up, x: 5.0, y: 5.0 });
    assert_eq!(
        rt.emitted(),
        &[serde_json::json!("tap1"), serde_json::json!("tap2")]
    );

    // Drive a frame; the guest renders a rectangle scene the host collects.
    let frame = rt.render_frame(16_000).expect("guest rendered a frame");
    assert_eq!(frame["root"]["ops"][0]["op"], "drawRect");
}

/// Phase 5: the signed code-delivery path, from signing to a verified run.
#[test]
fn signed_bundle_loads_and_runs_but_tamper_is_rejected() {
    let key = *b"deployment-signing-key";
    let signer = BundleLoader::new(HmacSha256Scheme::new(key));

    let mut bundle = CodeBundle {
        id: "app.counter".into(),
        version: 7,
        entrypoint: "main".into(),
        source: r#"void main() { askHost("test.emit", ["v7"]); }"#.into(),
        signature: Vec::new(),
    };
    signer.sign(&mut bundle);

    // Device side: verify before loading.
    let mut loader = BundleLoader::new(HmacSha256Scheme::new(key));
    let trusted_source = loader.accept(&bundle).expect("valid bundle accepted");
    let mut rt = DartRuntime::from_dart(
        "bundle_run",
        &trusted_source,
        DartCapabilitySet::sandboxed(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(rt.emitted(), &[serde_json::json!("v7")]);

    // A tampered bundle never yields source, so it can never reach the VM.
    let mut evil = bundle.clone();
    evil.version = 8;
    evil.source = r#"void main() { askHost("test.emit", ["pwned"]); }"#.into();
    let mut loader2 = BundleLoader::new(HmacSha256Scheme::new(key));
    assert!(loader2.accept(&evil).is_err());
}

/// Deepen P2: dart:isolate ports deliver messages to the guest in send order,
/// and a cooperative Isolate.spawn runs a named entry with its message.
#[test]
fn isolate_ports_and_spawn() {
    let code = r#"
        function __portDispatch(a) {
            askHost("test.emit", ["got:" + a[1]]);
        }
        function worker(msg) {
            askHost("test.emit", ["worker:" + msg]);
        }
        var port = askHost("dart:isolate/ReceivePort", []);
        askHost("dart:isolate/SendPort.send", [port, "one"]);
        askHost("dart:isolate/SendPort.send", [port, "two"]);
        askHost("dart:isolate/Isolate.spawn", ["worker", "hi"]);
    "#;
    let mut rt = DartRuntime::from_js(
        "iso_test",
        code,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    let out: Vec<String> = rt.emitted().iter().map(|v| v.as_str().unwrap().to_string()).collect();
    // spawn drains before port messages in the pump priority order.
    assert_eq!(out, vec!["worker:hi", "got:one", "got:two"]);
}

/// Deepen P2: a periodic timer fires repeatedly until the guest cancels it.
#[test]
fn periodic_timer_end_to_end() {
    let code = r#"
        var count = 0;
        var id = 0;
        function __dartDispatch(a) {
            count = count + 1;
            askHost("test.emit", ["tick" + count]);
            if (count == 3) { askHost("dart:async/Timer.cancel", [id]); }
        }
        id = askHost("dart:async/Timer.periodic", [1, 10]);
    "#;
    let mut rt = DartRuntime::from_js(
        "periodic_test",
        code,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    let out: Vec<String> = rt.emitted().iter().map(|v| v.as_str().unwrap().to_string()).collect();
    assert_eq!(out, vec!["tick1", "tick2", "tick3"]);
}

/// Deepen P3: a real Dart **class** — fields, initializing-formal constructor,
/// methods with bare field references, instantiation, and method calls — compiled
/// to a native JS class and run on the VM.
#[test]
fn runs_a_dart_class() {
    let dart = r#"
        class Counter {
            int value = 0;
            Counter(this.value);
            void inc() { value = value + 1; }
            int read() { return value; }
        }
        void main() {
            Counter c = Counter(10);
            c.inc();
            c.inc();
            askHost("test.emit", [c.read()]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "class_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("dart class compiles");
    rt.run().expect("runs");
    assert_eq!(rt.emitted(), &[serde_json::json!(12)]);
}

/// Deepen P3: inheritance with `super()` and an overriding subclass, plus a
/// ternary and compound assignment, end-to-end.
#[test]
fn runs_dart_inheritance() {
    let dart = r#"
        class Animal {
            int legs = 4;
            int legCount() { return legs; }
        }
        class Bird extends Animal {
            Bird() { legs = 2; }
        }
        void main() {
            Bird b = Bird();
            int n = b.legCount();
            askHost("test.emit", [n > 2 ? "many" : "few"]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "inherit_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(rt.emitted(), &[serde_json::json!("few")]);
}

/// Deepen P4: reified `is`/`as` end-to-end — class-instance subtype checks via
/// the runtime class hierarchy, plus primitive type tests, all from Dart source.
#[test]
fn reified_is_and_as_from_dart() {
    let dart = r#"
        class Animal { }
        class Dog extends Animal { }
        class Cat extends Animal { }
        void main() {
            Dog d = Dog();
            askHost("test.emit", [d is Animal]);
            askHost("test.emit", [d is Cat]);
            askHost("test.emit", [5 is int]);
            askHost("test.emit", ["hi" is String]);
            Animal a = d as Animal;
            askHost("test.emit", [a is Dog]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "isas_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(
        rt.emitted(),
        &[
            serde_json::json!(true),   // Dog is Animal
            serde_json::json!(false),  // Dog is Cat
            serde_json::json!(true),   // 5 is int
            serde_json::json!(true),   // "hi" is String
            serde_json::json!(true),   // (d as Animal) is Dog
        ]
    );
}

/// Deepen P5: retained scene diffing — two frames that differ only in one rect's
/// color yield a minimal patch, not a whole new tree.
#[test]
fn frame_diff_is_minimal() {
    let dart = r#"
        var color = 100;
        void onPointerEvent(e) { color = 200; }
        void onDrawFrame() {
            askHost("dart:ui/PictureRecorder.beginRecording", []);
            askHost("dart:ui/Canvas.drawRect", [0.0, 0.0, 10.0, 10.0, color]);
            var pic = askHost("dart:ui/PictureRecorder.endRecording", []);
            var scene = askHost("dart:ui/Picture.toScene", [pic]);
            askHost("dart:ui/FlutterView.render", [scene]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "diff_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("defines handlers");

    let p0 = rt.render_frame_patch(16_000);
    assert_eq!(p0.len(), 1); // first frame: full set

    rt.dispatch_pointer(PointerEvent { pointer: 1, phase: PointerPhase::Down, x: 1.0, y: 1.0 });
    let p1 = rt.render_frame_patch(32_000);
    assert_eq!(p1.len(), 1, "only the color should differ");
    assert_eq!(p1[0].value, Some(serde_json::json!(200)));
}

/// VM conformance: Dart core-type members (`List.length`, indexing, `String.length`)
/// now resolve in the VM, so idiomatic Dart that iterates a list runs unchanged.
#[test]
fn dart_list_and_string_length() {
    let dart = r#"
        void main() {
            var xs = [10, 20, 30, 40];
            var total = 0;
            for (int i = 0; i < xs.length; i++) { total = total + xs[i]; }
            var name = "flutter";
            askHost("test.emit", [total]);
            askHost("test.emit", [name.length]);
            askHost("test.emit", [xs.isEmpty]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "corelib_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(
        rt.emitted(),
        &[serde_json::json!(100), serde_json::json!(7), serde_json::json!(false)]
    );
}

/// VM conformance: bound native methods on core types — idiomatic Dart method
/// calls on List and String now dispatch through the VM (mutating add, queries,
/// string transforms), while user-class instance methods still work.
#[test]
fn dart_core_type_methods() {
    let dart = r#"
        class Greeter {
            String greet(String who) { return "hi " + who; }
        }
        void main() {
            var xs = [1, 2, 3];
            xs.add(4);
            xs.add(5);
            askHost("test.emit", [xs.length]);
            askHost("test.emit", [xs.contains(4)]);
            askHost("test.emit", [xs.indexOf(3)]);
            var s = "Hello, Flutter";
            askHost("test.emit", [s.toUpperCase()]);
            askHost("test.emit", [s.substring(7)]);
            askHost("test.emit", [s.split(", ").length]);
            var g = Greeter();
            askHost("test.emit", [g.greet("world")]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "methods_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(
        rt.emitted(),
        &[
            serde_json::json!(5),                 // 3 + add(4) + add(5)
            serde_json::json!(true),              // contains(4)
            serde_json::json!(2),                 // indexOf(3)
            serde_json::json!("HELLO, FLUTTER"),
            serde_json::json!("Flutter"),
            serde_json::json!(2),                 // split(", ").length
            serde_json::json!("hi world"),        // instance method still works
        ]
    );
}

/// VM+front-end conformance: closures and higher-order Iterable methods. The
/// functional patterns (map/where/fold/reduce/any/every) — which thread state
/// through arguments — run end-to-end from real Dart.
///
/// Note: Elpian closures capture by value, so mutating a captured outer variable
/// (e.g. `forEach((e) => acc += e)`) does not propagate; use `fold`/`reduce`.
#[test]
fn dart_closures_and_higher_order() {
    let dart = r#"
        int sq(int x) => x * x;
        void main() {
            var xs = [1, 2, 3, 4, 5];
            askHost("test.emit", [xs.map((e) => e * 2)]);
            askHost("test.emit", [xs.where((e) => e % 2 == 1)]);
            askHost("test.emit", [xs.fold(0, (a, b) => a + b)]);
            askHost("test.emit", [xs.reduce((a, b) => a + b)]);
            askHost("test.emit", [xs.any((e) => e > 4)]);
            askHost("test.emit", [xs.every((e) => e > 0)]);
            askHost("test.emit", [sq(6)]);
            askHost("test.emit", [xs.map((e) => sq(e)).fold(0, (a, b) => a + b)]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "closures_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(
        rt.emitted(),
        &[
            serde_json::json!([2, 4, 6, 8, 10]),  // map
            serde_json::json!([1, 3, 5]),         // where (odds)
            serde_json::json!(15),                // fold sum
            serde_json::json!(15),                // reduce sum
            serde_json::json!(true),              // any > 4
            serde_json::json!(true),              // every > 0
            serde_json::json!(36),                // sq(6) arrow-body fn
            serde_json::json!(55),                // sum of squares 1..5
        ]
    );
}

/// VM+front-end conformance: named and optional parameters — the Flutter
/// constructor/callback idiom. Named ctor params (`{this.x}`), named params with
/// defaults, and named arguments at call sites all run from real Dart.
#[test]
fn dart_named_parameters() {
    let dart = r#"
        class Box {
            Box(this.label, {this.width, this.height});
            String describe() { return label + ":" + width + "x" + height; }
        }
        int scaled(int base, {int factor = 2, int offset = 0}) => base * factor + offset;
        void main() {
            var b = Box("btn", width: "10", height: "20");
            askHost("test.emit", [b.describe()]);
            askHost("test.emit", [scaled(5)]);
            askHost("test.emit", [scaled(5, factor: 3)]);
            askHost("test.emit", [scaled(5, factor: 3, offset: 1)]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "named_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(
        rt.emitted(),
        &[
            serde_json::json!("btn:10x20"),
            serde_json::json!(10),   // 5*2 + 0
            serde_json::json!(15),   // 5*3 + 0
            serde_json::json!(16),   // 5*3 + 1
        ]
    );
}

/// VM+front-end conformance: async/await via CPS transform on the microtask
/// event loop. Async functions return Futures; awaits sequence through `.then`
/// continuations. Covers awaiting another async function, sequential awaits, and
/// delivering the result via `.then`.
#[test]
fn dart_async_await() {
    let dart = r#"
        Future<int> delayedValue(int v) async { return v; }
        Future<int> sumTwo() async {
            var a = await delayedValue(10);
            var b = await delayedValue(20);
            return a + b;
        }
        Future<String> label() async {
            var n = await sumTwo();
            return "total=" + n;
        }
        void main() {
            sumTwo().then((r) => askHost("test.emit", [r]));
            label().then((s) => askHost("test.emit", [s]));
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "async_await_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    // Both futures resolve during the microtask pump; order is deterministic.
    let out = rt.emitted();
    assert!(out.contains(&serde_json::json!(30)), "sumTwo -> 30, got {out:?}");
    assert!(out.contains(&serde_json::json!("total=30")), "label -> total=30, got {out:?}");
}

/// VM conformance: broadened dart:core surface — num methods/getters, more
/// List methods, Map literals + methods/getters, more String methods.
#[test]
fn dart_core_surface() {
    let dart = r#"
        void main() {
            askHost("test.emit", [(3.7).toInt()]);
            askHost("test.emit", [(-5).abs()]);
            askHost("test.emit", [(3.14159).toStringAsFixed(2)]);
            askHost("test.emit", [(9).clamp(0, 5)]);
            var xs = [3, 1, 2];
            xs.addAll([4]);
            xs.insert(0, 0);
            askHost("test.emit", [xs.length]);
            askHost("test.emit", [xs.first]);
            askHost("test.emit", [xs.reversed]);
            var m = {"a": 1, "b": 2};
            m["c"] = 3;
            askHost("test.emit", [m.length]);
            askHost("test.emit", [m.containsKey("b")]);
            askHost("test.emit", [m.keys.length]);
            askHost("test.emit", ["hi".padRight(5, ".")]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "core_surface_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(
        rt.emitted(),
        &[
            serde_json::json!(3),          // 3.7.toInt
            serde_json::json!(5),          // (-5).abs
            serde_json::json!("3.14"),     // toStringAsFixed
            serde_json::json!(5),          // clamp(9 -> 0..5)
            serde_json::json!(5),          // length after addAll+insert
            serde_json::json!(0),          // first (inserted 0)
            serde_json::json!([4, 2, 1, 3, 0]), // reversed
            serde_json::json!(3),          // map length
            serde_json::json!(true),       // containsKey
            serde_json::json!(3),          // keys.length
            serde_json::json!("hi..."),    // padRight
        ]
    );
}

/// By-reference closure capture: a closure mutating an enclosing variable now
/// propagates (via the box transform), so forEach-accumulator and closure-counter
/// patterns work — the deepest previous correctness gap.
#[test]
fn dart_by_reference_closure_capture() {
    let dart = r#"
        int makeSum(List<int> xs) {
            var total = 0;
            xs.forEach((e) => total = total + e);
            return total;
        }
        void main() {
            askHost("test.emit", [makeSum([1, 2, 3, 4, 5])]);

            var count = 0;
            var bump = () { count = count + 1; };
            bump();
            bump();
            bump();
            askHost("test.emit", [count]);

            // where + a captured filter threshold
            var threshold = 2;
            var kept = [1, 2, 3, 4].where((e) => e > threshold);
            askHost("test.emit", [kept]);
        }
    "#;
    let mut rt = DartRuntime::from_dart(
        "byref_test",
        dart,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    )
    .expect("compiles");
    rt.run().expect("runs");
    assert_eq!(
        rt.emitted(),
        &[
            serde_json::json!(15),          // 1+2+3+4+5 via forEach mutation
            serde_json::json!(3),           // closure counter
            serde_json::json!([3, 4]),      // where with captured threshold
        ]
    );
}
