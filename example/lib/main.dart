import 'package:flutter/material.dart';

import 'tabs/batch_tab.dart';
import 'tabs/image_tab.dart';
import 'tabs/inspect_tab.dart';
import 'tabs/merge_tab.dart';
import 'tabs/thumbnails_tab.dart';
import 'tabs/tools_tab.dart';
import 'tabs/video_tab.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PixelCompressorExampleApp());
}

class const PixelCompressorExampleApp({super.key}) extends StatefulWidget {
  @override
  State<PixelCompressorExampleApp> createState() =>
      _PixelCompressorExampleAppState();
}

class _PixelCompressorExampleAppState()
    extends State<PixelCompressorExampleApp> {
  ThemeMode _themeMode = .system;

  void _cycleTheme() => setState(
    () => _themeMode = switch (_themeMode) {
      .system => .light,
      .light => .dark,
      .dark => .system,
    },
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pixel_compressor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: HomePage(themeMode: _themeMode, onCycleTheme: _cycleTheme),
    );
  }
}

class const _TabSpec(this.label, this.icon, this.page) {
  final String label;
  final IconData icon;
  final Widget page;
}

const _tabs = [
  _TabSpec('Image', Icons.image_rounded, ImageTab()),
  _TabSpec('Batch', Icons.burst_mode_rounded, BatchTab()),
  _TabSpec('Inspect', Icons.info_outline_rounded, InspectTab()),
  _TabSpec('Video', Icons.movie_rounded, VideoTab()),
  _TabSpec('Thumbnails', Icons.view_carousel_rounded, ThumbnailsTab()),
  _TabSpec('Merge', Icons.dashboard_customize_rounded, MergeTab()),
  _TabSpec('Tools', Icons.handyman_rounded, ToolsTab()),
];

class const HomePage({
  super.key,
  required this.themeMode,
  required this.onCycleTheme,
}) extends StatelessWidget {
  final ThemeMode themeMode;
  final VoidCallback onCycleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = AppPalette.of(context);
    final (themeIcon, themeLabel) = switch (themeMode) {
      ThemeMode.system => (Icons.brightness_auto_rounded, 'System'),
      ThemeMode.light => (Icons.light_mode_rounded, 'Light'),
      ThemeMode.dark => (Icons.dark_mode_rounded, 'Dark'),
    };

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        body: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: .topCenter,
                  end: .bottomCenter,
                  colors: palette.headerGradient,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const .fromLTRB(
                        Insets.md,
                        Insets.sm,
                        Insets.sm,
                        0,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: .circular(10),
                              gradient: LinearGradient(
                                colors: [scheme.primary, scheme.tertiary],
                              ),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                              color: scheme.onPrimary,
                            ),
                          ),
                          const SizedBox(width: Insets.sm + 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: .start,
                              children: [
                                Text(
                                  'pixel_compressor',
                                  style: theme.appBarTheme.titleTextStyle,
                                ),
                                Text(
                                  'Image & video compression for Flutter',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Theme: $themeLabel',
                            onPressed: onCycleTheme,
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              transitionBuilder: (child, animation) =>
                                  RotationTransition(
                                    turns: Tween(
                                      begin: 0.75,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ),
                              child: Icon(themeIcon, key: ValueKey(themeIcon)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Insets.sm + 4),
                    TabBar(
                      isScrollable: true,
                      padding: const .symmetric(horizontal: Insets.sm + 4),
                      labelPadding: const .symmetric(horizontal: Insets.md),
                      tabs: [
                        for (final t in _tabs)
                          Tab(
                            height: 40,
                            child: Row(
                              mainAxisSize: .min,
                              children: [
                                Icon(t.icon, size: 18),
                                const SizedBox(width: 6),
                                Text(t.label),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(children: [for (final t in _tabs) t.page]),
            ),
          ],
        ),
      ),
    );
  }
}
