//! The JavaScript guest surface: `godot.js` (the JS twin of the Dart prelude)
//! and the Victor UI kit (`ui.js`) compiled by js2elpian and run on real VMs
//! against a mock engine. Pins that:
//!
//!   * a JS root program speaks the identical wire protocol (create / set /
//!     call / connect round-trips, batching, value-shape marshaling);
//!   * bridged signals dispatch back into JS closures (`__godotDispatch`);
//!   * `GTimer` rides the VM event loop under `pump`;
//!   * a JS parent spawns a JS child (`vm.spawn` inherits the language) and
//!     exchanges messages with it;
//!   * the UI-kit composition seam works: `import 'ui.js'` pulls the kit in,
//!     and its widgets emit the expected Control-node op stream.

use std::cell::RefCell;
use std::rc::Rc;

use elpian_godot::{GuestLang, VmManager};
use serde_json::{json, Value};

/// A recording mock engine: services `new`/`singleton`/`tree`/`self`/`load`
/// (guest-chosen handles), records every op, and remembers signal connects so
/// tests can drive them back through `__godotDispatch`.
#[derive(Default)]
struct Mock {
    ops: Vec<Value>,
    /// (handle, signal, namespaced cb id)
    connects: Vec<(i64, String, i64)>,
    next_host_handle: i64,
}

impl Mock {
    fn exec(&mut self, op: &Value) -> Value {
        self.ops.push(op.clone());
        if op.get("chk").is_some() {
            return json!(true);
        }
        if let Some(signal) = op.get("connect").and_then(|v| v.as_str()) {
            let handle = op.get("ref").and_then(|v| v.as_i64()).unwrap_or(0);
            let cb = op.get("cb").and_then(|v| v.as_i64()).unwrap_or(0);
            self.connects.push((handle, signal.to_string(), cb));
            return Value::Null;
        }
        if op.get("method").is_some() {
            // Object-returning engine calls used by the kit/tests.
            let name = op.get("method").and_then(|v| v.as_str()).unwrap_or("");
            if name == "get_root" || name == "create_tween" || name == "get_parent" {
                self.next_host_handle -= 1;
                return json!({"obj": self.next_host_handle, "class": "Object"});
            }
            return Value::Null;
        }
        if op.get("new").is_some()
            || op.get("singleton").is_some()
            || op.get("tree").is_some()
            || op.get("self").is_some()
            || op.get("load").is_some()
        {
            return op.get("def").map(|d| d.clone()).unwrap_or_else(|| {
                self.next_host_handle -= 1;
                json!(self.next_host_handle)
            });
        }
        if op.get("const").is_some() {
            return json!(1);
        }
        Value::Null
    }

    fn created(&self, class: &str) -> usize {
        self.ops
            .iter()
            .filter(|op| op.get("new").and_then(|v| v.as_str()) == Some(class))
            .count()
    }

    fn sets_of(&self, prop: &str) -> Vec<Value> {
        self.ops
            .iter()
            .filter(|op| op.get("set").and_then(|v| v.as_str()) == Some(prop))
            .filter_map(|op| op.get("value").cloned())
            .collect()
    }
}

fn boot_js(id: &str, source: &str) -> (VmManager, Rc<RefCell<Mock>>) {
    let mock = Rc::new(RefCell::new(Mock::default()));
    let mut mgr = VmManager::new_root_lang(id.to_string(), source, GuestLang::Js, true, 0, 0)
        .expect("JS guest must compile");
    let hooked = mock.clone();
    mgr.set_bridge(Some(Box::new(move |name, args| {
        let mut m = hooked.borrow_mut();
        match name {
            "godot.op" => Some(m.exec(args.first().unwrap_or(&Value::Null))),
            "godot.batch" => {
                let ops = args.first().and_then(|v| v.as_array()).cloned().unwrap_or_default();
                Some(Value::Array(ops.iter().map(|op| m.exec(op)).collect()))
            }
            _ => None,
        }
    })));
    mgr.run_root().expect("main() must run");
    (mgr, mock)
}

