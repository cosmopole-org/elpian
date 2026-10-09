/**
 * Services a guest's host calls — a port of `HostHandler`
 * (flutter/lib/src/vm/host_handler.dart). Every runtime (Elpian VM, QuickJS,
 * WASM) funnels `askHost(api, payload)` here; replies are typed JSON
 * envelopes (`{"type", "data": {"value"}}`).
 */
import { commandFromJson, isCanvasCommandType, type CanvasCommand } from '../canvas/store.js';
import type { ElpianServices } from '../engine/engine.js';
import { asHostArgs, coerceJsonMap, isMap, normalizedArgs, parseVmPayload, toNumber, unwrapHostArgs, type JsonMap } from '../util/json.js';
import { NULL_RESPONSE, OK_RESPONSE, makeResponse } from '../util/typed.js';
import { allHostApiNames, canvasApiNames, domApiNames } from '../vm/host-api-catalog.js';
import type { ElpianDOM, ElpianElement } from './dom.js';

export type RenderHostCallback = (viewJson: JsonMap, scopeKey: string | null) => void;

export interface HostHandlerOptions {
  onRender?: RenderHostCallback;
  onUpdateApp?: (updateData: JsonMap) => void;
  onPrintln?: (message: string) => void;
  onGetEnvironment?: () => JsonMap;
  /** A guest reached for an API this handler does not implement. */
  onUnservicedApi?: (apiName: string, advertised: boolean) => void;
  /** Consulted before every call; return false to refuse it. */
  onAuthorize?: (apiName: string) => boolean;
  /** [onAuthorize] refused a call. */
  onCallRefused?: (apiName: string) => void;
  log?: (message: string) => void;
}

export class HostHandler {
  constructor(
    readonly services: ElpianServices,
    readonly options: HostHandlerOptions = {},
  ) {}

  get dom(): ElpianDOM {
    return this.services.dom;
  }

  private scoped(id: string): string {
    return this.services.scopeId(id);
  }

  private log(message: string): void {
    this.options.log?.(message);
  }

  handleHostCall(apiName: string, payload: string): string {
    const { onAuthorize, onCallRefused } = this.options;
    if (onAuthorize && !onAuthorize(apiName)) {
      onCallRefused?.(apiName);
      this.log(`HostHandler[${this.services.appId}]: ${apiName} refused by policy`);
      // The typed null the VM produces for a denied capability.
      return NULL_RESPONSE;
    }
    if (domApiNames.has(apiName)) return this.handleDomApi(apiName, payload);
    if (canvasApiNames.has(apiName)) return this.handleCanvasApi(apiName, payload);
    switch (apiName) {
      case 'render':
        return this.handleRender(payload);
      case 'updateApp':
        return this.handleUpdateApp(payload);
      case 'println':
        return this.handlePrintln(payload);
      case 'env.get':
        return this.handleEnvGet();
      case 'stringify':
        return makeResponse('string', payload);
      default:
        return this.unserviced(apiName);
    }
  }

  private unserviced(apiName: string): string {
    const known = allHostApiNames.has(apiName);
    this.options.onUnservicedApi?.(apiName, known);
    this.log(
      known
        ? `HostHandler: ${apiName} is advertised by the VM but not serviced here; returning null`
        : `HostHandler: unknown host API ${apiName}; returning null`,
    );
    return NULL_RESPONSE;
  }

  handleRender(payload: string): string {
    try {
      const args = asHostArgs(parseVmPayload(payload));
      const viewArg = args.length ? args[0] : null;
      const scopeKey = args.length > 1 ? asNullableString(args[1]) : null;
      const viewJson = coerceJsonMap(viewArg);
      if (viewJson) this.options.onRender?.(viewJson, scopeKey);
      else if (typeof viewArg === 'string') this.options.onRender?.({ type: 'Text', props: { text: viewArg } }, scopeKey);
    } catch (e) {
      this.log(`HostHandler: render error: ${e}`);
    }
    return OK_RESPONSE;
  }

  handleUpdateApp(payload: string): string {
    try {
      const parsed = unwrapHostArgs(parseVmPayload(payload));
      if (isMap(parsed)) this.options.onUpdateApp?.(parsed);
    } catch (e) {
      this.log(`HostHandler: updateApp error: ${e}`);
    }
    return OK_RESPONSE;
  }

  handlePrintln(payload: string): string {
    const parsed = unwrapHostArgs(parseVmPayload(payload));
    this.options.onPrintln?.(typeof parsed === 'string' ? parsed : payload);
    return OK_RESPONSE;
  }

