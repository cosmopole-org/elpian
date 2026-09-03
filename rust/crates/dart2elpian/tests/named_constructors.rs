//! A named constructor has to construct.
//!
//! `ClassName.named(...)` is parsed as a static member, because that is how it
//! is reached. But its body assigns to `this`, meaning the object being built.
//! Emitted as a bare static — which is what happened until this test existed —
//! it assigns those fields onto the *class*, constructs nothing, and returns
//! undefined. The call site gets null and fails on the first property read,
//! somewhere else entirely.
//!
//! Found while merging `godot.dart` and `flutter.dart` into `gui.dart`: a
//! `GuiTheme.dark()` returned nothing and the failure surfaced as "non object
//! value can not be indexed by string" three call sites away.

fn js(src: &str) -> String {
    dart2elpian::transpile(src).expect("transpiles")
}

#[test]
fn a_named_constructor_allocates_and_returns_an_instance() {
    let out = js(r#"
class T {
  var x;
  T.dark() { this.x = 7; }
}
void main() { var t = T.dark(); print(t.x); }
"#);
    assert!(
        out.contains("new T()"),
        "the factory must allocate — it constructed nothing:\n{out}"
    );
    assert!(
        out.contains("return __o"),
        "the factory must return the object it built:\n{out}"
    );
}

#[test]
fn a_named_constructor_body_assigns_to_the_new_object_not_the_class() {
    let out = js(r#"
class T {
  var x;
  T.dark() { this.x = 7; }
}
void main() { var t = T.dark(); print(t.x); }
"#);
    // The body lands in an instance initializer, where `this` is the object.
    assert!(
        out.contains("__init_dark"),
        "the body should run as an instance initializer:\n{out}"
    );
    // The *declaration*, not the call site in the factory above it.
    let init = out
        .split("__init_dark(")
        .last()
        .expect("initializer present");
    assert!(
        init.contains("this.x = 7"),
        "the field assignment should be on the instance:\n{out}"
    );
}

#[test]
fn a_named_constructor_takes_its_parameters() {
    let out = js(r#"
class T {
  var x;
  var y;
  T.at(a, b) { this.x = a; this.y = b; }
}
void main() { var t = T.at(1, 2); print(t.x); }
"#);
    assert!(
        out.contains("static at(a, b)"),
        "the factory should keep the parameter list:\n{out}"
    );
    assert!(
        out.contains("__o.__init_at(a, b)"),
        "the factory should forward its parameters to the initializer:\n{out}"
    );
}
