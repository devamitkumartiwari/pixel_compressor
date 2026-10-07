import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../widgets/video_preview_player.dart';
import '../widgets/widgets.dart';

/// `compressVideoFile` with every option, live progress and cancel.
class const VideoTab({super.key}) extends StatefulWidget {
  @override
  State<VideoTab> createState() => _VideoTabState();
}

class _VideoTabState()
    extends State<VideoTab>
    with AutomaticKeepAliveClientMixin {
  String? _path;
  PixelMediaInfo? _sourceInfo;
  int _sourceSize = 0;

  PixelVideoQuality _quality = PixelVideoQuality.MediumQuality;
  PixelVideoCodec _codec = .h264;
  int _frameRate = 30;
  bool _customBitrate = false;
  double _bitrate = 2000000;
  bool _limitSize = false;
  double _maxWidth = 1280, _maxHeight = 1280;
  bool _trim = false;
  RangeValues _trimRange = const RangeValues(0, 1);
  bool _includeAudio = true;
  int? _audioBitrate;
  int? _audioSampleRate;
  int? _audioChannels;
  double _keyFrameInterval = 3;
  bool _preventLarger = true;
  bool _customOutput = false;

  bool _busy = false;
  double _progress = 0;
  Object? _error;
  PixelMediaInfo? _result;
  Duration? _elapsed;
  late final PixelProgressSubscription _subscription;

  @override
  bool get wantKeepAlive => true;

  double get _durationSec => (_sourceInfo?.duration ?? 0) / 1000;

  @override
  void initState() {
    super.initState();
    if (PlatformSupport.video) {
      // progress$ is a broadcast stream: any number of listeners may subscribe.
      _subscription = PixelVideoCompressor.progress$.subscribe((progress) {
        if (mounted && _busy) setState(() => _progress = progress);
      });
    }
  }

  @override
  void dispose() {
    if (PlatformSupport.video) _subscription.unsubscribe();
    super.dispose();
  }

  Future<void> _pick() async {
    final path = await pickVideo(context);
    if (path == null || !mounted) return;
    setState(() {
      _path = path;
      _sourceInfo = null;
      _sourceSize = fileSize(path);
      _result = null;
      _error = null;
    });
    try {
      final info = await PixelVideoCompressor.readMediaInfo(path);
      if (!mounted) return;
      final seconds = (info.duration ?? 0) / 1000;
      setState(() {
        _sourceInfo = info;
        _trimRange = RangeValues(0, seconds > 0 ? seconds : 1);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = ExampleError("Couldn't read this video: $e"));
      }
    }
  }

  Future<void> _compress() async {
    final path = _path;
    if (path == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
      _result = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      final trimmed = _trim && _durationSec > 0;
      final info = await PixelVideoCompressor.compressVideoFile(
        path,
        quality: _quality,
        codec: _codec,
        frameRate: _frameRate,
        bitrate: _customBitrate ? _bitrate.round() : null,
        maxWidth: _limitSize ? _maxWidth.round() : null,
        maxHeight: _limitSize ? _maxHeight.round() : null,
        startTime: trimmed ? (_trimRange.start * 1000).round() : null,
        duration: trimmed
            ? ((_trimRange.end - _trimRange.start) * 1000).round()
            : null,
        includeAudio: _includeAudio,
        audioBitrate: _includeAudio ? _audioBitrate : null,
        audioSampleRate: _includeAudio ? _audioSampleRate : null,
        audioChannels: _includeAudio ? _audioChannels : null,
        keyFrameInterval: _keyFrameInterval,
        preventLargerOutput: _preventLarger,
        outputPath: _customOutput ? await outputPathFor('video', 'mp4') : null,
        // deleteOrigin stays false: never delete the user's video in a demo.
      );
      if (!mounted) return;
      setState(() {
        _elapsed = stopwatch.elapsed;
        if (info == null) {
          // Native failures come back as null (the error is logged).
          _error = const ExampleError(
            'Compression failed on the native side. Check the device logs.',
          );
        } else {
          _result = info;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const header = HeroHeader(
      icon: Icons.movie_rounded,
      title: 'Video',
      subtitle: 'H.264 / HEVC with trim, resize, bitrate and audio control',
    );
    if (!PlatformSupport.video) {
      return const FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.videocam_off_rounded,
          title: 'Not available on the web',
          message: 'Video compression runs on Android, iOS and macOS.',
        ),
      );
    }
    final path = _path;
    if (path == null) {
      return FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.video_library_rounded,
          title: 'Pick a video to compress',
          message:
              'Media3 Transformer on Android, AVFoundation on iOS and macOS.',
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

    final info = _sourceInfo;
    return FeatureLayout(
      header: header,
      preview: [
        SourceCard(
          title: path.split(Platform.pathSeparator).last,
          onChange: _busy ? null : _pick,
          preview: VideoPreviewPlayer(key: ValueKey(path), file: File(path)),
          chips: [
            StatChip(
              icon: Icons.sd_storage_rounded,
              label: formatBytes(_sourceSize),
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
      options: _options(),
      result: _resultView(path),
      actions: Row(
        children: [
          Expanded(
            child: BusyButton(
              label: _busy ? 'Compressing…' : 'Compress',
              icon: Icons.compress_rounded,
              busy: _busy,
              onPressed: _compress,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _busy
                ? Padding(
                    padding: const EdgeInsets.only(left: Insets.sm + 4),
                    child: OutlinedButton.icon(
                      onPressed: PixelVideoCompressor.cancelVideoCompression,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Cancel'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  List<Widget> _options() {
    final enabled = !_busy;
    void set(VoidCallback f) => setState(f);
    return [
      OptionCard(
        title: 'Quality & codec',
        icon: Icons.high_quality_rounded,
        children: [
          OptionDropdown<PixelVideoQuality>(
            label: 'Quality preset',
            selected: _quality,
            choices: [
              for (final q in PixelVideoQuality.values)
                Choice(q, _qualityLabel(q)),
            ],
            onChanged: enabled ? (q) => set(() => _quality = q) : null,
          ),
          OptionSegmented<PixelVideoCodec>(
            label: 'Codec',
            selected: _codec,
            choices: const [Choice(.h264, 'H.264'), Choice(.hevc, 'HEVC')],
            onChanged: enabled ? (c) => set(() => _codec = c) : null,
            hint: _codec == .hevc
                ? '≈40% smaller; falls back to H.264 on Android devices '
                      'without an HEVC encoder'
                : null,
          ),
          OptionSegmented<int>(
            label: 'Frame rate',
            selected: _frameRate,
            choices: const [
              Choice(24, '24'),
              Choice(30, '30'),
              Choice(60, '60'),
            ],
            onChanged: enabled ? (f) => set(() => _frameRate = f) : null,
          ),
        ],
      ),
      OptionCard(
        title: 'Trim',
        icon: Icons.content_cut_rounded,
        trailing: Switch(
          value: _trim,
          onChanged: enabled && _durationSec > 0
              ? (v) => set(() => _trim = v)
              : null,
        ),
        children: [
          if (!_trim)
            const PlatformHint('startTime + duration, in milliseconds')
          else ...[
            Row(
              children: [
                ValuePill(formatTimestamp(_secs(_trimRange.start))),
                const Spacer(),
                Text(
                  formatDuration(_secs(_trimRange.end - _trimRange.start)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                ValuePill(formatTimestamp(_secs(_trimRange.end))),
              ],
            ),
            RangeSlider(
              values: _trimRange,
              max: _durationSec,
              onChanged: enabled
                  ? (r) {
                      if (r.end - r.start >= 0.5) set(() => _trimRange = r);
                    }
                  : null,
            ),
          ],
        ],
      ),
      OptionCard(
        title: 'Audio',
        icon: Icons.graphic_eq_rounded,
        trailing: Switch(
          value: _includeAudio,
          onChanged: enabled ? (v) => set(() => _includeAudio = v) : null,
        ),
        children: [
          if (!_includeAudio)
            const PlatformHint('includeAudio: false drops the audio track')
          else ...[
            OptionSegmented<int?>(
              label: 'Bitrate',
              selected: _audioBitrate,
              choices: const [
                Choice(null, 'Auto'),
                Choice(64000, '64k'),
                Choice(128000, '128k'),
                Choice(192000, '192k'),
              ],
              onChanged: enabled ? (v) => set(() => _audioBitrate = v) : null,
            ),
            OptionSegmented<int?>(
              label: 'Sample rate',
              selected: _audioSampleRate,
              choices: const [
                Choice(null, 'Auto'),
                Choice(22050, '22 kHz'),
                Choice(44100, '44.1'),
                Choice(48000, '48'),
              ],
              onChanged: enabled
                  ? (v) => set(() => _audioSampleRate = v)
                  : null,
            ),
            OptionSegmented<int?>(
              label: 'Channels',
              selected: _audioChannels,
              choices: const [
                Choice(null, 'Auto'),
                Choice(1, 'Mono'),
                Choice(2, 'Stereo'),
              ],
              onChanged: enabled ? (v) => set(() => _audioChannels = v) : null,
            ),
            const PlatformHint(
              'Auto keeps an AAC source track without re-encoding on Android.',
            ),
          ],
        ],
      ),
      AdvancedSection(
        children: [
          OptionSwitch(
            title: 'Custom bitrate',
            subtitle: 'Overrides the quality preset',
            value: _customBitrate,
            onChanged: enabled ? (v) => set(() => _customBitrate = v) : null,
          ),
          if (_customBitrate)
            LabeledSlider(
              label: 'Video bitrate',
              valueLabel: formatBitrate(_bitrate.round()),
              value: _bitrate,
              min: 250000,
              max: 10000000,
              divisions: 39,
              onChanged: enabled ? (v) => set(() => _bitrate = v) : null,
            ),
          OptionSwitch(
            title: 'Limit size',
            subtitle: 'maxWidth / maxHeight',
            value: _limitSize,
            onChanged: enabled ? (v) => set(() => _limitSize = v) : null,
          ),
          if (_limitSize) ...[
            LabeledSlider(
              label: 'Max width',
              valueLabel: '${_maxWidth.round()} px',
              value: _maxWidth,
              min: 240,
              max: 3840,
              divisions: 45,
              onChanged: enabled ? (v) => set(() => _maxWidth = v) : null,
            ),
            LabeledSlider(
              label: 'Max height',
              valueLabel: '${_maxHeight.round()} px',
              value: _maxHeight,
              min: 240,
              max: 3840,
              divisions: 45,
              onChanged: enabled ? (v) => set(() => _maxHeight = v) : null,
            ),
          ],
          LabeledSlider(
            label: 'Key-frame interval',
            valueLabel: '${_keyFrameInterval.round()} s',
            value: _keyFrameInterval,
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: enabled ? (v) => set(() => _keyFrameInterval = v) : null,
          ),
          OptionSwitch(
            title: 'Prevent larger output',
            subtitle:
                'Keep the original streams if compressing would grow the file',
            value: _preventLarger,
            onChanged: enabled ? (v) => set(() => _preventLarger = v) : null,
          ),
          OptionSwitch(
            title: 'Custom output path',
            subtitle: 'outputPath: a .mp4 in the example temp folder',
            value: _customOutput,
            onChanged: enabled ? (v) => set(() => _customOutput = v) : null,
          ),
        ],
      ),
    ];
  }

  Duration _secs(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  static String _qualityLabel(PixelVideoQuality q) => switch (q) {
    PixelVideoQuality.DefaultQuality => 'Default',
    PixelVideoQuality.LowQuality => 'Low',
    PixelVideoQuality.MediumQuality => 'Medium',
    PixelVideoQuality.HighestQuality => 'Highest',
    PixelVideoQuality.Res640x480Quality => '640 × 480',
    PixelVideoQuality.Res960x540Quality => '960 × 540',
    PixelVideoQuality.Res1280x720Quality => '1280 × 720',
    PixelVideoQuality.Res1920x1080Quality => '1920 × 1080',
  };

  Widget? _resultView(String sourcePath) {
    if (_busy) {
      return Card(
        key: const ValueKey('progress'),
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            children: [
              ProgressRing(progress: _progress / 100, caption: 'progress\$'),
              const SizedBox(height: Insets.md),
              Text(
                'Compressing… you can switch tabs, it keeps running.',
                textAlign: .center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return ErrorBanner(
        key: ValueKey(error),
        error: error,
        onDismiss: () => setState(() => _error = null),
      );
    }
    final result = _result;
    if (result == null) return null;
    if (result.isCancel ?? false) {
      return const ResultCard(
        key: ValueKey('cancelled'),
        title: 'Cancelled',
        icon: Icons.stop_circle_outlined,
        children: [PlatformHint('The result came back with isCancel: true.')],
      );
    }
    final outPath = result.path!;
    final outSize = result.filesize ?? fileSize(outPath);
    return ResultCard(
      key: ValueKey(result),
      title: 'Compressed',
      children: [
        Row(
          children: [
            Expanded(
              child: VideoPreviewPlayer(
                key: ValueKey('src-$sourcePath'),
                file: File(sourcePath),
                height: 160,
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: VideoPreviewPlayer(
                key: ValueKey('out-$outPath'),
                file: File(outPath),
                height: 160,
              ),
            ),
          ],
        ),
        SavingsBadge(originalBytes: _sourceSize, outputBytes: outSize),
        SizeComparisonBar(originalBytes: _sourceSize, outputBytes: outSize),
        StatChips([
          StatChip(
            icon: Icons.aspect_ratio_rounded,
            label: '${result.width} × ${result.height}',
          ),
          StatChip(
            icon: Icons.schedule_rounded,
            label: formatDuration(
              Duration(milliseconds: (result.duration ?? 0).round()),
            ),
          ),
          StatChip(
            icon: Icons.memory_rounded,
            label: _codec == .hevc ? 'HEVC' : 'H.264',
          ),
          if (_elapsed case final elapsed?)
            StatChip(
              icon: Icons.timer_outlined,
              label: formatDuration(elapsed),
            ),
        ]),
        SelectableText(
          outPath,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
