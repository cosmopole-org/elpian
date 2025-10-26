use std::sync::mpsc;

use elpian::sdk::vm::VM;
use serde_json::json;

fn main() {
    // let mut vm = VM::create(
    //     vec![
    //         // let a = "b";
    //         0x0e, 0x0b, 0x00, 0x00, 0x00, 0x01, 0x61, 7, 0x00, 0x00, 0x00, 0x01, 0x62,
    //         0x0d, 0x0b, 0x00, 0x00, 0x00, 0x07, 0x70, 0x72, 0x69, 0x6e, 0x74, 0x6c, 0x6e,
    //         0x00, 0x00, 0x00, 0x01, 0x0b, 0x00, 0x00, 0x00, 0x01, 0x61,
    //         // a = "cba" - "c" - "b";
    //         // 0x02, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 0x12, 0x12, 7, 0x00, 0x00, 0x00, 0x03, 99, 98,
    //         // 97, 7, 0x00, 0x00, 0x00, 0x01, 99, 7, 0x00, 0x00, 0x00, 0x01, 98,
    //         // // a = a + "d"
    //         // 0x02, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 0x11, 0x0b, 0x00, 0x00, 0x00, 0x01, 97, 7, 0x00, 0x00, 0x00, 0x01, 100
    //     ],
    //     1,
    //     vec!["println".to_string()]
    // );
    let mut vm = VM::compile_and_create(
        json!({
          "type": "program",
          "body": [
            {
              "type": "defineFunction",
              "data": {
                "name": "println",
                "params": ["input"],
                "body": [
                  {
                    "type": "ifStmt",
                    "data": {
                      "condition": {
                        "type": "arithmetic",
                        "data": {
                          "operation": "==",
                          "operand1": {
                            "type": "i32",
                            "data": { "value": 37 }
                          },
                          "operand2": {
                            "type": "i32",
                            "data": { "value": 37 }
                          }
                        }
                      },
                      "body": [
                        {
                          "type": "callFunction",
                          "data": {
                            "callee": {
                              "type": "identifier",
                              "data": { "name": "askHost" }
                            },
                            "arguments": [
                              {
                                "type": "string",
                                "data": { "value": "println" }
                              },
                              {
                                "type": "identifier",
                                "data": { "name": "input" }
                              }
                            ]
                          }
                        }
                      ]
                    }
                  }
                ]
              },
            },
            {
              "type": "defineFunction",
              "data": {
                "name": "test",
                "params": [],
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
            },
            {
              "type": "assignment",
              "data": {
                "leftSide": {
                  "type": "identifier",
                  "data": { "name": "count" }
                },
                "rightSide": {
                  "type": "i32",
                  "data": { "value": 33 }
                }
              }
            },
            {
              "type": "callFunction",
              "data": {
                "callee": {
                  "type": "identifier",
                  "data": { "name": "println" }
                },
                "arguments": [
                  {
                    "type": "arithmetic",
                    "data": {
                      "operation": "+",
                      "operand1": {
                        "type": "i32",
                        "data": { "value": 35 }
                      },
                      "operand2": {
                        "type": "i32",
                        "data": { "value": 37 }
                      }
                    }
                  }
                ]
              }
            }
          ]
              },
            },
            {
              "type": "callFunction",
              "data": {
                "callee": {
                  "type": "identifier",
                  "data": { "name": "test" }
                },
                "arguments": []
              }
            }
          ]
        }),
        1,
        vec!["println".to_string()],
    );
    vm.run();
    vm.print_memory();
    println!("ended !");
    let (_sender, end_signal_recv) = mpsc::channel::<bool>();
    println!("{:?}", end_signal_recv.recv().err().unwrap());
}
