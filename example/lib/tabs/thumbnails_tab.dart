import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../widgets/widgets.dart';

enum _Mode() {
  bytes,
  file,
}

class const _Frame(
  this.position, {
  this.bytes,
  this.path,
  this.failed = false,
}) {
  /// Milliseconds, or -1 for the platform default frame.
  final int position;
  final Uint8List? bytes;
  final String? path;
  final bool failed;
}

/// `thumbnailBytes` / `thumbnailFile` at evenly spaced positions.
class const ThumbnailsTab({super.key}) extends StatefulWidget {
  @override
  State<ThumbnailsTab> createState() => _ThumbnailsTabState();
}

class _ThumbnailsTabState()
    extends State<ThumbnailsTab>
    with AutomaticKeepAliveClientMixin {
  String? _path;
  PixelMediaInfo? _info;

  double _count = 6;
  double _quality = 75;
  int _maxSize = 512;
  _Mode _mode = _Mode.bytes;

  bool _busy = false;
  List<int> _positions = const [];
  final Map<int, _Frame> _frames = {};
  Duration? _elapsed;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pick() async {
    final path = await pickVideo(context);
    if (path == null || !mounted) return;
    setState(() {
      _path = path;
      _info = null;
      _frames.clear();
      _positions = const [];
      _error = null;
    });
    try {
      final info = await PixelVideoCompressor.readMediaInfo(path);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) {
        setState(() => _error = ExampleError("Couldn't read this video: $e"));
      }
    }
  }

  Future<void> _generate() async {
    final path = _path;
    if (path == null) return;
    HapticFeedback.lightImpact();
    final durationMs = (_info?.duration ?? 0).round();
    final count = _count.round();
    final positions = durationMs <= 0
        ? const [-1]
        : [
            for (var i = 0; i < count; i++)
              ((i + 0.5) / count * durationMs).round(),
          ];
    setState(() {
      _busy = true;
      _error = null;
      _positions = positions;
      _frames.clear();
    });
    final stopwatch = Stopwatch()..start();
    for (final position in positions) {
      _Frame frame;
      try {
        if (_mode == _Mode.bytes) {
          final bytes = await PixelVideoCompressor.thumbnailBytes(
            path,
            quality: _quality.round(),
            position: position,
            maxSize: _maxSize,
          );
          frame = bytes == null
              ? _Frame(position, failed: true)
              : _Frame(position, bytes: bytes);
        } else {
          final file = await PixelVideoCompressor.thumbnailFile(
            path,
            quality: _quality.round(),
            position: position,
            maxSize: _maxSize,
          );
          frame = _Frame(
            position,
            bytes: await file.readAsBytes(),
            path: file.path,
          );
        }
      } catch (_) {
        frame = _Frame(position, failed: true);
      }
      if (!mounted) return;
      setState(() => _frames[position] = frame);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _elapsed = stopwatch.elapsed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const header = HeroHeader(
      icon: Icons.view_carousel_rounded,
      title: 'Thumbnails',
      subtitle: 'JPEG frames at exact positions, as bytes or files',
    );
    if (!PlatformSupport.video) {
      return const FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.videocam_off_rounded,
          title: 'Not available on the web',
          message: 'Video thumbnails run on Android, iOS and macOS.',
        ),
      );
    }
    final path = _path;
    if (path == null) {
      return FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.photo_library_outlined,
          title: 'Pick a video',
          message: 'Grab a strip of frames spread across its duration.',
          actions: [
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add video'),
            ),
          ],
        ),
      );
    }

    final info = _info;
    return FeatureLayout(
      header: header,
      preview: [
        SourceCard(
          title: path.split(Platform.pathSeparator).last,
          onChange: _busy ? null : _pick,
          chips: [
            StatChip(
              icon: Icons.sd_storage_rounded,
              label: formatBytes(fileSize(path)),
            ),
            if (info != null) ...[
              StatChip(
                icon: Icons.aspect_ratio_rounded,
                label: '${info.width} × ${info.height}',
              ),
              StatChip(
                icon: Icons.schedule_rounded,
                label: formatDuration(
                  Duration(milliseconds: (info.duration ?? 0).round()),
                ),
              ),
            ],
          ],
        ),
      ],
      options: [
        OptionCard(
          title: 'Frames',
          icon: Icons.grid_view_rounded,
          children: [
            LabeledSlider(
              label: 'Number of frames',
              valueLabel: '${_count.round()}',
              value: _count,
              min: 1,
              max: 12,
              divisions: 11,
              onChanged: _busy ? null : (v) => setState(() => _count = v),
            ),
            LabeledSlider(
              label: 'JPEG quality',
              valueLabel: '${_quality.round()}',
              value: _quality,
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: _busy ? null : (v) => setState(() => _quality = v),
            ),
            OptionSegmented<int>(
              label: 'maxSize (longest side)',
              selected: _maxSize,
              choices: const [
                Choice(256, '256'),
                Choice(512, '512'),
                Choice(1024, '1024'),
              ],
              onChanged: _busy ? null : (v) => setState(() => _maxSize = v),
            ),
            OptionSegmented<_Mode>(
              label: 'Return',
              selected: _mode,
              choices: const [
                Choice(_Mode.bytes, 'thumbnailBytes'),
                Choice(_Mode.file, 'thumbnailFile'),
              ],
              onChanged: _busy ? null : (v) => setState(() => _mode = v),
            ),
          ],
        ),
      ],
      result: _resultView(),
      actions: SizedBox(
        width: double.infinity,
        child: BusyButton(
          label: _busy
              ? '${_frames.length} of ${_positions.length}'
              : 'Generate thumbnails',
          icon: Icons.auto_awesome_motion_rounded,
          busy: _busy,
          onPressed: _generate,
        ),
      ),
    );
  }

  Widget? _resultView() {
    final error = _error;
    if (error != null) return ErrorBanner(key: ValueKey(error), error: error);
    if (_positions.isEmpty) return null;
    final failed = _frames.values.where((f) => f.failed).length;
    return ResultCard(
      key: ValueKey(_positions),
      title: _busy
          ? 'Extracting frames…'
          : failed == 0
          ? '${_positions.length} frames'
          : '${_positions.length - failed} frames, $failed failed',
      icon: _busy ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 150).floor().clamp(2, 4);
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Insets.sm,
              crossAxisSpacing: Insets.sm,
              childAspectRatio: 1,
              children: [
                for (final p in _positions)
                  _FrameTile(position: p, frame: _frames[p]),
              ],
            );
          },
        ),
        if (!_busy)
          StatChips([
            if (_elapsed case final elapsed?)
              StatChip(
                icon: Icons.timer_outlined,
                label: formatDuration(elapsed),
              ),
            StatChip(
              icon: Icons.code_rounded,
              label: _mode == _Mode.bytes ? 'thumbnailBytes' : 'thumbnailFile',
            ),
          ]),
      ],
    );
  }
}

class const _FrameTile({required this.position, required this.frame})
    extends StatelessWidget {
  final int position;
  final _Frame? frame;

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    final label = position < 0
        ? 'default'
        : formatTimestamp(Duration(milliseconds: position));
    final Widget body;
    if (frame == null) {
      body = const ShimmerBox(height: double.infinity, radius: 12);
    } else if (frame.failed || frame.bytes == null) {
      final scheme = Theme.of(context).colorScheme;
      body = Container(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: .circular(12),
        ),
        child: Icon(
          Icons.broken_image_outlined,
          color: scheme.onErrorContainer,
        ),
      );
    } else {
      body = ImagePreview(
        bytes: frame.bytes!,
        height: double.infinity,
        fit: .cover,
        label: label,
      );
    }
    return Tooltip(
      message: frame?.path ?? label,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: KeyedSubtree(key: ValueKey(frame), child: body),
      ),
    );
  }
}
