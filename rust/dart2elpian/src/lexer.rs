//! The Dart-subset lexer: source text -> a token stream.

use crate::token::{Tok, StrPart, KEYWORDS};

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

pub(crate) struct Lexer<'a> {
    src: &'a [u8],
    pos: usize,
}

impl<'a> Lexer<'a> {
    pub(crate) fn new(src: &'a str) -> Self {
        Lexer { src: src.as_bytes(), pos: 0 }
    }

    fn peek(&self) -> u8 {
        *self.src.get(self.pos).unwrap_or(&0)
    }
    fn peek2(&self) -> u8 {
        *self.src.get(self.pos + 1).unwrap_or(&0)
    }
    fn bump(&mut self) -> u8 {
        let c = self.peek();
        self.pos += 1;
        c
    }

    fn skip_trivia(&mut self) {
        loop {
            let c = self.peek();
            if c.is_ascii_whitespace() {
                self.pos += 1;
            } else if c == b'/' && self.peek2() == b'/' {
                while self.peek() != b'\n' && self.peek() != 0 {
                    self.pos += 1;
                }
            } else if c == b'/' && self.peek2() == b'*' {
                self.pos += 2;
                while !(self.peek() == b'*' && self.peek2() == b'/') && self.peek() != 0 {
                    self.pos += 1;
                }
                self.pos += 2;
            } else {
                break;
            }
        }
    }

    pub(crate) fn tokenize(&mut self) -> Result<Vec<Tok>, String> {
        let mut out = Vec::new();
        loop {
            self.skip_trivia();
            let c = self.peek();
            if c == 0 {
                out.push(Tok::Eof);
                return Ok(out);
            }
            if c == b'@' {
                // Metadata annotation (`@override`, `@immutable`, `@Foo(bar)`):
                // consume it entirely at lex time so the parser never sees it.
                self.skip_annotation();
                continue;
            }
            if c.is_ascii_alphabetic() || c == b'_' {
                out.push(self.lex_ident());
            } else if c.is_ascii_digit() {
                out.push(self.lex_number()?);
            } else if c == b'"' || c == b'\'' {
                out.push(self.lex_string(c)?);
            } else {
                out.push(self.lex_op()?);
            }
        }
    }

    fn lex_ident(&mut self) -> Tok {
        let start = self.pos;
        while {
            let c = self.peek();
            c.is_ascii_alphanumeric() || c == b'_'
        } {
            self.pos += 1;
        }
        let s = std::str::from_utf8(&self.src[start..self.pos]).unwrap().to_string();
        match s.as_str() {
            "true" => Tok::Bool(true),
            "false" => Tok::Bool(false),
            "null" => Tok::Null,
            _ if KEYWORDS.contains(&s.as_str()) => Tok::Kw(s),
            _ => Tok::Ident(s),
        }
    }

    /// Consume a metadata annotation: `@`, a dotted identifier
    /// (`Foo`, `Foo.bar`), and an optional balanced argument list `( ... )`.
    /// Annotations carry no runtime meaning here, so they are dropped.
    fn skip_annotation(&mut self) {
        self.pos += 1; // '@'
        // dotted identifier
        loop {
            while {
                let c = self.peek();
                c.is_ascii_alphanumeric() || c == b'_'
            } {
                self.pos += 1;
            }
            if self.peek() == b'.' {
                self.pos += 1;
            } else {
                break;
            }
        }
        self.skip_trivia();
        if self.peek() == b'(' {
            let mut depth = 0i32;
            loop {
                match self.peek() {
                    b'(' => depth += 1,
                    b')' => {
                        depth -= 1;
                        self.pos += 1;
                        if depth == 0 {
                            break;
                        }
                        continue;
                    }
                    0 => break,
                    _ => {}
                }
                self.pos += 1;
            }
        }
    }

