import type { StyleProp, ViewStyle } from 'react-native';

/** The session kinds every host supports (see the core's SessionRegistry). */
export type ElpianSessionKind = 'json' | 'miniapp' | 'superapp' | 'stream' | 'nextjs' | 'server' | 'agent';

/** A session event: `ready`, `error`, `println`, `updateApp`, `routeChanged`, `result`, … */
export interface ElpianEvent {
  event: string;
  payload: unknown;
}

export interface ElpianViewProps {
  /** Session kind; changing it re-opens the session. */
  kind: ElpianSessionKind;
  /**
   * Session options (JSON-serializable), e.g. for `miniapp`:
   * `{ runtime: 'quickjs' | 'elpian' | 'wasm', code, astJson, bytecodeBase64, entryFunction, stylesheet }`;
   * for `agent`: `{ baseUrl, appId, agent, prompt?, conversationId?, chat? }`.
   * Changing them re-opens the session.
   */
  options?: Record<string, unknown>;
  /** Every session event. */
  onEvent?: (e: ElpianEvent) => void;
  /** Convenience for `ready`. */
  onReady?: () => void;
  /** Convenience for `error`. */
  onError?: (message: string) => void;
  style?: StyleProp<ViewStyle>;
}

/** Imperative handle (via `ref`). */
export interface ElpianViewHandle {
  /** Call a session method (navigate, push, callFunction, usage, state, …). */
  call(method: string, ...args: unknown[]): Promise<unknown>;
  /** Close the session (the view can be re-opened by changing `kind`/`options`). */
  close(): Promise<void>;
}
