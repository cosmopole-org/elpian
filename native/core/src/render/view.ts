/**
 * The view protocol — the only thing a platform renderer has to understand.
 *
 * The core lays out the Elpian tree itself and emits a flat stream of
 * operations over a small set of primitive *view kinds*. The web renderer
 * maps each kind onto DOM elements and applies the props. Frames are always in logical pixels,
 * relative to the parent view's top-left corner (a scroll view's children are
 * relative to its content origin).
 *
 * The protocol is JSON-only, so a renderer can live in the page, a worker or
 * a test harness alike.
 */
import type { Color } from '../css/color.js';
import type { Alignment, Border, BorderRadius, BoxFit, BoxShadow, Filter, Gradient, Matrix4, TextShadow } from '../css/types.js';

export type ViewKind =
  | 'view' // a box: background, border, radius, shadows, clip, transform, opacity, gestures
  | 'text' // a laid-out paragraph of styled spans
  | 'image' // a bitmap from a URL / asset / data URI
  | 'scroll' // a scrolling container (children live in its content space)
  | 'textInput' // single- or multi-line editable text
  | 'checkbox'
  | 'radio'
  | 'switch'
  | 'slider'
  | 'select' // a dropdown / menu picker
  | 'progress' // linear or circular, determinate or not
  | 'canvas' // a 2D canvas fed with Elpian canvas commands
  | 'scene3d' // an embedded Godot viewport
  | 'video'
  | 'audio'
  | 'web' // an embedded web page (iframe / embed / object)
  | 'native'; // a host-registered native component (a server-component island)

export interface TextStyleSpec {
  color: Color;
  fontSize: number;
  fontWeight: number;
  italic: boolean;
  /** `null` = the platform's default sans-serif; `serif`, `monospace`, `icons` or a family name. */
  fontFamily: string | null;
  letterSpacing: number;
  wordSpacing: number;
  /** Line height as a multiple of the font size (Flutter `height`); null = font default. */
  height: number | null;
  /** Bit flags: 1 underline, 2 overline, 4 line-through. */
  decoration: number;
  decorationColor: Color | null;
  decorationStyle: string | null;
  decorationThickness: number | null;
  shadows: TextShadow[] | null;
  background: Color | null;
  /** Vertical shift in px (positive = down) for `sub` / `sup`. */
  baselineShift: number;
}

export interface TextSpanSpec {
  text: string;
  style: TextStyleSpec;
  /** Present when the span is tappable (a link inside rich text). */
  link?: string;
}

export interface TextSpec {
  spans: TextSpanSpec[];
  align: 'left' | 'right' | 'center' | 'justify' | 'start' | 'end';
  maxLines: number | null;
  overflow: 'clip' | 'ellipsis' | 'fade' | 'visible';
  softWrap: boolean;
  selectable: boolean;
  direction: 'ltr' | 'rtl';
}

export interface TextMetrics {
  width: number;
  height: number;
  /** Distance from the top to the first line's alphabetic baseline. */
  baseline: number;
  lineCount: number;
  /** True when maxLines/overflow cut the text. */
  didExceedMaxLines: boolean;
}

/** Sizes a native control the core cannot measure itself. */
export interface ControlMeasureSpec {
  kind: ViewKind;
  props: Record<string, any>;
}

export interface Size {
  width: number;
  height: number;
}

/** Gestures a view should recognise and report back with `dispatch`. */
export type GestureKind =
  | 'tap'
  | 'doubletap'
  | 'longpress'
  | 'tapdown'
  | 'tapup'
  | 'tapcancel'
  | 'pan' // dragstart / drag / dragend
  | 'swipe'
  | 'pointer' // pointerdown / up / move / cancel
  | 'hover' // pointerenter / exit / hover
  | 'scale' // pinch / rotate
  | 'key' // keyboard while focused
  | 'focus' // focus / blur
  | 'dismiss' // swipe-to-dismiss (Dismissible)
  | 'draggable' // long-press/drag with a floating feedback copy (Draggable)
  | 'scroll'; // report scroll offsets

/** The visual and behavioural properties of one view. Absent = unset/default. */
export interface ViewProps {
  frame: [number, number, number, number];

  // ---- box painting (all kinds) ----
  background?: Color | null;
  /** Gradient layers, bottom first; painted above [background]. */
  gradients?: Gradient[] | null;
  backgroundImage?: { src: string; fit: BoxFit | null; alignment: Alignment | null; repeat: string | null; size?: { width: number | null; height: number | null } | null } | null;
  border?: Border | null;
  radius?: BorderRadius | null;
  /** Paint and clip as an ellipse inscribed in the frame (BoxShape.circle). */
  oval?: boolean;
  shadows?: BoxShadow[] | null;
  outline?: { width: number; color: Color; style: string; offset: number } | null;
  opacity?: number;
  /** Applied about [transformOrigin] (px, relative to the view). */
  transform?: Matrix4 | null;
  transformOrigin?: [number, number] | null;
  /** Clip children to the (rounded) bounds. */
  clip?: boolean;
  hidden?: boolean;
  /** `none` = this view and its subtree ignore touches. */
  pointerEvents?: 'auto' | 'none';
  cursor?: string | null;
  filter?: Filter | null;
  backdropFilter?: Filter | null;
  /** A ShaderMask-style gradient painted over the content with srcATop (Shimmer). */
  shaderMask?: Gradient | null;
  blendMode?: string | null;
  zIndex?: number;

