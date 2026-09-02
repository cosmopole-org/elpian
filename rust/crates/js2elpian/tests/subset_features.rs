//! Which JavaScript the Elpian front-end actually accepts.
//!
//! The guest SDK is written in a *subset*, and nothing states its edges. That
//! matters as soon as you design against it: a class-component base class needs
//! `class … extends`, `super()`, prototype access and `for…in`; a widget
//! registry needs object iteration and string methods. Finding out which of
//! those work by writing 3,000 lines and seeing what breaks is the expensive
//! order.
//!
//! Each test is one feature. A failure here is a real constraint on how the SDK
//! can be written, not a bug.

/// Compile and run `src`; Ok(()) when it neither fails to compile nor traps.
fn accepts(id: &str, src: &str) -> Result<(), String> {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let compiled = js2elpian::create_vm_from_js(id.to_string(), src.to_string());
    let outcome = std::panic::catch_unwind(|| {
        if !compiled {
            return Err("does not compile".to_string());
        }
        let _ = elpian_vm::api::execute_vm(id.to_string());
        match elpian_vm::api::trap_reason(id) {
            Some(r) => Err(r),
            None => Ok(()),
        }
    });
    std::panic::set_hook(previous);
    let result = match outcome {
        Ok(r) => r,
        Err(p) => Err(p
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| p.downcast_ref::<&str>().map(|s| s.to_string()))
            .unwrap_or_else(|| "panic".to_string())),
    };
    elpian_vm::api::destroy_vm(id.to_string());
    result
}

fn assert_accepts(id: &str, what: &str, src: &str) {
    if let Err(e) = accepts(id, src) {
        panic!("the subset does not support {what}: {e}\n\n{src}");
    }
}

#[test]
fn classes_with_constructors_and_methods() {
    assert_accepts(
        "sub-class",
        "a class with a constructor and a method",
        r#"
class Box {
  constructor(v) { this.v = v; }
  get() { return this.v; }
}
let b = new Box(3);
if (b.get() !== 3) { throw "wrong"; }
"#,
    );
}

#[test]
fn class_inheritance_with_super() {
    // The Component base class depends on this entirely.
    assert_accepts(
        "sub-extends",
        "class inheritance with super()",
        r#"
class Base {
  constructor(v) { this.v = v; }
  describe() { return "base:" + this.v; }
}
class Derived extends Base {
  constructor(v) { super(v); this.extra = 1; }
  describe() { return "derived:" + this.v + ":" + this.extra; }
}
let d = new Derived(2);
if (d.describe() !== "derived:2:1") { throw "wrong: " + d.describe(); }
"#,
    );
}

#[test]
fn calling_an_inherited_method_that_the_subclass_did_not_override() {
    assert_accepts(
        "sub-inherit",
        "inheriting a method",
        r#"
class Base { hello() { return "hi"; } }
class Derived extends Base {}
let d = new Derived();
if (d.hello() !== "hi") { throw "wrong"; }
"#,
    );
}

// ---------------------------------------------------------------------------
// Telling a class component from a function component
// ---------------------------------------------------------------------------
//
// This is where the SDK's class-component design was decided, so the result is
// worth stating plainly. **None** of the usual discriminators exist here:
//
//   * `Type.prototype` is null, so no prototype marker;
//   * static fields and static methods do not inherit to a subclass;
//   * a class object cannot be assigned to, so it cannot carry its own flag.
//
// `instanceof` does work — but only on an *instance*, and constructing one
// speculatively is not an option: `new fn(props)` on a function component would
// run its body, and its hooks, before we knew what it was.
//
// So a class component is handed over explicitly, with `GUI.component(...)`,
// rather than detected. Each of these tests will start failing the day the
// front-end grows the feature it probes, which is the signal to simplify.

#[test]
fn a_constructor_has_no_prototype_property() {
    // Recorded because it is load-bearing: it rules out the prototype-marker
    // approach every React-like runtime reaches for first.
    let r = accepts(
        "sub-proto",
        r#"
class Base { render() { return 1; } }
if (Base.prototype != null) { throw "prototype exists after all"; }
"#,
    );
    assert!(
        r.is_ok(),
        "the subset grew a `prototype` property — the SDK's class-component \
         discriminator can be simplified: {r:?}"
    );
}

#[test]
fn instanceof_recognises_a_subclass() {
    let r = accepts(
        "sub-instanceof",
        r#"
class Base { render() { return 1; } }
class Derived extends Base {}
let d = new Derived();
if (!(d instanceof Base)) { throw "instanceof failed"; }
"#,
    );
    assert!(r.is_ok(), "instanceof against a base class: {r:?}");
}

