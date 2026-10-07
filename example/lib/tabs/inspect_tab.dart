import 'package:flutter/material.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../utils/format.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../widgets/widgets.dart';

/// Read-only info: `PixelImageInfo.fromBytes` (image headers, every platform)
/// and `PixelVideoCompressor.readMediaInfo` (video).
class const InspectTab({super.key}) extends StatefulWidget {
  @override
  State<InspectTab> createState() => _InspectTabState();
}

class _InspectTabState()
    extends State<InspectTab>
    with AutomaticKeepAliveClientMixin {
  PickedImage? _image;
  PixelImageInfo? _imageInfo;
  Duration? _imageParseTime;

  String? _videoPath;
  PixelMediaInfo? _videoInfo;
  bool _videoBusy = false;
  Object? _videoError;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pickImage() async {
    final picked = await pickImages(context);
    if (picked == null || picked.isEmpty || !mounted) return;
    final stopwatch = Stopwatch()..start();
    final info = PixelImageInfo.fromBytes(picked.first.bytes);
    final elapsed = stopwatch.elapsed;
    setState(() {
      _image = picked.first;
      _imageInfo = info;
      _imageParseTime = elapsed;
    });
  }

  Future<void> _pickVideo() async {
    final path = await pickVideo(context);
    if (path == null || !mounted) return;
    setState(() {
      _videoPath = path;
      _videoInfo = null;
      _videoError = null;
      _videoBusy = true;
    });
    try {
      final info = await PixelVideoCompressor.readMediaInfo(path);
      if (mounted) setState(() => _videoInfo = info);
    } catch (e) {
      // readMediaInfo reports native failures as a null result internally,
      // which surfaces here as a TypeError.
      if (mounted) {
        setState(
          () => _videoError = ExampleError("Couldn't read this video: $e"),
        );
      }
    } finally {
      if (mounted) setState(() => _videoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FeatureLayout(
      header: const HeroHeader(
        icon: Icons.info_outline_rounded,
        title: 'Inspect',
        subtitle: 'Dimensions, format and orientation without compressing',
      ),
      options: [_imageCard(), _videoCard()],
    );
  }

  Widget _imageCard() {
    final image = _image;
    final info = _imageInfo;
    return OptionCard(
      title: 'Image header · PixelImageInfo',
      icon: Icons.image_search_rounded,
      trailing: TextButton.icon(
        onPressed: _pickImage,
        icon: Icon(
          image == null ? Icons.add_rounded : Icons.swap_horiz_rounded,
          size: 18,
        ),
        label: Text(image == null ? 'Pick' : 'Change'),
      ),
      children: [
        if (image == null)
          const PlatformHint(
            'Reads JPEG, PNG, WebP, HEIC, GIF and BMP headers in pure Dart, '
            'without decoding pixels. Works on every platform.',
          )
        else ...[
          ImagePreview(bytes: image.bytes, height: 180, label: image.name),
          if (info == null)
            const ErrorBanner(
              error: ExampleError('Unrecognised or truncated image header.'),
            )
          else
            InfoTable([
              ('Format', info.format?.name.toUpperCase() ?? 'Other (measured)'),
              ('Displayed size', '${info.width} × ${info.height}'),
              (
                'Orientation',
                '${info.orientation} · ${describeOrientation(info.orientation)}',
              ),
              ('File size', formatBytes(image.size)),
              if (_imageParseTime case final t?)
                ('Parsed in', '${t.inMicroseconds} µs'),
            ]),
        ],
      ],
    );
  }

  Widget _videoCard() {
    final info = _videoInfo;
    final error = _videoError;
    return OptionCard(
      title: 'Video · readMediaInfo',
      icon: Icons.video_file_outlined,
      trailing: PlatformSupport.video
          ? TextButton.icon(
              onPressed: _videoBusy ? null : _pickVideo,
              icon: Icon(
                _videoPath == null
                    ? Icons.add_rounded
                    : Icons.swap_horiz_rounded,
                size: 18,
              ),
              label: Text(_videoPath == null ? 'Pick' : 'Change'),
            )
          : null,
      children: [
        if (!PlatformSupport.video)
          PlatformHint('Video is not available on ${PlatformSupport.name}.')
        else if (_videoPath == null)
          const PlatformHint(
            'Title, author, dimensions, orientation, file size and duration.',
          )
        else if (_videoBusy)
          const ShimmerBox(height: 160)
        else if (error != null)
          ErrorBanner(error: error)
        else if (info != null)
          InfoTable([
            ('Path', info.path ?? '–'),
            if (info.title?.isNotEmpty ?? false) ('Title', info.title!),
            if (info.author?.isNotEmpty ?? false) ('Author', info.author!),
            ('Dimensions', '${info.width ?? '?'} × ${info.height ?? '?'}'),
            ('Orientation', '${info.orientation ?? 0}°'),
            ('File size', formatBytes(info.filesize ?? 0)),
            (
              'Duration',
              formatDuration(
                Duration(milliseconds: (info.duration ?? 0).round()),
              ),
            ),
          ]),
      ],
    );
  }
}
