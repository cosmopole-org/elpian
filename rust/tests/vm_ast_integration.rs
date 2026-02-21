use elpian_vm::sdk::{data::Val, vm::VM};
use serde_json::{json, Value};

fn collect_host_calls(mut vm: VM) -> (Vec<Value>, Val) {
    let mut host_calls = Vec::new();
    let mut result = vm.run();

    while result.typ == 253 {
        let raw = vm
            .sending_host_call_data
            .clone()
            .expect("host call payload should exist when vm is paused");
        let payload: Value = serde_json::from_str(&raw).expect("host call payload should be valid JSON");
        host_calls.push(payload);
        result = vm.continue_run("{\"type\":\"bool\",\"data\":{\"value\":true}}".to_string());
    }

    (host_calls, result)
}

fn host_call_from_paused_vm(vm: &VM) -> Value {
    let raw = vm
        .sending_host_call_data
        .clone()
        .expect("host call payload should exist when vm is paused");
    serde_json::from_str(&raw).expect("host call payload should be valid JSON")
}

fn continue_past_host_call(vm: &mut VM) -> Val {
    vm.continue_run("{\"type\":\"bool\",\"data\":{\"value\":true}}".to_string())
}

#[test]
fn arithmetic_indexer_and_cast_ast_executes_correctly() {
    let program = json!({
      "type": "program",
      "body": [
        {
          "type": "definition",
          "data": {
            "leftSide": { "type": "identifier", "data": { "name": "user" } },
            "rightSide": {
              "type": "object",
              "data": { "value": {
                "name": { "type": "string", "data": { "value": "Alice" } },
                "age": { "type": "i16", "data": { "value": 30 } }
              }}
            }
          }
        },
        {
          "type": "definition",
          "data": {
            "leftSide": { "type": "identifier", "data": { "name": "age" } },
            "rightSide": {
              "type": "indexer",
              "data": {
                "target": { "type": "identifier", "data": { "name": "user" } },
                "index": { "type": "string", "data": { "value": "age" } }
              }
            }
          }
        },
        {
          "type": "definition",
          "data": {
            "leftSide": { "type": "identifier", "data": { "name": "answer" } },
            "rightSide": {
              "type": "arithmetic",
              "data": {
                "operation": "+",
                "operand1": { "type": "identifier", "data": { "name": "age" } },
                "operand2": { "type": "i16", "data": { "value": 12 } }
              }
            }
          }
        },
        {
          "type": "host_call",
          "data": {
            "name": "println",
            "args": [{ "type": "identifier", "data": { "name": "answer" } }]
          }
        }
      ]
    });

    let vm = VM::compile_and_create_of_ast("arith-vm".to_string(), program, 0, vec![]);
    let (calls, final_result) = collect_host_calls(vm);

    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0]["apiName"], "println");
    assert_eq!(calls[0]["payload"], "[42]");
    assert_eq!(final_result.stringify(), "\"[undefined]\"");
}

