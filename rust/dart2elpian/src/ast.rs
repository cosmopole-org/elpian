//! The Dart-subset abstract syntax tree produced by the parser and consumed by
//! the emitter and source transforms.

use crate::token::StrPart;

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub(crate) enum Expr {
    Int(i64),
    Double(f64),
    Str(Vec<StrPart>),
    Bool(bool),
    Null,
    Ident(String),
    List(Vec<Expr>),
    Unary(String, Box<Expr>),
    Binary(String, Box<Expr>, Box<Expr>),
    Assign(Box<Expr>, Box<Expr>),
    /// Compound assignment `lhs op= rhs` (`+= -= *= /=`).
    AssignOp(String, Box<Expr>, Box<Expr>),
    /// `++`/`--`; the bool is true for prefix form.
    Update(String, Box<Expr>, bool),
    Ternary(Box<Expr>, Box<Expr>, Box<Expr>),
    Call(Box<Expr>, Vec<Expr>, Vec<(String, Expr)>),
    Index(Box<Expr>, Box<Expr>),
    /// Member access `obj.name`.
    Member(Box<Expr>, String),
    /// `this`.
    This,
    /// Instantiation `ClassName(args)` — Dart has no `new` keyword required.
    New(String, Vec<Expr>, Vec<(String, Expr)>),
    /// `expr is Type` — a reified type test.
    Is(Box<Expr>, String),
    /// `expr as Type` — a reified cast.
    As(Box<Expr>, String),
    /// A function expression / closure: `(params) => expr` or `(params) { body }`.
    Closure(ParamList, Vec<Stmt>),
    /// `await expr` inside an `async` function.
    Await(Box<Expr>),
    /// A map literal `{k: v, ...}` (entries with values) or a set literal
    /// `{a, b, ...}` (entries without values, lowered to a list).
    MapOrSet(Vec<(Expr, Option<Expr>)>),
    /// `throw expr` — Dart's throw is an expression.
    Throw(Box<Expr>),
    /// Null-aware member access `obj?.name` (short-circuits to null on a null
    /// receiver).
    NullMember(Box<Expr>, String),
    /// A cascade `target..a()..b = c` — a sequence of operations on one target,
    /// evaluating to the target. Each element is applied to the (shared) target.
    Cascade(Box<Expr>, Vec<CascadeOp>),
}

/// One section of a cascade (`..member`, `..method(args)`, `..[i] = v`, …),
/// applied to the cascade's shared target.
#[derive(Debug, Clone)]
pub(crate) enum CascadeOp {
    /// `..name` / `..name = value` (when `assign` is set) / `..name(args)`
    /// (when `call` is set).
    Member(String, Option<Box<Expr>>, Option<(Vec<Expr>, Vec<(String, Expr)>)>),
    /// `..[index] = value`.
    IndexSet(Box<Expr>, Box<Expr>),
}

#[derive(Debug, Clone)]
pub(crate) enum Stmt {
    Var(String, Option<Expr>),
    Expr(Expr),
    Return(Option<Expr>),
    If(Expr, Vec<Stmt>, Vec<Stmt>),
    While(Expr, Vec<Stmt>),
    /// `do { body } while (cond);`.
    DoWhile(Vec<Stmt>, Expr),
    Block(Vec<Stmt>),
    Break,
    Continue,
    /// `switch (value) { case v: … default: … }`. Each arm is (case-value
    /// expressions, body); the optional trailing body is the `default` arm.
    Switch(Expr, Vec<(Vec<Expr>, Vec<Stmt>)>, Option<Vec<Stmt>>),
    /// `try { body } on T catch (e) { … } finally { … }`. The catch binding and
    /// body are present when a `catch`/`on` clause exists; `finally` when a
    /// `finally` clause exists.
    Try(Vec<Stmt>, Option<(String, Vec<Stmt>)>, Option<Vec<Stmt>>),
}

/// A single formal parameter.
#[derive(Debug, Clone)]
pub(crate) struct Param {
    pub(crate) name: String,
    /// `this.x` shorthand (constructors) — assigns the field directly.
    pub(crate) is_this: bool,
    /// Default value for optional-positional / named params.
    pub(crate) default: Option<Expr>,
}

/// A parsed parameter list: required-positional, optional-positional (`[...]`),
/// and named (`{...}`). Named params are lowered to a single trailing options
/// object; optional-positional to trailing params with null-default fill-in.
#[derive(Debug, Clone, Default)]
pub(crate) struct ParamList {
    pub(crate) positional: Vec<Param>,
    pub(crate) optional_pos: Vec<Param>,
    pub(crate) named: Vec<Param>,
}

impl ParamList {
    pub(crate) fn all_this_params(&self) -> impl Iterator<Item = &Param> {
        self.positional
            .iter()
            .chain(self.optional_pos.iter())
            .chain(self.named.iter())
            .filter(|p| p.is_this)
    }
}

pub(crate) const NAMED_ARG: &str = "__named";

#[derive(Debug, Clone)]
pub(crate) struct Method {
    pub(crate) name: String,
    pub(crate) params: ParamList,
    pub(crate) body: Vec<Stmt>,
    pub(crate) is_async: bool,
    /// A getter (`T get x => …`): declared with no parameters and read as a bare
    /// member (`obj.x`), which the emitter rewrites to a call `obj.x()`.
    pub(crate) is_getter: bool,
    /// A `static` member: belongs to the class, reached as `Class.member`.
    pub(crate) is_static: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct ClassDecl {
    pub(crate) name: String,
    pub(crate) superclass: Option<String>,
    pub(crate) fields: Vec<(String, Option<Expr>)>,
    /// `static` fields (`static const foo = …`), reached as `Class.foo`.
    pub(crate) static_fields: Vec<(String, Option<Expr>)>,
    pub(crate) ctor_params: ParamList,
    pub(crate) ctor_body: Vec<Stmt>,
    pub(crate) has_ctor: bool,
    pub(crate) calls_super: bool,
    pub(crate) methods: Vec<Method>,
}

/// A Dart `enum Name { a, b, c }`, lowered to a top-level object mapping each
/// constant to its name string, so `Name.a` reads as a stable comparable value.
#[derive(Debug, Clone)]
pub(crate) struct EnumDecl {
    pub(crate) name: String,
    pub(crate) variants: Vec<String>,
}

#[derive(Debug, Clone)]
pub(crate) enum Item {
    Func(String, ParamList, Vec<Stmt>, bool /* is_async */),
    Class(ClassDecl),
    Enum(EnumDecl),
    Stmt(Stmt),
}

