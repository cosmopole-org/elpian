//! # elpian-agent
//!
//! Agents for Elpian fullstack mini apps. An app declares agents in its
//! manifest — instructions, skills, and the app's own server functions as
//! tools — and they act as (part of) the app's backend, producing UI as A2UI
//! v0.9.1 messages that every Elpian host renders with its own renderer.
//!
//! * [`manifest`] — the `agents` / `providers` manifest sections, validated.
//! * [`skills`] — `agents/skills/<name>/SKILL.md`, loaded on demand.
//! * [`prompt`] — the byte-stable system prompt.
//! * [`a2ui`] — the vendored schemas and the validator built on them.
//! * [`provider`] — Anthropic (default), OpenAI-compatible, and scripted.
//! * [`agent`] — building an app's agents, and the tool loop.
//! * [`conversation`] — append-only histories and their surfaces.
//!
//! The crate knows nothing about the host: function tools run through the
//! [`agent::FunctionRunner`] the host supplies, which is how they get the
//! caller's identity, quota and capabilities.

pub mod a2ui;
pub mod agent;
pub mod conversation;
pub mod manifest;
pub mod prompt;
pub mod provider;
pub mod skills;

pub use agent::{
    run_turn, Agent, AppAgents, FunctionInfo, FunctionRunner, TurnContext, TurnInput, TurnSummary,
};
pub use conversation::{Conversation, ConversationStore};
pub use manifest::{AgentSpec, AgentsConfig};
