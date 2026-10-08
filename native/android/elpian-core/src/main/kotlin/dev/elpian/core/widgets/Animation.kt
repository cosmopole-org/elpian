package dev.elpian.core.widgets

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.CSSStyle
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.M3
import dev.elpian.core.css.Offset
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.W
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.w

/**
 * Animation widgets (widgets/animation.ts) — ports of
 * flutter/lib/src/widgets/elpian_animated_*.dart, the explicit `*Transition`
 * widgets, `TweenAnimationBuilder`, `StaggeredAnimation`, `Shimmer`, `Pulse`
 * and `AnimatedGradient`. Every builder reads the same style fields and
 * defaults as its Flutter counterpart and lowers onto the animated render
 * objects in render/Animated.kt, which tick on the owner's frame clock.
 */

private val ZERO = EdgeInsets(0.0, 0.0, 0.0, 0.0)

private fun only(children: List<W>): W? = children.firstOrNull()

val animationWidgets: Map<String, WidgetBuilder> = linkedMapOf(
    // --------------------------------------------------------------------------
    // Implicit
    // --------------------------------------------------------------------------
    "AnimatedContainer" to { node, children, _ ->
        val s = node.style
        val duration = s?.transitionDuration ?: 200.0
        val curve = s?.transitionCurve
        var current: W? = only(children)
        // AnimatedContainer → Container composition with every layer animated.
        if (s?.padding != null || current != null) current = w("animatedPadding", mapOf("padding" to (s?.padding ?: ZERO), "duration" to duration, "curve" to curve), current ?: SHRINK)
        current = w("animatedDecorated", mapOf("decoration" to Decoration(color = s?.backgroundColor, radius = s?.borderRadius), "duration" to duration, "curve" to curve), current)
        current = w("animatedConstrained", mapOf("width" to s?.width, "height" to s?.height, "duration" to duration, "curve" to curve), current)
        s?.margin?.let { current = w("animatedPadding", mapOf("padding" to it, "duration" to duration, "curve" to curve), current) }
        current!!
    },
    "AnimatedOpacity" to { node, children, _ ->
        // Flutter's builder passes no curve (linear).
        w("animatedOpacity", mapOf("opacity" to (node.style?.opacity ?: 1.0), "duration" to (node.style?.transitionDuration ?: 200.0)), only(children))
    },
    "AnimatedCrossFade" to { node, children, _ ->
        val s = node.style
        val curve = s?.transitionCurve
        val first = children.getOrNull(0) ?: SHRINK
        val second = children.getOrNull(1) ?: SHRINK
        w(
            "animatedCrossFade",
            mapOf("showFirst" to (node.props["showFirst"] != false), "duration" to (s?.transitionDuration ?: 300.0), "curve" to curve),
            listOf(w("opacity", mapOf("opacity" to 1.0), first, "first"), w("opacity", mapOf("opacity" to 0.0), second, "second")),
        )
    },
    "AnimatedSwitcher" to { node, children, _ ->
        w(
            "animatedSwitcher",
            mapOf(
                "duration" to (node.style?.transitionDuration ?: 300.0),
                "transitionType" to dev.elpian.core.util.jsString(node.props["transitionType"] ?: "fade"),
                "curve" to node.style?.transitionCurve,
            ),
            if (children.isNotEmpty()) listOf(children[0]) else emptyList(),
        )
    },
    "AnimatedAlign" to { node, children, _ ->
        val s = node.style
        w(
            "animatedAlign",
            mapOf("alignment" to (s?.alignmentEnd ?: s?.alignment ?: Alignment(0.0, 0.0)), "duration" to (s?.transitionDuration ?: 300.0), "curve" to s?.transitionCurve),
            only(children),
        )
    },
    "AnimatedPadding" to { node, children, _ ->
        val s = node.style
        w("animatedPadding", mapOf("padding" to (s?.padding ?: ZERO), "duration" to (s?.transitionDuration ?: 300.0), "curve" to s?.transitionCurve), only(children))
    },
    "AnimatedPositioned" to { node, children, _ ->
        val s = node.style
        w(
            "animatedPositioned",
            mapOf(
                "top" to s?.top,
                "right" to s?.right,
                "bottom" to s?.bottom,
                "left" to s?.left,
                "width" to s?.width,
                "height" to s?.height,
                "duration" to (s?.transitionDuration ?: 300.0),
                "curve" to s?.transitionCurve,
            ),
            only(children) ?: SHRINK,
        )
    },
    "AnimatedScale" to { node, children, _ ->
        val s = node.style
        w("animatedTransform", mapOf("scale" to (s?.scale ?: 1.0), "alignment" to Alignment(0.0, 0.0), "duration" to (s?.transitionDuration ?: 300.0), "curve" to s?.transitionCurve), only(children))
    },
    "AnimatedRotation" to { node, children, _ ->
        val s = node.style
        w("animatedTransform", mapOf("turns" to (s?.rotate ?: 0.0) / 360, "alignment" to Alignment(0.0, 0.0), "duration" to (s?.transitionDuration ?: 300.0), "curve" to s?.transitionCurve), only(children))
    },
    "AnimatedSlide" to { node, children, _ ->
        val s = node.style
        val o = s?.slideEnd ?: Offset(0.0, 0.0)
        w("animatedTransform", mapOf("slide" to listOf(o.dx, o.dy), "alignment" to Alignment(-1.0, -1.0), "duration" to (s?.transitionDuration ?: 300.0), "curve" to s?.transitionCurve), only(children))
    },
    "AnimatedSize" to { node, children, _ ->
        val s = node.style
        w("animatedSize", mapOf("duration" to (s?.transitionDuration ?: 300.0), "curve" to s?.transitionCurve, "alignment" to Alignment(0.0, 0.0)), only(children))
    },
    "AnimatedDefaultTextStyle" to { node, children, _ ->
        val s = node.style
        w("animatedDefaultTextStyle", mapOf("style" to (createTextStyle(s) ?: TextStyle()), "duration" to (s?.transitionDuration ?: 300.0), "curve" to s?.transitionCurve), only(children) ?: SHRINK)
    },

    // --------------------------------------------------------------------------
    // Explicit
    // --------------------------------------------------------------------------
    "FadeTransition" to { node, children, _ ->
        val s = node.style
        transition("fade", s, s?.fadeBegin ?: 0.0, s?.fadeEnd ?: 1.0, only(children) ?: w("constrained"))
    },
    "SlideTransition" to { node, children, _ ->
        val s = node.style
        val b = s?.slideBegin ?: Offset(-1.0, 0.0)
        val e = s?.slideEnd ?: Offset(0.0, 0.0)
        transition("slide", s, listOf(b.dx, b.dy), listOf(e.dx, e.dy), only(children) ?: w("constrained"))
    },
    "ScaleTransition" to { node, children, _ ->
        val s = node.style
        transition("scale", s, s?.scaleBegin ?: 0.0, s?.scaleEnd ?: 1.0, only(children) ?: w("constrained"))
    },
    "RotationTransition" to { node, children, _ ->
        val s = node.style
        transition("rotation", s, s?.rotationBegin ?: 0.0, s?.rotationEnd ?: 1.0, only(children) ?: w("constrained"))
    },
    "SizeTransition" to { node, children, _ ->
        val s = node.style
        val t = transition("size", s, s?.animationFrom ?: 0.0, s?.animationTo ?: 1.0, only(children) ?: w("constrained"))
        t.p["axis"] = if (node.props["axis"] == "horizontal") "horizontal" else "vertical"
        t
    },

    // --------------------------------------------------------------------------
    // Custom
    // --------------------------------------------------------------------------
    "TweenAnimationBuilder" to { node, children, _ ->
        val s = node.style
        w(
            "transition",
            mapOf(
                "kind" to "tween",
                "tweenType" to dev.elpian.core.util.jsString(node.props["tweenType"] ?: "opacity"),
                "begin" to (s?.animationFrom ?: 0.0),
                "end" to (s?.animationTo ?: 1.0),
                "duration" to (s?.animationDuration ?: s?.transitionDuration ?: 300.0),
                "curve" to s?.transitionCurve,
            ),
            only(children) ?: w("constrained"),
        )
    },
    "StaggeredAnimation" to { node, children, _ ->
        val s = node.style
        w(
            "staggered",
            mapOf("duration" to (s?.animationDuration ?: 1000.0), "staggerDelay" to (s?.staggerDelay ?: 100.0), "curve" to (s?.transitionCurve ?: "easeOut")),
            children.mapIndexed { i, c -> w("staggerItem", emptyMap(), c, c.k ?: "stagger-$i") },
        )
    },
    "Shimmer" to { node, children, _ ->
        val s = node.style
        val child = only(children)
            // Flutter's placeholder bar: a sized box with a rounded (transparent)
            // decoration; the mask paints the sweep onto it.
            ?: w(
                "constrained",
                mapOf("width" to (s?.width ?: 200.0), "height" to (s?.height ?: 20.0)),
                w("decorated", mapOf("decoration" to Decoration(color = M3.surfaceContainerHighest, radius = s?.borderRadius ?: BorderRadius.all(4.0)))),
            )
        w(
            "shimmer",
            mapOf(
                "duration" to (s?.animationDuration ?: 1500.0),
                "baseColor" to (s?.shimmerBaseColor ?: 0xffe0e0e0.toInt()),
                "highlightColor" to (s?.shimmerHighlightColor ?: 0xfff5f5f5.toInt()),
                "blendMode" to "srcATop",
            ),
            child,
        )
    },
    "Pulse" to { node, children, _ ->
        val s = node.style
        w(
            "transition",
            mapOf("kind" to "pulse", "begin" to (s?.scaleBegin ?: 1.0), "end" to (s?.scaleEnd ?: 1.05), "duration" to (s?.animationDuration ?: 1000.0), "curve" to (s?.transitionCurve ?: "easeInOut")),
            only(children) ?: w("constrained"),
        )
    },
    "AnimatedGradient" to { node, children, _ ->
        val s = node.style
        val gradient = w(
            "animatedGradient",
            mapOf(
                "duration" to (s?.animationDuration ?: 2000.0),
                "colors" to (s?.gradientColors ?: listOf(0xff2196f3.toInt(), 0xff9c27b0.toInt(), 0xffe91e63.toInt(), 0xff2196f3.toInt())),
                "decoration" to Decoration(radius = s?.borderRadius),
            ),
            only(children),
        )
        // Container(width, height, decoration): no child → expands like Container.
        if (s?.width != null || s?.height != null) {
            w("constrained", mapOf("width" to s?.width, "height" to s?.height), gradient)
        } else if (children.isNotEmpty()) {
            gradient
        } else {
            w("limited", mapOf("maxWidth" to 0.0, "maxHeight" to 0.0), w("constrained", mapOf("minWidth" to Double.POSITIVE_INFINITY, "minHeight" to Double.POSITIVE_INFINITY), gradient))
        }
    },
)

private fun transition(kind: String, s: CSSStyle?, begin: Any?, end: Any?, child: W): W = w(
    "transition",
    mapOf(
        "kind" to kind,
        "begin" to begin,
        "end" to end,
        "duration" to (s?.animationDuration ?: s?.transitionDuration ?: 300.0),
        "curve" to s?.transitionCurve,
        "repeat" to (s?.animationRepeat ?: false),
        "autoReverse" to (s?.animationAutoReverse ?: false),
    ),
    child,
)
