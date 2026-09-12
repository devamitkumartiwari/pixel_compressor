import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// An inline video player with tap-to-play/pause, a progress bar, and a
/// button to open the same video full-screen. Give it a [ValueKey] on the
/// file path at the call site so Flutter creates a fresh player (rather
/// than reusing state) whenever the underlying file changes.
class VideoPreviewPlayer extends StatefulWidget {
  const VideoPreviewPlayer({super.key, required this.file, this.height = 220});

  final File file;
  final double height;

  @override
  State<VideoPreviewPlayer> createState() => _VideoPreviewPlayerState();
}

class _VideoPreviewPlayerState extends State<VideoPreviewPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initialize = _controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  void _openFullScreen() {
    _controller.pause();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenVideo(file: widget.file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialize,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: widget.height,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
                GestureDetector(
                  onTap: _togglePlay,
                  child: AnimatedOpacity(
                    opacity: _controller.value.isPlaying ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                    onPressed: _openFullScreen,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.all(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FullScreenVideo extends StatefulWidget {
  const _FullScreenVideo({required this.file});

  final File file;

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initialize = _controller.initialize().then((_) {
      if (mounted) setState(() => _controller.play());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: FutureBuilder<void>(
          future: _initialize,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            return GestureDetector(
              onTap: () => setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              }),
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            );
          },
        ),
      ),
    );
  }
}
