use std::{env, fs, process};

fn usage() -> ! {
    eprintln!("usage: elpian-run <app.elpian.bc> <function> [json-input]");
    process::exit(2);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 || args.len() > 4 { usage(); }
    let bytes = fs::read(&args[1]).unwrap_or_else(|e| {
        eprintln!("cannot read {}: {e}", args[1]);
        process::exit(1);
    });
    let id = "elpian-cli-server".to_string();
    elpian_vm::api::init_vm_system();
    elpian_vm::api::create_vm_from_bytecode(id.clone(), bytes);
    let initial = elpian_vm::api::execute_vm(id.clone());
    if initial.has_host_call {
        eprintln!("server module made an unsupported top-level host call: {}", initial.host_call_data);
        process::exit(1);
    }
    let result = if let Some(input) = args.get(3) {
        elpian_vm::api::execute_vm_func_with_input(id, args[2].clone(), input.clone(), 1)
    } else {
        elpian_vm::api::execute_vm_func(id, args[2].clone(), 1)
    };
    if result.has_host_call {
        eprintln!("server function made an unsupported host call: {}", result.host_call_data);
        process::exit(1);
    }
    println!("{}", result.result_value);
}
