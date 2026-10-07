import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../widgets/widgets.dart';

enum _SizeMode() {
  min,
  max,
  exact,
}

enum _Output() {
  bytes,
  file,
}

class const _Result({
  required this.bytes,
  required this.info,
  required this.api,
  required this.elapsed,
  this.path,
}) {
  final Uint8List bytes;
  final PixelImageInfo? info;
  final String api;
  final Duration elapsed;
  final String? path;
}

/// Single-image compression with every `PixelImageCompressor` option.
class const ImageTab({super.key}) extends StatefulWidget {
  @override
  State<ImageTab> createState() => _ImageTabState();
}

class _ImageTabState()
    extends State<ImageTab>
    with AutomaticKeepAliveClientMixin {
  PickedImage? _source;
  PixelImageInfo? _sourceInfo;

  PixelImageFormat _format = .jpeg;
  double _quality = 80;
  _SizeMode _sizeMode = _SizeMode.min;
  double _minWidth = 1920, _minHeight = 1080;
  double _maxWidth = 1280, _maxHeight = 1280;
  double _exactWidth = 1080, _exactHeight = 1080;
  PixelImageFit _fit = .contain;
  int _padColor = 0xFF000000;
  int _rotate = 0;
  bool _autoCorrect = true;
  bool _keepExif = false;
  int _inSampleSize = 1;
  double _retries = 5;
  _Output _output = _Output.bytes;

  bool _busy = false;
  Object? _error;
  _Result? _result;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pick() async {
    final picked = await pickImages(context);
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _source = picked.first;
      _sourceInfo = .fromBytes(picked.first.bytes);
      _result = null;
      _error = null;
    });
  }

  Future<void> _compress() async {
    final source = _source;
    if (source == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _error = null;
    });

    final exactSize = _sizeMode == _SizeMode.exact
        ? PixelExactSize(
            _exactWidth.round(),
            _exactHeight.round(),
            fit: _fit,
            padColor: _padColor,
          )
        : null;
    final minWidth = _sizeMode == _SizeMode.min ? _minWidth.round() : 1920;
    final minHeight = _sizeMode == _SizeMode.min ? _minHeight.round() : 1080;
    final maxWidth = _sizeMode == _SizeMode.max ? _maxWidth.round() : null;
    final maxHeight = _sizeMode == _SizeMode.max ? _maxHeight.round() : null;
    final quality = _quality.round();
    final retries = _retries.round();
    final stopwatch = Stopwatch()..start();

    try {
      final _Result result;
      if (_output == _Output.file) {
        // compressFileToFile: the target extension must match the format.
        final path = await materialize(source);
        final target = await outputPathFor(source.name, extensionFor(_format));
        final file = await PixelImageCompressor.compressFileToFile(
          path,
          target,
          minWidth: minWidth,
          minHeight: minHeight,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          exactSize: exactSize,
          inSampleSize: _inSampleSize,
          quality: quality,
          rotate: _rotate,
          autoCorrectionAngle: _autoCorrect,
          format: _format,
          keepExif: _keepExif,
          numberOfRetries: retries,
        );
        final bytes = await file.readAsBytes();
        result = _Result(
          bytes: bytes,
          info: .fromBytes(bytes),
          api: 'compressFileToFile',
          elapsed: stopwatch.elapsed,
          path: file.path,
        );
      } else if (source.asset case final asset?) {
        final bytes = await PixelImageCompressor.compressAsset(
          asset,
          minWidth: minWidth,
          minHeight: minHeight,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          exactSize: exactSize,
          quality: quality,
          rotate: _rotate,
          autoCorrectionAngle: _autoCorrect,
          format: _format,
          keepExif: _keepExif,
        );
        result = _Result(
          bytes: bytes,
          info: .fromBytes(bytes),
          api: 'compressAsset',
          elapsed: stopwatch.elapsed,
        );
      } else if (source.path case final path?) {
        final r = await PixelImageCompressor.compressFileWithInfo(
          path,
          minWidth: minWidth,
          minHeight: minHeight,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          exactSize: exactSize,
          inSampleSize: _inSampleSize,
          quality: quality,
          rotate: _rotate,
          autoCorrectionAngle: _autoCorrect,
          format: _format,
          keepExif: _keepExif,
          numberOfRetries: retries,
        );
        result = _Result(
          bytes: r.bytes,
          info: r.info,
          api: 'compressFileWithInfo',
          elapsed: stopwatch.elapsed,
        );
      } else {
        // Web picks have no path: compress the bytes.
        final r = await PixelImageCompressor.compressBytesWithInfo(
          source.bytes,
          minWidth: minWidth,
          minHeight: minHeight,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          exactSize: exactSize,
          inSampleSize: _inSampleSize,
          quality: quality,
          rotate: _rotate,
          autoCorrectionAngle: _autoCorrect,
          format: _format,
          keepExif: _keepExif,
        );
        result = _Result(
          bytes: r.bytes,
          info: r.info,
          api: 'compressBytesWithInfo',
          elapsed: stopwatch.elapsed,
        );
      }
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _result = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final source = _source;
    const header = HeroHeader(
      icon: Icons.photo_size_select_large_rounded,
      title: 'Image',
      subtitle: 'JPEG · PNG · WebP · HEIC with resize, rotation and EXIF',
    );

    if (source == null) {
      return FeatureLayout(
        header: header,
        empty: EmptyState(
          icon: Icons.add_photo_alternate_rounded,
          title: 'Pick an image to compress',
          message:
              'Choose a photo, take one, or start with a bundled sample. '
              'Every option of PixelImageCompressor is below.',
          actions: [
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add image'),
            ),
          ],
        ),
      );
    }

    final info = _sourceInfo;
    return FeatureLayout(
      header: header,
      preview: [
        SourceCard(
          title: source.name,
          onChange: _busy ? null : _pick,
          preview: ImagePreview(bytes: source.bytes, height: 220),
          chips: [
            StatChip(
              icon: Icons.sd_storage_rounded,
              label: formatBytes(source.size),
            ),
            if (info != null) ...[
              StatChip(
                icon: Icons.aspect_ratio_rounded,
                label: '${info.width} × ${info.height}',
              ),
              StatChip(
                icon: Icons.image_outlined,
                label: info.format?.name.toUpperCase() ?? 'Other',
              ),
              if (info.orientation != 1)
                StatChip(
                  icon: Icons.screen_rotation_rounded,
                  label: 'EXIF ${info.orientation}',
                ),
            ],
            StatChip(
              icon: Icons.source_rounded,
              label: source.asset != null ? 'Asset' : 'File',
            ),
          ],
        ),
      ],
      options: _options(),
      result: _resultView(source),
      actions: BusyButton(
        label: _busy ? 'Compressing…' : 'Compress',
        icon: Icons.compress_rounded,
        busy: _busy,
        onPressed: _compress,
      ),
    );
  }

  List<Widget> _options() {
    final unsupported = [
      for (final f in PixelImageFormat.values)
        if (!PlatformSupport.supportsFormat(f)) f.name.toUpperCase(),
    ];
    return [
      OptionCard(
        title: 'Format & quality',
        icon: Icons.palette_outlined,
        children: [
          OptionSegmented<PixelImageFormat>(
            label: 'Output format',
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
            hint: unsupported.isEmpty
                ? null
                : '${unsupported.join(', ')} not available on '
                      '${PlatformSupport.name}',
          ),
          LabeledSlider(
            label: _format == .png ? 'Quality (ignored by PNG)' : 'Quality',
            valueLabel: '${_quality.round()}',
            value: _quality,
            min: 1,
            max: 100,
            divisions: 99,
            onChanged: (v) => setState(() => _quality = v),
          ),
        ],
      ),
      OptionCard(
        title: 'Size',
        icon: Icons.photo_size_select_small_rounded,
        children: [
          OptionSegmented<_SizeMode>(
            label: 'Resize mode',
            selected: _sizeMode,
            choices: const [
              Choice(_SizeMode.min, 'Min'),
              Choice(_SizeMode.max, 'Max'),
              Choice(_SizeMode.exact, 'Exact'),
            ],
            onChanged: (m) => setState(() => _sizeMode = m),
          ),
          ...switch (_sizeMode) {
            _SizeMode.min => [
              _hint(
                'minWidth / minHeight: scale down, keeping the aspect '
                'ratio, until one side reaches the minimum.',
              ),
              _dimSlider('Min width', _minWidth, (v) => _minWidth = v),
              _dimSlider('Min height', _minHeight, (v) => _minHeight = v),
            ],
            _SizeMode.max => [
              _hint(
                'maxWidth / maxHeight: fit inside this box, never upscale.',
              ),
              _dimSlider('Max width', _maxWidth, (v) => _maxWidth = v),
              _dimSlider('Max height', _maxHeight, (v) => _maxHeight = v),
            ],
            _SizeMode.exact => [
              _hint('PixelExactSize: exactly this many pixels, applied last.'),
              _dimSlider('Width', _exactWidth, (v) => _exactWidth = v),
              _dimSlider('Height', _exactHeight, (v) => _exactHeight = v),
              OptionSegmented<PixelImageFit>(
                label: 'Fit',
                selected: _fit,
                choices: const [
                  Choice(.contain, 'Contain'),
                  Choice(.cover, 'Cover'),
                  Choice(.stretch, 'Stretch'),
                ],
                onChanged: (f) => setState(() => _fit = f),
              ),
              if (_fit == .contain) _padColorPicker(),
            ],
          },
        ],
      ),
      OptionCard(
        title: 'Orientation & metadata',
        icon: Icons.screen_rotation_alt_rounded,
        children: [
          OptionSegmented<int>(
            label: 'Rotate',
            selected: _rotate,
            choices: const [
              Choice(0, '0°'),
              Choice(90, '90°'),
              Choice(180, '180°'),
              Choice(270, '270°'),
            ],
            onChanged: PlatformSupport.exif
                ? (r) => setState(() => _rotate = r)
                : null,
          ),
          OptionSwitch(
            title: 'Auto-correct angle',
            subtitle: 'Apply the EXIF orientation (try the Portrait sample)',
            hint: PlatformSupport.exif
                ? null
                : 'Not on ${PlatformSupport.name}',
            value: _autoCorrect,
            onChanged: (v) => setState(() => _autoCorrect = v),
          ),
          OptionSwitch(
            title: 'Keep EXIF',
            subtitle: 'Copy camera metadata into the output',
            hint: PlatformSupport.exif
                ? null
                : 'Not on ${PlatformSupport.name}',
            value: _keepExif,
            onChanged: (v) => setState(() => _keepExif = v),
          ),
        ],
      ),
      OptionCard(
        title: 'Output',
        icon: Icons.output_rounded,
        children: [
          OptionSegmented<_Output>(
            label: 'Return',
            selected: _output,
            choices: [
              const Choice(_Output.bytes, 'Bytes', icon: Icons.memory_rounded),
              Choice(
                _Output.file,
                'File',
                icon: Icons.insert_drive_file_outlined,
                enabled: PlatformSupport.files,
              ),
            ],
            onChanged: (o) => setState(() => _output = o),
            hint: PlatformSupport.files
                ? null
                : 'Files are not available on the web',
          ),
          _hint(switch ((_output, _source)) {
            (_Output.file, _) =>
              'Calls compressFileToFile into the temp folder.',
            (_, PickedImage(asset: _?)) => 'Calls compressAsset.',
            (_, PickedImage(path: _?)) => 'Calls compressFileWithInfo.',
            _ => 'Calls compressBytesWithInfo.',
          }),
        ],
      ),
      AdvancedSection(
        children: [
          OptionSegmented<int>(
            label: 'inSampleSize (Android decode subsampling)',
            selected: _inSampleSize,
            choices: const [
              Choice(1, '1'),
              Choice(2, '2'),
              Choice(4, '4'),
              Choice(8, '8'),
            ],
            onChanged: (v) => setState(() => _inSampleSize = v),
          ),
          LabeledSlider(
            label: 'numberOfRetries (file APIs, on out-of-memory)',
            valueLabel: '${_retries.round()}',
            value: _retries,
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (v) => setState(() => _retries = v),
          ),
        ],
      ),
    ];
  }

  Widget _hint(String text) => PlatformHint(text);

  Widget _dimSlider(String label, double value, void Function(double) set) =>
      LabeledSlider(
        label: label,
        valueLabel: '${value.round()} px',
        value: value,
        min: 100,
        max: 4000,
        divisions: 39,
        onChanged: (v) => setState(() => set(v)),
      );

  Widget _padColorPicker() {
    const colors = {
      0xFF000000: 'Black',
      0xFFFFFFFF: 'White',
      0xFF5B4BDB: 'Violet',
      0xFF0F766E: 'Teal',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: .center,
      children: [
        Text('Padding', style: Theme.of(context).textTheme.bodyMedium),
        for (final MapEntry(key: argb, value: name) in colors.entries)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: Color(argb), radius: 8),
            label: Text(name),
            selected: _padColor == argb,
            onSelected: (_) => setState(() => _padColor = argb),
          ),
      ],
    );
  }

  Widget? _resultView(PickedImage source) {
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
    final info = result.info;
    return ResultCard(
      key: ValueKey(result),
      title: 'Compressed',
      children: [
        BeforeAfter(before: source.bytes, after: result.bytes),
        SavingsBadge(
          originalBytes: source.size,
          outputBytes: result.bytes.length,
        ),
        SizeComparisonBar(
          originalBytes: source.size,
          outputBytes: result.bytes.length,
        ),
        StatChips([
          if (info != null) ...[
            StatChip(
              icon: Icons.aspect_ratio_rounded,
              label: '${info.width} × ${info.height}',
            ),
            StatChip(
              icon: Icons.image_outlined,
              label: info.format?.name.toUpperCase() ?? 'Other',
            ),
            StatChip(
              icon: Icons.screen_rotation_rounded,
              label: describeOrientation(info.orientation),
            ),
          ],
          StatChip(
            icon: Icons.timer_outlined,
            label: formatDuration(result.elapsed),
          ),
          StatChip(icon: Icons.code_rounded, label: result.api),
        ]),
        if (result.path case final path?)
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
