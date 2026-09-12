import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'pages/batch_page.dart';
import 'pages/cache_page.dart';
import 'pages/capabilities_page.dart';
import 'pages/image_page.dart';
import 'pages/merge_page.dart';
import 'pages/metadata_page.dart';
import 'pages/thumbnails_page.dart';
import 'pages/video_page.dart';
import 'widgets/media_source_sheet.dart';

void main() {
  runApp(const PixelCompressorExampleApp());
}

const _defaultSeed = Color(0xFF4B3DCB);

class PixelCompressorExampleApp extends StatelessWidget {
  const PixelCompressorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pixel_compressor demo',
      theme: buildAppTheme(_defaultSeed),
      themeMode: ThemeMode.light,
      home: const HomePage(),
    );
  }
}

/// Light-only theme, parameterized by [seedColor] so each feature can get
/// its own visual identity (see [_Feature.color]) while sharing the same
/// structural styling (card shape/elevation, typography, input style).
/// Deliberately not relying on Material 3's default tonal surfaces (which
/// look flat/washed-out at low elevation) — cards are pure white with a
/// soft shadow and a hairline outline tinted by the seed, on a warm,
/// slightly off-white page background also tinted by the seed.
ThemeData buildAppTheme(Color seedColor) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  );
  final pageBackground = Color.alphaBlend(
    seedColor.withValues(alpha: 0.025),
    Colors.white,
  );
  const cardColor = Colors.white;
  const titleColor = Color(0xFF1B1B23);

  // Two-font pairing for visual hierarchy: Poppins (geometric, bold) for
  // headings/titles/buttons, Inter (neutral, highly legible) for body copy.
  final headingFont = GoogleFonts.poppins();
  final baseTextTheme = GoogleFonts.interTextTheme().apply(
    bodyColor: titleColor,
    displayColor: titleColor,
  );
  final textTheme = baseTextTheme.copyWith(
    headlineMedium: headingFont.copyWith(
      fontSize: baseTextTheme.headlineMedium?.fontSize,
      fontWeight: FontWeight.w800,
      color: titleColor,
      letterSpacing: -0.4,
    ),
    headlineSmall: headingFont.copyWith(
      fontSize: baseTextTheme.headlineSmall?.fontSize,
      fontWeight: FontWeight.w800,
      color: titleColor,
      letterSpacing: -0.3,
    ),
    titleLarge: headingFont.copyWith(
      fontWeight: FontWeight.w700,
      color: titleColor,
    ),
    titleMedium: headingFont.copyWith(
      fontWeight: FontWeight.w600,
      color: titleColor,
    ),
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: pageBackground,
    splashFactory: InkRipple.splashFactory,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: pageBackground,
      foregroundColor: titleColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: headingFont.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: titleColor,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 3,
      shadowColor: seedColor.withValues(alpha: 0.15),
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: seedColor.withValues(alpha: 0.08)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: const StadiumBorder(),
        textStyle: headingFont.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: const StadiumBorder(),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
        textStyle: headingFont.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: seedColor.withValues(alpha: 0.035),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

/// What kind of single-file picker (if any) a feature's "Next" step opens.
/// `null` means the feature doesn't fit a single gallery/camera pick —
/// Batch/Merge take multiple files via their own in-page picker, and
/// Metadata/Capabilities/Cache don't take a media file up front at all —
/// so those go straight to their page instead of through an intro step.
enum MediaPickerKind { image, video }

class _Feature {
  const _Feature({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.builder,
    this.mediaPicker,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;

  /// [initialFile] is the file picked during the intro step, if any —
  /// pages that don't take one (Batch/Merge/Metadata/Capabilities/Cache)
  /// simply ignore it.
  final Widget Function(BuildContext context, File? initialFile) builder;
  final MediaPickerKind? mediaPicker;
}

final List<_Feature> _features = [
  _Feature(
    label: 'Image',
    description: 'Quality, resize, rotate, EXIF, target size.',
    icon: Icons.image_outlined,
    color: const Color(0xFF3B82F6),
    mediaPicker: MediaPickerKind.image,
    builder: (_, file) => ImagePage(initialFile: file),
  ),
  _Feature(
    label: 'Video',
    description: 'Presets, codec, trim, target size.',
    icon: Icons.videocam_outlined,
    color: const Color(0xFFEF4444),
    mediaPicker: MediaPickerKind.video,
    builder: (_, file) => VideoPage(initialFile: file),
  ),
  _Feature(
    label: 'Batch',
    description: 'Compress many files in one call.',
    icon: Icons.collections_outlined,
    color: const Color(0xFF10B981),
    builder: (_, _) => const BatchPage(),
  ),
  _Feature(
    label: 'Merge',
    description: 'Stitch images together, pure Dart.',
    icon: Icons.merge_type,
    color: const Color(0xFF8B5CF6),
    builder: (_, _) => const MergePage(),
  ),
  _Feature(
    label: 'Thumbnails',
    description: 'Capture frames from a video.',
    icon: Icons.grid_view_outlined,
    color: const Color(0xFFF59E0B),
    mediaPicker: MediaPickerKind.video,
    builder: (_, file) => ThumbnailsPage(initialFile: file),
  ),
  _Feature(
    label: 'Metadata',
    description: 'Dimensions, duration, codec info.',
    icon: Icons.info_outline,
    color: const Color(0xFF06B6D4),
    builder: (_, _) => const MetadataPage(),
  ),
  _Feature(
    label: 'Capabilities',
    description: 'What this device can hardware-encode.',
    icon: Icons.memory,
    color: const Color(0xFF6366F1),
    builder: (_, _) => const CapabilitiesPage(),
  ),
  _Feature(
    label: 'Cache',
    description: "Inspect/clear the plugin's own cache.",
    icon: Icons.folder_outlined,
    color: const Color(0xFF14B8A6),
    builder: (_, _) => const CachePage(),
  ),
];

/// Landing page — every feature is reachable from here as its own row
/// tile. No drawer/sidebar: this page *is* the nav. Tiles size themselves
/// to their content (icon + two lines of text), never to a width-derived
/// aspect ratio.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('pixel_compressor')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The engine can report a transient 0-width first frame during
            // startup on some devices — guard against it explicitly rather
            // than let the width math below go negative and crash.
            if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 0) {
              return const SizedBox.shrink();
            }
            const spacing = 12.0;
            const horizontalPadding = 32.0;
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 600
                ? 2
                : 1;
            final availableWidth = constraints.maxWidth - horizontalPadding;
            final tileWidth =
                ((availableWidth - spacing * (columns - 1)) / columns).clamp(
                  0.0,
                  double.infinity,
                );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final feature in _features)
                    SizedBox(
                      width: tileWidth,
                      child: _FeatureTile(feature: feature),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.feature});

  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _FeatureIntroPage(feature: feature),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: feature.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(feature.icon, color: feature.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.label,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      feature.description,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: feature.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step between the home page and a feature's real page: shows the
/// feature's identity (icon/name/description) in its own color theme,
/// with a single "Next" action. For features with a [_Feature.mediaPicker],
/// Next opens the gallery/camera chooser immediately — the feature page
/// itself then opens already populated with whatever was picked. Features
/// with no single-file picker (Batch/Merge take multiple; Metadata/
/// Capabilities/Cache don't take a file up front) go straight through to
/// their page instead.
class _FeatureIntroPage extends StatefulWidget {
  const _FeatureIntroPage({super.key, required this.feature});

  final _Feature feature;

  @override
  State<_FeatureIntroPage> createState() => _FeatureIntroPageState();
}

class _FeatureIntroPageState extends State<_FeatureIntroPage> {
  bool _working = false;

  Future<void> _next() async {
    final feature = widget.feature;
    final pickerKind = feature.mediaPicker;
    if (pickerKind == null) {
      _openFeaturePage(null);
      return;
    }

    setState(() => _working = true);
    try {
      final source = await showMediaSourceSheet(
        context,
        captureLabel: pickerKind == MediaPickerKind.video
            ? 'Record a video'
            : 'Take a photo',
      );
      if (source == null) return;
      final picker = ImagePicker();
      final picked = pickerKind == MediaPickerKind.video
          ? await picker.pickVideo(source: source)
          : await picker.pickImage(source: source);
      if (picked == null) return;
      if (mounted) _openFeaturePage(File(picked.path));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _openFeaturePage(File? file) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            _FeaturePageScaffold(feature: widget.feature, initialFile: file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    return Theme(
      data: buildAppTheme(feature.color),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(feature.label)),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                feature.color,
                                feature.color.withValues(alpha: 0.78),
                              ],
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(36),
                              bottomRight: Radius.circular(36),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 92,
                                height: 92,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  feature.icon,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                feature.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                feature.description,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: Colors.black87,
                                      height: 1.4,
                                    ),
                              ),
                              if (feature.mediaPicker != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Next, choose a photo from your gallery or capture a new one.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.black45),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _working ? null : _next,
                      child: _working
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Next'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The feature's real page, themed in its own color, given whatever file
/// (if any) the intro step already picked.
class _FeaturePageScaffold extends StatelessWidget {
  const _FeaturePageScaffold({required this.feature, this.initialFile});

  final _Feature feature;
  final File? initialFile;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAppTheme(feature.color),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(feature.label)),
          body: SafeArea(
            top: false,
            child: feature.builder(context, initialFile),
          ),
        ),
      ),
    );
  }
}
