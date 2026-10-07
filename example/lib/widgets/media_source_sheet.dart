import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../theme/app_theme.dart';
import '../utils/media.dart';
import '../utils/platform_support.dart';
import '../utils/web_file_picker.dart';

/// What the user chose in [showMediaSourceSheet].
sealed class const MediaChoice();

/// The device gallery (or the browser's file dialog on the web).
class const PickFromGallery() extends MediaChoice;

/// A bundled sample; [sample] is null for "all samples".
class const UseSample(this.sample) extends MediaChoice {
  final Sample? sample;
}

/// Bottom sheet: gallery and, for images, the bundled samples. Goes straight
/// to the gallery when that's the only option.
Future<MediaChoice?> showMediaSourceSheet(
  BuildContext context, {
  required String title,
  bool showSamples = false,
  bool multiple = false,
}) {
  if (!showSamples) {
    return .value(const PickFromGallery());
  }
  return showModalBottomSheet<MediaChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const .fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: Insets.md + 4),
              _SourceOption(
                icon: Icons.photo_library_rounded,
                label: PlatformSupport.isWeb ? 'Browse' : 'Gallery',
                color: theme.colorScheme.primary,
                onTap: () => Navigator.of(context).pop(const PickFromGallery()),
              ),
              if (showSamples) ...[
                const SizedBox(height: Insets.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text('Samples', style: theme.textTheme.titleSmall),
                    ),
                    if (multiple)
                      TextButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(const UseSample(null)),
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Use all'),
                      ),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: samples.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: Insets.sm + 4),
                    itemBuilder: (context, i) => _SampleTile(
                      sample: samples[i],
                      onTap: () =>
                          Navigator.of(context).pop(UseSample(samples[i])),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class const _SourceOption({
  required this.icon,
  required this.label,
  required this.color,
  required this.onTap,
}) extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(Insets.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Insets.cardRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.md + 4),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color, shape: .circle),
                child: Icon(icon, color: theme.colorScheme.surface, size: 26),
              ),
              const SizedBox(height: Insets.sm + 4),
              Text(label, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class const _SampleTile({required this.sample, required this.onTap})
    extends StatelessWidget {
  final Sample sample;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 112,
      child: InkWell(
        borderRadius: BorderRadius.circular(Insets.controlRadius),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: .start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Insets.controlRadius),
              child: Image.asset(
                sample.asset,
                width: 112,
                height: 84,
                fit: BoxFit.cover,
                cacheWidth: 336,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sample.label,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.labelMedium,
            ),
            Text(
              sample.description,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks one or more images via [showMediaSourceSheet]. Returns null when
/// the user backs out.
Future<List<PickedImage>?> pickImages(
  BuildContext context, {
  bool multiple = false,
}) async {
  final choice = await showMediaSourceSheet(
    context,
    title: multiple ? 'Add images' : 'Add an image',
    showSamples: true,
    multiple: multiple,
  );
  switch (choice) {
    case null:
      return null;
    case UseSample(:final sample):
      return [
        for (final s in sample == null ? samples : [sample])
          await .fromSample(s),
      ];
    case PickFromGallery():
      if (kIsWeb) {
        final files = await pickWebFiles(accept: 'image/*', multiple: multiple);
        return files.isEmpty ? null : files.map(PickedImage.fromWeb).toList();
      }
      if (!context.mounted) return null;
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: multiple ? _maxImages : 1,
          requestType: .image,
        ),
      );
      if (assets == null || assets.isEmpty) return null;
      final images = [
        for (final asset in assets) ?await PickedImage.fromAssetEntity(asset),
      ];
      return images.isEmpty ? null : images;
  }
}

/// Upper bound for multi-select (batch and merge).
const _maxImages = 20;

/// Picks a video from the gallery. Returns its path, or null.
Future<String?> pickVideo(BuildContext context) async {
  final assets = await AssetPicker.pickAssets(
    context,
    pickerConfig: const AssetPickerConfig(maxAssets: 1, requestType: .video),
  );
  final file = await assets?.firstOrNull?.originFile;
  return file?.path;
}
