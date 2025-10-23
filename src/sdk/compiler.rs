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
            result.append(&mut val["data"]["value"].as_str().unwrap().as_bytes().to_vec());
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
        _ => {
            panic!("unknown val type");
        }
    }
    result
}

pub fn compile(program: serde_json::Value) -> Vec<u8> {
    let mut result: Vec<u8> = vec![];
    for operation in program["body"].as_array().unwrap().iter() {
        match operation["type"].as_str().unwrap() {
            "definition" => {
                result.push(0x01);
                result.push(0x0b);
                if operation["data"]["leftSide"]["type"].as_str().unwrap() == "identifier" {
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
                result.push(0x02);
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
                }
            }
            _ => {
                // skip
            }
        }
    }
    result
}