  // ---- interaction ----
  gestures?: GestureKind[] | null;
  /** Native pressed-state feedback: ripple / highlight colour. */
  ripple?: Color | null;
  focusable?: boolean;
  tooltip?: string | null;
  semanticsLabel?: string | null;
  role?: string | null;
  /** For `draggable`: opaque data echoed back on drop. */
  dragData?: any;
  /** For `dismiss`: allowed direction (`horizontal`, `endToStart`, `startToEnd`, `vertical`, `up`, `down`). */
  dismissDirection?: string | null;

  // ---- text ----
  text?: TextSpec;

  // ---- image ----
  src?: string | null;
  fit?: BoxFit | null;
  alignment?: Alignment | null;
  alt?: string | null;
  tint?: Color | null;

  // ---- scroll ----
  /** `vertical`, `horizontal` or `both`. */
  scrollAxis?: 'vertical' | 'horizontal' | 'both';
  contentSize?: [number, number];
  scrollEnabled?: boolean;
  showScrollbar?: boolean;
  /** Scroll position the core asks the platform to apply (restored state). */
  scrollTo?: [number, number] | null;

  // ---- controls ----
  value?: any;
  checked?: boolean;
  enabled?: boolean;
  placeholder?: string | null;
  inputType?: string | null; // text, password, number, email, tel, url, search, multiline…
  multiline?: boolean;
  minLines?: number | null;
  maxLines?: number | null;
  maxLength?: number | null;
  readOnly?: boolean;
  autofocus?: boolean;
  suggestions?: string[] | null;
  options?: { value: string; label: string; group?: string | null; disabled?: boolean }[] | null;
  min?: number;
  max?: number;
  step?: number | null;
  /** Control palette (track, thumb, fill, text, hint, border, focused border). */
  colors?: Record<string, Color | null> | null;
  textStyle?: TextStyleSpec | null;
  hintStyle?: TextStyleSpec | null;
  contentPadding?: [number, number, number, number] | null;
  variant?: string | null; // progress: linear|circular; switch/checkbox styles…
  strokeWidth?: number | null;

  // ---- canvas ----
  /** Full command list for a canvas (normalised, see canvas/commands.ts). */
  commands?: any[] | null;
  /** Commands to append to what the canvas already shows (cached contexts). */
  appendCommands?: any[] | null;
  canvasVersion?: number;

  // ---- 3D ----
  surfaceId?: number;
  clickable?: boolean;

  // ---- media / web ----
  autoplay?: boolean;
  loop?: boolean;
  muted?: boolean;
  controls?: boolean;
  poster?: string | null;
  tracks?: { src: string; kind: string; srclang: string | null; label: string | null; default: boolean }[] | null;
  html?: string | null;
  javascript?: boolean;

  // ---- native island ----
  /** The host-registered component name (`registerNativeComponent`). */
  component?: string | null;
  componentProps?: Record<string, any> | null;
}

export type ViewOp =
  | { op: 'create'; id: number; kind: ViewKind; parent: number; index: number; props: ViewProps }
  | { op: 'update'; id: number; props: Partial<ViewProps> }
  | { op: 'move'; id: number; parent: number; index: number }
  | { op: 'remove'; id: number }
  | { op: 'command'; id: number; name: string; args?: any };

/** The id of the platform-owned root container every top-level view is created in. */
export const ROOT_VIEW_ID = 0;

/** Events a platform reports back for a view. */
export interface ViewEvent {
  id: number;
  /** tap, doubletap, longpress, tapdown, tapup, tapcancel, dragstart, drag, dragend,
   *  swipe, pointerdown, pointerup, pointermove, pointercancel, pointerenter,
   *  pointerexit, pointerhover, scalestart, scaleupdate, scaleend, keydown, keyup,
   *  focus, blur, change, input, submit, scroll, dismissed, dragaccept, load, error,
   *  play, pause, ended, timeupdate, signal … */
  type: string;
  x?: number;
  y?: number;
  localX?: number;
  localY?: number;
  dx?: number;
  dy?: number;
  vx?: number;
  vy?: number;
  scale?: number;
  rotation?: number;
  buttons?: number;
  pressure?: number;
  pointerId?: number;
  key?: string;
  keyCode?: number;
  altKey?: boolean;
  ctrlKey?: boolean;
  shiftKey?: boolean;
  metaKey?: boolean;
  value?: any;
  scrollX?: number;
  scrollY?: number;
  direction?: string;
  data?: any;
}
