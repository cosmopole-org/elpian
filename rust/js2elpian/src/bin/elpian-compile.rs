use std::{env, fs, process};

fn usage() -> ! {
    eprintln!("usage: elpian-compile <ast|bytecode> <input.js> <output>");
    process::exit(2);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 { usage(); }
    let source = fs::read_to_string(&args[2]).unwrap_or_else(|e| {
        eprintln!("cannot read {}: {e}", args[2]);
        process::exit(1);
    });
    let result = match args[1].as_str() {
        "ast" => fs::write(&args[3], js2elpian::compile_js_to_ast(source).as_bytes()),
        "bytecode" => match js2elpian::compile_js_to_bytecode(&source) {
            Some(bytes) => fs::write(&args[3], bytes),
            None => {
                eprintln!("JavaScript is outside the supported Elpian subset");
                process::exit(1);
            }
        },
        _ => usage(),
    };
    if let Err(e) = result {
        eprintln!("cannot write {}: {e}", args[3]);
        process::exit(1);
    }
}