    fn lex_number(&mut self) -> Result<Tok, String> {
        let start = self.pos;
        // Hex integer literal (`0xFF2196F3`) — common for ARGB colours.
        if self.peek() == b'0' && (self.peek2() == b'x' || self.peek2() == b'X') {
            self.pos += 2;
            let hstart = self.pos;
            while self.peek().is_ascii_hexdigit() {
                self.pos += 1;
            }
            if self.pos == hstart {
                return Err("bad hex literal".into());
            }
            let s = std::str::from_utf8(&self.src[hstart..self.pos]).unwrap();
            return Ok(Tok::Int(i64::from_str_radix(s, 16).map_err(|_| "bad hex literal")?));
        }
        let mut is_double = false;
        while self.peek().is_ascii_digit() {
            self.pos += 1;
        }
        if self.peek() == b'.' && self.peek2().is_ascii_digit() {
            is_double = true;
            self.pos += 1;
            while self.peek().is_ascii_digit() {
                self.pos += 1;
            }
        }
        let s = std::str::from_utf8(&self.src[start..self.pos]).unwrap();
        if is_double {
            Ok(Tok::Double(s.parse().map_err(|_| "bad double")?))
        } else {
            Ok(Tok::Int(s.parse().map_err(|_| "bad int")?))
        }
    }

    /// Lex a string literal into interpolation parts. Supports `\n \t \\ \" \$`,
    /// `$identifier`, and `${expression}`.
    fn lex_string(&mut self, quote: u8) -> Result<Tok, String> {
        self.bump(); // opening quote
        let mut parts = Vec::new();
        let mut lit = String::new();
        loop {
            let c = self.peek();
            if c == 0 {
                return Err("unterminated string".into());
            }
            if c == quote {
                self.bump();
                break;
            }
            if c == b'\\' {
                self.bump();
                let e = self.bump();
                lit.push(match e {
                    b'n' => '\n',
                    b't' => '\t',
                    b'r' => '\r',
                    b'\\' => '\\',
                    b'$' => '$',
                    other => other as char,
                });
                continue;
            }
            if c == b'$' {
                if !lit.is_empty() {
                    parts.push(StrPart::Lit(std::mem::take(&mut lit)));
                }
                self.bump();
                if self.peek() == b'{' {
                    self.bump();
                    let start = self.pos;
                    let mut depth = 1;
                    while depth > 0 {
                        let d = self.bump();
                        match d {
                            b'{' => depth += 1,
                            b'}' => depth -= 1,
                            0 => return Err("unterminated interpolation".into()),
                            _ => {}
                        }
                    }
                    let raw = std::str::from_utf8(&self.src[start..self.pos - 1]).unwrap().to_string();
                    parts.push(StrPart::Expr(raw));
                } else {
                    let start = self.pos;
                    while {
                        let d = self.peek();
                        d.is_ascii_alphanumeric() || d == b'_'
                    } {
                        self.pos += 1;
                    }
                    let raw = std::str::from_utf8(&self.src[start..self.pos]).unwrap().to_string();
                    parts.push(StrPart::Expr(raw));
                }
                continue;
            }
            lit.push(self.bump() as char);
        }
        if !lit.is_empty() || parts.is_empty() {
            parts.push(StrPart::Lit(lit));
        }
        Ok(Tok::Str(parts))
    }

