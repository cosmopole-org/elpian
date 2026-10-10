/**
 * The `formatString` template language: literal text with `${…}`
 * interpolations, `\${` as an escaped literal marker. Inside an interpolation:
 *
 *   - literals: `'…'` / `"…"` strings (backslash escapes), numbers (`-1.5e3`,
 *     `.5`, `+1`, `1.`), `true`, `false`, `null`;
 *   - data paths: `/absolute/path`, `relative/path`, `./x`, `../x`;
 *   - function calls with named arguments: `formatDate(value: /d, format: 'yyyy')`
 *     (arguments are themselves expressions; a trailing comma is allowed);
 *   - nested interpolations: `${${/path}}`.
 *
 * Expressions nest at most {@link MAX_EXPRESSION_DEPTH} deep (interpolations
 * and function arguments both count). [parseTemplate] returns the parts with
 * adjacent string literals joined — the representation `expressions.yaml`
 * compares against.
 */
import { parseError } from './errors.js';

export const MAX_EXPRESSION_DEPTH = 100;

export interface PathPart {
  path: string;
}

export interface CallPart {
  call: string;
  args: Record<string, TemplateValue>;
  returnType: 'any';
}

export type TemplateValue = string | number | boolean | null | PathPart | CallPart;
/** A parsed template part (`null` never appears: it produces no part). */
export type TemplatePart = string | number | boolean | PathPart | CallPart;

const IDENT_CHAR = /[A-Za-z0-9_\-./~$@#[\]]/;
const ARG_NAME_CHAR = /[A-Za-z0-9_]/;

class Parser {
  i = 0;
  constructor(readonly s: string) {}

  peek(offset = 0): string {
    return this.s[this.i + offset] ?? '';
  }

  skipWs(): void {
    while (this.i < this.s.length && /\s/.test(this.s[this.i])) this.i++;
  }

  /** The body of one `${…}` whose `${` has been consumed; leaves `}` consumed. */
  interpolation(depth: number): TemplateValue {
    if (depth > MAX_EXPRESSION_DEPTH) throw parseError(`Max recursion depth (${MAX_EXPRESSION_DEPTH}) exceeded in expression`);
    this.skipWs();
    if (this.i >= this.s.length) throw parseError('Unclosed interpolation: expected "}"');
    const value = this.expression(depth);
    this.skipWs();
    if (this.i >= this.s.length) throw parseError('Unclosed interpolation: expected "}"');
    if (this.peek() !== '}') throw parseError(`Unexpected characters "${this.s.substring(this.i, this.i + 10)}" in expression`);
    this.i++;
    return value;
  }

  expression(depth: number): TemplateValue {
    if (depth > MAX_EXPRESSION_DEPTH) throw parseError(`Max recursion depth (${MAX_EXPRESSION_DEPTH}) exceeded in expression`);
    this.skipWs();
    const c = this.peek();
    if (c === '') throw parseError('Unclosed interpolation: expected an expression');
    if (c === '$' && this.peek(1) === '{') {
      this.i += 2;
      return this.interpolation(depth + 1);
    }
    if (c === "'" || c === '"') return this.stringLiteral(c);
    if (this.startsNumber()) return this.number();
    const start = this.i;
    while (this.i < this.s.length && IDENT_CHAR.test(this.s[this.i]) && !(this.s[this.i] === '$' && this.peek(1) === '{')) this.i++;
    const token = this.s.substring(start, this.i);
    if (token === '') throw parseError(`Unexpected characters "${this.s.substring(this.i, this.i + 10)}" in expression`);
    const save = this.i;
    this.skipWs();
    if (this.peek() === '(') {
      this.i++;
      return this.call(token, depth);
    }
    this.i = save;
    if (token === 'true') return true;
    if (token === 'false') return false;
    if (token === 'null') return null;
    return { path: token };
  }

  private startsNumber(): boolean {
    const digit = (ch: string) => ch >= '0' && ch <= '9';
    const c = this.peek();
    if (digit(c)) return true;
    if (c === '.') return digit(this.peek(1));
    if (c === '+' || c === '-') return digit(this.peek(1)) || (this.peek(1) === '.' && digit(this.peek(2)));
    return false;
  }

  private number(): number {
    const start = this.i;
    if (this.peek() === '+' || this.peek() === '-') this.i++;
    while (this.i < this.s.length) {
      const ch = this.s[this.i];
      if ((ch >= '0' && ch <= '9') || ch === '.') this.i++;
      else if (ch === 'e' || ch === 'E') {
        this.i++;
        if (this.peek() === '+' || this.peek() === '-') this.i++;
      } else break;
    }
    const text = this.s.substring(start, this.i);
    if (!/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.test(text)) throw parseError(`Invalid number literal "${text}"`);
    const value = Number(text);
    if (!Number.isFinite(value)) throw parseError(`Number literal "${text}" is out of range`);
    return value === 0 ? 0 : value;
  }

  private stringLiteral(quote: string): string {
    this.i++;
    let out = '';
    while (this.i < this.s.length) {
      const ch = this.s[this.i++];
      if (ch === quote) return out;
      if (ch === '\\') {
        const next = this.s[this.i++] ?? '';
        out += next === 'n' ? '\n' : next === 't' ? '\t' : next === 'r' ? '\r' : next;
      } else out += ch;
    }
    throw parseError('Unclosed string literal in expression');
  }

  private call(name: string, depth: number): CallPart {
    const args: Record<string, TemplateValue> = {};
    this.skipWs();
    if (this.peek() === ')') {
      this.i++;
      return { call: name, args, returnType: 'any' };
    }
    for (;;) {
      this.skipWs();
      const start = this.i;
      while (this.i < this.s.length && ARG_NAME_CHAR.test(this.s[this.i])) this.i++;
      const argName = this.s.substring(start, this.i);
      this.skipWs();
      if (!argName || this.peek() !== ':') throw parseError(`Expected ":" after argument name in call to ${name}()`);
      this.i++;
      args[argName] = this.expression(depth + 1);
      this.skipWs();
      const c = this.peek();
      if (c === ',') {
        this.i++;
        this.skipWs();
        if (this.peek() === ')') {
          this.i++;
          break;
        }
        continue;
      }
      if (c === ')') {
        this.i++;
        break;
      }
      throw parseError(`Expected "," or ")" after function arguments in call to ${name}()`);
    }
    return { call: name, args, returnType: 'any' };
  }
}

/** Parse a `formatString` template into its parts (adjacent literals joined). */
export function parseTemplate(input: string): TemplatePart[] {
  const parts: TemplatePart[] = [];
  let literal = '';
  const flush = () => {
    if (literal !== '') parts.push(literal);
    literal = '';
  };
  const p = new Parser(input);
  while (p.i < input.length) {
    const ch = input[p.i];
    if (ch === '\\' && input[p.i + 1] === '$' && input[p.i + 2] === '{') {
      literal += '${';
      p.i += 3;
      continue;
    }
    if (ch === '$' && input[p.i + 1] === '{') {
      p.i += 2;
      const value = p.interpolation(1);
      if (value === null) continue;
      if (typeof value === 'string') literal += value;
      else {
        flush();
        parts.push(value);
      }
      continue;
    }
    literal += ch;
    p.i++;
  }
  flush();
  return parts;
}

/** True when [input] contains an interpolation (an unescaped `${`). */
export function hasInterpolation(input: string): boolean {
  return /(^|[^\\])\$\{/.test(input);
}
