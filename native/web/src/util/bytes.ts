/**
 * UTF-8 and base64 helpers that work the same in every JS environment the web
 * host runs in (browsers, workers, Node for tests).
 */

export function utf8Encode(text: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < text.length; i++) {
    let c = text.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
      const d = text.charCodeAt(i + 1);
      if (d >= 0xdc00 && d <= 0xdfff) {
        c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
        i++;
      } else c = 0xfffd;
    } else if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return Uint8Array.from(out);
}

/** Decode UTF-8, replacing malformed sequences with U+FFFD (`allowMalformed`). */
export function utf8Decode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  const n = bytes.length;
  const push = (cp: number) => {
    if (cp >= 0x10000) {
      cp -= 0x10000;
      out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
    } else out += String.fromCharCode(cp);
  };
  while (i < n) {
    const b = bytes[i];
    if (b < 0x80) {
      push(b);
      i++;
      continue;
    }
    let need = 0;
    let cp = 0;
    let min = 0;
    if (b >= 0xc2 && b <= 0xdf) {
      need = 1;
      cp = b & 0x1f;
      min = 0x80;
    } else if (b >= 0xe0 && b <= 0xef) {
      need = 2;
      cp = b & 0x0f;
      min = 0x800;
    } else if (b >= 0xf0 && b <= 0xf4) {
      need = 3;
      cp = b & 0x07;
      min = 0x10000;
    } else {
      push(0xfffd);
      i++;
      continue;
    }
    let j = 1;
    for (; j <= need; j++) {
      const c = bytes[i + j];
      if (c === undefined || (c & 0xc0) !== 0x80) break;
      cp = (cp << 6) | (c & 0x3f);
    }
    if (j <= need || cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) {
      push(0xfffd);
      i += Math.max(1, j);
      continue;
    }
    push(cp);
    i += need + 1;
  }
  return out;
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64_INDEX: Record<string, number> = {};
for (let i = 0; i < B64.length; i++) B64_INDEX[B64[i]] = i;
B64_INDEX['-'] = 62;
B64_INDEX['_'] = 63;

export function base64Encode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const v = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64[v >> 18] + B64[(v >> 12) & 63] + B64[(v >> 6) & 63] + B64[v & 63];
  }
  const rest = bytes.length - i;
  if (rest === 1) {
    const v = bytes[i] << 16;
    out += B64[v >> 18] + B64[(v >> 12) & 63] + '==';
  } else if (rest === 2) {
    const v = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64[v >> 18] + B64[(v >> 12) & 63] + B64[(v >> 6) & 63] + '=';
  }
  return out;
}

/** Decode standard or URL-safe base64 (whitespace and padding tolerated). */
export function base64Decode(text: string): Uint8Array {
  const clean = text.replace(/[\s=]/g, '');
  const out = new Uint8Array(Math.floor((clean.length * 3) / 4));
  let o = 0;
  let acc = 0;
  let bits = 0;
  for (let i = 0; i < clean.length; i++) {
    const v = B64_INDEX[clean[i]];
    if (v === undefined) throw new Error(`invalid base64 character "${clean[i]}"`);
    acc = (acc << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[o++] = (acc >> bits) & 0xff;
    }
  }
  return out.subarray(0, o);
}
