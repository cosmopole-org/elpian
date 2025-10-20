use elpian::sdk::vm::VM;

fn main() {
    let mut vm = VM::new(vec![1, 1, 1, 1], 1);
    vm.run_func("hello");
}