#[test]
fn if_elseif_else_ast_picks_expected_branch() {
    let program = json!({
      "type": "program",
      "body": [
        {
          "type": "definition",
          "data": {
            "leftSide": { "type": "identifier", "data": { "name": "score" } },
            "rightSide": { "type": "i16", "data": { "value": 85 } }
          }
        },
        {
          "type": "definition",
          "data": {
            "leftSide": { "type": "identifier", "data": { "name": "grade" } },
            "rightSide": { "type": "string", "data": { "value": "" } }
          }
        },
        {
          "type": "ifStmt",
          "data": {
            "condition": {
              "type": "arithmetic",
              "data": {
                "operation": ">=",
                "operand1": { "type": "identifier", "data": { "name": "score" } },
                "operand2": { "type": "i16", "data": { "value": 90 } }
              }
            },
            "body": [
              {
                "type": "assignment",
                "data": {
                  "leftSide": { "type": "identifier", "data": { "name": "grade" } },
                  "rightSide": { "type": "string", "data": { "value": "A" } }
                }
              }
            ],
            "elseifStmt": {
              "type": "ifStmt",
              "data": {
                "condition": {
                  "type": "arithmetic",
                  "data": {
                    "operation": ">=",
                    "operand1": { "type": "identifier", "data": { "name": "score" } },
                    "operand2": { "type": "i16", "data": { "value": 80 } }
                  }
                },
                "body": [
                  {
                    "type": "assignment",
                    "data": {
                      "leftSide": { "type": "identifier", "data": { "name": "grade" } },
                      "rightSide": { "type": "string", "data": { "value": "B" } }
                    }
                  }
                ]
              }
            },
            "elseStmt": {
              "data": {
                "body": [
                  {
                    "type": "assignment",
                    "data": {
                      "leftSide": { "type": "identifier", "data": { "name": "grade" } },
                      "rightSide": { "type": "string", "data": { "value": "C" } }
                    }
                  }
                ]
              }
            }
          }
        },
        {
          "type": "host_call",
          "data": {
            "name": "println",
            "args": [{ "type": "identifier", "data": { "name": "grade" } }]
          }
        }
      ]
    });

    let vm = VM::compile_and_create_of_ast("if-vm".to_string(), program, 0, vec![]);
    let (calls, _) = collect_host_calls(vm);

    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0]["payload"], "[\"B\"]");
}

