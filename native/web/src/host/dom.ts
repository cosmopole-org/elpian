/**
 * The guest-visible document — a port of `dom_api.dart` (`ElpianDOM`,
 * `ElpianElement`), backing the `dom.*` host APIs. Elements can be turned into
 * Elpian JSON (`toJson`) and rendered.
 */
import type { JsonMap } from '../util/json.js';

export class ElpianElement {
  parent: ElpianElement | null = null;
  private kids: ElpianElement[] = [];
  private attrs: Record<string, any> = {};
  private styles: Record<string, any> = {};
  private listeners = new Map<string, (data?: any) => void>();
  textContent: string | null = null;

  constructor(
    readonly tagName: string,
    readonly id: string | null,
    readonly classes: string[],
    private readonly dom: ElpianDOM,
  ) {}

  get innerHTML(): string | null {
    return this.textContent;
  }
  set innerHTML(v: string | null) {
    this.textContent = v;
  }

  getAttribute(name: string): any {
    return this.attrs[name];
  }
  setAttribute(name: string, value: any): void {
    this.attrs[name] = value;
  }
  removeAttribute(name: string): void {
    delete this.attrs[name];
  }
  hasAttribute(name: string): boolean {
    return Object.prototype.hasOwnProperty.call(this.attrs, name);
  }
  get attributes(): Record<string, any> {
    return { ...this.attrs };
  }

  setStyle(property: string, value: any): void {
    this.styles[property] = value;
  }
  getStyle(property: string): any {
    return this.styles[property];
  }
  setStyleObject(styles: Record<string, any>): void {
    Object.assign(this.styles, styles);
  }
  get style(): Record<string, any> {
    return { ...this.styles };
  }

  addClass(className: string): void {
    if (!this.classes.includes(className)) {
      this.classes.push(className);
      this.dom.indexClass(className, this);
    }
  }
  removeClass(className: string): void {
    const i = this.classes.indexOf(className);
    if (i >= 0) this.classes.splice(i, 1);
    this.dom.unindexClass(className, this);
  }
  hasClass(className: string): boolean {
    return this.classes.includes(className);
  }
  toggleClass(className: string): void {
    if (this.hasClass(className)) this.removeClass(className);
    else this.addClass(className);
  }

  appendChild(child: ElpianElement): void {
    child.parent?.removeChild(child);
    child.parent = this;
    this.kids.push(child);
  }
  insertBefore(newChild: ElpianElement, reference: ElpianElement | null): void {
    newChild.parent?.removeChild(newChild);
    newChild.parent = this;
    if (!reference) {
      this.kids.push(newChild);
      return;
    }
    const index = this.kids.indexOf(reference);
    if (index >= 0) this.kids.splice(index, 0, newChild);
    else this.kids.push(newChild);
  }
  removeChild(child: ElpianElement): void {
    const i = this.kids.indexOf(child);
    if (i >= 0) {
      this.kids.splice(i, 1);
      child.parent = null;
    }
  }
  replaceChild(newChild: ElpianElement, oldChild: ElpianElement): void {
    if (!this.kids.includes(oldChild)) return;
    newChild.parent?.removeChild(newChild);
    const index = this.kids.indexOf(oldChild);
    newChild.parent = this;
    oldChild.parent = null;
    this.kids[index] = newChild;
  }
  get children(): ElpianElement[] {
    return [...this.kids];
  }
  get firstChild(): ElpianElement | null {
    return this.kids[0] ?? null;
  }
  get lastChild(): ElpianElement | null {
    return this.kids[this.kids.length - 1] ?? null;
  }
  get nextSibling(): ElpianElement | null {
    if (!this.parent) return null;
    const s = this.parent.kids;
    const i = s.indexOf(this);
    return i >= 0 && i < s.length - 1 ? s[i + 1] : null;
  }
  get previousSibling(): ElpianElement | null {
    if (!this.parent) return null;
    const s = this.parent.kids;
    const i = s.indexOf(this);
    return i > 0 ? s[i - 1] : null;
  }

  addEventListener(event: string, callback: (data?: any) => void): void {
    this.listeners.set(event, callback);
  }
  removeEventListener(event: string): void {
    this.listeners.delete(event);
  }
  dispatchEvent(event: string, data?: any): void {
    this.listeners.get(event)?.(data);
  }

  clone(deep = false): ElpianElement {
    const copy = this.dom.createElement(this.tagName, { classes: [...this.classes] });
    copy.attrs = { ...this.attrs };
    copy.styles = { ...this.styles };
    copy.textContent = this.textContent;
    if (deep) for (const k of this.kids) copy.appendChild(k.clone(true));
    return copy;
  }

