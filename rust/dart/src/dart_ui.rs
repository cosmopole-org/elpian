//! `dart:ui` — the canonical "group 3" wall library.
//!
//! In stock Flutter, `dart:ui` (`Canvas`, `Picture`, `Scene`, `SceneBuilder`,
//! `ParagraphBuilder`, `PlatformDispatcher`, …) is **not Dart source**: the
//! methods are native functions implemented in the C++ engine and bound into the
//! isolate via tonic/`Dart_SetNativeResolver`. That native binding is exactly
//! what a non-Dart VM cannot inherit for free, and is why "run the framework
//! kernel unchanged" is a native-integration problem, not a language problem.
//!
//! The way through — the one every shippable dynamic-Flutter system uses — is to
//! re-express the `dart:ui` surface as **host-bridge calls** that the embedder
//! services. The guest's `Canvas` calls are *recorded* into a serializable
//! display-list (a scene tree); `endRecording` hands that tree back, and the
//! real engine (native/AOT, iOS-legal) rasterizes it. The VM never generates
//! machine code, so there is no JIT and no App Store violation.
//!
//! This module implements a faithful slice of that: `PictureRecorder`/`Canvas`
//! recording a display-list of paint ops, returned as a JSON scene tree ready
//! for a native rasterizer (or the elpis protocol renderer) to consume.

use serde_json::{json, Value};

/// A single recorded paint operation — one node of the display list.
#[derive(Debug, Clone)]
struct PaintOp(Value);

/// Records `Canvas` operations into a display-list, mirroring the engine's
/// `PictureRecorder` → `Canvas` → `Picture` flow.
#[derive(Debug, Default)]
pub struct SceneRecorder {
    recording: bool,
    ops: Vec<PaintOp>,
    /// Completed pictures keyed by handle, awaiting composition into a scene.
    pictures: std::collections::HashMap<u32, Vec<Value>>,
    /// `Paint` objects (color / stroke width / style).
    paints: std::collections::HashMap<u32, Value>,
    /// `Path` objects — an accumulated list of sub-path verbs.
    paths: std::collections::HashMap<u32, Vec<Value>>,
    /// `SceneBuilder` layer stacks keyed by handle.
    scenes: std::collections::HashMap<u32, SceneBuilderState>,
    next_id: u32,
}

/// A `SceneBuilder` under construction: a stack of open layers and the finished
/// root children.
#[derive(Debug, Default, Clone)]
struct SceneBuilderState {
    stack: Vec<Value>,
    open: Vec<Value>,
}

pub type OpResult = Result<Value, String>;

impl SceneRecorder {
    pub fn new() -> Self {
        SceneRecorder::default()
    }

    /// Total recorded ops across live pictures — used for resource accounting.
    pub fn op_count(&self) -> u64 {
        self.pictures.values().map(|p| p.len() as u64).sum::<u64>() + self.ops.len() as u64
    }

