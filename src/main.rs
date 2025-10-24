use std::sync::mpsc;

use elpian::sdk::vm::VM;
use serde_json::json;

fn main() {
    // let mut vm = VM::create(
    //     vec![
    //         // let a = "b";
    //         0x01, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 7, 0x00, 0x00, 0x00, 0x01, 98,
    //         // a = "cba" - "c" - "b";
    //         0x02, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 0x12, 0x12, 7, 0x00, 0x00, 0x00, 0x03, 99, 98,
    //         97, 7, 0x00, 0x00, 0x00, 0x01, 99, 7, 0x00, 0x00, 0x00, 0x01, 98,
    //         // a = a + "d"
    //         0x02, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 0x11, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 7, 0x00, 0x00, 0x00, 0x01, 100
    //     ],
    //     1,
    // );
    let mut vm = VM::compile_and_create(
        json!({
          "type": "program",
          "body": [
            {
              "type": "definition",
              "data": {
                "leftSide": {
                  "type": "identifier",
                  "data": { "name": "count" }
                },
                "rightSide": {
                  "type": "i32",
                  "data": { "value": 23 }
                }
              }
            }
          ]
        }),
        1,
        vec!["println".to_string()]
    );
    vm.run();
    vm.print_memory();
    println!("ended !");
    let (_sender, end_signal_recv) = mpsc::channel::<bool>();
    println!("{:?}", end_signal_recv.recv().err().unwrap());
}