#[test]
fn js_guest_speaks_the_wire_protocol() {
    let src = r#"
        import 'godot.js';
        function main() {
            let node = GD.create('Node2D');
            node.set('position', new Vector2(4.5, 2.25));
            node.set('modulate', new Color(1.0, 0.5, 0.25, 1.0));
            GD.mount(node);
            let label = GD.create('Label');
            label.set('text', 'hello from js');
            node.call('add_child', [label]);
            print('protocol: mounted ' + node.cls);
        }
        main();
    "#;
    let (mut mgr, mock) = boot_js("js-protocol", src);
    let m = mock.borrow();
    assert_eq!(m.created("Node2D"), 1);
    assert_eq!(m.created("Label"), 1);
    let positions = m.sets_of("position");
    assert_eq!(positions, vec![json!({"vec2": [4.5, 2.25]})]);
    // Whole floats serialize as integers on the wire; compare numerically.
    let colors = m.sets_of("modulate");
    let rgba: Vec<f64> = colors[0]["color"]
        .as_array()
        .expect("a color wire shape")
        .iter()
        .map(|v| v.as_f64().unwrap())
        .collect();
    assert_eq!(rgba, vec![1.0, 0.5, 0.25, 1.0]);
    let texts = m.sets_of("text");
    assert_eq!(texts, vec![json!("hello from js")]);
    drop(m);
    let log = mgr.take_log().join("\n");
    assert!(log.contains("protocol: mounted Node2D"), "log was: {log}");
}

#[test]
fn js_batching_coalesces_ops_into_one_crossing() {
    let src = r#"
        import 'godot.js';
        function main() {
            GD.beginBatch();
            let a = GD.create('Node2D');
            let b = GD.create('Sprite2D');
            a.set('position', new Vector2(1.0, 2.0));
            let results = GD.endBatch();
            print('batched: ' + results.length + ' results');
        }
        main();
    "#;
    let (mut mgr, mock) = boot_js("js-batch", src);
    assert_eq!(mock.borrow().created("Node2D"), 1);
    assert_eq!(mock.borrow().created("Sprite2D"), 1);
    let log = mgr.take_log().join("\n");
    assert!(log.contains("batched: 3 results"), "log was: {log}");
}

#[test]
fn js_signal_connect_dispatches_back_into_the_closure() {
    let src = r#"
        import 'godot.js';
        var taps = 0;
        function main() {
            let btn = GD.create('Button');
            btn.set('text', 'Tap');
            GD.mount(btn);
            btn.connect('pressed', (args) => {
                taps = taps + 1;
                print('js tap #' + taps);
            });
        }
        main();
    "#;
    let (mut mgr, mock) = boot_js("js-signal", src);
    let (_, signal, cb) = mock.borrow().connects.first().cloned().expect("a connect op");
    assert_eq!(signal, "pressed");
    // Namespaced by the manager: root VM (1) rides the high 32 bits.
    assert_eq!(cb >> 32, 1);
    mgr.invoke("__godotDispatch", json!([cb, []]));
    mgr.invoke("__godotDispatch", json!([cb, []]));
    let log = mgr.take_log().join("\n");
    assert!(log.contains("js tap #1"), "log was: {log}");
    assert!(log.contains("js tap #2"), "log was: {log}");
}

#[test]
fn js_gtimer_fires_on_the_pumped_event_loop() {
    let src = r#"
        import 'godot.js';
        var fired = 0;
        function main() {
            GTimer.periodic(100, () => {
                fired = fired + 1;
                print('tick ' + fired);
            });
        }
        main();
    "#;
    let (mut mgr, _mock) = boot_js("js-timer", src);
    for _ in 0..35 {
        mgr.pump(16).expect("pump");
    }
    let log = mgr.take_log().join("\n");
    assert!(log.contains("tick 1"), "log was: {log}");
    assert!(log.contains("tick 5"), "log was: {log}");
}

#[test]
fn js_parent_spawns_js_child_and_they_exchange_messages() {
    let src = r#"
        import 'godot.js';
        var childSrc = "function main() { VMs.sendParent('hi from js child'); } main();";
        function main() {
            let pod = GD.create('Node2D');
            GD.mount(pod);
            VMs.onMessage((sender, msg) => {
                print('parent got: ' + msg + ' (from vm ' + sender + ')');
            });
            let child = VMs.spawn(childSrc, pod, { label: 'js-child' });
            if (child == null) { print('spawn FAILED'); }
        }
        main();
    "#;
    let (mut mgr, _mock) = boot_js("js-spawn", src);
    let log = mgr.take_log().join("\n");
    assert!(
        log.contains("parent got: hi from js child (from vm 2)"),
        "log was: {log}"
    );
    assert!(mgr.vm_alive(2), "the JS child must be alive");
}

