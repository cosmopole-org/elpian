use std::sync::Arc;

use crate::sdk::data::{Val, ValGroup};

pub struct Scope {
    pub memory: Arc<ValGroup>,
}
impl Scope {
    pub fn new() -> Self {
        Scope {
            memory: Arc::new(ValGroup::new_empty()),
        }
    }
    pub fn find_val(&self, name: String) -> Val {
        let val = self.memory.data.get(&name);
        if val.is_none() {
            return Val::new(0, Arc::new(Box::new(0)));
        } else {
            return val.unwrap().clone();
        }
    }
}

pub struct Context {
    pub memory: Vec<Scope>,
}

impl Context {
    pub fn new() -> Self {
        Context {
            memory: vec![Scope::new()],
        }
    }
    pub fn push_scope(&mut self) {
        self.memory.push(Scope::new());
    }
    pub fn pop_scope(&mut self) {
        self.memory.pop();
    }
    pub fn get_scope(&mut self, index: usize) -> &Scope {
        let scope: &Scope = self.memory.get(index).unwrap();
        scope
    }
    pub fn find_val_globally(&mut self, name: String) -> Val {
        for scope in self.memory.iter() {
            let val = scope.find_val(name.clone());
            if !val.is_empty() {
                return val;
            }
        }
        Val::new(0, Arc::new(Box::new(0)))
    }
    pub fn find_val_in_last_scope(&mut self, name: String) -> Val {
        self.memory.last().unwrap().find_val(name.clone())
    }
    pub fn find_val_in_first_scope(&mut self, name: String) -> Val {
        self.memory.first().unwrap().find_val(name.clone())
    }
}
