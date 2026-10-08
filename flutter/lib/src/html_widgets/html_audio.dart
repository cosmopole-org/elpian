import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlAudio {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = _HtmlAudioPlayer(node: node);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}

class _HtmlAudioPlayer extends StatefulWidget {
  final ElpianNode node;

  const _HtmlAudioPlayer({required this.node});

  @override
  State<_HtmlAudioPlayer> createState() => _HtmlAudioPlayerState();
}

class _HtmlAudioPlayerState extends State<_HtmlAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isReady = false;
  String? _error;

  String get _src => widget.node.props['src'] as String? ?? '';
  bool get _autoplay => widget.node.props['autoplay'] == true;
  bool get _loop => widget.node.props['loop'] == true;
  bool get _muted => widget.node.props['muted'] == true;

  @override
  void initState() {
    super.initState();
    _attachListeners();
    _loadSource();
  }

  @override
  void didUpdateWidget(covariant _HtmlAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSrc = oldWidget.node.props['src'] as String? ?? '';
    if (oldSrc != _src) {
      _loadSource();
    }
  }

  void _attachListeners() {
    _player.durationStream.listen((value) {
      if (!mounted) return;
      setState(() {
        _duration = value ?? Duration.zero;
      });
    });

    _player.positionStream.listen((value) {
      if (!mounted) return;
      setState(() {
        _position = value;
      });
    });

    _player.playerStateStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _loadSource() async {
    setState(() {
      _error = null;
      _isReady = false;
      _duration = Duration.zero;
      _position = Duration.zero;
    });

    if (_src.isEmpty) {
      return;
    }

    try {
      if (_src.startsWith('http://') || _src.startsWith('https://')) {
        await _player.setUrl(_src);
      } else {
        await _player.setAsset(_src);
      }
      await _player.setLoopMode(_loop ? LoopMode.one : LoopMode.off);
      await _player.setVolume(_muted ? 0 : 1);

      if (_autoplay) {
        await _player.play();
      }

      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_src.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.audiotrack),
        title: Text('audio src is required'),
      );
    }

    if (_error != null) {
      return ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text('audio failed to load: $_error'),
      );
    }

    if (!_isReady) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      );
    }

    final isPlaying = _player.playing;
    final maxMs = _duration.inMilliseconds;
    final valueMs = _position.inMilliseconds.clamp(0, maxMs == 0 ? 1 : maxMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () async {
                if (isPlaying) {
                  await _player.pause();
                } else {
                  await _player.play();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () async {
                await _player.stop();
                await _player.seek(Duration.zero);
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
        Slider(
          min: 0,
          max: (maxMs == 0 ? 1 : maxMs).toDouble(),
          value: valueMs.toDouble(),
          onChanged: (value) {
            _player.seek(Duration(milliseconds: value.toInt()));
          },
        ),
      ],
    );
  }
}
