# A2UI (vendored)

The A2UI protocol v0.9.1 — the format Elpian's agentic mini apps use for
agent-generated UI — copied from [google/A2UI](https://github.com/google/A2UI)
at commit `03b77ae95a12f5040754f8cc48a8fa9ab761c377`, under the Apache License 2.0 (see `LICENSE`). Unmodified.

| Path | What |
|---|---|
| `spec/json/` | Message, common-type and capability JSON schemas |
| `spec/catalogs/basic/` | The basic component catalog (`catalog.json`), its rules and 43 example surfaces |
| `spec/docs/` | Protocol, basic-catalog implementation guide, custom functions, extensions |
| `spec/test/` | The schema test cases |
| `conformance/` | Language-agnostic renderer conformance cases (data model, node resolution, expressions, actions, validation) |

Elpian implements A2UI in each of its engines — Flutter (`flutter/lib/src/a2ui`),
web (`native/web/src/a2ui`), Android (`native/android/elpian-core/.../a2ui`)
and iOS (`native/ios/Sources/ElpianCore/A2UI`) — and the agent runtime in
`rust/crates/elpian-agent`. Every implementation is tested against these files.
See [wiki/24-agentic-ui.md](../wiki/24-agentic-ui.md).
