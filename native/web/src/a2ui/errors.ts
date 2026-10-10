/**
 * A2UI errors. Every failure the renderer reports carries a category (the
 * conformance suites' `expect_error.category`) and, for validation failures,
 * the protocol's standard error shape:
 *
 * ```json
 * { "code": "VALIDATION_FAILED", "surfaceId": "s1", "path": "/components/0/text", "message": "…" }
 * ```
 */

export type A2UIErrorCategory = 'DataError' | 'ParseError' | 'ValidationError' | 'ExpressionError' | 'TransportError';

/** Machine-readable cause of a schema issue (`missing_field`, `invalid_value`, …). */
export type A2UIIssueCode = 'missing_field' | 'invalid_value' | 'type_mismatch' | 'unknown_field' | 'topology' | 'limit';

export class A2UIError extends Error {
  constructor(
    readonly category: A2UIErrorCategory,
    message: string,
    readonly details: { surfaceId?: string | null; path?: string | null; issue?: A2UIIssueCode | null } = {},
  ) {
    super(message);
    this.name = category;
  }

  get surfaceId(): string | null {
    return this.details.surfaceId ?? null;
  }

  get path(): string | null {
    return this.details.path ?? null;
  }

  /** The client→server `error` payload (A2UI's standard shape). */
  toWire(): A2UIWireError {
    if (this.category === 'ValidationError') {
      return { code: 'VALIDATION_FAILED', surfaceId: this.surfaceId ?? '', path: this.path ?? '/', message: this.message };
    }
    return { code: this.category.replace(/Error$/, '').toUpperCase() + '_ERROR', surfaceId: this.surfaceId ?? '', message: this.message };
  }
}

export interface A2UIWireError {
  code: string;
  surfaceId: string;
  path?: string;
  message: string;
}

export function dataError(message: string): A2UIError {
  return new A2UIError('DataError', message);
}

export function parseError(message: string): A2UIError {
  return new A2UIError('ParseError', message);
}

export function expressionError(message: string): A2UIError {
  return new A2UIError('ExpressionError', message);
}
