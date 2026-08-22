import 'package:flutter/material.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';

class CachePage extends StatefulWidget {
  const CachePage({super.key});

  @override
  State<CachePage> createState() => _CachePageState();
}

class _CachePageState extends State<CachePage> {
  bool _busy = false;
  int? _sizeBytes;
  Object? _error;

  Future<void> _getSize() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final size = await PixelCompressor.cache.size();
      if (mounted) setState(() => _sizeBytes = size);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PixelCompressor.cache.clear();
      if (mounted) {
        setState(() => _sizeBytes = 0);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Cache cleared')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: 'Output cache',
          icon: Icons.folder_outlined,
          children: [
            const Text(
              "pixel_compressor writes results to a cache-managed temp directory when you don't pass an "
              'explicit outputPath. This screen inspects and clears that directory.',
            ),
            const SizedBox(height: 12),
            if (_sizeBytes != null)
              Text(
                'Current cache size: ${formatBytes(_sizeBytes!)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _getSize,
                    icon: const Icon(Icons.storage_outlined),
                    label: const Text('Get size'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear cache'),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ErrorBanner(error: _error!),
          ),
      ],
    );
  }
}
