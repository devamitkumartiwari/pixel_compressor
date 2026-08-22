import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';
import '../widgets/size_comparison_bar.dart';

class BatchPage extends StatefulWidget {
  const BatchPage({super.key});

  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  List<File> _sourceFiles = [];

  bool _busy = false;
  int _currentIndex = 0;
  int _totalItems = 0;
  ProgressEvent? _progress;
  BatchResult? _result;

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    setState(() {
      _sourceFiles = picked.map((x) => File(x.path)).toList();
      _result = null;
    });
  }

  Future<void> _compressAll() async {
    if (_sourceFiles.isEmpty) return;

    setState(() {
      _busy = true;
      _result = null;
      _currentIndex = 0;
      _totalItems = _sourceFiles.length;
      _progress = null;
    });

    final result = await PixelCompressor.image.compressBatch(
      _sourceFiles.map(MediaSource.file).toList(),
      options: const ImageCompressOptions(quality: 70, maxWidth: 1920),
      onProgress: (itemIndex, totalItems, event) {
        if (mounted) {
          setState(() {
            _currentIndex = itemIndex;
            _totalItems = totalItems;
            _progress = event;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _result = result;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: 'Batch compression',
          icon: Icons.collections_outlined,
          children: [
            const Text(
              'Compresses a list of images one at a time, continuing past any per-item failure — '
              'useful for e.g. compressing a whole camera roll selection before upload.',
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: _sourceFiles.isEmpty || _busy ? null : _compressAll,
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
            label: Text(_busy ? 'Compressing…' : 'Compress all'),
          ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _totalItems == 0
                      ? null
                      : (_currentIndex) / _totalItems,
                ),
                const SizedBox(height: 4),
                Text(
                  'Item ${_currentIndex + 1} of $_totalItems${_progress != null ? ' — ${_progress!.stage.name}' : ''}',
                ),
              ],
            ),
          ),
        if (result != null)
          SectionCard(
            title: 'Batch result',
            icon: Icons.check_circle_outline,
            children: [
              Text(
                '${result.succeeded.length} succeeded, ${result.failed.length} failed',
              ),
              const SizedBox(height: 12),
              if (result.succeeded.isNotEmpty) ...[
                SizeComparisonBar(
                  originalBytes: result.originalSizeBytes,
                  outputBytes: result.outputSizeBytes,
                ),
                const SizedBox(height: 12),
              ],
              ...result.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.succeeded
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: item.succeeded
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.succeeded
                              ? '${item.source.resolvedPath.split('/').last} — '
                                    '${formatBytes(item.result!.originalSizeBytes)} → '
                                    '${formatBytes(item.result!.outputSizeBytes)}'
                              : '${item.source.resolvedPath.split('/').last} — ${item.error!.nativeCode}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (result != null &&
            result.failed.isNotEmpty &&
            result.failed.length == result.items.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ErrorBanner(error: result.failed.first.error!),
          ),
      ],
    );
  }
}
