/**
 * A2UI inside Elpian: the `A2UISurface` widget (also `a2ui-surface`), the
 * per-app conversation registry it and the host APIs share, and the guest
 * host APIs `agent.send`, `agent.action` and `a2ui.dataModel`.
 *
 * Widget props:
 *   agent         agent name (`/apps/<app>/agent/<agent>`)
 *   app           app id (default: the registry's — the current app)
 *   baseUrl       server base URL (default: the registry's / the session's)
 *   conversation  conversation key; widgets with the same key share one
 *                 conversation (default `agent:<agent>`)
 *   prompt        first message, sent once when the conversation is new
 *   surfaceId     render only this surface (default: all, in creation order)
 *   showText      render the agent's prose
 *   chat          add an input row to message the agent
 *   messages      static A2UI messages to render without an agent
 * Events (dispatched to the node's `events` handlers):
 *   a2uiAction  {name, surfaceId, sourceComponentId, timestamp, context}
 *   a2uiText    {text}
 *   a2uiError   {message}
 *   a2uiDone    {stopReason, conversationId}
 */
import type { ElpianEngine, ElpianServices } from '../engine/engine.js';
import { makeEvent, type ElpianEvent } from '../events/events.js';
import { nodeFromJson, type ElpianNode } from '../model/node.js';
import type { W } from '../render/object.js';
import { isMap, normalizedArgs, stableKey, type JsonMap } from '../util/json.js';
import { makeResponse, NULL_RESPONSE } from '../util/typed.js';
import type { BuildContext, WidgetBuilder } from '../widgets/context.js';
import { A2UIConversation, type A2UIConversationEvent } from './conversation.js';
import { lowerSurface, paletteFor } from './lowering.js';
import type { AgentEndpoint } from './transport.js';

/** The guest host APIs this module serves. */
export const AGENT_API_NAMES: ReadonlySet<string> = new Set(['agent.send', 'agent.action', 'a2ui.dataModel']);

/** Where agents are reached when a widget or host call does not say. */
export interface A2UIDefaults {
  baseUrl?: string | null;
  appId?: string | null;
  headers?: Record<string, string>;
}

interface Binding {
  engine: ElpianEngine;
  node: ElpianNode;
  conversation: A2UIConversation;
  unsubscribe: () => void;
}

/** Conversations of one app (one ElpianServices), keyed by conversation key. */
export class A2UIRegistry {
  defaults: A2UIDefaults = {};
  private readonly conversations = new Map<string, A2UIConversation>();
  private readonly engines = new Set<ElpianEngine>();
  private readonly bindings = new Map<string, Binding>();

  /** The conversation under [key], created by [create] when new. */
  conversation(key: string, create: () => A2UIConversation): A2UIConversation {
    let c = this.conversations.get(key);
    if (!c) {
      c = create();
      this.conversations.set(key, c);
      c.on((e) => {
        if (e.type === 'changed') this.invalidate();
      });
    }
    return c;
  }

  get(key: string): A2UIConversation | undefined {
    return this.conversations.get(key);
  }

  keys(): string[] {
    return [...this.conversations.keys()];
  }

  /** An endpoint for [agent] from the defaults (and overrides), or null without a base URL / app. */
  endpoint(agent: string, overrides: { baseUrl?: unknown; appId?: unknown } = {}): AgentEndpoint | null {
    const baseUrl = typeof overrides.baseUrl === 'string' && overrides.baseUrl ? overrides.baseUrl : this.defaults.baseUrl ?? null;
    const appId = typeof overrides.appId === 'string' && overrides.appId ? overrides.appId : this.defaults.appId ?? null;
    if (!agent || baseUrl == null || appId == null) return null;
    return { baseUrl, appId, agent, headers: this.defaults.headers };
  }

  /** An engine renders this registry's conversations. */
  attach(engine: ElpianEngine): void {
    this.engines.add(engine);
  }

  /** Every attached engine renders again. */
  invalidate(): void {
    for (const e of this.engines) e.host.invalidate?.();
  }

  /** Route [conversation]'s events to the widget rendered as [elementId]. */
  bind(elementId: string, engine: ElpianEngine, node: ElpianNode, conversation: A2UIConversation): void {
    const existing = this.bindings.get(elementId);
    if (existing && existing.conversation === conversation) {
      existing.node = node;
      existing.engine = engine;
      return;
    }
    existing?.unsubscribe();
    const binding: Binding = { engine, node, conversation, unsubscribe: () => {} };
    binding.unsubscribe = conversation.on((e) => this.deliver(elementId, binding, e));
    this.bindings.set(elementId, binding);
  }

