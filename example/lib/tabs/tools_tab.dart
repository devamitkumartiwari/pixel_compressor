import 'package:flutter/material.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../theme/app_theme.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../widgets/widgets.dart';

class const _Support(this.supported, [this.message]) {
  final bool supported;
  final String? message;
}

/// Format support, validator switches, native logging and caches.
class const ToolsTab({super.key}) extends StatefulWidget {
  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState()
    extends State<ToolsTab>
    with AutomaticKeepAliveClientMixin {
  Map<PixelImageFormat, _Support>? _support;
  bool _nativeLog = false;
  late bool _ignoreExtName = _validator?.ignoreCheckExtName ?? false;
  late bool _ignoreSupport = _validator?.ignoreCheckSupportPlatform ?? false;
  int _videoLogLevel = 2;

  @override
  bool get wantKeepAlive => true;

  /// Null when no image backend is registered (unsupported OS, unit tests).
  static PixelImageFormatValidator? get _validator {
    try {
      return PixelImageCompressor.validator;
    } on UnimplementedError {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  /// `validator.checkSupportPlatform` returns false or throws a
  /// `PixelCompressError` (`unsupported_format`) when the platform can't
  /// encode a format.
  Future<void> _checkSupport() async {
    final validator = _validator;
    final results = <PixelImageFormat, _Support>{};
    for (final format in PixelImageFormat.values) {
      if (validator == null) {
        results[format] = const _Support(false, 'No image backend here');
        continue;
      }
      try {
        final ok = await validator.checkSupportPlatform(format);
        results[format] = _Support(ok);
      } on PixelCompressError catch (e) {
        results[format] = _Support(false, e.message);
      } catch (e) {
        results[format] = _Support(false, '$e');
      }
    }
    if (mounted) setState(() => _support = results);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FeatureLayout(
      header: const HeroHeader(
        icon: Icons.handyman_rounded,
        title: 'Tools',
        subtitle: 'Platform support, validator, logging and caches',
      ),
      options: [_supportCard(), _validatorCard(), _loggingCard(), _cacheCard()],
    );
  }

  Widget _supportCard() {
    final support = _support;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return OptionCard(
      title: 'Output formats on ${PlatformSupport.name}',
      icon: Icons.verified_outlined,
      trailing: IconButton(
        tooltip: 'Check again',
        visualDensity: .compact,
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () {
          setState(() => _support = null);
          _checkSupport();
        },
      ),
      children: [
        if (support == null)
          const ShimmerBox(height: 160)
        else
          for (final MapEntry(key: format, value: s) in support.entries)
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: s.supported
                        ? palette.successContainer
                        : theme.colorScheme.errorContainer,
                    shape: .circle,
                  ),
                  child: Icon(
                    s.supported ? Icons.check_rounded : Icons.close_rounded,
                    size: 18,
                    color: s.supported
                        ? palette.onSuccessContainer
                        : theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: Insets.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        format.name.toUpperCase(),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        s.message ??
                            (s.supported ? 'Supported' : 'Not supported'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        const PlatformHint(
          'PixelImageCompressor.validator.checkSupportPlatform',
        ),
      ],
    );
  }

  Widget _validatorCard() {
    return OptionCard(
      title: 'Validator',
      icon: Icons.rule_rounded,
      children: [
        OptionSwitch(
          title: 'Ignore file extension check',
          subtitle:
              'validator.ignoreCheckExtName: allow a compressFileToFile '
              'target whose extension differs from the format',
          value: _ignoreExtName,
          onChanged: _validator == null
              ? null
              : (v) {
                  _validator?.ignoreCheckExtName = v;
                  setState(() => _ignoreExtName = v);
                },
        ),
        OptionSwitch(
          title: 'Ignore platform support check',
          subtitle:
              'ignoreCheckSupportPlatform: let the native side try any format',
          value: _ignoreSupport,
          onChanged: _validator == null
              ? null
              : (v) {
                  PixelImageCompressor.ignoreCheckSupportPlatform(v);
                  setState(() {
                    _ignoreSupport = v;
                    _support = null;
                  });
                  _checkSupport();
                },
        ),
        if (PlatformSupport.isWeb)
          const PlatformHint(
            'On the web every format check passes; the browser decides.',
          ),
      ],
    );
  }

  Widget _loggingCard() {
    return OptionCard(
      title: 'Native logging',
      icon: Icons.terminal_rounded,
      children: [
        OptionSwitch(
          title: 'Image logs',
          subtitle: 'PixelImageCompressor.nativeLogEnabled',
          value: _nativeLog,
          onChanged: _validator == null
              ? null
              : (v) {
                  PixelImageCompressor.nativeLogEnabled = v;
                  setState(() => _nativeLog = v);
                },
        ),
        OptionSegmented<int>(
          label: 'Video log level (setNativeLogLevel)',
          selected: _videoLogLevel,
          choices: const [
            Choice(0, 'All'),
            Choice(1, 'Info'),
            Choice(2, 'Warn'),
            Choice(3, 'Error'),
          ],
          onChanged: PlatformSupport.video
              ? (v) async {
                  setState(() => _videoLogLevel = v);
                  await PixelVideoCompressor.setNativeLogLevel(v);
                }
              : null,
          hint: PlatformSupport.video
              ? 'Media3 log level on Android; no effect on iOS / macOS'
              : 'Not on ${PlatformSupport.name}',
        ),
      ],
    );
  }

  Widget _cacheCard() {
    return OptionCard(
      title: 'Cache & status',
      icon: Icons.cleaning_services_outlined,
      children: [
        if (PlatformSupport.video)
          StreamBuilder<double>(
            stream: PixelVideoCompressor.progress$.stream,
            builder: (context, snapshot) {
              final running = PixelVideoCompressor.isCompressing;
              return OptionSwitch(
                title: 'Video compression running',
                subtitle: running
                    ? 'isCompressing · ${snapshot.data?.toStringAsFixed(0) ?? 0}%'
                    : 'isCompressing · idle',
                value: running,
                onChanged: null,
              );
            },
          ),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            FilledButton.tonalIcon(
              onPressed: PlatformSupport.video
                  ? () async {
                      final cleared =
                          await PixelVideoCompressor.clearVideoCache();
                      _toast('clearVideoCache → $cleared');
                    }
                  : null,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear video cache'),
            ),
            FilledButton.tonalIcon(
              onPressed: PlatformSupport.files
                  ? () async {
                      final dir = await exampleTempDir();
                      await dir.delete(recursive: true);
                      _toast('Example temp files deleted');
                    }
                  : null,
              icon: const Icon(Icons.folder_delete_outlined),
              label: const Text('Clear example files'),
            ),
          ],
        ),
        if (!PlatformSupport.files)
          PlatformHint('No file system on ${PlatformSupport.name}'),
      ],
    );
  }
}
