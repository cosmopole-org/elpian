import 'package:flutter/material.dart';

import '../canvas/canvas_context_store.dart';
import '../models/elpian_node.dart';

class ElpianCachedCanvas {
  static Widget build(ElpianNode node, List<Widget> children) {
    final contextId = node.props['contextId']?.toString() ?? node.props['id']?.toString();
    final width = _toDouble(node.props['width']) ?? node.style?.width;
    final height = _toDouble(node.props['height']) ?? node.style?.height;
    final backgroundColor = node.props['backgroundColor'] as Color?;

    if (contextId == null || contextId.isEmpty) {
      return const SizedBox.shrink();
    }

    final ctx = CanvasContextStore.instance.get(contextId);
    if (ctx != null && width != null && height != null) {
      ctx.setSize(width, height);
    }

    return CachedCanvasWidget(
      contextId: contextId,
      width: width,
      height: height,
      backgroundColor: backgroundColor ?? node.style?.backgroundColor,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class CachedCanvasWidget extends StatelessWidget {
  final String contextId;
  final double? width;
  final double? height;
  final Color? backgroundColor;

  const CachedCanvasWidget({
    super.key,
    required this.contextId,
    this.width,
    this.height,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final ctx = CanvasContextStore.instance.get(contextId);
    if (ctx == null) return const SizedBox.shrink();

    return ValueListenableBuilder<int>(
      valueListenable: ctx.version,
      builder: (_, version, ___) {
        final size = Size(width ?? ctx.width, height ?? ctx.height);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _CachedCanvasPainter(
                contextId: contextId,
                backgroundColor: backgroundColor,
                version: version,
              ),
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _CachedCanvasPainter extends CustomPainter {
  final String contextId;
  final Color? backgroundColor;
  final int version;

  _CachedCanvasPainter({
    required this.contextId,
    required this.backgroundColor,
    required this.version,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor != null) {
      final paint = Paint()..color = backgroundColor!;
      canvas.drawRect(Offset.zero & size, paint);
    }

    final ctx = CanvasContextStore.instance.get(contextId);
    if (ctx == null) return;

    final picture = ctx.getPicture();
    if (picture != null) {
      canvas.drawPicture(picture);
    }
  }

  @override
  bool shouldRepaint(_CachedCanvasPainter oldDelegate) {
    return oldDelegate.contextId != contextId ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.version != version;
  }
}
