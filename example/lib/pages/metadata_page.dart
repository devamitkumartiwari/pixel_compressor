import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';

class MetadataPage extends StatefulWidget {
  const MetadataPage({super.key});

  @override
  State<MetadataPage> createState() => _MetadataPageState();
}

class _MetadataPageState extends State<MetadataPage> {
  String? _sourceName;
  bool _busy = false;
  MediaInfo? _info;
  Object? _error;

  Future<void> _pick(ImageSource source, {required bool video}) async {
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(source: source)
        : await picker.pickImage(source: source);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _sourceName = file.uri.pathSegments.last;
      _info = null;
      _error = null;
      _busy = true;
    });

    try {
      final info = await PixelCompressor.metadata.read(MediaSource.file(file));
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: 'Read metadata',
          icon: Icons.info_outline,
          children: [
            const Text(
              'Reads dimensions, duration, codec, and EXIF info without compressing anything.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pick(ImageSource.gallery, video: false),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Pick image'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pick(ImageSource.gallery, video: true),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Pick video'),
                  ),
                ),
              ],
            ),
            if (_sourceName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Source: $_sourceName',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ErrorBanner(error: _error!),
          ),
        if (info != null)
          SectionCard(
            title: 'Media info',
            icon: Icons.check_circle_outline,
            children: [
              _row('Type', info.mediaType.name),
              _row('Size', formatBytes(info.sizeBytes)),
              _row(
                'Dimensions',
                '${info.width ?? '?'} x ${info.height ?? '?'}',
              ),
              _row('Format', info.format ?? '—'),
              if (info.mediaType == MediaType.image) ...[
                _row('EXIF present', '${info.exifPresent ?? '?'}'),
                _row('Orientation', '${info.orientation ?? '—'}'),
              ],
              if (info.mediaType == MediaType.video) ...[
                _row(
                  'Duration',
                  info.duration != null ? formatDuration(info.duration!) : '—',
                ),
                _row('FPS', info.fps?.toStringAsFixed(1) ?? '—'),
                _row(
                  'Bitrate',
                  info.bitrateBps != null
                      ? '${(info.bitrateBps! / 1000).round()} kbps'
                      : '—',
                ),
                _row('Video codec', info.videoCodec ?? '—'),
                _row('Audio codec', info.audioCodec ?? '—'),
                _row('Container', info.container ?? '—'),
                _row('Has audio', '${info.hasAudio ?? '?'}'),
              ],
            ],
          ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
