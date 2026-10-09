/**
 * The few globals the core relies on. Every host provides them: browsers
 * natively, and the Android (QuickJS) and iOS (JavaScriptCore) bridges install
 * a `console` that forwards to the platform log before loading the core.
 */
declare const console: {
  log(...args: unknown[]): void;
  info(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  error(...args: unknown[]): void;
  debug(...args: unknown[]): void;
};
