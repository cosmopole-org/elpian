//! Scratch diagnostics for the TritonLand boot gate: (1) the connect()
//! URL-normalization logic runs correctly in the VM, and (2) the full
//! production guest.js (import markers stripped, as the composer does)
//! compiles through js2elpian without dialect errors.

use elpian_vm::api;

fn run_js_and_call(id: &str, js: &str, func: &str) -> String {
    assert!(js2elpian::create_vm_from_js(id.to_string(), js.to_string()), "JS should compile");
    let _ = api::execute_vm(id.to_string());
    api::execute_vm_func(id.to_string(), func.to_string(), 1).result_value
}

#[test]
fn connect_url_normalization_runs_in_vm() {
    let js = r#"
function f() {
  var serverUrl = "  https://tritonland.onrender.com/  ";
  var origin = serverUrl.trim();
  while (origin != "" && origin.substring(origin.length - 1, origin.length) == "/") {
    origin = origin.substring(0, origin.length - 1);
  }
  if (!(origin.startsWith("http://") || origin.startsWith("https://"))) {
    return "REJECTED";
  }
  return origin;
}
"#;
    assert_eq!(
        run_js_and_call("tl-url", js, "f"),
        "\"https://tritonland.onrender.com\""
    );
}

// `production_guest_compiles` is not vendored: it read a hardcoded absolute
// path (/home/user/TritonLand/...) that exists only on one developer's machine,
// so it could never pass here — and a permanently-red test makes CI unable to
// signal real breakage. It lives on in victor.
