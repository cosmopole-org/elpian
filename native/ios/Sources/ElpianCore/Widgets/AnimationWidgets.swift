import Foundation

/**
 * Animation widgets (widgets/animation.ts) — ports of
 * flutter/lib/src/widgets/elpian_animated_*.dart, the explicit `*Transition`
 * widgets, `TweenAnimationBuilder`, `StaggeredAnimation`, `Shimmer`, `Pulse`
 * and `AnimatedGradient`. Every builder reads the same style fields and
 * defaults as its Flutter counterpart and lowers onto the animated render
 * objects in Render/Animated.swift, which tick on the owner's frame clock.
 */

private let ZERO = EdgeInsets(top: 0, right: 0, bottom: 0, left: 0)

private func only(_ children: [W]) -> W? { children.first }

private func animatedContainer(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    let duration = s?.transitionDuration ?? 200
    let curve = s?.transitionCurve
    var current: W? = only(children)
    // AnimatedContainer → Container composition with every layer animated.
    if s?.padding != nil || current != nil {
        current = w("animatedPadding", ["padding": s?.padding ?? ZERO, "duration": duration, "curve": curve], child: current ?? SHRINK)
    }
    current = w("animatedDecorated", ["decoration": BoxDecoration(color: s?.backgroundColor, radius: s?.borderRadius), "duration": duration, "curve": curve], child: current)
    current = w("animatedConstrained", ["width": s?.width, "height": s?.height, "duration": duration, "curve": curve], child: current)
    if let m = s?.margin { current = w("animatedPadding", ["padding": m, "duration": duration, "curve": curve], child: current) }
    return current!
}

private func animatedCrossFade(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    let curve = s?.transitionCurve
    let firstChild = children.count > 0 ? children[0] : SHRINK
    let secondChild = children.count > 1 ? children[1] : SHRINK
    return w(
        "animatedCrossFade",
        ["showFirst": !node.props.isFalse("showFirst"), "duration": s?.transitionDuration ?? 300, "curve": curve],
        [w("opacity", ["opacity": 1.0], child: firstChild, "first"), w("opacity", ["opacity": 0.0], child: secondChild, "second")]
    )
}

private func animatedPositioned(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    return w(
        "animatedPositioned",
        [
            "top": s?.top,
            "right": s?.right,
            "bottom": s?.bottom,
            "left": s?.left,
            "width": s?.width,
            "height": s?.height,
            "duration": s?.transitionDuration ?? 300,
            "curve": s?.transitionCurve,
        ],
        child: only(children) ?? SHRINK
    )
}

private func tweenAnimationBuilder(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    return w(
        "transition",
        [
            "kind": "tween",
            "tweenType": jsString(node.props["tweenType"] ?? "opacity"),
            "begin": s?.animationFrom ?? 0,
            "end": s?.animationTo ?? 1,
            "duration": s?.animationDuration ?? s?.transitionDuration ?? 300,
            "curve": s?.transitionCurve,
        ],
        child: only(children) ?? w("constrained")
    )
}

private func shimmer(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    let child = only(children)
        // Flutter's placeholder bar: a sized box with a rounded (transparent)
        // decoration; the mask paints the sweep onto it.
        ?? w(
            "constrained",
            ["width": s?.width ?? 200, "height": s?.height ?? 20],
            child: w("decorated", ["decoration": BoxDecoration(color: M3.surfaceContainerHighest, radius: s?.borderRadius ?? BorderRadius.all(4))])
        )
    return w(
        "shimmer",
        [
            "duration": s?.animationDuration ?? 1500,
            "baseColor": s?.shimmerBaseColor ?? 0xffe0e0e0 as Color,
            "highlightColor": s?.shimmerHighlightColor ?? 0xfff5f5f5 as Color,
            "blendMode": "srcATop",
        ],
        child: child
    )
}

private func animatedGradient(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    let defaultColors: [Color] = [0xff2196f3, 0xff9c27b0, 0xffe91e63, 0xff2196f3]
    let gradient = w(
        "animatedGradient",
        [
            "duration": s?.animationDuration ?? 2000,
            "colors": s?.gradientColors ?? defaultColors,
            "decoration": BoxDecoration(radius: s?.borderRadius),
        ],
        child: only(children)
    )
    // Container(width, height, decoration): no child → expands like Container.
    if s?.width != nil || s?.height != nil {
        return w("constrained", ["width": s?.width, "height": s?.height], child: gradient)
    }
    if !children.isEmpty { return gradient }
    return w("limited", ["maxWidth": 0.0, "maxHeight": 0.0], child: w("constrained", ["minWidth": Double.infinity, "minHeight": Double.infinity], child: gradient))
}

