import 'package:flutter/material.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';

class CapabilitiesPage extends StatefulWidget {
  const CapabilitiesPage({super.key});

  @override
  State<CapabilitiesPage> createState() => _CapabilitiesPageState();
}

class _CapabilitiesPageState extends State<CapabilitiesPage> {
  bool _busy = false;
  Capabilities? _capabilities;
  Object? _error;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
      _capabilities = null;
    });
    try {
      final capabilities = await PixelCompressor.capabilities.check();
      if (mounted) setState(() => _capabilities = capabilities);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: 'Device capabilities',
          icon: Icons.memory,
          children: [
            const Text(
              'Which codecs this device can encode with, and the max hardware-encodable resolution.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _check,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_busy ? 'Checking…' : 'Check capabilities'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ErrorBanner(error: _error!),
          ),
        if (capabilities != null)
          SectionCard(
            title: 'Result',
            icon: Icons.check_circle_outline,
            children: [
              _statusRow('H.264 encode', capabilities.h264Encode),
              _statusRow('HEVC encode', capabilities.hevcEncode),
              _statusRow('AAC encode', capabilities.aacEncode),
              _statusRow('WebP encode', capabilities.webpEncode),
              _statusRow('HEIC encode', capabilities.heicEncode),
              const SizedBox(height: 8),
              Text(
                'Max hardware resolution: '
                '${capabilities.maxHardwareWidth ?? '?'} x ${capabilities.maxHardwareHeight ?? '?'}',
              ),
            ],
          ),
      ],
    );
  }

  Widget _statusRow(String label, CodecSupportStatus status) {
    final (icon, color) = switch (status) {
      CodecSupportStatus.supported => (Icons.check_circle, Colors.green),
      CodecSupportStatus.unsupported => (Icons.cancel, Colors.red),
      CodecSupportStatus.unknown => (Icons.help_outline, Colors.grey),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(status.name, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
