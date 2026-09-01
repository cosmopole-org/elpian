//! `dart:typed_data` — foundational byte-buffer library.
//!
//! `typed_data` is a "group 3" foundational library (a native part of the Dart
//! runtime, not written in user Dart) that the Flutter framework leans on
//! everywhere — every `Image`, `Path`, vertex list, and platform-channel message
//! is `ByteData`/`Uint8List` underneath. It is, however, *self-contained*: it is
//! pure memory with no GPU/OS dependency, which makes it the natural first
//! group-3 library to implement completely.
//!
//! Model: the guest holds opaque integer buffer handles; the bytes live host-
//! side in this store. Guest calls arrive as
//! `dart:typed_data/ByteData.<op>` with a JSON argument array. This mirrors how
//! the Dart VM keeps the backing store native and hands the guest a view object.

use std::collections::HashMap;

use serde_json::{json, Value};

/// A typed-list view over a byte buffer (`Uint8List`, `Int32List`, `Float64List`
/// …) — an element-indexed window, exactly like Dart's typed list backed by a
/// `ByteBuffer`.
#[derive(Debug, Clone, Copy)]
struct View {
    buffer: u32,
    elem_size: usize,
    offset_bytes: usize,
    length_elems: usize,
    /// 0 = Uint8, 1 = Int32, 2 = Float64.
    kind: u8,
}

/// Host-side store of byte buffers, keyed by the handle the guest holds.
#[derive(Debug, Default)]
pub struct TypedDataStore {
    buffers: HashMap<u32, Vec<u8>>,
    views: HashMap<u32, View>,
    next_id: u32,
}

/// Result of a typed_data op: either a JSON reply for the guest, or a Dart error
/// message (e.g. `RangeError`) to surface as a thrown exception.
pub type OpResult = Result<Value, String>;

impl TypedDataStore {
    pub fn new() -> Self {
        TypedDataStore::default()
    }

    /// Number of live buffers — used by the runtime to account memory.
    pub fn total_bytes(&self) -> u64 {
        self.buffers.values().map(|b| b.len() as u64).sum()
    }

    fn alloc(&mut self, len: usize) -> u32 {
        let id = self.next_id;
        self.next_id += 1;
        self.buffers.insert(id, vec![0u8; len]);
        id
    }

    fn buf(&self, id: u32) -> Result<&Vec<u8>, String> {
        self.buffers
            .get(&id)
            .ok_or_else(|| format!("StateError: no ByteData for handle {id}"))
    }

    fn buf_mut(&mut self, id: u32) -> Result<&mut Vec<u8>, String> {
        self.buffers
            .get_mut(&id)
            .ok_or_else(|| format!("StateError: no ByteData for handle {id}"))
    }

