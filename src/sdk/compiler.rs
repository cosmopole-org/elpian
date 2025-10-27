fn serialize_expr(val: serde_json::Value) -> Vec<u8> {
    let mut result: Vec<u8> = vec![];
    match val["type"].as_str().unwrap() {
        "i16" => {
            result.push(1);
            result.append(
                &mut i16::to_be_bytes(val["data"]["value"].as_i64().unwrap() as i16).to_vec(),
            );
        }
        "i32" => {
            result.push(2);
            result.append(
                &mut i32::to_be_bytes(val["data"]["value"].as_i64().unwrap() as i32).to_vec(),
            );
        }
        "i64" => {
            result.push(3);
            result.append(
                &mut i64::to_be_bytes(val["data"]["value"].as_i64().unwrap() as i64).to_vec(),
            );
        }
        "f32" => {
            result.push(4);
            result.append(
                &mut f32::to_be_bytes(val["data"]["value"].as_f64().unwrap() as f32).to_vec(),
            );
        }
        "f64" => {
            result.push(5);
            result.append(
                &mut f64::to_be_bytes(val["data"]["value"].as_f64().unwrap() as f64).to_vec(),
            );
        }
        "bool" => {
            result.push(6);
            result.push(if val["data"]["value"].as_bool().unwrap() == true {
                0x01
            } else {
                0x00
            });
        }
        "string" => {
            result.push(7);
            let mut value_bytes = val["data"]["value"].as_str().unwrap().as_bytes().to_vec();
            result.append(&mut i32::to_be_bytes(value_bytes.len() as i32).to_vec());
            result.append(&mut value_bytes);
        }
        "identifier" => {
            result.push(0x0b);
            let mut value_bytes = val["data"]["name"].as_str().unwrap().as_bytes().to_vec();
            result.append(&mut i32::to_be_bytes(value_bytes.len() as i32).to_vec());
            result.append(&mut value_bytes);
        }
        "object" => {
            result.push(8);
            result.append(&mut i32::to_be_bytes(val["data"]["value"].as_object().unwrap().iter().len() as i32).to_vec());
            for (k, v) in val["data"]["value"].as_object().unwrap().iter() {
                result.append(&mut k.as_bytes().to_vec());
                result.append(&mut serialize_expr(v.clone()));
            }
        }
        "array" => {
            result.push(9);
            result.append(
                &mut i32::to_be_bytes(val["data"]["value"].as_array().unwrap().iter().len() as i32)
                    .to_vec(),
            );
            for v in val["data"]["value"].as_array().unwrap().iter() {
                result.append(&mut serialize_expr(v.clone()));
            }
        }
        "not" => {
            result.push(0xfc);
            result.append(&mut serialize_expr(val["data"]["value"].clone()));
        }
        "arithmetic" => {
            match val["data"]["operation"].as_str().unwrap() {
                "==" => {
                    result.push(0xf0);
                }
                ">" => {
                    result.push(0xf1);
                }
                ">=" => {
                    result.push(0xf2);
                }
                "<" => {
                    result.push(0xf3);
                }
                "<=" => {
                    result.push(0xf4);
                }
                "!=" => {
                    result.push(0xf5);
                }
                "+" => {
                    result.push(0xf6);
                }
                "-" => {
                    result.push(0xf7);
                }
                "*" => {
                    result.push(0xf8);
                }
                "/" => {
                    result.push(0xf9);
                }
                "%" => {
                    result.push(0xfa);
                }
                "^" => {
                    result.push(0xfb);
                }
                _ => {}
            };
            result.append(&mut serialize_expr(val["data"]["operand1"].clone()));
            result.append(&mut serialize_expr(val["data"]["operand2"].clone()));
        }
        "callFunction" => {
            result.push(0x0d);
            result.append(&mut serialize_expr(val["data"]["callee"].clone()));
            result.append(
                &mut i32::to_be_bytes(val["data"]["arguments"].as_array().unwrap().len() as i32)
                    .to_vec(),
            );
            val["data"]["arguments"]
                .as_array()
                .unwrap()
                .iter()
                .for_each(|arg| {
                    result.append(&mut serialize_expr(arg.clone()));
                });
        }
        _ => {
            panic!("unknown val type");
        }
    }
    result
}

