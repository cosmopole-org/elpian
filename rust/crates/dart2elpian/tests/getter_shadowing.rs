//! A getter stops being a getter if any class in the program has a field of
//! that name.
//!
//! `dart2elpian` rewrites a property read of a getter into a call, because the
//! VM has no property accessors — `obj.x` on a getter would otherwise yield the
//! *function*. The rewrite is keyed on the name alone and applied program-wide,
//! so it is disabled for a name that is anywhere also a plain field. That is the
//! safe direction (calling a field would be worse), but it makes the guarantee
//! non-local: a getter's correctness depends on every other class in the
//! program.
//!
//! Merging two libraries is exactly how that goes wrong, and it did. `gui.dart`
//! was built by merging the engine transport with the widget layer. The widget
//! layer's `Color` exposed `value`; the engine's `StringName`, `NodePath`,
//! `GInt` and `GFloat` each declare `final value`. Separately both were fine.
//! Together, `Color.value` silently stopped being called — every painted colour
//! read a function object, and the app rendered nothing at all, with no error.
//!
//! `Color.value` is a stored field now, which is the right answer regardless
//! (it is read once per painted node per frame). These tests pin the rule that
//! made it necessary, so the next merge finds it here rather than in a blank
//! window.

fn js(src: &str) -> String {
    dart2elpian::transpile(src).expect("transpiles")
}

#[test]
fn a_getter_read_as_a_property_is_invoked() {
    let out = js(r#"
class Box {
  var w;
  Box(this.w);
  int get area => w * 2;
}
void main() { var b = Box(3); print(b.area); }
"#);
    assert!(
        out.contains("b.area()"),
        "getter read was not rewritten to a call — it yields the function:\n{out}"
    );
}

#[test]
fn a_field_of_the_same_name_anywhere_disables_the_getter_everywhere() {
    // The hazard, stated as a test. Not a bug to fix here — the alternative
    // (emitting a call for something that might be a field) is worse — but a
    // rule that has to be visible, because nothing about `Box` explains why its
    // getter stopped working.
    let out = js(r#"
class Unrelated { final int value; Unrelated(this.value); }
class Box {
  var w;
  Box(this.w);
  int get value => w * 2;
}
void main() { var b = Box(3); print(b.value); }
"#);
    assert!(
        !out.contains("b.value()"),
        "the ambiguity rule appears to have changed — a getter is now called \
         even though another class declares a field of that name. If that is \
         deliberate, this test should say so; if not, `Color.value` in gui.dart \
         and anything like it needs re-checking:\n{out}"
    );
}

#[test]
fn the_gui_sdk_has_no_getter_shadowed_by_a_field() {
    // The standing check on the SDK itself: every getter it declares must not
    // collide with a field name anywhere in the same file, or it is silently
    // not a getter.
    const SDK: &str = include_str!("../../../../guest-sdk/dart/gui.dart");

    let mut getters: Vec<String> = Vec::new();
    let mut fields: Vec<String> = Vec::new();
    for line in SDK.lines() {
        let t = line.trim();
        if let Some(rest) = t.split(" get ").nth(1) {
            if !t.starts_with("//") && !t.starts_with("///") {
                let name: String = rest
                    .chars()
                    .take_while(|c| c.is_alphanumeric() || *c == '_')
                    .collect();
                if !name.is_empty() {
                    getters.push(name);
                }
            }
        }
        // `var x;` / `final T x;` / `final x;` field declarations.
        if t.starts_with("var ") || t.starts_with("final ") || t.starts_with("const ") {
            if let Some(decl) = t.strip_suffix(';') {
                if let Some(name) = decl.split_whitespace().last() {
                    if name.chars().all(|c| c.is_alphanumeric() || c == '_') {
                        fields.push(name.to_string());
                    }
                }
            }
        }
    }

    let shadowed: Vec<&String> = getters.iter().filter(|g| fields.contains(g)).collect();
    assert!(
        shadowed.is_empty(),
        "these getters in gui.dart share a name with a field declared in the \
         same program, so they are not called when read — they yield the \
         function object instead, silently: {shadowed:?}"
    );
    assert!(
        !getters.is_empty(),
        "the scan found no getters at all — it has stopped matching"
    );
}