#[test]
fn ui_kit_composes_on_import_and_builds_control_nodes() {
    let src = r#"
        import 'godot.js';
        import 'ui.js';
        function main() {
            let app = VUI.app({ design: [720, 1280], portrait: true });
            let taps = { n: 0 };
            let page = VUI.column({
                gap: 16,
                pad: 24,
                children: [
                    VUI.heading('Victor UI'),
                    VUI.card({ children: [VUI.text('a card')] }),
                    VUI.button('Tap me', { onTap: () => {
                        taps.n = taps.n + 1;
                        print('ui tap #' + taps.n);
                    } }),
                    VUI.toggle({ value: false, onChanged: (on) => { print('toggle -> ' + on); } }),
                    VUI.progress({ value: 40.0 }),
                ],
            });
            app.push(page);
            print('ui built');
        }
        main();
    "#;
    let (mut mgr, mock) = boot_js("js-uikit", src);
    {
        let m = mock.borrow();
        assert_eq!(m.created("CanvasLayer"), 1, "the app root is a CanvasLayer");
        assert!(m.created("Label") >= 2, "heading + card text");
        // The action button + the toggle's hit-area button.
        assert!(m.created("Button") >= 2);
        assert_eq!(m.created("ProgressBar"), 1);
        assert!(m.created("StyleBoxFlat") >= 5, "widgets style themselves");
        // Portrait: on a desktop mock (no 'mobile' feature) the window itself
        // is sized to the portrait design resolution.
        assert!(
            m.ops.iter().any(|op| {
                op.get("method").and_then(|v| v.as_str()) == Some("window_set_size")
            }),
            "portrait mode must size the window"
        );
    }
    // Tap the action button through the bridge dispatch path.
    let cb = {
        let m = mock.borrow();
        m.connects
            .iter()
            .find(|(_, s, _)| s == "pressed")
            .map(|(_, _, cb)| *cb)
            .expect("the button connected 'pressed'")
    };
    mgr.invoke("__godotDispatch", json!([cb, []]));
    let log = mgr.take_log().join("\n");
    assert!(log.contains("ui built"), "log was: {log}");
    assert!(log.contains("ui tap #1"), "log was: {log}");
}

#[test]
fn net_composes_on_import_and_speaks_http_with_a_cookie_jar() {
    let src = r#"
        import 'godot.js';
        import 'net.js';
        function main() {
            Net.setBase('https://play.example');
            Net.postJson('/api/auth/signin', { email: 'k@example.com', password: 'pw' }, (res) => {
                print('status ' + res.status);
                let data = res.json();
                print('user ' + data.user.username);
                print('cookie ' + Net.cookie('sid'));
            });
            print('request sent');
        }
        main();
    "#;
    let (mut mgr, mock) = boot_js("js-net", src);
    // The request built one HTTPRequest node, connected its completion signal
    // and invoked `request` with the resolved URL + method code POST(2).
    let (request_args, cb) = {
        let m = mock.borrow();
        assert_eq!(m.created("HTTPRequest"), 1);
        let cb = m
            .connects
            .iter()
            .find(|(_, s, _)| s == "request_completed")
            .map(|(_, _, cb)| *cb)
            .expect("request_completed connected");
        let call = m
            .ops
            .iter()
            .find(|op| op.get("method").and_then(|v| v.as_str()) == Some("request"))
            .cloned()
            .expect("HTTPRequest.request invoked");
        (call.get("args").cloned().unwrap(), cb)
    };
    let args = request_args.as_array().unwrap();
    assert_eq!(args[0], json!("https://play.example/api/auth/signin"));
    assert_eq!(args[2], json!({ "int": 2 }), "POST method code");
    let body: Value =
        serde_json::from_str(args[3].as_str().expect("json body string")).unwrap();
    assert_eq!(body, json!({ "email": "k@example.com", "password": "pw" }));

    // Complete the request through the dispatch path: 200, a Set-Cookie header
    // and a JSON body (PackedByteArray → u8/base64 on the wire).
    mgr.invoke(
        "__godotDispatch",
        json!([
            cb,
            [
                0,
                200,
                { "strs": ["Content-Type: application/json", "Set-Cookie: sid=abc123; HttpOnly; Path=/"] },
                { "u8": "eyJvayI6dHJ1ZSwidXNlciI6eyJ1c2VybmFtZSI6ImthaSJ9fQ==" }
            ]
        ]),
    );
    let log = mgr.take_log().join("\n");
    assert!(log.contains("request sent"), "log was: {log}");
    assert!(log.contains("status 200"), "log was: {log}");
    assert!(log.contains("user kai"), "log was: {log}");
    assert!(log.contains("cookie abc123"), "log was: {log}");
}