#[test]
fn a_static_field_does_not_inherit_to_a_subclass() {
    let r = accepts(
        "sub-static",
        r#"
class Base { static isComponent = true; }
class Derived extends Base {}
if (Derived.isComponent === true) { throw "statics inherit after all"; }
"#,
    );
    assert!(
        r.is_ok(),
        "a static field now inherits to a subclass — the SDK's class-component \
         discriminator can be simplified to read one: {r:?}"
    );
}

#[test]
fn a_static_method_does_not_inherit_either() {
    // The remaining candidate: if a static *method* inherits where a static
    // field does not, a class component can be recognised by asking the class
    // itself, with no instance and no speculative construction.
    // Reading it off the subclass yields a non-function, and calling that
    // traps the VM rather than throwing — so the limit is asserted from here
    // rather than probed with try/catch inside the guest.
    let r = accepts(
        "sub-staticfn",
        r#"
class Base { static kind() { return "component"; } }
class Derived extends Base {}
Derived.kind();
"#,
    );
    assert!(
        r.is_err(),
        "a static method now inherits — the discriminator can use one instead \
         of GUI.component(...)"
    );
}

#[test]
fn a_static_is_not_readable_off_a_subclass() {
    let r = accepts(
        "sub-staticfn-read",
        r#"
class Base { static kind() { return "component"; } }
class Derived extends Base {}
if (__isType(Derived.kind, "function")) { throw "readable after all"; }
"#,
    );
    assert!(r.is_ok(), "a static is now readable off a subclass: {r:?}");
}

#[test]
fn a_class_object_cannot_be_assigned_to() {
    // The last fallback, also unavailable.
    let r = accepts(
        "sub-classprop",
        r#"
class Base { render() { return 1; } }
Base.__marker = true;
"#,
    );
    assert!(
        r.is_err(),
        "a class is now assignable — it could carry its own marker instead of \
         being handed over explicitly"
    );
}

#[test]
fn constructing_from_a_variable_holding_the_class() {
    // The reconciler holds the component type in a variable and does `new type(props)`.
    assert_accepts(
        "sub-new-var",
        "constructing from a variable holding a class",
        r#"
class Box { constructor(v) { this.v = v; } }
let T = Box;
let b = new T(5);
if (b.v !== 5) { throw "wrong"; }
"#,
    );
}

#[test]
fn iterating_an_object_with_for_in() {
    // The registry, `setState`'s merge and the shallow copy all need this.
    assert_accepts(
        "sub-forin",
        "for…in over an object",
        r#"
let o = { a: 1, b: 2 };
let n = 0;
for (let k in o) { n = n + o[k]; }
if (n !== 3) { throw "wrong: " + n; }
"#,
    );
}

#[test]
fn string_case_and_slicing_methods() {
    // Deriving `Button` from the registry name `"button"`.
    assert_accepts(
        "sub-strings",
        "substring / toUpperCase",
        r#"
let s = "button";
let out = s.substring(0, 1).toUpperCase() + s.substring(1);
if (out !== "Button") { throw "wrong: " + out; }
"#,
    );
}

#[test]
fn an_arrow_stored_on_an_object_and_invoked_later() {
    // Every widget spec is an object of closures.
    assert_accepts(
        "sub-spec",
        "an object of closures",
        r#"
let spec = {
  create: (props) => props.n + 1,
  update: (node, prev, props) => props.n + 2,
};
if (spec.create({ n: 1 }) !== 2) { throw "create"; }
if (spec.update(null, null, { n: 1 }) !== 3) { throw "update"; }
"#,
    );
}

#[test]
fn throwing_a_string_is_catchable() {
    assert_accepts(
        "sub-throw",
        "throw / catch",
        r#"
let caught = null;
try { throw "boom"; } catch (e) { caught = e; }
if (caught !== "boom") { throw "not caught"; }
"#,
    );
}

#[test]
fn a_class_method_used_as_a_callback_keeps_its_receiver() {
    // `onPress: () => this.handle()` inside a class component.
    assert_accepts(
        "sub-this",
        "an arrow capturing `this` inside a method",
        r#"
class Counter {
  constructor() { this.n = 0; }
  bump() {
    let f = () => { this.n = this.n + 1; };
    f();
    return this.n;
  }
}
let c = new Counter();
if (c.bump() !== 1) { throw "wrong"; }
"#,
    );
}
