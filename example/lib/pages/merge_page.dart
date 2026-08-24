import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';

class MergePage extends StatefulWidget {
  const MergePage({super.key});

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  List<File> _sourceFiles = [];
  MergeDirection _direction = MergeDirection.vertical;
  double _spacing = 8;
  bool _scaleToFit = true;

  bool _busy = false;
  MergeResult? _result;
  Object? _error;

  CompressionResult? _jpegResult;
  bool _compressingJpeg = false;

  List<ui.Image>? _previewImages;
  bool _loadingPreview = false;
  Object? _previewError;
  final _captureController = MergeCaptureController();
  Uint8List? _capturedPng;
  bool _capturing = false;

  @override
  void dispose() {
    _disposePreviewImages();
    super.dispose();
  }

  void _disposePreviewImages() {
    for (final image in _previewImages ?? const <ui.Image>[]) {
      image.dispose();
    }
    _previewImages = null;
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    _disposePreviewImages();
    setState(() {
      _sourceFiles = picked.map((x) => File(x.path)).toList();
      _result = null;
      _error = null;
      _jpegResult = null;
      _capturedPng = null;
      _previewError = null;
    });
  }

  Future<void> _merge() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
      _jpegResult = null;
    });

    try {
      final result = await PixelCompressor.merge.combine(
        _sourceFiles.map(MediaSource.file).toList(),
        options: MergeOptions(
          direction: _direction,
          spacing: _spacing,
          scaleToFit: _scaleToFit,
        ),
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compressToJpeg() async {
    final result = _result;
    if (result == null) return;

    setState(() => _compressingJpeg = true);
    try {
      final jpeg = await PixelCompressor.image.compress(
        MediaSource.file(result.outputFile),
        options: const ImageCompressOptions(
          format: ImageFormat.jpeg,
          quality: 80,
        ),
      );
      if (mounted) setState(() => _jpegResult = jpeg);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _compressingJpeg = false);
    }
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _previewError = null;
      _capturedPng = null;
    });

    try {
      final images = <ui.Image>[
        for (final file in _sourceFiles)
          await PixelCompressor.merge.decode(MediaSource.file(file)),
      ];
      _disposePreviewImages();
      if (mounted) setState(() => _previewImages = images);
    } catch (e) {
      if (mounted) setState(() => _previewError = e);
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _previewError = null;
    });
    try {
      final png = await _captureController.capturePng();
      if (mounted) setState(() => _capturedPng = png);
    } catch (e) {
      if (mounted) setState(() => _previewError = e);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final previewImages = _previewImages;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: 'Merge images',
          icon: Icons.merge_type,
          children: [
            const Text(
              'Stitches 2+ images together vertically or horizontally — '
              'pure Dart, no third-party dependencies, output is PNG.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickImages,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                _sourceFiles.isEmpty
                    ? 'Pick images'
                    : 'Pick a different selection',
              ),
            ),
            if (_sourceFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${_sourceFiles.length} image(s) selected'),
            ],
          ],
        ),
        SectionCard(
          title: 'Options',
          icon: Icons.tune,
          children: [
            SegmentedButton<MergeDirection>(
              segments: const [
                ButtonSegment(
                  value: MergeDirection.vertical,
                  label: Text('Vertical'),
                  icon: Icon(Icons.vertical_distribute),
                ),
                ButtonSegment(
                  value: MergeDirection.horizontal,
                  label: Text('Horizontal'),
                  icon: Icon(Icons.horizontal_distribute),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: _busy
                  ? null
                  : (selection) => setState(() => _direction = selection.first),
            ),
            const SizedBox(height: 12),
            Text('Spacing: ${_spacing.round()}px'),
            Slider(
              value: _spacing,
              min: 0,
              max: 40,
              divisions: 40,
              label: '${_spacing.round()}',
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _spacing = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Scale to fit'),
              subtitle: const Text(
                'Scale every image so its cross-axis size matches the '
                'widest/tallest source',
              ),
              value: _scaleToFit,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _scaleToFit = value),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: _sourceFiles.length < 2 || _busy ? null : _merge,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.merge_type),
            label: Text(_busy ? 'Merging…' : 'Merge'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ErrorBanner(error: _error!),
          ),
        if (result != null)
          SectionCard(
            title: 'Result',
            icon: Icons.check_circle_outline,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(result.outputBytes),
              ),
              const SizedBox(height: 8),
              Text('${result.width}x${result.height}'),
              Text(
                '${formatBytes(result.outputSizeBytes)} · '
                '${result.sourceCount} sources · '
                '${formatDuration(result.duration)}',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _compressingJpeg ? null : _compressToJpeg,
                icon: _compressingJpeg
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.compress),
                label: const Text('Compress to JPEG'),
              ),
              if (_jpegResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  'JPEG: ${formatBytes(_jpegResult!.outputSizeBytes)} '
                  '(${formatPercent(_jpegResult!.savedPercent)} smaller)',
                ),
              ],
            ],
          ),
        SectionCard(
          title: 'Live preview + capture',
          icon: Icons.preview_outlined,
          children: [
            const Text(
              'Decodes the sources and lays them out in a real Column/Row '
              'via MergeView, then screenshots it via MergeCaptureController.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _sourceFiles.length < 2 || _loadingPreview
                  ? null
                  : _loadPreview,
              icon: _loadingPreview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.visibility_outlined),
              label: const Text('Load preview'),
            ),
            if (previewImages != null) ...[
              const SizedBox(height: 12),
              Center(
                child: MergeView(
                  images: previewImages,
                  controller: _captureController,
                  direction: _direction,
                  spacing: _spacing,
                  scaleToFit: _scaleToFit,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _capturing ? null : _capture,
                icon: _capturing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined),
                label: const Text('Capture'),
              ),
            ],
            if (_capturedPng != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_capturedPng!),
              ),
              const SizedBox(height: 4),
              Text('Captured: ${formatBytes(_capturedPng!.length)}'),
            ],
            if (_previewError != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(error: _previewError!),
            ],
          ],
        ),
      ],
    );
  }
}