  private deliver(elementId: string, b: Binding, e: A2UIConversationEvent): void {
    let type: string;
    let payload: unknown;
    switch (e.type) {
      case 'action':
        type = 'a2uiAction';
        payload = e.action;
        break;
      case 'text':
        if (e.role !== 'agent') return;
        type = 'a2uiText';
        payload = { text: e.text };
        break;
      case 'error':
        type = 'a2uiError';
        payload = { message: e.message };
        break;
      case 'done':
        type = 'a2uiDone';
        payload = { stopReason: e.stopReason, conversationId: e.conversationId };
        break;
      default:
        return;
    }
    const events = b.node.events ?? {};
    const name = Object.keys(events).find((k) => k.toLowerCase() === type.toLowerCase());
    if (!name) return;
    const dispatcher = b.engine.services.events;
    if (!dispatcher.getNode(elementId)) {
      // The widget is no longer rendered.
      b.unsubscribe();
      this.bindings.delete(elementId);
      return;
    }
    const event: ElpianEvent = makeEvent(name, 'custom', elementId, { data: isMap(payload) ? payload : { value: payload }, value: payload });
    dispatcher.dispatchEvent(event, elementId);
  }

  dispose(): void {
    for (const b of this.bindings.values()) b.unsubscribe();
    this.bindings.clear();
    for (const c of this.conversations.values()) c.dispose();
    this.conversations.clear();
    this.engines.clear();
  }
}

const registries = new WeakMap<ElpianServices, A2UIRegistry>();

/** The A2UI registry of an app's services (created on first use). */
export function a2uiRegistry(services: ElpianServices): A2UIRegistry {
  let r = registries.get(services);
  if (!r) {
    r = new A2UIRegistry();
    registries.set(services, r);
  }
  return r;
}

function conversationKey(props: JsonMap, elementId: string): string {
  if (typeof props.conversation === 'string' && props.conversation) return props.conversation;
  if (Array.isArray(props.messages)) return `static:${elementId}`;
  return `agent:${typeof props.agent === 'string' ? props.agent : ''}`;
}

type Node = Record<string, any>;

function chatParts(conversation: A2UIConversation, props: JsonMap, key: string, invalidate: () => void): Node[] {
  const parts: Node[] = [];
  const palette = paletteFor({});
  if (props.showText === true) {
    conversation.transcript.forEach((t, i) => {
      const mine = t.role === 'user';
      parts.push({
        type: 'Row',
        key: `${key}/t${i}`,
        props: { style: { justifyContent: mine ? 'flex-end' : 'flex-start' } },
        children: [
          {
            type: 'Flexible',
            props: { flex: 1, fit: 'loose' },
            children: [
              {
                type: 'Container',
                props: { style: { padding: '8 12', margin: 4, borderRadius: 16, backgroundColor: mine ? palette.primaryContainer : palette.surfaceContainer } },
                children: [{ type: 'Text', props: { text: t.text, style: { fontSize: 15, lineHeight: 1.45, color: palette.onSurface } } }],
              },
            ],
          },
        ],
      });
    });
  }
  if (conversation.busy) {
    parts.push({ type: 'LinearProgressIndicator', key: `${key}/busy`, props: { style: { color: palette.primary, margin: '4 0' } } });
  }
  if (props.chat === true) {
    const draftKey = `${key}#draft`;
    const draft = conversation.ui.get(draftKey, '');
    const submit = () => {
      const text = conversation.ui.get(draftKey, '').trim();
      if (!text || !conversation.endpoint) return;
      conversation.ui.set(draftKey, '');
      conversation.send(text);
      invalidate();
    };
    parts.push({
      type: 'Row',
      key: `${key}/chat`,
      props: { style: { alignItems: 'center', margin: '8 0 0 0' } },
      children: [
        {
          type: 'Expanded',
          props: { flex: 1 },
          children: [
            {
              type: 'TextField',
              key: `${key}/chat/input`,
              props: { value: draft, hint: 'Message the agent', style: { color: palette.onSurface, margin: '0 8 0 4' } },
              events: {
                input: (e: any) => {
                  e.propagationStopped = true;
                  conversation.ui.set(draftKey, String(e?.value ?? ''));
                },
                submit: (e: any) => {
                  e.propagationStopped = true;
                  submit();
                },
              },
            },
          ],
        },
        {
          type: 'Button',
          key: `${key}/chat/send`,
          props: { text: 'Send', disabled: conversation.busy, style: { backgroundColor: palette.primary, color: palette.onPrimary } },
          events: {
            click: (e: any) => {
              e.propagationStopped = true;
              submit();
            },
          },
          children: [{ type: 'Icon', props: { icon: 'send', size: 20, style: { color: palette.onPrimary } } }],
        },
      ],
    });
  }
  return parts;
}

