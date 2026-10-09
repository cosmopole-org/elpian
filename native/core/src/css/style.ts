/**
 * The resolved style of one element — the TypeScript twin of the Flutter
 * `CSSStyle` model, produced by [CSSParser.parse].
 *
 * Every field the Flutter parser fills is present with the same meaning; the
 * extra fields are values Flutter's model declares but its parser leaves
 * unread (filters, outlines, per-side borders from CSS strings, `margin:auto`
 * …), which the native renderers honour.
 */
import type { Color } from './color.js';
import type {
  Alignment,
  Border,
  BorderRadius,
  BoxFit,
  BoxShadow,
  EdgeInsets,
  Filter,
  FontWeight,
  Gradient,
  Keyframe,
  Matrix4,
  Offset,
  Overflow,
  Percent,
  TextAlign,
  TextDecoration,
  TextOverflow,
  TextShadow,
} from './types.js';

export interface CSSStyle {
  // Sizing
  width?: number | null;
  height?: number | null;
  widthFactor?: number | null;
  heightFactor?: number | null;
  minWidth?: number | null;
  maxWidth?: number | null;
  minHeight?: number | null;
  maxHeight?: number | null;
  aspectRatio?: number | null;

  // Spacing
  padding?: EdgeInsets | null;
  margin?: EdgeInsets | null;
  /** Sides whose margin is `auto` (centring in a flex/block parent). */
  marginAuto?: { top: boolean; right: boolean; bottom: boolean; left: boolean } | null;
  /** Padding/margin sides written as percentages, resolved against the parent width. */
  paddingPercent?: Partial<Record<'top' | 'right' | 'bottom' | 'left', Percent>> | null;
  marginPercent?: Partial<Record<'top' | 'right' | 'bottom' | 'left', Percent>> | null;

  // Positioning
  alignment?: Alignment | null;
  position?: string | null;
  top?: number | null;
  right?: number | null;
  bottom?: number | null;
  left?: number | null;
  zIndex?: number | null;

  // Layout
  display?: string | null;
  flexDirection?: string | null;
  justifyContent?: string | null;
  alignItems?: string | null;
  alignContent?: string | null;
  alignSelf?: string | null;
  flex?: number | null;
  flexGrow?: number | null;
  flexShrink?: number | null;
  flexBasis?: string | null;
  flexWrap?: string | null;
  order?: number | null;
  gap?: number | null;
  rowGap?: number | null;
  columnGap?: number | null;
  overflow?: Overflow | null;
  overflowX?: Overflow | null;
  overflowY?: Overflow | null;
  boxSizing?: string | null;

  // Grid
  gridTemplateColumns?: string | null;
  gridTemplateRows?: string | null;
  gridTemplateAreas?: string | null;
  gridAutoColumns?: string | null;
  gridAutoRows?: string | null;
  gridAutoFlow?: string | null;
  gridColumnGap?: number | null;
  gridRowGap?: number | null;
  gridGap?: number | null;
  gridColumn?: string | null;
  gridRow?: string | null;
  gridArea?: string | null;
  justifyItems?: string | null;
  justifySelf?: string | null;

  // Background
  backgroundColor?: Color | null;
  backgroundImage?: string | null;
  backgroundSize?: BoxFit | null;
  backgroundSizePx?: { width: number | null; height: number | null } | null;
  backgroundPosition?: Alignment | null;
  backgroundRepeat?: string | null;
  gradient?: Gradient | null;
  /** Extra gradient layers of a multi-layer `background` (painted under [gradient]). */
  gradientLayers?: Gradient[] | null;

  // Border
  border?: Border | null;
  borderRadius?: BorderRadius | null;
  /** Corner radii given as percentages of the box (`border-radius: 50%`). */
  borderRadiusPercent?: BorderRadius | null;
  borderColor?: Color | null;
  borderWidth?: number | null;
  borderStyle?: string | null;
  outlineColor?: Color | null;
  outlineWidth?: number | null;
  outlineStyle?: string | null;
  outlineOffset?: number | null;

  // Text
  color?: Color | null;
  fontSize?: number | null;
  fontWeight?: FontWeight | null;
  fontStyle?: 'normal' | 'italic' | null;
  fontFamily?: string | null;
  letterSpacing?: number | null;
  wordSpacing?: number | null;
  /** Line height as a multiple of the font size (Flutter `TextStyle.height`). */
  lineHeight?: number | null;
  /** Line height given in pixels (`line-height: 24px`). */
  lineHeightPx?: number | null;
  textAlign?: TextAlign | null;
  textDecoration?: TextDecoration | null;
  textDecorationColor?: Color | null;
  textDecorationStyle?: string | null;
  textDecorationThickness?: number | null;
  textOverflow?: TextOverflow | null;
  textTransform?: string | null;
  whiteSpace?: string | null;
  borderCollapse?: 'collapse' | 'separate' | null;
  borderSpacing?: number | null;
  verticalAlign?: string | null;
  writingMode?: string | null;
  wordBreak?: string | null;
  lineClamp?: number | null;

  // Effects
  boxShadow?: BoxShadow[] | null;
  textShadow?: TextShadow[] | null;
  transform?: Matrix4 | null;
  rotate?: number | null;
  scale?: number | null;
  scaleX?: number | null;
  scaleY?: number | null;
  translate?: Offset | null;
  transformOrigin?: Alignment | null;
  opacity?: number | null;
  visible?: boolean | null;
  visibility?: string | null;
  filter?: Filter | null;
  backdropFilter?: Filter | null;
  mixBlendMode?: string | null;

  // Interaction
  cursor?: string | null;
  pointerEvents?: string | null;
  userSelect?: string | null;
  touchAction?: string | null;

  // Media
  objectFit?: BoxFit | null;
  objectPosition?: Alignment | null;

  // Clipping / shape
  clipBehavior?: string | null;
  shape?: 'rectangle' | 'circle' | null;

  // Transitions and animation
  transitionDuration?: number | null; // ms
  transitionCurve?: string | null;
  transitionProperty?: string | null;
  transitionDelay?: number | null;
  animationName?: string | null;
  animationDuration?: number | null;
  animationTimingFunction?: string | null;
  animationDelay?: number | null;
  animationIterationCount?: number | null; // -1 = infinite
  animationDirection?: string | null;
  animationFillMode?: string | null;
  animationPlayState?: string | null;
  animateOnBuild?: boolean | null;
  staggerDelay?: number | null;
  staggerChildren?: number | null;
  animationFrom?: number | null;
  animationTo?: number | null;
  slideBegin?: Offset | null;
  slideEnd?: Offset | null;
  scaleBegin?: number | null;
  scaleEnd?: number | null;
  rotationBegin?: number | null;
  rotationEnd?: number | null;
  fadeBegin?: number | null;
  fadeEnd?: number | null;
  colorBegin?: Color | null;
  colorEnd?: Color | null;
  paddingBegin?: EdgeInsets | null;
  paddingEnd?: EdgeInsets | null;
  alignmentBegin?: Alignment | null;
  alignmentEnd?: Alignment | null;
  shimmerBaseColor?: Color | null;
  shimmerHighlightColor?: Color | null;
  animationAutoReverse?: boolean | null;
  animationRepeat?: boolean | null;
  keyframes?: Keyframe[] | null;
  gradientColors?: Color[] | null;
  gradientStops?: number[] | null;
}
