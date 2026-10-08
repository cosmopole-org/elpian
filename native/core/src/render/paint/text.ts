/**
 * RenderText — a paragraph of styled spans (Flutter `Text` / `RichText` /
 * `SelectableText`). Layout asks the platform to measure the paragraph with
 * the incoming max width (the platform renders the exact same spec, so the
 * measured and painted text always agree).
 */
import { RenderObject, INF, constrain, type Constraints } from '../object.js';
import { applyTextTransform, mergeTextStyle, toSpec, type TextStyle } from '../text-style.js';
import type { TextMetrics, TextSpanSpec, TextSpec, ViewEvent, ViewKind, ViewProps } from '../view.js';
import { RenderDefaultTextStyle } from './box.js';

export interface SpanInput {
  text: string;
  style?: TextStyle | null;
  link?: string | null;
}

/**
 * props: {
 *   text?: string, spans?: SpanInput[], style?: TextStyle,
 *   align?, maxLines?, overflow?, softWrap?, selectable?, direction?,
 *   onLink?: (href) => void
 * }
 */
export class RenderText extends RenderObject {
  private metrics: TextMetrics | null = null;
  private spec: TextSpec | null = null;

  /** The nearest DefaultTextStyle chain merged outermost-first. */
  inheritedStyle(): { style: TextStyle; align?: string; maxLines?: number | null; overflow?: string; softWrap?: boolean } {
    const chain: RenderDefaultTextStyle[] = [];
    let node = this.parent;
    while (node) {
      if (node instanceof RenderDefaultTextStyle) chain.push(node);
      node = node.parent;
    }
    let style: TextStyle = {};
    let align: string | undefined;
    let maxLines: number | null | undefined;
    let overflow: string | undefined;
    let softWrap: boolean | undefined;
    for (let i = chain.length - 1; i >= 0; i--) {
      const p = chain[i].props;
      style = mergeTextStyle(style, p.style);
      if (p.textAlign) align = p.textAlign;
      if (p.maxLines !== undefined) maxLines = p.maxLines;
      if (p.overflow) overflow = p.overflow;
      if (p.softWrap !== undefined) softWrap = p.softWrap;
    }
    return { style, align, maxLines, overflow, softWrap };
  }

  buildSpec(): TextSpec {
    const inherited = this.inheritedStyle();
    const base = mergeTextStyle(inherited.style, this.props.style ?? null);
    const scale = this.owner?.textScale ?? 1;
    const inputs: SpanInput[] = this.props.spans ?? [{ text: this.props.text ?? '' }];
    const spans: TextSpanSpec[] = inputs.map((s) => {
      const style = mergeTextStyle(base, s.style ?? null);
      const out: TextSpanSpec = { text: applyTextTransform(s.text ?? '', style.textTransform), style: toSpec(style, scale) };
      if (s.link) out.link = s.link;
      return out;
    });
    const softWrap = this.props.softWrap ?? inherited.softWrap ?? true;
    return {
      spans,
      align: this.props.align ?? inherited.align ?? 'start',
      maxLines: this.props.maxLines ?? inherited.maxLines ?? null,
      overflow: this.props.overflow ?? inherited.overflow ?? 'clip',
      softWrap,
      selectable: !!this.props.selectable,
      direction: this.props.direction === 'rtl' ? 'rtl' : 'ltr',
    } as TextSpec;
  }

  private measure(spec: TextSpec, maxWidth: number): TextMetrics {
    const owner = this.owner;
    if (!owner) {
      const size = spec.spans.reduce((s, sp) => s + sp.text.length * sp.style.fontSize * 0.5, 0);
      return { width: Math.min(size, maxWidth), height: 20, baseline: 15, lineCount: 1, didExceedMaxLines: false };
    }
    return owner.measureText(spec, maxWidth);
  }

  protected performLayout(c: Constraints): void {
    const spec = this.buildSpec();
    this.spec = spec;
    const maxWidth = spec.softWrap || spec.overflow === 'ellipsis' || spec.overflow === 'fade' ? c.maxWidth : INF;
    const metrics = this.measure(spec, maxWidth);
    this.metrics = metrics;
    // Fractional widths are rounded up so the platform never wraps a line
    // the measurement placed on one line.
    this.size = constrain(c, { width: Math.ceil(metrics.width - 0.001), height: Math.ceil(metrics.height - 0.001) });
  }

  baseline(): number | null {
    return this.metrics?.baseline ?? null;
  }

  protected computeMinIntrinsicWidth(): number {
    const spec = this.buildSpec();
    if (!spec.softWrap) return Math.ceil(this.measure(spec, INF).width);
    return Math.ceil(this.measure(spec, 0).width);
  }
  protected computeMaxIntrinsicWidth(): number {
    return Math.ceil(this.measure(this.buildSpec(), INF).width);
  }
  protected computeMinIntrinsicHeight(width: number): number {
    return Math.ceil(this.measure(this.buildSpec(), width).height);
  }
  protected computeMaxIntrinsicHeight(width: number): number {
    return this.computeMinIntrinsicHeight(width);
  }

  viewKind(): ViewKind {
    return 'text';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    const spec = this.spec ?? this.buildSpec();
    const hasLinks = spec.spans.some((s) => s.link);
    return { text: spec, gestures: hasLinks ? ['tap'] : null };
  }

  handleViewEvent(event: ViewEvent): void {
    if (event.type === 'link' && typeof event.value === 'string') this.props.onLink?.(event.value);
  }

  get lastMetrics(): TextMetrics | null {
    return this.metrics;
  }
}
