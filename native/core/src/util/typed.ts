/**
 * The typed value envelope the Elpian VM uses on its host boundary:
 * `{"type": "<tag>", "data": {"value": <payload>}}`.
 *
 * Host APIs answer with these, and event payloads delivered to guest functions
 * are encoded with [toTypedVmValue] so both the native and the wasm VM decode
 * arguments the same way (mirrors `_toTypedVmValue` in elpian_vm_widget.dart).
 */

export function makeResponse(type: string, value: unknown): string {
  return JSON.stringify({ type, data: { value } });
}

export const NULL_RESPONSE = makeResponse('null', null);
export const OK_RESPONSE = makeResponse('i16', 0);
export const ONE_RESPONSE = makeResponse('i16', 1);

export interface TypedValue {
  type: string;
  data: { value: unknown };
}

export function toTypedVmValue(value: unknown): TypedValue {
  if (value === null || value === undefined) return { type: 'null', data: { value: null } };
  if (typeof value === 'boolean') return { type: 'bool', data: { value } };
  if (typeof value === 'number') {
    if (Number.isInteger(value) && Number.isSafeInteger(value)) {
      return { type: 'i64', data: { value } };
    }
    return { type: 'f64', data: { value } };
  }
  if (typeof value === 'string') return { type: 'string', data: { value } };
  if (Array.isArray(value)) {
    return { type: 'array', data: { value: value.map(toTypedVmValue) } };
  }
  if (typeof value === 'object') {
    const out: Record<string, TypedValue> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = toTypedVmValue(v);
    }
    return { type: 'object', data: { value: out } };
  }
  return { type: 'string', data: { value: String(value) } };
}

/** Decode a typed envelope back to a plain value (inverse of [toTypedVmValue]). */
export function fromTypedVmValue(value: any): any {
  if (value == null || typeof value !== 'object') return value;
  if (typeof value.type === 'string' && value.data && 'value' in value.data) {
    const inner = value.data.value;
    switch (value.type) {
      case 'array':
        return Array.isArray(inner) ? inner.map(fromTypedVmValue) : inner;
      case 'object': {
        if (inner == null || typeof inner !== 'object') return inner;
        const out: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(inner)) out[k] = fromTypedVmValue(v);
        return out;
      }
      default:
        return inner;
    }
  }
  return value;
}