    /// Dispatch a `dart:ui/<Class.method>` call. Supported slice:
    /// `PictureRecorder.beginRecording`, `Canvas.drawRect`, `Canvas.drawCircle`,
    /// `Canvas.drawParagraph`, and `PictureRecorder.endRecording` (returns a
    /// picture handle whose display-list can be fetched with `Picture.toScene`).
    pub fn dispatch(&mut self, method: &str, args: &[Value]) -> OpResult {
        match method {
            "PictureRecorder.beginRecording" => {
                if self.recording {
                    return Err("StateError: PictureRecorder already recording".into());
                }
                self.recording = true;
                self.ops.clear();
                Ok(Value::Null)
            }
            "Canvas.drawRect" => {
                self.require_recording()?;
                // args: [left, top, right, bottom, colorArgb]
                let r = rect(args)?;
                let color = as_u64(args, 4)?;
                self.ops.push(PaintOp(json!({
                    "op": "drawRect",
                    "rect": r,
                    "color": color,
                })));
                Ok(Value::Null)
            }
            "Canvas.drawCircle" => {
                self.require_recording()?;
                // args: [cx, cy, radius, colorArgb]
                let cx = as_f64(args, 0)?;
                let cy = as_f64(args, 1)?;
                let radius = as_f64(args, 2)?;
                let color = as_u64(args, 3)?;
                self.ops.push(PaintOp(json!({
                    "op": "drawCircle",
                    "center": [cx, cy],
                    "radius": radius,
                    "color": color,
                })));
                Ok(Value::Null)
            }
            "Canvas.drawParagraph" => {
                self.require_recording()?;
                // args: [text, x, y, fontSize, colorArgb]
                let text = as_str(args, 0)?;
                let x = as_f64(args, 1)?;
                let y = as_f64(args, 2)?;
                let size = as_f64(args, 3)?;
                let color = as_u64(args, 4)?;
                self.ops.push(PaintOp(json!({
                    "op": "drawParagraph",
                    "text": text,
                    "offset": [x, y],
                    "fontSize": size,
                    "color": color,
                })));
                Ok(Value::Null)
            }
            "PictureRecorder.endRecording" => {
                self.require_recording()?;
                let id = self.next_id;
                self.next_id += 1;
                let ops: Vec<Value> = self.ops.drain(..).map(|o| o.0).collect();
                self.pictures.insert(id, ops);
                self.recording = false;
                Ok(json!(id))
            }
            "Picture.toScene" => {
                let id = as_u32(args, 0)?;
                let ops = self
                    .pictures
                    .get(&id)
                    .ok_or_else(|| format!("StateError: no Picture for handle {id}"))?;
                Ok(json!({ "root": { "op": "picture", "ops": ops } }))
            }

            // ---- Paint ----
            "Paint.create" => {
                // args: [colorArgb, strokeWidth, style]  (style: 0 fill, 1 stroke)
                let color = as_u64(args, 0)?;
                let stroke_width = args.get(1).and_then(|v| v.as_f64()).unwrap_or(0.0);
                let style = args.get(2).and_then(|v| v.as_u64()).unwrap_or(0);
                let id = self.fresh_id();
                self.paints.insert(
                    id,
                    json!({ "color": color, "strokeWidth": stroke_width, "style": style }),
                );
                Ok(json!(id))
            }

            // ---- Transform / clip / layer stack ----
            "Canvas.save" => self.push_op(json!({ "op": "save" })),
            "Canvas.restore" => self.push_op(json!({ "op": "restore" })),
            "Canvas.translate" => {
                self.push_op(json!({ "op": "translate", "dx": as_f64(args, 0)?, "dy": as_f64(args, 1)? }))
            }
            "Canvas.scale" => {
                self.push_op(json!({ "op": "scale", "sx": as_f64(args, 0)?, "sy": as_f64(args, 1)? }))
            }
            "Canvas.rotate" => self.push_op(json!({ "op": "rotate", "radians": as_f64(args, 0)? })),
            "Canvas.clipRect" => {
                let r = rect(args)?;
                self.push_op(json!({ "op": "clipRect", "rect": r }))
            }

            // ---- Path ----
            "Path.create" => {
                let id = self.fresh_id();
                self.paths.insert(id, Vec::new());
                Ok(json!(id))
            }
            "Path.moveTo" => self.path_verb(args, "moveTo"),
            "Path.lineTo" => self.path_verb(args, "lineTo"),
            "Path.close" => {
                let id = as_u32(args, 0)?;
                self.path_mut(id)?.push(json!({ "verb": "close" }));
                Ok(Value::Null)
            }
            "Canvas.drawPath" => {
                self.require_recording()?;
                let path_id = as_u32(args, 0)?;
                let paint_id = as_u32(args, 1)?;
                let verbs = self.path(path_id)?.clone();
                let paint = self.paint(paint_id)?.clone();
                self.ops.push(PaintOp(json!({ "op": "drawPath", "path": verbs, "paint": paint })));
                Ok(Value::Null)
            }

            // ---- SceneBuilder ----
            "SceneBuilder.create" => {
                let id = self.fresh_id();
                self.scenes.insert(id, SceneBuilderState::default());
                Ok(json!(id))
            }
            "SceneBuilder.pushOffset" => {
                let id = as_u32(args, 0)?;
                let dx = as_f64(args, 1)?;
                let dy = as_f64(args, 2)?;
                let sb = self.scene_mut(id)?;
                sb.stack.push(json!({ "layer": "offset", "dx": dx, "dy": dy, "children": [] }));
                Ok(Value::Null)
            }
            "SceneBuilder.addPicture" => {
                let id = as_u32(args, 0)?;
                let dx = as_f64(args, 1)?;
                let dy = as_f64(args, 2)?;
                let pic_id = as_u32(args, 3)?;
                let ops = self
                    .pictures
                    .get(&pic_id)
                    .ok_or_else(|| format!("StateError: no Picture for handle {pic_id}"))?
                    .clone();
                let node = json!({ "layer": "picture", "dx": dx, "dy": dy, "ops": ops });
                self.scene_add_child(id, node)
            }
            "SceneBuilder.pop" => {
                let id = as_u32(args, 0)?;
                let sb = self.scene_mut(id)?;
                let layer = sb
                    .stack
                    .pop()
                    .ok_or_else(|| "StateError: SceneBuilder.pop with empty stack".to_string())?;
                self.scene_add_child(id, layer)
            }
            "SceneBuilder.build" => {
                let id = as_u32(args, 0)?;
                let sb = self.scene(id)?;
                if !sb.stack.is_empty() {
                    return Err("StateError: SceneBuilder.build with unbalanced push/pop".into());
                }
                Ok(json!({ "root": { "layer": "root", "children": sb.open } }))
            }

            other => Err(format!("NoSuchMethodError: dart:ui/{other}")),
        }
    }

