//! A server function must be able to call the host.
//!
//! On the previous server it could not: any `askHost` returned HTTP 501, so a
//! server function could not log, read the clock, keep state, or touch a file.
//! These tests drive the real AST → bytecode → executor path through the
//! invocation loop and assert each of those now works, and that the capability
//! posture actually stops the ones it should.

use elpian_host::services::{ServerContext, ServerServices};
use elpian_host::state::{SecretStore, StateStore};
use elpian_host::{invoke, server_capabilities, InvokeLimits, Outcome};
use elpian_vm::api::{self, Capability};
use serde_json::{json, Value};

// ---- AST helpers -----------------------------------------------------------

fn ident(name: &str) -> Value {
    json!({ "type": "identifier", "data": { "name": name } })
}
fn strv(s: &str) -> Value {
    json!({ "type": "string", "data": { "value": s } })
}
fn ret(value: Value) -> Value {
    json!({ "type": "returnOperation", "data": { "value": value } })
}
fn host_call(name: &str, args: Vec<Value>) -> Value {
    json!({ "type": "host_call", "data": { "name": name, "args": args } })
}
fn func_def(name: &str, params: Vec<&str>, body: Vec<Value>) -> Value {
    json!({ "type": "functionDefinition", "data": { "name": name, "params": params, "body": body } })
}
fn program(body: Vec<Value>) -> String {
    json!({ "type": "program", "body": body }).to_string()
}

// ---- Harness ---------------------------------------------------------------

struct Fixture {
    id: String,
    state: StateStore,
    secrets: SecretStore,
    ctx: ServerContext,
}

impl Fixture {
    fn new(id: &str, ast: &str, granted: &[Capability]) -> Fixture {
        assert!(
            api::create_vm_from_ast(id.to_string(), ast.to_string()),
            "the test program should compile"
        );
        // Governance is applied *before* the first run, never after.
        api::set_capabilities(id, server_capabilities(granted));

        Fixture {
            id: id.to_string(),
            state: StateStore::default(),
            secrets: SecretStore::new(),
            ctx: ServerContext {
                app: "notes".into(),
                machine_id: id.to_string(),
                function: String::new(),
                declared_secrets: vec!["apiKey".into()],
                fs: None,
                user: None,
                network: elpian_host::app::NetworkMode::Closed,
            },
        }
    }

    fn with_fs(mut self, dir: &std::path::Path) -> Fixture {
        std::fs::create_dir_all(dir).unwrap();
        self.ctx.fs = Some(elpian_host::appfs::AppFs::new(dir));
        self
    }

    fn call(&mut self, function: &str, args: Value) -> (Outcome, ServerServices) {
        self.ctx.function = function.to_string();
        let mut services =
            ServerServices::new(self.ctx.clone(), self.state.clone(), self.secrets.clone());
        let outcome = invoke(
            &self.id,
            function,
            &args,
            &mut services,
            &InvokeLimits::default(),
            // These fixtures create a VM per call, so every one is cold: the
            // module's top level still has to run.
            true,
        );
        (outcome, services)
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        api::destroy_vm(self.id.clone());
    }
}

fn returned(outcome: Outcome) -> Value {
    match outcome {
        Outcome::Returned(v) => v,
        other => panic!("expected a returned value, got {other:?}"),
    }
}

// ---- The 501 is gone -------------------------------------------------------

#[test]
fn a_server_function_can_log() {
    let ast = program(vec![func_def(
        "hello",
        vec![],
        vec![
            host_call("log", vec![strv("from the server")]),
            ret(strv("ok")),
        ],
    )]);
    let mut fx = Fixture::new("sf-log", &ast, &[Capability::Logging]);
    let (outcome, services) = fx.call("hello", json!(null));

    assert_eq!(returned(outcome), json!("ok"));
    assert_eq!(
        services.log.guest,
        vec!["from the server".to_string()],
        "the guest's log call reached the host instead of a 501"
    );
}

#[test]
fn a_server_function_can_read_the_clock() {
    let ast = program(vec![func_def(
        "now",
        vec![],
        vec![ret(host_call("time.now", vec![]))],
    )]);
    let mut fx = Fixture::new("sf-clock", &ast, &[Capability::Clock]);
    let millis = returned(fx.call("now", json!(null)).0);

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;
    let observed = millis.as_u64().expect("a millisecond timestamp");
    assert!(
        observed > 1_600_000_000_000 && observed <= now + 1_000,
        "expected a plausible wall-clock time, got {observed}"
    );
}

#[test]
fn a_server_function_can_keep_state_across_invocations() {
    let ast = program(vec![
        func_def(
            "put",
            vec!["v"],
            vec![ret(host_call("kv.set", vec![strv("note:1"), ident("v")]))],
        ),
        func_def(
            "get",
            vec![],
            vec![ret(host_call("kv.get", vec![strv("note:1")]))],
        ),
    ]);
    let mut fx = Fixture::new("sf-state", &ast, &[Capability::State]);

    assert_eq!(returned(fx.call("put", json!("hello")).0), json!(true));
    // A *separate* invocation reads it back — the state outlived the call.
    assert_eq!(returned(fx.call("get", json!(null)).0), json!("hello"));
}

#[test]
fn a_server_function_can_use_its_own_filesystem() {
    let dir = std::env::temp_dir().join("elpian-host-fs-test");
    let _ = std::fs::remove_dir_all(&dir);
    let ast = program(vec![
        func_def(
            "save",
            vec![],
            vec![ret(host_call(
                "fs.write",
                vec![strv("notes.txt"), strv("written by the guest")],
            ))],
        ),
        func_def(
            "load",
            vec![],
            vec![ret(host_call("fs.read", vec![strv("notes.txt")]))],
        ),
    ]);
    let mut fx = Fixture::new("sf-fs", &ast, &[Capability::Storage]).with_fs(&dir);

    assert_eq!(returned(fx.call("save", json!(null)).0), json!(true));
    assert_eq!(
        returned(fx.call("load", json!(null)).0),
        json!("written by the guest")
    );
}

