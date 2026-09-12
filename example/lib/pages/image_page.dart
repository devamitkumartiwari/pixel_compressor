import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../widgets/error_banner.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/section_card.dart';
import '../widgets/size_comparison_bar.dart';
import '../widgets/zoomable_image_preview.dart';

class ImagePage extends StatefulWidget {
  const ImagePage({super.key, this.initialFile});

  /// A file already picked (e.g. by the home page's intro/picker step) —
  /// when set, this is loaded immediately instead of waiting for the user
  /// to tap "Pick an image".
  final File? initialFile;

  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  File? _sourceFile;
  int? _originalSizeBytes;
  MediaInfo? _sourceInfo;

  double _quality = 80;
  ImageFormat? _format;
  ExifPolicy _exifPolicy = ExifPolicy.strip;
  final _maxWidthController = TextEditingController();
  final _maxHeightController = TextEditingController();
  final _targetSizeKbController = TextEditingController();

  bool _busy = false;
  ProgressEvent? _progress;
  CompressionResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final file = widget.initialFile;
    if (file != null) {
      _loadFile(file);
    }
  }

  @override
  void dispose() {
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    _targetSizeKbController.dispose();
    super.dispose();
  }

  Future<void> _loadFile(File file) async {
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
      // Metadata is a nice-to-have here; the picked file's size on disk is
      // already shown, so a metadata failure doesn't block compressing it.
    }
  }

  Future<void> _pickImage() async {
    final source = await showMediaSourceSheet(
      context,
      captureLabel: 'Take a photo',
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    await _loadFile(File(picked.path));
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
    final targetKb = int.tryParse(_targetSizeKbController.text);

    try {
      final result = await PixelCompressor.image.compress(
        MediaSource.file(file),
        options: ImageCompressOptions(
          quality: _quality.round(),
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          format: _format,
          exifPolicy: _exifPolicy,
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
          title: 'Source image',
          icon: Icons.image_outlined,
          children: [
            if (file != null) ...[
              ZoomableImagePreview(file: file),
              const SizedBox(height: 8),
              Text('Size on disk: ${formatBytes(_originalSizeBytes ?? 0)}'),
              if (_sourceInfo != null)
                Text(
                  '${_sourceInfo!.width ?? '?'} x ${_sourceInfo!.height ?? '?'} · ${_sourceInfo!.format ?? '?'}',
                ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                file == null ? 'Pick an image' : 'Pick a different image',
              ),
            ),
          ],
        ),
        SectionCard(
          title: 'Compression options',
          icon: Icons.tune,
          children: [
            Text('Quality: ${_quality.round()}'),
            Slider(
              value: _quality,
              min: 1,
              max: 100,
              divisions: 99,
              label: _quality.round().toString(),
              onChanged: (value) => setState(() => _quality = value),
            ),
            DropdownButtonFormField<ImageFormat?>(
              initialValue: _format,
              decoration: const InputDecoration(labelText: 'Output format'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Keep source format'),
                ),
                ...ImageFormat.values.map(
                  (f) => DropdownMenuItem(value: f, child: Text(f.name)),
                ),
              ],
              onChanged: (value) => setState(() => _format = value),
            ),
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
                helperText: 'If set, quality above is ignored and the native side searches for it',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ExifPolicy>(
              segments: const [
                ButtonSegment(
                  value: ExifPolicy.strip,
                  label: Text('Strip EXIF'),
                ),
                ButtonSegment(value: ExifPolicy.keep, label: Text('Keep EXIF')),
              ],
              selected: {_exifPolicy},
              onSelectionChanged: (selection) =>
                  setState(() => _exifPolicy = selection.first),
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
            label: Text(_busy ? 'Compressing…' : 'Compress image'),
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
              ZoomableImagePreview(
                key: ValueKey(_result!.outputPath),
                file: _result!.outputFile,
              ),
              const SizedBox(height: 12),
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
