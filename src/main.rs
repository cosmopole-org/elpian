use std::sync::mpsc;

use elpian::sdk::vm::VM;

fn main() {
    let mut vm = VM::new(vec![0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 97, 0x01, 7, 0x00, 0x00, 0x00, 0x01, 98], 1);
    vm.run();
    vm.print_memory();
    println!("ended !");
    let (sender, end_signal_recv) = mpsc::channel::<bool>();
    println!("{:?}", end_signal_recv.recv().err().unwrap());
}
