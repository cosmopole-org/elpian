# 24 — Agentic UI: agents as the backend, A2UI as the UI

A fullstack mini app can put **agents** where server functions would be: an LLM
with your instructions, your skills and your server functions as tools. It
answers in **[A2UI](https://a2ui.org/)** (v0.9.1), a declarative UI format.
Every Elpian host renders A2UI with Elpian's own renderer, so agent-made UI
looks and behaves like the rest of the app. It can sit right next to static
Elpian UI:

```text
 device (any Elpian host)                 host (elpiand)                       model provider
 ┌──────────────────────────────┐        ┌───────────────────────────────┐    ┌──────────────┐
 │ static Elpian UI (client VM) │        │ POST /apps/<app>/agent/<name> │    │ Claude       │
 │ ┌──────────────────────────┐ │  JSON  │  agent loop ── Messages API ──┼───►│ (default)    │
 │ │ A2UISurface              │─┼───────►│   tools: a2ui_send            │    │ or OpenAI-   │
 │ │  ↳ A2UI processor        │ │ NDJSON │          load_skill           │    │ compatible   │
 │ │  ↳ lowered to Elpian     │◄┼────────┤          fn_<your function> ──┼─┐  └──────────────┘
 │ │    widgets               │ │        │  A2UI validated vs. the spec  │ │
 │ └──────────────────────────┘ │        └───────────────────────────────┘ │
 │ static Elpian UI             │          your server functions (VMs) ◄───┘
 └──────────────────────────────┘
```

The three modes compose freely:

- **Static.** Server functions and client code, as in [chapter 18](18-fullstack.md).
- **Agentic.** An agent is the whole backend; the client is one `agent` session.
- **Mixed.** Static client UI embeds `A2UISurface` widgets, and the agent calls
  your static server functions as tools.

## 1. Try it

```sh
elpian create shop --template agentic          # add --renderer native for the DOM host
cd shop && elpian run install
ELPIAN_AGENT_PROVIDER=scripted elpian run dev  # offline: replays agents/scripted.json
ANTHROPIC_API_KEY=sk-ant-... elpian run dev    # the real agent on Claude
```

The template has:

- an `assistant` agent with instructions and two skills;
- a `listProducts` server function that the agent uses as a tool;
- a client that renders a static header and footer around an `A2UISurface`.

`scripts/e2e-agentic.mjs` runs exactly this in Chromium. It is part of CI.

## 2. Declaring agents

In `elpian.app.json`, next to `functions`:

```jsonc
{
  "id": "shop",
  "capabilities": ["render", "server_call", "agents", "state", "logging"],
  "secrets": ["ANTHROPIC_API_KEY"],
  "functions": [
    { "name": "listProducts", "kind": "action",
      "description": "List the shop's products, optionally filtered by category.",
      "params": { "type": "object", "properties": { "category": { "enum": ["tea", "coffee"] } } } }
  ],
  "agents": [
    {
      "name": "assistant",
      "description": "Helps customers find and order products.",
      "instructions": "agents/assistant.md",  // a bundle file (.md/.txt) or inline text
      "skills": ["catalog", "ordering"],     // agents/skills/<name>/SKILL.md
      "tools": ["listProducts"],             // your own functions — must exist in `functions`
      "provider": "anthropic",               // anthropic (default) | openai | scripted
      "model": "claude-opus-5-5",            // the anthropic default
      "effort": "medium",                    // low | medium | high | xhigh | max
      "maxTurns": 16,                        // tool-loop iterations per request
      "maxOutputTokens": 64000
    }
  ],
  "providers": {                             // optional
    "anthropic": { "secret": "ANTHROPIC_API_KEY" },
    "openai": { "secret": "OPENAI_API_KEY", "baseUrl": "https://…/v1", "model": "…" }
  }
}
```

The manifest is validated when the app is built, packaged and loaded. Each of
these is an error before anything is served:

- a tool that isn't a declared function;
- a skill with no `SKILL.md`;
- a missing instructions file;
- a provider whose key isn't a declared secret;
- an `openai` agent with no `model`;
- a catalog other than the basic one.

A function's `description` and `params` (a JSON Schema) become its tool
definition. Write them for the model.

### Skills

A skill is a directory, `agents/skills/<name>/`, with a `SKILL.md` file:

```markdown
---
name: ordering
description: Handle an "order" action from a product list.
---

An `order` action arrives as `{"a2uiAction": {"name": "order", "context": {"id", "name"}}}`.
Confirm in one short sentence, and show the confirmation in a surface `order` …
```

The system prompt lists each skill's `name` and `description`. The model loads
the body with the `load_skill` tool when it needs it. The directory can also
hold `examples/*.json`: arrays of A2UI messages that are shown with the body.
Keep instructions short and put the know-how in skills, so the prompt stays
small and stable (it is prompt-cached).

## 3. What the agent can do

The model gets three kinds of tool:

| Tool | Does |
|---|---|
| `a2ui_send` `{messages: [...]}` | Sends A2UI messages (`createSurface`, `updateComponents`, `updateDataModel`, `deleteSurface`) to the device. Each batch is checked against the vendored v0.9.1 JSON Schemas and the basic catalog. It is also checked for structure: unique ids, a single `root`, no dangling or cyclic references, known functions, and surface lifecycle. Only valid messages are streamed. Errors go back to the model as `VALIDATION_FAILED` results so it can fix them. |
| `load_skill` `{name}` | Returns a skill's body and examples. |
| `fn_<name>` | Calls one of your declared server functions through the normal invoke path: same caller identity, capabilities, limits, quota and network posture. This is how static Elpian logic and agents mix. |

The system prompt contains:

- your instructions;
- the A2UI rules;
- the basic catalog, with its components (Text, Image, Icon, Video,
  AudioPlayer, Row, Column, List, Card, Tabs, Modal, Divider, Button,
  TextField, CheckBox, ChoicePicker, Slider, DateTimeInput) and functions;
- the skill index.

It is byte-stable, so the provider caches it.

### The Claude request

Elpian calls the Anthropic Messages API directly over HTTPS
(`rust/crates/elpian-agent`, `ureq` + rustls). Each request:

- streams;
- sets `output_config.effort`;
- does not send `thinking` (current models think adaptively);
- leaves `tool_choice` on auto;
- streams tool inputs eagerly and validates every one before it runs;
- prompt-caches the stable prefix.

For the current Opus, Sonnet and Fable models it opts into server-side refusal
fallbacks (`fallbacks: "default"`). Conversation history is kept append-only,
and thinking blocks are echoed back unchanged.

When a response stops, Elpian handles the stop reason:

- **`refusal`**: the partial output is discarded and the client gets an error
  frame.
- **`max_tokens`**: reported.
- **429 and 5xx**: retried with backoff.

## 4. The wire: `POST /apps/<app>/agent/<agent>`

Request body:

```jsonc
{ "conversationId": "c_…",       // optional — omitted on the first turn
  "message": "Show me tea",      // and/or
  "action": { "name": "order", "surfaceId": "products", "sourceComponentId": "order",
              "timestamp": "2026-10-09T16:17:12.571Z", "context": { "id": "assam" } },
  "dataModel": { "surfaces": { "products": { … } } },   // when a surface has sendDataModel
  "capabilities": { "supportedCatalogIds": [ "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json" ] } }
```

Some requests are refused before the stream starts:

| Status | When |
|---|---|
| 400 | Bad body |
| 404 | Unknown app or agent |
| 409 | A turn is already running in this conversation |
| 429 | Over quota |
| 503 | No provider key; the detail goes to the operator log only |

Otherwise the response is `application/x-ndjson`, one JSON object per line,
in this order:

1. `{"type":"conversation","conversationId":"…"}`, always first.
2. A2UI messages, verbatim, e.g. `{"version":"v0.9.1","createSurface":{…}}`.
3. `{"type":"text","text":"…"}`: the agent's prose.
4. `{"type":"status","state":"working"|"tool","tool":"fn_listProducts"}`.
5. `{"type":"error","message":"…"}`.
6. `{"type":"done","stopReason":"end_turn"|"max_turns"|"max_tokens"|"refusal"|"error"}`, always last.

An action reaches the model as the next user turn,
`{"a2uiAction": …, "dataModel": …}`. Only surfaces this conversation created
are accepted in the client's data model. `GET /apps/<app>/manifest.json` lists
each agent's `name` and `description`, and never its instructions or skills.

## 5. Showing agent UI in a client

Every host has the same three entry points.

**The `A2UISurface` widget** (also written `a2ui-surface` in HTML) works in
static UI on every host:

```ts
import { el, a2uiSurface, agentSend } from '@elpian/sdk';

el('div', {}, [
  el('h1', { text: 'Tea & Coffee' }, []),
  a2uiSurface({ agent: 'assistant', prompt: 'Show me what you have.', chat: true, showText: true }),
]);
```

| Prop | Meaning |
|---|---|
| `agent` | The agent's name |
| `prompt` | First message, sent when the widget mounts |
| `conversation` | A key; widgets with the same key share one conversation (default `agent:<agent>`) |
| `surfaceId` | Show only this surface (default: all, in creation order) |
| `showText` | Show the agent's prose |
| `chat` | Add an input row for messaging the agent |
| `showAttribution` | Show the surface theme's `agentDisplayName` |
| `app`, `baseUrl` | Another app or server (default: this app on its host) |
| `messages` | Render a fixed list of A2UI messages with no agent (offline and tests) |

The widget emits these events: `a2uiAction`, `a2uiText`, `a2uiError` and
`a2uiDone`.

**The `agent` session kind** renders a full-screen agent app: every surface,
the prose and a chat row. It takes the options `baseUrl`, `appId`, `agent`,
`conversationId`, `prompt`, `chat` and `stylesheet`, and has the methods
`send` and `action`.

- Kotlin: `ElpianHostView.open("agent", options)`
- Swift: `ElpianHostView.open(kind: "agent", …)`
- Web: `mountElpian(el, 'agent', options)`
- Expo: `<ElpianView kind="agent" …>`
- Flutter: `ElpianAgentView`

**Host APIs for guest code** need the `agents` capability:

- `agent.send {agent, conversation?, message}` returns `{conversationId}`.
- `agent.action {agent, conversation?, action}`.
- `a2ui.dataModel {conversation, surfaceId}` returns the surface's current
  data model.

The SDK wraps them as `agentSend`, `agentAction` and `a2uiDataModel`.

### Elpian's A2UI renderer

Each engine has one: web `native/web/src/a2ui`, Flutter
`flutter/lib/src/a2ui`, Android `…/dev/elpian/core/a2ui`, iOS
`Sources/ElpianCore/A2UI`. Each one:

- processes the v0.9.1 messages (buffering until `root` exists, JSON-Pointer
  data model, templates with relative paths);
- evaluates dynamic values and the basic catalog's functions (`formatString`,
  `formatNumber`, `formatCurrency`, `formatDate`, `pluralize`, `regex`,
  `email`, `length`, `numeric`, `required`, `openUrl`, `and`, `or`, `not`);