#[test]
fn a_server_function_receives_its_arguments_and_returns_a_value() {
    let ast = program(vec![func_def("echo", vec!["msg"], vec![ret(ident("msg"))])]);
    let mut fx = Fixture::new("sf-args", &ast, &[]);
    assert_eq!(
        returned(fx.call("echo", json!("round trip")).0),
        json!("round trip")
    );
}

// ---- The posture actually denies -------------------------------------------

#[test]
fn a_denied_capability_reads_as_null_rather_than_reaching_the_host() {
    // The same program, without the `state` grant.
    let ast = program(vec![func_def(
        "put",
        vec![],
        vec![ret(host_call("kv.set", vec![strv("k"), strv("v")]))],
    )]);
    let mut fx = Fixture::new("sf-denied", &ast, &[Capability::Logging]);
    let (outcome, services) = fx.call("put", json!(null));

    assert_eq!(
        returned(outcome),
        json!(null),
        "a denied capability short-circuits inside the VM"
    );
    assert!(
        services.log.host.is_empty(),
        "the call should not have reached the host at all, but it logged {:?}",
        services.log.host
    );
    assert!(
        fx.state.get("notes", "k").is_none(),
        "nothing was written despite the guest asking"
    );
}

#[test]
fn the_network_is_not_reachable_from_a_server_function_by_default() {
    let ast = program(vec![func_def(
        "reach",
        vec![],
        vec![ret(host_call("net.fetch", vec![strv("http://example.com")]))],
    )]);
    // `Network` is grantable in principle, but an app that was not granted it
    // holds nothing — the base is deny-all.
    let mut fx = Fixture::new("sf-net", &ast, &[Capability::Logging, Capability::State]);
    assert_eq!(returned(fx.call("reach", json!(null)).0), json!(null));
}

#[test]
fn a_secret_not_declared_in_the_manifest_reads_as_absent() {
    let ast = program(vec![
        func_def(
            "declared",
            vec![],
            vec![ret(host_call("secret.get", vec![strv("apiKey")]))],
        ),
        func_def(
            "undeclared",
            vec![],
            vec![ret(host_call("secret.get", vec![strv("otherKey")]))],
        ),
    ]);
    let mut fx = Fixture::new("sf-secret", &ast, &[Capability::State]);
    fx.secrets.put("notes", "apiKey", "s3cret".into());
    fx.secrets.put("notes", "otherKey", "also-here".into());

    assert_eq!(returned(fx.call("declared", json!(null)).0), json!("s3cret"));
    assert_eq!(
        returned(fx.call("undeclared", json!(null)).0),
        json!(null),
        "a secret the manifest did not declare is indistinguishable from one \
         that does not exist"
    );
}

// ---- Failure containment ---------------------------------------------------

#[test]
fn a_guest_trap_is_contained_rather_than_unwinding_into_the_host() {
    // `{} - 1` is a guest type error; the executor raises it as a panic.
    let ast = program(vec![func_def(
        "boom",
        vec![],
        vec![ret(json!({ "type": "arithmetic", "data": {
            "operation": "-",
            "operand1": { "type": "object", "data": { "value": {} } },
            "operand2": { "type": "i64", "data": { "value": 1 } } } }))],
    )]);
    let mut fx = Fixture::new("sf-trap", &ast, &[Capability::Logging]);
    let (outcome, _) = fx.call("boom", json!(null));

    match outcome {
        // The reason is available to the *operator*; the HTTP layer decides not
        // to show it to a caller.
        Outcome::Trapped(reason) => assert!(!reason.is_empty()),
        // Some guest faults surface as a returned error value rather than a
        // trap. Either is contained, which is what this asserts.
        Outcome::Returned(value) => {
            assert!(value.is_string() || value.is_null(), "got {value:?}")
        }
        other => panic!("unexpected outcome {other:?}"),
    }
}

#[test]
fn an_invocation_that_will_not_stop_calling_the_host_is_cut_off() {
    // A loop that calls `log` a million times.
    let ast = program(vec![func_def(
        "spin",
        vec![],
        vec![
            json!({ "type": "definition", "data": {
                "leftSide": ident("i"),
                "rightSide": { "type": "i64", "data": { "value": 0 } } } }),
            json!({ "type": "loopStmt", "data": {
                "condition": { "type": "arithmetic", "data": {
                    "operation": "<",
                    "operand1": ident("i"),
                    "operand2": { "type": "i64", "data": { "value": 1000000 } } } },
                "body": [ host_call("log", vec![strv("x")]) ] } }),
            ret(strv("never")),
        ],
    )]);
    let mut fx = Fixture::new("sf-spin", &ast, &[Capability::Logging]);

    fx.ctx.function = "spin".into();
    let mut services = ServerServices::new(fx.ctx.clone(), fx.state.clone(), fx.secrets.clone());
    let outcome = invoke(
        &fx.id,
        "spin",
        &json!(null),
        &mut services,
        &InvokeLimits { max_host_calls: 50 },
        true,
    );

    assert_eq!(outcome, Outcome::TooManyHostCalls);
    assert!(
        services.log.guest.len() <= 51,
        "the cut-off should have stopped it near the bound, got {} calls",
        services.log.guest.len()
    );
}
