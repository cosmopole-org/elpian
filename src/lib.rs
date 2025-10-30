use wasm_bindgen::prelude::*;

use crate::sdk::vm::VM;
use serde_json::json;

pub mod sdk;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);
    #[wasm_bindgen(js_namespace = console, js_name = log)]
    fn log_u32(a: u32);
    #[wasm_bindgen(js_namespace = console, js_name = log)]
    fn log_many(a: &str, b: &str);
}

#[wasm_bindgen(start)]
fn main() -> Result<(), JsValue> {
  Ok(())
}

#[wasm_bindgen]
pub fn execute() {
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
                  },
                  {
                    "type": "return",
                    "data": {
                      "value": {
                        "type": "string",
                        "data": {
                          "value": "hello keyhan !",
                        }
                      }
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
                  "data": { "name": "println" }
                },
                "arguments": [
                  {
                    "type": "arithmetic",
                    "data": {
                      "operation": "+",
                      "operand1": {
                        "type": "callFunction",
                        "data": {
                          "callee": {
                            "type": "identifier",
                            "data": { "name": "println" }
                          },
                          "arguments": [
                            {
                              "type": "array",
                              "data": {
                                "value": [
                                  {
                                    "type": "string",
                                    "data": {
                                      "value": "keyhan"
                                    }
                                  },
                                  {
                                    "type": "i16",
                                    "data": {
                                      "value": 27
                                    }
                                  },
                                ],
                              }
                            }
                          ]
                        }
                      },
                      "operand2": {
                        "type": "string",
                        "data": {
                          "value": " hi !",
                        }
                      }
                    }
                  }
                ]
              }
            }
          ]
        }),
        1,
        vec!["println".to_string()],
    );
    vm.run();
    vm.print_memory();
    log("ended !");
}
