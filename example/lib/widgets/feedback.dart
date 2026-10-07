import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

import '../theme/app_theme.dart';

/// An error message the example raises itself (e.g. a video call that
/// returned null, which is how `PixelVideoCompressor` reports native errors).
class const ExampleError(this.message) {
  final String message;

  @override
  String toString() => message;
}

/// Renders anything a pixel_compressor call can throw, with its type, code
/// (for `PixelCompressError`) and a copy button.
class const ErrorBanner({super.key, required this.error, this.onDismiss})
    extends StatelessWidget {
  final Object error;
  final VoidCallback? onDismiss;

  (String title, String? code, String message) _describe() {
    final e = error;
    return switch (e) {
      PixelCompressError() => ('Compression failed', e.code, e.message),
      ArgumentError() => (
        'Invalid option',
        e.name,
        '${e.message}${e.invalidValue == null ? '' : ' (${e.invalidValue})'}',
      ),
      StateError() => ('Busy', null, e.message.trim()),
      // UnimplementedError extends UnsupportedError, so it goes first.
      UnimplementedError() => (
        'Not available on this platform',
        null,
        e.message ?? '$e',
      ),
      UnsupportedError() => ('Not supported here', null, e.message ?? '$e'),
      PlatformException() => ('Native error', e.code, e.message ?? '$e'),
      ExampleError() => ('Something went wrong', null, e.message),
      _ => ('Something went wrong', null, '$e'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (title, code, message) = _describe();
    return Container(
      padding: const .fromLTRB(Insets.md, Insets.md, Insets.sm, Insets.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(Insets.cardRadius - 4),
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: Insets.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: 4,
                  crossAxisAlignment: .center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    if (code != null)
                      Container(
                        padding: const .symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: .circular(999),
                        ),
                        child: Text(
                          code,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onError,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy error',
            visualDensity: .compact,
            color: scheme.onErrorContainer,
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$error'));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Error copied')));
            },
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: .compact,
              color: scheme.onErrorContainer,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

/// Animated loading placeholder.
class const ShimmerBox({
  super.key,
  this.height = 120,
  this.width,
  this.radius = 16,
}) extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState()
    extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh;
    final highlight = scheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 3 - 1;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: .circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, -0.3),
              end: Alignment(t + 1, 0.3),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

/// Large animated circular progress with the percentage in the middle.
class const ProgressRing({
  super.key,
  required this.progress,
  this.size = 132,
  this.caption,
}) extends StatelessWidget {
  /// 0–1.
  final double progress;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0, 1)),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, value, _) => SizedBox.square(
        dimension: size,
        child: Stack(
          fit: .expand,
          children: [
            CircularProgressIndicator(
              value: value,
              strokeWidth: 10,
              strokeCap: .round,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            Center(
              child: Column(
                mainAxisSize: .min,
                children: [
                  Text(
                    '${(value * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFeatures: tabular,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