#[test]
fn socket_io_frames_ride_a_websocket_peer() {
    let src = r#"
        import 'godot.js';
        import 'net.js';
        function main() {
            let socket = SocketIO.connect('https://play.example', {});
            socket.on('connect', (x) => { print('sio connected'); });
            socket.on('chat:new', (data) => { print('chat from ' + data.from); });
            print('sio dialing');
        }
        main();
    "#;
    let (mut mgr, mock) = boot_js("js-sio", src);
    {
        let m = mock.borrow();
        assert_eq!(m.created("WebSocketPeer"), 1);
        let dial = m
            .ops
            .iter()
            .find(|op| op.get("method").and_then(|v| v.as_str()) == Some("connect_to_url"))
            .cloned()
            .expect("connect_to_url invoked");
        let url = dial["args"][0].as_str().unwrap();
        assert_eq!(url, "wss://play.example/socket.io/?EIO=4&transport=websocket");
    }
    let log = mgr.take_log().join("\n");
    assert!(log.contains("sio dialing"), "log was: {log}");
}

#[test]
fn js_list_higher_order_methods_run_via_the_injected_prelude() {
    // `.map`/`.filter`/`.forEach`/`.reduce` resolve through the VM's
    // Dispatch::Prelude members; js2elpian injects the `__List_*` helpers so
    // JS guests can actually call them (they used to hit "not runnable").
    let src = r#"
        import 'godot.js';
        function main() {
            let doubled = [1, 2, 3].map((x) => x * 2);
            print('map ' + doubled.join(','));
            let odds = [1, 2, 3, 4, 5].filter((x) => x % 2 == 1);
            print('filter ' + odds.join(','));
            let sum = [1, 2, 3, 4].reduce((a, b) => a + b);
            print('reduce ' + sum);
            let seen = [];
            ["a", "b"].forEach((x, i) => { seen.push(x + i); });
            print('forEach ' + seen.join(','));
            print('every ' + [2, 4].every((x) => x % 2 == 0));
            print('any ' + [1, 3, 4].any((x) => x % 2 == 0));
        }
        main();
    "#;
    let (mut mgr, _mock) = boot_js("js-list-ho", src);
    let log = mgr.take_log().join("\n");
    assert!(log.contains("map 2,4,6"), "log was: {log}");
    assert!(log.contains("filter 1,3,5"), "log was: {log}");
    assert!(log.contains("reduce 10"), "log was: {log}");
    assert!(log.contains("forEach a0,b1"), "log was: {log}");
    assert!(log.contains("every true"), "log was: {log}");
    assert!(log.contains("any true"), "log was: {log}");
}

#[test]
fn equality_on_cyclic_objects_terminates_via_identity() {
    // `==` on objects/arrays short-circuits on identity before the structural
    // walk, so comparing a self-referential graph (a React instance tree with
    // parent/child back-references) terminates instead of recursing forever.
    let src = r#"
        import 'godot.js';
        function main() {
            let parent = { name: "p", children: [] };
            let child = { name: "c", parent: parent };
            parent.children.push(child);
            print('self ' + (parent == parent));
            print('member ' + (parent.children[0] == child));
            let list = [parent];
            let found = false;
            for (let i = 0; i < list.length; i++) {
                if (list[i] == parent) {
                    found = true;
                }
            }
            print('scan ' + found);
        }
        main();
    "#;
    let (mut mgr, _mock) = boot_js("js-cyc-eq", src);
    let log = mgr.take_log().join("\n");
    assert!(log.contains("self true"), "log was: {log}");
    assert!(log.contains("member true"), "log was: {log}");
    assert!(log.contains("scan true"), "log was: {log}");
}
