import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../widgets/widgets.dart';

class const _Result(this.merge, this.api) {
  final PixelMergeResult merge;
  final String api;
}

/// `PixelMergeView` live preview + `PixelMergeCaptureController`, and the
/// headless `PixelImageMerger.merge`.
class const MergeTab({super.key}) extends StatefulWidget {
  @override
  State<MergeTab> createState() => _MergeTabState();
}

class _MergeTabState()
    extends State<MergeTab>
    with AutomaticKeepAliveClientMixin {
  final _controller = PixelMergeCaptureController();
  List<PickedImage> _picked = const [];
  List<PixelMergeSource> _sources = const [];

  PixelMergeLayout _layout = .vertical;
  double _gridColumns = 2;
  double _spacing = 16;
  double _padding = 16;
  double _cornerRadius = 24;
  PixelMergeAlignment _alignment = .center;
  bool _scaleToFit = true;
  Color _background = const Color(0xFFFFFFFF);
  PixelImageFormat _format = .jpeg;
  double _quality = 85;
  bool _limitOutput = false;
  double _maxSide = 2048;

  /// Kept as one instance: PixelMergeView re-renders whenever it gets a
  /// different options object, so only rebuild it when an option changes.
  late PixelMergeOptions _options = _buildOptions();

  bool _busy = false;
  Object? _error;
  _Result? _result;

  @override
  bool get wantKeepAlive => true;

  PixelMergeOptions _buildOptions() => PixelMergeOptions(
    layout: _layout,
    gridColumns: _gridColumns.round(),
    spacing: _spacing,
    padding: _padding,
    cornerRadius: _cornerRadius,
    alignment: _alignment,
    scaleToFit: _scaleToFit,
    background: _background,
    format: _format,
    quality: _quality.round(),
    maxOutputWidth: _limitOutput ? _maxSide.round() : null,
    maxOutputHeight: _limitOutput ? _maxSide.round() : null,
  );

  void _set(VoidCallback change) => setState(() {
    change();
    _options = _buildOptions();
  });

  Future<void> _pick() async {
    final picked = await pickImages(context, multiple: true);
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _picked = picked;
      _sources = [
        for (final p in picked)
          if (p.asset case final asset?)
            PixelMergeSource.asset(asset)
          else if (p.path case final path?)
            PixelMergeSource.file(path)
          else
            PixelMergeSource.bytes(p.bytes),
      ];
      _result = null;
      _error = picked.length < 2
          ? const ExampleError('Pick at least 2 images to merge.')
          : null;
    });
  }

  Future<void> _run({required bool headless}) async {
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final PixelMergeResult result;
      if (headless) {
        final outputPath = PlatformSupport.files
            ? await outputPathFor('merged', extensionFor(_format))
            : null;
        result = await PixelImageMerger.merge(
          _sources,
          options: outputPath == null
              ? _options
              : _options.copyWith(outputPath: outputPath),
        );
      } else {
        // Re-renders what the view shows at full output resolution.
        result = await _controller.capture();
      }
      if (mounted) {
        setState(
          () => _result = _Result(
            result,
            headless
                ? 'PixelImageMerger.merge'
                : 'PixelMergeCaptureController.capture',
          ),
        );
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
      icon: Icons.dashboard_customize_rounded,
      title: 'Merge',
      subtitle: 'Stitch images into a strip or a grid, live preview',
    );
    if (_picked.isEmpty) {
      return FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.auto_awesome_mosaic_rounded,
          title: 'Combine images',
          message:
              'Vertical, horizontal or justified grid. Pure Dart, so it '
              'works on every platform including the web.',
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

    final canMerge = _sources.length >= 2;
    return FeatureLayout(
      header: header,
      preview: [_previewCard(canMerge)],
      options: _optionCards(),
      result: _resultView(),
      actions: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy || !canMerge
                  ? null
                  : () => _run(headless: false),
              icon: const Icon(Icons.camera_rounded),
              label: const FittedBox(child: Text('Export view')),
            ),
          ),
          const SizedBox(width: Insets.sm + 4),
          Expanded(
            child: BusyButton(
              label: 'Merge',
              icon: Icons.merge_rounded,
              busy: _busy,
              onPressed: canMerge ? () => _run(headless: true) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(bool canMerge) {
    return SourceCard(
      title: '${_picked.length} images',
      onChange: _busy ? null : _pick,
      preview: canMerge
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: Center(
                child: PixelMergeView(
                  sources: _sources,
                  options: _options,
                  controller: _controller,
                  placeholder: const ShimmerBox(height: 280),
                  errorBuilder: (context, error) => ErrorBanner(error: error),
                ),
              ),
            )
          : null,
      chips: [
        const StatChip(icon: Icons.visibility_rounded, label: 'PixelMergeView'),
        StatChip(
          icon: Icons.sd_storage_rounded,
          label: formatBytes(_picked.fold(0, (s, p) => s + p.size)),
        ),
      ],
    );
  }

  List<Widget> _optionCards() {
    return [
      OptionCard(
        title: 'Layout',
        icon: Icons.view_quilt_rounded,
        children: [
          OptionSegmented<PixelMergeLayout>(
            label: 'Arrangement',
            selected: _layout,
            choices: const [
              Choice(.vertical, 'Vertical', icon: Icons.view_agenda_outlined),
              Choice(.horizontal, 'Horizontal', icon: Icons.view_week_outlined),
              Choice(.grid, 'Grid', icon: Icons.grid_view_rounded),
            ],
            onChanged: (v) => _set(() => _layout = v),
          ),
          if (_layout == .grid)
            LabeledSlider(
              label: 'Grid columns',
              valueLabel: '${_gridColumns.round()}',
              value: _gridColumns,
              min: 2,
              max: 5,
              divisions: 3,
              onChanged: (v) => _set(() => _gridColumns = v),
            ),
          OptionSegmented<PixelMergeAlignment>(
            label: 'Cross-axis alignment',
            selected: _alignment,
            choices: const [
              Choice(.start, 'Start'),
              Choice(.center, 'Center'),
              Choice(.end, 'End'),
            ],
            onChanged: (v) => _set(() => _alignment = v),
            hint: _scaleToFit
                ? 'Matters with scale-to-fit off or a short last grid row'
                : null,
          ),
          OptionSwitch(
            title: 'Scale to fit',
            subtitle: 'Images share the cross-axis size (justified grid)',
            value: _scaleToFit,
            onChanged: (v) => _set(() => _scaleToFit = v),
          ),
        ],
      ),
      OptionCard(
        title: 'Style',
        icon: Icons.brush_rounded,
        children: [
          _pxSlider('Spacing', _spacing, (v) => _spacing = v),
          _pxSlider('Padding', _padding, (v) => _padding = v),
          _pxSlider('Corner radius', _cornerRadius, (v) => _cornerRadius = v),
          _backgroundPicker(),
        ],
      ),
      OptionCard(
        title: 'Output',
        icon: Icons.output_rounded,
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
            onChanged: (v) => _set(() => _format = v),
            hint: _format == .png
                ? null
                : 'JPEG and HEIC have no alpha: the background is made opaque',
          ),
          if (_format != .png)
            LabeledSlider(
              label: 'Quality',
              valueLabel: '${_quality.round()}',
              value: _quality,
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (v) => _set(() => _quality = v),
            ),
          OptionSwitch(
            title: 'Limit output size',
            subtitle: 'Default: long side 4096 px (hard cap 8192 / 32 MP)',
            value: _limitOutput,
            onChanged: (v) => _set(() => _limitOutput = v),
          ),
          if (_limitOutput)
            LabeledSlider(
              label: 'Longest side',
              valueLabel: '${_maxSide.round()} px',
              value: _maxSide,
              min: 512,
              max: 8192,
              divisions: 30,
              onChanged: (v) => _set(() => _maxSide = v),
            ),
        ],
      ),
    ];
  }

  Widget _pxSlider(String label, double value, void Function(double) set) =>
      LabeledSlider(
        label: label,
        valueLabel: '${value.round()} px',
        value: value,
        min: 0,
        max: 64,
        divisions: 16,
        onChanged: (v) => _set(() => set(v)),
      );

  Widget _backgroundPicker() {
    const colors = {
      'White': Color(0xFFFFFFFF),
      'Ink': Color(0xFF111827),
      'Lilac': Color(0xFFEDE9FE),
      'Clear': Color(0x00000000),
    };
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text('Background', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final MapEntry(key: name, value: color) in colors.entries)
              ChoiceChip(
                avatar: CircleAvatar(
                  radius: 8,
                  backgroundColor: color.a == 0
                      ? Theme.of(context).colorScheme.surface
                      : color,
                  child: color.a == 0
                      ? const Icon(Icons.block_rounded, size: 12)
                      : null,
                ),
                label: Text(name),
                selected: _background == color,
                onSelected: (_) => _set(() => _background = color),
              ),
          ],
        ),
      ],
    );
  }

  Widget? _resultView() {
    final error = _error;
    if (error != null) {
      return ErrorBanner(
        key: ValueKey(error),
        error: error,
        onDismiss: () => setState(() => _error = null),
      );
    }
    final result = _result;
    if (result == null) return null;
    final merge = result.merge;
    return ResultCard(
      key: ValueKey(result),
      title: 'Merged ${merge.sourceCount} images',
      children: [
        ImagePreview(bytes: merge.bytes, height: 280, label: 'Output'),
        StatChips([
          StatChip(
            icon: Icons.aspect_ratio_rounded,
            label: '${merge.width} × ${merge.height}',
          ),
          StatChip(
            icon: Icons.image_outlined,
            label: merge.format.name.toUpperCase(),
          ),
          StatChip(
            icon: Icons.sd_storage_rounded,
            label: formatBytes(merge.bytes.length),
          ),
          StatChip(
            icon: Icons.timer_outlined,
            label: formatDuration(merge.elapsed),
          ),
          StatChip(icon: Icons.code_rounded, label: result.api),
        ]),
        if (merge.path case final path?)
          SelectableText(
            path,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