    fn fresh_id(&mut self) -> u32 {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    fn push_op(&mut self, op: Value) -> OpResult {
        self.require_recording()?;
        self.ops.push(PaintOp(op));
        Ok(Value::Null)
    }

    fn path_verb(&mut self, args: &[Value], verb: &str) -> OpResult {
        let id = as_u32(args, 0)?;
        let x = as_f64(args, 1)?;
        let y = as_f64(args, 2)?;
        self.path_mut(id)?.push(json!({ "verb": verb, "x": x, "y": y }));
        Ok(Value::Null)
    }

    fn path(&self, id: u32) -> Result<&Vec<Value>, String> {
        self.paths.get(&id).ok_or_else(|| format!("StateError: no Path for handle {id}"))
    }
    fn path_mut(&mut self, id: u32) -> Result<&mut Vec<Value>, String> {
        self.paths.get_mut(&id).ok_or_else(|| format!("StateError: no Path for handle {id}"))
    }
    fn paint(&self, id: u32) -> Result<&Value, String> {
        self.paints.get(&id).ok_or_else(|| format!("StateError: no Paint for handle {id}"))
    }
    fn scene(&self, id: u32) -> Result<&SceneBuilderState, String> {
        self.scenes.get(&id).ok_or_else(|| format!("StateError: no SceneBuilder for handle {id}"))
    }
    fn scene_mut(&mut self, id: u32) -> Result<&mut SceneBuilderState, String> {
        self.scenes.get_mut(&id).ok_or_else(|| format!("StateError: no SceneBuilder for handle {id}"))
    }

    /// Attach a finished child to the currently-open layer, or to the root if no
    /// layer is open.
    fn scene_add_child(&mut self, id: u32, node: Value) -> OpResult {
        let sb = self.scene_mut(id)?;
        if let Some(top) = sb.stack.last_mut() {
            if let Some(children) = top.get_mut("children").and_then(|c| c.as_array_mut()) {
                children.push(node);
            }
        } else {
            sb.open.push(node);
        }
        Ok(Value::Null)
    }

    fn require_recording(&self) -> Result<(), String> {
        if self.recording {
            Ok(())
        } else {
            Err("StateError: Canvas op outside an active recording".into())
        }
    }
}

fn rect(args: &[Value]) -> Result<Value, String> {
    Ok(json!([
        as_f64(args, 0)?,
        as_f64(args, 1)?,
        as_f64(args, 2)?,
        as_f64(args, 3)?
    ]))
}

fn get<'a>(args: &'a [Value], i: usize) -> Result<&'a Value, String> {
    args.get(i).ok_or_else(|| format!("missing argument {i}"))
}

fn as_f64(args: &[Value], i: usize) -> Result<f64, String> {
    get(args, i)?
        .as_f64()
        .ok_or_else(|| format!("argument {i} is not a number"))
}

fn as_u64(args: &[Value], i: usize) -> Result<u64, String> {
    get(args, i)?
        .as_u64()
        .ok_or_else(|| format!("argument {i} is not a non-negative integer"))
}

