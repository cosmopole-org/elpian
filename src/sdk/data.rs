use std::any::Any;
use std::collections::HashMap;
use std::ops::Deref;
use std::sync::Arc;

#[derive(Clone)]
pub struct Val {
    pub typ: i64,
    pub data: Arc<Box<dyn Any>>,
}

unsafe impl Send for Val {}

impl Val {
    pub fn new(typ: i64, data: Arc<Box<dyn Any>>) -> Self {
        Val { typ, data: data }
    }
    fn clone_data(&self) -> Self {
        return match self.typ {
            1 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_i16().clone())),
            },
            2 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_i32().clone())),
            },
            3 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_i64().clone())),
            },
            4 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_f32().clone())),
            },
            5 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_f64().clone())),
            },
            6 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_bool().clone())),
            },
            7 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_string().clone())),
            },
            8 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_object().clone_object())),
            },
            9 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_array())),
            },
            10 => Val {
                typ: self.typ,
                data: Arc::new(Box::new(self.as_func())),
            },
            11 => {
                let d: Arc<Val> = self.as_refer();
                Val {
                    typ: self.typ,
                    data: Arc::new(Box::new(d)),
                }
            }
            _ => Val {
                typ: self.typ,
                data: Arc::new(Box::new(0)),
            },
        };
    }
    pub fn as_i16(&self) -> i16 {
        let a = self.data.clone();
        let b = a.deref();
        b.downcast_ref::<i16>().unwrap().clone()
    }
    pub fn as_i32(&self) -> i32 {
        let a = self.data.clone();
        let b = a.deref();
        b.downcast_ref::<i32>().unwrap().clone()
    }
    pub fn as_i64(&self) -> i64 {
        let a = self.data.clone();
        let b = a.deref();
        b.downcast_ref::<i64>().unwrap().clone()
    }
    pub fn as_f32(&self) -> f32 {
        let a = self.data.clone();
        let b = a.deref();
        b.downcast_ref::<f32>().unwrap().clone()
    }
    pub fn as_f64(&self) -> f64 {
        let a = self.data.clone();
        let b = a.deref();
        b.downcast_ref::<f64>().unwrap().clone()
    }
    pub fn as_bool(&self) -> bool {
        let a = self.data.clone();
        let b = a.deref();
        b.downcast_ref::<bool>().unwrap().clone()
    }
    pub fn as_string(&self) -> String {
        let a = self.data.clone();
        let b = a.deref();
        b.downcast_ref::<String>().unwrap().clone()
    }
    pub fn as_object(&self) -> Object {
        let a = self.data.clone();
        let b = a.deref();
        let c = b.downcast_ref::<Object>().unwrap();
        c.clone_object()
    }
    pub fn as_array(&self) -> Array {
        let a = self.data.clone();
        let b = a.deref();
        let c = b.downcast_ref::<Array>().unwrap();
        c.clone_arr()
    }
    pub fn as_func(&self) -> Function {
        let a = self.data.clone();
        let b = a.deref();
        let c = b.downcast_ref::<Function>().unwrap();
        c.clone_func()
    }
    pub fn as_refer(&self) -> Arc<Val> {
        let a = self.data.clone();
        let b = a.deref();
        let c = b.downcast_ref::<Arc<Val>>().unwrap();
        c.clone()
    }
    pub fn is_empty(&self) -> bool {
        self.typ == 0
    }
}

pub struct ValGroup {
    pub data: HashMap<String, Val>,
}

impl ValGroup {
    pub fn new_empty() -> Self {
        ValGroup {
            data: HashMap::new(),
        }
    }
    pub fn new(data: HashMap<String, Val>) -> Self {
        ValGroup { data }
    }
    fn clone_data(&self) -> Self {
        let mut copied: HashMap<String, Val> = HashMap::new();
        for (k, v) in self.data.iter() {
            copied.insert(k.clone(), v.clone_data());
        }
        ValGroup::new(copied)
    }
}

pub struct Blueprint {
    pub typ_id: i64,
    pub def_props: ValGroup,
}

impl Blueprint {
    pub fn new(typ_id: i64, def_props: ValGroup) -> Self {
        Blueprint { typ_id, def_props }
    }
    pub fn new_instance(&self) -> Object {
        Object::new(self.typ_id, self.def_props.clone_data())
    }
}

pub struct Object {
    typ: i64,
    data: ValGroup,
}

impl Object {
    pub fn new(typ: i64, data: ValGroup) -> Self {
        Object { typ, data }
    }
    pub fn clone_object(&self) -> Self {
        return Object::new(self.typ, self.data.clone_data());
    }
}

pub struct Array {
    data: Vec<Val>,
}

impl Array {
    pub fn new_empty() -> Self {
        Array { data: vec![] }
    }
    pub fn new(data: Vec<Val>) -> Self {
        Array { data: data }
    }
    pub fn clone_arr(&self) -> Self {
        return Array::new(self.data.iter().map(|item| item.clone_data()).collect());
    }
}

pub struct Function {
    pub start: usize,
    pub end: usize,
}

impl Function {
    pub fn new(start: usize, end: usize) -> Self {
        Function { start, end }
    }
    pub fn clone_func(&self) -> Self {
        return Function::new(self.start, self.end);
    }
}
