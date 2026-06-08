import 'package:flutter/material.dart';
import '../models/css_style.dart';

class CSSProperties {
  /// Apply CSS styles to a widget using Container or other wrappers.
  ///
  /// [applyFlex] controls whether a `flex` style is wrapped here as a
  /// [Flexible]. Callers that add their own wrappers *around* the result (e.g.
  /// a tappable link wrapping it in a GestureDetector) must pass `false` and
  /// re-apply the flex as the outermost widget themselves — otherwise the
  /// [Flexible] is buried beneath a non-Flex widget and Flutter throws
  /// "Incorrect use of ParentDataWidget" when the element sits in a Row/Column.
  static Widget applyStyle(Widget child, CSSStyle? style, {bool applyFlex = true}) {
    if (style == null) return child;

    Widget result = child;

    // Apply opacity
    if (style.opacity != null && style.opacity! < 1.0) {
      result = Opacity(
        opacity: style.opacity!,
        child: result,
      );
    }

    // Apply transform
    if (style.transform != null || style.rotate != null || style.scale != null) {
      Matrix4 transform = style.transform ?? Matrix4.identity();
      
      if (style.rotate != null) {
        transform = Matrix4.rotationZ(style.rotate! * 3.14159 / 180);
      }
      
      if (style.scale != null) {
        transform = Matrix4.diagonal3Values(style.scale!, style.scale!, 1.0);
      }
      
      result = Transform(
        transform: transform,
        alignment: Alignment.center,
        child: result,
      );
    }

    // Apply visibility
    if (style.visible == false) {
      result = Visibility(
        visible: false,
        child: result,
      );
    }

    // Apply alignment
    if (style.alignment != null) {
      result = Align(
        alignment: style.alignment!,
        child: result,
      );
    }

    // Apply overflow (clip / scroll). Kept *inside* the size constraints below
    // so the ConstrainedBox/SizedBox supplies the bound the scroll view needs.
    //
    // A scroll view fed an unbounded constraint on its scroll axis throws in
    // Flutter, so we only make an axis scrollable when that axis is actually
    // bounded by an explicit or max size on the same node (the common case:
    // a panel/window with `maxHeight` + `overflowY: auto`). Otherwise `auto`
    // degrades to a clip, which is always safe.
    final overflowX = style.overflowX ?? style.overflow;
    final overflowY = style.overflowY ?? style.overflow;
    final boundedWidth = style.width != null || style.maxWidth != null;
    final boundedHeight = style.height != null || style.maxHeight != null;
    final scrollY = overflowY == Overflow.scroll && boundedHeight;
    final scrollX = overflowX == Overflow.scroll && boundedWidth;
    if (scrollY || scrollX) {
      result = SingleChildScrollView(
        scrollDirection: scrollY ? Axis.vertical : Axis.horizontal,
        child: result,
      );
    } else if (_clips(overflowX) || _clips(overflowY)) {
      // Clip to the rounded shape when a border radius is set, so a window/card
      // with `borderRadius` + `overflow:hidden` actually rounds its corners
      // (a plain ClipRect leaves square corners poking past the rounded box).
      result = style.borderRadius != null
          ? ClipRRect(borderRadius: style.borderRadius!, child: result)
          : ClipRect(child: result);
    }

    // Apply size constraints (before flex so Flexible is outermost). Percentage
    // axes are sized later by a FractionallySizedBox (see below), so the fixed
    // pixel value is suppressed here for any axis that carries a factor.
    final wf = style.widthFactor;
    final hf = style.heightFactor;
    final fixedWidth = wf == null ? style.width : null;
    final fixedHeight = hf == null ? style.height : null;
    if (fixedWidth != null || fixedHeight != null ||
        style.minWidth != null || style.maxWidth != null ||
        style.minHeight != null || style.maxHeight != null) {
      result = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: style.minWidth ?? 0.0,
          maxWidth: style.maxWidth ?? double.infinity,
          minHeight: style.minHeight ?? 0.0,
          maxHeight: style.maxHeight ?? double.infinity,
        ),
        child: SizedBox(
          width: fixedWidth,
          height: fixedHeight,
          child: result,
        ),
      );
    }

    // Apply Container for styling
    if (_needsContainer(style)) {
      result = Container(
        padding: style.padding,
        decoration: BoxDecoration(
          color: style.backgroundColor,
          gradient: style.gradient,
          border: style.border ?? (style.borderColor != null && style.borderWidth != null
              ? Border.all(
                  color: style.borderColor!,
                  width: style.borderWidth!,
                )
              : null),
          borderRadius: style.borderRadius,
          boxShadow: style.boxShadow,
        ),
        child: result,
      );
    }

    // Apply margin
    if (style.margin != null) {
      result = Padding(
        padding: style.margin!,
        child: result,
      );
    }

    // Apply percentage width/height relative to the PARENT (CSS semantics).
    //
    // Wrapped here — outside the decoration/size/margin — so the fraction
    // governs the whole painted box (a `width:60%` fill paints its gradient at
    // 60% of the parent, not 60% of the screen). Resolving `%` against the
    // viewport previously made fills span the full bar on desktop. We only
    // engage the FractionallySizedBox when the parent's matching axis is
    // bounded; otherwise the (viewport-resolved) pixel value is reinstated as a
    // safe fallback so the box never collapses or throws on an unbounded axis.
    if (wf != null || hf != null) {
      final inner = result;
      result = LayoutBuilder(
        builder: (context, constraints) {
          final useW = wf != null && constraints.maxWidth.isFinite;
          final useH = hf != null && constraints.maxHeight.isFinite;
          if (!useW && !useH) {
            return SizedBox(
              width: wf != null ? style.width : null,
              height: hf != null ? style.height : null,
              child: inner,
            );
          }
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: useW ? wf : null,
            heightFactor: useH ? hf : null,
            child: (!useW && wf != null)
                ? SizedBox(width: style.width, child: inner)
                : (!useH && hf != null)
                    ? SizedBox(height: style.height, child: inner)
                    : inner,
          );
        },
      );
    }

    // Wrap with implicit animations if transition properties are set
    if (style.transitionDuration != null && style.animateOnBuild == true) {
      result = _wrapWithAnimations(result, style);
    }

    // CSS `pointer-events: none` — make the element and its whole subtree
    // transparent to hit testing so taps fall through to whatever sits behind
    // it. Without this, decorative `position:absolute` overlays (the auth
    // screen's ambient gradient "blobs", any full-bleed sheen/scrim) painted
    // above the content silently swallow every tap meant for the controls
    // beneath them — text fields never focus and buttons/tabs only respond on
    // the sliver not covered by the overlay. The property was already parsed
    // into the style model but never applied.
    if (style.pointerEvents == 'none') {
      result = IgnorePointer(child: result);
    }

    // Apply flex LAST so Flexible is a direct child of Row/Column/Flex.
    // Skipped when the caller will wrap the result and re-apply flex outermost.
    // CSS `flex:<n>` grows to fill its share → TIGHT fit, so equal-width tiles
    // (resource pills), spacers (`flex:1` gaps in stat rows) and full-bleed
    // panes actually claim their space instead of collapsing to content width.
    if (applyFlex && style.flex != null) {
      result = Flexible(
        flex: style.flex!,
        fit: FlexFit.tight,
        child: result,
      );
    }

    return result;
  }

  /// Wrap widget with implicit animation wrappers based on style
  static Widget _wrapWithAnimations(Widget child, CSSStyle style) {
    Widget result = child;
    final duration = style.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = style.transitionCurve ?? Curves.linear;

    if (style.opacity != null) {
      result = AnimatedOpacity(
        opacity: style.opacity!,
        duration: duration,
        curve: curve,
        child: result,
      );
    }

    if (style.padding != null) {
      result = AnimatedPadding(
        padding: style.padding!,
        duration: duration,
        curve: curve,
        child: result,
      );
    }

    if (style.alignment != null) {
      result = AnimatedAlign(
        alignment: style.alignment!,
        duration: duration,
        curve: curve,
        child: result,
      );
    }

    return result;
  }

  /// Whether an overflow value should clip its content to the box.
  static bool _clips(Overflow? overflow) =>
      overflow == Overflow.hidden || overflow == Overflow.clip;

  static bool _needsContainer(CSSStyle style) {
    return style.padding != null ||
        style.backgroundColor != null ||
        style.gradient != null ||
        style.border != null ||
        style.borderRadius != null ||
        style.boxShadow != null ||
        style.borderColor != null;
  }

  /// Map a CSS `font-family` stack onto a font Flutter can actually render.
  ///
  /// CSS passes a comma-separated preference list ending in a generic family,
  /// e.g. `"Georgia, Cambria, 'Times New Roman', serif"`. Passing that whole
  /// string to [TextStyle.fontFamily] matches *nothing* (it is treated as one
  /// family name), so the engine fell back to the default sans for every serif
  /// or monospace run. We walk the list in order and resolve the first entry to
  /// a bundled face: serif-ish names → the bundled `serif` family, mono-ish
  /// names → `monospace`. Sans/unknown names resolve to `null` (Flutter's
  /// default sans, Roboto), mirroring a browser's own fallback for these stacks.
  static String? resolveFontFamily(String? family) {
    if (family == null) return null;
    for (final raw in family.split(',')) {
      final name = raw.trim().replaceAll(RegExp("^['\"]|['\"]\$"), '').toLowerCase();
      if (name.isEmpty) continue;
      if (_serifFamilies.contains(name) || name.contains('serif') && !name.contains('sans')) {
        return _serifFamily;
      }
      if (_monoFamilies.contains(name) || name.contains('mono')) {
        return _monoFamily;
      }
      if (_sansFamilies.contains(name) ||
          name.contains('sans') ||
          name == 'system-ui' ||
          name.startsWith('-apple') ||
          name == 'ui-sans-serif') {
        return null; // Flutter default sans (Roboto)
      }
      // A concrete, unrecognised family name: hand it to Flutter as-is (it may
      // be bundled by the host app); keep scanning only if it is clearly empty.
      return raw.trim().replaceAll(RegExp("^['\"]|['\"]\$"), '');
    }
    return null;
  }

  // Fonts declared in this package are exposed under a `packages/<pkg>/` family
  // prefix (see the generated FontManifest), so callers — even inside the
  // package — must reference the prefixed name.
  static const String _serifFamily = 'packages/elpian_ui/serif';
  static const String _monoFamily = 'packages/elpian_ui/monospace';

  static const Set<String> _serifFamilies = {
    'serif', 'georgia', 'times', 'times new roman', 'cambria', 'garamond',
    'cinzel', 'playfair display', 'merriweather', 'crimson', 'crimson pro',
    'pt serif', 'noto serif', 'liberation serif', 'roboto serif',
  };
  static const Set<String> _monoFamilies = {
    'monospace', 'courier', 'courier new', 'consolas', 'menlo', 'monaco',
    'roboto mono', 'sf mono', 'source code pro', 'fira code', 'jetbrains mono',
    'liberation mono', 'ui-monospace',
  };
  static const Set<String> _sansFamilies = {
    'sans-serif', 'arial', 'helvetica', 'helvetica neue', 'roboto', 'inter',
    'segoe ui', 'verdana', 'tahoma', 'noto sans', 'liberation sans', 'ubuntu',
  };

  /// Create a TextStyle from CSS style
  static TextStyle? createTextStyle(CSSStyle? style) {
    if (style == null) return null;

    return TextStyle(
      color: style.color,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      fontFamily: resolveFontFamily(style.fontFamily),
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      height: style.lineHeight,
      decoration: style.textDecoration,
      shadows: style.textShadow,
    );
  }

  static const _mainAxisAlignmentMap = <String, MainAxisAlignment>{
    'center': MainAxisAlignment.center,
    'flex-start': MainAxisAlignment.start,
    'start': MainAxisAlignment.start,
    'flex-end': MainAxisAlignment.end,
    'end': MainAxisAlignment.end,
    'space-between': MainAxisAlignment.spaceBetween,
    'space-around': MainAxisAlignment.spaceAround,
    'space-evenly': MainAxisAlignment.spaceEvenly,
  };

  /// Get main axis alignment from CSS justifyContent
  static MainAxisAlignment getMainAxisAlignment(String? justifyContent) {
    return _mainAxisAlignmentMap[justifyContent?.toLowerCase()] ?? MainAxisAlignment.start;
  }

  static const _crossAxisAlignmentMap = <String, CrossAxisAlignment>{
    'center': CrossAxisAlignment.center,
    'flex-start': CrossAxisAlignment.start,
    'start': CrossAxisAlignment.start,
    'flex-end': CrossAxisAlignment.end,
    'end': CrossAxisAlignment.end,
    'stretch': CrossAxisAlignment.stretch,
    'baseline': CrossAxisAlignment.baseline,
  };

  /// Get cross axis alignment from CSS alignItems
  static CrossAxisAlignment getCrossAxisAlignment(String? alignItems) {
    return _crossAxisAlignmentMap[alignItems?.toLowerCase()] ?? CrossAxisAlignment.start;
  }
}
