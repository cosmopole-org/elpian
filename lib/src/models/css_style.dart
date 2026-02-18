import 'package:flutter/material.dart';

enum Overflow {
  visible,
  clip,
}

class CSSStyle {
  // Layout Properties
  final double? width;
  final double? height;
  final double? minWidth;
  final double? maxWidth;
  final double? minHeight;
  final double? maxHeight;

  // Spacing
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final EdgeInsets? paddingTop;
  final EdgeInsets? paddingRight;
  final EdgeInsets? paddingBottom;
  final EdgeInsets? paddingLeft;
  final EdgeInsets? marginTop;
  final EdgeInsets? marginRight;
  final EdgeInsets? marginBottom;
  final EdgeInsets? marginLeft;

  // Positioning
  final AlignmentGeometry? alignment;
  final String? position; // relative, absolute, fixed, sticky
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final double? zIndex;

  // Display & Overflow
  final String? display; // flex, block, inline, inline-block, grid, none
  final String? flexDirection; // row, column, row-reverse, column-reverse
  final String? justifyContent;
  final String? alignItems;
  final String? alignContent;
  final String? alignSelf;
  final int? flex;
  final int? flexGrow;
  final int? flexShrink;
  final String? flexBasis;
  final Overflow? overflow;
  final Overflow? overflowX;
  final Overflow? overflowY;

  // Grid Properties
  final String? gridTemplateColumns;
  final String? gridTemplateRows;
  final String? gridTemplateAreas;
  final String? gridAutoColumns;
  final String? gridAutoRows;
  final String? gridAutoFlow;
  final double? gridColumnGap;
  final double? gridRowGap;
  final double? gridGap;
  final String? gridColumn;
  final String? gridRow;
  final String? gridArea;
  final String? justifyItems;
  final String? justifySelf;

  // Background
  final Color? backgroundColor;
  final String? backgroundImage;
  final BoxFit? backgroundSize;
  final AlignmentGeometry? backgroundPosition;
  final String? backgroundRepeat;
  final String? backgroundAttachment;
  final String? backgroundClip;
  final String? backgroundOrigin;
  final Gradient? gradient;
  final List<Color>? gradientColors;
  final List<double>? gradientStops;

  // Border
  final Border? border;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final double? borderWidth;
  final String? borderStyle;
  final BorderSide? borderTop;
  final BorderSide? borderRight;
  final BorderSide? borderBottom;
  final BorderSide? borderLeft;
  final double? borderTopLeftRadius;
  final double? borderTopRightRadius;
  final double? borderBottomLeftRadius;
  final double? borderBottomRightRadius;

  // Outline
  final Color? outlineColor;
  final double? outlineWidth;
  final String? outlineStyle;
  final double? outlineOffset;

  // Text Properties
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final String? fontFamily;
  final double? letterSpacing;
  final double? wordSpacing;
  final double? lineHeight;
  final TextAlign? textAlign;
  final TextDecoration? textDecoration;
  final Color? textDecorationColor;
  final TextDecorationStyle? textDecorationStyle;
  final double? textDecorationThickness;
  final TextOverflow? textOverflow;
  final String? textTransform;
  final String? whiteSpace;
  final TextBaseline? textBaseline;
  final String? verticalAlign;
  final String? writingMode;
  final String? textOrientation;

  // Shadow
  final List<BoxShadow>? boxShadow;
  final List<Shadow>? textShadow;
  final Shadow? dropShadow;

  // Transform
  final Matrix4? transform;
  final double? rotate;
  final double? rotateX;
  final double? rotateY;
  final double? rotateZ;
  final double? scale;
  final double? scaleX;
  final double? scaleY;
  final Offset? translate;
  final double? translateX;
  final double? translateY;
  final double? skewX;
  final double? skewY;
  final String? transformOrigin;
  final String? transformStyle;
  final String? perspective;
  final String? perspectiveOrigin;
  final String? backfaceVisibility;

  // Opacity & Visibility
  final double? opacity;
  final bool? visible;
  final String? visibility;

  // Cursor & Interaction
  final String? cursor;
  final String? pointerEvents;
  final String? userSelect;
  final String? touchAction;

  // Flex-specific
  final double? gap;
  final double? rowGap;
  final double? columnGap;
  final String? flexWrap;
  final int? order;

  // Box Model
  final String? boxSizing;
  final String? objectFit;
  final String? objectPosition;

  // Clipping & Masking
  final Clip? clipBehavior;
  final String? clipPath;
  final BoxShape? shape;