  handleEnvGet(): string {
    return makeResponse('object', this.options.onGetEnvironment?.() ?? {});
  }

  // ---------------------------------------------------------------------------
  // dom.*
  // ---------------------------------------------------------------------------

  private handleDomApi(apiName: string, payload: string): string {
    try {
      const args = normalizedArgs(payload);
      const dom = this.dom;
      const s = (k: string) => (args[k] == null ? '' : String(args[k]));
      const el = (key = 'id') => this.elementFromArgs(args, key);
      switch (apiName) {
        case 'dom.createElement': {
          const classes = Array.isArray(args.classes) ? args.classes.map(String) : null;
          return makeResponse('object', encodeElement(dom.createElement(args.tagName != null ? String(args.tagName) : 'div', { id: args.id != null ? String(args.id) : null, classes })));
        }
        case 'dom.getElementById':
          return makeResponse('object', encodeElement(dom.getElementById(s('id'))));
        case 'dom.getElementsByClassName':
          return makeResponse('array', encodeElements(dom.getElementsByClassName(s('className'))));
        case 'dom.getElementsByTagName':
          return makeResponse('array', encodeElements(dom.getElementsByTagName(s('tagName'))));
        case 'dom.querySelector':
          return makeResponse('object', encodeElement(dom.querySelector(s('selector'))));
        case 'dom.querySelectorAll':
          return makeResponse('array', encodeElements(dom.querySelectorAll(s('selector'))));
        case 'dom.removeElement': {
          const e = el();
          if (e) dom.removeElement(e);
          return OK_RESPONSE;
        }
        case 'dom.clear':
          dom.clear();
          return OK_RESPONSE;
        case 'dom.setTextContent': {
          const e = el();
          if (e) e.textContent = args.text != null ? String(args.text) : null;
          return OK_RESPONSE;
        }
        case 'dom.setInnerHtml': {
          const e = el();
          if (e) e.innerHTML = args.html != null ? String(args.html) : null;
          return OK_RESPONSE;
        }
        case 'dom.setAttribute':
          el()?.setAttribute(s('name'), args.value);
          return OK_RESPONSE;
        case 'dom.getAttribute':
          return makeResponse('string', String(el()?.getAttribute(s('name')) ?? ''));
        case 'dom.removeAttribute':
          el()?.removeAttribute(s('name'));
          return OK_RESPONSE;
        case 'dom.hasAttribute':
          return makeResponse('bool', el()?.hasAttribute(s('name')) ?? false);
        case 'dom.setStyle':
          el()?.setStyle(s('property'), args.value);
          return OK_RESPONSE;
        case 'dom.getStyle':
          return makeResponse('string', String(el()?.getStyle(s('property')) ?? ''));
        case 'dom.setStyleObject':
          el()?.setStyleObject(isMap(args.styles) ? args.styles : {});
          return OK_RESPONSE;
        case 'dom.addClass':
          el()?.addClass(s('className'));
          return OK_RESPONSE;
        case 'dom.removeClass':
          el()?.removeClass(s('className'));
          return OK_RESPONSE;
        case 'dom.hasClass':
          return makeResponse('bool', el()?.hasClass(s('className')) ?? false);
        case 'dom.toggleClass':
          el()?.toggleClass(s('className'));
          return OK_RESPONSE;
        case 'dom.appendChild': {
          const parent = el('parentId');
          const child = el('childId');
          if (parent && child) parent.appendChild(child);
          return OK_RESPONSE;
        }
        case 'dom.insertBefore': {
          const parent = el('parentId');
          const child = el('newChildId');
          if (parent && child) parent.insertBefore(child, el('referenceChildId'));
          return OK_RESPONSE;
        }
        case 'dom.removeChild': {
          const parent = el('parentId');
          const child = el('childId');
          if (parent && child) parent.removeChild(child);
          return OK_RESPONSE;
        }
        case 'dom.replaceChild': {
          const parent = el('parentId');
          const fresh = el('newChildId');
          const old = el('oldChildId');
          if (parent && fresh && old) parent.replaceChild(fresh, old);
          return OK_RESPONSE;
        }
        case 'dom.addEventListener': {
          const e = el();
          const event = s('event');
          const callback = args.callback != null ? String(args.callback) : null;
          if (e && callback) {
            e.addEventListener(event, (data) =>
              this.options.onUpdateApp?.({ domEvent: callback, elementId: e.id, event, ...(data !== undefined ? { data } : {}) }),
            );
          }
          return OK_RESPONSE;
        }
        case 'dom.removeEventListener':
          el()?.removeEventListener(s('event'));
          return OK_RESPONSE;
        case 'dom.dispatchEvent':
          el()?.dispatchEvent(s('event'), args.data);
          return OK_RESPONSE;
        case 'dom.toJson': {
          const e = el();
          return makeResponse('object', e ? e.toJson() : {});
        }
        case 'dom.getAllElements':
          return makeResponse('array', encodeElements(dom.allElements));
      }
      return OK_RESPONSE;
    } catch (e) {
      this.log(`HostHandler: dom API error (${apiName}): ${e}`);
      return OK_RESPONSE;
    }
  }

