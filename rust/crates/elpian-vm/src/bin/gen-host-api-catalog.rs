//! Write the Dart host-API catalog generated from the VM's own list.
//!
//! See `elpian_vm::api::catalog` for what is generated and why. This binary is
//! a thin wrapper so the same rendering can be unit-tested for staleness.
//!
//! ```text
//! cargo run --bin gen-host-api-catalog -- ../flutter/lib/src/vm/host_api_catalog.dart
//! cargo run --bin gen-host-api-catalog -- ../native/core/src/vm/host-api-catalog.ts
//! cargo run --bin gen-host-api-catalog            # print to stdout
//! ```
//!
//! A `.ts` path gets the TypeScript catalog the native hosts use.

fn main() {
    match std::env::args().nth(1) {
        Some(path) => {
            let source = if path.ends_with(".ts") {
                elpian_vm::api::catalog::ts_catalog()
            } else {
                elpian_vm::api::catalog::dart_catalog()
            };
            if let Err(e) = std::fs::write(&path, &source) {
                eprintln!("gen-host-api-catalog: cannot write {path}: {e}");
                std::process::exit(1);
            }
            eprintln!("gen-host-api-catalog: wrote {path}");
        }
        None => print!("{}", elpian_vm::api::catalog::dart_catalog()),
    }
}