  // Filter & Backdrop
  final double? blur;
  final double? brightness;
  final double? contrast;
  final double? grayscale;
  final double? hueRotate;
  final double? invert;
  final double? saturate;
  final double? sepia;
  final Color? backdropColor;
  final double? backdropBlur;

  // Animation & Transition
  final Duration? transitionDuration;
  final Curve? transitionCurve;
  final String? transitionProperty;
  final Duration? transitionDelay;
  final String? animationName;
  final Duration? animationDuration;
  final String? animationTimingFunction;
  final Duration? animationDelay;
  final int? animationIterationCount;
  final String? animationDirection;
  final String? animationFillMode;
  final String? animationPlayState;

  // Advanced Animation Properties
  final bool? animateOnBuild;
  final Duration? staggerDelay;
  final int? staggerChildren;
  final double? animationFrom;
  final double? animationTo;
  final Offset? slideBegin;
  final Offset? slideEnd;
  final double? scaleBegin;
  final double? scaleEnd;
  final double? rotationBegin;
  final double? rotationEnd;
  final double? fadeBegin;
  final double? fadeEnd;
  final Color? colorBegin;
  final Color? colorEnd;
  final EdgeInsets? paddingBegin;
  final EdgeInsets? paddingEnd;
  final AlignmentGeometry? alignmentBegin;
  final AlignmentGeometry? alignmentEnd;
  final Color? shimmerBaseColor;
  final Color? shimmerHighlightColor;
  final bool? animationAutoReverse;
  final bool? animationRepeat;
  final List<Map<String, dynamic>>? keyframes;

  // Content & Lists
  final String? content;
  final String? listStyleType;
  final String? listStylePosition;
  final String? listStyleImage;

  // Table
  final String? tableLayout;
  final String? borderCollapse;
  final double? borderSpacing;
  final String? captionSide;
  final String? emptyCells;

  // Miscellaneous
  final String? resize;
  final String? float;
  final String? clear;
  final int? tabSize;
  final String? direction;
  final String? unicodeBidi;

  const CSSStyle({
    this.width,
    this.height,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.padding,
    this.margin,
    this.paddingTop,
    this.paddingRight,
    this.paddingBottom,
    this.paddingLeft,
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
    this.alignment,
    this.position,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.zIndex,
    this.display,
    this.flexDirection,
    this.justifyContent,
    this.alignItems,
    this.alignContent,
    this.alignSelf,
    this.flex,
    this.flexGrow,
    this.flexShrink,
    this.flexBasis,
    this.overflow,
    this.overflowX,
    this.overflowY,
    this.gridTemplateColumns,
    this.gridTemplateRows,
    this.gridTemplateAreas,
    this.gridAutoColumns,
    this.gridAutoRows,
    this.gridAutoFlow,
    this.gridColumnGap,
    this.gridRowGap,
    this.gridGap,
    this.gridColumn,
    this.gridRow,
    this.gridArea,
    this.justifyItems,
    this.justifySelf,
    this.backgroundColor,
    this.backgroundImage,
    this.backgroundSize,
    this.backgroundPosition,
    this.backgroundRepeat,
    this.backgroundAttachment,
    this.backgroundClip,
    this.backgroundOrigin,
    this.gradient,
    this.gradientColors,
    this.gradientStops,
    this.border,
    this.borderRadius,
    this.borderColor,
    this.borderWidth,
    this.borderStyle,
    this.borderTop,
    this.borderRight,
    this.borderBottom,
    this.borderLeft,
    this.borderTopLeftRadius,
    this.borderTopRightRadius,
    this.borderBottomLeftRadius,
    this.borderBottomRightRadius,
    this.outlineColor,
    this.outlineWidth,
    this.outlineStyle,
    this.outlineOffset,
    this.color,
    this.fontSize,
    this.fontWeight,
    this.fontStyle,
    this.fontFamily,
    this.letterSpacing,
    this.wordSpacing,
    this.lineHeight,
    this.textAlign,
    this.textDecoration,
    this.textDecorationColor,
    this.textDecorationStyle,
    this.textDecorationThickness,
    this.textOverflow,
    this.textTransform,
    this.whiteSpace,
    this.textBaseline,
    this.verticalAlign,
    this.writingMode,
    this.textOrientation,
    this.boxShadow,
    this.textShadow,
    this.dropShadow,
    this.transform,
    this.rotate,
    this.rotateX,
    this.rotateY,
    this.rotateZ,
    this.scale,
    this.scaleX,
    this.scaleY,
    this.translate,
    this.translateX,
    this.translateY,
    this.skewX,
    this.skewY,
    this.transformOrigin,
    this.transformStyle,
    this.perspective,
    this.perspectiveOrigin,
    this.backfaceVisibility,
    this.opacity,
    this.visible,
    this.visibility,
    this.cursor,
    this.pointerEvents,
    this.userSelect,
    this.touchAction,
    this.gap,
    this.rowGap,
    this.columnGap,
    this.flexWrap,
    this.order,
    this.boxSizing,
    this.objectFit,
    this.objectPosition,
    this.clipBehavior,
    this.clipPath,
    this.shape,
    this.blur,
    this.brightness,
    this.contrast,
    this.grayscale,
    this.hueRotate,
    this.invert,
    this.saturate,
    this.sepia,
    this.backdropColor,
    this.backdropBlur,
    this.transitionDuration,
    this.transitionCurve,
    this.transitionProperty,
    this.transitionDelay,
    this.animationName,
    this.animationDuration,
    this.animationTimingFunction,
    this.animationDelay,
    this.animationIterationCount,
    this.animationDirection,
    this.animationFillMode,
    this.animationPlayState,
    this.animateOnBuild,
    this.staggerDelay,
    this.staggerChildren,
    this.animationFrom,
    this.animationTo,
    this.slideBegin,
    this.slideEnd,
    this.scaleBegin,
    this.scaleEnd,
    this.rotationBegin,
    this.rotationEnd,
    this.fadeBegin,
    this.fadeEnd,
    this.colorBegin,
    this.colorEnd,
    this.paddingBegin,
    this.paddingEnd,
    this.alignmentBegin,
    this.alignmentEnd,
    this.shimmerBaseColor,
    this.shimmerHighlightColor,
    this.animationAutoReverse,
    this.animationRepeat,
    this.keyframes,
    this.content,
    this.listStyleType,
    this.listStylePosition,
    this.listStyleImage,
    this.tableLayout,
    this.borderCollapse,
    this.borderSpacing,
    this.captionSide,
    this.emptyCells,
    this.resize,
    this.float,
    this.clear,
    this.tabSize,
    this.direction,
    this.unicodeBidi,
  });