/** Build the Elpian node tree an `A2UISurface` element shows (exported for previews and tests). */
export function a2uiSurfaceTree(engine: ElpianEngine, props: JsonMap, elementId: string, node: ElpianNode | null = null): Node {
  const registry = a2uiRegistry(engine.services);
  registry.attach(engine);
  const agent = typeof props.agent === 'string' ? props.agent : '';
  const key = conversationKey(props, elementId);
  const conversation = registry.conversation(
    key,
    () =>
      new A2UIConversation({
        endpoint: Array.isArray(props.messages) ? null : registry.endpoint(agent, { baseUrl: props.baseUrl, appId: props.app }),
        conversationId: typeof props.conversationId === 'string' ? props.conversationId : null,
      }),
  );
  if (!conversation.endpoint && agent && !Array.isArray(props.messages)) {
    conversation.endpoint = registry.endpoint(agent, { baseUrl: props.baseUrl, appId: props.app });
  }
  if (Array.isArray(props.messages)) conversation.syncStatic(props.messages, stableKey(props.messages));
  if (node) registry.bind(elementId, engine, node, conversation);
  if (typeof props.prompt === 'string' && props.prompt && !conversation.prompted && conversation.endpoint) {
    conversation.prompted = true;
    const prompt = props.prompt;
    // Not during a build: the turn emits events.
    void Promise.resolve().then(() => conversation.send(prompt));
  }
  const invalidate = () => registry.invalidate();
  const hooks = conversation.loweringHooks(invalidate);
  const parts: Node[] = [];
  for (const surface of conversation.processor.surfaces) {
    if (typeof props.surfaceId === 'string' && props.surfaceId && surface.id !== props.surfaceId) continue;
    parts.push(lowerSurface(surface, { hooks, state: conversation.ui, keyPrefix: elementId, showAttribution: props.showAttribution !== false }).node);
  }
  parts.push(...chatParts(conversation, props, elementId, invalidate));
  return { type: 'Column', key: `${elementId}/a2ui`, props: { style: { alignItems: 'stretch' } }, children: parts };
}

const a2uiSurfaceBuilder: WidgetBuilder = (node, _children, ctx: BuildContext): W => {
  const tree = a2uiSurfaceTree(ctx.engine, node.props, ctx.elementId, node);
  return ctx.engine.renderNode(nodeFromJson(tree), ctx, 0);
};

export const a2uiWidgets: Record<string, WidgetBuilder> = {
  A2UISurface: a2uiSurfaceBuilder,
  'a2ui-surface': a2uiSurfaceBuilder,
};

// ----------------------------------------------------------------------------
// Host APIs
// ----------------------------------------------------------------------------

function errorResponse(message: string): string {
  return makeResponse('object', { error: { message } });
}

/** A typed host response for a JSON value. */
function valueResponse(value: unknown): string {
  if (value === null || value === undefined) return NULL_RESPONSE;
  if (Array.isArray(value)) return makeResponse('array', value);
  if (typeof value === 'object') return makeResponse('object', value);
  if (typeof value === 'string') return makeResponse('string', value);
  if (typeof value === 'boolean') return makeResponse('bool', value);
  if (typeof value === 'number') return makeResponse(Number.isInteger(value) ? 'i64' : 'f64', value);
  return NULL_RESPONSE;
}

/**
 * `agent.send {agent, conversation?, message}` → `{conversationId, conversation}`
 * (once the agent named the conversation); `agent.action {agent, conversation?,
 * action}` → the same; `a2ui.dataModel {conversation, surfaceId}` → the
 * surface's current data model. `conversation` is the conversation key the
 * widgets use (default `agent:<agent>`), so guest code and `A2UISurface`
 * widgets share conversations.
 */
export async function handleAgentHostCall(services: ElpianServices, apiName: string, payload: string): Promise<string> {
  const args = normalizedArgs(payload);
  const registry = a2uiRegistry(services);
  const agent = typeof args.agent === 'string' ? args.agent : '';
  const key = typeof args.conversation === 'string' && args.conversation ? args.conversation : `agent:${agent}`;
  switch (apiName) {
    case 'agent.send':
    case 'agent.action': {
      if (!agent && !registry.get(key)) return errorResponse(`${apiName} requires "agent"`);
      const conversation = registry.conversation(key, () => new A2UIConversation({ endpoint: registry.endpoint(agent) }));
      if (!conversation.endpoint && agent) conversation.endpoint = registry.endpoint(agent);
      if (!conversation.endpoint) return errorResponse('no agent endpoint is configured for this app');
      let turn;
      if (apiName === 'agent.send') {
        turn = conversation.send(typeof args.message === 'string' ? args.message : JSON.stringify(args.message ?? ''));
      } else {
        const action = isMap(args.action) ? { ...args.action } : null;
        if (!action || typeof action.name !== 'string') return errorResponse('agent.action requires an "action" with a "name"');
        if (typeof action.timestamp !== 'string') action.timestamp = new Date().toISOString();
        if (!isMap(action.context)) action.context = {};
        turn = conversation.sendAction(action);
      }
      const conversationId = await turn.conversationId;
      registry.invalidate();
      return makeResponse('object', { conversationId, conversation: key });
    }
    case 'a2ui.dataModel': {
      const conversation = registry.get(key);
      const surfaceId = typeof args.surfaceId === 'string' ? args.surfaceId : '';
      if (!conversation || !surfaceId) return NULL_RESPONSE;
      return valueResponse(conversation.dataModel(surfaceId));
    }
  }
  return NULL_RESPONSE;
}
