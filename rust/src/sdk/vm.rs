use std::{cell::RefCell, rc::Rc};

use serde_json::Value;

use crate::sdk::{compiler, data::Val, executor::Executor};

use crate::sdk::data::{Array, Object, Payload, ValGroup, ValMap};

pub struct CallbackHolder {
    pub callback: Box<dyn Fn(String) -> String>,
}

pub struct VM {
    machine_id: String,
    pub program: Vec<u8>,
    single_thread_executor: Option<Rc<RefCell<Executor>>>,
    pending_host_call_id: i64,
    pub sending_host_call_data: Option<String>,
}

unsafe impl Send for VM {}
unsafe impl Sync for VM {}

impl VM {
    pub fn compile_and_create_of_bytecode(
        machine_id: String,
        program: Vec<u8>,
        func_group: Vec<String>,
    ) -> Self {
        let executor = Executor::create_in_single_thread(program.clone(), 0, func_group);
        VM {
            machine_id,
            program,
            single_thread_executor: Some(Rc::new(RefCell::new(executor))),
            pending_host_call_id: 0,
            sending_host_call_data: None,
        }
    }
    pub fn compile_and_create_of_ast(
        machine_id: String,
        program: serde_json::Value,
        _executor_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let byte_code = compiler::compile_ast(program, 0);
        Self::compile_and_create_of_bytecode(machine_id, byte_code, func_group)
    }
    pub fn compile_and_create_of_code(
        machine_id: String,
        program: String,
        _executor_count: i32,
        func_group: Vec<String>,
    ) -> Self {
        let byte_code = compiler::compile_code(program);
        Self::compile_and_create_of_bytecode(machine_id, byte_code, func_group)
    }
    pub fn print_memory(&mut self) {}
    pub fn run(&mut self) -> Val {
        self.run_func_with_input("", None, 0)
    }

    // ---- Host-facing instance management ------------------------------------
    //
    // These thin wrappers reach through the executor so the embedder can govern,
    // gate, and steer the instance entirely via the public VM handle.

