use std::any::Any;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

#[derive(Clone, Debug)]
pub struct Val {
    pub typ: i64,
    pub data: Rc<RefCell<Box<dyn Any>>>,
}

unsafe impl Send for Val {}

impl Val {
    pub fn new(typ: i64, data: Rc<RefCell<Box<dyn Any>>>) -> Self {
        Val { typ, data: data }
    }
    pub fn stringify(&self) -> String {
        return match self.typ {
            1 => self.as_i16().to_string(),
            2 => self.as_i32().to_string(),
            3 => self.as_i64().to_string(),
            4 => self.as_f32().to_string(),
            5 => self.as_f64().to_string(),
            6 => self.as_bool().to_string(),
            7 => serde_json::json!(self.as_string()).to_string(),
            8 => self.as_object().borrow().stringify(),
            9 => self.as_array().borrow().stringify(),
            10 => format!("\"{}\"", self.as_func().borrow().name.clone()),
            _ => "\"[undefined]\"".to_string(),
        };
    }
    fn clone_data(&self) -> Self {
        return match self.typ {
            1 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_i16().clone()))),
            },
            2 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_i32().clone()))),
            },
            3 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_i64().clone()))),
            },
            4 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_f32().clone()))),
            },
            5 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_f64().clone()))),
            },
            6 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_bool().clone()))),
            },
            7 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_string().clone()))),
            },
            8 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(
                    Rc::new(RefCell::new(self.as_object().borrow().clone_object())),
                ))),
            },
            9 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(Rc::new(RefCell::new(self.as_array().borrow().clone_arr()))))),
            },
            10 => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(self.as_func()))),
            },
            _ => Val {
                typ: self.typ,
                data: Rc::new(RefCell::new(Box::new(0))),
            },
        };
    }
    pub fn as_i16(&self) -> i16 {
        let a = self.data.clone();
        let x = a.borrow().downcast_ref::<i16>().unwrap().clone();
        x
    }
    pub fn as_i32(&self) -> i32 {
        let a = self.data.clone();
        let x = a.borrow().downcast_ref::<i32>().unwrap().clone();
        x
    }
    pub fn as_i64(&self) -> i64 {
        let a = self.data.clone();
        let x = a.borrow().downcast_ref::<i64>().unwrap().clone();
        x
    }
    pub fn as_f32(&self) -> f32 {
        let a = self.data.clone();
        let x = a.borrow().downcast_ref::<f32>().unwrap().clone();
        x
    }
    pub fn as_f64(&self) -> f64 {
        let a = self.data.clone();
        let x = a.borrow().downcast_ref::<f64>().unwrap().clone();
        x
    }
    pub fn as_bool(&self) -> bool {
        let a = self.data.clone();
        let x = a.borrow().downcast_ref::<bool>().unwrap().clone();
        x
    }
    pub fn as_string(&self) -> String {
        let a = self.data.clone();
        let x = a.borrow().downcast_ref::<String>().unwrap().clone();
        x
    }
    pub fn as_object(&self) -> Rc<RefCell<Object>> {
        let a = self.data.clone();
        let b = a.borrow();
        let c = b.downcast_ref::<Rc<RefCell<Object>>>().unwrap();
        c.clone()
    }
    pub fn as_array(&self) -> Rc<RefCell<Array>> {
        let a = self.data.clone();
        let b: std::cell::Ref<'_, Box<dyn Any>> = a.borrow();
        let c = b.downcast_ref::<Rc<RefCell<Array>>>().unwrap();
        c.clone()
    }
    pub fn as_func(&self) -> Rc<RefCell<Function>> {
        let a = self.data.clone();
        let b = a.borrow();
        let c = b.downcast_ref::<Rc<RefCell<Function>>>().unwrap();
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
    pub fn stringify(&self) -> String {
        let mut result = "{".to_string();
        let mut index = 0;
        for (k, v) in self.data.iter() {
            if index > 0 {
                result = format!("{}, \"{}\": {}", result, k, v.stringify());
            } else {
                result = format!("{} \"{}\": {}", result, k, v.stringify());
            }
            index += 1;
        }
        result = format!("{} }}", result);
        result
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
    pub typ: i64,
    pub data: ValGroup,
}

impl Object {
    pub fn new(typ: i64, data: ValGroup) -> Self {
        Object { typ, data }
    }
    pub fn clone_object(&self) -> Self {
        return Object::new(self.typ, self.data.clone_data());
    }
    pub fn stringify(&self) -> String {
        self.data.stringify()
    }
}

pub struct Array {
    pub data: Vec<Val>,
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
    pub fn stringify(&self) -> String {
        let mut result = "[".to_string();
        let mut index = 0;
        for v in self.data.iter() {
            if index > 0 {
                result = format!("{}, {}", result, v.stringify());
            } else {
                result = format!("{}{}", result, v.stringify());
            }
            index += 1;
        }
        result = format!("{}]", result);
        result
    }
}

#[derive(Clone, Debug)]
pub struct Function {
    pub name: String,
    pub start: usize,
    pub end: usize,
    pub params: Vec<String>,
}

impl Function {
    pub fn new(name: String, start: usize, end: usize, params: Vec<String>) -> Self {
        Function { name, start, end, params }
    }
    pub fn clone_func(&self) -> Self {
        return Function::new(self.name.clone(), self.start, self.end, self.params.clone());
    }
}