  private elementFromArgs(args: JsonMap, key: string): ElpianElement | null {
    const raw = args[key] ?? args.selector;
    const id = raw == null ? '' : String(raw);
    if (!id) return null;
    return this.dom.getElementById(id) ?? this.dom.querySelector(id);
  }

  // ---------------------------------------------------------------------------
  // canvas.*
  // ---------------------------------------------------------------------------

  private handleCanvasApi(apiName: string, payload: string): string {
    try {
      if (apiName.startsWith('canvas.ctx.')) return this.handleCanvasContextApi(apiName, payload);
      const args = normalizedArgs(payload);
      const canvas = this.services.canvas;
      switch (apiName) {
        case 'canvas.clear':
          canvas.clear();
          return OK_RESPONSE;
        case 'canvas.getCommands':
          return makeResponse(
            'array',
            canvas.commands.map((c) => ({ type: c.type, params: c.params, ...(c.id != null ? { id: c.id } : {}) })),
          );
        case 'canvas.addCommand': {
          const cmd = commandFromArgs(args);
          if (cmd) canvas.addCommand(cmd);
          return OK_RESPONSE;
        }
        case 'canvas.addCommands':
          canvas.addCommands((Array.isArray(args.commands) ? args.commands : []).filter(isMap).map(commandFromJson));
          return OK_RESPONSE;
      }
      const name = apiName.replace(/^canvas\./, '');
      if (isCanvasCommandType(name)) canvas.addCommand({ type: name, params: args });
      return OK_RESPONSE;
    } catch (e) {
      this.log(`HostHandler: canvas API error (${apiName}): ${e}`);
      return OK_RESPONSE;
    }
  }

  private handleCanvasContextApi(apiName: string, payload: string): string {
    const args = normalizedArgs(payload);
    const store = this.services.canvasContexts;
    const id = args.id != null ? String(args.id) : null;
    const ctx = () => (id == null ? undefined : store.get(this.scoped(id)));
    switch (apiName) {
      case 'canvas.ctx.create': {
        const created = store.create({
          id: id == null || id === '' ? null : this.scoped(id),
          width: toNumber(args.width) ?? 0,
          height: toNumber(args.height) ?? 0,
        });
        // The guest's own id: later calls scope it again on the way in.
        return makeResponse('string', id ?? created.id);
      }
      case 'canvas.ctx.dispose':
        if (id) store.dispose(this.scoped(id));
        return OK_RESPONSE;
      case 'canvas.ctx.clear':
        ctx()?.clear();
        return OK_RESPONSE;
      case 'canvas.ctx.setSize': {
        const c = ctx();
        if (c) c.setSize(toNumber(args.width) ?? c.width, toNumber(args.height) ?? c.height);
        return OK_RESPONSE;
      }
      case 'canvas.ctx.addCommand': {
        const c = ctx();
        const json = args.command ?? args;
        if (c && isMap(json)) c.addCommand(commandFromJson(json));
        return OK_RESPONSE;
      }
      case 'canvas.ctx.addCommands': {
        const c = ctx();
        if (c && Array.isArray(args.commands)) c.addCommands(args.commands.filter(isMap).map(commandFromJson));
        return OK_RESPONSE;
      }
    }
    return OK_RESPONSE;
  }
}

function commandFromArgs(args: JsonMap): CanvasCommand | null {
  const t = args.type != null ? String(args.type) : null;
  if (!t || !isCanvasCommandType(t)) return null;
  return { type: t, params: isMap(args.params) ? { ...args.params } : {}, id: args.id != null ? String(args.id) : null };
}

function encodeElement(e: ElpianElement | null): JsonMap | null {
  return e ? e.encode() : null;
}

function encodeElements(list: ElpianElement[]): JsonMap[] {
  return list.map((e) => e.encode());
}

function asNullableString(value: unknown): string | null {
  if (value == null) return null;
  const s = String(value).trim();
  return s === '' || s === 'null' ? null : s;
}