/** The animation builders, in registration order. */
public let animationWidgets: [(String, WidgetBuilder)] = [
    // --------------------------------------------------------------------------
    // Implicit
    // --------------------------------------------------------------------------
    ("AnimatedContainer", animatedContainer),
    ("AnimatedOpacity", { node, children, _ in
        // Flutter's builder passes no curve (linear).
        w("animatedOpacity", ["opacity": node.style?.opacity ?? 1, "duration": node.style?.transitionDuration ?? 200], child: only(children))
    }),
    ("AnimatedCrossFade", animatedCrossFade),
    ("AnimatedSwitcher", { node, children, _ in
        w(
            "animatedSwitcher",
            [
                "duration": node.style?.transitionDuration ?? 300,
                "transitionType": jsString(node.props["transitionType"] ?? "fade"),
                "curve": node.style?.transitionCurve,
            ],
            children.isEmpty ? [] : [children[0]]
        )
    }),
    ("AnimatedAlign", { node, children, _ in
        let s = node.style
        return w(
            "animatedAlign",
            ["alignment": s?.alignmentEnd ?? s?.alignment ?? Alignment(x: 0, y: 0), "duration": s?.transitionDuration ?? 300, "curve": s?.transitionCurve],
            child: only(children)
        )
    }),
    ("AnimatedPadding", { node, children, _ in
        let s = node.style
        return w("animatedPadding", ["padding": s?.padding ?? ZERO, "duration": s?.transitionDuration ?? 300, "curve": s?.transitionCurve], child: only(children))
    }),
    ("AnimatedPositioned", animatedPositioned),
    ("AnimatedScale", { node, children, _ in
        let s = node.style
        return w(
            "animatedTransform",
            ["scale": s?.scale ?? 1, "alignment": Alignment(x: 0, y: 0), "duration": s?.transitionDuration ?? 300, "curve": s?.transitionCurve],
            child: only(children)
        )
    }),
    ("AnimatedRotation", { node, children, _ in
        let s = node.style
        return w(
            "animatedTransform",
            ["turns": (s?.rotate ?? 0) / 360, "alignment": Alignment(x: 0, y: 0), "duration": s?.transitionDuration ?? 300, "curve": s?.transitionCurve],
            child: only(children)
        )
    }),
    ("AnimatedSlide", { node, children, _ in
        let s = node.style
        let o = s?.slideEnd ?? Offset(dx: 0, dy: 0)
        return w(
            "animatedTransform",
            ["slide": [o.dx, o.dy], "alignment": Alignment(x: -1, y: -1), "duration": s?.transitionDuration ?? 300, "curve": s?.transitionCurve],
            child: only(children)
        )
    }),
    ("AnimatedSize", { node, children, _ in
        let s = node.style
        return w("animatedSize", ["duration": s?.transitionDuration ?? 300, "curve": s?.transitionCurve, "alignment": Alignment(x: 0, y: 0)], child: only(children))
    }),
    ("AnimatedDefaultTextStyle", { node, children, _ in
        let s = node.style
        return w(
            "animatedDefaultTextStyle",
            ["style": createTextStyle(s) ?? TextStyle(), "duration": s?.transitionDuration ?? 300, "curve": s?.transitionCurve],
            child: only(children) ?? SHRINK
        )
    }),

    // --------------------------------------------------------------------------
    // Explicit
    // --------------------------------------------------------------------------
    ("FadeTransition", { node, children, _ in
        let s = node.style
        return transition("fade", s, s?.fadeBegin ?? 0, s?.fadeEnd ?? 1, only(children) ?? w("constrained"))
    }),
    ("SlideTransition", { node, children, _ in
        let s = node.style
        let b = s?.slideBegin ?? Offset(dx: -1, dy: 0)
        let e = s?.slideEnd ?? Offset(dx: 0, dy: 0)
        return transition("slide", s, [b.dx, b.dy], [e.dx, e.dy], only(children) ?? w("constrained"))
    }),
    ("ScaleTransition", { node, children, _ in
        let s = node.style
        return transition("scale", s, s?.scaleBegin ?? 0, s?.scaleEnd ?? 1, only(children) ?? w("constrained"))
    }),
    ("RotationTransition", { node, children, _ in
        let s = node.style
        return transition("rotation", s, s?.rotationBegin ?? 0, s?.rotationEnd ?? 1, only(children) ?? w("constrained"))
    }),
    ("SizeTransition", { node, children, _ in
        let s = node.style
        let t = transition("size", s, s?.animationFrom ?? 0, s?.animationTo ?? 1, only(children) ?? w("constrained"))
        t.p["axis"] = node.props.s("axis") == "horizontal" ? "horizontal" : "vertical"
        return t
    }),

    // --------------------------------------------------------------------------
    // Custom
    // --------------------------------------------------------------------------
    ("TweenAnimationBuilder", tweenAnimationBuilder),
    ("StaggeredAnimation", { node, children, _ in
        let s = node.style
        return w(
            "staggered",
            ["duration": s?.animationDuration ?? 1000, "staggerDelay": s?.staggerDelay ?? 100, "curve": s?.transitionCurve ?? "easeOut"],
            children.enumerated().map { i, c in w("staggerItem", Props(), child: c, c.k ?? "stagger-\(i)") }
        )
    }),
    ("Shimmer", shimmer),
    ("Pulse", { node, children, _ in
        let s = node.style
        return w(
            "transition",
            ["kind": "pulse", "begin": s?.scaleBegin ?? 1, "end": s?.scaleEnd ?? 1.05, "duration": s?.animationDuration ?? 1000, "curve": s?.transitionCurve ?? "easeInOut"],
            child: only(children) ?? w("constrained")
        )
    }),
    ("AnimatedGradient", animatedGradient),
]

private func transition(_ kind: String, _ s: CSSStyle?, _ begin: Any?, _ end: Any?, _ child: W) -> W {
    w(
        "transition",
        [
            "kind": kind,
            "begin": begin,
            "end": end,
            "duration": s?.animationDuration ?? s?.transitionDuration ?? 300,
            "curve": s?.transitionCurve,
            "repeat": s?.animationRepeat ?? false,
            "autoReverse": s?.animationAutoReverse ?? false,
        ],
        child: child
    )
}
