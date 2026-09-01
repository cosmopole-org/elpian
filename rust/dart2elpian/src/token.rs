//! Lexical tokens shared by the lexer and parser.

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Tok {
    Ident(String),
    Int(i64),
    Double(f64),
    Str(Vec<StrPart>),
    Bool(bool),
    Null,
    // punctuation / operators
    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Comma,
    Semi,
    Dot,
    Question,
    Colon,
    Op(String),
    Kw(String),
    Eof,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum StrPart {
    Lit(String),
    /// Raw source of an interpolation expression, re-parsed by the parser.
    Expr(String),
}

pub(crate) const KEYWORDS: &[&str] = &[
    "var", "final", "if", "else", "while", "for", "return", "void", "int", "double", "num",
    "String", "bool", "dynamic", "class", "extends", "this", "new", "super", "is", "as", "async",
    "await", "do", "switch", "case", "default", "break", "continue", "try", "catch", "finally",
    "throw", "rethrow",
];

