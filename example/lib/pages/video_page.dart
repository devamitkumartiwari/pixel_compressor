import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';
import '../widgets/size_comparison_bar.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  File? _sourceFile;
  int? _originalSizeBytes;
  MediaInfo? _sourceInfo;

  CompressionMode _mode = CompressionMode.smart;
  QualityPreset _preset = QualityPreset.medium;
  VideoCodec _codec = VideoCodec.auto;
  bool _audioEnabled = true;
  final _maxWidthController = TextEditingController();
  final _maxHeightController = TextEditingController();
  final _bitrateKbpsController = TextEditingController();
  final _fpsController = TextEditingController();
  final _targetSizeKbController = TextEditingController();

  bool _busy = false;
  ProgressEvent? _progress;
  CompressionResult? _result;
  Object? _error;

  @override
  void dispose() {
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    _bitrateKbpsController.dispose();
    _fpsController.dispose();
    _targetSizeKbController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    final size = await file.length();
    setState(() {
      _sourceFile = file;
      _originalSizeBytes = size;
      _sourceInfo = null;
      _result = null;
      _error = null;
      _progress = null;
    });

    try {
      final info = await PixelCompressor.metadata.read(MediaSource.file(file));
      if (mounted) setState(() => _sourceInfo = info);
    } on PixelCompressorException {
      // Not fatal — the picked file's on-disk size is already shown.
    }
  }

  Future<void> _compress() async {
    final file = _sourceFile;
    if (file == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _progress = null;
    });

    final maxWidth = int.tryParse(_maxWidthController.text);
    final maxHeight = int.tryParse(_maxHeightController.text);
    final bitrateKbps = int.tryParse(_bitrateKbpsController.text);
    final fps = int.tryParse(_fpsController.text);
    final targetKb = int.tryParse(_targetSizeKbController.text);

    try {
      final result = await PixelCompressor.video.compress(
        MediaSource.file(file),
        options: VideoCompressOptions(
          mode: _mode,
          preset: _mode == CompressionMode.smart ? _preset : null,
          codec: _mode == CompressionMode.manual ? _codec : null,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          fps: fps,
          bitrateBps: _mode == CompressionMode.manual && bitrateKbps != null
              ? bitrateKbps * 1000
              : null,
          audioEnabled: _audioEnabled,
          targetSizeBytes: targetKb == null ? null : targetKb * 1024,
        ),
        onProgress: (event) {
          if (mounted) setState(() => _progress = event);
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _sourceFile;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: 'Source video',
          icon: Icons.videocam_outlined,
          children: [
            if (file != null) ...[
              Text(file.uri.pathSegments.last, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text('Size on disk: ${formatBytes(_originalSizeBytes ?? 0)}'),
              if (_sourceInfo != null) ...[
                Text(
                  '${_sourceInfo!.width ?? '?'} x ${_sourceInfo!.height ?? '?'}',
                ),
                if (_sourceInfo!.duration != null)
                  Text('Duration: ${formatDuration(_sourceInfo!.duration!)}'),
                if (_sourceInfo!.videoCodec != null)
                  Text('Codec: ${_sourceInfo!.videoCodec}'),
              ],
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: Text(
                file == null ? 'Pick a video' : 'Pick a different video',
              ),
            ),
          ],
        ),
        SectionCard(
          title: 'Compression options',
          icon: Icons.tune,
          children: [
            SegmentedButton<CompressionMode>(
              segments: const [
                ButtonSegment(
                  value: CompressionMode.smart,
                  label: Text('Smart (preset)'),
                ),
                ButtonSegment(
                  value: CompressionMode.manual,
                  label: Text('Manual'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 12),
            if (_mode == CompressionMode.smart)
              DropdownButtonFormField<QualityPreset>(
                initialValue: _preset,
                decoration: const InputDecoration(labelText: 'Quality preset'),
                items: QualityPreset.values
                    .where((p) => p != QualityPreset.custom)
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _preset = value ?? _preset),
              )
            else ...[
              DropdownButtonFormField<VideoCodec>(
                initialValue: _codec,
                decoration: const InputDecoration(labelText: 'Codec'),
                items: VideoCodec.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (value) => setState(() => _codec = value ?? _codec),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bitrateKbpsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bitrate (kbps)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _fpsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'FPS'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxWidthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max width (px)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxHeightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max height (px)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetSizeKbController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target size (KB, optional)',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep audio'),
              value: _audioEnabled,
              onChanged: (value) => setState(() => _audioEnabled = value),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: file == null || _busy ? null : _compress,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.compress),
            label: Text(_busy ? 'Compressing…' : 'Compress video'),
          ),
        ),
        if (_busy && _progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: _progress!.percent / 100),
                const SizedBox(height: 4),
                Text(
                  '${_progress!.stage.name} — ${_progress!.percent.toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ErrorBanner(error: _error!),
          ),
        if (_result != null)
          SectionCard(
            title: 'Result',
            icon: Icons.check_circle_outline,
            children: [
              SizeComparisonBar(
                originalBytes: _result!.originalSizeBytes,
                outputBytes: _result!.outputSizeBytes,
              ),
              const SizedBox(height: 12),
              Text('Codec/encoder: ${_result!.codec}'),
              Text('Format: ${_result!.format}'),
              Text('Took: ${formatDuration(_result!.duration)}'),
              Text(
                'Output path: ${_result!.outputPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }
}