    /// Dispatch a `ByteData.<method>` call. `method` is the segment after the
    /// `dart:typed_data/` prefix; `args` is the guest's JSON argument array.
    ///
    /// Supported (the load-bearing subset): `ByteData.alloc(len) -> handle`,
    /// `lengthInBytes(handle) -> int`, and get/set for `Uint8`, `Int32`, and
    /// `Float64` with an explicit little-endian flag (Dart's `Endian` argument).
    pub fn dispatch(&mut self, method: &str, args: &[Value]) -> OpResult {
        match method {
            "ByteData.alloc" => {
                let len = as_usize(args, 0)?;
                Ok(json!(self.alloc(len)))
            }
            "ByteData.lengthInBytes" => {
                let id = as_u32(args, 0)?;
                Ok(json!(self.buf(id)?.len()))
            }
            "ByteData.setUint8" => {
                let (id, off, v) = (as_u32(args, 0)?, as_usize(args, 1)?, as_i64(args, 2)?);
                let b = self.buf_mut(id)?;
                bounds(b.len(), off, 1)?;
                b[off] = v as u8;
                Ok(Value::Null)
            }
            "ByteData.getUint8" => {
                let (id, off) = (as_u32(args, 0)?, as_usize(args, 1)?);
                let b = self.buf(id)?;
                bounds(b.len(), off, 1)?;
                Ok(json!(b[off] as u64))
            }
            "ByteData.setInt32" => {
                let (id, off, v) = (as_u32(args, 0)?, as_usize(args, 1)?, as_i64(args, 2)?);
                let little = as_bool(args, 3);
                let bytes = (v as i32).to_le_bytes();
                let bytes = if little { bytes } else { swap4(bytes) };
                let b = self.buf_mut(id)?;
                bounds(b.len(), off, 4)?;
                b[off..off + 4].copy_from_slice(&bytes);
                Ok(Value::Null)
            }
            "ByteData.getInt32" => {
                let (id, off) = (as_u32(args, 0)?, as_usize(args, 1)?);
                let little = as_bool(args, 2);
                let b = self.buf(id)?;
                bounds(b.len(), off, 4)?;
                let mut raw = [0u8; 4];
                raw.copy_from_slice(&b[off..off + 4]);
                if !little {
                    raw = swap4(raw);
                }
                Ok(json!(i32::from_le_bytes(raw)))
            }
            "ByteData.setFloat64" => {
                let (id, off) = (as_u32(args, 0)?, as_usize(args, 1)?);
                let v = as_f64(args, 2)?;
                let little = as_bool(args, 3);
                let bytes = v.to_le_bytes();
                let bytes = if little { bytes } else { swap8(bytes) };
                let b = self.buf_mut(id)?;
                bounds(b.len(), off, 8)?;
                b[off..off + 8].copy_from_slice(&bytes);
                Ok(Value::Null)
            }
            "ByteData.getFloat64" => {
                let (id, off) = (as_u32(args, 0)?, as_usize(args, 1)?);
                let little = as_bool(args, 2);
                let b = self.buf(id)?;
                bounds(b.len(), off, 8)?;
                let mut raw = [0u8; 8];
                raw.copy_from_slice(&b[off..off + 8]);
                if !little {
                    raw = swap8(raw);
                }
                Ok(json!(f64::from_le_bytes(raw)))
            }
            "ByteData.setRange" => {
                // args: [dstHandle, start, end, srcHandle, srcStart]
                let dst = as_u32(args, 0)?;
                let start = as_usize(args, 1)?;
                let end = as_usize(args, 2)?;
                let src = as_u32(args, 3)?;
                let src_start = as_usize(args, 4)?;
                let count = end.saturating_sub(start);
                let src_bytes = {
                    let sb = self.buf(src)?;
                    if src_start + count > sb.len() {
                        return Err(format!(
                            "RangeError: source range {src_start}+{count} exceeds {}",
                            sb.len()
                        ));
                    }
                    sb[src_start..src_start + count].to_vec()
                };
                let db = self.buf_mut(dst)?;
                bounds(db.len(), start, count)?;
                db[start..start + count].copy_from_slice(&src_bytes);
                Ok(Value::Null)
            }

            // ---- Typed list views (Uint8List / Int32List / Float64List) ----
            "Uint8List.view" => self.make_view(args, 1, 0),
            "Int32List.view" => self.make_view(args, 4, 1),
            "Float64List.view" => self.make_view(args, 8, 2),
            "TypedList.length" => {
                let v = self.view(as_u32(args, 0)?)?;
                Ok(json!(v.length_elems))
            }
            "TypedList.getAt" => {
                let view = *self.view(as_u32(args, 0)?)?;
                let index = as_usize(args, 1)?;
                self.view_get(&view, index)
            }
            "TypedList.setAt" => {
                let view = *self.view(as_u32(args, 0)?)?;
                let index = as_usize(args, 1)?;
                let value = arg(args, 2)?.clone();
                self.view_set(&view, index, &value)
            }

            other => Err(format!("NoSuchMethodError: dart:typed_data/{other}")),
        }
    }

