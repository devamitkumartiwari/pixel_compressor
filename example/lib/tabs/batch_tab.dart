import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../widgets/widgets.dart';

class const _Input(this.image, this.path) {
  final PickedImage image;
  final String path;
}

/// `compressFilesToBytes`: several files, bounded concurrency, per-file
/// results and errors.
class const BatchTab({super.key}) extends StatefulWidget {
  @override
  State<BatchTab> createState() => _BatchTabState();
}

class _BatchTabState()
    extends State<BatchTab>
    with AutomaticKeepAliveClientMixin {
  List<_Input> _inputs = const [];
  double _concurrency = 2;
  PixelImageFormat _format = .jpeg;
  double _quality = 75;
  bool _limitSize = true;
  double _maxSide = 1280;

  bool _busy = false;
  int _done = 0;
  Duration? _elapsed;
  List<PixelBatchItem>? _results;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pick() async {
    final picked = await pickImages(context, multiple: true);
    if (picked == null || picked.isEmpty) return;
    // The batch API takes file paths; samples are copied to temp files.
    final inputs = [for (final p in picked) _Input(p, await materialize(p))];
    if (!mounted) return;
    setState(() {
      _inputs = inputs;
      _results = null;
      _error = null;
      _done = 0;
    });
  }

  Future<void> _run() async {
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _done = 0;
      _results = null;
      _error = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      final results = await PixelImageCompressor.compressFilesToBytes(
        [for (final i in _inputs) i.path],
        concurrency: _concurrency.round(),
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
        format: _format,
        quality: _quality.round(),
        maxWidth: _limitSize ? _maxSide.round() : null,
        maxHeight: _limitSize ? _maxSide.round() : null,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _elapsed = stopwatch.elapsed;
        });
      }
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
      icon: Icons.burst_mode_rounded,
      title: 'Batch',
      subtitle: 'Many files at once with bounded concurrency',
    );

    if (!PlatformSupport.files) {
      return const FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Not available on the web',
          message:
              'compressFilesToBytes works on file paths. Use the Image tab '
              'to compress bytes in the browser.',
        ),
      );
    }
    if (_inputs.isEmpty) {
      return FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.collections_rounded,
          title: 'Pick a few images',
          message:
              'Results come back in input order, and one failing file '
              "doesn't stop the rest.",
          actions: [
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add images'),
            ),
          ],
        ),
      );
    }

    final total = _inputs.length;
    return FeatureLayout(
      header: header,
      preview: [_inputStrip()],
      options: [
        OptionCard(
          title: 'Batch',
          icon: Icons.speed_rounded,
          children: [
            LabeledSlider(
              label: 'Concurrency',
              valueLabel: '${_concurrency.round()} at a time',
              value: _concurrency,
              min: 1,
              max: 4,
              divisions: 3,
              onChanged: (v) => setState(() => _concurrency = v),
            ),
          ],
        ),
        OptionCard(
          title: 'Output',
          icon: Icons.tune_rounded,
          children: [
            OptionSegmented<PixelImageFormat>(
              label: 'Format',
              selected: _format,
              choices: [
                for (final f in PixelImageFormat.values)
                  Choice(
                    f,
                    f.name.toUpperCase(),
                    enabled: PlatformSupport.supportsFormat(f),
                  ),
              ],
              onChanged: (f) => setState(() => _format = f),
            ),
            LabeledSlider(
              label: 'Quality',
              valueLabel: '${_quality.round()}',
              value: _quality,
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (v) => setState(() => _quality = v),
            ),
            OptionSwitch(
              title: 'Limit size',
              subtitle: 'maxWidth / maxHeight',
              value: _limitSize,
              onChanged: (v) => setState(() => _limitSize = v),
            ),
            if (_limitSize)
              LabeledSlider(
                label: 'Longest side',
                valueLabel: '${_maxSide.round()} px',
                value: _maxSide,
                min: 320,
                max: 4000,
                divisions: 46,
                onChanged: (v) => setState(() => _maxSide = v),
              ),
          ],
        ),
      ],
      result: _resultView(),
      actions: Column(
        mainAxisSize: .min,
        children: [
          if (_busy) ...[
            LinearProgressIndicator(value: total == 0 ? null : _done / total),
            const SizedBox(height: Insets.sm),
          ],
          SizedBox(
            width: double.infinity,
            child: BusyButton(
              label: _busy
                  ? '$_done of $total done'
                  : 'Compress $total ${total == 1 ? 'image' : 'images'}',
              icon: Icons.bolt_rounded,
              busy: _busy,
              onPressed: _run,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputStrip() {
    final totalBytes = _inputs.fold<int>(0, (s, i) => s + i.image.size);
    return SourceCard(
      title: '${_inputs.length} images',
      onChange: _busy ? null : _pick,
      preview: SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _inputs.length,
          separatorBuilder: (_, _) => const SizedBox(width: Insets.sm),
          itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.circular(Insets.controlRadius),
            child: Image.memory(
              _inputs[i].image.bytes,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              cacheWidth: 288,
              errorBuilder: (context, _, _) => Container(
                width: 96,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: const Icon(Icons.image_outlined),
              ),
            ),
          ),
        ),
      ),
      chips: [
        StatChip(
          icon: Icons.sd_storage_rounded,
          label: formatBytes(totalBytes),
        ),
      ],
    );
  }

  Widget? _resultView() {
    final error = _error;
    if (error != null) {
      return ErrorBanner(key: ValueKey(error), error: error);
    }
    final results = _results;
    if (results == null) return null;

    var inBytes = 0, outBytes = 0, failed = 0;
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      if (r.isSuccess) {
        inBytes += _inputs[i].image.size;
        outBytes += r.bytes!.length;
      } else {
        failed++;
      }
    }

    return ResultCard(
      key: ValueKey(results),
      title: failed == 0
          ? 'All ${results.length} compressed'
          : '${results.length - failed} compressed, $failed failed',
      icon: failed == 0 ? Icons.check_circle_rounded : Icons.warning_rounded,
      children: [
        if (outBytes > 0)
          SavingsBadge(originalBytes: inBytes, outputBytes: outBytes),
        StatChips([
          if (_elapsed case final elapsed?)
            StatChip(
              icon: Icons.timer_outlined,
              label: formatDuration(elapsed),
            ),
          StatChip(
            icon: Icons.speed_rounded,
            label: 'concurrency ${_concurrency.round()}',
          ),
        ]),
        for (var i = 0; i < results.length; i++)
          _BatchRow(input: _inputs[i], item: results[i]),
      ],
    );
  }
}

class const _BatchRow({required this.input, required this.item})
    extends StatelessWidget {
  final _Input input;
  final PixelBatchItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final bytes = item.bytes;
    final info = item.info;
    return Row(
      children: [
        ClipRRect(
          borderRadius: .circular(10),
          child: SizedBox.square(
            dimension: 52,
            child: bytes == null
                ? ColoredBox(
                    color: theme.colorScheme.errorContainer,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  )
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 156,
                    errorBuilder: (context, _, _) =>
                        const Icon(Icons.image_outlined),
                  ),
          ),
        ),
        const SizedBox(width: Insets.sm + 4),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(
                input.image.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                item.isSuccess
                    ? '${formatBytes(input.image.size)} → ${formatBytes(bytes!.length)}'
                          '${info == null ? '' : ' · ${info.width}×${info.height}'}'
                    : '${item.error!.code ?? 'error'}: ${item.error!.message}',
                maxLines: 2,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: item.isSuccess
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
        ),
        Icon(
          item.isSuccess ? Icons.check_rounded : Icons.close_rounded,
          color: item.isSuccess ? palette.success : theme.colorScheme.error,
        ),
      ],
    );
  }
}
