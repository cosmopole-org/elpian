//! Write the Dart host-API catalog generated from the VM's own list.
//!
//! See `elpian_vm::api::catalog` for what is generated and why. This binary is
//! a thin wrapper so the same rendering can be unit-tested for staleness.
//!
//! ```text
//! cargo run --bin gen-host-api-catalog -- ../lib/src/vm/host_api_catalog.dart
//! cargo run --bin gen-host-api-catalog            # print to stdout
//! ```

fn main() {
    let dart = elpian_vm::api::catalog::dart_catalog();
    match std::env::args().nth(1) {
        Some(path) => {
            if let Err(e) = std::fs::write(&path, &dart) {
                eprintln!("gen-host-api-catalog: cannot write {path}: {e}");
                std::process::exit(1);
            }
            eprintln!("gen-host-api-catalog: wrote {path}");
        }
        None => print!("{dart}"),
    }
}
