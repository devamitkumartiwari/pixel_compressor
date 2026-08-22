import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';

class ThumbnailsPage extends StatefulWidget {
  const ThumbnailsPage({super.key});

  @override
  State<ThumbnailsPage> createState() => _ThumbnailsPageState();
}

class _ThumbnailsPageState extends State<ThumbnailsPage> {
  File? _sourceFile;
  Duration? _sourceDuration;
  int _count = 4;

  bool _busy = false;
  List<ThumbnailResult>? _results;
  Object? _error;

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    setState(() {
      _sourceFile = file;
      _sourceDuration = null;
      _results = null;
      _error = null;
    });

    try {
      final info = await PixelCompressor.metadata.read(MediaSource.file(file));
      if (mounted) setState(() => _sourceDuration = info.duration);
    } on PixelCompressorException {
      // Fall back to fixed 2s spacing below when duration isn't available.
    }
  }

  List<Duration> _evenlySpacedPositions() {
    final duration = _sourceDuration;
    if (duration == null || duration.inMilliseconds <= 0) {
      return List.generate(_count, (i) => Duration(seconds: i * 2));
    }
    final stepMs = duration.inMilliseconds / (_count + 1);
    return List.generate(
      _count,
      (i) => Duration(milliseconds: (stepMs * (i + 1)).round()),
    );
  }

  Future<void> _generate() async {
    final file = _sourceFile;
    if (file == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _results = null;
    });

    try {
      final results = await PixelCompressor.thumbnails.generate(
        MediaSource.file(file),
        ThumbnailOptions(
          positions: _evenlySpacedPositions(),
          maxWidth: 320,
          maxHeight: 320,
        ),
      );
      if (mounted) setState(() => _results = results);
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
              if (_sourceDuration != null)
                Text('Duration: ${formatDuration(_sourceDuration!)}'),
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
          title: 'Thumbnail options',
          icon: Icons.tune,
          children: [
            Text('Frame count: $_count'),
            Slider(
              value: _count.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '$_count',
              onChanged: (value) => setState(() => _count = value.round()),
            ),
            Text(
              'Positions: ${_evenlySpacedPositions().map(formatDuration).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: file == null || _busy ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.grid_view_outlined),
            label: Text(_busy ? 'Generating…' : 'Generate thumbnails'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ErrorBanner(error: _error!),
          ),
        if (_results != null)
          SectionCard(
            title: 'Result (${_results!.length} frames)',
            icon: Icons.check_circle_outline,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _results!
                    .map(
                      (thumb) => SizedBox(
                        width: 100,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                thumb.outputFile,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 100,
                                  height: 100,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              formatDuration(thumb.position),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
      ],
    );
  }
}