  CSSStyle copyWith({
    double? width,
    double? height,
    double? minWidth,
    double? maxWidth,
    double? minHeight,
    double? maxHeight,
    EdgeInsets? padding,
    EdgeInsets? margin,
    AlignmentGeometry? alignment,
    String? position,
    double? top,
    double? right,
    double? bottom,
    double? left,
    double? zIndex,
    String? display,
    String? flexDirection,
    String? justifyContent,
    String? alignItems,
    int? flex,
    Overflow? overflow,
    Color? backgroundColor,
    String? backgroundImage,
    BoxFit? backgroundSize,
    AlignmentGeometry? backgroundPosition,
    Gradient? gradient,
    Border? border,
    BorderRadius? borderRadius,
    Color? borderColor,
    double? borderWidth,
    String? borderStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    String? fontFamily,
    double? letterSpacing,
    double? wordSpacing,
    double? lineHeight,
    TextAlign? textAlign,
    TextDecoration? textDecoration,
    TextOverflow? textOverflow,
    String? textTransform,
    List<BoxShadow>? boxShadow,
    List<Shadow>? textShadow,
    Matrix4? transform,
    double? rotate,
    double? scale,
    Offset? translate,
    double? opacity,
    bool? visible,
    String? cursor,
    String? pointerEvents,
    double? gap,
    String? flexWrap,
    Duration? transitionDuration,
    Curve? transitionCurve,
    Duration? animationDuration,
    Curve? transitionCurveOverride,
    String? animationName,
    Duration? animationDelay,
    int? animationIterationCount,
    String? animationDirection,
    String? animationFillMode,
    String? animationPlayState,
    bool? animateOnBuild,
    Duration? staggerDelay,
    int? staggerChildren,
    double? animationFrom,
    double? animationTo,
    Offset? slideBegin,
    Offset? slideEnd,
    double? scaleBegin,
    double? scaleEnd,
    double? rotationBegin,
    double? rotationEnd,
    double? fadeBegin,
    double? fadeEnd,
    Color? colorBegin,
    Color? colorEnd,
    EdgeInsets? paddingBegin,
    EdgeInsets? paddingEnd,
    AlignmentGeometry? alignmentBegin,
    AlignmentGeometry? alignmentEnd,
    Color? shimmerBaseColor,
    Color? shimmerHighlightColor,
    bool? animationAutoReverse,
    bool? animationRepeat,
    List<Map<String, dynamic>>? keyframes,
  }) {
    return CSSStyle(
      width: width ?? this.width,
      height: height ?? this.height,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      minHeight: minHeight ?? this.minHeight,
      maxHeight: maxHeight ?? this.maxHeight,
      padding: padding ?? this.padding,
      margin: margin ?? this.margin,
      alignment: alignment ?? this.alignment,
      position: position ?? this.position,
      top: top ?? this.top,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
      left: left ?? this.left,
      zIndex: zIndex ?? this.zIndex,
      display: display ?? this.display,
      flexDirection: flexDirection ?? this.flexDirection,
      justifyContent: justifyContent ?? this.justifyContent,
      alignItems: alignItems ?? this.alignItems,
      flex: flex ?? this.flex,
      overflow: overflow ?? this.overflow,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      backgroundSize: backgroundSize ?? this.backgroundSize,
      backgroundPosition: backgroundPosition ?? this.backgroundPosition,
      gradient: gradient ?? this.gradient,
      border: border ?? this.border,
      borderRadius: borderRadius ?? this.borderRadius,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      borderStyle: borderStyle ?? this.borderStyle,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      fontFamily: fontFamily ?? this.fontFamily,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      textAlign: textAlign ?? this.textAlign,
      textDecoration: textDecoration ?? this.textDecoration,
      textOverflow: textOverflow ?? this.textOverflow,
      textTransform: textTransform ?? this.textTransform,
      boxShadow: boxShadow ?? this.boxShadow,
      textShadow: textShadow ?? this.textShadow,
      transform: transform ?? this.transform,
      rotate: rotate ?? this.rotate,
      scale: scale ?? this.scale,
      translate: translate ?? this.translate,
      opacity: opacity ?? this.opacity,
      visible: visible ?? this.visible,
      cursor: cursor ?? this.cursor,
      pointerEvents: pointerEvents ?? this.pointerEvents,
      gap: gap ?? this.gap,
      flexWrap: flexWrap ?? this.flexWrap,
      transitionDuration: transitionDuration ?? this.transitionDuration,
      transitionCurve: transitionCurve ?? this.transitionCurve,
      animationDuration: animationDuration ?? this.animationDuration,
      animationName: animationName ?? this.animationName,
      animationDelay: animationDelay ?? this.animationDelay,
      animationIterationCount: animationIterationCount ?? this.animationIterationCount,
      animationDirection: animationDirection ?? this.animationDirection,
      animationFillMode: animationFillMode ?? this.animationFillMode,
      animationPlayState: animationPlayState ?? this.animationPlayState,
      animateOnBuild: animateOnBuild ?? this.animateOnBuild,
      staggerDelay: staggerDelay ?? this.staggerDelay,
      staggerChildren: staggerChildren ?? this.staggerChildren,
      animationFrom: animationFrom ?? this.animationFrom,
      animationTo: animationTo ?? this.animationTo,
      slideBegin: slideBegin ?? this.slideBegin,
      slideEnd: slideEnd ?? this.slideEnd,
      scaleBegin: scaleBegin ?? this.scaleBegin,
      scaleEnd: scaleEnd ?? this.scaleEnd,
      rotationBegin: rotationBegin ?? this.rotationBegin,
      rotationEnd: rotationEnd ?? this.rotationEnd,
      fadeBegin: fadeBegin ?? this.fadeBegin,
      fadeEnd: fadeEnd ?? this.fadeEnd,
      colorBegin: colorBegin ?? this.colorBegin,
      colorEnd: colorEnd ?? this.colorEnd,
      paddingBegin: paddingBegin ?? this.paddingBegin,
      paddingEnd: paddingEnd ?? this.paddingEnd,
      alignmentBegin: alignmentBegin ?? this.alignmentBegin,
      alignmentEnd: alignmentEnd ?? this.alignmentEnd,
      shimmerBaseColor: shimmerBaseColor ?? this.shimmerBaseColor,
      shimmerHighlightColor: shimmerHighlightColor ?? this.shimmerHighlightColor,
      animationAutoReverse: animationAutoReverse ?? this.animationAutoReverse,
      animationRepeat: animationRepeat ?? this.animationRepeat,
      keyframes: keyframes ?? this.keyframes,
    );
  }
}