    /// Create a typed-list view: args `[bufferHandle, offsetBytes, lengthElems]`.
    fn make_view(&mut self, args: &[Value], elem_size: usize, kind: u8) -> OpResult {
        let buffer = as_u32(args, 0)?;
        let offset_bytes = as_usize(args, 1)?;
        let length_elems = as_usize(args, 2)?;
        let blen = self.buf(buffer)?.len();
        if offset_bytes + length_elems * elem_size > blen {
            return Err(format!(
                "RangeError: view {offset_bytes}+{length_elems}*{elem_size} exceeds buffer {blen}"
            ));
        }
        let id = self.next_id;
        self.next_id += 1;
        self.views.insert(
            id,
            View { buffer, elem_size, offset_bytes, length_elems, kind },
        );
        Ok(json!(id))
    }

    fn view(&self, id: u32) -> Result<&View, String> {
        self.views
            .get(&id)
            .ok_or_else(|| format!("StateError: no typed list for handle {id}"))
    }

    fn view_get(&self, v: &View, index: usize) -> OpResult {
        if index >= v.length_elems {
            return Err(format!("RangeError: index {index} for length {}", v.length_elems));
        }
        let off = v.offset_bytes + index * v.elem_size;
        let b = self.buf(v.buffer)?;
        match v.kind {
            0 => Ok(json!(b[off] as u64)),
            1 => {
                let mut raw = [0u8; 4];
                raw.copy_from_slice(&b[off..off + 4]);
                Ok(json!(i32::from_le_bytes(raw)))
            }
            2 => {
                let mut raw = [0u8; 8];
                raw.copy_from_slice(&b[off..off + 8]);
                Ok(json!(f64::from_le_bytes(raw)))
            }
            _ => Err("unknown view kind".into()),
        }
    }

    fn view_set(&mut self, v: &View, index: usize, value: &Value) -> OpResult {
        if index >= v.length_elems {
            return Err(format!("RangeError: index {index} for length {}", v.length_elems));
        }
        let off = v.offset_bytes + index * v.elem_size;
        let b = self.buf_mut(v.buffer)?;
        match v.kind {
            0 => {
                b[off] = value.as_i64().unwrap_or(0) as u8;
            }
            1 => {
                let bytes = (value.as_i64().unwrap_or(0) as i32).to_le_bytes();
                b[off..off + 4].copy_from_slice(&bytes);
            }
            2 => {
                let bytes = value.as_f64().unwrap_or(0.0).to_le_bytes();
                b[off..off + 8].copy_from_slice(&bytes);
            }
            _ => return Err("unknown view kind".into()),
        }
        Ok(Value::Null)
    }
}

fn bounds(len: usize, off: usize, width: usize) -> Result<(), String> {
    if off + width > len {
        Err(format!(
            "RangeError: offset {off}+{width} out of range for ByteData of {len} bytes"
        ))
    } else {
        Ok(())
    }
}

fn swap4(mut b: [u8; 4]) -> [u8; 4] {
    b.reverse();
    b
}

fn swap8(mut b: [u8; 8]) -> [u8; 8] {
    b.reverse();
    b
}

fn arg<'a>(args: &'a [Value], i: usize) -> Result<&'a Value, String> {
    args.get(i)
        .ok_or_else(|| format!("missing argument {i}"))
}

fn as_usize(args: &[Value], i: usize) -> Result<usize, String> {
    arg(args, i)?
        .as_u64()
        .map(|v| v as usize)
        .ok_or_else(|| format!("argument {i} is not a non-negative integer"))
}

fn as_u32(args: &[Value], i: usize) -> Result<u32, String> {
    arg(args, i)?
        .as_u64()
        .map(|v| v as u32)
        .ok_or_else(|| format!("argument {i} is not a handle"))
}

fn as_i64(args: &[Value], i: usize) -> Result<i64, String> {
    arg(args, i)?
        .as_i64()
        .ok_or_else(|| format!("argument {i} is not an integer"))
}

fn as_f64(args: &[Value], i: usize) -> Result<f64, String> {
    arg(args, i)?
        .as_f64()
        .ok_or_else(|| format!("argument {i} is not a number"))
}