    fn lex_op(&mut self) -> Result<Tok, String> {
        let c = self.bump();
        let two = |a: u8, b: u8, s: &mut Self| -> bool {
            if s.peek() == b {
                s.pos += 1;
                let _ = a;
                true
            } else {
                false
            }
        };
        let tok = match c {
            b'(' => Tok::LParen,
            b')' => Tok::RParen,
            b'{' => Tok::LBrace,
            b'}' => Tok::RBrace,
            b'[' => Tok::LBracket,
            b']' => Tok::RBracket,
            b',' => Tok::Comma,
            b';' => Tok::Semi,
            b'.' => {
                if two(b'.', b'.', self) {
                    Tok::Op("..".into())
                } else {
                    Tok::Dot
                }
            }
            b'?' => {
                if self.peek() == b'?' {
                    self.pos += 1;
                    if self.peek() == b'=' {
                        self.pos += 1;
                        Tok::Op("??=".into())
                    } else {
                        Tok::Op("??".into())
                    }
                } else if self.peek() == b'.' {
                    self.pos += 1;
                    Tok::Op("?.".into())
                } else {
                    Tok::Question
                }
            }
            b':' => Tok::Colon,
            b'+' => {
                if two(b'+', b'+', self) {
                    Tok::Op("++".into())
                } else if two(b'+', b'=', self) {
                    Tok::Op("+=".into())
                } else {
                    Tok::Op("+".into())
                }
            }
            b'-' => {
                if two(b'-', b'-', self) {
                    Tok::Op("--".into())
                } else if two(b'-', b'=', self) {
                    Tok::Op("-=".into())
                } else {
                    Tok::Op("-".into())
                }
            }
            b'*' => {
                if two(b'*', b'=', self) {
                    Tok::Op("*=".into())
                } else {
                    Tok::Op("*".into())
                }
            }
            b'%' => {
                if two(b'%', b'=', self) {
                    Tok::Op("%=".into())
                } else {
                    Tok::Op("%".into())
                }
            }
            b'/' => {
                if two(b'/', b'=', self) {
                    Tok::Op("/=".into())
                } else {
                    Tok::Op("/".into())
                }
            }
            b'~' => {
                if two(b'~', b'/', self) {
                    Tok::Op("~/".into())
                } else {
                    // Bitwise NOT (unary).
                    Tok::Op("~".into())
                }
            }
            b'=' => {
                if two(b'=', b'=', self) {
                    Tok::Op("==".into())
                } else if two(b'=', b'>', self) {
                    Tok::Op("=>".into())
                } else {
                    Tok::Op("=".into())
                }
            }
            b'!' => {
                if two(b'!', b'=', self) {
                    Tok::Op("!=".into())
                } else {
                    Tok::Op("!".into())
                }
            }
            b'<' => {
                if two(b'<', b'=', self) {
                    Tok::Op("<=".into())
                } else if self.peek() == b'<' {
                    self.pos += 1;
                    if self.peek() == b'=' {
                        self.pos += 1;
                        Tok::Op("<<=".into())
                    } else {
                        Tok::Op("<<".into())
                    }
                } else {
                    Tok::Op("<".into())
                }
            }
            b'>' => {
                if two(b'>', b'=', self) {
                    Tok::Op(">=".into())
                } else if self.peek() == b'>' {
                    self.pos += 1;
                    if self.peek() == b'>' {
                        self.pos += 1;
                        if self.peek() == b'=' {
                            self.pos += 1;
                            Tok::Op(">>>=".into())
                        } else {
                            Tok::Op(">>>".into())
                        }
                    } else if self.peek() == b'=' {
                        self.pos += 1;
                        Tok::Op(">>=".into())
                    } else {
                        Tok::Op(">>".into())
                    }
                } else {
                    Tok::Op(">".into())
                }
            }
            b'&' => {
                if two(b'&', b'&', self) {
                    Tok::Op("&&".into())
                } else if two(b'&', b'=', self) {
                    Tok::Op("&=".into())
                } else {
                    Tok::Op("&".into())
                }
            }
            b'|' => {
                if two(b'|', b'|', self) {
                    Tok::Op("||".into())
                } else if two(b'|', b'=', self) {
                    Tok::Op("|=".into())
                } else {
                    Tok::Op("|".into())
                }
            }
            b'^' => {
                if two(b'^', b'=', self) {
                    Tok::Op("^=".into())
                } else {
                    Tok::Op("^".into())
                }
            }
            other => return Err(format!("unexpected character '{}'", other as char)),
        };
        Ok(tok)
    }
}

