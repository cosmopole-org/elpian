use std::{cell::RefCell, rc::Rc};

use crate::sdk::data::{Val, ValGroup};

pub struct Scope {
    pub memory: Rc<RefCell<ValGroup>>,
}
impl Scope {
    pub fn new() -> Self {
        Scope {
            memory: Rc::new(RefCell::new(ValGroup::new_empty())),
        }
    }
    pub fn find_val(&self, name: String) -> Val {
        let v = self.memory.borrow();
        let val = v.data.get(&name);
        if val.is_none() {
            return Val::new(0, Rc::new(RefCell::new(Box::new(0))));
        } else {
            return val.unwrap().clone();
        }
    }
    pub fn update_val(&mut self, name: String, val: Val) -> bool {
        let mut v = self.memory.borrow_mut();
        if v.data.contains_key(&name) {
            v.data.insert(name, val);
            return true;
        }
        false
    }
    pub fn define_val(&mut self, name: String, val: Val) {
        let mut v = self.memory.borrow_mut();
        v.data.insert(name, val);
    }
}

pub struct Context {
    pub memory: Vec<Rc<RefCell<Scope>>>,
}

impl Context {
    pub fn new() -> Self {
        Context {
            memory: vec![Rc::new(RefCell::new(Scope::new()))],
        }
    }
    pub fn push_scope(&mut self) {
        self.memory.push(Rc::new(RefCell::new(Scope::new())));
    }
    pub fn pop_scope(&mut self) {
        self.memory.pop();
    }
    pub fn get_scope(&mut self, index: usize) -> Rc<RefCell<Scope>> {
        self.memory.get(index).unwrap().clone()
    }
    pub fn find_val_globally(&mut self, name: String) -> Val {
        for scope in self.memory.iter().rev() {
            let val = scope.borrow().find_val(name.clone());
            if !val.is_empty() {
                return val;
            }
        }
        Val::new(0, Rc::new(RefCell::new(Box::new(0))))
    }
    pub fn put_val_globally(&mut self, name: String, val: Val) {
        let mut found = false;
        for scope in self.memory.iter().rev() {
            if scope.borrow_mut().update_val(name.clone(), val.clone()) {
                found = true;
                break;
            }
        }
        if !found {
            self.memory
                .last()
                .unwrap()
                .borrow_mut()
                .define_val(name.clone(), val.clone());
        }
    }
    pub fn find_val_in_last_scope(&mut self, name: String) -> Val {
        self.memory.last().unwrap().borrow().find_val(name.clone())
    }
    pub fn find_val_in_first_scope(&mut self, name: String) -> Val {
        self.memory.first().unwrap().borrow().find_val(name.clone())
    }
}