- runs checks, which disable buttons and show field errors;
- turns `action.event` into the client→server action, with
  `sendDataModel` support;
- lowers each component onto Elpian's widgets, with two-way input binding and
  stateful Tabs and Modals.

They are tested against the vendored A2UI conformance cases and all 43 example
surfaces of the basic catalog ([`a2ui/`](../a2ui/README.md)). Elpian
deliberately doesn't use the official A2UI renderer libraries:

- there is no official Android renderer;
- its own renderer lets agent UI mix with Elpian UI and look the same on every
  host.

## 6. Governance

- **Keys stay on the host.** A provider key must be a declared app secret, or
  come from the environment under `elpian run dev` / `elpiand --dev`. It is
  never sent to clients.
- **Agents only reach your declared tools.** An agent can call only the
  functions listed in its `tools`. Each call goes through the same quota,
  capability and network checks as a client calling it.
- **Each agent request is one invocation**, counted against the app's quota.
  Token usage is logged, not metered.
- **The provider call is the host's, not the guest's.** It works even for a
  `network: "closed"` app, because it isn't guest egress.
- **Conversations live in host memory.** They expire after 30 minutes idle,
  and only one turn can run per conversation at a time.

## 7. Differences and limits

- **Only the basic catalog.** Custom catalogs are not supported yet.
- **Streaming granularity.** A2UI messages stream when the model's
  `a2ui_send` call completes, not token by token.
- **Renderer choices** (the same on every host):
  - Images default to `cover` (`contain` for the `icon` variant).
  - A Modal covers its surface rather than the whole screen.
  - Field errors show after the user touches the field.
- **Dev-only providers.** The scripted provider (`ELPIAN_AGENT_PROVIDER=scripted`,
  `ELPIAN_AGENT_SCRIPT`) is for tests and offline development.
