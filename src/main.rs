use std::sync::mpsc;

use elpian::sdk::vm::VM;

fn main() {
    let mut vm = VM::new(vec![0x01, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 7, 0x00, 0x00, 0x00, 0x01, 98,
        0x02, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 7, 0x00, 0x00, 0x00, 0x01, 99], 1);
    vm.run();
    vm.print_memory();
    println!("ended !");
    let (_sender, end_signal_recv) = mpsc::channel::<bool>();
    println!("{:?}", end_signal_recv.recv().err().unwrap());
}
