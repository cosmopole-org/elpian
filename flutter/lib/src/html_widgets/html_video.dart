import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlVideo {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = _HtmlVideoPlayer(node: node);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}

class _HtmlVideoPlayer extends StatefulWidget {
  final ElpianNode node;

  const _HtmlVideoPlayer({required this.node});

  @override
  State<_HtmlVideoPlayer> createState() => _HtmlVideoPlayerState();
}

class _HtmlVideoPlayerState extends State<_HtmlVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;

  String get _src => widget.node.props['src'] as String? ?? '';
  bool get _autoplay => widget.node.props['autoplay'] == true;
  bool get _loop => widget.node.props['loop'] == true;
  bool get _muted => widget.node.props['muted'] == true;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant _HtmlVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSrc = oldWidget.node.props['src'] as String? ?? '';
    if (oldSrc != _src) {
      _disposeController();
      _initController();
    }
  }

  void _initController() {
    if (_src.isEmpty) {
      return;
    }

    final controller = _src.startsWith('http://') || _src.startsWith('https://')
        ? VideoPlayerController.networkUrl(Uri.parse(_src))
        : VideoPlayerController.asset(_src);

    _controller = controller;
    _initializeFuture = controller.initialize().then((_) async {
      await controller.setLooping(_loop);
      await controller.setVolume(_muted ? 0 : 1);
      if (_autoplay) {
        await controller.play();
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _initializeFuture = null;
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_src.isEmpty || controller == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'video src is required',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: Text(
                'video failed to load: ${snapshot.error}',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? (16 / 9)
                    : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  onPressed: () {
                    setState(() {
                      controller.value.isPlaying
                          ? controller.pause()
                          : controller.play();
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    _src,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