pub fn compile(program: serde_json::Value, start_point: usize) -> Vec<u8> {
    let mut result: Vec<u8> = vec![];
    for operation in program["body"].as_array().unwrap().iter() {
        match operation["type"].as_str().unwrap() {
            "ifStmt" => {
                result.push(0x10);
                result.push(0x01);
                result.append(&mut serialize_expr(operation["data"]["condition"].clone()).to_vec());
                let body_start = start_point + result.len() + 8 + 8 + 8 + 8;
                let body = compile(operation["data"].clone(), body_start);
                let body_end = body_start + body.len();
                result.append(&mut i64::to_be_bytes(body_start as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut body.clone());
            }
            "loopStmt" => {
                let loop_start = start_point + result.len();
                result.push(0x11);
                result.append(&mut serialize_expr(operation["data"]["condition"].clone()).to_vec());
                let body_start = start_point + result.len() + 8 + 8 + 8;
                let mut body = compile(operation["data"].clone(), body_start);
                body.push(0x15);
                body.append(&mut i64::to_be_bytes(loop_start as i64).to_vec());
                let body_end = body_start + body.len();
                result.append(&mut i64::to_be_bytes(body_start as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut body.clone());
            }
            "defineFunction" => {
                result.push(0x13);
                let mut str_bytes = operation["data"]["name"]
                    .as_str()
                    .unwrap()
                    .as_bytes()
                    .to_vec();
                let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                result.append(&mut len_bytes);
                result.append(&mut str_bytes);
                result.append(
                    &mut i32::to_be_bytes(
                        operation["data"]["params"].as_array().unwrap().len() as i32
                    )
                    .to_vec(),
                );
                for p_name in operation["data"]["params"].as_array().unwrap().iter() {
                    let mut str_bytes = p_name.as_str().unwrap().as_bytes().to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                }
                let func_start = start_point + result.len() + 8 + 8;
                let body = compile(operation["data"].clone(), func_start);
                let func_end = func_start + body.len();
                result.append(&mut i64::to_be_bytes(func_start as i64).to_vec());
                result.append(&mut i64::to_be_bytes(func_end as i64).to_vec());
                result.append(&mut body.clone());
            }
            "callFunction" => {
                result.push(0x0d);
                result.append(&mut serialize_expr(operation["data"]["callee"].clone()));
                result.append(
                    &mut i32::to_be_bytes(
                        operation["data"]["arguments"].as_array().unwrap().len() as i32
                    )
                    .to_vec(),
                );
                operation["data"]["arguments"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .for_each(|arg| {
                        result.append(&mut serialize_expr(arg.clone()));
                    });
            }
            "definition" => {
                result.push(0x0e);
                if operation["data"]["leftSide"]["type"].as_str().unwrap() == "identifier" {
                    result.push(0x0b);
                    let mut str_bytes = operation["data"]["leftSide"]["data"]["name"]
                        .as_str()
                        .unwrap()
                        .as_bytes()
                        .to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                    result.append(&mut serialize_expr(operation["data"]["rightSide"].clone()));
                }
            }
            "assignment" => {
                result.push(0x0f);
                if operation["data"]["leftSide"]["type"].as_str().unwrap() == "identifier" {
                    result.push(0x0b);
                    let mut str_bytes = operation["data"]["leftSide"]["data"]["name"]
                        .as_str()
                        .unwrap()
                        .as_bytes()
                        .to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                    result.append(&mut serialize_expr(operation["data"]["rightSide"].clone()));
                } else if operation["data"]["leftSide"]["type"].as_str().unwrap() == "indexer" {
                    result.push(0x0c);
                    let mut str_bytes =
                        operation["data"]["leftSide"]["data"]["target"]["data"]["name"]
                            .as_str()
                            .unwrap()
                            .as_bytes()
                            .to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                    result.append(&mut serialize_expr(operation["data"]["rightSide"].clone()));
                }
            }
            _ => {
                // skip
            }
        }
    }
    if result.len() == 0 {
        result.push(0x00);
    }
    result
}
