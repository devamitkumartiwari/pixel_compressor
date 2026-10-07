import 'package:flutter/material.dart';

/// Spacing and shape tokens shared by every screen.
abstract final class Insets() {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const double cardRadius = 20;
  static const double controlRadius = 12;

  /// Two-pane layout from this width up.
  static const double wideBreakpoint = 900;
}

/// Extra colours the Material scheme doesn't have: a "savings" accent and the
/// header gradient.
@immutable
class const AppPalette({
  required this.success,
  required this.successContainer,
  required this.onSuccessContainer,
  required this.headerGradient,
}) extends ThemeExtension<AppPalette> {
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final List<Color> headerGradient;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>()!;

  @override
  AppPalette copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    List<Color>? headerGradient,
  }) => AppPalette(
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    headerGradient: headerGradient ?? this.headerGradient,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      success: .lerp(success, other.success, t)!,
      successContainer: .lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: .lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      headerGradient: [
        for (var i = 0; i < headerGradient.length; i++)
          .lerp(headerGradient[i], other.headerGradient[i], t)!,
      ],
    );
  }
}

abstract final class AppTheme() {
  static const _seed = Color(0xFF5B4BDB);

  static ThemeData get light => _build(.light);
  static ThemeData get dark => _build(.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == .dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      tertiary: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
    );
    final palette = AppPalette(
      success: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
      successContainer: isDark
          ? const Color(0xFF134E4A)
          : const Color(0xFFCCFBF1),
      onSuccessContainer: isDark
          ? const Color(0xFFCCFBF1)
          : const Color(0xFF134E4A),
      headerGradient: isDark
          ? [const Color(0xFF1E1B3A), scheme.surface]
          : [const Color(0xFFEDE9FE), scheme.surface],
    );

    final base = ThemeData(colorScheme: scheme, brightness: brightness);
    final text = base.textTheme;
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Insets.controlRadius),
    );

    return base.copyWith(
      extensions: [palette],
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: .w700,
          letterSpacing: -0.6,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: .w700,
          letterSpacing: -0.4,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: .w700,
          letterSpacing: -0.3,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: .w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: .w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: .w800,
          letterSpacing: -0.5,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: .zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Insets.cardRadius),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: .tab,
        indicator: BoxDecoration(
          color: scheme.primary,
          borderRadius: .circular(999),
        ),
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.labelLarge?.copyWith(fontWeight: .w700),
        unselectedLabelStyle: text.labelLarge,
        splashBorderRadius: .circular(999),
        tabAlignment: .start,
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.08),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          shape: RoundedRectangleBorder(borderRadius: .circular(16)),
          textStyle: text.labelLarge?.copyWith(fontWeight: .w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          shape: RoundedRectangleBorder(borderRadius: .circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: controlShape,
          visualDensity: VisualDensity.compact,
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: controlShape,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        overlayShape: .noOverlay,
        showValueIndicator: .never,
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: .resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Icon(Icons.check_rounded)
              : null,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.controlRadius),
          borderSide: .none,
        ),
        contentPadding: const .symmetric(horizontal: Insets.md, vertical: 14),
      ),
      listTileTheme: ListTileThemeData(
        shape: controlShape,
        contentPadding: .zero,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: .floating,
        shape: controlShape,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.surfaceContainerHighest,
        borderRadius: .circular(999),
      ),
    );
  }
}

/// Tabular figures so numbers don't jitter while they change.
const tabular = [FontFeature.tabularFigures()];