  /** The element as Elpian JSON (`toElpianNode().toJson()`). */
  toJson(): JsonMap {
    const props: JsonMap = { ...this.attrs };
    if (this.textContent != null) props.text = this.textContent;
    if (this.classes.length) props.className = this.classes.join(' ');
    if (Object.keys(this.styles).length) props.style = { ...this.styles };
    const out: JsonMap = { type: this.tagName, props, children: this.kids.map((k) => k.toJson()) };
    if (this.id != null) out.key = this.id;
    return out;
  }

  encode(): JsonMap {
    return {
      id: this.id,
      tagName: this.tagName,
      classes: [...this.classes],
      attributes: { ...this.attrs },
      style: { ...this.styles },
      textContent: this.textContent,
      children: this.kids.map((c) => c.id),
    };
  }

  toString(): string {
    return `<${this.tagName}${this.id ? ` id="${this.id}"` : ''}${this.classes.length ? ` class="${this.classes.join(' ')}"` : ''}>`;
  }
}

export class ElpianDOM {
  private byId = new Map<string, ElpianElement>();
  private all: ElpianElement[] = [];
  private byClass = new Map<string, ElpianElement[]>();
  private byTag = new Map<string, ElpianElement[]>();

  getElementById(id: string): ElpianElement | null {
    return this.byId.get(id) ?? null;
  }
  getElementsByClassName(className: string): ElpianElement[] {
    return [...(this.byClass.get(className) ?? [])];
  }
  getElementsByTagName(tagName: string): ElpianElement[] {
    return [...(this.byTag.get(tagName) ?? [])];
  }
  querySelector(selector: string): ElpianElement | null {
    return this.querySelectorAll(selector)[0] ?? null;
  }
  querySelectorAll(selector: string): ElpianElement[] {
    const s = selector.trim();
    if (s.startsWith('#')) {
      const e = this.getElementById(s.substring(1));
      return e ? [e] : [];
    }
    if (s.startsWith('.')) return this.getElementsByClassName(s.substring(1));
    // `tag.class` compound selectors.
    const m = /^([a-zA-Z][\w-]*)?((?:\.[\w-]+)*)$/.exec(s);
    if (m && m[2]) {
      const classes = m[2].split('.').filter((c) => c);
      return this.all.filter((e) => (!m[1] || e.tagName === m[1]) && classes.every((c) => e.classes.includes(c)));
    }
    return this.getElementsByTagName(s);
  }

  createElement(tagName: string, opts: { id?: string | null; classes?: string[] | null } = {}): ElpianElement {
    const el = new ElpianElement(tagName, opts.id ?? null, [...(opts.classes ?? [])], this);
    if (el.id != null) this.byId.set(el.id, el);
    this.all.push(el);
    const tags = this.byTag.get(tagName) ?? [];
    tags.push(el);
    this.byTag.set(tagName, tags);
    for (const c of el.classes) this.indexClass(c, el);
    return el;
  }

  /** Build elements from Elpian JSON (`ElpianElement.fromElpianNode`). */
  fromJson(json: JsonMap): ElpianElement {
    const props = (json.props ?? {}) as JsonMap;
    const cn = props.className;
    const classes = typeof cn === 'string' ? cn.split(/\s+/).filter((c: string) => c) : Array.isArray(cn) ? cn.map(String) : [];
    const el = this.createElement(String(json.type ?? 'div'), { id: (json.key as string) ?? null, classes });
    for (const [k, v] of Object.entries(props)) if (k !== 'className' && k !== 'style') el.setAttribute(k, v);
    if (props.style && typeof props.style === 'object') el.setStyleObject(props.style as JsonMap);
    if (props.text != null) el.textContent = String(props.text);
    for (const child of (json.children as JsonMap[]) ?? []) el.appendChild(this.fromJson(child));
    return el;
  }

  indexClass(className: string, el: ElpianElement): void {
    const list = this.byClass.get(className) ?? [];
    if (!list.includes(el)) list.push(el);
    this.byClass.set(className, list);
  }

  unindexClass(className: string, el: ElpianElement): void {
    const list = this.byClass.get(className);
    if (!list) return;
    const i = list.indexOf(el);
    if (i >= 0) list.splice(i, 1);
  }

  removeElement(el: ElpianElement): void {
    if (el.id != null) this.byId.delete(el.id);
    this.all = this.all.filter((e) => e !== el);
    const tags = this.byTag.get(el.tagName);
    if (tags) this.byTag.set(el.tagName, tags.filter((e) => e !== el));
    for (const c of el.classes) this.unindexClass(c, el);
    el.parent?.removeChild(el);
  }

  clear(): void {
    this.byId.clear();
    this.all = [];
    this.byClass.clear();
    this.byTag.clear();
  }

  get allElements(): ElpianElement[] {
    return [...this.all];
  }
}