fn as_bool(args: &[Value], i: usize) -> bool {
    args.get(i).and_then(|v| v.as_bool()).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn int32_roundtrips_little_endian() {
        let mut s = TypedDataStore::new();
        let h = s.dispatch("ByteData.alloc", &[json!(8)]).unwrap();
        let h = h.as_u64().unwrap() as i64;
        s.dispatch("ByteData.setInt32", &[json!(h), json!(0), json!(1234567), json!(true)])
            .unwrap();
        let got = s
            .dispatch("ByteData.getInt32", &[json!(h), json!(0), json!(true)])
            .unwrap();
        assert_eq!(got, json!(1234567));
    }

    #[test]
    fn endianness_is_honored() {
        let mut s = TypedDataStore::new();
        let h = s.dispatch("ByteData.alloc", &[json!(4)]).unwrap().as_u64().unwrap() as i64;
        s.dispatch("ByteData.setInt32", &[json!(h), json!(0), json!(1), json!(false)])
            .unwrap();
        // Big-endian 1 => bytes 00 00 00 01 => byte[3] == 1.
        let b3 = s
            .dispatch("ByteData.getUint8", &[json!(h), json!(3)])
            .unwrap();
        assert_eq!(b3, json!(1));
    }

    #[test]
    fn float64_roundtrips() {
        let mut s = TypedDataStore::new();
        let h = s.dispatch("ByteData.alloc", &[json!(8)]).unwrap().as_u64().unwrap() as i64;
        s.dispatch("ByteData.setFloat64", &[json!(h), json!(0), json!(3.5), json!(true)])
            .unwrap();
        let got = s
            .dispatch("ByteData.getFloat64", &[json!(h), json!(0), json!(true)])
            .unwrap();
        assert_eq!(got, json!(3.5));
    }

    #[test]
    fn int32list_view_indexes_elements() {
        let mut s = TypedDataStore::new();
        let buf = s.dispatch("ByteData.alloc", &[json!(16)]).unwrap().as_u64().unwrap() as i64;
        // Int32List view of 4 elements over the 16-byte buffer.
        let view = s
            .dispatch("Int32List.view", &[json!(buf), json!(0), json!(4)])
            .unwrap()
            .as_u64()
            .unwrap() as i64;
        s.dispatch("TypedList.setAt", &[json!(view), json!(2), json!(999)]).unwrap();
        let got = s.dispatch("TypedList.getAt", &[json!(view), json!(2)]).unwrap();
        assert_eq!(got, json!(999));
        assert_eq!(s.dispatch("TypedList.length", &[json!(view)]).unwrap(), json!(4));
        // Element 2 lives at byte offset 8; ByteData sees the same bytes.
        let via_bytedata = s.dispatch("ByteData.getInt32", &[json!(buf), json!(8), json!(true)]).unwrap();
        assert_eq!(via_bytedata, json!(999));
    }

    #[test]
    fn set_range_copies_bytes() {
        let mut s = TypedDataStore::new();
        let src = s.dispatch("ByteData.alloc", &[json!(4)]).unwrap().as_u64().unwrap() as i64;
        let dst = s.dispatch("ByteData.alloc", &[json!(4)]).unwrap().as_u64().unwrap() as i64;
        s.dispatch("ByteData.setInt32", &[json!(src), json!(0), json!(0x01020304), json!(true)]).unwrap();
        s.dispatch("ByteData.setRange", &[json!(dst), json!(0), json!(4), json!(src), json!(0)]).unwrap();
        let got = s.dispatch("ByteData.getInt32", &[json!(dst), json!(0), json!(true)]).unwrap();
        assert_eq!(got, json!(0x01020304));
    }

    #[test]
    fn out_of_range_is_a_range_error() {
        let mut s = TypedDataStore::new();
        let h = s.dispatch("ByteData.alloc", &[json!(2)]).unwrap().as_u64().unwrap() as i64;
        let err = s
            .dispatch("ByteData.setInt32", &[json!(h), json!(0), json!(1), json!(true)])
            .unwrap_err();
        assert!(err.contains("RangeError"), "got: {err}");
    }
}