    fn exec(&self) -> std::cell::RefMut<'_, crate::sdk::executor::Executor> {
        self.single_thread_executor.as_ref().unwrap().borrow_mut()
    }

    /// Replace the resource-limit policy (instructions / memory / storage /
    /// call depth). Usage already accrued is retained.
    pub fn set_limits(&self, limits: crate::sdk::limits::ResourceLimits) {
        self.exec().set_limits(limits);
    }
    /// Current resource-limit policy.
    pub fn limits(&self) -> crate::sdk::limits::ResourceLimits {
        self.exec().limits()
    }
    /// Live resource-usage tally.
    pub fn usage(&self) -> crate::sdk::limits::ResourceUsage {
        self.exec().usage()
    }
    /// A snapshot of the capability toggles.
    pub fn capabilities(&self) -> crate::sdk::capabilities::CapabilitySet {
        self.exec().capabilities()
    }
    /// Replace the capability set wholesale.
    pub fn set_capabilities(&self, caps: crate::sdk::capabilities::CapabilitySet) {
        self.exec().set_capabilities(caps);
    }
    /// Toggle a single capability (network, storage, …) on or off.
    pub fn set_capability(&self, cap: crate::sdk::capabilities::Capability, allowed: bool) {
        self.exec().capabilities_mut().set(cap, allowed);
    }
    /// Host: request a pause at the next interpreter step boundary.
    pub fn request_pause(&self) {
        self.exec().request_pause();
    }
    /// Host: request termination at the next interpreter step boundary.
    pub fn request_terminate(&self) {
        self.exec().request_terminate();
    }
    /// Host: clear a pause flag (requested or confirmed) without driving.
    /// For an instance that was idle when paused — nothing to resume, but the
    /// stale flag would otherwise suspend its next turn immediately.
    pub fn clear_pause(&self) {
        self.exec().resume_control();
    }
    /// Current run state (running / paused / terminated / …).
    pub fn run_state(&self) -> crate::sdk::lifecycle::RunState {
        self.exec().run_state()
    }
    /// Whether the most recent turn ended because the host paused the instance.
    pub fn is_paused(&self) -> bool {
        matches!(self.run_state(), crate::sdk::lifecycle::RunState::Paused)
    }
    /// The fatal trap reason, if the instance was stopped by a limit or error.
    pub fn trap_reason(&self) -> Option<String> {
        self.exec().trap_reason()
    }
    /// Charge the host filesystem's storage delta against the storage budget.
    pub fn charge_storage(&self, delta: i64) -> Result<(), String> {
        self.exec().charge_storage(delta)
    }
    /// Reconcile the absolute persistent-storage figure with the host total.
    pub fn set_storage_bytes(&self, bytes: u64) -> Result<(), String> {
        self.exec().set_storage_bytes(bytes)
    }

    /// Resume a paused instance, continuing exactly where it suspended. Returns
    /// the same kind of result a normal step would (a pending host call, a
    /// further pause, completion, or a trap), routed through
    /// [`VM::handle_executor_request`]. No value is injected.
    pub fn resume(&mut self) -> Val {
        self.single_thread_executor.as_ref().unwrap().borrow_mut().resume_control();
        // 0x04 = resume-after-pause; the typ-254 payload means "no value".
        let r = self
            .single_thread_executor
            .as_ref()
            .unwrap()
            .borrow_mut()
            .single_thread_operation(0x04, self.pending_host_call_id, Val::new(254, Payload::Null));
        self.handle_executor_request(r.0, r.1, r.2)
    }
    pub fn is_exec_processing(&self) -> bool {
        self.single_thread_executor
            .as_ref()
            .unwrap()
            .borrow()
            .processing
    }
    pub fn run_func_with_input(&mut self, func_name: &str, input: Option<&str>, cb_id: i64) -> Val {
        let payload = if func_name.is_empty() {
            Val::new(0, Payload::Null)
        } else {
            let input_val = match input {
                Some(json_str) => {
                    let trimmed = json_str.trim();
                    if trimmed.is_empty() {
                        Val::new(0, Payload::Null)
                    } else {
                        match serde_json::from_str::<Value>(trimmed) {
                            Ok(value) => self.convert_json_value_to_val(value),
                            Err(_) => {
                                // Fallback: treat non-JSON payloads as plain strings.
                                Val::new(7, Payload::from(trimmed.to_string()))
                            }
                        }
                    }
                }
                None => Val::new(0, Payload::Null),
            };
            Val::new(
                9,
                Payload::from(Rc::new(RefCell::new(Array::new(
                    vec![
                        Val::new(7, Payload::from(func_name.to_string())),
                        input_val,
                    ],
                )))),
            )
        };
        let r = self
            .single_thread_executor
            .as_ref()
            .unwrap()
            .borrow_mut()
            .single_thread_operation(0x01, cb_id, payload);
        self.handle_executor_request(r.0, r.1, r.2)
    }
    pub fn continue_run(&mut self, res_raw: String) -> Val {
        let res_json: Value = serde_json::from_str(&res_raw).unwrap();
        let res = self.convert_json_value_to_val(res_json);
        let res_next = self
            .single_thread_executor
            .as_ref()
            .unwrap()
            .borrow_mut()
            .single_thread_operation(0x03, self.pending_host_call_id, res);
        self.handle_executor_request(res_next.0, res_next.1, res_next.2)
    }
    fn convert_json_value_to_val(&self, val: Value) -> Val {
        let maybe_typed_value = val
            .as_object()
            .and_then(|obj| obj.get("type").and_then(Value::as_str).map(|t| (obj, t)));

        if let Some((obj, typ)) = maybe_typed_value {
            let data_value = obj
                .get("data")
                .and_then(Value::as_object)
                .and_then(|data| data.get("value"))
                .cloned()
                .unwrap_or(Value::Null);

            match typ {
                "null" => return Val::new(0, Payload::Null),
                "i16" => {
                    if let Some(v) = data_value.as_i64() {
                        return Val::new(1, Payload::from(v as i16));
                    }
                }
                "i32" => {
                    if let Some(v) = data_value.as_i64() {
                        return Val::new(2, Payload::from(v as i32));
                    }
                }
                "i64" => {
                    if let Some(v) = data_value.as_i64() {
                        return Val::new(3, Payload::from(v));
                    }
                }
                "f32" => {
                    if let Some(v) = data_value.as_f64() {
                        return Val::new(4, Payload::from(v as f32));
                    }
                }
                "f64" | "number" => {
                    // `number` is the JS numeric type, aliased onto f64.
                    if let Some(v) = data_value.as_f64() {
                        return Val::new(5, Payload::from(v));
                    }
                }
                "bool" => {
                    if let Some(v) = data_value.as_bool() {
                        return Val::new(6, Payload::from(v));
                    }
                }
                "string" => {
                    if let Some(v) = data_value.as_str() {
                        return Val::new(7, Payload::from(v.to_string()));
                    }
                }
                "object" => {
                    if let Some(map) = data_value.as_object() {
                        let mut obj_map = ValMap::default();
                        for (k, v) in map.iter() {
                            obj_map.insert(k.clone(), self.convert_json_value_to_val(v.clone()));
                        }
                        return Val::new(
                            8,
                            Payload::from(Rc::new(RefCell::new(Object::new(
                                -2,
                                ValGroup::new(obj_map),
                            )))),
                        );
                    }
                }
                "array" => {
                    if let Some(items) = data_value.as_array() {
                        let vals: Vec<Val> = items
                            .iter()
                            .map(|item| self.convert_json_value_to_val(item.clone()))
                            .collect();
                        return Val::new(
                            9,
                            Payload::from(Rc::new(RefCell::new(Array::new(
                                vals,
                            )))),
                        );
                    }
                }
                _ => {}
            }
        }

        match val {
            Value::Null => Val::new(0, Payload::Null),
            Value::Bool(v) => Val::new(6, Payload::from(v)),
            Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    Val::new(3, Payload::from(i))
                } else {
                    Val::new(
                        5,
                        Payload::from(n.as_f64().unwrap_or(0.0)),
                    )
                }
            }
            Value::String(s) => Val::new(7, Payload::from(s)),
            Value::Array(items) => {
                let vals: Vec<Val> = items
                    .into_iter()
                    .map(|item| self.convert_json_value_to_val(item))
                    .collect();
                Val::new(
                    9,
                    Payload::from(Rc::new(RefCell::new(Array::new(
                        vals,
                    )))),
                )
            }
            Value::Object(map) => {
                let mut obj_map = ValMap::default();
                for (k, v) in map.into_iter() {
                    obj_map.insert(k, self.convert_json_value_to_val(v));
                }
                Val::new(
                    8,
                    Payload::from(Rc::new(RefCell::new(Object::new(
                        -2,
                        ValGroup::new(obj_map),
                    )))),
                )
            }
        }
    }
    fn handle_executor_request(&mut self, op_code: u8, cb_id: i64, payload: Val) -> Val {
        match op_code {
            0x01 => payload,
            0x02 => {
                // Build the host-call envelope by direct string concatenation
                // rather than `json!({…}).to_string()`. The previous form put
                // `payload` (which is itself a JSON string emitted by `stringify`)
                // *as* a JSON string value, forcing serde_json to re-escape every
                // byte. The embedder then had to JSON-parse the wrapper, JSON-
                // un-escape the payload string, *and* JSON-parse the payload —
                // three full passes over a buffer that, for a `gpu.submit` carrying
                // a fat instance buffer, dominates per-frame cost. Here payload is
                // spliced in **raw**, machine_id and api_name are escaped only
                // for their string slots, and the wrapper still parses as plain
                // JSON on the other side — but the payload survives as a single
                // contiguous JSON object the runtime can parse once.
                let params_arr = payload.as_array();
                let params = params_arr.borrow();
                self.pending_host_call_id = cb_id;
                let api_name = params.data[0].as_string();
                // Build the envelope as one growing buffer, streaming the
                // payload directly into it via `stringify_into` instead of
                // materialising a separate payload `String` first. The
                // payload is typically the dominant size (a per-frame instance
                // buffer of thousands of numbers), so cutting the intermediate
                // copy halves the allocation traffic of `gpu.submit`.
                let mut envelope = String::with_capacity(
                    self.machine_id.len() + api_name.len() + 1024,
                );
                envelope.push_str("{\"machineId\":");
                push_json_string(&mut envelope, &self.machine_id);
                envelope.push_str(",\"apiName\":");
                push_json_string(&mut envelope, &api_name);
                envelope.push_str(",\"payload\":");
                params.data[2].stringify_into(&mut envelope);
                envelope.push('}');
                self.sending_host_call_data = Some(envelope);
                Val::new(253, Payload::Null)
            }
            // 0x05 = paused (continuation preserved); 0x06 = terminated/trapped
            // (payload carries the trap reason string, empty for a clean stop).
            // Neither sets a host call: the embedder inspects `run_state()` /
            // `trap_reason()` and resumes or disposes accordingly.
            0x05 | 0x06 => payload,
            _ => Val::new(0, Payload::Null),
        }
    }
}

/// Append `s` to `out` as a JSON-encoded string literal (with surrounding
/// quotes). Hand-rolled so the host-call envelope can be built by simple
/// concatenation without paying for `serde_json::to_string` on the whole
/// envelope; the wrapper around `gpu.submit` is hit every frame.
fn push_json_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}
