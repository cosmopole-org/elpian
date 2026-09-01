//! The framework binding protocol: host → guest events and the frame pipeline.
//!
//! In stock Flutter the engine drives the framework by calling `dart:ui`
//! callbacks — `PlatformDispatcher.onPointerDataPacket`, `onBeginFrame`,
//! `onDrawFrame`, lifecycle and text-input channels. On Elpian those same
//! signals are delivered to the guest as calls to well-known handler functions,
//! and the guest hands back a scene tree (built with the `dart:ui` recorder)
//! that the native, AOT rasterizer paints.
//!
//! This module defines the serializable event types; the runtime
//! ([`crate::runtime::DartRuntime`]) delivers them to the guest and collects the
//! rendered frame.

use serde_json::{json, Value};

/// Guest handler names the runtime invokes (defined by the app or generated
/// Dart glue). Missing handlers are a harmless no-op, like an undefined
/// `onEvent`.
pub mod handlers {
    pub const POINTER: &str = "onPointerEvent";
    pub const LIFECYCLE: &str = "onAppLifecycleStateChanged";
    pub const TEXT_INPUT: &str = "onTextInput";
    pub const BEGIN_FRAME: &str = "onBeginFrame";
    pub const DRAW_FRAME: &str = "onDrawFrame";
}

/// The `dart:ui` host call the guest makes to submit its built scene for the
/// current frame.
pub const RENDER_METHOD: &str = "FlutterView.render";

/// Pointer lifecycle phase, mirroring `PointerChange`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PointerPhase {
    Down,
    Move,
    Up,
    Cancel,
}

impl PointerPhase {
    fn as_str(self) -> &'static str {
        match self {
            PointerPhase::Down => "down",
            PointerPhase::Move => "move",
            PointerPhase::Up => "up",
            PointerPhase::Cancel => "cancel",
        }
    }
}

/// A pointer (touch/mouse) event delivered to the guest.
#[derive(Debug, Clone, Copy)]
pub struct PointerEvent {
    pub pointer: i64,
    pub phase: PointerPhase,
    pub x: f64,
    pub y: f64,
}

impl PointerEvent {
    pub fn to_json(self) -> Value {
        json!({
            "pointer": self.pointer,
            "phase": self.phase.as_str(),
            "x": self.x,
            "y": self.y,
        })
    }
}

/// App lifecycle state, mirroring `AppLifecycleState`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AppLifecycleState {
    Resumed,
    Inactive,
    Paused,
    Detached,
}

impl AppLifecycleState {
    pub fn as_str(self) -> &'static str {
        match self {
            AppLifecycleState::Resumed => "resumed",
            AppLifecycleState::Inactive => "inactive",
            AppLifecycleState::Paused => "paused",
            AppLifecycleState::Detached => "detached",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pointer_event_serializes() {
        let ev = PointerEvent { pointer: 1, phase: PointerPhase::Down, x: 12.0, y: 34.0 };
        let j = ev.to_json();
        assert_eq!(j["phase"], "down");
        assert_eq!(j["x"], 12.0);
    }

    #[test]
    fn lifecycle_names_match_flutter() {
        assert_eq!(AppLifecycleState::Resumed.as_str(), "resumed");
        assert_eq!(AppLifecycleState::Paused.as_str(), "paused");
    }
}