fn as_u32(args: &[Value], i: usize) -> Result<u32, String> {
    as_u64(args, i).map(|v| v as u32)
}

fn as_str(args: &[Value], i: usize) -> Result<String, String> {
    get(args, i)?
        .as_str()
        .map(|s| s.to_string())
        .ok_or_else(|| format!("argument {i} is not a string"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_and_composes_a_scene() {
        let mut r = SceneRecorder::new();
        r.dispatch("PictureRecorder.beginRecording", &[]).unwrap();
        r.dispatch(
            "Canvas.drawRect",
            &[json!(0.0), json!(0.0), json!(100.0), json!(50.0), json!(4294901760u64)],
        )
        .unwrap();
        r.dispatch(
            "Canvas.drawCircle",
            &[json!(50.0), json!(25.0), json!(10.0), json!(4278190335u64)],
        )
        .unwrap();
        let pic = r.dispatch("PictureRecorder.endRecording", &[]).unwrap();
        let pic_id = pic.as_u64().unwrap() as i64;
        let scene = r.dispatch("Picture.toScene", &[json!(pic_id)]).unwrap();
        let ops = &scene["root"]["ops"];
        assert_eq!(ops.as_array().unwrap().len(), 2);
        assert_eq!(ops[0]["op"], "drawRect");
        assert_eq!(ops[1]["op"], "drawCircle");
    }

    #[test]
    fn path_and_paint_compose_a_drawpath_op() {
        let mut r = SceneRecorder::new();
        let paint = r
            .dispatch("Paint.create", &[json!(4278190335u64), json!(2.0), json!(1)])
            .unwrap()
            .as_u64()
            .unwrap() as i64;
        let path = r.dispatch("Path.create", &[]).unwrap().as_u64().unwrap() as i64;
        r.dispatch("Path.moveTo", &[json!(path), json!(0.0), json!(0.0)]).unwrap();
        r.dispatch("Path.lineTo", &[json!(path), json!(10.0), json!(10.0)]).unwrap();
        r.dispatch("Path.close", &[json!(path)]).unwrap();
        r.dispatch("PictureRecorder.beginRecording", &[]).unwrap();
        r.dispatch("Canvas.drawPath", &[json!(path), json!(paint)]).unwrap();
        let pic = r.dispatch("PictureRecorder.endRecording", &[]).unwrap().as_u64().unwrap() as i64;
        let scene = r.dispatch("Picture.toScene", &[json!(pic)]).unwrap();
        let op = &scene["root"]["ops"][0];
        assert_eq!(op["op"], "drawPath");
        assert_eq!(op["paint"]["style"], 1);
        assert_eq!(op["path"].as_array().unwrap().len(), 3);
    }

    #[test]
    fn scene_builder_composes_layers() {
        let mut r = SceneRecorder::new();
        // Record a picture first.
        r.dispatch("PictureRecorder.beginRecording", &[]).unwrap();
        r.dispatch("Canvas.drawRect", &[json!(0.0), json!(0.0), json!(1.0), json!(1.0), json!(1)]).unwrap();
        let pic = r.dispatch("PictureRecorder.endRecording", &[]).unwrap().as_u64().unwrap() as i64;
        // Build a scene with one offset layer containing the picture.
        let sb = r.dispatch("SceneBuilder.create", &[]).unwrap().as_u64().unwrap() as i64;
        r.dispatch("SceneBuilder.pushOffset", &[json!(sb), json!(5.0), json!(6.0)]).unwrap();
        r.dispatch("SceneBuilder.addPicture", &[json!(sb), json!(0.0), json!(0.0), json!(pic)]).unwrap();
        r.dispatch("SceneBuilder.pop", &[json!(sb)]).unwrap();
        let scene = r.dispatch("SceneBuilder.build", &[json!(sb)]).unwrap();
        let root = &scene["root"];
        assert_eq!(root["children"][0]["layer"], "offset");
        assert_eq!(root["children"][0]["children"][0]["layer"], "picture");
    }

    #[test]
    fn canvas_op_outside_recording_is_a_state_error() {
        let mut r = SceneRecorder::new();
        let err = r
            .dispatch("Canvas.drawRect", &[json!(0.0), json!(0.0), json!(1.0), json!(1.0), json!(0)])
            .unwrap_err();
        assert!(err.contains("StateError"), "got: {err}");
    }
}