#[test]
fn function_definition_and_input_argument_ast_executes() {
    let program = json!({
      "type": "program",
      "body": [
        {
          "type": "functionDefinition",
          "data": {
            "name": "greet",
            "params": ["name"],
            "body": [
              {
                "type": "returnOperation",
                "data": {
                  "value": {
                    "type": "arithmetic",
                    "data": {
                      "operation": "+",
                      "operand1": { "type": "string", "data": { "value": "Hello, " } },
                      "operand2": { "type": "identifier", "data": { "name": "name" } }
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    });

    let mut vm = VM::compile_and_create_of_ast("func-vm".to_string(), program, 0, vec![]);
    let boot = vm.run();
    assert_eq!(boot.stringify(), "\"[undefined]\"");

    let result = vm.run_func_with_input(
        "greet",
        Some(r#"{"type":"string","data":{"value":"Elpian"}}"#),
        0,
    );
    assert_eq!(result.stringify(), "\"Hello, Elpian\"");
}

#[test]
fn switch_statement_ast_matches_case() {
    let program = json!({
      "type": "program",
      "body": [
        {
          "type": "definition",
          "data": {
            "leftSide": { "type": "identifier", "data": { "name": "day" } },
            "rightSide": { "type": "string", "data": { "value": "Monday" } }
          }
        },
        {
          "type": "definition",
          "data": {
            "leftSide": { "type": "identifier", "data": { "name": "kind" } },
            "rightSide": { "type": "string", "data": { "value": "unknown" } }
          }
        },
        {
          "type": "switchStmt",
          "data": {
            "value": { "type": "identifier", "data": { "name": "day" } },
            "cases": [
              {
                "value": { "type": "string", "data": { "value": "Monday" } },
                "body": {
                  "body": [
                    {
                      "type": "assignment",
                      "data": {
                        "leftSide": { "type": "identifier", "data": { "name": "kind" } },
                        "rightSide": { "type": "string", "data": { "value": "weekday-start" } }
                      }
                    }
                  ]
                }
              },
              {
                "value": { "type": "string", "data": { "value": "Friday" } },
                "body": {
                  "body": [
                    {
                      "type": "assignment",
                      "data": {
                        "leftSide": { "type": "identifier", "data": { "name": "kind" } },
                        "rightSide": { "type": "string", "data": { "value": "weekday-end" } }
                      }
                    }
                  ]
                }
              }
            ]
          }
        },
        {
          "type": "host_call",
          "data": {
            "name": "println",
            "args": [{ "type": "identifier", "data": { "name": "kind" } }]
          }
        }
      ]
    });

    let vm = VM::compile_and_create_of_ast("switch-vm".to_string(), program, 0, vec![]);
    let (calls, _) = collect_host_calls(vm);

    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0]["payload"], "[\"weekday-start\"]");
}

#[test]
fn vm_counter_example_boot_and_increment_render_without_errors() {
    let program = json!({
        "type": "program",
        "body": [
            {
                "type": "definition",
                "data": {
                    "leftSide": { "type": "identifier", "data": { "name": "count" } },
                    "rightSide": { "type": "i16", "data": { "value": 0 } }
                }
            },
            {
                "type": "functionDefinition",
                "data": {
                    "name": "renderNow",
                    "params": [],
                    "body": [
                        {
                            "type": "host_call",
                            "data": {
                                "name": "render",
                                "args": [{ "type": "identifier", "data": { "name": "count" } }]
                            }
                        }
                    ]
                }
            },
            {
                "type": "functionDefinition",
                "data": {
                    "name": "increment",
                    "params": [],
                    "body": [
                        {
                            "type": "assignment",
                            "data": {
                                "leftSide": { "type": "identifier", "data": { "name": "count" } },
                                "rightSide": {
                                    "type": "arithmetic",
                                    "data": {
                                        "operation": "+",
                                        "operand1": { "type": "identifier", "data": { "name": "count" } },
                                        "operand2": { "type": "i16", "data": { "value": 1 } }
                                    }
                                }
                            }
                        },
                        {
                            "type": "functionCall",
                            "data": {
                                "callee": { "type": "identifier", "data": { "name": "renderNow" } },
                                "args": []
                            }
                        }
                    ]
                }
            },
            {
                "type": "functionCall",
                "data": {
                    "callee": { "type": "identifier", "data": { "name": "renderNow" } },
                    "args": []
                }
            }
        ]
    });

    let mut vm = VM::compile_and_create_of_ast("vm-counter".to_string(), program, 0, vec![]);

    let boot = vm.run();
    assert_eq!(boot.typ, 253);
    assert_eq!(host_call_from_paused_vm(&vm)["payload"], "[0]");
    let _ = continue_past_host_call(&mut vm);

    let increment = vm.run_func_with_input("increment", None, 0);
    assert_eq!(increment.typ, 253);
    assert_eq!(host_call_from_paused_vm(&vm)["payload"], "[1]");
}

#[test]
fn vm_theme_example_toggle_switches_background_value() {
    let program = json!({
        "type": "program",
        "body": [
            {
                "type": "definition",
                "data": {
                    "leftSide": { "type": "identifier", "data": { "name": "isDark" } },
                    "rightSide": { "type": "bool", "data": { "value": false } }
                }
            },
            {
                "type": "functionDefinition",
                "data": {
                    "name": "renderNow",
                    "params": [],
                    "body": [
                        {
                            "type": "host_call",
                            "data": {
                                "name": "render",
                                "args": [{ "type": "identifier", "data": { "name": "isDark" } }]
                            }
                        }
                    ]
                }
            },
            {
                "type": "functionDefinition",
                "data": {
                    "name": "toggleTheme",
                    "params": [],
                    "body": [
                        {
                            "type": "assignment",
                            "data": {
                                "leftSide": { "type": "identifier", "data": { "name": "isDark" } },
                                "rightSide": { "type": "bool", "data": { "value": true } }
                            }
                        },
                        {
                            "type": "functionCall",
                            "data": {
                                "callee": { "type": "identifier", "data": { "name": "renderNow" } },
                                "args": []
                            }
                        }
                    ]
                }
            },
            {
                "type": "functionCall",
                "data": {
                    "callee": { "type": "identifier", "data": { "name": "renderNow" } },
                    "args": []
                }
            }
        ]
    });

    let mut vm = VM::compile_and_create_of_ast("vm-theme".to_string(), program, 0, vec![]);
    let boot = vm.run();
    assert_eq!(boot.typ, 253);
    assert_eq!(host_call_from_paused_vm(&vm)["payload"], "[false]");
    let _ = continue_past_host_call(&mut vm);

    let toggled = vm.run_func_with_input("toggleTheme", None, 0);
    assert_eq!(toggled.typ, 253);
    assert_eq!(host_call_from_paused_vm(&vm)["payload"], "[true]");
}

#[test]
fn vm_message_example_updates_text_from_function_input() {
    let program = json!({
        "type": "program",
        "body": [
            {
                "type": "definition",
                "data": {
                    "leftSide": { "type": "identifier", "data": { "name": "message" } },
                    "rightSide": { "type": "string", "data": { "value": "Waiting for Flutter input..." } }
                }
            },
            {
                "type": "functionDefinition",
                "data": {
                    "name": "renderNow",
                    "params": [],
                    "body": [
                        {
                            "type": "host_call",
                            "data": {
                                "name": "render",
                                "args": [{ "type": "identifier", "data": { "name": "message" } }]
                            }
                        }
                    ]
                }
            },
            {
                "type": "functionDefinition",
                "data": {
                    "name": "setMessage",
                    "params": ["nextMessage"],
                    "body": [
                        {
                            "type": "assignment",
                            "data": {
                                "leftSide": { "type": "identifier", "data": { "name": "message" } },
                                "rightSide": { "type": "identifier", "data": { "name": "nextMessage" } }
                            }
                        },
                        {
                            "type": "functionCall",
                            "data": {
                                "callee": { "type": "identifier", "data": { "name": "renderNow" } },
                                "args": []
                            }
                        }
                    ]
                }
            },
            {
                "type": "functionCall",
                "data": {
                    "callee": { "type": "identifier", "data": { "name": "renderNow" } },
                    "args": []
                }
            }
        ]
    });

    let mut vm = VM::compile_and_create_of_ast("vm-message".to_string(), program, 0, vec![]);
    let boot = vm.run();
    assert_eq!(boot.typ, 253);
    assert_eq!(host_call_from_paused_vm(&vm)["payload"], "[\"Waiting for Flutter input...\"]");
    let _ = continue_past_host_call(&mut vm);

    let updated = vm.run_func_with_input(
        "setMessage",
        Some(r#"{"type":"string","data":{"value":"Hello from Flutter"}}"#),
        0,
    );
    assert_eq!(updated.typ, 253);
    assert_eq!(host_call_from_paused_vm(&vm)["payload"], "[\"Hello from Flutter\"]");
}

#[test]
fn host_call_ast_round_trips_through_continue_run() {
    let program = json!({
      "type": "program",
      "body": [
        {
          "type": "host_call",
          "data": {
            "name": "render",
            "args": [
              {
                "type": "object",
                "data": { "value": {
                  "type": { "type": "string", "data": { "value": "Text" } },
                  "props": {
                    "type": "object",
                    "data": { "value": {
                      "data": { "type": "string", "data": { "value": "hello" } }
                    }}
                  }
                }}
              }
            ]
          }
        }
      ]
    });

    let mut vm = VM::compile_and_create_of_ast("host-vm".to_string(), program, 0, vec![]);
    let first = vm.run();

    assert_eq!(first.typ, 253);
    let call_data = vm.sending_host_call_data.clone().expect("host call payload should exist");
    let call_json: Value = serde_json::from_str(&call_data).expect("valid host call json");
    assert_eq!(call_json["machineId"], "host-vm");
    assert_eq!(call_json["apiName"], "render");
    assert!(call_json["payload"].as_str().unwrap_or_default().contains("\"Text\""));

    let final_result = vm.continue_run("{\"type\":\"bool\",\"data\":{\"value\":true}}".to_string());
    assert_eq!(final_result.stringify(), "\"[undefined]\"");
}
