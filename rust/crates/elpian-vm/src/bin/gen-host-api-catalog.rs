//! Write the host-API catalog generated from the VM's own list.
//!
//! See `elpian_vm::api::catalog` for what is generated and why. This binary is
//! a thin wrapper so the same rendering can be unit-tested for staleness.
//!
//! ```text
//! cargo run --bin gen-host-api-catalog -- ../flutter/lib/src/vm/host_api_catalog.dart
//! cargo run --bin gen-host-api-catalog -- ../native/core/src/vm/host-api-catalog.ts
//! cargo run --bin gen-host-api-catalog -- \
//!     ../native/android/elpian-core/src/main/kotlin/dev/elpian/core/vm/HostApiCatalog.kt
//! cargo run --bin gen-host-api-catalog -- ../native/ios/Sources/ElpianCore/VM/HostApiCatalog.swift
//! cargo run --bin gen-host-api-catalog            # print to stdout
//! ```
//!
//! The output language follows the path's extension: `.ts` gets the
//! TypeScript catalog the web host uses, `.kt` the Kotlin one the Android core
//! uses, `.swift` the Swift one the iOS core uses, anything else the Dart one.

fn main() {
    match std::env::args().nth(1) {
        Some(path) => {
            let source = if path.ends_with(".ts") {
                elpian_vm::api::catalog::ts_catalog()
            } else if path.ends_with(".kt") {
                elpian_vm::api::catalog::kotlin_catalog()
            } else if path.ends_with(".swift") {
                elpian_vm::api::catalog::swift_catalog()
            } else {
                elpian_vm::api::catalog::dart_catalog()
            };
            if let Some(dir) = std::path::Path::new(&path).parent() {
                if !dir.as_os_str().is_empty() {
                    if let Err(e) = std::fs::create_dir_all(dir) {
                        eprintln!("gen-host-api-catalog: cannot create {}: {e}", dir.display());
                        std::process::exit(1);
                    }
                }
            }
            if let Err(e) = std::fs::write(&path, &source) {
                eprintln!("gen-host-api-catalog: cannot write {path}: {e}");
                std::process::exit(1);
            }
            eprintln!("gen-host-api-catalog: wrote {path}");
        }
        None => print!("{}", elpian_vm::api::catalog::dart_catalog()),
    }
}
